-- =====================================================================
--  Lab D1.4 | The database says NO - each statement below breaks a
--  business rule and must fail. Bugs in the app cannot corrupt the data.
--
--  docker exec -it bank-postgres psql -U bank_app -d bankdb -f /sql/05_constraints_say_no.sql
-- =====================================================================

-- 1. overdraw an account (ck_account_balance)
UPDATE account SET balance = balance - 100000.00 WHERE account_number = '501000000004';

-- 2. a second SAVINGS account for Priya (uq_account_customer_type)
INSERT INTO account (customer_id, account_type, balance)
SELECT customer_id, 'SAVINGS', 1000.00 FROM customer WHERE pan = 'ABCPS1234K';

-- 3. transfer to the same account (ck_transfer_accounts)
INSERT INTO fund_transfer (idempotency_key, from_account_id, to_account_id, amount)
VALUES ('lab-d1-4-0003', 1, 1, 100.00);

-- 4. replay an idempotency key that was already used (uq_transfer_idempotency)
INSERT INTO fund_transfer (idempotency_key, from_account_id, to_account_id, amount)
VALUES ('seed-0001', 1, 2, 5000.00);

-- 5. a PAN in the wrong format (ck_customer_pan)
INSERT INTO customer (full_name, email, phone, date_of_birth, pan)
VALUES ('Test User', 'test.user@example.com', '9876500099', '1990-01-01', 'ABC123');

-- 6. rewrite history in the ledger (no UPDATE/DELETE privilege for bank_app)
DELETE FROM account_transaction WHERE txn_id = 1;
