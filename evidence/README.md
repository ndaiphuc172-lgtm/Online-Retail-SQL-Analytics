# Final evidence index

Tests ran on PHUCCOMPUTER, SQL Server 2022 16.0.1000.6, compatibility 160, on 2026-10-12. This package was assembled from the restored final-review archive on 2026-11-02 without rerunning SQL.

- `runtime_small_clean.txt` / `runtime_large_clean.txt`: authoritative clean setup/seed/report logs with body-hash banners. `clean_run_validation.json` contains parsed checks.
- `runtime_fixtures.rpt`: regression and actual-module fixture results.
- `runtime_targeted_cohort_customer.txt` / `runtime_targeted_refund_sla_success.txt`: final targeted PASS outputs.
- `rerun_pasted_evidence.json` / `legacy_view_test_pasted.json`: labelled structured transcriptions of SSMS output supplied in chat.
- `runtime_performance.txt`: IO/TIME output; `performance_validation.json` records statement-message sums. Cache plan output was empty.
- `runtime_live_metadata.txt` / `runtime_live_view_details.txt`: observed metadata and full legacy definitions.
- `source_manifest.json`: original and delivered SQL hashes; original absolute source paths removed from this public-ready copy. Original sources themselves are intentionally excluded. `changes.diff` preserves original-to-fixed comparison.

No empty error logs have been fabricated. Raw retained reports are unchanged, including legitimate warnings and expected caught constraint errors. Tests ran on synthetic data; existing live views were inspected but not deployed. No claim is made that packaging revalidated the live server.
