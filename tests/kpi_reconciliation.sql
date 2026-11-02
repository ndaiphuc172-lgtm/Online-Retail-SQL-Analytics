/* Generated from the delivered production query bodies, not simplified
   independent implementations. Re-run generate_reconciliation.py after edits.
   Read-only against permanent data. SQLCMD -b required to stop on error.
   Set the same coverage cutoff in the G section as in the cohort module.
   Approved item allocation: cent mismatches FAIL, never tolerated away.
*/
DROP TABLE IF EXISTS #AuditRevenue;
/*=============================================================================
  PORTFOLIO PROJECT: ONLINE RETAIL ANALYTICS
  STEP 4.1 - MONTHLY REVENUE AND PROFIT BY SALES CHANNEL

  SQL dialect : Microsoft SQL Server
  Database    : OnlineRetailDB

  BUSINESS QUESTION
  How do revenue and estimated profit change by month and sales channel?

  KPI RULES
  1. Only Delivered orders are recognized as sales.
  2. Gross merchandise sales exclude tax and shipping.
  3. Only Completed refunds reduce revenue.
  4. Refunds are attributed to the original order month (order-cohort view).
  5. Shipping is not refundable under the current business rules.
  6. Estimated profit is conservative because the schema does not record
     whether returned inventory was restocked, repaired, or written off.
=============================================================================*/

USE OnlineRetailDB;
GO

SET NOCOUNT ON;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.Orders
    WHERE OrderStatus = 'Delivered'
)
BEGIN
    THROW 50001, 'No delivered orders are available for revenue analysis.', 1;
END;

DECLARE @StartMonth date;
DECLARE @EndMonth   date;

SELECT
    @StartMonth = DATEFROMPARTS(YEAR(MIN(OrderDate)), MONTH(MIN(OrderDate)), 1),
    @EndMonth   = DATEFROMPARTS(YEAR(MAX(OrderDate)), MONTH(MAX(OrderDate)), 1)
FROM dbo.Orders
WHERE OrderStatus = 'Delivered';

;WITH
/* Aggregate order-item data first so every order has exactly one row.
   This prevents revenue from being multiplied when later joins are added. */
OrderItemSummary AS
(
    SELECT
        oi.OrderID,
        SUM(oi.NetMerchandiseAmount)                  AS GrossMerchandiseSales,
        SUM(oi.TaxAmount)                             AS GrossTaxAmount,
        SUM(oi.Quantity * oi.UnitCostAtOrder)         AS OriginalCOGS
    FROM dbo.OrderItems AS oi
    GROUP BY oi.OrderID
),

/* A refund includes merchandise and tax. Allocate it proportionally using
   the original order item's merchandise-to-payable ratio. */
   --ty le hoan tien hang va hoan thue
RefundCashByItem AS
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
), CompletedRefundByOrder AS
(
    SELECT OrderID,SUM(CompletedRefundAmount) AS CompletedRefundAmount,
        SUM(RefundedMerchandiseAmount) AS RefundedMerchandiseAmount
    FROM CompletedRefundByItem GROUP BY OrderID
),

/* One row per delivered order: this is the safe analytical grain before
   grouping by month and channel. */
   --mot dong cho moi don da giao
DeliveredOrderFacts AS
(
    SELECT
        o.OrderID,
        DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1) AS OrderMonth,
        o.SalesChannel,
        CAST(ois.GrossMerchandiseSales AS decimal(18,2)) AS GrossMerchandiseSales,
        CAST(ois.GrossTaxAmount AS decimal(18,2))        AS GrossTaxAmount,
        CAST(o.ShippingFee AS decimal(18,2))             AS ShippingRevenue,
        CAST(ois.OriginalCOGS AS decimal(18,2))          AS OriginalCOGS,
        CAST(ISNULL(cro.CompletedRefundAmount, 0) AS decimal(18,2))
            AS CompletedRefundAmount,
        CAST(ISNULL(cro.RefundedMerchandiseAmount, 0) AS decimal(18,2))
            AS RefundedMerchandiseAmount
    FROM dbo.Orders AS o
    INNER JOIN OrderItemSummary AS ois
        ON ois.OrderID = o.OrderID
    LEFT JOIN CompletedRefundByOrder AS cro
        ON cro.OrderID = o.OrderID
    WHERE o.OrderStatus = 'Delivered'
),

/* Aggregate the order-level facts into the reporting grain:
   one row per month per sales channel. */

MonthlyChannelMetrics AS
(
    SELECT
        dof.OrderMonth,
        dof.SalesChannel,
        COUNT(*) AS DeliveredOrderCount,
        SUM(dof.GrossMerchandiseSales) AS GrossMerchandiseSales,
        SUM(dof.GrossTaxAmount) AS GrossTaxAmount,
        SUM(dof.ShippingRevenue) AS ShippingRevenue,
        SUM(dof.CompletedRefundAmount) AS CompletedRefundAmount,
        SUM(dof.RefundedMerchandiseAmount) AS RefundedMerchandiseAmount,
        SUM(dof.CompletedRefundAmount - dof.RefundedMerchandiseAmount)
            AS RefundedTaxAmount,
        SUM(dof.GrossMerchandiseSales - dof.RefundedMerchandiseAmount)
            AS NetMerchandiseSales,
        SUM
        (
            dof.GrossMerchandiseSales
            - dof.RefundedMerchandiseAmount
            + dof.ShippingRevenue
        ) AS NetRevenue,
        SUM(dof.OriginalCOGS) AS OriginalCOGS,
        SUM
        (
            dof.GrossMerchandiseSales
            - dof.RefundedMerchandiseAmount
            - dof.OriginalCOGS
        ) AS EstimatedGrossProfit
    FROM DeliveredOrderFacts AS dof
    GROUP BY
        dof.OrderMonth,
        dof.SalesChannel
),

/* Generate every calendar month in the reporting period. This ensures LAG
   compares adjacent calendar months instead of skipping months with no sales. */
MonthSpine AS
(
    SELECT @StartMonth AS OrderMonth

    UNION ALL

    SELECT DATEADD(MONTH, 1, OrderMonth)
    FROM MonthSpine
    WHERE OrderMonth < @EndMonth
),
SalesChannels AS
(
    SELECT SalesChannel
    FROM (VALUES ('Website'), ('App')) AS ch(SalesChannel)
),
CompleteMonthlySeries AS
(
    SELECT
        ms.OrderMonth,
        ch.SalesChannel,
        ISNULL(mcm.DeliveredOrderCount, 0)        AS DeliveredOrderCount,
        ISNULL(mcm.GrossMerchandiseSales, 0)      AS GrossMerchandiseSales,
        ISNULL(mcm.GrossTaxAmount, 0)             AS GrossTaxAmount,
        ISNULL(mcm.ShippingRevenue, 0)            AS ShippingRevenue,
        ISNULL(mcm.CompletedRefundAmount, 0)      AS CompletedRefundAmount,
        ISNULL(mcm.RefundedMerchandiseAmount, 0)  AS RefundedMerchandiseAmount,
        ISNULL(mcm.RefundedTaxAmount, 0)           AS RefundedTaxAmount,
        ISNULL(mcm.NetMerchandiseSales, 0)         AS NetMerchandiseSales,
        ISNULL(mcm.NetRevenue, 0)                  AS NetRevenue,
        ISNULL(mcm.OriginalCOGS, 0)                AS OriginalCOGS,
        ISNULL(mcm.EstimatedGrossProfit, 0)        AS EstimatedGrossProfit
    FROM MonthSpine AS ms
    CROSS JOIN SalesChannels AS ch
    LEFT JOIN MonthlyChannelMetrics AS mcm
        ON  mcm.OrderMonth = ms.OrderMonth
        AND mcm.SalesChannel = ch.SalesChannel
),

/* Window functions calculate the previous month's result and cumulative
   year-to-date revenue without collapsing the monthly rows. */
MetricsWithWindows AS
(
    SELECT
        cms.*,
        LAG(cms.NetRevenue) OVER
        (
            PARTITION BY cms.SalesChannel
            ORDER BY cms.OrderMonth
        ) AS PreviousMonthNetRevenue,
        SUM(cms.NetRevenue) OVER
        (
            PARTITION BY cms.SalesChannel, YEAR(cms.OrderMonth)
            ORDER BY cms.OrderMonth
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS YTDNetRevenue
    FROM CompleteMonthlySeries AS cms
)
SELECT
    OrderMonth,
    SalesChannel,
    DeliveredOrderCount,
    CAST(GrossMerchandiseSales AS decimal(18,2))     AS GrossMerchandiseSales,
    CAST(GrossTaxAmount AS decimal(18,2))            AS GrossTaxAmount,
    CAST(ShippingRevenue AS decimal(18,2))           AS ShippingRevenue,
    CAST(CompletedRefundAmount AS decimal(18,2))     AS CompletedRefundAmount,
    CAST(RefundedMerchandiseAmount AS decimal(18,2)) AS RefundedMerchandiseAmount,
    CAST(RefundedTaxAmount AS decimal(18,2))          AS RefundedTaxAmount,
    CAST(NetMerchandiseSales AS decimal(18,2))        AS NetMerchandiseSales,
    CAST(NetRevenue AS decimal(18,2))                 AS NetRevenue,
    CAST(OriginalCOGS AS decimal(18,2))               AS OriginalCOGS,
    CAST(EstimatedGrossProfit AS decimal(18,2))       AS EstimatedGrossProfit,

    /* NULLIF prevents division-by-zero errors in empty months. */
    CAST
    (
        NetRevenue / NULLIF(CAST(DeliveredOrderCount AS decimal(18,2)), 0)
        AS decimal(18,2)
    ) AS AverageOrderValue,
    CAST
    (
        100.0 * EstimatedGrossProfit /
        NULLIF(NetMerchandiseSales, 0)
        AS decimal(10,2)
    ) AS EstimatedGrossMarginPct,
    CAST
    (
        100.0 * (NetRevenue - PreviousMonthNetRevenue) /
        NULLIF(PreviousMonthNetRevenue, 0)
        AS decimal(10,2)
    ) AS MonthOverMonthGrowthPct,
    CAST(YTDNetRevenue AS decimal(18,2)) AS YTDNetRevenue
INTO #AuditRevenue
FROM MetricsWithWindows
ORDER BY
    OrderMonth,
    SalesChannel
OPTION (MAXRECURSION 0);
GO


GO
DROP TABLE IF EXISTS #DeliveredItemFacts;

;WITH
RefundCashByItem AS
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
),
ReceivedReturnByItem AS
(
    SELECT
        ri.OrderItemID,
        SUM(ri.Quantity) AS ReceivedReturnQuantity
    FROM dbo.ReturnItems AS ri
    INNER JOIN dbo.Returns AS rt
        ON rt.ReturnID = ri.ReturnID
    WHERE rt.ReceivedAt IS NOT NULL
    GROUP BY ri.OrderItemID
)
SELECT
    oi.OrderItemID,
    oi.OrderID,
    oi.ProductID,
    p.SKU,
    p.ProductName,
    p.CategoryID,
    c.CategoryName,
    DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1) AS OrderMonth,
    o.SalesChannel,
    oi.Quantity AS UnitsSold,
    ISNULL(rri.ReceivedReturnQuantity, 0) AS UnitsReturned,
    CAST(oi.NetMerchandiseAmount AS decimal(18,2)) AS GrossMerchandiseSales,
    CAST(ISNULL(cri.RefundedMerchandiseAmount, 0) AS decimal(18,2))
        AS RefundedMerchandiseAmount,
    CAST
    (
        oi.NetMerchandiseAmount
        - ISNULL(cri.RefundedMerchandiseAmount, 0)
        AS decimal(18,2)
    ) AS NetMerchandiseSales,
    CAST(oi.Quantity * oi.UnitCostAtOrder AS decimal(18,2)) AS OriginalCOGS,
    CAST
    (
        oi.NetMerchandiseAmount
        - ISNULL(cri.RefundedMerchandiseAmount, 0)
        - oi.Quantity * oi.UnitCostAtOrder
        AS decimal(18,2)
    ) AS EstimatedGrossProfit
INTO #DeliveredItemFacts
FROM dbo.Orders AS o
INNER JOIN dbo.OrderItems AS oi
    ON oi.OrderID = o.OrderID
INNER JOIN dbo.Products AS p
    ON p.ProductID = oi.ProductID
INNER JOIN dbo.Categories AS c
    ON c.CategoryID = p.CategoryID
LEFT JOIN CompletedRefundByItem AS cri
    ON cri.OrderItemID = oi.OrderItemID
LEFT JOIN ReceivedReturnByItem AS rri
    ON rri.OrderItemID = oi.OrderItemID
WHERE o.OrderStatus = 'Delivered';


DROP TABLE IF EXISTS #CustomerPurchases;

;WITH ItemTotals AS
(
    -- One row per order prevents item/payment join duplication.
    SELECT OrderID, CAST(SUM(NetMerchandiseAmount) AS decimal(28,2)) AS MerchandiseSales
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
), PurchaseFacts AS
(
    SELECT o.OrderID, o.CustomerID, o.OrderDate, o.SalesChannel,
        DATEFROMPARTS(YEAR(o.OrderDate),MONTH(o.OrderDate),1) AS OrderMonth,
        CAST(it.MerchandiseSales-ISNULL(rt.MerchandiseRefund,0)
            +o.ShippingFee AS decimal(18,2)) AS NetRevenue
    FROM dbo.Orders AS o
    JOIN ItemTotals AS it ON it.OrderID=o.OrderID
    LEFT JOIN RefundTotals AS rt ON rt.OrderID=o.OrderID
    WHERE o.OrderStatus='Delivered'
)
SELECT pf.*,
    ROW_NUMBER() OVER(PARTITION BY CustomerID ORDER BY OrderDate,OrderID)
        AS PurchaseNumber,
    LAG(OrderDate) OVER(PARTITION BY CustomerID ORDER BY OrderDate,OrderID)
        AS PreviousPurchaseAt,
    LEAD(OrderDate) OVER(PARTITION BY CustomerID ORDER BY OrderDate,OrderID)
        AS NextPurchaseAt,
    SUM(NetRevenue) OVER(PARTITION BY CustomerID ORDER BY OrderDate,OrderID
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
        AS CumulativeCustomerRevenue
INTO #CustomerPurchases
FROM PurchaseFacts AS pf;

DROP TABLE IF EXISTS #DeliveredOrderFacts;
DROP TABLE IF EXISTS #ReturnItemFacts;

/* One row per Delivered order supplies clean denominators. */
;WITH ItemTotals AS
(
    SELECT OrderID,
        SUM(Quantity) AS UnitsSold,
        SUM(LinePayableAmount) AS MerchandisePayableAmount
    FROM dbo.OrderItems
    GROUP BY OrderID
)
SELECT o.OrderID,
    DATEFROMPARTS(YEAR(o.OrderDate),MONTH(o.OrderDate),1) AS OrderMonth,
    o.SalesChannel,
    it.UnitsSold,
    CAST(it.MerchandisePayableAmount AS decimal(18,2))
        AS MerchandisePayableAmount
INTO #DeliveredOrderFacts
FROM dbo.Orders AS o
JOIN ItemTotals AS it ON it.OrderID=o.OrderID
WHERE o.OrderStatus='Delivered';

/* Aggregate refund attempts before joining ReturnItems. This keeps the fact
   table at one row per ReturnItem even when a refund is split or retried. */
;WITH CompletedSequence AS
(
    SELECT r.ReturnItemID,r.CompletedAt,r.RefundID,
        SUM(r.Amount) OVER(PARTITION BY r.ReturnItemID
            ORDER BY r.CompletedAt,r.RefundID ROWS UNBOUNDED PRECEDING)
            AS RunningCompletedAmount
    FROM dbo.Refunds r WHERE r.RefundStatus='Completed'
), Settlement AS
(
    SELECT cs.ReturnItemID,MIN(cs.CompletedAt) AS SettlementCompletedAt
    FROM CompletedSequence cs
    JOIN dbo.ReturnItems ri ON ri.ReturnItemID=cs.ReturnItemID
    WHERE ri.DecisionStatus IN ('ApprovedFull','ApprovedPartial')
      AND ri.ApprovedRefundAmount>0
      AND cs.RunningCompletedAmount>=ri.ApprovedRefundAmount
    GROUP BY cs.ReturnItemID
), RefundByReturnItem AS
(
    SELECT ReturnItemID,
        SUM(CASE WHEN RefundStatus='Completed' THEN Amount ELSE 0 END)
            AS CompletedRefundAmount,
        SUM(CASE WHEN RefundStatus='Pending' THEN Amount ELSE 0 END)
            AS PendingRefundAmount,
        SUM(CASE WHEN RefundStatus='Failed' THEN Amount ELSE 0 END)
            AS FailedRefundAttemptAmount,
        MAX(CASE WHEN RefundStatus='Completed' THEN CompletedAt END)
            AS LastRefundCompletedAt
    FROM dbo.Refunds
    GROUP BY ReturnItemID
)
SELECT ri.ReturnItemID,rt.ReturnID,rt.OrderID,oi.ProductID,
    p.SKU,p.ProductName,c.CategoryName,o.SalesChannel,
    DATEFROMPARTS(YEAR(o.OrderDate),MONTH(o.OrderDate),1) AS OrderMonth,
    o.OrderStatus,rt.RequestedAt,rt.ReceivedAt,ri.Quantity,
    ri.ReturnReason,ri.InspectionResult,ri.DecisionStatus,
    ri.EligibleRefundAmount,ISNULL(ri.ApprovedRefundAmount,0)
        AS ApprovedRefundAmount,
    ri.DecidedAt,ISNULL(rf.CompletedRefundAmount,0)
        AS CompletedRefundAmount,
    ISNULL(rf.PendingRefundAmount,0) AS PendingRefundAmount,
    ISNULL(rf.FailedRefundAttemptAmount,0) AS FailedRefundAttemptAmount,
    rf.LastRefundCompletedAt,st.SettlementCompletedAt,
    CASE WHEN ri.DecidedAt IS NOT NULL
           AND st.SettlementCompletedAt IS NOT NULL
         THEN CAST(DATEDIFF_BIG(SECOND,ri.DecidedAt,
                  st.SettlementCompletedAt)/86400.0 AS decimal(20,8))
    END AS DaysDecisionToSettlement
INTO #ReturnItemFacts
FROM dbo.ReturnItems AS ri
JOIN dbo.Returns AS rt ON rt.ReturnID=ri.ReturnID
JOIN dbo.OrderItems AS oi ON oi.OrderItemID=ri.OrderItemID
JOIN dbo.Orders AS o ON o.OrderID=rt.OrderID
JOIN dbo.Products AS p ON p.ProductID=oi.ProductID
JOIN dbo.Categories AS c ON c.CategoryID=p.CategoryID
LEFT JOIN RefundByReturnItem AS rf ON rf.ReturnItemID=ri.ReturnItemID
LEFT JOIN Settlement st ON st.ReturnItemID=ri.ReturnItemID;

DECLARE @ShipSLAHours decimal(10,2)=48.00;
DECLARE @TransitSLAHours decimal(10,2)=72.00;
DECLARE @EndToEndSLAHours decimal(10,2)=120.00;
DECLARE @AnalysisAsOf datetime2(0);

/* A data-driven as-of timestamp keeps the demo reproducible after cloning.
   In a live dashboard, replace this value with SYSUTCDATETIME(). */
SELECT @AnalysisAsOf=MAX(EventAt)
FROM
(
    SELECT OrderDate AS EventAt FROM dbo.Orders
    UNION ALL SELECT ShippedAt FROM dbo.Orders WHERE ShippedAt IS NOT NULL
    UNION ALL SELECT DeliveredAt FROM dbo.Orders WHERE DeliveredAt IS NOT NULL
    UNION ALL SELECT CancelledAt FROM dbo.Orders WHERE CancelledAt IS NOT NULL
    UNION ALL SELECT ChangedAt FROM dbo.OrderStatusHistory
) AS events;

IF @AnalysisAsOf IS NULL
BEGIN
    THROW 50006, 'No order events are available for fulfillment analysis.', 1;
END;

DROP TABLE IF EXISTS #FulfillmentFacts;

/* Grain: one row per order. Durations use seconds/3600 so partial hours are
   retained; DATEDIFF(HOUR) alone would count crossed hour boundaries. */
SELECT o.OrderID,o.CustomerID,o.OrderDate,o.SalesChannel,o.OrderStatus,
    o.ShippedAt,o.DeliveredAt,o.CancelledAt,
    DATEFROMPARTS(YEAR(o.OrderDate),MONTH(o.OrderDate),1) AS OrderMonth,
    CAST(DATEDIFF_BIG(SECOND,o.OrderDate,o.ShippedAt)/3600.0
        AS decimal(20,8)) AS OrderToShipHours,
    CAST(DATEDIFF_BIG(SECOND,o.ShippedAt,o.DeliveredAt)/3600.0
        AS decimal(20,8)) AS ShipToDeliveryHours,
    CAST(DATEDIFF_BIG(SECOND,o.OrderDate,o.DeliveredAt)/3600.0
        AS decimal(20,8)) AS OrderToDeliveryHours,
    CASE WHEN o.ShippedAt IS NOT NULL
              AND DATEDIFF_BIG(SECOND,o.OrderDate,o.ShippedAt)/3600.0
                    >@ShipSLAHours THEN 1
         WHEN o.ShippedAt IS NOT NULL THEN 0 END AS MissedShipSLA,
    CASE WHEN o.DeliveredAt IS NOT NULL
              AND DATEDIFF_BIG(SECOND,o.ShippedAt,o.DeliveredAt)/3600.0
                    >@TransitSLAHours THEN 1
         WHEN o.DeliveredAt IS NOT NULL THEN 0 END AS MissedTransitSLA,
    CASE WHEN o.DeliveredAt IS NOT NULL
              AND DATEDIFF_BIG(SECOND,o.OrderDate,o.DeliveredAt)/3600.0
                    >@EndToEndSLAHours THEN 1
         WHEN o.DeliveredAt IS NOT NULL THEN 0 END AS MissedEndToEndSLA
INTO #FulfillmentFacts
FROM dbo.Orders AS o;


DROP TABLE IF EXISTS #AuditCustomerTotal;
SELECT SUM(NetRevenue) NetRevenue,COUNT_BIG(*) PurchaseCount INTO #AuditCustomerTotal FROM #CustomerPurchases;
DROP TABLE IF EXISTS #Reconciliation;
CREATE TABLE #Reconciliation(TestID varchar(80),Expected decimal(28,2),Actual decimal(28,2),Result varchar(20));
INSERT #Reconciliation(TestID,Expected,Actual) VALUES
('REC01_ProductNetVsRevenue', (SELECT SUM(NetMerchandiseSales) FROM #AuditRevenue),(SELECT SUM(NetMerchandiseSales) FROM #DeliveredItemFacts)),
('REC02_CustomerVsRevenue',(SELECT SUM(NetRevenue) FROM #AuditRevenue),(SELECT NetRevenue FROM #AuditCustomerTotal)),
('REC03_ItemRefundVsRevenue',(SELECT SUM(RefundedMerchandiseAmount) FROM #AuditRevenue),(SELECT SUM(RefundedMerchandiseAmount) FROM #DeliveredItemFacts)),
('REC05_OrderCount',(SELECT COUNT_BIG(*) FROM dbo.Orders WHERE OrderStatus='Delivered'),(SELECT SUM(DeliveredOrderCount) FROM #AuditRevenue)),
('REC06_CustomerOrderCount',(SELECT COUNT_BIG(*) FROM dbo.Orders WHERE OrderStatus='Delivered'),(SELECT PurchaseCount FROM #AuditCustomerTotal)),
('REC07_ItemSubtractionIdentity',(SELECT CAST(SUM(GrossMerchandiseSales) AS decimal(28,2))-CAST(SUM(RefundedMerchandiseAmount) AS decimal(28,2)) FROM #DeliveredItemFacts),(SELECT SUM(NetMerchandiseSales) FROM #DeliveredItemFacts)),
('REC08_RefundCashAcrossModules',(SELECT SUM(CompletedRefundAmount) FROM #AuditRevenue),(SELECT SUM(CompletedRefundAmount) FROM #ReturnItemFacts WHERE OrderStatus='Delivered')),
('REC09_ReturnModuleOrderCount',(SELECT COUNT_BIG(*) FROM dbo.Orders WHERE OrderStatus='Delivered'),(SELECT COUNT_BIG(*) FROM #DeliveredOrderFacts)),
('REC10_FulfillmentDeliveredCount',(SELECT COUNT_BIG(*) FROM dbo.Orders WHERE OrderStatus='Delivered'),(SELECT COUNT_BIG(*) FROM #FulfillmentFacts WHERE DeliveredAt IS NOT NULL)),
('REC11_ShippingOnce',(SELECT SUM(ShippingFee) FROM dbo.Orders WHERE OrderStatus='Delivered'),(SELECT SUM(ShippingRevenue) FROM #AuditRevenue)),
('REC12_COGS',(SELECT SUM(OriginalCOGS) FROM #DeliveredItemFacts),(SELECT SUM(OriginalCOGS) FROM #AuditRevenue));
-- Category sums derive from the production C item fact and must retain cents.
INSERT #Reconciliation(TestID,Expected,Actual)
SELECT 'REC13_CategoryAdditivity', (SELECT SUM(NetMerchandiseSales) FROM #DeliveredItemFacts),SUM(NetSales)
FROM (SELECT CategoryID,SUM(NetMerchandiseSales) NetSales FROM #DeliveredItemFacts GROUP BY CategoryID) c;
UPDATE #Reconciliation SET Result=CASE WHEN Expected=Actual THEN 'PASS' ELSE 'FAIL' END;
SELECT * FROM #Reconciliation ORDER BY TestID;
-- Do not throw yet: permit cohort diagnostics to emit before the final gate.
GO
SET NOCOUNT ON;

-- REQUIRED coverage assertion: do not infer extraction coverage from purchases.
-- Large seed: 2026-10-01T00:00:00 (documented exclusive UTC cutoff).
-- Small demo policy selected with user authorization: observe through August 2026.
-- For the large seed set the declaration below to 2026-10-01T00:00:00.
-- This is a retrospective snapshot report, not historical status reconstruction.
DECLARE @ObservationCutoffExclusive datetime2(0)='2026-09-01T00:00:00';
IF @ObservationCutoffExclusive IS NULL
BEGIN
 SELECT 'REC04_CohortRevenue' TestID,'Explicit coverage cutoff' Expected,'Not supplied' Actual,'BLOCKED' Result;
 THROW 53101,'Cohort reconciliation blocked: cutoff required. Earlier FAIL results remain failures.',1;
END;
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


INSERT #Reconciliation(TestID,Expected,Actual)
SELECT 'REC04_CohortRevenue',(SELECT NetRevenue FROM #AuditCustomerTotal),SUM(CohortNetRevenue) FROM #CohortRetention;
INSERT #Reconciliation(TestID,Expected,Actual)
SELECT 'REC14_M0Retention',0,COUNT_BIG(*) FROM #CohortRetention WHERE MonthIndex=0 AND RetentionRatePct<>100;
UPDATE #Reconciliation SET Result=CASE WHEN Expected=Actual THEN 'PASS' ELSE 'FAIL' END;
SELECT * FROM #Reconciliation ORDER BY TestID;
IF EXISTS(SELECT 1 FROM #Reconciliation WHERE Result='FAIL') THROW 53100,'Cross-module KPI mismatch.',1;
GO
