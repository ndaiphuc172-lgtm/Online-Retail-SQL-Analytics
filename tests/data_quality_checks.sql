/* Read-only against permanent objects; temporary objects only.
   SQL Server 2016+, compatibility >=110. Run after metadata preflight.
   Expected/Actual are violation counts unless stated otherwise.
   No snapshot isolation setting is changed. Use a quiescent immutable snapshot
   for reproducible cross-statement totals. */
USE OnlineRetailDB;
GO
SET NOCOUNT ON;
IF DB_NAME()<>N'OnlineRetailDB' THROW 53000,'Wrong database.',1;
DROP TABLE IF EXISTS #AuditResults;
CREATE TABLE #AuditResults(TestID varchar(100),Expected nvarchar(200),Actual nvarchar(200),Result varchar(20));
IF OBJECT_ID(N'dbo.Categories',N'U') IS NULL OR OBJECT_ID(N'dbo.Customers',N'U') IS NULL OR OBJECT_ID(N'dbo.Products',N'U') IS NULL OR OBJECT_ID(N'dbo.Orders',N'U') IS NULL OR OBJECT_ID(N'dbo.OrderAddresses',N'U') IS NULL OR OBJECT_ID(N'dbo.OrderItems',N'U') IS NULL OR OBJECT_ID(N'dbo.Payments',N'U') IS NULL OR OBJECT_ID(N'dbo.OrderStatusHistory',N'U') IS NULL OR OBJECT_ID(N'dbo.Returns',N'U') IS NULL OR OBJECT_ID(N'dbo.ReturnItems',N'U') IS NULL OR OBJECT_ID(N'dbo.Refunds',N'U') IS NULL
BEGIN
 SELECT 'META01' TestID,'11 required tables' Expected,'Missing required tables' Actual,'BLOCKED' Result;
 THROW 53001,'Required schema missing.',1;
END;
INSERT #AuditResults SELECT 'DQ01_ConstraintsEnabledTrusted','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT name FROM sys.check_constraints WHERE is_disabled=1 OR is_not_trusted=1 UNION ALL SELECT name FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1) q) x;
INSERT #AuditResults SELECT 'DQ00_RequiredPrimaryKeys','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM sys.tables t WHERE SCHEMA_NAME(t.schema_id)='dbo' AND t.name IN ('Categories','Customers','Products','Orders','OrderAddresses','OrderItems','Payments','OrderStatusHistory','Returns','ReturnItems','Refunds') AND NOT EXISTS(SELECT 1 FROM sys.indexes i WHERE i.object_id=t.object_id AND i.is_primary_key=1 AND i.is_disabled=0)) x;
INSERT #AuditResults SELECT 'DQ02_ItemsAndShipping','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Orders o WHERE NOT EXISTS(SELECT 1 FROM dbo.OrderItems i WHERE i.OrderID=o.OrderID) OR NOT EXISTS(SELECT 1 FROM dbo.OrderAddresses a WHERE a.OrderID=o.OrderID AND a.AddressType='Shipping')) x;
INSERT #AuditResults SELECT 'DQ03_ItemAmounts','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.OrderItems WHERE Quantity<=0 OR UnitPrice<0 OR UnitCostAtOrder<0 OR LineDiscount<0 OR AllocatedOrderDiscount<0 OR TaxAmount<0 OR LineDiscount+AllocatedOrderDiscount>Quantity*UnitPrice OR NetMerchandiseAmount<>Quantity*UnitPrice-LineDiscount-AllocatedOrderDiscount OR LinePayableAmount<>NetMerchandiseAmount+TaxAmount) x;
INSERT #AuditResults SELECT 'DQ04_OrderStateDates','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Orders WHERE
CurrencyCode<>'USD' OR SalesChannel NOT IN ('Website','App') OR ShippingFee<0
OR ShippedAt<OrderDate OR DeliveredAt<ShippedAt OR CancelledAt<OrderDate
OR NOT ((OrderStatus IN ('Pending','Processing') AND ShippedAt IS NULL AND DeliveredAt IS NULL AND CancelledAt IS NULL)
 OR (OrderStatus='Shipped' AND ShippedAt IS NOT NULL AND DeliveredAt IS NULL AND CancelledAt IS NULL)
 OR (OrderStatus='Delivered' AND ShippedAt IS NOT NULL AND DeliveredAt IS NOT NULL AND CancelledAt IS NULL)
 OR (OrderStatus='Cancelled' AND CancelledAt IS NOT NULL AND ShippedAt IS NULL AND DeliveredAt IS NULL))) x;
INSERT #AuditResults SELECT 'DQ05_ReturnSameOrder','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.ReturnItems ri JOIN dbo.Returns r ON r.ReturnID=ri.ReturnID JOIN dbo.OrderItems i ON i.OrderItemID=ri.OrderItemID WHERE r.OrderID<>i.OrderID) x;
INSERT #AuditResults SELECT 'DQ06_ReturnReceiptDecision','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.ReturnItems ri JOIN dbo.Returns r ON r.ReturnID=ri.ReturnID WHERE r.ReceivedAt<r.RequestedAt OR (ri.DecisionStatus<>'Pending' AND (r.ReceivedAt IS NULL OR ri.DecidedAt IS NULL OR ri.DecidedAt<r.ReceivedAt))) x;
INSERT #AuditResults SELECT 'DQ07_ReservedReturnQuantity','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT i.OrderItemID FROM dbo.OrderItems i JOIN dbo.ReturnItems ri ON ri.OrderItemID=i.OrderItemID WHERE ri.DecisionStatus<>'Rejected' GROUP BY i.OrderItemID,i.Quantity HAVING SUM(CONVERT(bigint,ri.Quantity))>i.Quantity) q) x;
INSERT #AuditResults SELECT 'DQ08_ReturnAfterDelivery','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Returns r JOIN dbo.Orders o ON o.OrderID=r.OrderID WHERE o.OrderStatus<>'Delivered' OR o.DeliveredAt IS NULL OR r.RequestedAt<o.DeliveredAt OR NOT EXISTS(SELECT 1 FROM dbo.ReturnItems ri WHERE ri.ReturnID=r.ReturnID)) x;
INSERT #AuditResults SELECT 'DQ09_DecisionAmounts','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.ReturnItems WHERE Quantity<=0 OR EligibleRefundAmount<0 OR
 (DecisionStatus='Pending' AND (ApprovedRefundAmount IS NOT NULL OR DecidedAt IS NOT NULL OR InspectionResult IS NOT NULL)) OR
 (DecisionStatus='ApprovedFull' AND (ApprovedRefundAmount IS NULL OR ApprovedRefundAmount<>EligibleRefundAmount OR InspectionResult IS NULL OR InspectionResult<>'Compliant' OR DecidedAt IS NULL)) OR
 (DecisionStatus='ApprovedPartial' AND (ApprovedRefundAmount IS NULL OR ApprovedRefundAmount<=0 OR ApprovedRefundAmount>=EligibleRefundAmount OR InspectionResult IS NULL OR InspectionResult<>'NonCompliant' OR DecidedAt IS NULL OR NULLIF(LTRIM(RTRIM(DecisionReason)),'') IS NULL)) OR
 (DecisionStatus='Rejected' AND (ApprovedRefundAmount IS NULL OR ApprovedRefundAmount<>0 OR InspectionResult IS NULL OR InspectionResult<>'NonCompliant' OR DecidedAt IS NULL OR NULLIF(LTRIM(RTRIM(DecisionReason)),'') IS NULL))) x;
INSERT #AuditResults SELECT 'DQ10_RefundPaymentOrderAndChronology','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Refunds f JOIN dbo.Payments p ON p.PaymentID=f.PaymentID JOIN dbo.ReturnItems ri ON ri.ReturnItemID=f.ReturnItemID JOIN dbo.Returns r ON r.ReturnID=ri.ReturnID WHERE p.OrderID<>r.OrderID OR p.PaymentStatus<>'Completed' OR p.CompletedAt IS NULL OR ri.DecisionStatus NOT IN ('ApprovedFull','ApprovedPartial') OR ri.DecidedAt IS NULL OR f.CreatedAt<ri.DecidedAt OR f.CreatedAt<p.CompletedAt OR f.Amount<=0 OR f.CompletedAt<f.CreatedAt OR (f.RefundStatus='Completed' AND f.CompletedAt IS NULL) OR (f.RefundStatus IN ('Pending','Failed') AND f.CompletedAt IS NOT NULL)) x;
INSERT #AuditResults SELECT 'DQ11_RefundReservationCap','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT ri.ReturnItemID FROM dbo.ReturnItems ri JOIN dbo.Refunds f ON f.ReturnItemID=ri.ReturnItemID WHERE f.RefundStatus IN ('Pending','Completed') GROUP BY ri.ReturnItemID,ri.ApprovedRefundAmount HAVING ri.ApprovedRefundAmount IS NULL OR SUM(f.Amount)>ri.ApprovedRefundAmount) q) x;
INSERT #AuditResults SELECT 'DQ12_RefundPaymentReservationCap','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT p.PaymentID FROM dbo.Payments p JOIN dbo.Refunds f ON f.PaymentID=p.PaymentID WHERE f.RefundStatus IN ('Pending','Completed') GROUP BY p.PaymentID,p.Amount HAVING SUM(f.Amount)>p.Amount) q) x;
INSERT #AuditResults SELECT 'DQ13_PaymentChronology','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Payments p JOIN dbo.Orders o ON o.OrderID=p.OrderID WHERE p.Amount<=0 OR p.CreatedAt<o.OrderDate OR p.CompletedAt<p.CreatedAt OR (p.PaymentStatus='Completed' AND p.CompletedAt IS NULL) OR (p.PaymentStatus IN ('Pending','Failed') AND p.CompletedAt IS NOT NULL)) x;
INSERT #AuditResults SELECT 'DQ14_CollectedVsPayable','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Orders o JOIN (SELECT OrderID,CAST(SUM(LinePayableAmount) AS decimal(28,2)) Payable FROM dbo.OrderItems GROUP BY OrderID) i ON i.OrderID=o.OrderID LEFT JOIN (SELECT OrderID,SUM(Amount) Captured FROM dbo.Payments WHERE PaymentStatus='Completed' GROUP BY OrderID) p ON p.OrderID=o.OrderID WHERE COALESCE(p.Captured,0)>i.Payable+o.ShippingFee OR (o.OrderStatus='Delivered' AND COALESCE(p.Captured,0)<>i.Payable+o.ShippingFee)) x;
INSERT #AuditResults SELECT 'DQ15_ZeroPayableRefund','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Refunds f JOIN dbo.ReturnItems ri ON ri.ReturnItemID=f.ReturnItemID JOIN dbo.OrderItems i ON i.OrderItemID=ri.OrderItemID WHERE i.LinePayableAmount=0 AND f.RefundStatus IN ('Pending','Completed')) x;
INSERT #AuditResults SELECT 'DQ16_DuplicateHistoryEvent','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT OrderID,OrderStatus,ChangedAt FROM dbo.OrderStatusHistory GROUP BY OrderID,OrderStatus,ChangedAt HAVING COUNT_BIG(*)>1) q) x;
INSERT #AuditResults SELECT 'DQ17_LatestHistoryMatches','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Orders o LEFT JOIN (SELECT OrderID,OrderStatus,ROW_NUMBER() OVER(PARTITION BY OrderID ORDER BY ChangedAt DESC,OrderStatusHistoryID DESC) rn FROM dbo.OrderStatusHistory) h ON h.OrderID=o.OrderID AND h.rn=1 WHERE h.OrderID IS NULL OR h.OrderStatus<>o.OrderStatus) x;
INSERT #AuditResults SELECT 'DQ18_HistoryContradictions','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM
(SELECT OrderStatus,LAG(OrderStatus) OVER(PARTITION BY OrderID ORDER BY ChangedAt,OrderStatusHistoryID) prev FROM dbo.OrderStatusHistory) h
WHERE (prev IS NULL AND OrderStatus<>'Pending') OR (prev IS NOT NULL AND NOT
((prev='Pending' AND OrderStatus IN ('Processing','Cancelled')) OR
 (prev='Processing' AND OrderStatus IN ('Shipped','Cancelled')) OR
 (prev='Shipped' AND OrderStatus='Delivered')))) x;
INSERT #AuditResults SELECT 'DQ19_HistoryDates','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.OrderStatusHistory h JOIN dbo.Orders o ON o.OrderID=h.OrderID WHERE h.ChangedAt<o.OrderDate OR (h.OrderStatus='Pending' AND h.ChangedAt<>o.OrderDate) OR (h.OrderStatus='Shipped' AND (o.ShippedAt IS NULL OR h.ChangedAt<>o.ShippedAt)) OR (h.OrderStatus='Delivered' AND (o.DeliveredAt IS NULL OR h.ChangedAt<>o.DeliveredAt)) OR (h.OrderStatus='Cancelled' AND (o.CancelledAt IS NULL OR h.ChangedAt<>o.CancelledAt))) x;
INSERT #AuditResults SELECT 'DQ20_BusinessKey','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT PaymentProvider,TransactionReference FROM dbo.Payments WHERE TransactionReference IS NOT NULL GROUP BY PaymentProvider,TransactionReference HAVING COUNT_BIG(*)>1) q) x;
INSERT #AuditResults SELECT 'DQ21_BusinessKey','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT Provider,TransactionReference FROM dbo.Refunds WHERE TransactionReference IS NOT NULL GROUP BY Provider,TransactionReference HAVING COUNT_BIG(*)>1) q) x;
INSERT #AuditResults SELECT 'DQ22_BusinessKey','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT OrderID,LineNumber FROM dbo.OrderItems  GROUP BY OrderID,LineNumber HAVING COUNT_BIG(*)>1) q) x;
INSERT #AuditResults SELECT 'DQ23_BusinessKey','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT ReturnID,OrderItemID FROM dbo.ReturnItems  GROUP BY ReturnID,OrderItemID HAVING COUNT_BIG(*)>1) q) x;
INSERT #AuditResults SELECT 'DQ24_BusinessKey','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT SKU FROM dbo.Products  GROUP BY SKU HAVING COUNT_BIG(*)>1) q) x;
INSERT #AuditResults SELECT 'DQ25_Orphan_Products_CategoryID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Products c LEFT JOIN dbo.Categories p ON c.CategoryID=p.CategoryID WHERE p.CategoryID IS NULL) x;
INSERT #AuditResults SELECT 'DQ26_Orphan_Orders_CustomerID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Orders c LEFT JOIN dbo.Customers p ON c.CustomerID=p.CustomerID WHERE p.CustomerID IS NULL) x;
INSERT #AuditResults SELECT 'DQ27_Orphan_OrderAddresses_OrderID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.OrderAddresses c LEFT JOIN dbo.Orders p ON c.OrderID=p.OrderID WHERE p.OrderID IS NULL) x;
INSERT #AuditResults SELECT 'DQ28_Orphan_OrderItems_OrderID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.OrderItems c LEFT JOIN dbo.Orders p ON c.OrderID=p.OrderID WHERE p.OrderID IS NULL) x;
INSERT #AuditResults SELECT 'DQ29_Orphan_OrderItems_ProductID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.OrderItems c LEFT JOIN dbo.Products p ON c.ProductID=p.ProductID WHERE p.ProductID IS NULL) x;
INSERT #AuditResults SELECT 'DQ30_Orphan_Payments_OrderID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Payments c LEFT JOIN dbo.Orders p ON c.OrderID=p.OrderID WHERE p.OrderID IS NULL) x;
INSERT #AuditResults SELECT 'DQ31_Orphan_Returns_OrderID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Returns c LEFT JOIN dbo.Orders p ON c.OrderID=p.OrderID WHERE p.OrderID IS NULL) x;
INSERT #AuditResults SELECT 'DQ32_Orphan_ReturnItems_ReturnID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.ReturnItems c LEFT JOIN dbo.Returns p ON c.ReturnID=p.ReturnID WHERE p.ReturnID IS NULL) x;
INSERT #AuditResults SELECT 'DQ33_Orphan_ReturnItems_OrderItemID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.ReturnItems c LEFT JOIN dbo.OrderItems p ON c.OrderItemID=p.OrderItemID WHERE p.OrderItemID IS NULL) x;
INSERT #AuditResults SELECT 'DQ34_Orphan_Refunds_PaymentID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Refunds c LEFT JOIN dbo.Payments p ON c.PaymentID=p.PaymentID WHERE p.PaymentID IS NULL) x;
INSERT #AuditResults SELECT 'DQ35_Orphan_Refunds_ReturnItemID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.Refunds c LEFT JOIN dbo.ReturnItems p ON c.ReturnItemID=p.ReturnItemID WHERE p.ReturnItemID IS NULL) x;
INSERT #AuditResults SELECT 'DQ36_Orphan_OrderStatusHistory_OrderID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM dbo.OrderStatusHistory c LEFT JOIN dbo.Orders p ON c.OrderID=p.OrderID WHERE p.OrderID IS NULL) x;

;WITH Entitlement AS
(
 SELECT ri.ReturnItemID,ri.Quantity,ri.EligibleRefundAmount,i.Quantity SoldQuantity,i.LinePayableAmount,
 SUM(CONVERT(bigint,ri.Quantity)) OVER(PARTITION BY i.OrderItemID ORDER BY r.RequestedAt,r.ReturnID,ri.ReturnItemID ROWS UNBOUNDED PRECEDING) CQ
 FROM dbo.ReturnItems ri JOIN dbo.Returns r ON r.ReturnID=ri.ReturnID
 JOIN dbo.OrderItems i ON i.OrderItemID=ri.OrderItemID WHERE ri.DecisionStatus<>'Rejected'
)
INSERT #AuditResults
SELECT 'DQ37_EntitlementRounding','0',CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN COUNT_BIG(*)=0 THEN 'PASS' ELSE 'FAIL' END
FROM Entitlement WHERE EligibleRefundAmount<>
ROUND(LinePayableAmount*CQ/NULLIF(SoldQuantity,0),2)-ROUND(LinePayableAmount*(CQ-Quantity)/NULLIF(SoldQuantity,0),2);

-- Received rejected goods are physical receipt events; no unique-unit identity.
-- Report excess receipts as policy-review evidence, not a universal failed rule.
SELECT i.OrderItemID,i.Quantity SoldUnits,SUM(CONVERT(bigint,ri.Quantity)) ReceivedUnits
FROM dbo.OrderItems i JOIN dbo.ReturnItems ri ON ri.OrderItemID=i.OrderItemID
JOIN dbo.Returns r ON r.ReturnID=ri.ReturnID WHERE r.ReceivedAt IS NOT NULL
GROUP BY i.OrderItemID,i.Quantity HAVING SUM(CONVERT(bigint,ri.Quantity))>i.Quantity;

DROP TABLE IF EXISTS #ConstraintViolations;
CREATE TABLE #ConstraintViolations([Table] nvarchar(512),[Constraint] nvarchar(512),[Where] nvarchar(max));
INSERT #ConstraintViolations EXEC('DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS, ALL_ERRORMSGS');
INSERT #AuditResults SELECT 'DQ38_StoredConstraintViolations','0',CONVERT(nvarchar(200),COUNT_BIG(*)),
CASE WHEN COUNT_BIG(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM #ConstraintViolations;
-- Definitions are inventory for review, not proof of enforcement or equivalence.
SELECT t.name TableName,c.name ConstraintName,c.definition,c.is_disabled,c.is_not_trusted
FROM sys.check_constraints c JOIN sys.tables t ON t.object_id=c.parent_object_id;
SELECT t.name TableName,c.name DefaultName,c.definition FROM sys.default_constraints c JOIN sys.tables t ON t.object_id=c.parent_object_id;
SELECT t.name TableName,i.name IndexName,i.is_primary_key,i.is_unique,i.filter_definition
FROM sys.indexes i JOIN sys.tables t ON t.object_id=i.object_id WHERE i.is_unique=1;

DECLARE @SeedProfile varchar(10)='small'; -- set 'small' or 'large' ONLY for that unchanged fixture.
INSERT #AuditResults SELECT 'BASE_Categories',COALESCE(CONVERT(nvarchar(200),CASE @SeedProfile WHEN 'small' THEN 5 WHEN 'large' THEN 5 END),'Profile required'),CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN @SeedProfile IS NULL THEN 'NOT EXECUTED' WHEN COUNT_BIG(*)=CASE @SeedProfile WHEN 'small' THEN 5 WHEN 'large' THEN 5 END THEN 'PASS' ELSE 'FAIL' END FROM dbo.Categories;
INSERT #AuditResults SELECT 'BASE_Customers',COALESCE(CONVERT(nvarchar(200),CASE @SeedProfile WHEN 'small' THEN 6 WHEN 'large' THEN 1500 END),'Profile required'),CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN @SeedProfile IS NULL THEN 'NOT EXECUTED' WHEN COUNT_BIG(*)=CASE @SeedProfile WHEN 'small' THEN 6 WHEN 'large' THEN 1500 END THEN 'PASS' ELSE 'FAIL' END FROM dbo.Customers;
INSERT #AuditResults SELECT 'BASE_Products',COALESCE(CONVERT(nvarchar(200),CASE @SeedProfile WHEN 'small' THEN 8 WHEN 'large' THEN 50 END),'Profile required'),CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN @SeedProfile IS NULL THEN 'NOT EXECUTED' WHEN COUNT_BIG(*)=CASE @SeedProfile WHEN 'small' THEN 8 WHEN 'large' THEN 50 END THEN 'PASS' ELSE 'FAIL' END FROM dbo.Products;
INSERT #AuditResults SELECT 'BASE_Orders',COALESCE(CONVERT(nvarchar(200),CASE @SeedProfile WHEN 'small' THEN 8 WHEN 'large' THEN 8096 END),'Profile required'),CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN @SeedProfile IS NULL THEN 'NOT EXECUTED' WHEN COUNT_BIG(*)=CASE @SeedProfile WHEN 'small' THEN 8 WHEN 'large' THEN 8096 END THEN 'PASS' ELSE 'FAIL' END FROM dbo.Orders;
INSERT #AuditResults SELECT 'BASE_OrderAddresses',COALESCE(CONVERT(nvarchar(200),CASE @SeedProfile WHEN 'small' THEN 12 WHEN 'large' THEN 10120 END),'Profile required'),CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN @SeedProfile IS NULL THEN 'NOT EXECUTED' WHEN COUNT_BIG(*)=CASE @SeedProfile WHEN 'small' THEN 12 WHEN 'large' THEN 10120 END THEN 'PASS' ELSE 'FAIL' END FROM dbo.OrderAddresses;
INSERT #AuditResults SELECT 'BASE_OrderItems',COALESCE(CONVERT(nvarchar(200),CASE @SeedProfile WHEN 'small' THEN 9 WHEN 'large' THEN 15765 END),'Profile required'),CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN @SeedProfile IS NULL THEN 'NOT EXECUTED' WHEN COUNT_BIG(*)=CASE @SeedProfile WHEN 'small' THEN 9 WHEN 'large' THEN 15765 END THEN 'PASS' ELSE 'FAIL' END FROM dbo.OrderItems;
INSERT #AuditResults SELECT 'BASE_Payments',COALESCE(CONVERT(nvarchar(200),CASE @SeedProfile WHEN 'small' THEN 7 WHEN 'large' THEN 8584 END),'Profile required'),CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN @SeedProfile IS NULL THEN 'NOT EXECUTED' WHEN COUNT_BIG(*)=CASE @SeedProfile WHEN 'small' THEN 7 WHEN 'large' THEN 8584 END THEN 'PASS' ELSE 'FAIL' END FROM dbo.Payments;
INSERT #AuditResults SELECT 'BASE_OrderStatusHistory',COALESCE(CONVERT(nvarchar(200),CASE @SeedProfile WHEN 'small' THEN 24 WHEN 'large' THEN 31187 END),'Profile required'),CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN @SeedProfile IS NULL THEN 'NOT EXECUTED' WHEN COUNT_BIG(*)=CASE @SeedProfile WHEN 'small' THEN 24 WHEN 'large' THEN 31187 END THEN 'PASS' ELSE 'FAIL' END FROM dbo.OrderStatusHistory;
INSERT #AuditResults SELECT 'BASE_Returns',COALESCE(CONVERT(nvarchar(200),CASE @SeedProfile WHEN 'small' THEN 3 WHEN 'large' THEN 699 END),'Profile required'),CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN @SeedProfile IS NULL THEN 'NOT EXECUTED' WHEN COUNT_BIG(*)=CASE @SeedProfile WHEN 'small' THEN 3 WHEN 'large' THEN 699 END THEN 'PASS' ELSE 'FAIL' END FROM dbo.Returns;
INSERT #AuditResults SELECT 'BASE_ReturnItems',COALESCE(CONVERT(nvarchar(200),CASE @SeedProfile WHEN 'small' THEN 3 WHEN 'large' THEN 814 END),'Profile required'),CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN @SeedProfile IS NULL THEN 'NOT EXECUTED' WHEN COUNT_BIG(*)=CASE @SeedProfile WHEN 'small' THEN 3 WHEN 'large' THEN 814 END THEN 'PASS' ELSE 'FAIL' END FROM dbo.ReturnItems;
INSERT #AuditResults SELECT 'BASE_Refunds',COALESCE(CONVERT(nvarchar(200),CASE @SeedProfile WHEN 'small' THEN 2 WHEN 'large' THEN 827 END),'Profile required'),CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN @SeedProfile IS NULL THEN 'NOT EXECUTED' WHEN COUNT_BIG(*)=CASE @SeedProfile WHEN 'small' THEN 2 WHEN 'large' THEN 827 END THEN 'PASS' ELSE 'FAIL' END FROM dbo.Refunds;

SELECT * FROM #AuditResults ORDER BY TestID;
IF EXISTS(SELECT 1 FROM #AuditResults WHERE Result='FAIL') THROW 53002,'Validation failed; inspect result rows.',1;
