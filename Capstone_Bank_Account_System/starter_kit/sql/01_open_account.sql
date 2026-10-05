-- =====================================================================
--  Lab D1.2 | Open an account by hand - the SQL your API will run
--
--  docker exec -it bank-postgres psql -U bank_app -d bankdb -f /sql/01_open_account.sql
--
--  \gset stores the columns of a RETURNING row in psql variables
--  (:customer_id, :account_id ...), the way your code keeps the values
--  that INSERT ... RETURNING hands back.
-- =====================================================================
\set ON_ERROR_STOP on
\set amount 15000.00

BEGIN;

-- 1. new customer (PAN not seen before)
INSERT INTO customer (full_name, email, phone, date_of_birth, pan)
VALUES ('Karthik Rao', 'karthik.rao@example.com', '9876500004', '1995-02-14', 'CKRPR7788Q')
RETURNING customer_id \gset

-- 2. the account: number, currency, status, timestamps come from DEFAULTs
INSERT INTO account (customer_id, account_type, balance)
VALUES (:customer_id, 'SAVINGS', :amount)
RETURNING account_id, account_number \gset

-- 3. the initial deposit is the first ledger entry
INSERT INTO account_transaction (account_id, txn_type, amount, balance_after, description)
VALUES (:account_id, 'CREDIT', :amount, :amount, 'Initial deposit');

COMMIT;

SELECT a.account_number, c.full_name, a.account_type, a.balance, a.status
FROM account a JOIN customer c USING (customer_id)
WHERE a.account_id = :account_id;
