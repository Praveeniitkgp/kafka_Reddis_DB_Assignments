-- =====================================================================
--  Lab D1.5 | Account statement queries
--
--  docker exec -it bank-postgres psql -U bank_app -d bankdb -f /sql/03_statement.sql
--
--  Statement for 501000000001, 1-30 September 2026, page 0, size 3.
--  The date range is half-open: from 00:00 IST on fromDate up to (not
--  including) 00:00 IST on the day AFTER toDate. Your code computes the
--  two instants; here they are written out with the +05:30 offset.
-- =====================================================================
\set ON_ERROR_STOP on
\set acc      '501000000001'
\set from_ts  '2026-09-01 00:00:00+05:30'
\set to_ts    '2026-10-01 00:00:00+05:30'
\set size     3
\set page     0

SELECT account_id AS acc_id FROM account WHERE account_number = :'acc' \gset

-- Q1. one page of transactions, newest first (txn_id breaks ties)
SELECT t.txn_id,
       to_char(t.txn_time, 'YYYY-MM-DD HH24:MI') AS txn_time,
       t.txn_type, t.amount, t.balance_after, t.description,
       ft.reference_no
FROM account_transaction t
LEFT JOIN fund_transfer ft ON ft.transfer_id = t.transfer_id
WHERE t.account_id = :acc_id
  AND t.txn_time >= :'from_ts' AND t.txn_time < :'to_ts'
ORDER BY t.txn_time DESC, t.txn_id DESC
LIMIT :size OFFSET (:page * :size);

-- Q2. paging metadata and period totals in one pass
SELECT count(*)                                                       AS total_elements,
       ceil(count(*)::numeric / :size)                                AS total_pages,
       COALESCE(SUM(amount) FILTER (WHERE txn_type = 'CREDIT'), 0)    AS total_credits,
       COALESCE(SUM(amount) FILTER (WHERE txn_type = 'DEBIT'),  0)    AS total_debits
FROM account_transaction
WHERE account_id = :acc_id
  AND txn_time >= :'from_ts' AND txn_time < :'to_ts';

-- Q3. opening balance = balance after the last entry BEFORE the period (0 if none)
--     closing balance = balance after the last entry INSIDE or before the period
SELECT COALESCE((SELECT balance_after FROM account_transaction
                 WHERE account_id = :acc_id AND txn_time < :'from_ts'
                 ORDER BY txn_time DESC, txn_id DESC LIMIT 1), 0.00)  AS opening_balance,
       COALESCE((SELECT balance_after FROM account_transaction
                 WHERE account_id = :acc_id AND txn_time < :'to_ts'
                 ORDER BY txn_time DESC, txn_id DESC LIMIT 1), 0.00)  AS closing_balance;

-- Q4. proof that the statement query uses the index, not a full scan
SET enable_seqscan = off;   -- tiny table: force the planner to show the index path
EXPLAIN (COSTS OFF)
SELECT txn_id FROM account_transaction
WHERE account_id = :acc_id AND txn_time >= :'from_ts' AND txn_time < :'to_ts'
ORDER BY txn_time DESC, txn_id DESC LIMIT 3;
