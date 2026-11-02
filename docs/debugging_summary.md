# Final debugging summary

The final SQL addresses schema/seed guards, database naming, common item-level refund rounding, aggregate decimal precision, retry chronology, explicit cohort cutoff/maturity, sub-hour SLA boundaries, terminal-stage aging and D/G temporary-table collisions. B01–B17 findings and limitations are in bug_backlog.md.

Final runtime outcomes and evidence are consolidated in completion_gate.md. Two additional test-harness problems (payment reservation allocation and facts dropped before assertions) were corrected; the final refund/SLA run passed. Their failed attempts are intentionally excluded from this final-only portfolio package.

Legacy CustomerOrders now counts distinct orders with historical UnitPrice; RecentOrders replaces the absent oi.Price reference with UnitPrice. User-selected all-status gross semantics are preserved. Fixes passed a disposable transactional test; original live views remain unchanged.

Packaging changed documentation and selection only, not final SQL/test/driver bytes. No database was accessed or modified while assembling this delivery.
