:ON ERROR EXIT
USE [OnlineRetailDB_Audit_small_Rebuild_20261012_02];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF CONVERT(nvarchar(128),SERVERPROPERTY('MachineName'))<>N'PHUCCOMPUTER'
 THROW 53910,'Unexpected server.',1;
IF DB_NAME()<>N'OnlineRetailDB_Audit_small_Rebuild_20261012_02'
 THROW 53911,'Only the previously authorized disposable small database is permitted.',1;
IF @@TRANCOUNT<>0 THROW 53912,'Use a fresh session without a transaction.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 EXEC(N'CREATE OR ALTER VIEW dbo.vw_RecentOrders
 AS
 SELECT o.OrderID,o.OrderDate,c.CustomerID,c.FirstName,c.LastName,
 SUM(oi.Quantity*oi.UnitPrice) AS OrderAmount
 FROM dbo.Customers c JOIN dbo.Orders o ON c.CustomerID=o.CustomerID
 JOIN dbo.OrderItems oi ON o.OrderID=oi.OrderID
 GROUP BY o.OrderID,o.OrderDate,c.CustomerID,c.FirstName,c.LastName;');
 EXEC(N'CREATE OR ALTER VIEW dbo.vw_CustomerOrders
 AS
 SELECT c.CustomerID,c.FirstName,c.LastName,
 COUNT(DISTINCT o.OrderID) AS TotalOrders,
 SUM(oi.Quantity*oi.UnitPrice) AS TotalAmount
 FROM dbo.Customers c JOIN dbo.Orders o ON c.CustomerID=o.CustomerID
 JOIN dbo.OrderItems oi ON o.OrderID=oi.OrderID
 GROUP BY c.CustomerID,c.FirstName,c.LastName;');
 CREATE TABLE #ViewResults(TestID varchar(80),Expected bigint,Actual bigint);
 CREATE TABLE #BeforeCustomer(CustomerID int PRIMARY KEY,TotalOrders int,TotalAmount decimal(38,2));
 EXEC(N'INSERT #BeforeCustomer SELECT CustomerID,TotalOrders,TotalAmount FROM dbo.vw_CustomerOrders;');
 INSERT #ViewResults SELECT 'VIEW04_CustomerOrderCountIsOrdersNotItems',8,SUM(CONVERT(bigint,TotalOrders)) FROM #BeforeCustomer;
 /* Dynamic binding prevents cached pre-existing view metadata being used. */
 CREATE TABLE #BeforeView(OrderID int PRIMARY KEY,OrderAmount decimal(38,2));
 EXEC(N'INSERT #BeforeView SELECT OrderID,OrderAmount FROM dbo.vw_RecentOrders;');
 INSERT #ViewResults SELECT 'VIEW01_AllSeedOrdersRepresented',8,COUNT_BIG(*) FROM #BeforeView;
 DECLARE @ProductID int=(SELECT MIN(ProductID) FROM dbo.OrderItems);
 UPDATE dbo.Products SET Price=Price+1.00 WHERE ProductID=@ProductID;
 IF @@ROWCOUNT<>1 THROW 53913,'Catalog-price test target missing.',1;
 CREATE TABLE #AfterView(OrderID int PRIMARY KEY,OrderAmount decimal(38,2));
 EXEC(N'INSERT #AfterView SELECT OrderID,OrderAmount FROM dbo.vw_RecentOrders;');
 CREATE TABLE #AfterCustomer(CustomerID int PRIMARY KEY,TotalOrders int,TotalAmount decimal(38,2));
 EXEC(N'INSERT #AfterCustomer SELECT CustomerID,TotalOrders,TotalAmount FROM dbo.vw_CustomerOrders;');
 INSERT #ViewResults SELECT 'VIEW05_CustomerHistoryUnaffectedByCatalogPrice',0,COUNT_BIG(*)
 FROM (SELECT * FROM #BeforeCustomer EXCEPT SELECT * FROM #AfterCustomer) differences;
 INSERT #ViewResults SELECT 'VIEW06_NoUnexpectedNewCustomerRows',0,COUNT_BIG(*)
 FROM (SELECT * FROM #AfterCustomer EXCEPT SELECT * FROM #BeforeCustomer) differences;
 INSERT #ViewResults SELECT 'VIEW02_CatalogPriceDoesNotChangeHistory',0,COUNT_BIG(*)
 FROM (SELECT * FROM #BeforeView EXCEPT SELECT * FROM #AfterView) differences;
 INSERT #ViewResults SELECT 'VIEW03_NoUnexpectedNewViewRows',0,COUNT_BIG(*)
 FROM (SELECT * FROM #AfterView EXCEPT SELECT * FROM #BeforeView) differences;
 SELECT TestID,Expected,Actual,CASE WHEN Expected=Actual THEN 'PASS' ELSE 'FAIL' END Result FROM #ViewResults;
 IF EXISTS(SELECT 1 FROM #ViewResults WHERE Expected<>Actual)
  THROW 53914,'Legacy view test failed.',1;
 ROLLBACK TRANSACTION;
 PRINT 'LEGACY_VIEW_PATCH_TEST_COMPLETE_ROLLED_BACK';
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
