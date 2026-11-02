# Bug backlog — final repository review
All fixed core SQL below is covered by clean small/large DQ, actual-module execution and 14 exact-cent reconciliation checks. Severity is portfolio impact. Historical supplied errors are retained, not edited into successful logs.

| ID / severity | Initial evidence / root cause | Change and affected chain | Validation / remaining limitation |
|---|---|---|---|
| B01 high | Static: setup could continue after errors across GO batches | Guard existing DB, defer USE/schema, transactional DDL; schema/seed chain | Clean creation and rerun rejection PASS |
| B02 high | Static: small seed wrong DB name | Correct to OnlineRetailDB | Clean small setup/seed PASS |
| B03 high | Definition conflict: refund rounding caused cent differences | Completed cash aggregated per OrderItemID; exact-cent allocation; shared A/C/D/G | FIN01–07, REC01–04/07, clean and fixture PASS |
| B04 high | Coverage/maturity unclear | Explicit exclusive cutoff small Sep 1, large Oct 1 UTC; G grid and flags | EDGE01–06 and clean G PASS; snapshot not historical reconstruction |
| B05 high | Static: success before failure counted recovery | Require later successful attempt by CreatedAt, B | PAY01–02 and INT01 PASS; creation time remains chronology proxy |
| B06 medium | Static: rounded/integer duration could misclassify boundary | F uses seconds, fractional hours and stable priority | Nine actual F boundary tests + SLA regression PASS |
| B07 medium | Static: terminal stages could be aged as open | F excludes terminal statuses from stage aging | Actual F and DQ history checks; terminal absence inspected |
| B08 medium | Defensive issue: last completed event used for settlement | E cumulative completed amount crosses positive approval threshold | REF01–03 PASS; original valid-data bug not proven independently |
| B09 medium | Static: Pareto invalid for negative/nonpositive contribution | C suppresses invalid cumulative percentages; preserve signed values | Guard inspected, actual C executes; no scalability claim |
| B10 high | Static: seed reruns could partially load | Small seed locks/checks all eleven tables, transaction/ambient guard | Clean seed and safe rerun PASS |
| B11 medium | Data-rule scope: large paid Processing expectation not universal | Profile-specific baseline vs universal integrity checks | Both profiles DQ/baselines PASS |
| B12 blocker | Initial runtime access unavailable | Connected PHUCCOMPUTER 16.0.1000.6, compat 160 | New supplied raw runtime results; resolved |
| B13 medium | Runtime/syntax: unquoted RowCount alias | Small seed quotes [RowCount] | Clean seed compiles/executes |
| B14 high | Runtime: SUM decimal(38,s) arithmetic can reduce scale | Cast summed monetary intermediates to decimal(28,2), D/G/seed/DQ/REC | FIN07 + exact-cent clean reconciliation PASS |
| B15 high | Runtime Msg207 CohortMonth from D/G temp-name reuse | G uses #CohortPurchases | Same-connection actual D/G fixture and clean A–G PASS |
| B16 medium | Static: legacy CustomerOrders counts item lines/current price | Owner-selected all-status gross scope; DISTINCT OrderID, historical UnitPrice | Six rollback-only view checks PASS; live view unchanged |
| B17 high | Static: legacy RecentOrders oi.Price absent from live schema | Historical UnitPrice, preserve output scope | Same six view tests bind/execute; live deployment not performed |

Original SQL snapshots are retained in the untouched source archive, not this final-only package. Difference: evidence/changes.diff; hashes: evidence/source_manifest.json. B16/B17 fixes: legacy_views/. Legacy TotalAmount is gross all-status merchandise, not recognized net revenue. No live deployment or permanent index was authorized. Two refund/SLA harness failures were fixture allocation and premature cleanup; both corrected. Failed-attempt logs remain only in the source archive; final 13 assertions PASS.
