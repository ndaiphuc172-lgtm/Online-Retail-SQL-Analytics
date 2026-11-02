/*=============================================================================
  PORTFOLIO PROJECT: ONLINE RETAIL ANALYTICS
  STEP 4.6 - FULFILLMENT AND DELIVERY PERFORMANCE

  SQL dialect : Microsoft SQL Server
  Database    : OnlineRetailDB

  DEMO SLA ASSUMPTIONS
  - Order to shipment : <= 48 hours
  - Shipment to delivery: <= 72 hours
  - Order to delivery : <= 120 hours

  OUTPUTS
  1. Monthly fulfillment KPIs by order cohort and channel.
  2. Overall channel comparison and performance ranking.
  3. Open-order backlog and SLA risk.
  4. Average time spent in each order status.
=============================================================================*/

USE [OnlineRetailDB];
GO
SET NOCOUNT ON;

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

/* RESULT 1: Monthly operational KPIs. Median is calculated by
   PERCENTILE_CONT, while conditional aggregates preserve all orders. */
;WITH MonthlyBase AS
(
    SELECT OrderMonth,SalesChannel,
        COUNT(*) AS TotalOrderCount,
        SUM(CASE WHEN ShippedAt IS NOT NULL THEN 1 ELSE 0 END)
            AS ShippedOrderCount,
        SUM(CASE WHEN DeliveredAt IS NOT NULL THEN 1 ELSE 0 END)
            AS DeliveredOrderCount,
        SUM(CASE WHEN OrderStatus='Cancelled' THEN 1 ELSE 0 END)
            AS CancelledOrderCount,
        AVG(OrderToShipHours) AS AvgOrderToShipHours,
        AVG(ShipToDeliveryHours) AS AvgShipToDeliveryHours,
        AVG(OrderToDeliveryHours) AS AvgOrderToDeliveryHours,
        SUM(ISNULL(MissedShipSLA,0)) AS MissedShipSLACount,
        SUM(ISNULL(MissedTransitSLA,0)) AS MissedTransitSLACount,
        SUM(ISNULL(MissedEndToEndSLA,0)) AS MissedEndToEndSLACount
    FROM #FulfillmentFacts
    GROUP BY OrderMonth,SalesChannel
), MedianRows AS
(
    SELECT OrderMonth,SalesChannel,
        PERCENTILE_CONT(0.5) WITHIN GROUP
            (ORDER BY OrderToDeliveryHours) OVER
            (PARTITION BY OrderMonth,SalesChannel)
            AS MedianOrderToDeliveryHours
    FROM #FulfillmentFacts
    WHERE DeliveredAt IS NOT NULL
), MonthlyMedians AS
(
    SELECT DISTINCT OrderMonth,SalesChannel,MedianOrderToDeliveryHours
    FROM MedianRows
), MonthlyKPI AS
(
    SELECT mb.*,mm.MedianOrderToDeliveryHours,
        CAST(100.0*mb.MissedShipSLACount/NULLIF(mb.ShippedOrderCount,0)
            AS decimal(10,2)) AS LateShipmentRatePct,
        CAST(100.0*mb.MissedTransitSLACount
            /NULLIF(mb.DeliveredOrderCount,0) AS decimal(10,2))
            AS LateTransitRatePct,
        CAST(100.0*mb.MissedEndToEndSLACount
            /NULLIF(mb.DeliveredOrderCount,0) AS decimal(10,2))
            AS LateEndToEndRatePct
    FROM MonthlyBase mb
    LEFT JOIN MonthlyMedians mm ON mm.OrderMonth=mb.OrderMonth
        AND mm.SalesChannel=mb.SalesChannel
), MonthlyTrend AS
(
    SELECT *,
        LAG(AvgOrderToDeliveryHours) OVER
            (PARTITION BY SalesChannel ORDER BY OrderMonth)
            AS PreviousReportedCohortAvgDeliveryHours
    FROM MonthlyKPI
)
SELECT OrderMonth,SalesChannel,TotalOrderCount,ShippedOrderCount,
    DeliveredOrderCount,CancelledOrderCount,
    CAST(AvgOrderToShipHours AS decimal(18,2)) AS AvgOrderToShipHours,
    CAST(AvgShipToDeliveryHours AS decimal(18,2)) AS AvgShipToDeliveryHours,
    CAST(AvgOrderToDeliveryHours AS decimal(18,2)) AS AvgOrderToDeliveryHours,
    CAST(MedianOrderToDeliveryHours AS decimal(18,2))
        AS MedianOrderToDeliveryHours,
    MissedShipSLACount,LateShipmentRatePct,
    MissedTransitSLACount,LateTransitRatePct,
    MissedEndToEndSLACount,LateEndToEndRatePct,
    CAST(AvgOrderToDeliveryHours-PreviousReportedCohortAvgDeliveryHours
        AS decimal(18,2)) AS ChangeVsPreviousReportedCohortHours
FROM MonthlyTrend
ORDER BY OrderMonth,SalesChannel;

/* RESULT 2: Channel performance and speed rank. A lower average delivery
   duration receives the better rank. */
;WITH ChannelBase AS
(
    SELECT SalesChannel,COUNT(*) AS TotalOrderCount,
        SUM(CASE WHEN DeliveredAt IS NOT NULL THEN 1 ELSE 0 END)
            AS DeliveredOrderCount,
        AVG(OrderToShipHours) AS AvgOrderToShipHours,
        AVG(ShipToDeliveryHours) AS AvgShipToDeliveryHours,
        AVG(OrderToDeliveryHours) AS AvgOrderToDeliveryHours,
        SUM(ISNULL(MissedEndToEndSLA,0)) AS MissedEndToEndSLACount
    FROM #FulfillmentFacts
    GROUP BY SalesChannel
), ChannelKPI AS
(
    SELECT *,CAST(100.0*MissedEndToEndSLACount
        /NULLIF(DeliveredOrderCount,0) AS decimal(10,2))
        AS LateEndToEndRatePct
    FROM ChannelBase
)
SELECT SalesChannel,TotalOrderCount,DeliveredOrderCount,
    CAST(AvgOrderToShipHours AS decimal(18,2)) AS AvgOrderToShipHours,
    CAST(AvgShipToDeliveryHours AS decimal(18,2)) AS AvgShipToDeliveryHours,
    CAST(AvgOrderToDeliveryHours AS decimal(18,2)) AS AvgOrderToDeliveryHours,
    LateEndToEndRatePct,
    DENSE_RANK() OVER
        (ORDER BY CASE WHEN AvgOrderToDeliveryHours IS NULL THEN 1 ELSE 0 END,
                  AvgOrderToDeliveryHours ASC)
        AS DeliverySpeedRank
FROM ChannelKPI
ORDER BY DeliverySpeedRank,SalesChannel;

/* RESULT 3: Open-order backlog as of the deterministic analysis timestamp. */
;WITH OpenOrders AS
(
    SELECT *,
        CAST(DATEDIFF_BIG(SECOND,OrderDate,@AnalysisAsOf)/3600.0
            AS decimal(20,8)) AS OpenAgeHours,
        CAST(DATEDIFF_BIG(SECOND,ShippedAt,@AnalysisAsOf)/3600.0
            AS decimal(20,8)) AS HoursWaitingAfterShipment
    FROM #FulfillmentFacts
    WHERE DeliveredAt IS NULL AND CancelledAt IS NULL
), Risk AS
(
    SELECT *,CASE
        WHEN ShippedAt IS NOT NULL
         AND DATEDIFF_BIG(SECOND,ShippedAt,@AnalysisAsOf)>@TransitSLAHours*3600
            THEN 'Delivery overdue'
        WHEN ShippedAt IS NULL
         AND DATEDIFF_BIG(SECOND,OrderDate,@AnalysisAsOf)>@ShipSLAHours*3600
            THEN 'Shipment overdue'
        ELSE 'Within SLA'
    END AS BacklogRisk,
    CASE
        WHEN ShippedAt IS NOT NULL
            THEN HoursWaitingAfterShipment-@TransitSLAHours
        ELSE OpenAgeHours-@ShipSLAHours
    END AS HoursBeyondRelevantSLA
    FROM OpenOrders
)
SELECT ROW_NUMBER() OVER
        (ORDER BY CASE WHEN HoursBeyondRelevantSLA>0 THEN 0 ELSE 1 END,
                  HoursBeyondRelevantSLA DESC,OrderDate,OrderID) AS BacklogPriority,
    OrderID,CustomerID,SalesChannel,OrderStatus,OrderDate,ShippedAt,
    @AnalysisAsOf AS AnalysisAsOf,
    CAST(OpenAgeHours AS decimal(18,2)) AS OpenAgeHours,
    CAST(HoursWaitingAfterShipment AS decimal(18,2)) AS HoursWaitingAfterShipment,
    BacklogRisk,
    CAST(CASE WHEN HoursBeyondRelevantSLA>0 THEN HoursBeyondRelevantSLA ELSE 0 END
        AS decimal(18,2)) AS OverdueHours
FROM Risk
ORDER BY BacklogPriority;

/* RESULT 4: Time spent in workflow statuses. LEAD locates the next event.
   Current Pending/Processing/Shipped stages end at @AnalysisAsOf; terminal
   Delivered/Cancelled stages are excluded from duration averages. */
;WITH StatusEvents AS
(
    SELECT osh.OrderStatusHistoryID,osh.OrderID,o.SalesChannel,
        osh.OrderStatus,osh.ChangedAt,
        LEAD(osh.ChangedAt) OVER
            (PARTITION BY osh.OrderID
             ORDER BY osh.ChangedAt,osh.OrderStatusHistoryID) AS NextChangedAt
    FROM dbo.OrderStatusHistory osh
    JOIN dbo.Orders o ON o.OrderID=osh.OrderID
), StatusDurations AS
(
    SELECT *,CASE
        WHEN NextChangedAt IS NOT NULL THEN NextChangedAt
        WHEN OrderStatus IN('Pending','Processing','Shipped')
            THEN @AnalysisAsOf
    END AS StageEndedAt
    FROM StatusEvents
), ValidDurations AS
(
    SELECT *,CAST(DATEDIFF_BIG(SECOND,ChangedAt,StageEndedAt)/3600.0
        AS decimal(20,8)) AS HoursInStatus
    FROM StatusDurations
    WHERE StageEndedAt IS NOT NULL
      AND OrderStatus IN ('Pending','Processing','Shipped')
)
SELECT SalesChannel,OrderStatus,COUNT(*) AS StageOccurrenceCount,
    SUM(CASE WHEN NextChangedAt IS NULL THEN 1 ELSE 0 END)
        AS CurrentlyOpenStageCount,
    CAST(AVG(HoursInStatus) AS decimal(18,2)) AS AvgHoursInStatus,
    CAST(MAX(HoursInStatus) AS decimal(18,2)) AS MaxHoursInStatus
FROM ValidDurations
GROUP BY SalesChannel,OrderStatus
ORDER BY SalesChannel,
    CASE OrderStatus WHEN 'Pending' THEN 1 WHEN 'Processing' THEN 2
         WHEN 'Shipped' THEN 3 ELSE 4 END;

DROP TABLE IF EXISTS #FulfillmentFacts;
GO

/* DEMO INTERPRETATION
   - Delivered demo orders satisfy the 48/72/120-hour SLA assumptions.
   - The May Shipped order appears as delivery overdue.
   - The June Processing and July Pending orders appear as shipment overdue.
   - @AnalysisAsOf is the latest order/status event in the demo, so results are
     reproducible. Replace it with SYSUTCDATETIME() for a live operation view.
*/
