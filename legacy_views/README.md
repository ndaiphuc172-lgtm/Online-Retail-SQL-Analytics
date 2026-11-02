# Tested legacy-view patches

These final ALTER patches address views discovered in the existing database. They are not created by the core clean schema and are not required for A–G. They preserve the user's chosen all-status historical gross merchandise semantics, excluding discount/refund/tax/shipping; customer totals count distinct OrderID.

Six assertions passed in the guarded small disposable transactional test, followed by rollback. No original live view was deployed. Do not run ALTER patches against an existing non-disposable database without authorization and deployment review. RecentOrders intentionally has no invented recency window.
