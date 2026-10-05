#!/bin/sh
# ---------------------------------------------------------------------------
#  Lab D1.7 | Why we lock - 10 sessions each debit 100.00, 20 times.
#  200 x 100.00 = 20,000.00, so 1,00,000.00 must end at 80,000.00.
#
#      docker exec bank-postgres sh /sql/07_race_demo.sh
#
#  Uses a throw-away demo_wallet table (created and dropped here), so the
#  bank's real accounts and ledger are not touched.
# ---------------------------------------------------------------------------
PSQL="psql -U bank_admin -d bankdb -qAt"

for mode in unsafe safe; do
  $PSQL -c "SET client_min_messages = warning; DROP TABLE IF EXISTS demo_wallet;
            CREATE TABLE demo_wallet (id int PRIMARY KEY, balance numeric(15,2));
            INSERT INTO demo_wallet VALUES (1, 100000.00);"
  pgbench -U bank_admin -d bankdb -n -c 10 -j 4 -t 20 -f /sql/07_race_$mode.pgbench > /dev/null 2>&1
  echo "$mode: expected 80000.00, got $($PSQL -c 'SELECT balance FROM demo_wallet')"
done

$PSQL -c "DROP TABLE demo_wallet;"
