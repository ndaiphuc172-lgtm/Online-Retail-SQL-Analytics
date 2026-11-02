/*=============================================================================
  PORTFOLIO PROJECT: ONLINE RETAIL ANALYTICS
  STEP 4.5 - RETURN AND REFUND PERFORMANCE

  SQL dialect : Microsoft SQL Server
  Database    : OnlineRetailDB

  OUTPUTS
  1. Monthly return/refund KPIs by order cohort and sales channel.
  2. Inspection and refund-decision outcomes.
  3. Return-reason analysis.
  4. Product return-risk ranking.

  BUSINESS RULES
  - Sales denominators include Delivered orders only.
  - A physical return requires Returns.ReceivedAt IS NOT NULL.
  - Only RefundStatus='Completed' is treated as money refunded.
  - Refund rates use tax-inclusive merchandise payable as denominator because
    Refunds.Amount includes refunded merchandise tax and excludes shipping.
  - Returns/refunds are attributed to the original order month (cohort view).
=============================================================================*/

USE [OnlineRetailDB];
GO
SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM dbo.Orders WHERE OrderStatus='Delivered')
BEGIN
    THROW 50005, 'No delivered orders are available for return analysis.', 1;
END;

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

/* RESULT 1: Monthly cohort KPIs, including zero-activity month/channel rows. */
DECLARE @StartMonth date=(SELECT MIN(OrderMonth) FROM #DeliveredOrderFacts);
DECLARE @EndMonth date=(SELECT MAX(OrderMonth) FROM #DeliveredOrderFacts);

;WITH MonthSpine AS
(
    SELECT @StartMonth AS OrderMonth
    UNION ALL
    SELECT DATEADD(MONTH,1,OrderMonth)
    FROM MonthSpine WHERE OrderMonth<@EndMonth
), Channels AS
(
    SELECT SalesChannel FROM (VALUES('Website'),('App')) v(SalesChannel)
), SalesMetrics AS
(
    SELECT OrderMonth,SalesChannel,COUNT(*) AS DeliveredOrderCount,
        SUM(UnitsSold) AS UnitsSold,
        SUM(MerchandisePayableAmount) AS MerchandisePayableAmount
    FROM #DeliveredOrderFacts
    GROUP BY OrderMonth,SalesChannel
), ReturnOrderFlags AS
(
    SELECT OrderID,OrderMonth,SalesChannel,
        1 AS HasReturnRequest,
        MAX(CASE WHEN ReceivedAt IS NOT NULL THEN 1 ELSE 0 END)
            AS HasReceivedReturn
    FROM #ReturnItemFacts
    WHERE OrderStatus='Delivered'
    GROUP BY OrderID,OrderMonth,SalesChannel
), ReturnOrderMetrics AS
(
    SELECT OrderMonth,SalesChannel,
        SUM(HasReturnRequest) AS OrdersWithReturnRequest,
        SUM(HasReceivedReturn) AS OrdersWithReceivedReturn
    FROM ReturnOrderFlags
    GROUP BY OrderMonth,SalesChannel
), ReturnItemMetrics AS
(
    SELECT OrderMonth,SalesChannel,
        SUM(CASE WHEN ReceivedAt IS NOT NULL THEN Quantity ELSE 0 END)
            AS ReceivedReturnedUnits,
        SUM(CASE WHEN DecisionStatus='ApprovedFull' THEN 1 ELSE 0 END)
            AS ApprovedFullItemCount,
        SUM(CASE WHEN DecisionStatus='ApprovedPartial' THEN 1 ELSE 0 END)
            AS ApprovedPartialItemCount,
        SUM(CASE WHEN DecisionStatus='Rejected' THEN 1 ELSE 0 END)
            AS RejectedItemCount,
        SUM(CASE WHEN DecisionStatus='Pending' THEN 1 ELSE 0 END)
            AS PendingDecisionItemCount,
        SUM(CompletedRefundAmount) AS CompletedRefundAmount
    FROM #ReturnItemFacts
    WHERE OrderStatus='Delivered'
    GROUP BY OrderMonth,SalesChannel
), CompleteSeries AS
(
    SELECT ms.OrderMonth,ch.SalesChannel,
        ISNULL(sm.DeliveredOrderCount,0) AS DeliveredOrderCount,
        ISNULL(sm.UnitsSold,0) AS UnitsSold,
        ISNULL(sm.MerchandisePayableAmount,0) AS MerchandisePayableAmount,
        ISNULL(rom.OrdersWithReturnRequest,0) AS OrdersWithReturnRequest,
        ISNULL(rom.OrdersWithReceivedReturn,0) AS OrdersWithReceivedReturn,
        ISNULL(rim.ReceivedReturnedUnits,0) AS ReceivedReturnedUnits,
        ISNULL(rim.ApprovedFullItemCount,0) AS ApprovedFullItemCount,
        ISNULL(rim.ApprovedPartialItemCount,0) AS ApprovedPartialItemCount,
        ISNULL(rim.RejectedItemCount,0) AS RejectedItemCount,
        ISNULL(rim.PendingDecisionItemCount,0) AS PendingDecisionItemCount,
        ISNULL(rim.CompletedRefundAmount,0) AS CompletedRefundAmount
    FROM MonthSpine ms CROSS JOIN Channels ch
    LEFT JOIN SalesMetrics sm ON sm.OrderMonth=ms.OrderMonth
        AND sm.SalesChannel=ch.SalesChannel
    LEFT JOIN ReturnOrderMetrics rom ON rom.OrderMonth=ms.OrderMonth
        AND rom.SalesChannel=ch.SalesChannel
    LEFT JOIN ReturnItemMetrics rim ON rim.OrderMonth=ms.OrderMonth
        AND rim.SalesChannel=ch.SalesChannel
), Rates AS
(
    SELECT *,
        CAST(100.0*OrdersWithReceivedReturn/NULLIF(DeliveredOrderCount,0)
            AS decimal(10,2)) AS OrderReturnRatePct,
        CAST(100.0*ReceivedReturnedUnits/NULLIF(UnitsSold,0)
            AS decimal(10,2)) AS UnitReturnRatePct,
        CAST(100.0*CompletedRefundAmount/NULLIF(MerchandisePayableAmount,0)
            AS decimal(10,2)) AS RefundToPayableRatePct
    FROM CompleteSeries
), Trends AS
(
    SELECT *,
        LAG(OrderReturnRatePct) OVER
            (PARTITION BY SalesChannel ORDER BY OrderMonth)
            AS PreviousMonthOrderReturnRatePct,
        SUM(CompletedRefundAmount) OVER
            (PARTITION BY SalesChannel,YEAR(OrderMonth) ORDER BY OrderMonth
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
            AS YTDCompletedRefundAmount
    FROM Rates
)
SELECT OrderMonth,SalesChannel,DeliveredOrderCount,UnitsSold,
    OrdersWithReturnRequest,OrdersWithReceivedReturn,ReceivedReturnedUnits,
    OrderReturnRatePct,UnitReturnRatePct,
    CAST(OrderReturnRatePct-PreviousMonthOrderReturnRatePct AS decimal(10,2))
        AS OrderReturnRateChangePoints,
    ApprovedFullItemCount,ApprovedPartialItemCount,RejectedItemCount,
    PendingDecisionItemCount,
    CAST(CompletedRefundAmount AS decimal(18,2)) AS CompletedRefundAmount,
    RefundToPayableRatePct,
    CAST(YTDCompletedRefundAmount AS decimal(18,2))
        AS YTDCompletedRefundAmount
FROM Trends
ORDER BY OrderMonth,SalesChannel
OPTION(MAXRECURSION 0);

/* RESULT 2: Decision, approval and settlement outcomes. */
SELECT COALESCE(InspectionResult,'Not inspected') AS InspectionResult,
    DecisionStatus,COUNT(*) AS ReturnItemCount,SUM(Quantity) AS ReturnedUnits,
    CAST(SUM(EligibleRefundAmount) AS decimal(18,2))
        AS EligibleRefundAmount,
    CAST(SUM(ApprovedRefundAmount) AS decimal(18,2))
        AS ApprovedRefundAmount,
    CAST(SUM(CompletedRefundAmount) AS decimal(18,2))
        AS CompletedRefundAmount,
    CAST(SUM(PendingRefundAmount) AS decimal(18,2)) AS PendingRefundAmount,
    CAST(SUM(FailedRefundAttemptAmount) AS decimal(18,2))
        AS FailedRefundAttemptAmount,
    CAST(100.0*SUM(ApprovedRefundAmount)/NULLIF(SUM(EligibleRefundAmount),0)
        AS decimal(10,2)) AS ApprovedVsEligiblePct,
    CAST(100.0*SUM(CompletedRefundAmount)/NULLIF(SUM(ApprovedRefundAmount),0)
        AS decimal(10,2)) AS SettlementCompletionPct,
    CAST(AVG(DaysDecisionToSettlement) AS decimal(18,2))
        AS AvgDaysDecisionToSettlement
FROM #ReturnItemFacts
GROUP BY COALESCE(InspectionResult,'Not inspected'),DecisionStatus
ORDER BY DecisionStatus,InspectionResult;

/* RESULT 3: Exact free-text reasons are grouped as entered. In production,
   add a normalized ReturnReasonCode dimension for stable reporting. */
;WITH ReasonMetrics AS
(
    SELECT ReturnReason,COUNT(*) AS ReturnItemCount,SUM(Quantity) AS ReturnedUnits,
        SUM(CompletedRefundAmount) AS CompletedRefundAmount
    FROM #ReturnItemFacts
    GROUP BY ReturnReason
), ReasonAnalytics AS
(
    SELECT *,SUM(ReturnItemCount) OVER() AS AllReturnItems,
        DENSE_RANK() OVER(ORDER BY ReturnItemCount DESC,ReturnedUnits DESC)
            AS ReasonFrequencyRank
    FROM ReasonMetrics
)
SELECT ReturnReason,ReturnItemCount,ReturnedUnits,
    CAST(100.0*ReturnItemCount/NULLIF(AllReturnItems,0) AS decimal(10,2))
        AS ShareOfReturnItemsPct,
    CAST(CompletedRefundAmount AS decimal(18,2)) AS CompletedRefundAmount,
    ReasonFrequencyRank
FROM ReasonAnalytics
ORDER BY ReasonFrequencyRank,ReturnReason;

/* RESULT 4: Product risk uses physical received units, including rejected
   returns. Products without Delivered sales have no meaningful return rate. */
;WITH ProductSales AS
(
    SELECT oi.ProductID,SUM(oi.Quantity) AS UnitsSold,
        SUM(oi.LinePayableAmount) AS MerchandisePayableAmount
    FROM dbo.Orders o JOIN dbo.OrderItems oi ON oi.OrderID=o.OrderID
    WHERE o.OrderStatus='Delivered'
    GROUP BY oi.ProductID
), ProductReturns AS
(
    SELECT ProductID,
        SUM(CASE WHEN ReceivedAt IS NOT NULL THEN Quantity ELSE 0 END)
            AS ReceivedReturnedUnits,
        SUM(CompletedRefundAmount) AS CompletedRefundAmount
    FROM #ReturnItemFacts
    WHERE OrderStatus='Delivered'
    GROUP BY ProductID
), ProductRates AS
(
    SELECT p.ProductID,p.SKU,p.ProductName,c.CategoryName,ps.UnitsSold,
        ISNULL(pr.ReceivedReturnedUnits,0) AS ReceivedReturnedUnits,
        ISNULL(pr.CompletedRefundAmount,0) AS CompletedRefundAmount,
        CAST(100.0*ISNULL(pr.ReceivedReturnedUnits,0)/NULLIF(ps.UnitsSold,0)
            AS decimal(10,2)) AS UnitReturnRatePct,
        CAST(100.0*ISNULL(pr.CompletedRefundAmount,0)
            /NULLIF(ps.MerchandisePayableAmount,0) AS decimal(10,2))
            AS RefundToPayableRatePct
    FROM ProductSales ps JOIN dbo.Products p ON p.ProductID=ps.ProductID
    JOIN dbo.Categories c ON c.CategoryID=p.CategoryID
    LEFT JOIN ProductReturns pr ON pr.ProductID=ps.ProductID
)
SELECT *,DENSE_RANK() OVER
    (ORDER BY UnitReturnRatePct DESC,ReceivedReturnedUnits DESC)
    AS ProductReturnRiskRank
FROM ProductRates
ORDER BY ProductReturnRiskRank,ProductID;

DROP TABLE IF EXISTS #ReturnItemFacts;
DROP TABLE IF EXISTS #DeliveredOrderFacts;
GO

/* DEMO EXPECTATIONS
   - February App: full refund, refund-to-payable rate 100%.
   - March Website: partial refund 38.88 / 64.80 = 60%.
   - August App: physical return exists but refund is rejected, so refund=0.
   - Shoes, backpack and earbuds each have a 100% physical unit return rate;
     the small sample size must be considered before business action.
*/
