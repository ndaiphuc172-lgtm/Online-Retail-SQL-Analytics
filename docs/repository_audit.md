# Repository audit
Authoritative sources: eight original SQL files supplied by user, eight recovered corrected SQL files, live metadata reports and SQL Server execution results. Original snapshots remain in the untouched source archive and are intentionally excluded from this final-only package. Current delivered hashes match evidence/source_manifest.json.

Core persistent layer: eleven dbo retail tables with PK/FK/CHECK/unique/default/computed columns. Analytical layer consists of session-local facts and report SELECTs; no invented staging or warehouse layer. Runtime fixtures are test-only #Fixture tables; no persistent raw source was overwritten.

Order: new schema → exactly one small/large seed → DQ → A/B/C and D/E/F/G → reconciliation. Both clean paths observed PASS with matching transformed-body hashes. Original non-disposable OnlineRetailDB was inspected read-only. New disposable schemas/seeds and rolled-back constraint/view tests were authorized separately.

Live metadata has three legacy views: CustomerOrders (Customers, Orders, OrderItems, Products), ProductDeails (Products, Categories), RecentOrders (Orders, Customers, OrderItems). Existing diagram functions/procedures and sysdiagrams belong to SSMS infrastructure. Corrected customer view removes unnecessary Products dependency; RecentOrders keeps historical item-price totals. Existing live views remain unchanged; fixes are delivered as tested review patches.

Server Phuccomputer; SQL Server 2022 16.0.1000.6; compatibility 160. Core scripts use SQL Server 2016+ features; this package was runtime-tested only on SQL Server 2022. Test view CREATE OR ALTER requires SQL Server 2016 SP1+; live patch uses ALTER on existing views.

Integrity: clean runs assert 39 DQ and 11 baselines per seed, plus seven negative constraint tests. Row-level constraints cannot enforce all cross-table workflow rules; validation scripts check chronology, payment/refund reservations, entitlement and orphans. Nullable/shared email, failed attempts and valid cancellations are not treated as errors merely for existing.

Evidence limits: finite synthetic data does not certify arbitrary future writes, true customer lifetime or production scalability. sys.partitions counts are metadata estimates. Pasted rerun/view evidence is labelled as transcription. No credentials, server settings, cache clearing or permanent tuning indexes were used.
