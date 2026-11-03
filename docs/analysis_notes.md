# Analysis notes and small-seed expectations

These notes describe the reporting logic and expected output for the unmodified small seed. They are not universal results, automated assertions or findings about a real retailer. Use the tests for executable checks.

## Cohort Retention

- A purchase is a Delivered order; a fully refunded Delivered order remains purchase activity.
- Cohorts use the first Delivered purchase month; acquisition channel follows OrderDate then OrderID to break timestamp ties.
- Set the exclusive UTC cutoff to `2026-09-01T00:00:00` for the small seed or `2026-10-01T00:00:00` for the large seed. Coverage is asserted, not inferred from the latest purchase. Events at/after the cutoff are rejected, not silently filtered.
- An observed month without purchases has zero activity/retention. A future period is absent from the observed grid and appears as NULL in the M0-M12 matrix. Partial final months are flagged.
- Repeat-purchase conversion is observed through the selected cutoff, not measured over a fixed follow-up horizon. Compare channels within cohorts, accounting for maturity.
- Revenue is retrospective: completed refunds are attributed to the original order cohort. This does not reconstruct historical order status.

**Small seed only:** four purchasing customers, no repeat customers; M0 retention is 100%, observed later-month retention is zero, and future matrix cells are NULL. This reflects the seed design, not a broken query or evidence of real-world customer churn.

## Sales Analysis

### Monthly revenue and estimated profit

- Revenue recognizes Delivered orders only. Completed refunds reduce revenue; shipping is nonrefundable, counted once per order and excluded from merchandise-only sales.
- Refund cash includes tax. Merchandise refund is allocated by the original item's merchandise/payable ratio, rounded once per item using exact integer-cent arithmetic; tax refund is the remaining cash component.
- Some output columns are named `GrossMerchandiseSales` but use `NetMerchandiseAmount`: they are after item/order discounts and before refunds. Interpret the implemented formula, not the alias alone.
- Empty month/channel combinations remain visible with zero counts and monetary totals. Month-over-month growth is NULL for the first month or a prior-month revenue of zero.
- Net revenue excludes tax and includes shipping. Estimated profit retains original COGS because return restocking/write-off information is unavailable; it is not a fully realized profit measure.

### Orders and payments

- Current order status is a snapshot; the funnel uses history plus inferred reach from later statuses/timestamps. It is not a history-only event measurement. Cancellation is a branch outcome.
- Payment-attempt failure rates include Pending attempts in the denominator. Order-level failure incidence uses all orders, while retry recovery uses orders affected by failed attempts.
- Failed.CreatedAt is a proxy for failure chronology. A later-created Completed attempt counts as recovery even if another successful attempt existed earlier.
- Payment methods with the same displayed failure rate share a dense rank; rank 1 is the highest failure rate. Interpret small attempt populations cautiously.
- NULL percentages mean an unavailable denominator, not zero performance.

### Products and categories

- Historical prices/costs come from OrderItems. Product/category merchandise revenue and estimated profit exclude tax/shipping.
- Products/categories without Delivered sales are retained. Physical returned units require receipt and include rejected returns; completed merchandise refund is a separate financial measure.
- Product and category order counts overlap. Do not sum them into a portfolio-wide unique order count.
- Rankings use refund-adjusted merchandise sales. Dense-rank top five can include more than five products because of ties.
- Monthly cumulative percentages are calculated over all monthly products before filtering the top ranks. Pareto percentages are NULL when totals are nonpositive or any product contribution is negative.

## Customer Analysis

- Revenue is observed, retrospective customer revenue within the available dataset, not predicted CLV. It does not include a forecast, acquisition costs or a complete customer lifetime.
- Customer output retains customers without Delivered purchases and gives them NULL AOV and revenue rank. A fully refunded Delivered purchase remains a purchase.
- Monthly purchase mix omits months without purchases; it does not zero-fill a calendar grid. One customer can place both a first and a repeat order in the same month.

## Delivery Analysis

- The demo SLA assumptions remain 48 hours from order to shipment, 72 hours from shipment to delivery and 120 hours end to end. These are project assumptions, not external service guarantees.
- AnalysisAsOf is the latest recorded order/status event, not the current wall-clock time or proof of extraction coverage. This makes the snapshot reproducible. Choose an observation timestamp that matches the reporting purpose; switching to SYSUTCDATETIME() is not automatically appropriate.
- Elapsed hours retain fractional durations through seconds/3600. LEAD finds the next status event; open nonterminal stages end at AnalysisAsOf, and terminal Delivered/Cancelled stages are excluded from stage-duration averages.

## Schema and seed validation

- Row-level constraints and foreign keys do not enforce all cumulative cross-table workflow rules. DQ checks validate Pending/Completed refund reservation caps against approval/payment amounts; Failed attempts do not reserve approval under the project policy. Passing DQ is a dataset check, not permanent prevention of future invalid writes.
- The large-seed sample-return output shows return decisions and approved amounts. That SELECT does not inspect payment retry attempts.

## Return Refund Analysis

- Sales denominators use Delivered orders. A physical receipt requires `Returns.ReceivedAt IS NOT NULL`; inspection approval and cash settlement are separate events.
- Refund-to-payable rates compare tax-inclusive completed refund cash against tax-inclusive merchandise payable, excluding shipping.
- Return/refund outcomes are attributed to the original order month rather than the refund event month.
- Completed, Pending and Failed refund amounts are aggregated separately per return item. Settlement occurs when cumulative Completed cash first reaches the positive approved amount. Unsettled items have NULL settlement duration and are not treated as zero-day settlements.
- Return reasons are grouped as exact free text. A normalized reason-code dimension would be needed for stable production categorization.
- Product risk includes received rejected units. Products without Delivered sales are excluded from this product-rate output because they lack a valid sold-unit denominator.

**Small seed only:** February App has a full refund with a 100% refund-to-payable rate; March Website has a partial refund of 38.88 / 64.80 = 60%; August App has a received but rejected return, so refunded cash is zero. Shoes, backpack and earbuds each have a 100% physical unit-return rate in this tiny seed; this is not sufficient evidence for a business intervention.
