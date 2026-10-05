# Capstone Project: Bank Account System

A beginner capstone in which participants build account opening, money transfer and account statement
APIs for the fictional Horizon Bank. The application layer is implemented in Node.js; the data layer
is fixed: **PostgreSQL** (system of record), **Redis** (cache) and **Kafka** (events). There is no UI;
Postman or curl drives the APIs.

| Path | What it is |
|---|---|
| `Bank_Account_System_Capstone_Case_Study.pdf` | **The deliverable**: training case study + project specification (80 pages) |
| `case_study/*.md` | Source chapters: 00 About … 12 Trainer Guide, A Reference Code, B Glossary |
| `starter_kit/` | What participants get: `docker-compose.yml`, `db/` schema + seed, `sql/` labs, `kafka/` topic script |
| `diagrams/*.svg` | Architecture, ERD, transfer sequence, cache read path, Kafka flow (inlined into the PDF) |
| `_capture/` | Real outputs shown in the book + `capture_all.sh`, which regenerates them |
| `build_pdf.py` | Markdown → HTML → PDF (headless Chrome/Edge), "Ledger Teal & Brass" theme |

## Rebuild

```bash
python build_pdf.py                 # needs: pip install markdown ; Chrome or Edge
```

## Run the Node.js API

```bash
cd starter_kit
docker compose up -d
docker exec bank-kafka sh /scripts/create-topics.sh
cd ..
npm install
npm start
```

The API listens on `http://localhost:3000` and exposes `POST /api/accounts`,
`POST /api/transfers`, and `GET /api/accounts/:accountNumber/statement`.
PostgreSQL is published on host port `15432` to avoid conflicts with an existing local PostgreSQL service.
Copy `.env.example` to `.env` when changing the default local connection settings.

## Re-capture the outputs (after changing the schema, seed or lab scripts)

```bash
bash _capture/capture_all.sh        # Git Bash; WARNING: runs "docker compose down -v" on the starter kit
python build_pdf.py
```

The book pulls the starter-kit files and the captured outputs in by reference (`<!-- include: -->`,
`<!-- output: -->`), so the listings and outputs in the PDF always match the kit.

## Verified

Tested on 01-Oct-2026 with Docker 29, `postgres:16-alpine`, `redis:7-alpine`, `apache/kafka:4.3.1`:
schema + seed load, every SQL lab, the constraint "says no" script, the pgbench race demo (unsafe run
loses debits, `FOR UPDATE` run is exact), reconciliation, Redis cache/idempotency commands, and topic
creation / keyed produce / group consume / offset reset. The application code is the participants'
job; Appendix A has reference sketches whose SQL was run against the kit database.
