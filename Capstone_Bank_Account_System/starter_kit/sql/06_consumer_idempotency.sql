-- =====================================================================
--  Lab D3.4 | Idempotent consumer - what notification-service writes
--  for ONE TransferCompleted event: a debit alert and a credit alert.
--
--  docker exec -it bank-postgres psql -U bank_app -d bankdb -f /sql/06_consumer_idempotency.sql
--
--  Kafka delivers at-least-once: after a crash or rebalance the same
--  event can arrive again. The run below inserts the same event twice;
--  the second insert writes nothing, so nobody gets a second SMS.
-- =====================================================================
\set event_id '0b6f7a52-3c1e-4d0a-9a51-2f8e6c1d9b47'

-- first delivery
INSERT INTO notification_log (event_id, account_number, event_type, message)
VALUES (:'event_id', '501000000001', 'TransferCompleted',
        'Rs 2500.00 debited from A/c XX0001 to A/c XX0002. Ref TRF20261001000005. Avl bal Rs 52500.00'),
       (:'event_id', '501000000002', 'TransferCompleted',
        'Rs 2500.00 credited to A/c XX0002 from A/c XX0001. Ref TRF20261001000005. Avl bal Rs 31000.00')
ON CONFLICT (event_id, account_number) DO NOTHING;

-- re-delivery of the very same event
INSERT INTO notification_log (event_id, account_number, event_type, message)
VALUES (:'event_id', '501000000001', 'TransferCompleted', 'duplicate'),
       (:'event_id', '501000000002', 'TransferCompleted', 'duplicate')
ON CONFLICT (event_id, account_number) DO NOTHING;

SELECT account_number, left(message, 48) AS message FROM notification_log
WHERE event_id = :'event_id' ORDER BY account_number;
