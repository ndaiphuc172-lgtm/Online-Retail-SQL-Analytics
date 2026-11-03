# SQL validation summary

Validation ran on SQL Server 2022, version 16.0.1000.6, compatibility 160, on 2026-10-12. This report summarizes existing execution results; repository cleanup did not rerun SQL. Data is synthetic.

| Validation | Observed result |
|---|---|
| Clean schema + small seed + A–G reports | PASS: 39 DQ checks, 11 row-count baselines, 14 unique KPI reconciliations, seven expected constraint failures |
| Clean schema + large seed + A–G reports | PASS: same check counts; large seed also has built-in load/staging checks |
| Regression fixtures | 22 assertions PASS |
| Actual-module integration | 36 fixture-integrity checks, one later-success retry assertion and 14 unique KPI reconciliations PASS |
| Targeted cohort/customer outputs | Eight assertions PASS: same-month distinct customers, zero/NULL periods, partial-month flags, timestamp ties, zero-price item and no-purchase customer |
| Targeted returns and fulfillment | 13 assertions PASS: split settlement, pending/failed refunds, repeated partial returns and nine actual SLA boundaries; 36 fixture-integrity checks also PASS |
| Safe schema/seed rerun | Six assertions PASS: expected guard errors and unchanged row counts/checksums |

Financial reconciliation uses exact cents rather than a tolerance. Counts are per suite or seed; do not add repeated output rows or overlapping suites into a unique project-wide total.

| Financial baseline | Small seed | Large seed |
|---|---:|---:|
| All orders | 8 | 8,096 |
| Delivered orders | 4 | 7,467 |
| Net revenue, USD | 1,088.99 | 1,847,763.57 |
| Completed merchandise refunds, USD | 186.00 | 71,592.71 |

Use [testing.md](testing.md) for reproducible scripts, [kpi_reconciliation_report.md](kpi_reconciliation_report.md) for financial scope and [test_coverage_audit.md](test_coverage_audit.md) for edge-case coverage.

Full raw outputs and provenance are preserved in a separate local ZIP, not committed to this portfolio. Clean-run logs had input-body hash banners; some auxiliary results were pasted from SSMS and transcribed as structured records. Finite fixture success is not a guarantee for arbitrary future writes, production data or scalability. Source formatting/comment updates were checked for unchanged executable SQL; this report retains the original runtime date.
