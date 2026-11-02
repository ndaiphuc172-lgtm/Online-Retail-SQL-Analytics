:ON ERROR EXIT
PRINT 'CLEAN_RUN_BODY_SHA256=2eff82effe7f9105d78240138883f6113463581fc210eb8d91b909acf80e3ada';
USE master;
GO
IF CONVERT(nvarchar(128),SERVERPROPERTY('MachineName'))<>N'PHUCCOMPUTER' THROW 53910,'Unexpected server; stop.',1;
SELECT CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) ServerName,CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion')) ProductVersion;
GO
IF DB_ID(N'OnlineRetailDB_Audit_small_Clean_20261012_03') IS NOT NULL THROW 53900,'Target exists; no changes permitted.',1;
GO
PRINT 'BEGIN_small_0';
GO
/* New database only. SQL Server 2016+; SQLCMD -b or run entire file.
   Creates permanent tables and indexes: authorized disposable environment only.
   If DDL fails, the newly created empty database may remain; no automatic DROP.
   UTC, USD, Website/App, one shipment/order. Shipping is not refundable.
   Row constraints do not enforce cross-table workflows; run data quality checks.
*/
USE master;
GO
SET NOCOUNT ON;
IF @@TRANCOUNT <> 0
    THROW 50000, 'Run setup in a fresh session without a transaction.', 1;
IF DB_ID(N'OnlineRetailDB_Audit_small_Clean_20261012_03') IS NOT NULL
    THROW 50001, 'Database already exists. Setup stopped without changes.', 1;
EXEC(N'CREATE DATABASE OnlineRetailDB_Audit_small_Clean_20261012_03');
EXEC(N'USE OnlineRetailDB_Audit_small_Clean_20261012_03;
SET XACT_ABORT ON;
BEGIN TRY
BEGIN TRANSACTION;

--table Categories
CREATE TABLE dbo.Categories (
 CategoryID int IDENTITY PRIMARY KEY,
 CategoryName nvarchar(100) NOT NULL UNIQUE,
 CONSTRAINT CK_Category_Name CHECK(LEN(LTRIM(RTRIM(CategoryName)))>0)
);
--table Customers
CREATE TABLE dbo.Customers (
 CustomerID int IDENTITY PRIMARY KEY,
 FirstName nvarchar(50) NOT NULL,
 LastName nvarchar(50) NOT NULL,
 Email nvarchar(150) NULL,
 Phone nvarchar(30) NULL,
 CountryCode char(2) NOT NULL,
 CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
 IsActive bit NOT NULL DEFAULT 1
);
-- Email is contact data, not customer identity: shared email is permitted.
CREATE TABLE dbo.Products (
 ProductID int IDENTITY PRIMARY KEY,
 SKU varchar(50) NOT NULL UNIQUE,
 ProductName nvarchar(150) NOT NULL,
 CategoryID int NOT NULL REFERENCES dbo.Categories(CategoryID),
 Price decimal(18,2) NOT NULL CHECK(Price>=0),
 Stock int NOT NULL DEFAULT 0 CHECK(Stock>=0),
 IsActive bit NOT NULL DEFAULT 1,
 CONSTRAINT CK_Product_SKU CHECK(LEN(LTRIM(RTRIM(SKU)))>0)
);

--table orders
CREATE TABLE dbo.Orders
(
    OrderID INT IDENTITY(1,1)
    --IDENTITY SQL Server tự tăng ID.
        CONSTRAINT PK_Orders PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATETIME2(0) NOT NULL
        CONSTRAINT DF_Orders_OrderDate
        DEFAULT SYSUTCDATETIME(),
    SalesChannel VARCHAR(10) NOT NULL,
    CurrencyCode CHAR(3) NOT NULL
        CONSTRAINT DF_Orders_CurrencyCode
        DEFAULT ''USD'',
    OrderStatus VARCHAR(15) NOT NULL
        CONSTRAINT DF_Orders_OrderStatus
        DEFAULT ''Pending'',
    ShippingFee DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_Orders_ShippingFee
        DEFAULT 0,
    ShippedAt DATETIME2(0) NULL,
    DeliveredAt DATETIME2(0) NULL,
    CancelledAt DATETIME2(0) NULL,
    CONSTRAINT FK_Orders_Customers
        FOREIGN KEY (CustomerID)
        REFERENCES dbo.Customers(CustomerID),
    CONSTRAINT CK_Orders_SalesChannel
        CHECK (SalesChannel IN (''Website'', ''App'')),
    CONSTRAINT CK_Orders_CurrencyCode
        CHECK (CurrencyCode = ''USD''),
    CONSTRAINT CK_Orders_OrderStatus
        CHECK
        (
            OrderStatus IN
            (
                ''Pending'',
                ''Processing'',
                ''Shipped'',
                ''Delivered'',
                ''Cancelled''
            )
        ),
    CONSTRAINT CK_Orders_ShippingFee
        CHECK (ShippingFee >= 0),
    CONSTRAINT CK_Orders_Timeline
        CHECK
        (
            (ShippedAt IS NULL OR ShippedAt >= OrderDate)
            AND
            (
                DeliveredAt IS NULL
                OR
                (
                    ShippedAt IS NOT NULL
                    AND DeliveredAt >= ShippedAt
                )
            )
            AND
            (
                CancelledAt IS NULL
                OR CancelledAt >= OrderDate
            )
        ),
    CONSTRAINT CK_Orders_StateDates
        CHECK
        (
            (
                OrderStatus IN (''Pending'', ''Processing'')
                AND ShippedAt IS NULL
                AND DeliveredAt IS NULL
                AND CancelledAt IS NULL
            )
            OR
            (
                OrderStatus = ''Shipped''
                AND ShippedAt IS NOT NULL
                AND DeliveredAt IS NULL
                AND CancelledAt IS NULL
            )
            OR
            (
                OrderStatus = ''Delivered''
                AND ShippedAt IS NOT NULL
                AND DeliveredAt IS NOT NULL
                AND CancelledAt IS NULL
            )
            OR
            (
                OrderStatus = ''Cancelled''
                AND CancelledAt IS NOT NULL
                AND ShippedAt IS NULL
                AND DeliveredAt IS NULL
            )
        )
);

-- Historical snapshot; not a link to a mutable customer address.
CREATE TABLE dbo.OrderAddresses (
 OrderID int NOT NULL REFERENCES dbo.Orders(OrderID),
 AddressType varchar(10) NOT NULL CHECK(AddressType IN (''Shipping'',''Billing'')),
 RecipientName nvarchar(150) NOT NULL,
 AddressLine nvarchar(255) NOT NULL,
 City nvarchar(100) NOT NULL,
 Region nvarchar(100) NULL,
 PostalCode nvarchar(20) NULL,
 CountryCode char(2) NOT NULL,
 PRIMARY KEY(OrderID,AddressType)
);
--table OrderItems
CREATE TABLE dbo.OrderItems (
 OrderItemID int IDENTITY PRIMARY KEY,
 OrderID int NOT NULL REFERENCES dbo.Orders(OrderID),
 LineNumber smallint NOT NULL CHECK(LineNumber>0),
 ProductID int NOT NULL REFERENCES dbo.Products(ProductID),
 Quantity int NOT NULL CHECK(Quantity>0),
 UnitPrice decimal(18,2) NOT NULL CHECK(UnitPrice>=0),
 UnitCostAtOrder decimal(18,2) NOT NULL CHECK(UnitCostAtOrder>=0),
 LineDiscount decimal(18,2) NOT NULL DEFAULT 0 CHECK(LineDiscount>=0),
 AllocatedOrderDiscount decimal(18,2) NOT NULL DEFAULT 0 CHECK(AllocatedOrderDiscount>=0),
 TaxAmount decimal(18,2) NOT NULL DEFAULT 0 CHECK(TaxAmount>=0),
 NetMerchandiseAmount AS CONVERT(decimal(18,2),Quantity*UnitPrice-LineDiscount-AllocatedOrderDiscount) PERSISTED,
 LinePayableAmount AS CONVERT(decimal(18,2),Quantity*UnitPrice-LineDiscount-AllocatedOrderDiscount+TaxAmount) PERSISTED,
 CONSTRAINT CK_Item_Discount CHECK(LineDiscount+AllocatedOrderDiscount<=Quantity*UnitPrice),
 CONSTRAINT UQ_Item_Line UNIQUE(OrderID,LineNumber)
);
-- One row per collection attempt. Completed collection stays Completed after refunds.
CREATE TABLE dbo.Payments (
 PaymentID int IDENTITY PRIMARY KEY,
 OrderID int NOT NULL REFERENCES dbo.Orders(OrderID),
 PaymentMethod varchar(20) NOT NULL CHECK(PaymentMethod IN (''Card'',''BankTransfer'',''EWallet'',''Cash'')),
 PaymentProvider varchar(50) NOT NULL,
 TransactionReference varchar(100) NULL,
 Amount decimal(18,2) NOT NULL CHECK(Amount>0),
 PaymentStatus varchar(12) NOT NULL DEFAULT ''Pending'' CHECK(PaymentStatus IN (''Pending'',''Completed'',''Failed'')),
 CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
 CompletedAt datetime2(0) NULL,
 CONSTRAINT CK_Payment_Date CHECK(
  (PaymentStatus=''Completed'' AND CompletedAt IS NOT NULL AND CompletedAt>=CreatedAt) OR
  (PaymentStatus IN (''Pending'',''Failed'') AND CompletedAt IS NULL))
);

CREATE UNIQUE INDEX UX_Payment_Reference ON dbo.Payments(PaymentProvider,TransactionReference)
 WHERE TransactionReference IS NOT NULL;

-- Header represents the physical return; inspection decision is per item.
CREATE TABLE dbo.Returns (
 ReturnID int IDENTITY PRIMARY KEY,
 OrderID int NOT NULL REFERENCES dbo.Orders(OrderID),
 RequestedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
 ReceivedAt datetime2(0) NULL,
 CONSTRAINT CK_Return_Receipt CHECK(ReceivedAt IS NULL OR ReceivedAt>=RequestedAt)
);

--table ReturnItems
CREATE TABLE dbo.ReturnItems (
    ReturnItemID int IDENTITY PRIMARY KEY,
    ReturnID int NOT NULL REFERENCES dbo.Returns(ReturnID),
    OrderItemID int NOT NULL REFERENCES dbo.OrderItems(OrderItemID),
    Quantity int NOT NULL CHECK(Quantity > 0),
    ReturnReason nvarchar(255) NOT NULL,

    -- Entitlement for these units after allocated discounts/tax, excluding shipping.
    EligibleRefundAmount decimal(18,2) NOT NULL CHECK(EligibleRefundAmount >= 0),

    InspectionResult varchar(15) NULL
        CHECK(InspectionResult IN (''Compliant'', ''NonCompliant'')),

    DecisionStatus varchar(15) NOT NULL
        DEFAULT ''Pending''
        CHECK(DecisionStatus IN (''Pending'', ''ApprovedFull'', ''ApprovedPartial'', ''Rejected'')),

    ApprovedRefundAmount decimal(18,2) NULL,
    DecidedAt datetime2(0) NULL,
    DecisionReason nvarchar(255) NULL,

    CONSTRAINT UQ_ReturnItem UNIQUE(ReturnID, OrderItemID),

    CONSTRAINT CK_ReturnItem_Decision CHECK(
        (DecisionStatus = ''Pending''
            AND InspectionResult IS NULL
            AND ApprovedRefundAmount IS NULL
            AND DecidedAt IS NULL)

        OR

        (DecisionStatus = ''ApprovedFull''
            AND InspectionResult IS NOT NULL
            AND InspectionResult = ''Compliant''
            AND DecidedAt IS NOT NULL
            AND ApprovedRefundAmount IS NOT NULL
            AND ApprovedRefundAmount = EligibleRefundAmount)

        OR

        (DecisionStatus = ''ApprovedPartial''
            AND InspectionResult IS NOT NULL
            AND InspectionResult = ''NonCompliant''
            AND DecidedAt IS NOT NULL
            AND ApprovedRefundAmount IS NOT NULL
            AND ApprovedRefundAmount > 0
            AND ApprovedRefundAmount < EligibleRefundAmount
            AND DecisionReason IS NOT NULL
            AND LEN(LTRIM(RTRIM(DecisionReason))) > 0)

        OR

        (DecisionStatus = ''Rejected''
            AND InspectionResult IS NOT NULL
            AND InspectionResult = ''NonCompliant''
            AND DecidedAt IS NOT NULL
            AND ApprovedRefundAmount IS NOT NULL
            AND ApprovedRefundAmount = 0
            AND DecisionReason IS NOT NULL
            AND LEN(LTRIM(RTRIM(DecisionReason))) > 0)
    )
);

-- One row per refund attempt against a payment and an approved return item.
-- Split a refund across payments using multiple rows. Failed attempts do not
-- consume approval; Pending and Completed attempts reserve approved amount.

CREATE TABLE dbo.Refunds (
    RefundID int IDENTITY PRIMARY KEY,
    ReturnItemID int NOT NULL REFERENCES dbo.ReturnItems(ReturnItemID),
    PaymentID int NOT NULL REFERENCES dbo.Payments(PaymentID),
    Amount decimal(18,2) NOT NULL CHECK(Amount > 0),

    RefundStatus varchar(12) NOT NULL
        DEFAULT ''Pending''
        CHECK(RefundStatus IN (''Pending'', ''Completed'', ''Failed'')),

    Provider varchar(50) NOT NULL,
    TransactionReference varchar(100) NULL,
    CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CompletedAt datetime2(0) NULL,

    CONSTRAINT CK_Refund_Date CHECK(
        (RefundStatus = ''Completed''
            AND CompletedAt IS NOT NULL
            AND CompletedAt >= CreatedAt)
        OR
        (RefundStatus IN (''Pending'', ''Failed'')
            AND CompletedAt IS NULL)
    )
);

CREATE UNIQUE INDEX UX_Refund_Reference
ON dbo.Refunds(Provider, TransactionReference)
WHERE TransactionReference IS NOT NULL;

CREATE TABLE dbo.OrderStatusHistory (
    OrderStatusHistoryID bigint IDENTITY PRIMARY KEY,
    OrderID int NOT NULL REFERENCES dbo.Orders(OrderID),

    OrderStatus varchar(15) NOT NULL
        CHECK(OrderStatus IN (
            ''Pending'',
            ''Processing'',
            ''Shipped'',
            ''Delivered'',
            ''Cancelled''
        )),

    ChangedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    ChangedBy nvarchar(128) NOT NULL,
    ChangeReason nvarchar(255) NULL
);

CREATE INDEX IX_Products_Category ON dbo.Products(CategoryID);
CREATE INDEX IX_Orders_Customer_Date ON dbo.Orders(CustomerID,OrderDate);
CREATE INDEX IX_Orders_Date ON dbo.Orders(OrderDate);
-- UQ_Item_Line already supports OrderID lookups.
CREATE INDEX IX_Items_Product ON dbo.OrderItems(ProductID);
CREATE INDEX IX_Payments_Order ON dbo.Payments(OrderID);
CREATE INDEX IX_Returns_Order ON dbo.Returns(OrderID);
CREATE INDEX IX_ReturnItems_Item ON dbo.ReturnItems(OrderItemID);
CREATE INDEX IX_Refunds_ReturnItem ON dbo.Refunds(ReturnItemID);
CREATE INDEX IX_Refunds_Payment ON dbo.Refunds(PaymentID);
CREATE INDEX IX_History_Order_Date ON dbo.OrderStatusHistory(OrderID,ChangedAt);
COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;


SELECT name AS TableName FROM sys.tables ORDER BY name;');

GO
PRINT 'END_small_0';
GO
SELECT name,compatibility_level,state_desc FROM sys.databases WHERE name=N'OnlineRetailDB_Audit_small_Clean_20261012_03';
GO
PRINT 'BEGIN_small_1';
GO
USE OnlineRetailDB_Audit_small_Clean_20261012_03;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/*
    Online Retail Portfolio - Small Demo Seed
    Purpose:
      - Lightweight dataset for GitHub reviewers to clone and run quickly.
      - Shows the core business flow: orders, payments, cancellation, delivery,
        returns, full refund, partial refund, rejection, and pending states.

    Recommended order:
      1. Run OnlineRetail Create tb.sql
      2. Run this file on an empty OnlineRetailDB_Audit_small_Clean_20261012_03

    Notes:
      - This file intentionally avoids DELETE/TRUNCATE so reviewers do not
        accidentally remove existing work.
      - Full analytical volume should live in a separate optional seed file.
*/

IF DB_NAME() <> N'OnlineRetailDB_Audit_small_Clean_20261012_03'
    THROW 51000, 'Run this script inside OnlineRetailDB_Audit_small_Clean_20261012_03.', 1;

IF @@TRANCOUNT <> 0
    THROW 51003, 'Run seed in a fresh session without a transaction.', 1;

BEGIN TRY
    BEGIN TRAN;
    IF EXISTS (SELECT 1 FROM dbo.Categories WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Categories is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Customers WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Customers is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Products WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Products is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Orders WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Orders is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM dbo.OrderAddresses WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'OrderAddresses is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM dbo.OrderItems WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'OrderItems is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Payments WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Payments is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM dbo.OrderStatusHistory WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'OrderStatusHistory is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Returns WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Returns is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM dbo.ReturnItems WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'ReturnItems is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Refunds WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Refunds is not empty. Seed stopped.', 1;

    DECLARE
        @CatElectronics int,
        @CatFashion int,
        @CatHome int,
        @CatSports int,
        @CatBooks int,
        @CustomerAn int,
        @CustomerBinh int,
        @CustomerChi int,
        @CustomerDung int,
        @CustomerEva int,
        @CustomerFrank int,
        @ProdLaptop int,
        @ProdEarbuds int,
        @ProdShoes int,
        @ProdBackpack int,
        @ProdCoffeeMaker int,
        @ProdYogaMat int,
        @ProdNovel int,
        @ProdPhoneCase int,
        @Order1 int,
        @Order2 int,
        @Order3 int,
        @Order4 int,
        @Order5 int,
        @Order6 int,
        @Order7 int,
        @Order8 int,
        @ItemOrder2Shoes int,
        @ItemOrder3Backpack int,
        @ItemOrder8Earbuds int,
        @PaymentOrder1 int,
        @PaymentOrder2 int,
        @PaymentOrder3 int,
        @PaymentOrder5 int,
        @PaymentOrder8 int,
        @ReturnOrder2 int,
        @ReturnOrder3 int,
        @ReturnOrder8 int,
        @ReturnItemOrder2 int,
        @ReturnItemOrder3 int,
        @ReturnItemOrder8 int;

    INSERT dbo.Categories (CategoryName)
    VALUES
        (N'Electronics'),
        (N'Fashion'),
        (N'Home & Kitchen'),
        (N'Sports'),
        (N'Books');

    SELECT @CatElectronics = CategoryID FROM dbo.Categories WHERE CategoryName = N'Electronics';
    SELECT @CatFashion = CategoryID FROM dbo.Categories WHERE CategoryName = N'Fashion';
    SELECT @CatHome = CategoryID FROM dbo.Categories WHERE CategoryName = N'Home & Kitchen';
    SELECT @CatSports = CategoryID FROM dbo.Categories WHERE CategoryName = N'Sports';
    SELECT @CatBooks = CategoryID FROM dbo.Categories WHERE CategoryName = N'Books';

    INSERT dbo.Customers (FirstName, LastName, Email, Phone, CountryCode, CreatedAt, IsActive)
    VALUES (N'An', N'Nguyen', N'an.nguyen@example.com', N'+12025550101', 'US', '2025-01-05T09:15:00', 1);
    SET @CustomerAn = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Customers (FirstName, LastName, Email, Phone, CountryCode, CreatedAt, IsActive)
    VALUES (N'Binh', N'Tran', N'family@example.com', NULL, 'US', '2025-02-12T11:30:00', 1);
    SET @CustomerBinh = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Customers (FirstName, LastName, Email, Phone, CountryCode, CreatedAt, IsActive)
    VALUES (N'Chi', N'Le', NULL, N'+12025550103', 'US', '2025-03-18T14:00:00', 1);
    SET @CustomerChi = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Customers (FirstName, LastName, Email, Phone, CountryCode, CreatedAt, IsActive)
    VALUES (N'Dung', N'Pham', N'family@example.com', N'+12025550104', 'US', '2025-05-01T08:45:00', 1);
    SET @CustomerDung = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Customers (FirstName, LastName, Email, Phone, CountryCode, CreatedAt, IsActive)
    VALUES (N'Eva', N'Miller', N'eva.miller@example.com', N'+12025550105', 'US', '2025-09-21T18:20:00', 0);
    SET @CustomerEva = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Customers (FirstName, LastName, Email, Phone, CountryCode, CreatedAt, IsActive)
    VALUES (N'Frank', N'Wilson', N'frank.wilson@example.com', N'+12025550106', 'US', '2026-01-10T10:10:00', 1);
    SET @CustomerFrank = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Products (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('EL-LAP-001', N'Everyday Laptop 14 inch', @CatElectronics, 899.00, 18, 1);
    SET @ProdLaptop = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Products (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('EL-EAR-002', N'Wireless Earbuds', @CatElectronics, 120.00, 75, 1);
    SET @ProdEarbuds = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Products (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('FA-SHO-003', N'Running Shoes', @CatFashion, 80.00, 42, 1);
    SET @ProdShoes = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Products (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('FA-BAG-004', N'City Backpack', @CatFashion, 60.00, 60, 1);
    SET @ProdBackpack = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Products (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('HK-COF-005', N'Compact Coffee Maker', @CatHome, 95.00, 25, 1);
    SET @ProdCoffeeMaker = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Products (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('SP-YOG-006', N'Yoga Mat', @CatSports, 30.00, 80, 1);
    SET @ProdYogaMat = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Products (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('BK-NOV-007', N'Weekend Novel', @CatBooks, 20.00, 100, 1);
    SET @ProdNovel = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Products (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('EL-CAS-008', N'Phone Case - Old Model', @CatElectronics, 15.00, 0, 0);
    SET @ProdPhoneCase = CONVERT(int, SCOPE_IDENTITY());

    /*
        Order 1: delivered order, paid successfully, no return.
        Revenue analysis should include this order.
    */
    INSERT dbo.Orders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee, ShippedAt, DeliveredAt)
    VALUES (@CustomerAn, '2026-01-15T10:00:00', 'Website', 'Delivered', 0.00, '2026-01-16T09:00:00', '2026-01-18T15:30:00');
    SET @Order1 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.OrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order1, 1, @ProdLaptop, 1, 899.00, 620.00, 0.00, 0.00, 71.92);

    INSERT dbo.Payments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order1, 'Card', N'Stripe', 'SMALL-DEMO-PAY-001', 970.92, 'Completed', '2026-01-15T10:02:00', '2026-01-15T10:03:00');
    SET @PaymentOrder1 = CONVERT(int, SCOPE_IDENTITY());

    /*
        Order 2: delivered order with a compliant return and full refund.
        This demonstrates approved full refund after returned goods are received.
    */
    INSERT dbo.Orders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee, ShippedAt, DeliveredAt)
    VALUES (@CustomerBinh, '2026-02-10T13:10:00', 'App', 'Delivered', 0.00, '2026-02-11T08:00:00', '2026-02-13T12:00:00');
    SET @Order2 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.OrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order2, 1, @ProdShoes, 2, 80.00, 42.00, 10.00, 0.00, 12.00);
    SET @ItemOrder2Shoes = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Payments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order2, 'EWallet', N'PayPal', 'SMALL-DEMO-PAY-002', 162.00, 'Completed', '2026-02-10T13:12:00', '2026-02-10T13:13:00');
    SET @PaymentOrder2 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Returns (OrderID, RequestedAt, ReceivedAt)
    VALUES (@Order2, '2026-02-17T09:00:00', '2026-02-20T16:00:00');
    SET @ReturnOrder2 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.ReturnItems (ReturnID, OrderItemID, Quantity, ReturnReason, EligibleRefundAmount, InspectionResult, DecisionStatus, ApprovedRefundAmount, DecidedAt, DecisionReason)
    VALUES (@ReturnOrder2, @ItemOrder2Shoes, 2, N'Wrong size; item returned unused with original packaging.', 162.00, 'Compliant', 'ApprovedFull', 162.00, '2026-02-21T10:00:00', NULL);
    SET @ReturnItemOrder2 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Refunds (ReturnItemID, PaymentID, Amount, RefundStatus, Provider, TransactionReference, CreatedAt, CompletedAt)
    VALUES (@ReturnItemOrder2, @PaymentOrder2, 162.00, 'Completed', N'PayPal', 'SMALL-DEMO-REF-002', '2026-02-21T10:15:00', '2026-02-21T11:00:00');

    /*
        Order 3: delivered order with noncompliant return and partial refund.
        This matches the project rule: noncompliant return may receive partial refund.
    */
    INSERT dbo.Orders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee, ShippedAt, DeliveredAt)
    VALUES (@CustomerChi, '2026-03-05T19:20:00', 'Website', 'Delivered', 5.99, '2026-03-06T09:00:00', '2026-03-08T14:00:00');
    SET @Order3 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.OrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order3, 1, @ProdBackpack, 1, 60.00, 28.00, 0.00, 0.00, 4.80);
    SET @ItemOrder3Backpack = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Payments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order3, 'Card', N'Stripe', 'SMALL-DEMO-PAY-003', 70.79, 'Completed', '2026-03-05T19:21:00', '2026-03-05T19:22:00');
    SET @PaymentOrder3 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Returns (OrderID, RequestedAt, ReceivedAt)
    VALUES (@Order3, '2026-03-12T08:30:00', '2026-03-16T17:00:00');
    SET @ReturnOrder3 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.ReturnItems (ReturnID, OrderItemID, Quantity, ReturnReason, EligibleRefundAmount, InspectionResult, DecisionStatus, ApprovedRefundAmount, DecidedAt, DecisionReason)
    VALUES (@ReturnOrder3, @ItemOrder3Backpack, 1, N'Customer reported defect; item returned with visible use marks.', 64.80, 'NonCompliant', 'ApprovedPartial', 38.88, '2026-03-17T10:30:00', N'Partial refund approved because returned goods were not in original condition.');
    SET @ReturnItemOrder3 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Refunds (ReturnItemID, PaymentID, Amount, RefundStatus, Provider, TransactionReference, CreatedAt, CompletedAt)
    VALUES (@ReturnItemOrder3, @PaymentOrder3, 38.88, 'Completed', N'Stripe', 'SMALL-DEMO-REF-003', '2026-03-17T10:45:00', '2026-03-17T11:15:00');

    /*
        Order 4: cancelled before payment capture.
        Cancellation should not count as delivered revenue.
    */
    INSERT dbo.Orders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee, CancelledAt)
    VALUES (@CustomerDung, '2026-04-01T07:40:00', 'App', 'Cancelled', 5.99, '2026-04-01T08:05:00');
    SET @Order4 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.OrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order4, 1, @ProdCoffeeMaker, 1, 95.00, 52.00, 0.00, 0.00, 7.60);

    /*
        Order 5: shipped but not yet delivered.
        Useful for fulfillment status analysis.
    */
    INSERT dbo.Orders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee, ShippedAt)
    VALUES (@CustomerEva, '2026-05-14T16:00:00', 'Website', 'Shipped', 5.99, '2026-05-15T10:00:00');
    SET @Order5 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.OrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order5, 1, @ProdYogaMat, 1, 30.00, 12.00, 0.00, 0.00, 2.40);

    INSERT dbo.Payments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order5, 'Cash', N'COD', 'SMALL-DEMO-PAY-005', 38.39, 'Completed', '2026-05-14T16:01:00', '2026-05-15T10:05:00');
    SET @PaymentOrder5 = CONVERT(int, SCOPE_IDENTITY());

    /*
        Order 6: processing order with pending payment.
        Useful for pipeline and operational queue checks.
    */
    INSERT dbo.Orders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee)
    VALUES (@CustomerFrank, '2026-06-02T11:25:00', 'App', 'Processing', 5.99);
    SET @Order6 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.OrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order6, 1, @ProdNovel, 1, 20.00, 8.00, 0.00, 0.00, 1.60);

    INSERT dbo.Payments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order6, 'BankTransfer', N'ACH', 'SMALL-DEMO-PAY-006', 27.59, 'Pending', '2026-06-02T11:26:00', NULL);

    /*
        Order 7: pending order with inactive product.
        Historical/inactive products can still appear in prior carts/orders.
    */
    INSERT dbo.Orders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee)
    VALUES (@CustomerAn, '2026-07-09T20:10:00', 'Website', 'Pending', 5.99);
    SET @Order7 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.OrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order7, 1, @ProdPhoneCase, 1, 15.00, 4.50, 0.00, 0.00, 1.20);

    /*
        Order 8: failed payment attempt, successful retry, rejected return.
        Useful for payment funnel and return decision analytics.
    */
    INSERT dbo.Orders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee, ShippedAt, DeliveredAt)
    VALUES (@CustomerDung, '2026-08-18T12:35:00', 'App', 'Delivered', 0.00, '2026-08-19T09:00:00', '2026-08-21T13:45:00');
    SET @Order8 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.OrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order8, 1, @ProdEarbuds, 1, 120.00, 55.00, 0.00, 0.00, 9.60);
    SET @ItemOrder8Earbuds = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.OrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order8, 2, @ProdNovel, 2, 20.00, 8.00, 0.00, 0.00, 3.20);

    INSERT dbo.Payments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order8, 'Card', N'Stripe', 'SMALL-DEMO-PAY-008-FAIL', 172.80, 'Failed', '2026-08-18T12:36:00', NULL);

    INSERT dbo.Payments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order8, 'Card', N'Stripe', 'SMALL-DEMO-PAY-008-SUCCESS', 172.80, 'Completed', '2026-08-18T12:40:00', '2026-08-18T12:41:00');
    SET @PaymentOrder8 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Returns (OrderID, RequestedAt, ReceivedAt)
    VALUES (@Order8, '2026-08-25T09:30:00', '2026-08-29T16:20:00');
    SET @ReturnOrder8 = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.ReturnItems (ReturnID, OrderItemID, Quantity, ReturnReason, EligibleRefundAmount, InspectionResult, DecisionStatus, ApprovedRefundAmount, DecidedAt, DecisionReason)
    VALUES (@ReturnOrder8, @ItemOrder8Earbuds, 1, N'Returned without accessories and with physical damage.', 129.60, 'NonCompliant', 'Rejected', 0.00, '2026-08-30T10:00:00', N'Refund rejected because item was returned damaged and incomplete.');
    SET @ReturnItemOrder8 = CONVERT(int, SCOPE_IDENTITY());

    /*
        Shipping and billing addresses are separated so analysts can study
        fulfillment geography without mixing it with payment identity.
    */
    INSERT dbo.OrderAddresses (OrderID, AddressType, RecipientName, AddressLine, City, Region, PostalCode, CountryCode)
    VALUES
        (@Order1, 'Shipping', N'An Nguyen', N'100 Market Street', N'San Francisco', N'CA', N'94105', 'US'),
        (@Order1, 'Billing',  N'An Nguyen', N'100 Market Street', N'San Francisco', N'CA', N'94105', 'US'),
        (@Order2, 'Shipping', N'Binh Tran', N'22 Lake View Road', N'Seattle', N'WA', N'98101', 'US'),
        (@Order2, 'Billing',  N'Binh Tran', N'22 Lake View Road', N'Seattle', N'WA', N'98101', 'US'),
        (@Order3, 'Shipping', N'Chi Le', N'305 Sunset Avenue', N'Austin', N'TX', N'73301', 'US'),
        (@Order3, 'Billing',  N'Chi Le', N'305 Sunset Avenue', N'Austin', N'TX', N'73301', 'US'),
        (@Order4, 'Shipping', N'Dung Pham', N'88 River Drive', N'Chicago', N'IL', N'60601', 'US'),
        (@Order5, 'Shipping', N'Eva Miller', N'17 Pine Street', N'Denver', N'CO', N'80202', 'US'),
        (@Order6, 'Shipping', N'Frank Wilson', N'9 Oak Lane', N'Boston', N'MA', N'02108', 'US'),
        (@Order7, 'Shipping', N'An Nguyen', N'100 Market Street', N'San Francisco', N'CA', N'94105', 'US'),
        (@Order8, 'Shipping', N'Dung Pham', N'88 River Drive', N'Chicago', N'IL', N'60601', 'US'),
        (@Order8, 'Billing',  N'Dung Pham', N'88 River Drive', N'Chicago', N'IL', N'60601', 'US');

    /*
        Status history supports lifecycle analysis without relying only on the
        current status stored in dbo.Orders.
    */
    INSERT dbo.OrderStatusHistory (OrderID, OrderStatus, ChangedAt, ChangedBy, ChangeReason)
    VALUES
        (@Order1, 'Pending', '2026-01-15T10:00:00', N'system', N'Order created'),
        (@Order1, 'Processing', '2026-01-15T10:03:00', N'system', N'Payment captured'),
        (@Order1, 'Shipped', '2026-01-16T09:00:00', N'warehouse', N'Package handed to carrier'),
        (@Order1, 'Delivered', '2026-01-18T15:30:00', N'carrier', N'Delivery confirmed'),
        (@Order2, 'Pending', '2026-02-10T13:10:00', N'system', N'Order created'),
        (@Order2, 'Processing', '2026-02-10T13:13:00', N'system', N'Payment captured'),
        (@Order2, 'Shipped', '2026-02-11T08:00:00', N'warehouse', N'Package handed to carrier'),
        (@Order2, 'Delivered', '2026-02-13T12:00:00', N'carrier', N'Delivery confirmed'),
        (@Order3, 'Pending', '2026-03-05T19:20:00', N'system', N'Order created'),
        (@Order3, 'Processing', '2026-03-05T19:22:00', N'system', N'Payment captured'),
        (@Order3, 'Shipped', '2026-03-06T09:00:00', N'warehouse', N'Package handed to carrier'),
        (@Order3, 'Delivered', '2026-03-08T14:00:00', N'carrier', N'Delivery confirmed'),
        (@Order4, 'Pending', '2026-04-01T07:40:00', N'system', N'Order created'),
        (@Order4, 'Cancelled', '2026-04-01T08:05:00', N'customer_service', N'Customer cancelled before payment capture'),
        (@Order5, 'Pending', '2026-05-14T16:00:00', N'system', N'Order created'),
        (@Order5, 'Processing', '2026-05-14T16:01:00', N'system', N'COD order accepted'),
        (@Order5, 'Shipped', '2026-05-15T10:00:00', N'warehouse', N'Package handed to carrier'),
        (@Order6, 'Pending', '2026-06-02T11:25:00', N'system', N'Order created'),
        (@Order6, 'Processing', '2026-06-02T11:26:00', N'system', N'Waiting for bank transfer confirmation'),
        (@Order7, 'Pending', '2026-07-09T20:10:00', N'system', N'Order created'),
        (@Order8, 'Pending', '2026-08-18T12:35:00', N'system', N'Order created'),
        (@Order8, 'Processing', '2026-08-18T12:41:00', N'system', N'Payment retry succeeded'),
        (@Order8, 'Shipped', '2026-08-19T09:00:00', N'warehouse', N'Package handed to carrier'),
        (@Order8, 'Delivered', '2026-08-21T13:45:00', N'carrier', N'Delivery confirmed');

    DECLARE @QualityChecks TABLE
    (
        CheckName varchar(100) NOT NULL,
        FailedRows int NOT NULL
    );

    INSERT @QualityChecks (CheckName, FailedRows)
    SELECT 'Orders without items', COUNT(*)
    FROM dbo.Orders o
    WHERE NOT EXISTS (SELECT 1 FROM dbo.OrderItems oi WHERE oi.OrderID = o.OrderID);

    INSERT @QualityChecks (CheckName, FailedRows)
    SELECT 'Orders without shipping address', COUNT(*)
    FROM dbo.Orders o
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.OrderAddresses a
        WHERE a.OrderID = o.OrderID
          AND a.AddressType = 'Shipping'
    );

    INSERT @QualityChecks (CheckName, FailedRows)
    SELECT 'Return item not linked to same order', COUNT(*)
    FROM dbo.ReturnItems ri
    JOIN dbo.Returns r ON r.ReturnID = ri.ReturnID
    JOIN dbo.OrderItems oi ON oi.OrderItemID = ri.OrderItemID
    WHERE r.OrderID <> oi.OrderID;

    INSERT @QualityChecks (CheckName, FailedRows)
    SELECT 'Completed refund exceeds approved return amount', COUNT(*)
    FROM dbo.ReturnItems ri
    JOIN (
        SELECT ReturnItemID, SUM(Amount) AS CompletedRefundAmount
        FROM dbo.Refunds
        WHERE RefundStatus = 'Completed'
        GROUP BY ReturnItemID
    ) rf ON rf.ReturnItemID = ri.ReturnItemID
    WHERE rf.CompletedRefundAmount > ri.ApprovedRefundAmount;

    IF EXISTS (SELECT 1 FROM @QualityChecks WHERE FailedRows > 0)
    BEGIN
        SELECT * FROM @QualityChecks;
        THROW 51002, 'Small demo seed failed quality checks. Transaction rolled back.', 1;
    END;

    COMMIT;

    SELECT 'Categories' AS TableName, COUNT(*) AS [RowCount] FROM dbo.Categories
    UNION ALL SELECT 'Customers', COUNT(*) FROM dbo.Customers
    UNION ALL SELECT 'Products', COUNT(*) FROM dbo.Products
    UNION ALL SELECT 'Orders', COUNT(*) FROM dbo.Orders
    UNION ALL SELECT 'OrderItems', COUNT(*) FROM dbo.OrderItems
    UNION ALL SELECT 'Payments', COUNT(*) FROM dbo.Payments
    UNION ALL SELECT 'Returns', COUNT(*) FROM dbo.Returns
    UNION ALL SELECT 'ReturnItems', COUNT(*) FROM dbo.ReturnItems
    UNION ALL SELECT 'Refunds', COUNT(*) FROM dbo.Refunds
    UNION ALL SELECT 'OrderStatusHistory', COUNT(*) FROM dbo.OrderStatusHistory;

    SELECT OrderStatus, COUNT(*) AS Orders
    FROM dbo.Orders
    GROUP BY OrderStatus
    ORDER BY OrderStatus;

    SELECT DecisionStatus, COUNT(*) AS ReturnItems
    FROM dbo.ReturnItems
    GROUP BY DecisionStatus
    ORDER BY DecisionStatus;

    PRINT 'SMALL DEMO SEED PASSED: portfolio demo data inserted successfully.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK;

    THROW;
END CATCH;
GO

GO
PRINT 'END_small_1';
GO
PRINT 'BEGIN_small_2';
GO
/* Read-only against permanent objects; temporary objects only.
   SQL Server 2016+, compatibility >=110. Run after metadata preflight.
   Expected/Actual are violation counts unless stated otherwise.
   No snapshot isolation setting is changed. Use a quiescent immutable snapshot
   for reproducible cross-statement totals. */
USE OnlineRetailDB_Audit_small_Clean_20261012_03;
GO
SET NOCOUNT ON;
IF DB_NAME()<>N'OnlineRetailDB_Audit_small_Clean_20261012_03' THROW 53000,'Wrong database.',1;
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

GO
PRINT 'END_small_2';
GO
PRINT 'BEGIN_small_3';
GO
/*=============================================================================
  PORTFOLIO PROJECT: ONLINE RETAIL ANALYTICS
  STEP 4.1 - MONTHLY REVENUE AND PROFIT BY SALES CHANNEL

  SQL dialect : Microsoft SQL Server
  Database    : OnlineRetailDB_Audit_small_Clean_20261012_03

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

USE OnlineRetailDB_Audit_small_Clean_20261012_03;
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
FROM MetricsWithWindows
ORDER BY
    OrderMonth,
    SalesChannel
OPTION (MAXRECURSION 0);
GO

/*=============================================================================
  INTERPRETATION NOTES

  - A month/channel combination with no delivered orders remains visible as 0.
  - MonthOverMonthGrowthPct is NULL for the first month and whenever the prior
    calendar month's net revenue is 0; a percentage change from zero is not
    mathematically meaningful.
  - CompletedRefundAmount is the customer cash refund including refunded tax.
  - NetRevenue excludes tax and includes shipping revenue.
  - EstimatedGrossProfit does not reverse COGS for returned inventory because
    the current schema has no restock/write-off disposition field.
=============================================================================*/
/*=============================================================================
  PORTFOLIO PROJECT: ONLINE RETAIL ANALYTICS
  STEP 4.2 - ORDER STATUS, CANCELLATION AND PAYMENT PERFORMANCE

  SQL dialect : Microsoft SQL Server
  Database    : OnlineRetailDB_Audit_small_Clean_20261012_03

  BUSINESS QUESTIONS
  1. How many orders currently sit in each status?
  2. What percentage of orders are cancelled?
  3. How frequently do payment attempts fail?
  4. How many failed-payment orders are later recovered?
  5. How many orders progress through each fulfillment stage?

  OUTPUTS
  Result set 1: Monthly operational KPIs by sales channel.
  Result set 2: Overall order-status funnel by sales channel.
  Result set 3: Payment-method performance and failure ranking.
=============================================================================*/

USE OnlineRetailDB_Audit_small_Clean_20261012_03;
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

/*=============================================================================
  RESULT SET 1 - MONTHLY ORDER AND PAYMENT KPIs
=============================================================================*/

;WITH
/* Payments use an attempt-level grain: an order can fail once and then succeed.
   Aggregate attempts before joining Orders to prevent duplicated order counts. */
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
/* A calendar spine preserves zero-activity months, so trend comparisons use
   adjacent calendar months rather than adjacent rows with data. */
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


/*=============================================================================
  RESULT SET 2 - ORDER-STATUS FUNNEL

  The current Orders.OrderStatus is a snapshot. A funnel requires historical
  progression, so OrderStatusHistory is used together with order timestamps.
=============================================================================*/

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


/*=============================================================================
  RESULT SET 3 - PAYMENT METHOD PERFORMANCE

  DENSE_RANK gives methods with the same failure rate the same rank and does
  not arbitrarily separate tied business performance.
=============================================================================*/

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

/*=============================================================================
  INTERPRETATION NOTES

  - CancellationRatePct uses current final order status in each order cohort.
  - PaymentAttemptFailureRatePct uses all attempts, including Pending.
  - Retry uses Failed.CreatedAt as proxy: no failure-event timestamp exists.
    A later-created Completed attempt counts even if another success preceded it.
  - Funnel infers Pending for all orders and Processing for later active states;
    this is inferred reach plus history, not history-only event measurement.
  - OrdersAffectedByFailurePct uses all orders as the denominator.
  - RetryRecoveryRatePct measures failed-payment orders that later completed.
  - The funnel measures whether an order ever reached a stage, not merely its
    current status. Cancelled is a branch outcome rather than a linear stage.
  - FailureRateRank = 1 identifies the payment method with the highest failed
    attempt rate; small attempt volumes should be interpreted cautiously.
  - A NULL percentage means there is no valid denominator; it is not zero.
=============================================================================*/
/*=============================================================================
  PORTFOLIO PROJECT: ONLINE RETAIL ANALYTICS
  STEP 4.3 - PRODUCT AND CATEGORY PERFORMANCE

  SQL dialect : Microsoft SQL Server
  Database    : OnlineRetailDB_Audit_small_Clean_20261012_03

  BUSINESS QUESTIONS
  1. Which products and categories generate the most sales and profit?
  2. What percentage of revenue does each product/category contribute?
  3. Which products have high physical-return rates?
  4. Which products lead sales within each month?

  OUTPUTS
  Result set 1: Product performance and rankings.
  Result set 2: Category performance and rankings.
  Result set 3: Monthly product rankings and revenue concentration.

  KPI RULES
  - Only Delivered orders are recognized as sales.
  - Revenue uses historical OrderItems values, not current Products.Price.
  - Only Completed refunds reduce revenue.
  - Physical returned quantity requires Returns.ReceivedAt to be populated.
  - Shipping and tax are excluded from merchandise revenue and profit.
=============================================================================*/

USE OnlineRetailDB_Audit_small_Clean_20261012_03;
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

/*=============================================================================
  Build one reusable item-level fact table.

  Grain: one row per OrderItem belonging to a Delivered order.
  Refunds and returns are aggregated separately before they are joined. This
  prevents many-to-many joins from multiplying revenue, quantities or refunds.
=============================================================================*/

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


/*=============================================================================
  RESULT SET 1 - PRODUCT PERFORMANCE

  Products with no Delivered sales remain visible with zero metrics. This is
  useful for identifying inactive, cancelled-only or unsold inventory.
=============================================================================*/

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


/*=============================================================================
  RESULT SET 2 - CATEGORY PERFORMANCE
=============================================================================*/

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


/*=============================================================================
  RESULT SET 3 - MONTHLY PRODUCT RANKING

  The cumulative percentage supports Pareto analysis: it shows how quickly a
  small number of products account for most monthly sales.
=============================================================================*/

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

/*=============================================================================
  INTERPRETATION NOTES

  - Products and categories with zero Delivered sales are intentionally shown.
  - UnitReturnRatePct counts physically received returned units, including
    approved, partially approved and rejected return decisions.
  - RefundedMerchandiseAmount counts only Completed refunds and excludes the
    refunded tax component through proportional allocation.
  - EstimatedGrossProfit is conservative: the current schema cannot determine
    whether returned inventory was restocked or written off, so COGS is not
    reversed after a return.
  - Revenue ranks use NetMerchandiseSales after completed refunds.
  - Category/product order counts overlap: never sum them for portfolio orders.
  - Monthly top-five uses dense ranks, so ties may produce more than five rows.
  - Pareto is NULL for nonpositive totals or any negative product contribution.
=============================================================================*/

GO
PRINT 'END_small_3';
GO
PRINT 'BEGIN_small_4';
GO
/* STEP 4.4: CUSTOMER ANALYSIS - SQL SERVER
   Database: OnlineRetailDB_Audit_small_Clean_20261012_03
   Read-only against permanent tables; temporary tables are session-local.
   Purchase = Delivered order, ordered by OrderDate then OrderID.
   New order = first Delivered order; subsequent purchases = Repeat.
   Fully refunded Delivered orders still count as purchases.
   Observed lifetime revenue is NOT predicted Customer Lifetime Value.
   Revenue excludes tax, includes shipping, and attributes completed refunds
   to the original order. All results describe the available dataset only.
*/
USE [OnlineRetailDB_Audit_small_Clean_20261012_03];
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

GO
PRINT 'END_small_4';
GO
PRINT 'BEGIN_small_5';
GO
/*=============================================================================
  PORTFOLIO PROJECT: ONLINE RETAIL ANALYTICS
  STEP 4.5 - RETURN AND REFUND PERFORMANCE

  SQL dialect : Microsoft SQL Server
  Database    : OnlineRetailDB_Audit_small_Clean_20261012_03

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

USE [OnlineRetailDB_Audit_small_Clean_20261012_03];
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

GO
PRINT 'END_small_5';
GO
PRINT 'BEGIN_small_6';
GO
/*=============================================================================
  PORTFOLIO PROJECT: ONLINE RETAIL ANALYTICS
  STEP 4.6 - FULFILLMENT AND DELIVERY PERFORMANCE

  SQL dialect : Microsoft SQL Server
  Database    : OnlineRetailDB_Audit_small_Clean_20261012_03

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

USE [OnlineRetailDB_Audit_small_Clean_20261012_03];
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

GO
PRINT 'END_small_6';
GO
PRINT 'BEGIN_small_7';
GO
/*=============================================================================
  PORTFOLIO PROJECT: ONLINE RETAIL ANALYTICS
  STEP 4.7 - CUSTOMER COHORT AND RETENTION ANALYSIS

  SQL dialect : Microsoft SQL Server
  Database    : OnlineRetailDB_Audit_small_Clean_20261012_03

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

USE [OnlineRetailDB_Audit_small_Clean_20261012_03];
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

GO
PRINT 'END_small_7';
GO
PRINT 'BEGIN_small_8';
GO
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
  Database    : OnlineRetailDB_Audit_small_Clean_20261012_03

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

USE OnlineRetailDB_Audit_small_Clean_20261012_03;
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

GO
PRINT 'END_small_8';
GO
PRINT 'BEGIN_small_9';
GO
/* WRITE-DEPENDENT TEST: explicitly authorized disposable database only.
   Each test updates one row and rolls back; no constraints are disabled.
   Expected error codes are asserted. A missing target is a failure. */
USE OnlineRetailDB_Audit_small_Clean_20261012_03;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @AuthorizedDisposable bit=1; -- set to 1 only after explicit owner approval.
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



GO
PRINT 'END_small_9';
GO
PRINT 'ALL_SMALL_COMPLETE';
GO
