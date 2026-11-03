# KPI reconciliation report
PHUCCOMPUTER; SQL Server 2022 version 16.0.1000.6; compatibility 160. New clean reproduction supplied 12/10/2026 with matching driver-body hash banners.

| Measure | Small | Large |
|---|---:|---:|
| Orders | 8 | 8,096 |
| Delivered | 4 | 7,467 |
| Net revenue USD | 1,088.99 | 1,847,763.57 |
| Merchandise refund USD | 186.00 | 71,592.71 |
| Unique reconciliation checks | 14 PASS | 14 PASS |
| DQ / baseline / constraints | 39 / 11 / 7 PASS | 39 / 11 / 7 PASS |

Financial checks use exact documented cents without tolerance. Fixture net revenue is 1,090.97 USD because the fixture adds edge orders; it is not small-seed revenue.

Execution logs/provenance are retained in a separate local audit ZIP rather than this portfolio repository. The concise [test report](test_report.md) records the observed suites and their limits. Use the retained SQL tests to reproduce checks on a new authorized database.

Core workflow and targeted edge checks passed. See [test coverage](test_coverage_audit.md). Financial baselines are synthetic and do not describe a real retailer.
