/* Analyze monthly Delivered revenue and estimated profit by sales channel. */

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
/* Aggregate items per order to prevent duplicated revenue after joins. */
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

/* Aggregate completed refund cash per original order item. */

RefundCashByItem AS
(
    SELECT ri.OrderItemID,CAST(SUM(r.Amount) AS decimal(18,2)) AS CompletedRefundAmount
    FROM dbo.Refunds r
    JOIN dbo.ReturnItems ri ON ri.ReturnItemID=r.ReturnItemID
    WHERE r.RefundStatus='Completed'
    GROUP BY ri.OrderItemID
), CompletedRefundByItem AS
(
    /* Allocate merchandise refunds proportionally and round once per item using exact integer-cent arithmetic. */
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

/* Keep one row per Delivered order before monthly aggregation. */

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

/* Aggregate Delivered order facts by month and sales channel. */

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

/* Include every calendar month so LAG compares consecutive months. */
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

/* Calculate previous-month revenue and reset cumulative revenue each year. */
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

    /* Return NULL when a ratio has a zero denominator. */
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
FROM MetricsWithWindows
ORDER BY
    OrderMonth,
    SalesChannel
OPTION (MAXRECURSION 0);
GO

/* Analyze order status, payment failures and retry recovery. */

USE OnlineRetailDB;
GO

SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM dbo.Orders)
BEGIN
    THROW 50002, 'No orders are available for operational analysis.', 1;
END;

DECLARE @StartMonth date;
DECLARE @EndMonth   date;

SELECT
    @StartMonth = DATEFROMPARTS(YEAR(MIN(OrderDate)), MONTH(MIN(OrderDate)), 1),
    @EndMonth   = DATEFROMPARTS(YEAR(MAX(OrderDate)), MONTH(MAX(OrderDate)), 1)
FROM dbo.Orders;

/* Report monthly order and payment metrics by sales channel. */

;WITH
/* Aggregate payment attempts per order before joining order-level metrics. */
PaymentAttemptSummary AS
(
    SELECT
        p.OrderID,
        COUNT(*) AS PaymentAttemptCount,
        SUM(CASE WHEN p.PaymentStatus = 'Completed' THEN 1 ELSE 0 END)
            AS CompletedAttemptCount,
        SUM(CASE WHEN p.PaymentStatus = 'Failed' THEN 1 ELSE 0 END)
            AS FailedAttemptCount,
        SUM(CASE WHEN p.PaymentStatus = 'Pending' THEN 1 ELSE 0 END)
            AS PendingAttemptCount,
        MAX(CASE WHEN p.PaymentStatus = 'Completed' THEN 1 ELSE 0 END)
            AS HasCompletedPayment,
        MAX(CASE WHEN p.PaymentStatus = 'Failed' THEN 1 ELSE 0 END)
            AS HasFailedPayment,
        MIN(CASE WHEN p.PaymentStatus = 'Failed' THEN p.CreatedAt END)
            AS FirstFailedAt,
        MAX(CASE WHEN p.PaymentStatus = 'Completed' THEN p.CompletedAt END)
            AS LastCompletedAt
    FROM dbo.Payments AS p
    GROUP BY p.OrderID
),
OrderFacts AS
(
    SELECT
        o.OrderID,
        DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1) AS OrderMonth,
        o.SalesChannel,
        o.OrderStatus,
        ISNULL(pas.PaymentAttemptCount, 0)   AS PaymentAttemptCount,
        ISNULL(pas.CompletedAttemptCount, 0) AS CompletedAttemptCount,
        ISNULL(pas.FailedAttemptCount, 0)    AS FailedAttemptCount,
        ISNULL(pas.PendingAttemptCount, 0)   AS PendingAttemptCount,
        ISNULL(pas.HasCompletedPayment, 0)   AS HasCompletedPayment,
        ISNULL(pas.HasFailedPayment, 0)      AS HasFailedPayment,
        CASE
            WHEN pas.FirstFailedAt IS NOT NULL
             AND EXISTS
             (SELECT 1 FROM dbo.Payments retry
              WHERE retry.OrderID=o.OrderID
                AND retry.PaymentStatus='Completed'
                AND retry.CreatedAt>pas.FirstFailedAt
                AND retry.CompletedAt>=retry.CreatedAt)
            THEN 1 ELSE 0
        END AS IsRecoveredAfterFailure
    FROM dbo.Orders AS o
    LEFT JOIN PaymentAttemptSummary AS pas
        ON pas.OrderID = o.OrderID
),
MonthlyMetrics AS
(
    SELECT
        ofa.OrderMonth,
        ofa.SalesChannel,
        COUNT(*) AS TotalOrderCount,
        SUM(CASE WHEN ofa.OrderStatus = 'Pending' THEN 1 ELSE 0 END)
            AS PendingOrderCount,
        SUM(CASE WHEN ofa.OrderStatus = 'Processing' THEN 1 ELSE 0 END)
            AS ProcessingOrderCount,
        SUM(CASE WHEN ofa.OrderStatus = 'Shipped' THEN 1 ELSE 0 END)
            AS ShippedOrderCount,
        SUM(CASE WHEN ofa.OrderStatus = 'Delivered' THEN 1 ELSE 0 END)
            AS DeliveredOrderCount,
        SUM(CASE WHEN ofa.OrderStatus = 'Cancelled' THEN 1 ELSE 0 END)
            AS CancelledOrderCount,
        SUM(ofa.PaymentAttemptCount) AS PaymentAttemptCount,
        SUM(ofa.CompletedAttemptCount) AS CompletedAttemptCount,
        SUM(ofa.FailedAttemptCount) AS FailedAttemptCount,
        SUM(ofa.PendingAttemptCount) AS PendingAttemptCount,
        SUM(ofa.HasCompletedPayment) AS OrdersWithCompletedPayment,
        SUM(ofa.HasFailedPayment) AS OrdersAffectedByPaymentFailure,
        SUM(ofa.IsRecoveredAfterFailure) AS RecoveredOrderCount
    FROM OrderFacts AS ofa
    GROUP BY
        ofa.OrderMonth,
        ofa.SalesChannel
),
/* Preserve zero-activity months for consecutive monthly comparisons. */
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
        ISNULL(mm.TotalOrderCount, 0)                AS TotalOrderCount,
        ISNULL(mm.PendingOrderCount, 0)              AS PendingOrderCount,
        ISNULL(mm.ProcessingOrderCount, 0)           AS ProcessingOrderCount,
        ISNULL(mm.ShippedOrderCount, 0)              AS ShippedOrderCount,
        ISNULL(mm.DeliveredOrderCount, 0)            AS DeliveredOrderCount,
        ISNULL(mm.CancelledOrderCount, 0)            AS CancelledOrderCount,
        ISNULL(mm.PaymentAttemptCount, 0)            AS PaymentAttemptCount,
        ISNULL(mm.CompletedAttemptCount, 0)          AS CompletedAttemptCount,
        ISNULL(mm.FailedAttemptCount, 0)             AS FailedAttemptCount,
        ISNULL(mm.PendingAttemptCount, 0)            AS PendingAttemptCount,
        ISNULL(mm.OrdersWithCompletedPayment, 0)     AS OrdersWithCompletedPayment,
        ISNULL(mm.OrdersAffectedByPaymentFailure, 0) AS OrdersAffectedByPaymentFailure,
        ISNULL(mm.RecoveredOrderCount, 0)            AS RecoveredOrderCount
    FROM MonthSpine AS ms
    CROSS JOIN SalesChannels AS ch
    LEFT JOIN MonthlyMetrics AS mm
        ON  mm.OrderMonth = ms.OrderMonth
        AND mm.SalesChannel = ch.SalesChannel
),
MonthlyRates AS
(
    SELECT
        cms.*,
        CAST
        (
            100.0 * cms.CancelledOrderCount /
            NULLIF(cms.TotalOrderCount, 0)
            AS decimal(10,2)
        ) AS CancellationRatePct,
        CAST
        (
            100.0 * cms.FailedAttemptCount /
            NULLIF(cms.PaymentAttemptCount, 0)
            AS decimal(10,2)
        ) AS PaymentAttemptFailureRatePct,
        CAST
        (
            100.0 * cms.OrdersAffectedByPaymentFailure /
            NULLIF(cms.TotalOrderCount, 0)
            AS decimal(10,2)
        ) AS OrdersAffectedByFailurePct,
        CAST
        (
            100.0 * cms.RecoveredOrderCount /
            NULLIF(cms.OrdersAffectedByPaymentFailure, 0)
            AS decimal(10,2)
        ) AS RetryRecoveryRatePct
    FROM CompleteMonthlySeries AS cms
),
MetricsWithTrend AS
(
    SELECT
        mr.*,
        LAG(mr.CancellationRatePct) OVER
        (
            PARTITION BY mr.SalesChannel
            ORDER BY mr.OrderMonth
        ) AS PreviousMonthCancellationRatePct,
        SUM(mr.TotalOrderCount) OVER
        (
            PARTITION BY mr.SalesChannel, YEAR(mr.OrderMonth)
            ORDER BY mr.OrderMonth
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS YTDOrderCount
    FROM MonthlyRates AS mr
)
SELECT
    OrderMonth,
    SalesChannel,
    TotalOrderCount,
    PendingOrderCount,
    ProcessingOrderCount,
    ShippedOrderCount,
    DeliveredOrderCount,
    CancelledOrderCount,
    CancellationRatePct,
    CAST
    (
        CancellationRatePct - PreviousMonthCancellationRatePct
        AS decimal(10,2)
    ) AS CancellationRateChangePoints,
    PaymentAttemptCount,
    CompletedAttemptCount,
    FailedAttemptCount,
    PendingAttemptCount,
    PaymentAttemptFailureRatePct,
    OrdersWithCompletedPayment,
    OrdersAffectedByPaymentFailure,
    OrdersAffectedByFailurePct,
    RecoveredOrderCount,
    RetryRecoveryRatePct,
    YTDOrderCount
FROM MetricsWithTrend
ORDER BY
    OrderMonth,
    SalesChannel
OPTION (MAXRECURSION 0);

/* Measure stage reach using status history and timestamp-based inference. */

;WITH
HistoricalStatusFlags AS
(
    SELECT
        osh.OrderID,
        MAX(CASE WHEN osh.OrderStatus = 'Processing' THEN 1 ELSE 0 END)
            AS HasProcessingEvent,
        MAX(CASE WHEN osh.OrderStatus = 'Shipped' THEN 1 ELSE 0 END)
            AS HasShippedEvent,
        MAX(CASE WHEN osh.OrderStatus = 'Delivered' THEN 1 ELSE 0 END)
            AS HasDeliveredEvent,
        MAX(CASE WHEN osh.OrderStatus = 'Cancelled' THEN 1 ELSE 0 END)
            AS HasCancelledEvent
    FROM dbo.OrderStatusHistory AS osh
    GROUP BY osh.OrderID
),
OrderJourneyFlags AS
(
    SELECT
        o.OrderID,
        o.SalesChannel,
        1 AS ReachedPending,
        CASE
            WHEN ISNULL(hsf.HasProcessingEvent, 0) = 1
              OR o.OrderStatus IN ('Processing', 'Shipped', 'Delivered')
            THEN 1 ELSE 0
        END AS ReachedProcessing,
        CASE
            WHEN ISNULL(hsf.HasShippedEvent, 0) = 1
              OR o.ShippedAt IS NOT NULL
            THEN 1 ELSE 0
        END AS ReachedShipped,
        CASE
            WHEN ISNULL(hsf.HasDeliveredEvent, 0) = 1
              OR o.DeliveredAt IS NOT NULL
            THEN 1 ELSE 0
        END AS ReachedDelivered,
        CASE
            WHEN ISNULL(hsf.HasCancelledEvent, 0) = 1
              OR o.CancelledAt IS NOT NULL
              OR o.OrderStatus = 'Cancelled'
            THEN 1 ELSE 0
        END AS WasCancelled
    FROM dbo.Orders AS o
    LEFT JOIN HistoricalStatusFlags AS hsf
        ON hsf.OrderID = o.OrderID
),
ChannelFunnelSummary AS
(
    SELECT
        ojf.SalesChannel,
        COUNT(*) AS TotalOrderCount,
        SUM(ojf.ReachedPending) AS PendingStageCount,
        SUM(ojf.ReachedProcessing) AS ProcessingStageCount,
        SUM(ojf.ReachedShipped) AS ShippedStageCount,
        SUM(ojf.ReachedDelivered) AS DeliveredStageCount,
        SUM(ojf.WasCancelled) AS CancelledOrderCount
    FROM OrderJourneyFlags AS ojf
    GROUP BY ojf.SalesChannel
),
FunnelStages AS
(
    SELECT
        cfs.SalesChannel,
        cfs.TotalOrderCount,
        cfs.CancelledOrderCount,
        stage.StageNumber,
        stage.StageName,
        stage.StageOrderCount
    FROM ChannelFunnelSummary AS cfs
    CROSS APPLY
    (
        VALUES
            (1, 'Pending',    cfs.PendingStageCount),
            (2, 'Processing', cfs.ProcessingStageCount),
            (3, 'Shipped',    cfs.ShippedStageCount),
            (4, 'Delivered',  cfs.DeliveredStageCount)
    ) AS stage(StageNumber, StageName, StageOrderCount)
),
FunnelWithPreviousStage AS
(
    SELECT
        fs.*,
        LAG(fs.StageOrderCount) OVER
        (
            PARTITION BY fs.SalesChannel
            ORDER BY fs.StageNumber
        ) AS PreviousStageOrderCount
    FROM FunnelStages AS fs
)
SELECT
    SalesChannel,
    StageNumber,
    StageName,
    StageOrderCount,
    PreviousStageOrderCount,
    CASE
        WHEN PreviousStageOrderCount IS NULL THEN NULL
        ELSE PreviousStageOrderCount - StageOrderCount
    END AS DropOffFromPreviousStage,
    CAST
    (
        100.0 * StageOrderCount /
        NULLIF(PreviousStageOrderCount, 0)
        AS decimal(10,2)
    ) AS StageConversionRatePct,
    CAST
    (
        100.0 * StageOrderCount /
        NULLIF(TotalOrderCount, 0)
        AS decimal(10,2)
    ) AS ShareOfAllOrdersPct,
    CancelledOrderCount,
    CAST
    (
        100.0 * CancelledOrderCount /
        NULLIF(TotalOrderCount, 0)
        AS decimal(10,2)
    ) AS OverallCancellationRatePct
FROM FunnelWithPreviousStage
ORDER BY
    SalesChannel,
    StageNumber;

/* Rank payment methods by failure rate, preserving ties. */

;WITH
PaymentMethodMetrics AS
(
    SELECT
        p.PaymentMethod,
        COUNT(*) AS PaymentAttemptCount,
        COUNT(DISTINCT p.OrderID) AS DistinctOrderCount,
        SUM(CASE WHEN p.PaymentStatus = 'Completed' THEN 1 ELSE 0 END)
            AS CompletedAttemptCount,
        SUM(CASE WHEN p.PaymentStatus = 'Failed' THEN 1 ELSE 0 END)
            AS FailedAttemptCount,
        SUM(CASE WHEN p.PaymentStatus = 'Pending' THEN 1 ELSE 0 END)
            AS PendingAttemptCount,
        SUM(p.Amount) AS AttemptedPaymentAmount,
        SUM
        (
            CASE WHEN p.PaymentStatus = 'Completed' THEN p.Amount ELSE 0 END
        ) AS CompletedPaymentAmount
    FROM dbo.Payments AS p
    GROUP BY p.PaymentMethod
),
PaymentMethodRates AS
(
    SELECT
        pmm.*,
        CAST
        (
            100.0 * pmm.FailedAttemptCount /
            NULLIF(pmm.PaymentAttemptCount, 0)
            AS decimal(10,2)
        ) AS PaymentFailureRatePct,
        CAST
        (
            100.0 * pmm.CompletedAttemptCount /
            NULLIF(pmm.PaymentAttemptCount, 0)
            AS decimal(10,2)
        ) AS PaymentSuccessRatePct
    FROM PaymentMethodMetrics AS pmm
)
SELECT
    PaymentMethod,
    PaymentAttemptCount,
    DistinctOrderCount,
    CompletedAttemptCount,
    FailedAttemptCount,
    PendingAttemptCount,
    PaymentSuccessRatePct,
    PaymentFailureRatePct,
    CAST(AttemptedPaymentAmount AS decimal(18,2)) AS AttemptedPaymentAmount,
    CAST(CompletedPaymentAmount AS decimal(18,2)) AS CompletedPaymentAmount,
    DENSE_RANK() OVER
    (
        ORDER BY PaymentFailureRatePct DESC
    ) AS FailureRateRank
FROM PaymentMethodRates
ORDER BY
    FailureRateRank,
    PaymentMethod;
GO

/* Analyze product and category merchandise sales, profit and returns. */

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
    THROW 50003, 'No delivered orders are available for product analysis.', 1;
END;

/* Aggregate refunds and received returns separately before building Delivered item facts. */

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
    /* Allocate merchandise refunds proportionally and round once per item using exact integer-cent arithmetic. */
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

/* Retain all products, including those with no Delivered sales. */

;WITH
ProductMetrics AS
(
    SELECT
        p.ProductID,
        p.SKU,
        p.ProductName,
        p.CategoryID,
        c.CategoryName,
        p.IsActive,
        p.Stock AS CurrentStock,
        COUNT(DISTINCT dif.OrderID) AS DeliveredOrderCount,
        ISNULL(SUM(dif.UnitsSold), 0) AS UnitsSold,
        ISNULL(SUM(dif.UnitsReturned), 0) AS UnitsReturned,
        ISNULL(SUM(dif.GrossMerchandiseSales), 0) AS GrossMerchandiseSales,
        ISNULL(SUM(dif.RefundedMerchandiseAmount), 0)
            AS RefundedMerchandiseAmount,
        ISNULL(SUM(dif.NetMerchandiseSales), 0) AS NetMerchandiseSales,
        ISNULL(SUM(dif.OriginalCOGS), 0) AS OriginalCOGS,
        ISNULL(SUM(dif.EstimatedGrossProfit), 0) AS EstimatedGrossProfit
    FROM dbo.Products AS p
    INNER JOIN dbo.Categories AS c
        ON c.CategoryID = p.CategoryID
    LEFT JOIN #DeliveredItemFacts AS dif
        ON dif.ProductID = p.ProductID
    GROUP BY
        p.ProductID,
        p.SKU,
        p.ProductName,
        p.CategoryID,
        c.CategoryName,
        p.IsActive,
        p.Stock
),
ProductAnalytics AS
(
    SELECT
        pm.*,
        DENSE_RANK() OVER
        (
            ORDER BY pm.NetMerchandiseSales DESC
        ) AS OverallRevenueRank,
        DENSE_RANK() OVER
        (
            PARTITION BY pm.CategoryID
            ORDER BY pm.NetMerchandiseSales DESC
        ) AS RevenueRankWithinCategory,
        SUM(pm.NetMerchandiseSales) OVER () AS TotalPortfolioNetSales,
        SUM(pm.NetMerchandiseSales) OVER
        (
            PARTITION BY pm.CategoryID
        ) AS CategoryNetSales
    FROM ProductMetrics AS pm
)
SELECT
    ProductID,
    SKU,
    ProductName,
    CategoryName,
    IsActive,
    CurrentStock,
    DeliveredOrderCount,
    UnitsSold,
    UnitsReturned,
    CAST
    (
        100.0 * UnitsReturned / NULLIF(UnitsSold, 0)
        AS decimal(10,2)
    ) AS UnitReturnRatePct,
    CAST(GrossMerchandiseSales AS decimal(18,2))
        AS GrossMerchandiseSales,
    CAST(RefundedMerchandiseAmount AS decimal(18,2))
        AS RefundedMerchandiseAmount,
    CAST(NetMerchandiseSales AS decimal(18,2))
        AS NetMerchandiseSales,
    CAST(OriginalCOGS AS decimal(18,2)) AS OriginalCOGS,
    CAST(EstimatedGrossProfit AS decimal(18,2))
        AS EstimatedGrossProfit,
    CAST
    (
        100.0 * EstimatedGrossProfit /
        NULLIF(NetMerchandiseSales, 0)
        AS decimal(10,2)
    ) AS EstimatedGrossMarginPct,
    CAST
    (
        100.0 * NetMerchandiseSales /
        NULLIF(TotalPortfolioNetSales, 0)
        AS decimal(10,2)
    ) AS PortfolioRevenueContributionPct,
    CAST
    (
        100.0 * NetMerchandiseSales /
        NULLIF(CategoryNetSales, 0)
        AS decimal(10,2)
    ) AS CategoryRevenueContributionPct,
    OverallRevenueRank,
    RevenueRankWithinCategory
FROM ProductAnalytics
ORDER BY
    OverallRevenueRank,
    ProductID;

/* Report category metrics; order counts can overlap across categories. */

;WITH
CategoryMetrics AS
(
    SELECT
        c.CategoryID,
        c.CategoryName,
        COUNT(DISTINCT dif.ProductID) AS ProductsWithDeliveredSales,
        COUNT(DISTINCT dif.OrderID) AS DeliveredOrderCount,
        ISNULL(SUM(dif.UnitsSold), 0) AS UnitsSold,
        ISNULL(SUM(dif.UnitsReturned), 0) AS UnitsReturned,
        ISNULL(SUM(dif.GrossMerchandiseSales), 0) AS GrossMerchandiseSales,
        ISNULL(SUM(dif.RefundedMerchandiseAmount), 0)
            AS RefundedMerchandiseAmount,
        ISNULL(SUM(dif.NetMerchandiseSales), 0) AS NetMerchandiseSales,
        ISNULL(SUM(dif.OriginalCOGS), 0) AS OriginalCOGS,
        ISNULL(SUM(dif.EstimatedGrossProfit), 0) AS EstimatedGrossProfit
    FROM dbo.Categories AS c
    LEFT JOIN #DeliveredItemFacts AS dif
        ON dif.CategoryID = c.CategoryID
    GROUP BY
        c.CategoryID,
        c.CategoryName
),
CategoryAnalytics AS
(
    SELECT
        cm.*,
        DENSE_RANK() OVER
        (
            ORDER BY cm.NetMerchandiseSales DESC
        ) AS CategoryRevenueRank,
        SUM(cm.NetMerchandiseSales) OVER () AS TotalPortfolioNetSales
    FROM CategoryMetrics AS cm
)
SELECT
    CategoryID,
    CategoryName,
    ProductsWithDeliveredSales,
    DeliveredOrderCount,
    UnitsSold,
    UnitsReturned,
    CAST
    (
        100.0 * UnitsReturned / NULLIF(UnitsSold, 0)
        AS decimal(10,2)
    ) AS UnitReturnRatePct,
    CAST(GrossMerchandiseSales AS decimal(18,2))
        AS GrossMerchandiseSales,
    CAST(RefundedMerchandiseAmount AS decimal(18,2))
        AS RefundedMerchandiseAmount,
    CAST(NetMerchandiseSales AS decimal(18,2))
        AS NetMerchandiseSales,
    CAST(OriginalCOGS AS decimal(18,2)) AS OriginalCOGS,
    CAST(EstimatedGrossProfit AS decimal(18,2))
        AS EstimatedGrossProfit,
    CAST
    (
        100.0 * EstimatedGrossProfit /
        NULLIF(NetMerchandiseSales, 0)
        AS decimal(10,2)
    ) AS EstimatedGrossMarginPct,
    CAST
    (
        100.0 * NetMerchandiseSales /
        NULLIF(TotalPortfolioNetSales, 0)
        AS decimal(10,2)
    ) AS PortfolioRevenueContributionPct,
    CategoryRevenueRank
FROM CategoryAnalytics
ORDER BY
    CategoryRevenueRank,
    CategoryID;

/* Rank monthly products and calculate cumulative sales shares before filtering top ranks. */

;WITH
MonthlyProductMetrics AS
(
    SELECT
        dif.OrderMonth,
        dif.ProductID,
        dif.SKU,
        dif.ProductName,
        dif.CategoryName,
        SUM(dif.UnitsSold) AS UnitsSold,
        SUM(dif.UnitsReturned) AS UnitsReturned,
        SUM(dif.NetMerchandiseSales) AS NetMerchandiseSales,
        SUM(dif.EstimatedGrossProfit) AS EstimatedGrossProfit
    FROM #DeliveredItemFacts AS dif
    GROUP BY
        dif.OrderMonth,
        dif.ProductID,
        dif.SKU,
        dif.ProductName,
        dif.CategoryName
),
MonthlyProductAnalytics AS
(
    SELECT
        mpm.*,
        DENSE_RANK() OVER
        (
            PARTITION BY mpm.OrderMonth
            ORDER BY mpm.NetMerchandiseSales DESC
        ) AS MonthlyRevenueRank,
        SUM(mpm.NetMerchandiseSales) OVER
        (
            PARTITION BY mpm.OrderMonth
        ) AS MonthlyTotalNetSales,
        MIN(mpm.NetMerchandiseSales) OVER
            (PARTITION BY mpm.OrderMonth) AS MinimumProductNetSales,
        SUM(mpm.NetMerchandiseSales) OVER
        (
            PARTITION BY mpm.OrderMonth
            ORDER BY mpm.NetMerchandiseSales DESC, mpm.ProductID
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS CumulativeMonthlyNetSales
    FROM MonthlyProductMetrics AS mpm
)
SELECT
    OrderMonth,
    ProductID,
    SKU,
    ProductName,
    CategoryName,
    UnitsSold,
    UnitsReturned,
    CAST(NetMerchandiseSales AS decimal(18,2)) AS NetMerchandiseSales,
    CAST(EstimatedGrossProfit AS decimal(18,2)) AS EstimatedGrossProfit,
    CAST
    (
        100.0 * NetMerchandiseSales /
        NULLIF(MonthlyTotalNetSales, 0)
        AS decimal(10,2)
    ) AS MonthlyRevenueContributionPct,
    CAST
    (
        CASE WHEN MonthlyTotalNetSales>0 AND MinimumProductNetSales>=0
             THEN 100.0 * CumulativeMonthlyNetSales /
                  NULLIF(MonthlyTotalNetSales, 0) END
        AS decimal(10,2)
    ) AS CumulativeMonthlyRevenuePct,
    CASE WHEN MonthlyTotalNetSales>0 AND MinimumProductNetSales>=0
         THEN 'Valid' ELSE 'Undefined: zero/negative sales' END AS ParetoStatus,
    MonthlyRevenueRank
FROM MonthlyProductAnalytics
WHERE MonthlyRevenueRank <= 5
ORDER BY
    OrderMonth,
    MonthlyRevenueRank,
    ProductID;

DROP TABLE IF EXISTS #DeliveredItemFacts;
GO
