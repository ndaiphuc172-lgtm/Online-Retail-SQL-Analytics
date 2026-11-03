# SQL problems and fixes

These examples explain reasoning behind the final SQL. They focus on the A–G workflow rather than deployment history.

| Problem | Fix | Validation |
|---|---|---|
| Joining multiple item/payment/refund rows can multiply amounts | Aggregate each child table to the required grain before joining | Actual-module fixtures and cross-module reconciliation |
| Refund allocation and decimal precision can disagree by one cent | Aggregate completed cash per original item, use consistent integer-cent rounding, cast monetary SUM intermediates before arithmetic | Financial regressions and 14 exact-cent KPI reconciliations per seed |
| An earlier payment success can be mistaken for retry recovery | Require a Completed attempt created after the failed attempt | Earlier-success/later-success regressions and actual module-B assertion |
| Rounded hours can misclassify an SLA boundary | Compare elapsed seconds before rounding; retain fractional hours for display | Actual F tests below/equal/above the 48/72/120-hour limits |
| Refund approval and settlement are different events | Find when cumulative Completed cash first reaches the positive approval; keep Pending/Failed separate | Actual E split/pending/failed refund assertions |
| Missing purchase months can be confused with future periods | Build the observed cohort grid with an explicit cutoff; observed inactivity is zero and future matrix cells are NULL | Targeted G output checks including partial-month coverage |
| First-purchase channel is ambiguous for equal timestamps | Order by OrderDate then OrderID | Actual cohort acquisition-channel tie assertion |
| D/G temporary tables shared a name but had different columns | Keep #CustomerPurchases and #CohortPurchases separate | Same-connection integration execution |
| Rerunning setup/seed could affect existing data | Reject an existing database or nonempty seed target; preserve transaction guards | Clean workflows and safe-rerun assertions |

Limitations remain explicit: retry timing uses CreatedAt as a proxy; revenue is retrospective and observed, not predicted CLV; return inventory disposition is unavailable, so profit is estimated; SLA thresholds are demo assumptions. See [the KPI contract](kpi_contract.md) and [test report](test_report.md).
