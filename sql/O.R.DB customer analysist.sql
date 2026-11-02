/* STEP 4.4: CUSTOMER ANALYSIS - SQL SERVER
   Database: OnlineRetailDB
   Read-only against permanent tables; temporary tables are session-local.
   Purchase = Delivered order, ordered by OrderDate then OrderID.
   New order = first Delivered order; subsequent purchases = Repeat.
   Fully refunded Delivered orders still count as purchases.
   Observed lifetime revenue is NOT predicted Customer Lifetime Value.
   Revenue excludes tax, includes shipping, and attributes completed refunds
   to the original order. All results describe the available dataset only.
*/
USE [OnlineRetailDB];
GO
SET NOCOUNT ON;

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

-- RESULT 1: Every customer, including customers without Delivered purchases.
;WITH CustomerMetrics AS
(
    SELECT c.CustomerID, c.FirstName, c.LastName, c.IsActive,
        c.CreatedAt AS RegisteredAt,
        COUNT(cp.OrderID) AS DeliveredOrderCount,
        MIN(cp.OrderDate) AS FirstPurchaseAt,
        MAX(cp.OrderDate) AS LastPurchaseAt,
        ISNULL(SUM(cp.NetRevenue),0) AS ObservedLifetimeNetRevenue,
        AVG(CAST(DATEDIFF_BIG(SECOND,cp.PreviousPurchaseAt,cp.OrderDate)
            AS decimal(20,4))/86400.0) AS AverageDaysBetweenPurchases
    FROM dbo.Customers AS c
    LEFT JOIN #CustomerPurchases AS cp ON cp.CustomerID=c.CustomerID
    GROUP BY c.CustomerID,c.FirstName,c.LastName,c.IsActive,c.CreatedAt
)
SELECT *,
    CASE WHEN DeliveredOrderCount=0 THEN 'No purchase'
         WHEN DeliveredOrderCount=1 THEN 'One-time buyer'
         ELSE 'Repeat buyer' END AS CustomerSegment,
    CAST(ObservedLifetimeNetRevenue/NULLIF(DeliveredOrderCount,0)
        AS decimal(18,2)) AS CustomerAOV,
    -- Non-buyers receive NULL rank instead of appearing as paying customers.
    CASE WHEN DeliveredOrderCount>0 THEN
        DENSE_RANK() OVER(ORDER BY
            CASE WHEN DeliveredOrderCount>0 THEN 1 ELSE 0 END DESC,
            ObservedLifetimeNetRevenue DESC)
        END AS RevenueRank
FROM CustomerMetrics
ORDER BY ObservedLifetimeNetRevenue DESC,CustomerID;

-- RESULT 2: Monthly order mix. Missing months are omitted, NOT zero-filled.
-- Customers can place both a New and a Repeat order in the same month.
;WITH MonthlyMix AS
(
    SELECT OrderMonth,SalesChannel,
        COUNT(*) AS DeliveredOrderCount,
        COUNT(DISTINCT CustomerID) AS PurchasingCustomerCount,
        SUM(CASE WHEN PurchaseNumber=1 THEN 1 ELSE 0 END) AS NewCustomerOrders,
        SUM(CASE WHEN PurchaseNumber>1 THEN 1 ELSE 0 END) AS RepeatCustomerOrders,
        SUM(CASE WHEN PurchaseNumber=1 THEN NetRevenue ELSE 0 END)
            AS NewCustomerRevenue,
        SUM(CASE WHEN PurchaseNumber>1 THEN NetRevenue ELSE 0 END)
            AS RepeatCustomerRevenue,
        SUM(NetRevenue) AS TotalNetRevenue
    FROM #CustomerPurchases
    GROUP BY OrderMonth,SalesChannel
)
SELECT *,
    CAST(100.0*RepeatCustomerOrders/NULLIF(DeliveredOrderCount,0)
        AS decimal(10,2)) AS RepeatOrderSharePct,
    CAST(100.0*RepeatCustomerRevenue/NULLIF(TotalNetRevenue,0)
        AS decimal(10,2)) AS RepeatRevenueSharePct,
    CAST(TotalNetRevenue/NULLIF(DeliveredOrderCount,0)
        AS decimal(18,2)) AS MonthlyAOV
FROM MonthlyMix
ORDER BY OrderMonth,SalesChannel;

-- RESULT 3: Purchase journey. Elapsed days use seconds, not date boundaries.
SELECT CustomerID,OrderID,OrderDate,SalesChannel,PurchaseNumber,
    CASE WHEN PurchaseNumber=1 THEN 'New' ELSE 'Repeat' END AS OrderBuyerType,
    NetRevenue,PreviousPurchaseAt,NextPurchaseAt,
    CAST(DATEDIFF_BIG(SECOND,PreviousPurchaseAt,OrderDate)/86400.0
        AS decimal(18,2)) AS DaysSincePreviousPurchase,
    CAST(DATEDIFF_BIG(SECOND,OrderDate,NextPurchaseAt)/86400.0
        AS decimal(18,2)) AS DaysUntilNextPurchase,
    CumulativeCustomerRevenue
FROM #CustomerPurchases
ORDER BY CustomerID,OrderDate,OrderID;

DROP TABLE IF EXISTS #CustomerPurchases;
GO

/* DEMO EXPECTATIONS:
   6 customers; 4 Delivered orders belonging to 4 customers.
   2 customers have no Delivered purchase; no customer has a Repeat purchase.
   Revenue: An=899.00, Binh=0.00, Chi=29.99, Dung=160.00.
   Total observed net revenue=1088.99 (shipping included, tax excluded).
   Empty repeat results reflect the small seed, not a SQL error.
   Limitations: no historical cutoff, acquisition costs, forecast, or complete
   lifetime history. This is retrospective revenue, not predictive CLV.
*/
