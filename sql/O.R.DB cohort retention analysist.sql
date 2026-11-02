/*=============================================================================
  PORTFOLIO PROJECT: ONLINE RETAIL ANALYTICS
  STEP 4.7 - CUSTOMER COHORT AND RETENTION ANALYSIS

  SQL dialect : Microsoft SQL Server
  Database    : OnlineRetailDB

  DEFINITIONS
  - Valid purchase: OrderStatus='Delivered'.
  - Cohort month: month of a customer's first Delivered order.
  - Month 0: acquisition month; Month 1, 2... are calendar-month offsets.
  - Retained customer: cohort customer with >=1 Delivered order in that month.
  - Fully refunded Delivered orders still count as purchase activity.
  - Revenue excludes tax, includes shipping, and subtracts completed refunds.

  OUTPUTS
  1. Long-form cohort retention and cumulative revenue.
  2. M0-M12 retention matrix for reporting/heatmaps.
  3. Repeat-purchase KPIs by cohort and acquisition channel.
=============================================================================*/

USE [OnlineRetailDB];
GO
SET NOCOUNT ON;

-- REQUIRED coverage assertion: do not infer extraction coverage from purchases.
-- Large seed: 2026-10-01T00:00:00 (documented exclusive UTC cutoff).
-- Small demo policy selected with user authorization: observe through August 2026.
-- For the large seed set the declaration below to 2026-10-01T00:00:00.
-- This is a retrospective snapshot report, not historical status reconstruction.
DECLARE @ObservationCutoffExclusive datetime2(0)='2026-09-01T00:00:00';
IF @ObservationCutoffExclusive IS NULL
    THROW 50008, 'Set the verified exclusive UTC dataset coverage cutoff.', 1;
IF EXISTS
(
    SELECT 1 FROM
    (
        SELECT OrderDate EventAt FROM dbo.Orders
        UNION ALL SELECT ShippedAt FROM dbo.Orders
        UNION ALL SELECT DeliveredAt FROM dbo.Orders
        UNION ALL SELECT CancelledAt FROM dbo.Orders
        UNION ALL SELECT ChangedAt FROM dbo.OrderStatusHistory
        UNION ALL SELECT CreatedAt FROM dbo.Payments
        UNION ALL SELECT CompletedAt FROM dbo.Payments
        UNION ALL SELECT RequestedAt FROM dbo.Returns
        UNION ALL SELECT ReceivedAt FROM dbo.Returns
        UNION ALL SELECT DecidedAt FROM dbo.ReturnItems
        UNION ALL SELECT CreatedAt FROM dbo.Refunds
        UNION ALL SELECT CompletedAt FROM dbo.Refunds
    ) e WHERE EventAt>=@ObservationCutoffExclusive
)
    THROW 50009, 'Snapshot contains events at/after cutoff; use a matching snapshot.', 1;
DECLARE @ObservationEndMonth date=DATEFROMPARTS(
    YEAR(DATEADD(SECOND,-1,@ObservationCutoffExclusive)),
    MONTH(DATEADD(SECOND,-1,@ObservationCutoffExclusive)),1);


IF NOT EXISTS(SELECT 1 FROM dbo.Orders WHERE OrderStatus='Delivered')
BEGIN
    THROW 50007, 'No delivered orders are available for cohort analysis.', 1;
END;

DROP TABLE IF EXISTS #CohortPurchases;
DROP TABLE IF EXISTS #CohortRetention;

/* Build refund-adjusted order revenue before assigning purchase sequence. */
;WITH ItemTotals AS
(
    SELECT OrderID,CAST(SUM(NetMerchandiseAmount) AS decimal(28,2)) AS MerchandiseSales
    FROM dbo.OrderItems
    GROUP BY OrderID
), RefundCashByItem AS
(
    SELECT ri.OrderItemID,CAST(SUM(r.Amount) AS decimal(18,2)) AS CompletedRefundAmount
    FROM dbo.Refunds r
    JOIN dbo.ReturnItems ri ON ri.ReturnItemID=r.ReturnItemID
    WHERE r.RefundStatus='Completed'
    GROUP BY ri.OrderItemID
), CompletedRefundByItem AS
(
    -- Approved 2026-10-11: aggregate cash per original item, round once to cents.
    -- Exact quotient/remainder implements ROUND(...,2) for nonnegative amounts.
    -- Tax refund = completed cash minus this rounded merchandise component.
    SELECT oi.OrderItemID,oi.OrderID,rc.CompletedRefundAmount,
        CAST(ROUND(
            ((a.Numerator-(a.Numerator % NULLIF(a.Denominator,0)))
                /NULLIF(a.Denominator,0)
             +CASE WHEN (a.Numerator % NULLIF(a.Denominator,0))*2>=a.Denominator
                   THEN 1 ELSE 0 END)/100.0,2) AS decimal(18,2))
            AS RefundedMerchandiseAmount
    FROM RefundCashByItem rc
    JOIN dbo.OrderItems oi ON oi.OrderItemID=rc.OrderItemID
    CROSS APPLY (VALUES
       (CAST(rc.CompletedRefundAmount*100 AS decimal(18,0))
          *CAST(oi.NetMerchandiseAmount*100 AS decimal(18,0)),
        CAST(oi.LinePayableAmount*100 AS decimal(18,0)))
    ) a(Numerator,Denominator)
), RefundTotals AS
(
    SELECT OrderID,CAST(SUM(RefundedMerchandiseAmount) AS decimal(28,2)) AS MerchandiseRefund
    FROM CompletedRefundByItem GROUP BY OrderID
), DeliveredOrders AS
(
    SELECT o.OrderID,o.CustomerID,o.OrderDate,o.SalesChannel,
        DATEFROMPARTS(YEAR(o.OrderDate),MONTH(o.OrderDate),1) AS OrderMonth,
        CAST(it.MerchandiseSales-ISNULL(rt.MerchandiseRefund,0)
            +o.ShippingFee AS decimal(18,2)) AS NetRevenue
    FROM dbo.Orders o
    JOIN ItemTotals it ON it.OrderID=o.OrderID
    LEFT JOIN RefundTotals rt ON rt.OrderID=o.OrderID
    WHERE o.OrderStatus='Delivered'
), PurchaseSequence AS
(
    SELECT *,
        ROW_NUMBER() OVER
            (PARTITION BY CustomerID ORDER BY OrderDate,OrderID)
            AS PurchaseNumber,
        MIN(OrderMonth) OVER(PARTITION BY CustomerID) AS CohortMonth,
        FIRST_VALUE(SalesChannel) OVER
            (PARTITION BY CustomerID ORDER BY OrderDate,OrderID
             ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
            AS AcquisitionChannel
    FROM DeliveredOrders
)
SELECT *,DATEDIFF(MONTH,CohortMonth,OrderMonth) AS MonthIndex
INTO #CohortPurchases
FROM PurchaseSequence;

DECLARE @MaxMonthIndex int=(SELECT MAX(DATEDIFF(MONTH,CohortMonth,
                                               @ObservationEndMonth))
                            FROM #CohortPurchases);

/* Create an observed cohort-month grid. This distinguishes:
   0    = period was observable but nobody returned;
   NULL = period has not elapsed yet and is excluded from the grid. */
;WITH CohortSizes AS
(
    SELECT CohortMonth,COUNT(DISTINCT CustomerID) AS CohortSize
    FROM #CohortPurchases
    GROUP BY CohortMonth
), Periods AS
(
    SELECT 0 AS MonthIndex
    UNION ALL
    SELECT MonthIndex+1 FROM Periods WHERE MonthIndex<@MaxMonthIndex
), CohortGrid AS
(
    SELECT cs.CohortMonth,cs.CohortSize,p.MonthIndex,
        DATEADD(MONTH,p.MonthIndex,cs.CohortMonth) AS ActivityMonth
    FROM CohortSizes cs CROSS JOIN Periods p
    WHERE p.MonthIndex<=DATEDIFF(MONTH,cs.CohortMonth,@ObservationEndMonth)
), Activity AS
(
    SELECT CohortMonth,MonthIndex,
        COUNT(DISTINCT CustomerID) AS ActiveCustomerCount,
        COUNT(*) AS DeliveredOrderCount,
        SUM(NetRevenue) AS CohortNetRevenue
    FROM #CohortPurchases
    GROUP BY CohortMonth,MonthIndex
), RetentionBase AS
(
    SELECT cg.CohortMonth,cg.MonthIndex,cg.ActivityMonth,cg.CohortSize,
        ISNULL(a.ActiveCustomerCount,0) AS ActiveCustomerCount,
        ISNULL(a.DeliveredOrderCount,0) AS DeliveredOrderCount,
        ISNULL(a.CohortNetRevenue,0) AS CohortNetRevenue,
        CAST(100.0*ISNULL(a.ActiveCustomerCount,0)/NULLIF(cg.CohortSize,0)
            AS decimal(10,2)) AS RetentionRatePct
    FROM CohortGrid cg
    LEFT JOIN Activity a ON a.CohortMonth=cg.CohortMonth
        AND a.MonthIndex=cg.MonthIndex
)
SELECT *,
    SUM(CohortNetRevenue) OVER
        (PARTITION BY CohortMonth ORDER BY MonthIndex
         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
        AS CumulativeCohortRevenue
INTO #CohortRetention
FROM RetentionBase
OPTION(MAXRECURSION 0);

/* RESULT 1: Long format is the preferred source for Power BI/Tableau. */
SELECT @ObservationCutoffExclusive AS ObservationCutoffExclusiveUTC,
    CAST(CASE WHEN DATEADD(MONTH,1,ActivityMonth)>@ObservationCutoffExclusive
              THEN 1 ELSE 0 END AS bit) AS IsPartialActivityMonth,
    CohortMonth,MonthIndex,ActivityMonth,CohortSize,
    ActiveCustomerCount,DeliveredOrderCount,RetentionRatePct,
    CAST(CohortNetRevenue AS decimal(18,2)) AS CohortNetRevenue,
    CAST(CohortNetRevenue/NULLIF(ActiveCustomerCount,0) AS decimal(18,2))
        AS RevenuePerActiveCustomer,
    CAST(CumulativeCohortRevenue AS decimal(18,2))
        AS CumulativeCohortRevenue
FROM #CohortRetention
ORDER BY CohortMonth,MonthIndex;

/* RESULT 2: A fixed 13-month matrix is convenient for a GitHub portfolio.
   NULL means the cohort has not yet had time to reach that month. */
SELECT @ObservationCutoffExclusive AS ObservationCutoffExclusiveUTC,
    @ObservationEndMonth AS LastObservedMonth,
    CAST(CASE WHEN DATEADD(MONTH,1,@ObservationEndMonth)>@ObservationCutoffExclusive
              THEN 1 ELSE 0 END AS bit) AS IsLastMonthPartial,
    CohortMonth,MAX(CohortSize) AS CohortSize,
    MAX(CASE WHEN MonthIndex=0 THEN RetentionRatePct END) AS M0,
    MAX(CASE WHEN MonthIndex=1 THEN RetentionRatePct END) AS M1,
    MAX(CASE WHEN MonthIndex=2 THEN RetentionRatePct END) AS M2,
    MAX(CASE WHEN MonthIndex=3 THEN RetentionRatePct END) AS M3,
    MAX(CASE WHEN MonthIndex=4 THEN RetentionRatePct END) AS M4,
    MAX(CASE WHEN MonthIndex=5 THEN RetentionRatePct END) AS M5,
    MAX(CASE WHEN MonthIndex=6 THEN RetentionRatePct END) AS M6,
    MAX(CASE WHEN MonthIndex=7 THEN RetentionRatePct END) AS M7,
    MAX(CASE WHEN MonthIndex=8 THEN RetentionRatePct END) AS M8,
    MAX(CASE WHEN MonthIndex=9 THEN RetentionRatePct END) AS M9,
    MAX(CASE WHEN MonthIndex=10 THEN RetentionRatePct END) AS M10,
    MAX(CASE WHEN MonthIndex=11 THEN RetentionRatePct END) AS M11,
    MAX(CASE WHEN MonthIndex=12 THEN RetentionRatePct END) AS M12
FROM #CohortRetention
GROUP BY CohortMonth
ORDER BY CohortMonth;

/* RESULT 3: Observed-to-cutoff conversion; cohorts have unequal maturity.
   Compare channels within cohort only. This is not a fixed-horizon retention KPI. */
;WITH CustomerSummary AS
(
    SELECT CustomerID,CohortMonth,AcquisitionChannel,
        MIN(CASE WHEN PurchaseNumber=1 THEN OrderDate END) AS FirstPurchaseAt,
        MIN(CASE WHEN PurchaseNumber=2 THEN OrderDate END) AS SecondPurchaseAt,
        MAX(PurchaseNumber) AS DeliveredOrderCount,
        SUM(NetRevenue) AS ObservedCustomerRevenue,
        SUM(CASE WHEN PurchaseNumber>1 THEN NetRevenue ELSE 0 END)
            AS RepeatOrderRevenue
    FROM #CohortPurchases
    GROUP BY CustomerID,CohortMonth,AcquisitionChannel
), CohortChannelKPI AS
(
    SELECT CohortMonth,AcquisitionChannel,COUNT(*) AS CohortSize,
        SUM(CASE WHEN DeliveredOrderCount>=2 THEN 1 ELSE 0 END)
            AS RepeatCustomerCount,
        SUM(ObservedCustomerRevenue) AS ObservedCohortRevenue,
        SUM(RepeatOrderRevenue) AS RepeatOrderRevenue,
        AVG(CASE WHEN SecondPurchaseAt IS NOT NULL THEN
            CAST(DATEDIFF_BIG(SECOND,FirstPurchaseAt,SecondPurchaseAt)
                 AS decimal(20,4))/86400.0 END) AS AvgDaysToSecondPurchase
    FROM CustomerSummary
    GROUP BY CohortMonth,AcquisitionChannel
), CohortRates AS
(
    SELECT *,
        CAST(100.0*RepeatCustomerCount/NULLIF(CohortSize,0)
            AS decimal(10,2)) AS RepeatPurchaseRatePct,
        CAST(100.0*RepeatOrderRevenue/NULLIF(ObservedCohortRevenue,0)
            AS decimal(10,2)) AS RepeatRevenueSharePct
    FROM CohortChannelKPI
)
SELECT @ObservationCutoffExclusive AS ObservationCutoffExclusiveUTC,
    DATEDIFF(MONTH,CohortMonth,@ObservationEndMonth) AS LastObservedMonthIndex,
    CAST(CASE WHEN DATEADD(MONTH,1,@ObservationEndMonth)>@ObservationCutoffExclusive
              THEN 1 ELSE 0 END AS bit) AS IsLastMonthPartial,
    CohortMonth,AcquisitionChannel,CohortSize,RepeatCustomerCount,
    RepeatPurchaseRatePct,
    CAST(AvgDaysToSecondPurchase AS decimal(18,2))
        AS AvgDaysToSecondPurchase,
    CAST(ObservedCohortRevenue AS decimal(18,2)) AS ObservedCohortRevenue,
    CAST(RepeatOrderRevenue AS decimal(18,2)) AS RepeatOrderRevenue,
    RepeatRevenueSharePct,
    DENSE_RANK() OVER
        (PARTITION BY CohortMonth
         ORDER BY RepeatPurchaseRatePct DESC,ObservedCohortRevenue DESC)
        AS AcquisitionChannelRankWithinCohort
FROM CohortRates
ORDER BY CohortMonth,AcquisitionChannelRankWithinCohort,AcquisitionChannel;

DROP TABLE IF EXISTS #CohortRetention;
DROP TABLE IF EXISTS #CohortPurchases;
GO

/* DEMO INTERPRETATION
   - The small seed has four purchasing customers and no repeat customer.
   - Every cohort has M0=100%; observable later months equal 0%.
   - Future, unobservable months are NULL in the matrix.
   - Zero repeat retention reflects the compact demo seed, not a query error.
   Use the larger mock-data script for a meaningful retention heatmap.
*/
