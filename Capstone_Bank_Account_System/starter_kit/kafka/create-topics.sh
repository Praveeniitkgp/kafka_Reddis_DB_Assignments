#!/bin/sh
# ---------------------------------------------------------------------------
#  Create the capstone's Kafka topics (safe to run again).
#
#      docker exec bank-kafka sh /scripts/create-topics.sh
#
#  3 partitions each: events with the same key (an account number) always
#  land in the same partition, so they stay in order. Replication factor 1
#  because the lab has a single broker - production would use 3.
# ---------------------------------------------------------------------------
set -e
BOOTSTRAP=localhost:9092

for topic in bank.account.opened.v1 bank.transfer.completed.v1 bank.transfer.failed.v1; do
  kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --create --if-not-exists \
    --topic "$topic" --partitions 3 --replication-factor 1 \
    --config retention.ms=604800000          # keep events for 7 days
done

kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --list
