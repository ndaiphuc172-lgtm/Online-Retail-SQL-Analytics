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

Authoritative clean logs: evidence/runtime_small_clean.txt, runtime_large_clean.txt. Verification: clean_run_validation.json; input manifest: clean_reproduction_manifest.json. Additional evidence: runtime_fixtures.rpt, runtime_performance.txt, runtime_live_metadata.txt, runtime_live_view_details.txt. Rerun and view tests are structured transcriptions of pasted chat output, identified as such; no fabricated original log files.

The older large-existing run contained Msg 102/53900/50001/51002. That historical mixed-result log is excluded from this final-only package; the later successful clean runs are the authoritative setup evidence. Separate _errors.txt streams were not supplied and are not fabricated.

Core workflow passes; targeted edge-case validation is recorded in test_coverage_audit.md. Live view deployment is outside completed validation.
