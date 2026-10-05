-- =====================================================================
--  Lab D1.6 | Reconciliation - checks that must ALWAYS hold.
--  Run them after every test session; R1-R3 must return zero rows.
--
--  docker exec -it bank-postgres psql -U bank_app -d bankdb -f /sql/04_reconciliation.sql
-- =====================================================================

-- R1. account.balance = credits - debits in the ledger = last balance_after
SELECT a.account_number, a.balance,
       SUM(CASE t.txn_type WHEN 'CREDIT' THEN t.amount ELSE -t.amount END) AS ledger_sum,
       (ARRAY_AGG(t.balance_after ORDER BY t.txn_time DESC, t.txn_id DESC))[1] AS last_balance_after
FROM account a
JOIN account_transaction t USING (account_id)
GROUP BY a.account_id, a.account_number, a.balance
HAVING a.balance <> SUM(CASE t.txn_type WHEN 'CREDIT' THEN t.amount ELSE -t.amount END)
    OR a.balance <> (ARRAY_AGG(t.balance_after ORDER BY t.txn_time DESC, t.txn_id DESC))[1];

-- R2. every COMPLETED transfer has exactly one DEBIT on the sender and
--     one CREDIT on the receiver, both for the transfer amount
SELECT ft.reference_no
FROM fund_transfer ft
LEFT JOIN account_transaction d ON d.transfer_id = ft.transfer_id AND d.txn_type = 'DEBIT'
LEFT JOIN account_transaction c ON c.transfer_id = ft.transfer_id AND c.txn_type = 'CREDIT'
WHERE ft.status = 'COMPLETED'
  AND (d.account_id IS DISTINCT FROM ft.from_account_id OR d.amount IS DISTINCT FROM ft.amount
    OR c.account_id IS DISTINCT FROM ft.to_account_id   OR c.amount IS DISTINCT FROM ft.amount);

-- R3. transfers move money, they never create it:
--     total balances must equal total initial deposits
SELECT total_balances, total_deposits
FROM (SELECT SUM(balance) AS total_balances FROM account) b,
     (SELECT SUM(amount)  AS total_deposits FROM account_transaction WHERE transfer_id IS NULL) d
WHERE total_balances <> total_deposits;

-- R4. summary for the test report
SELECT (SELECT count(*) FROM account)                                    AS accounts,
       (SELECT count(*) FROM fund_transfer WHERE status = 'COMPLETED')    AS transfers,
       (SELECT count(*) FROM account_transaction)                         AS ledger_rows,
       (SELECT SUM(balance) FROM account)                                 AS money_in_bank;
