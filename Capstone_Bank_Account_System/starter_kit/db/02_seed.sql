-- =====================================================================
--  Horizon Bank | seed data - 3 customers, 5 accounts, 4 transfers
--  in September 2026, so statements have history to show.
--
--  Final balances:  ...001 = 55,000   ...002 = 28,500   ...003 = 88,000
--                   ...004 = 13,500   ...005 =  5,000 (FROZEN)
--  Total money in the bank = 1,90,000 = sum of the initial deposits.
-- =====================================================================
SET timezone TO 'Asia/Kolkata';

INSERT INTO customer (full_name, email, phone, date_of_birth, pan, created_at) VALUES
  ('Priya Sharma', 'priya.sharma@example.com', '9876500001', '1992-04-18', 'ABCPS1234K', '2026-09-01 10:00'),
  ('Rahul Verma',  'rahul.verma@example.com',  '9876500002', '1988-11-02', 'AKQPV5678L', '2026-09-02 11:00'),
  ('Ananya Iyer',  'ananya.iyer@example.com',  '9876500003', '1999-07-25', 'BXTPI4321M', '2026-09-05 09:15');

INSERT INTO account (account_number, customer_id, account_type, balance, status, opened_at, updated_at)
SELECT v.account_number, c.customer_id, v.account_type, v.balance, v.status,
       v.opened_at::timestamptz, v.updated_at::timestamptz
FROM (VALUES
  ('501000000001', 'ABCPS1234K', 'SAVINGS',  55000.00, 'ACTIVE', '2026-09-01 10:00', '2026-09-28 12:10'),
  ('501000000002', 'AKQPV5678L', 'SAVINGS',  28500.00, 'ACTIVE', '2026-09-02 11:00', '2026-09-20 18:45'),
  ('501000000003', 'AKQPV5678L', 'CURRENT',  88000.00, 'ACTIVE', '2026-09-03 12:30', '2026-09-15 14:00'),
  ('501000000004', 'BXTPI4321M', 'SAVINGS',  13500.00, 'ACTIVE', '2026-09-05 09:15', '2026-09-28 12:10'),
  ('501000000005', 'BXTPI4321M', 'CURRENT',   5000.00, 'FROZEN', '2026-09-05 09:20', '2026-09-25 16:00')
) AS v (account_number, pan, account_type, balance, status, opened_at, updated_at)
JOIN customer c ON c.pan = v.pan
ORDER BY v.account_number;

-- the explicit numbers above did not use the sequence: move it past them
SELECT setval('account_number_seq', 5);

INSERT INTO fund_transfer (reference_no, idempotency_key, from_account_id, to_account_id,
                           amount, remarks, status, created_at)
SELECT v.reference_no, v.idem_key, f.account_id, t.account_id, v.amount, v.remarks,
       'COMPLETED', v.created_at::timestamptz
FROM (VALUES
  ('TRF20260910000001', 'seed-0001', '501000000001', '501000000002',  5000.00, 'Rent share',   '2026-09-10 09:30'),
  ('TRF20260915000002', 'seed-0002', '501000000003', '501000000001', 12000.00, 'Invoice 1043', '2026-09-15 14:00'),
  ('TRF20260920000003', 'seed-0003', '501000000002', '501000000004',  1500.00, 'Dinner',       '2026-09-20 18:45'),
  ('TRF20260928000004', 'seed-0004', '501000000001', '501000000004',  2000.00, 'Birthday gift','2026-09-28 12:10')
) AS v (reference_no, idem_key, from_acc, to_acc, amount, remarks, created_at)
JOIN account f ON f.account_number = v.from_acc
JOIN account t ON t.account_number = v.to_acc;

SELECT setval('transfer_ref_seq', 4);

-- ledger: 5 initial deposits + one DEBIT and one CREDIT per transfer
INSERT INTO account_transaction (account_id, transfer_id, txn_type, amount, balance_after,
                                 description, txn_time)
SELECT a.account_id, ft.transfer_id, v.txn_type, v.amount, v.balance_after, v.description,
       v.txn_time::timestamptz
FROM (VALUES
  ('501000000001', NULL,                'CREDIT',  50000.00,  50000.00, 'Initial deposit',                            '2026-09-01 10:00'),
  ('501000000002', NULL,                'CREDIT',  25000.00,  25000.00, 'Initial deposit',                            '2026-09-02 11:00'),
  ('501000000003', NULL,                'CREDIT', 100000.00, 100000.00, 'Initial deposit',                            '2026-09-03 12:30'),
  ('501000000004', NULL,                'CREDIT',  10000.00,  10000.00, 'Initial deposit',                            '2026-09-05 09:15'),
  ('501000000005', NULL,                'CREDIT',   5000.00,   5000.00, 'Initial deposit',                            '2026-09-05 09:20'),
  ('501000000001', 'TRF20260910000001', 'DEBIT',    5000.00,  45000.00, 'Transfer to 501000000002 - Rent share',      '2026-09-10 09:30'),
  ('501000000002', 'TRF20260910000001', 'CREDIT',   5000.00,  30000.00, 'Transfer from 501000000001 - Rent share',    '2026-09-10 09:30'),
  ('501000000003', 'TRF20260915000002', 'DEBIT',   12000.00,  88000.00, 'Transfer to 501000000001 - Invoice 1043',    '2026-09-15 14:00'),
  ('501000000001', 'TRF20260915000002', 'CREDIT',  12000.00,  57000.00, 'Transfer from 501000000003 - Invoice 1043',  '2026-09-15 14:00'),
  ('501000000002', 'TRF20260920000003', 'DEBIT',    1500.00,  28500.00, 'Transfer to 501000000004 - Dinner',          '2026-09-20 18:45'),
  ('501000000004', 'TRF20260920000003', 'CREDIT',   1500.00,  11500.00, 'Transfer from 501000000002 - Dinner',        '2026-09-20 18:45'),
  ('501000000001', 'TRF20260928000004', 'DEBIT',    2000.00,  55000.00, 'Transfer to 501000000004 - Birthday gift',   '2026-09-28 12:10'),
  ('501000000004', 'TRF20260928000004', 'CREDIT',   2000.00,  13500.00, 'Transfer from 501000000001 - Birthday gift', '2026-09-28 12:10')
) AS v (account_number, reference_no, txn_type, amount, balance_after, description, txn_time)
JOIN account a ON a.account_number = v.account_number
LEFT JOIN fund_transfer ft ON ft.reference_no = v.reference_no
ORDER BY v.txn_time, v.txn_type DESC;   -- DEBIT before CREDIT inside one transfer
