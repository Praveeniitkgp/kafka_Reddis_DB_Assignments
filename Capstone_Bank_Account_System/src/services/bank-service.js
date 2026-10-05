const accountProjection = `
  SELECT a.account_id, a.account_number, a.account_type, a.currency, a.balance,
         a.status, a.opened_at, a.updated_at, c.customer_id, c.full_name,
         c.email, c.phone, c.date_of_birth, c.pan
  FROM account a JOIN customer c ON c.customer_id = a.customer_id
`;

const accountView = (row) => ({
  accountNumber: row.account_number,
  accountType: row.account_type,
  currency: row.currency,
  balance: Number(row.balance),
  status: row.status,
  openedAt: row.opened_at,
  customer: { id: row.customer_id, fullName: row.full_name, email: row.email, phone: row.phone, dateOfBirth: row.date_of_birth, pan: row.pan }
});

export function createBankService(pool, cache, events, dailyLimit) {
  return {
    async openAccount(input) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const customer = await client.query(
          `INSERT INTO customer (full_name, email, phone, date_of_birth, pan) VALUES ($1, $2, $3, $4, $5) RETURNING customer_id`,
          [input.fullName, input.email, input.phone, input.dateOfBirth, input.pan]
        );
        const account = await client.query(
          `INSERT INTO account (customer_id, account_type, balance) VALUES ($1, $2, $3) RETURNING account_id, account_number`,
          [customer.rows[0].customer_id, input.accountType, input.initialDeposit]
        );
        await client.query(
          `INSERT INTO account_transaction (account_id, txn_type, amount, balance_after, description) VALUES ($1, 'CREDIT', $2, $2, 'Initial deposit')`,
          [account.rows[0].account_id, input.initialDeposit]
        );
        await client.query('COMMIT');
        const created = await pool.query(`${accountProjection} WHERE a.account_id = $1`, [account.rows[0].account_id]);
        await events.publish('bank.account.opened.v1', account.rows[0].account_number, { eventType: 'ACCOUNT_OPENED', accountNumber: account.rows[0].account_number, occurredAt: new Date().toISOString() });
        return accountView(created.rows[0]);
      } catch (error) { await client.query('ROLLBACK'); throw error; }
      finally { client.release(); }
    },

    async transfer(input) {
      const idempotencyCacheKey = `idempotency:transfer:${input.idempotencyKey}`;
      const cachedTransfer = await cache.get(idempotencyCacheKey);
      if (cachedTransfer) return { ...JSON.parse(cachedTransfer), replayed: true };
      const existing = await pool.query('SELECT transfer_id, reference_no, amount, status FROM fund_transfer WHERE idempotency_key = $1', [input.idempotencyKey]);
      if (existing.rowCount) {
        await cache.set(idempotencyCacheKey, JSON.stringify(existing.rows[0]), 86400);
        return { ...existing.rows[0], replayed: true };
      }
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const locked = await client.query(
          `${accountProjection} WHERE a.account_number = ANY($1::varchar[]) ORDER BY a.account_id FOR UPDATE`,
          [[input.fromAccountNumber, input.toAccountNumber]]
        );
        const from = locked.rows.find((row) => row.account_number === input.fromAccountNumber);
        const to = locked.rows.find((row) => row.account_number === input.toAccountNumber);
        if (!from || !to) throw Object.assign(new Error('Account not found'), { status: 404 });
        if (from.status !== 'ACTIVE' || to.status !== 'ACTIVE') throw Object.assign(new Error('Both accounts must be ACTIVE'), { status: 409 });
        if (Number(from.balance) < input.amount) throw Object.assign(new Error('Insufficient funds'), { status: 409 });
        const sent = await client.query(`SELECT COALESCE(SUM(amount), 0) AS sent_today FROM fund_transfer WHERE from_account_id = $1 AND status = 'COMPLETED' AND created_at >= date_trunc('day', now())`, [from.account_id]);
        if (Number(sent.rows[0].sent_today) + input.amount > dailyLimit) throw Object.assign(new Error('Daily transfer limit exceeded'), { status: 409 });
        const transfer = await client.query(
          `INSERT INTO fund_transfer (idempotency_key, from_account_id, to_account_id, amount, remarks) VALUES ($1, $2, $3, $4, $5) RETURNING transfer_id, reference_no, amount, status, created_at`,
          [input.idempotencyKey, from.account_id, to.account_id, input.amount, input.remarks || null]
        );
        const transferRow = transfer.rows[0];
        const balances = await client.query(
          `UPDATE account SET balance = CASE WHEN account_id = $1 THEN balance - $3 ELSE balance + $3 END, updated_at = now() WHERE account_id IN ($1, $2) RETURNING account_id, account_number, balance`,
          [from.account_id, to.account_id, input.amount]
        );
        const fromBalance = balances.rows.find((row) => row.account_id === from.account_id).balance;
        const toBalance = balances.rows.find((row) => row.account_id === to.account_id).balance;
        await client.query(
          `INSERT INTO account_transaction (account_id, transfer_id, txn_type, amount, balance_after, description) VALUES ($1, $2, 'DEBIT', $3, $4, $5), ($6, $2, 'CREDIT', $3, $7, $8)`,
          [from.account_id, transferRow.transfer_id, input.amount, fromBalance, `Transfer to ${to.account_number}${input.remarks ? ` - ${input.remarks}` : ''}`, to.account_id, toBalance, `Transfer from ${from.account_number}${input.remarks ? ` - ${input.remarks}` : ''}`]
        );
        await client.query('COMMIT');
        await Promise.all([
          cache.delPrefix(`statement:${from.account_number}:`),
          cache.delPrefix(`statement:${to.account_number}:`),
          cache.set(idempotencyCacheKey, JSON.stringify(transferRow), 86400)
        ]);
        await events.publish('bank.transfer.completed.v1', from.account_number, { eventType: 'TRANSFER_COMPLETED', transferId: transferRow.transfer_id, referenceNo: transferRow.reference_no, fromAccountNumber: from.account_number, toAccountNumber: to.account_number, amount: input.amount, occurredAt: transferRow.created_at });
        return { ...transferRow, replayed: false };
      } catch (error) {
        await client.query('ROLLBACK');
        if (error.code === '23505' && error.constraint === 'uq_transfer_idempotency') {
          const replay = await pool.query('SELECT transfer_id, reference_no, amount, status FROM fund_transfer WHERE idempotency_key = $1', [input.idempotencyKey]);
          await cache.set(idempotencyCacheKey, JSON.stringify(replay.rows[0]), 86400);
          return { ...replay.rows[0], replayed: true };
        }
        throw error;
      } finally { client.release(); }
    },

    async statement(accountNumber, fromDate, toDate, page, size) {
      const cacheKey = `statement:${accountNumber}:${fromDate}:${toDate}:${page}:${size}`;
      const cached = await cache.get(cacheKey);
      if (cached) return JSON.parse(cached);
      const account = await pool.query('SELECT account_id FROM account WHERE account_number = $1', [accountNumber]);
      if (!account.rowCount) throw Object.assign(new Error('Account not found'), { status: 404 });
      const from = `${fromDate}T00:00:00+05:30`;
      const rows = await pool.query(
        `SELECT t.txn_id, t.txn_time, t.txn_type, t.amount, t.balance_after, t.description, ft.reference_no FROM account_transaction t LEFT JOIN fund_transfer ft ON ft.transfer_id = t.transfer_id WHERE t.account_id = $1 AND t.txn_time >= $2::timestamptz AND t.txn_time < ($3::date + INTERVAL '1 day') ORDER BY t.txn_time DESC, t.txn_id DESC LIMIT $4 OFFSET $5`,
        [account.rows[0].account_id, from, toDate, size, page * size]
      );
      const totals = await pool.query(
        `SELECT count(*) AS total_elements, COALESCE(SUM(amount) FILTER (WHERE txn_type = 'CREDIT'), 0) AS total_credits, COALESCE(SUM(amount) FILTER (WHERE txn_type = 'DEBIT'), 0) AS total_debits FROM account_transaction WHERE account_id = $1 AND txn_time >= $2::timestamptz AND txn_time < ($3::date + INTERVAL '1 day')`,
        [account.rows[0].account_id, from, toDate]
      );
      const balances = await pool.query(
        `SELECT COALESCE((SELECT balance_after FROM account_transaction WHERE account_id = $1 AND txn_time < $2::timestamptz ORDER BY txn_time DESC, txn_id DESC LIMIT 1), 0) AS opening_balance, COALESCE((SELECT balance_after FROM account_transaction WHERE account_id = $1 AND txn_time < ($3::date + INTERVAL '1 day') ORDER BY txn_time DESC, txn_id DESC LIMIT 1), 0) AS closing_balance`,
        [account.rows[0].account_id, from, toDate]
      );
      const totalElements = Number(totals.rows[0].total_elements);
      const response = { accountNumber, fromDate, toDate, page, size, totalElements, totalPages: Math.ceil(totalElements / size), totalCredits: Number(totals.rows[0].total_credits), totalDebits: Number(totals.rows[0].total_debits), openingBalance: Number(balances.rows[0].opening_balance), closingBalance: Number(balances.rows[0].closing_balance), transactions: rows.rows.map((row) => ({ ...row, amount: Number(row.amount), balanceAfter: Number(row.balance_after) })) };
      await cache.set(cacheKey, JSON.stringify(response), 30);
      return response;
    }
  };
}