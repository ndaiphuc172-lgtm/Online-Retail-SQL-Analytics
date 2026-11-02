/* WRITE-DEPENDENT TEST: explicitly authorized disposable database only.
   Each test updates one row and rolls back; no constraints are disabled.
   Expected error codes are asserted. A missing target is a failure. */
USE OnlineRetailDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @AuthorizedDisposable bit=0; -- set to 1 only after explicit owner approval.
IF @AuthorizedDisposable<>1
BEGIN
 SELECT 'ENV02' TestID,'Explicit disposable authorization' Expected,'Not supplied' Actual,'BLOCKED' Result;
 THROW 53300,'Constraint-write tests require authorized disposable environment.',1;
END;
IF @@TRANCOUNT<>0 THROW 53301,'Fresh session required.',1;
DECLARE @Tests TABLE(TestID int PRIMARY KEY,TestName nvarchar(100),SqlText nvarchar(max),ExpectedError int);
INSERT INTO @Tests VALUES
(1,N'Quantity zero rejected',N'UPDATE dbo.OrderItems SET Quantity=0 WHERE OrderItemID=(SELECT MIN(OrderItemID) FROM dbo.OrderItems); IF @@ROWCOUNT<>1 THROW 52000, ''Test target missing'',1;',547),
(2,N'Shipment before order rejected',N'UPDATE dbo.Orders SET ShippedAt=DATEADD(DAY,-1,OrderDate) WHERE OrderID=(SELECT MIN(OrderID) FROM dbo.Orders WHERE OrderStatus=''Delivered''); IF @@ROWCOUNT<>1 THROW 52000, ''Test target missing'',1;',547),
(3,N'Delivered without shipment rejected',N'UPDATE dbo.Orders SET ShippedAt=NULL WHERE OrderID=(SELECT MIN(OrderID) FROM dbo.Orders WHERE OrderStatus=''Delivered''); IF @@ROWCOUNT<>1 THROW 52000, ''Test target missing'',1;',547),
(4,N'Unknown customer rejected',N'UPDATE dbo.Orders SET CustomerID=-2147483648 WHERE OrderID=(SELECT MIN(OrderID) FROM dbo.Orders); IF @@ROWCOUNT<>1 THROW 52000, ''Test target missing'',1;',547),
(5,N'Discount above merchandise rejected',N'UPDATE dbo.OrderItems SET LineDiscount=Quantity*UnitPrice+1 WHERE OrderItemID=(SELECT MIN(OrderItemID) FROM dbo.OrderItems); IF @@ROWCOUNT<>1 THROW 52000, ''Test target missing'',1;',547),
(6,N'Duplicate SKU rejected',N'UPDATE dbo.Products SET SKU=(SELECT SKU FROM dbo.Products WHERE ProductID=1) WHERE ProductID=2; IF @@ROWCOUNT<>1 THROW 52000, ''Test target missing'',1;',2627),
(7,N'Partial decision cannot approve full amount',N'UPDATE dbo.ReturnItems SET ApprovedRefundAmount=EligibleRefundAmount WHERE ReturnItemID=(SELECT MIN(ReturnItemID) FROM dbo.ReturnItems WHERE DecisionStatus=''ApprovedPartial''); IF @@ROWCOUNT<>1 THROW 52000, ''Test target missing'',1;',547);
DECLARE @Results TABLE(TestID int,TestName nvarchar(100),Result varchar(4),ActualError int,Detail nvarchar(4000));
DECLARE @TestID int=1,@TestName nvarchar(100),@Sql nvarchar(max),@Expected int;
WHILE @TestID<=7
BEGIN
    SELECT @TestName=TestName,@Sql=SqlText,@Expected=ExpectedError FROM @Tests WHERE TestID=@TestID;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC sys.sp_executesql @Sql;
        ROLLBACK TRANSACTION;
        INSERT INTO @Results VALUES(@TestID,@TestName,'FAIL',NULL,N'Invalid change was accepted; rolled back.');
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        INSERT INTO @Results VALUES(@TestID,@TestName,
            CASE WHEN ERROR_NUMBER()=@Expected OR (@Expected=2627 AND ERROR_NUMBER()=2601) THEN 'PASS' ELSE 'FAIL' END,
            ERROR_NUMBER(),ERROR_MESSAGE());
    END CATCH;
    SET @TestID+=1;
END;
SELECT r.TestID,r.TestName,t.ExpectedError AS Expected,r.ActualError AS Actual,r.Result,r.Detail FROM @Results r JOIN @Tests t ON t.TestID=r.TestID ORDER BY r.TestID;
IF EXISTS(SELECT 1 FROM @Results WHERE Result='FAIL')
    THROW 51011, 'Constraint regression failed. Inspect expected and actual errors.',1;


