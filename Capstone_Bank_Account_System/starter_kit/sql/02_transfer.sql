-- =====================================================================
--  Lab D1.3 | One fund transfer, step by step - the SQL your API runs
--
--  docker exec -it bank-postgres psql -U bank_app -d bankdb -f /sql/02_transfer.sql
--
--  Transfer 2,500.00 from 501000000001 (Priya) to 501000000002 (Rahul).
--  The app does the checks in step 2 in code; here you read the rows.
-- =====================================================================
\set ON_ERROR_STOP on
\set from_acc '501000000001'
\set to_acc   '501000000002'
\set amount   2500.00
\set idem_key 'lab-d1-3-0001'

BEGIN;

-- 1. Lock BOTH rows, always in account_id order. Two transfers that
--    touch the same pair of accounts then queue up instead of deadlocking.
SELECT account_id, account_number, balance, status
FROM account
WHERE account_number IN (:'from_acc', :'to_acc')
ORDER BY account_id
FOR UPDATE;

-- 2. Checks (in code): both rows found, both ACTIVE, balance >= amount,
--    and today's total + amount within the daily limit (5,00,000.00):
SELECT COALESCE(SUM(amount), 0.00) AS sent_today
FROM fund_transfer
WHERE from_account_id = (SELECT account_id FROM account WHERE account_number = :'from_acc')
  AND status = 'COMPLETED'
  AND created_at >= date_trunc('day', now());

SELECT account_id AS from_id FROM account WHERE account_number = :'from_acc' \gset
SELECT account_id AS to_id   FROM account WHERE account_number = :'to_acc'   \gset

-- 3. The transfer row (reference_no comes from its DEFAULT)
INSERT INTO fund_transfer (idempotency_key, from_account_id, to_account_id, amount, remarks)
VALUES (:'idem_key', :from_id, :to_id, :amount, 'Rent October')
RETURNING transfer_id, reference_no \gset

-- 4. Move the money. The database does the arithmetic, exactly.
UPDATE account SET balance = balance - :amount, updated_at = now()
WHERE account_id = :from_id
RETURNING balance AS from_balance \gset

UPDATE account SET balance = balance + :amount, updated_at = now()
WHERE account_id = :to_id
RETURNING balance AS to_balance \gset

-- 5. Two ledger entries: the DEBIT and the CREDIT
INSERT INTO account_transaction (account_id, transfer_id, txn_type, amount, balance_after, description)
VALUES (:from_id, :'transfer_id', 'DEBIT',  :amount, :from_balance, 'Transfer to '   || :'to_acc'   || ' - Rent October'),
       (:to_id,   :'transfer_id', 'CREDIT', :amount, :to_balance,   'Transfer from ' || :'from_acc' || ' - Rent October');

COMMIT;
-- 6. AFTER the commit, the app evicts the cache and publishes the Kafka event.

SELECT reference_no, amount, status FROM fund_transfer WHERE transfer_id = :'transfer_id';
SELECT account_number, balance FROM account WHERE account_id IN (:from_id, :to_id) ORDER BY account_id;
