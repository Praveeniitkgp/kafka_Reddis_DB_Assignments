-- =====================================================================
--  Horizon Bank | Bank Account System capstone | PostgreSQL 16 schema
--
--  Runs automatically on the FIRST start of the bank-postgres container
--  (every file in /docker-entrypoint-initdb.d runs in name order).
--  To run it again:  docker compose down -v  then  docker compose up -d
-- =====================================================================

-- Business dates are Indian dates: psql sessions show IST by default.
-- (Values are still stored as absolute instants in TIMESTAMPTZ.)
ALTER DATABASE bankdb SET timezone TO 'Asia/Kolkata';
SET timezone TO 'Asia/Kolkata';

-- ---------------------------------------------------------------------
-- Sequences behind the human-readable business numbers
-- ---------------------------------------------------------------------
CREATE SEQUENCE account_number_seq START 1;   -- 501000000001, 501000000002 ...
CREATE SEQUENCE transfer_ref_seq   START 1;   -- TRF20261005000001 ...

-- ---------------------------------------------------------------------
-- customer : one row per KYC-verified person, identified by PAN
-- ---------------------------------------------------------------------
CREATE TABLE customer (
    customer_id     BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name       VARCHAR(100)  NOT NULL,
    email           VARCHAR(150)  NOT NULL,
    phone           VARCHAR(10)   NOT NULL,
    date_of_birth   DATE          NOT NULL,
    pan             CHAR(10)      NOT NULL,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_customer_pan    UNIQUE (pan),
    CONSTRAINT uq_customer_email  UNIQUE (email),
    CONSTRAINT uq_customer_phone  UNIQUE (phone),
    CONSTRAINT ck_customer_pan    CHECK (pan ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'),
    CONSTRAINT ck_customer_phone  CHECK (phone ~ '^[6-9][0-9]{9}$'),
    CONSTRAINT ck_customer_email  CHECK (email = lower(email))   -- app stores lower case
);

-- ---------------------------------------------------------------------
-- account : one row per bank account; balance is the current balance
-- ---------------------------------------------------------------------
CREATE TABLE account (
    account_id      BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_number  VARCHAR(12)   NOT NULL
                    DEFAULT ('5010' || lpad(nextval('account_number_seq')::text, 8, '0')),
    customer_id     BIGINT        NOT NULL REFERENCES customer (customer_id),
    account_type    VARCHAR(10)   NOT NULL,
    currency        CHAR(3)       NOT NULL DEFAULT 'INR',
    balance         NUMERIC(15,2) NOT NULL DEFAULT 0,
    status          VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE',
    version         INTEGER       NOT NULL DEFAULT 0,       -- for optimistic locking (stretch)
    opened_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_account_number         UNIQUE (account_number),
    CONSTRAINT uq_account_customer_type  UNIQUE (customer_id, account_type),  -- 1 SAVINGS + 1 CURRENT max
    CONSTRAINT ck_account_type      CHECK (account_type IN ('SAVINGS', 'CURRENT')),
    CONSTRAINT ck_account_currency  CHECK (currency = 'INR'),
    CONSTRAINT ck_account_status    CHECK (status IN ('ACTIVE', 'FROZEN', 'CLOSED')),
    CONSTRAINT ck_account_balance   CHECK (balance >= 0)                     -- last line of defence
);

-- ---------------------------------------------------------------------
-- fund_transfer : one row per transfer request (the business event)
-- ---------------------------------------------------------------------
CREATE TABLE fund_transfer (
    transfer_id      UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    reference_no     VARCHAR(20)   NOT NULL
                     DEFAULT ('TRF' || to_char(now(), 'YYYYMMDD')
                              || lpad(nextval('transfer_ref_seq')::text, 6, '0')),
    idempotency_key  VARCHAR(64)   NOT NULL,
    from_account_id  BIGINT        NOT NULL REFERENCES account (account_id),
    to_account_id    BIGINT        NOT NULL REFERENCES account (account_id),
    amount           NUMERIC(15,2) NOT NULL,
    remarks          VARCHAR(100),
    status           VARCHAR(10)   NOT NULL DEFAULT 'COMPLETED',
    failure_reason   VARCHAR(40),
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_transfer_reference    UNIQUE (reference_no),
    CONSTRAINT uq_transfer_idempotency  UNIQUE (idempotency_key),   -- backstop if Redis loses the key
    CONSTRAINT ck_transfer_accounts  CHECK (from_account_id <> to_account_id),
    CONSTRAINT ck_transfer_amount    CHECK (amount > 0),
    CONSTRAINT ck_transfer_status    CHECK (status IN ('COMPLETED', 'FAILED')),
    CONSTRAINT ck_transfer_failure   CHECK ((status = 'FAILED') = (failure_reason IS NOT NULL))
);

-- daily-limit query: today's completed transfers out of one account
CREATE INDEX ix_transfer_from_created ON fund_transfer (from_account_id, created_at);

-- ---------------------------------------------------------------------
-- account_transaction : the ledger. Append-only; one row per balance
-- movement. Every transfer writes exactly one DEBIT and one CREDIT.
-- ---------------------------------------------------------------------
CREATE TABLE account_transaction (
    txn_id          BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id      BIGINT        NOT NULL REFERENCES account (account_id),
    transfer_id     UUID          REFERENCES fund_transfer (transfer_id),  -- NULL = initial deposit
    txn_type        VARCHAR(6)    NOT NULL,
    amount          NUMERIC(15,2) NOT NULL,
    balance_after   NUMERIC(15,2) NOT NULL,
    description     VARCHAR(140)  NOT NULL,
    txn_time        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT ck_txn_type      CHECK (txn_type IN ('CREDIT', 'DEBIT')),
    CONSTRAINT ck_txn_amount    CHECK (amount > 0),
    CONSTRAINT ck_txn_balance   CHECK (balance_after >= 0),
    CONSTRAINT uq_txn_transfer_leg UNIQUE (transfer_id, txn_type)          -- one DEBIT + one CREDIT
);

-- the statement query: one account, a date range, newest first
CREATE INDEX ix_txn_account_time ON account_transaction (account_id, txn_time DESC, txn_id DESC);

-- ---------------------------------------------------------------------
-- notification_log : written by the Kafka consumer (notification-service).
-- The primary key makes the consumer idempotent: a re-delivered event
-- hits ON CONFLICT DO NOTHING instead of sending a second SMS.
-- ---------------------------------------------------------------------
CREATE TABLE notification_log (
    event_id        UUID          NOT NULL,
    account_number  VARCHAR(12)   NOT NULL,
    event_type      VARCHAR(40)   NOT NULL,
    channel         VARCHAR(10)   NOT NULL DEFAULT 'SMS',
    message         VARCHAR(300)  NOT NULL,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT pk_notification_log PRIMARY KEY (event_id, account_number)
);

-- ---------------------------------------------------------------------
-- bank_app : the login your application uses. Least privilege:
-- no DDL, no DELETE anywhere, and the ledger cannot even be UPDATEd.
-- ---------------------------------------------------------------------
CREATE ROLE bank_app LOGIN PASSWORD 'bank_app_pwd';                   -- lab-only password
GRANT CONNECT ON DATABASE bankdb TO bank_app;
GRANT USAGE ON SCHEMA public TO bank_app;
GRANT SELECT, INSERT, UPDATE ON customer, account, fund_transfer TO bank_app;
GRANT SELECT, INSERT         ON account_transaction, notification_log TO bank_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO bank_app;
