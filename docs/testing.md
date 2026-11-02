# Running final tests

Tests are not prerequisites to view the already-collected evidence. They remain available for reproducibility.

1. `tests/metadata_preflight.sql`: read-only environment identity. Its owner/disposable gate is intentionally not inferable from a database name; it is not an analytical FAIL.
2. After exactly one seed, select its profile and run DQ and reconciliation as described in README. Reconciliation prints intermediate and final sets; count unique TestIDs, not repeated rows.
3. `tools/run_fixtures_standalone.sql` runs regression + actual-module integration using local temporary fixtures; SQLCMD Mode required.
4. Run both `tests/targeted_*_checks.sql` files as whole files with SQLCMD Mode; they use session-local fixtures.
5. `tests/constraint_failure_checks.sql` defaults to unauthorized (`@AuthorizedDisposable=0`). Enable only on an explicitly disposable database, with the correct USE target. Mutations roll back.
6. `legacy_views/test_recent_orders_patch.sql` is guarded for the previously authorized small disposable database and rolls back both view changes and the catalog-price mutation. Read its target before use. View ALTER patches are review/deployment artifacts, not scripts for the default clean workflow.

Always save both Results and Messages, inspect all assertions and errors, and require the final marker. A marker alone never overrides an earlier error. SQLCMD stop-on-error must be enabled for drivers. Clean-reproduction drivers refuse an existing target; do not delete a database merely to rerun a driver.
