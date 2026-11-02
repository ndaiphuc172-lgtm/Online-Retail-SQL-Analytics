# OnlineRetailDB — SQL Server Retail Analytics

A reproducible SQL portfolio for revenue, payments, product performance, customers, returns, delivery and retention. All customer/order data is synthetic. Results illustrate the simulated dataset, not a real retailer.

| Analysis | Business question |
|---|---|
| A — Revenue/profit | How do monthly recognized revenue and estimated profit change? |
| B — Orders/payments | Where do orders cancel or payment attempts fail, and do retries recover? |
| C — Products/categories | Which products contribute sales, estimated profit and returns? |
| D — Customers | Who purchases, repeats and contributes observed revenue? |
| E — Returns/refunds | What is received, approved, pending or settled, and how long does settlement take? |
| F — Fulfillment | Are orders shipped/delivered within demo SLA thresholds? |
| G — Cohorts | How do retention and refund-adjusted revenue vary with acquisition cohort? |

## Validated dataset results

| Metric | Small seed | Large seed |
|---|---:|---:|
| Orders | 8 | 8,096 |
| Delivered orders | 4 | 7,467 |
| Net revenue, USD | 1,088.99 | 1,847,763.57 |
| Completed merchandise refund, USD | 186.00 | 71,592.71 |

Recognized purchases use Delivered orders. Revenue includes shipping once and excludes tax; completed merchandise refunds are allocated and rounded per original order item. Read [the KPI contract](docs/kpi_contract.md) before interpreting outputs.

## Run from a new database

Validated on SQL Server 2022 (16.0.1000.6), compatibility 160. Use SSMS.

1. Run `sql/OnlineRetail Create tb.sql` only when `OnlineRetailDB` does not exist. Setup refuses an existing database.
2. Run exactly one seed: `OnlineRetailDB - clone data.sql` (small) or `OnlineRetail Insert Data.sql` (large). Seeds refuse nonempty tables.
3. In `tests/data_quality_checks.sql`, select `@SeedProfile='small'` or `'large'` for that seed, then run the whole file.
4. Run `OnlineRetailDB Querry.sql` (A/B/C), then customer (D), return_refund (E), fulfillment_delivery (F) and cohort retention (G) SQL files.
5. G defaults to exclusive UTC cutoff `2026-09-01T00:00:00` for small. For large select `2026-10-01T00:00:00`. Set the same cutoff wherever declared in `tests/kpi_reconciliation.sql`, then execute reconciliation.

Do not run both seeds or remove existing data to rerun setup. Files containing `:ON ERROR EXIT` require **Query > SQLCMD Mode** in that SSMS window. Run entire files, one connection per file.

For separate disposable reproduction, `tools/clean_reproduction` contains the exact final small/large drivers used in clean tests, with fixed isolated database names and input-hash banners. They deliberately stop if the named database already exists.

## Validation

Each clean seed passed 39 DQ checks, 11 baselines, 14 unique exact-cent KPI reconciliations and seven negative constraint tests. Further evidence covers 22 regression assertions, actual A–G fixtures, eight targeted cohort/customer and 13 refund/SLA assertions, safe rerun and six rollback-only legacy-view checks. See [completion evidence](docs/completion_gate.md), [test instructions](docs/testing.md) and [raw/structured evidence](evidence/README.md).

## Repository contents

- `sql/`: eight final schema, seed and reporting scripts.
- `tests/`: final preflight, integrity, reconciliation, regression and fixture scripts.
- `docs/`: KPI definitions, dependencies, findings, performance and coverage.
- `evidence/`: final successful outputs, source hashes and original-to-fixed diff.
- `legacy_views/`: tested legacy-view fixes; not part of the clean schema workflow.
- `tools/`: final fixture and clean-reproduction drivers only.

Legacy fixes were tested inside a transaction and rolled back. They have **not** been deployed to the original database. Legacy totals intentionally preserve all-status historical gross merchandise, distinct from A–G recognized net revenue. SLA thresholds are demo assumptions. Performance measurements have no before/after index claim; no production scalability or actual execution-plan evidence is implied.
