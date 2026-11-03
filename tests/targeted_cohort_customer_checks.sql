:ON ERROR EXIT
USE master;
GO
/* Generated integration harness: actual seven analysis modules and actual
   reconciliation queries run against eleven session-local #Fixture tables.
   No permanent object or user-data mutations. Connect to a verified SQL Server
   with temp-table permission; SQLCMD -b, one connection for the whole file.
   The controlled fixture defines its own coverage through 2026-10-01 UTC; this
   is NOT a coverage claim for the user's small dataset or a business decision.
   Same column definitions, CHECK/unique constraints and computed amounts as DDL.
   Foreign keys are omitted because SQL Server does not enforce FKs on temporary
   tables; actual orphan and workflow checks run explicitly before reports.
   Constraint enforcement on real schema is separately tested by the guarded
   constraint_failure_checks.sql. B03 corrections are included; exact-cent reconciliation must pass.
   This regenerated harness has not yet been executed on SQL Server.
   Regenerate after module edits; never modify the generated SQL independently.
*/
SET NOCOUNT ON;
DROP TABLE IF EXISTS #FixtureCategories;
CREATE TABLE #FixtureCategories (
 CategoryID int IDENTITY PRIMARY KEY,
 CategoryName nvarchar(100) NOT NULL UNIQUE,
 CHECK(LEN(LTRIM(RTRIM(CategoryName)))>0)
);
DROP TABLE IF EXISTS #FixtureCustomers;
CREATE TABLE #FixtureCustomers (
 CustomerID int IDENTITY PRIMARY KEY,
 FirstName nvarchar(50) NOT NULL,
 LastName nvarchar(50) NOT NULL,
 Email nvarchar(150) NULL,
 Phone nvarchar(30) NULL,
 CountryCode char(2) NOT NULL,
 CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
 IsActive bit NOT NULL DEFAULT 1
);
DROP TABLE IF EXISTS #FixtureProducts;
CREATE TABLE #FixtureProducts (
 ProductID int IDENTITY PRIMARY KEY,
 SKU varchar(50) NOT NULL UNIQUE,
 ProductName nvarchar(150) NOT NULL,
 CategoryID int NOT NULL,
 Price decimal(18,2) NOT NULL CHECK(Price>=0),
 Stock int NOT NULL DEFAULT 0 CHECK(Stock>=0),
 IsActive bit NOT NULL DEFAULT 1,
 CHECK(LEN(LTRIM(RTRIM(SKU)))>0)
);
DROP TABLE IF EXISTS #FixtureOrders;
CREATE TABLE #FixtureOrders (
    OrderID INT IDENTITY(1,1)
    --IDENTITY SQL Server tự tăng ID.
        PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATETIME2(0) NOT NULL
        DEFAULT SYSUTCDATETIME(),
    SalesChannel VARCHAR(10) NOT NULL,
    CurrencyCode CHAR(3) NOT NULL
        DEFAULT 'USD',
    OrderStatus VARCHAR(15) NOT NULL
        DEFAULT 'Pending',
    ShippingFee DECIMAL(18,2) NOT NULL
        DEFAULT 0,
    ShippedAt DATETIME2(0) NULL,
    DeliveredAt DATETIME2(0) NULL,
    CancelledAt DATETIME2(0) NULL,
    
    CHECK (SalesChannel IN ('Website', 'App')),
    CHECK (CurrencyCode = 'USD'),
    CHECK
        (
            OrderStatus IN
            (
                'Pending',
                'Processing',
                'Shipped',
                'Delivered',
                'Cancelled'
            )
        ),
    CHECK (ShippingFee >= 0),
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
    CHECK
        (
            (
                OrderStatus IN ('Pending', 'Processing')
                AND ShippedAt IS NULL
                AND DeliveredAt IS NULL
                AND CancelledAt IS NULL
            )
            OR
            (
                OrderStatus = 'Shipped'
                AND ShippedAt IS NOT NULL
                AND DeliveredAt IS NULL
                AND CancelledAt IS NULL
            )
            OR
            (
                OrderStatus = 'Delivered'
                AND ShippedAt IS NOT NULL
                AND DeliveredAt IS NOT NULL
                AND CancelledAt IS NULL
            )
            OR
            (
                OrderStatus = 'Cancelled'
                AND CancelledAt IS NOT NULL
                AND ShippedAt IS NULL
                AND DeliveredAt IS NULL
            )
        )
);
DROP TABLE IF EXISTS #FixtureOrderAddresses;
CREATE TABLE #FixtureOrderAddresses (
 OrderID int NOT NULL,
 AddressType varchar(10) NOT NULL CHECK(AddressType IN ('Shipping','Billing')),
 RecipientName nvarchar(150) NOT NULL,
 AddressLine nvarchar(255) NOT NULL,
 City nvarchar(100) NOT NULL,
 Region nvarchar(100) NULL,
 PostalCode nvarchar(20) NULL,
 CountryCode char(2) NOT NULL,
 PRIMARY KEY(OrderID,AddressType)
);
DROP TABLE IF EXISTS #FixtureOrderItems;
CREATE TABLE #FixtureOrderItems (
 OrderItemID int IDENTITY PRIMARY KEY,
 OrderID int NOT NULL,
 LineNumber smallint NOT NULL CHECK(LineNumber>0),
 ProductID int NOT NULL,
 Quantity int NOT NULL CHECK(Quantity>0),
 UnitPrice decimal(18,2) NOT NULL CHECK(UnitPrice>=0),
 UnitCostAtOrder decimal(18,2) NOT NULL CHECK(UnitCostAtOrder>=0),
 LineDiscount decimal(18,2) NOT NULL DEFAULT 0 CHECK(LineDiscount>=0),
 AllocatedOrderDiscount decimal(18,2) NOT NULL DEFAULT 0 CHECK(AllocatedOrderDiscount>=0),
 TaxAmount decimal(18,2) NOT NULL DEFAULT 0 CHECK(TaxAmount>=0),
 NetMerchandiseAmount AS CONVERT(decimal(18,2),Quantity*UnitPrice-LineDiscount-AllocatedOrderDiscount) PERSISTED,
 LinePayableAmount AS CONVERT(decimal(18,2),Quantity*UnitPrice-LineDiscount-AllocatedOrderDiscount+TaxAmount) PERSISTED,
 CHECK(LineDiscount+AllocatedOrderDiscount<=Quantity*UnitPrice),
 UNIQUE(OrderID,LineNumber)
);
DROP TABLE IF EXISTS #FixturePayments;
CREATE TABLE #FixturePayments (
 PaymentID int IDENTITY PRIMARY KEY,
 OrderID int NOT NULL,
 PaymentMethod varchar(20) NOT NULL CHECK(PaymentMethod IN ('Card','BankTransfer','EWallet','Cash')),
 PaymentProvider varchar(50) NOT NULL,
 TransactionReference varchar(100) NULL,
 Amount decimal(18,2) NOT NULL CHECK(Amount>0),
 PaymentStatus varchar(12) NOT NULL DEFAULT 'Pending' CHECK(PaymentStatus IN ('Pending','Completed','Failed')),
 CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
 CompletedAt datetime2(0) NULL,
 CHECK(
  (PaymentStatus='Completed' AND CompletedAt IS NOT NULL AND CompletedAt>=CreatedAt) OR
  (PaymentStatus IN ('Pending','Failed') AND CompletedAt IS NULL))
);
DROP TABLE IF EXISTS #FixtureReturns;
CREATE TABLE #FixtureReturns (
 ReturnID int IDENTITY PRIMARY KEY,
 OrderID int NOT NULL,
 RequestedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
 ReceivedAt datetime2(0) NULL,
 CHECK(ReceivedAt IS NULL OR ReceivedAt>=RequestedAt)
);
DROP TABLE IF EXISTS #FixtureReturnItems;
CREATE TABLE #FixtureReturnItems (
    ReturnItemID int IDENTITY PRIMARY KEY,
    ReturnID int NOT NULL,
    OrderItemID int NOT NULL,
    Quantity int NOT NULL CHECK(Quantity > 0),
    ReturnReason nvarchar(255) NOT NULL,

    -- Entitlement for these units after allocated discounts/tax, excluding shipping.
    EligibleRefundAmount decimal(18,2) NOT NULL CHECK(EligibleRefundAmount >= 0),

    InspectionResult varchar(15) NULL
        CHECK(InspectionResult IN ('Compliant', 'NonCompliant')),

    DecisionStatus varchar(15) NOT NULL
        DEFAULT 'Pending'
        CHECK(DecisionStatus IN ('Pending', 'ApprovedFull', 'ApprovedPartial', 'Rejected')),

    ApprovedRefundAmount decimal(18,2) NULL,
    DecidedAt datetime2(0) NULL,
    DecisionReason nvarchar(255) NULL,

    UNIQUE(ReturnID, OrderItemID),

    CHECK(
        (DecisionStatus = 'Pending'
            AND InspectionResult IS NULL
            AND ApprovedRefundAmount IS NULL
            AND DecidedAt IS NULL)

        OR

        (DecisionStatus = 'ApprovedFull'
            AND InspectionResult IS NOT NULL
            AND InspectionResult = 'Compliant'
            AND DecidedAt IS NOT NULL
            AND ApprovedRefundAmount IS NOT NULL
            AND ApprovedRefundAmount = EligibleRefundAmount)

        OR

        (DecisionStatus = 'ApprovedPartial'
            AND InspectionResult IS NOT NULL
            AND InspectionResult = 'NonCompliant'
            AND DecidedAt IS NOT NULL
            AND ApprovedRefundAmount IS NOT NULL
            AND ApprovedRefundAmount > 0
            AND ApprovedRefundAmount < EligibleRefundAmount
            AND DecisionReason IS NOT NULL
            AND LEN(LTRIM(RTRIM(DecisionReason))) > 0)

        OR

        (DecisionStatus = 'Rejected'
            AND InspectionResult IS NOT NULL
            AND InspectionResult = 'NonCompliant'
            AND DecidedAt IS NOT NULL
            AND ApprovedRefundAmount IS NOT NULL
            AND ApprovedRefundAmount = 0
            AND DecisionReason IS NOT NULL
            AND LEN(LTRIM(RTRIM(DecisionReason))) > 0)
    )
);
DROP TABLE IF EXISTS #FixtureRefunds;
CREATE TABLE #FixtureRefunds (
    RefundID int IDENTITY PRIMARY KEY,
    ReturnItemID int NOT NULL,
    PaymentID int NOT NULL,
    Amount decimal(18,2) NOT NULL CHECK(Amount > 0),

    RefundStatus varchar(12) NOT NULL
        DEFAULT 'Pending'
        CHECK(RefundStatus IN ('Pending', 'Completed', 'Failed')),

    Provider varchar(50) NOT NULL,
    TransactionReference varchar(100) NULL,
    CreatedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CompletedAt datetime2(0) NULL,

    CHECK(
        (RefundStatus = 'Completed'
            AND CompletedAt IS NOT NULL
            AND CompletedAt >= CreatedAt)
        OR
        (RefundStatus IN ('Pending', 'Failed')
            AND CompletedAt IS NULL)
    )
);
DROP TABLE IF EXISTS #FixtureOrderStatusHistory;
CREATE TABLE #FixtureOrderStatusHistory (
    OrderStatusHistoryID bigint IDENTITY PRIMARY KEY,
    OrderID int NOT NULL,

    OrderStatus varchar(15) NOT NULL
        CHECK(OrderStatus IN (
            'Pending',
            'Processing',
            'Shipped',
            'Delivered',
            'Cancelled'
        )),

    ChangedAt datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    ChangedBy nvarchar(128) NOT NULL,
    ChangeReason nvarchar(255) NULL
);
CREATE UNIQUE INDEX UX_Payment_Reference ON #FixturePayments(PaymentProvider,TransactionReference)
 WHERE TransactionReference IS NOT NULL;
CREATE UNIQUE INDEX UX_Refund_Reference
ON #FixtureRefunds(Provider, TransactionReference)
WHERE TransactionReference IS NOT NULL;

GO

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
      1. Run OnlineRetail - Schema.sql
      2. Run this file on an empty OnlineRetailDB

    Notes:
      - This file intentionally avoids DELETE/TRUNCATE so reviewers do not
        accidentally remove existing work.
      - Full analytical volume should live in a separate optional seed file.
*/



IF @@TRANCOUNT <> 0
    THROW 51003, 'Run seed in a fresh session without a transaction.', 1;

BEGIN TRY
    BEGIN TRAN;
    IF EXISTS (SELECT 1 FROM #FixtureCategories WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Categories is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM #FixtureCustomers WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Customers is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM #FixtureProducts WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Products is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM #FixtureOrders WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Orders is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM #FixtureOrderAddresses WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'OrderAddresses is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM #FixtureOrderItems WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'OrderItems is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM #FixturePayments WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Payments is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM #FixtureOrderStatusHistory WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'OrderStatusHistory is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM #FixtureReturns WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'Returns is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM #FixtureReturnItems WITH (TABLOCKX,HOLDLOCK))
        THROW 51001, 'ReturnItems is not empty. Seed stopped.', 1;
    IF EXISTS (SELECT 1 FROM #FixtureRefunds WITH (TABLOCKX,HOLDLOCK))
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

    INSERT #FixtureCategories (CategoryName)
    VALUES
        (N'Electronics'),
        (N'Fashion'),
        (N'Home & Kitchen'),
        (N'Sports'),
        (N'Books');

    SELECT @CatElectronics = CategoryID FROM #FixtureCategories WHERE CategoryName = N'Electronics';
    SELECT @CatFashion = CategoryID FROM #FixtureCategories WHERE CategoryName = N'Fashion';
    SELECT @CatHome = CategoryID FROM #FixtureCategories WHERE CategoryName = N'Home & Kitchen';
    SELECT @CatSports = CategoryID FROM #FixtureCategories WHERE CategoryName = N'Sports';
    SELECT @CatBooks = CategoryID FROM #FixtureCategories WHERE CategoryName = N'Books';

    INSERT #FixtureCustomers (FirstName, LastName, Email, Phone, CountryCode, CreatedAt, IsActive)
    VALUES (N'An', N'Nguyen', N'an.nguyen@example.com', N'+12025550101', 'US', '2025-01-05T09:15:00', 1);
    SET @CustomerAn = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureCustomers (FirstName, LastName, Email, Phone, CountryCode, CreatedAt, IsActive)
    VALUES (N'Binh', N'Tran', N'family@example.com', NULL, 'US', '2025-02-12T11:30:00', 1);
    SET @CustomerBinh = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureCustomers (FirstName, LastName, Email, Phone, CountryCode, CreatedAt, IsActive)
    VALUES (N'Chi', N'Le', NULL, N'+12025550103', 'US', '2025-03-18T14:00:00', 1);
    SET @CustomerChi = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureCustomers (FirstName, LastName, Email, Phone, CountryCode, CreatedAt, IsActive)
    VALUES (N'Dung', N'Pham', N'family@example.com', N'+12025550104', 'US', '2025-05-01T08:45:00', 1);
    SET @CustomerDung = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureCustomers (FirstName, LastName, Email, Phone, CountryCode, CreatedAt, IsActive)
    VALUES (N'Eva', N'Miller', N'eva.miller@example.com', N'+12025550105', 'US', '2025-09-21T18:20:00', 0);
    SET @CustomerEva = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureCustomers (FirstName, LastName, Email, Phone, CountryCode, CreatedAt, IsActive)
    VALUES (N'Frank', N'Wilson', N'frank.wilson@example.com', N'+12025550106', 'US', '2026-01-10T10:10:00', 1);
    SET @CustomerFrank = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureProducts (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('EL-LAP-001', N'Everyday Laptop 14 inch', @CatElectronics, 899.00, 18, 1);
    SET @ProdLaptop = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureProducts (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('EL-EAR-002', N'Wireless Earbuds', @CatElectronics, 120.00, 75, 1);
    SET @ProdEarbuds = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureProducts (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('FA-SHO-003', N'Running Shoes', @CatFashion, 80.00, 42, 1);
    SET @ProdShoes = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureProducts (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('FA-BAG-004', N'City Backpack', @CatFashion, 60.00, 60, 1);
    SET @ProdBackpack = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureProducts (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('HK-COF-005', N'Compact Coffee Maker', @CatHome, 95.00, 25, 1);
    SET @ProdCoffeeMaker = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureProducts (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('SP-YOG-006', N'Yoga Mat', @CatSports, 30.00, 80, 1);
    SET @ProdYogaMat = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureProducts (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('BK-NOV-007', N'Weekend Novel', @CatBooks, 20.00, 100, 1);
    SET @ProdNovel = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureProducts (SKU, ProductName, CategoryID, Price, Stock, IsActive)
    VALUES ('EL-CAS-008', N'Phone Case - Old Model', @CatElectronics, 15.00, 0, 0);
    SET @ProdPhoneCase = CONVERT(int, SCOPE_IDENTITY());

    /*
        Order 1: delivered order, paid successfully, no return.
        Revenue analysis should include this order.
    */
    INSERT #FixtureOrders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee, ShippedAt, DeliveredAt)
    VALUES (@CustomerAn, '2026-01-15T10:00:00', 'Website', 'Delivered', 0.00, '2026-01-16T09:00:00', '2026-01-18T15:30:00');
    SET @Order1 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureOrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order1, 1, @ProdLaptop, 1, 899.00, 620.00, 0.00, 0.00, 71.92);

    INSERT #FixturePayments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order1, 'Card', N'Stripe', 'SMALL-DEMO-PAY-001', 970.92, 'Completed', '2026-01-15T10:02:00', '2026-01-15T10:03:00');
    SET @PaymentOrder1 = CONVERT(int, SCOPE_IDENTITY());

    /*
        Order 2: delivered order with a compliant return and full refund.
        This demonstrates approved full refund after returned goods are received.
    */
    INSERT #FixtureOrders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee, ShippedAt, DeliveredAt)
    VALUES (@CustomerBinh, '2026-02-10T13:10:00', 'App', 'Delivered', 0.00, '2026-02-11T08:00:00', '2026-02-13T12:00:00');
    SET @Order2 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureOrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order2, 1, @ProdShoes, 2, 80.00, 42.00, 10.00, 0.00, 12.00);
    SET @ItemOrder2Shoes = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixturePayments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order2, 'EWallet', N'PayPal', 'SMALL-DEMO-PAY-002', 162.00, 'Completed', '2026-02-10T13:12:00', '2026-02-10T13:13:00');
    SET @PaymentOrder2 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureReturns (OrderID, RequestedAt, ReceivedAt)
    VALUES (@Order2, '2026-02-17T09:00:00', '2026-02-20T16:00:00');
    SET @ReturnOrder2 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureReturnItems (ReturnID, OrderItemID, Quantity, ReturnReason, EligibleRefundAmount, InspectionResult, DecisionStatus, ApprovedRefundAmount, DecidedAt, DecisionReason)
    VALUES (@ReturnOrder2, @ItemOrder2Shoes, 2, N'Wrong size; item returned unused with original packaging.', 162.00, 'Compliant', 'ApprovedFull', 162.00, '2026-02-21T10:00:00', NULL);
    SET @ReturnItemOrder2 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureRefunds (ReturnItemID, PaymentID, Amount, RefundStatus, Provider, TransactionReference, CreatedAt, CompletedAt)
    VALUES (@ReturnItemOrder2, @PaymentOrder2, 162.00, 'Completed', N'PayPal', 'SMALL-DEMO-REF-002', '2026-02-21T10:15:00', '2026-02-21T11:00:00');

    /*
        Order 3: delivered order with noncompliant return and partial refund.
        This matches the project rule: noncompliant return may receive partial refund.
    */
    INSERT #FixtureOrders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee, ShippedAt, DeliveredAt)
    VALUES (@CustomerChi, '2026-03-05T19:20:00', 'Website', 'Delivered', 5.99, '2026-03-06T09:00:00', '2026-03-08T14:00:00');
    SET @Order3 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureOrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order3, 1, @ProdBackpack, 1, 60.00, 28.00, 0.00, 0.00, 4.80);
    SET @ItemOrder3Backpack = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixturePayments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order3, 'Card', N'Stripe', 'SMALL-DEMO-PAY-003', 70.79, 'Completed', '2026-03-05T19:21:00', '2026-03-05T19:22:00');
    SET @PaymentOrder3 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureReturns (OrderID, RequestedAt, ReceivedAt)
    VALUES (@Order3, '2026-03-12T08:30:00', '2026-03-16T17:00:00');
    SET @ReturnOrder3 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureReturnItems (ReturnID, OrderItemID, Quantity, ReturnReason, EligibleRefundAmount, InspectionResult, DecisionStatus, ApprovedRefundAmount, DecidedAt, DecisionReason)
    VALUES (@ReturnOrder3, @ItemOrder3Backpack, 1, N'Customer reported defect; item returned with visible use marks.', 64.80, 'NonCompliant', 'ApprovedPartial', 38.88, '2026-03-17T10:30:00', N'Partial refund approved because returned goods were not in original condition.');
    SET @ReturnItemOrder3 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureRefunds (ReturnItemID, PaymentID, Amount, RefundStatus, Provider, TransactionReference, CreatedAt, CompletedAt)
    VALUES (@ReturnItemOrder3, @PaymentOrder3, 38.88, 'Completed', N'Stripe', 'SMALL-DEMO-REF-003', '2026-03-17T10:45:00', '2026-03-17T11:15:00');

    /*
        Order 4: cancelled before payment capture.
        Cancellation should not count as delivered revenue.
    */
    INSERT #FixtureOrders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee, CancelledAt)
    VALUES (@CustomerDung, '2026-04-01T07:40:00', 'App', 'Cancelled', 5.99, '2026-04-01T08:05:00');
    SET @Order4 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureOrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order4, 1, @ProdCoffeeMaker, 1, 95.00, 52.00, 0.00, 0.00, 7.60);

    /*
        Order 5: shipped but not yet delivered.
        Useful for fulfillment status analysis.
    */
    INSERT #FixtureOrders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee, ShippedAt)
    VALUES (@CustomerEva, '2026-05-14T16:00:00', 'Website', 'Shipped', 5.99, '2026-05-15T10:00:00');
    SET @Order5 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureOrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order5, 1, @ProdYogaMat, 1, 30.00, 12.00, 0.00, 0.00, 2.40);

    INSERT #FixturePayments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order5, 'Cash', N'COD', 'SMALL-DEMO-PAY-005', 38.39, 'Completed', '2026-05-14T16:01:00', '2026-05-15T10:05:00');
    SET @PaymentOrder5 = CONVERT(int, SCOPE_IDENTITY());

    /*
        Order 6: processing order with pending payment.
        Useful for pipeline and operational queue checks.
    */
    INSERT #FixtureOrders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee)
    VALUES (@CustomerFrank, '2026-06-02T11:25:00', 'App', 'Processing', 5.99);
    SET @Order6 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureOrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order6, 1, @ProdNovel, 1, 20.00, 8.00, 0.00, 0.00, 1.60);

    INSERT #FixturePayments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order6, 'BankTransfer', N'ACH', 'SMALL-DEMO-PAY-006', 27.59, 'Pending', '2026-06-02T11:26:00', NULL);

    /*
        Order 7: pending order with inactive product.
        Historical/inactive products can still appear in prior carts/orders.
    */
    INSERT #FixtureOrders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee)
    VALUES (@CustomerAn, '2026-07-09T20:10:00', 'Website', 'Pending', 5.99);
    SET @Order7 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureOrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order7, 1, @ProdPhoneCase, 1, 15.00, 4.50, 0.00, 0.00, 1.20);

    /*
        Order 8: failed payment attempt, successful retry, rejected return.
        Useful for payment funnel and return decision analytics.
    */
    INSERT #FixtureOrders (CustomerID, OrderDate, SalesChannel, OrderStatus, ShippingFee, ShippedAt, DeliveredAt)
    VALUES (@CustomerDung, '2026-08-18T12:35:00', 'App', 'Delivered', 0.00, '2026-08-19T09:00:00', '2026-08-21T13:45:00');
    SET @Order8 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureOrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order8, 1, @ProdEarbuds, 1, 120.00, 55.00, 0.00, 0.00, 9.60);
    SET @ItemOrder8Earbuds = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureOrderItems (OrderID, LineNumber, ProductID, Quantity, UnitPrice, UnitCostAtOrder, LineDiscount, AllocatedOrderDiscount, TaxAmount)
    VALUES (@Order8, 2, @ProdNovel, 2, 20.00, 8.00, 0.00, 0.00, 3.20);

    INSERT #FixturePayments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order8, 'Card', N'Stripe', 'SMALL-DEMO-PAY-008-FAIL', 172.80, 'Failed', '2026-08-18T12:36:00', NULL);

    INSERT #FixturePayments (OrderID, PaymentMethod, PaymentProvider, TransactionReference, Amount, PaymentStatus, CreatedAt, CompletedAt)
    VALUES (@Order8, 'Card', N'Stripe', 'SMALL-DEMO-PAY-008-SUCCESS', 172.80, 'Completed', '2026-08-18T12:40:00', '2026-08-18T12:41:00');
    SET @PaymentOrder8 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureReturns (OrderID, RequestedAt, ReceivedAt)
    VALUES (@Order8, '2026-08-25T09:30:00', '2026-08-29T16:20:00');
    SET @ReturnOrder8 = CONVERT(int, SCOPE_IDENTITY());

    INSERT #FixtureReturnItems (ReturnID, OrderItemID, Quantity, ReturnReason, EligibleRefundAmount, InspectionResult, DecisionStatus, ApprovedRefundAmount, DecidedAt, DecisionReason)
    VALUES (@ReturnOrder8, @ItemOrder8Earbuds, 1, N'Returned without accessories and with physical damage.', 129.60, 'NonCompliant', 'Rejected', 0.00, '2026-08-30T10:00:00', N'Refund rejected because item was returned damaged and incomplete.');
    SET @ReturnItemOrder8 = CONVERT(int, SCOPE_IDENTITY());

    /*
        Shipping and billing addresses are separated so analysts can study
        fulfillment geography without mixing it with payment identity.
    */
    INSERT #FixtureOrderAddresses (OrderID, AddressType, RecipientName, AddressLine, City, Region, PostalCode, CountryCode)
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
        current status stored in #FixtureOrders.
    */
    INSERT #FixtureOrderStatusHistory (OrderID, OrderStatus, ChangedAt, ChangedBy, ChangeReason)
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
    FROM #FixtureOrders o
    WHERE NOT EXISTS (SELECT 1 FROM #FixtureOrderItems oi WHERE oi.OrderID = o.OrderID);

    INSERT @QualityChecks (CheckName, FailedRows)
    SELECT 'Orders without shipping address', COUNT(*)
    FROM #FixtureOrders o
    WHERE NOT EXISTS (
        SELECT 1
        FROM #FixtureOrderAddresses a
        WHERE a.OrderID = o.OrderID
          AND a.AddressType = 'Shipping'
    );

    INSERT @QualityChecks (CheckName, FailedRows)
    SELECT 'Return item not linked to same order', COUNT(*)
    FROM #FixtureReturnItems ri
    JOIN #FixtureReturns r ON r.ReturnID = ri.ReturnID
    JOIN #FixtureOrderItems oi ON oi.OrderItemID = ri.OrderItemID
    WHERE r.OrderID <> oi.OrderID;

    INSERT @QualityChecks (CheckName, FailedRows)
    SELECT 'Completed refund exceeds approved return amount', COUNT(*)
    FROM #FixtureReturnItems ri
    JOIN (
        SELECT ReturnItemID, SUM(Amount) AS CompletedRefundAmount
        FROM #FixtureRefunds
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

    SELECT 'Categories' AS TableName, COUNT(*) AS [RowCount] FROM #FixtureCategories
    UNION ALL SELECT 'Customers', COUNT(*) FROM #FixtureCustomers
    UNION ALL SELECT 'Products', COUNT(*) FROM #FixtureProducts
    UNION ALL SELECT 'Orders', COUNT(*) FROM #FixtureOrders
    UNION ALL SELECT 'OrderItems', COUNT(*) FROM #FixtureOrderItems
    UNION ALL SELECT 'Payments', COUNT(*) FROM #FixturePayments
    UNION ALL SELECT 'Returns', COUNT(*) FROM #FixtureReturns
    UNION ALL SELECT 'ReturnItems', COUNT(*) FROM #FixtureReturnItems
    UNION ALL SELECT 'Refunds', COUNT(*) FROM #FixtureRefunds
    UNION ALL SELECT 'OrderStatusHistory', COUNT(*) FROM #FixtureOrderStatusHistory;

    SELECT OrderStatus, COUNT(*) AS Orders
    FROM #FixtureOrders
    GROUP BY OrderStatus
    ORDER BY OrderStatus;

    SELECT DecisionStatus, COUNT(*) AS ReturnItems
    FROM #FixtureReturnItems
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

/* Valid edge fixture: same customer and exact first-order timestamp, second
   channel, multiple products, split collections, success/failure/success,
   two tax-inclusive partial refunds with sub-cent merchandise allocation.
   The tax rate is deliberately 100% for a rounding fixture, not seed tax policy.
   No persistent table or constraint is touched. Cross-table keys checked below. */
DECLARE @EdgeCustomer int=(SELECT MIN(CustomerID) FROM #FixtureCustomers);
DECLARE @EdgeOrder int,@EdgeItem1 int,@EdgeItem2 int,@EdgePayment int,@EdgeReturn int,@EdgeReturnItem int;
INSERT #FixtureOrders(CustomerID,OrderDate,SalesChannel,OrderStatus,ShippingFee,ShippedAt,DeliveredAt)
VALUES(@EdgeCustomer,'2026-01-15T10:00:00','App','Delivered',0,'2026-01-16T09:00:00','2026-01-18T15:30:00');
SET @EdgeOrder=CONVERT(int,SCOPE_IDENTITY());
INSERT #FixtureOrderAddresses(OrderID,AddressType,RecipientName,AddressLine,City,CountryCode)
VALUES(@EdgeOrder,'Shipping','Fixture','Fixture address','Fixture','US');
INSERT #FixtureOrderItems(OrderID,LineNumber,ProductID,Quantity,UnitPrice,UnitCostAtOrder,TaxAmount)
VALUES(@EdgeOrder,1,(SELECT MIN(ProductID) FROM #FixtureProducts),1,1,0,1);
SET @EdgeItem1=CONVERT(int,SCOPE_IDENTITY());
INSERT #FixtureOrderItems(OrderID,LineNumber,ProductID,Quantity,UnitPrice,UnitCostAtOrder,TaxAmount)
VALUES(@EdgeOrder,2,(SELECT MAX(ProductID) FROM #FixtureProducts),1,1,0,1);
SET @EdgeItem2=CONVERT(int,SCOPE_IDENTITY());
INSERT #FixturePayments(OrderID,PaymentMethod,PaymentProvider,Amount,PaymentStatus,CreatedAt,CompletedAt)
VALUES(@EdgeOrder,'Card','Fixture',2,'Completed','2026-01-15T10:01:00','2026-01-15T10:02:00'),
(@EdgeOrder,'Card','Fixture',2,'Failed','2026-01-15T10:03:00',NULL),
(@EdgeOrder,'Card','Fixture',2,'Completed','2026-01-15T10:04:00','2026-01-15T10:05:00');
SELECT @EdgePayment=MAX(PaymentID) FROM #FixturePayments WHERE OrderID=@EdgeOrder AND PaymentStatus='Completed';
INSERT #FixtureReturns(OrderID,RequestedAt,ReceivedAt)
VALUES(@EdgeOrder,'2026-02-01T00:00:00','2026-02-02T00:00:00');
SET @EdgeReturn=CONVERT(int,SCOPE_IDENTITY());
INSERT #FixtureReturnItems(ReturnID,OrderItemID,Quantity,ReturnReason,EligibleRefundAmount,InspectionResult,DecisionStatus,ApprovedRefundAmount,DecidedAt,DecisionReason)
VALUES(@EdgeReturn,@EdgeItem1,1,'Fixture rounding',2,'NonCompliant','ApprovedPartial',0.01,'2026-02-03T00:00:00','Fixture partial');
SET @EdgeReturnItem=CONVERT(int,SCOPE_IDENTITY());
INSERT #FixtureRefunds(ReturnItemID,PaymentID,Amount,RefundStatus,Provider,CreatedAt,CompletedAt)
VALUES(@EdgeReturnItem,@EdgePayment,0.01,'Completed','Fixture','2026-02-03T01:00:00','2026-02-04T00:00:00');
INSERT #FixtureReturnItems(ReturnID,OrderItemID,Quantity,ReturnReason,EligibleRefundAmount,InspectionResult,DecisionStatus,ApprovedRefundAmount,DecidedAt,DecisionReason)
VALUES(@EdgeReturn,@EdgeItem2,1,'Fixture rounding',2,'NonCompliant','ApprovedPartial',0.01,'2026-02-03T00:00:00','Fixture partial');
SET @EdgeReturnItem=CONVERT(int,SCOPE_IDENTITY());
INSERT #FixtureRefunds(ReturnItemID,PaymentID,Amount,RefundStatus,Provider,CreatedAt,CompletedAt)
VALUES(@EdgeReturnItem,@EdgePayment,0.01,'Completed','Fixture','2026-02-03T01:00:00','2026-02-04T00:00:00');
INSERT #FixtureOrderStatusHistory(OrderID,OrderStatus,ChangedAt,ChangedBy)
VALUES(@EdgeOrder,'Pending','2026-01-15T10:00:00','Fixture'),
(@EdgeOrder,'Processing','2026-01-15T10:05:00','Fixture'),
(@EdgeOrder,'Shipped','2026-01-16T09:00:00','Fixture'),
(@EdgeOrder,'Delivered','2026-01-18T15:30:00','Fixture');
GO
DROP TABLE IF EXISTS #AuditResults;
CREATE TABLE #AuditResults(TestID varchar(100),Expected nvarchar(200),Actual nvarchar(200),Result varchar(20));
INSERT #AuditResults SELECT 'DQ02_ItemsAndShipping','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureOrders o WHERE NOT EXISTS(SELECT 1 FROM #FixtureOrderItems i WHERE i.OrderID=o.OrderID) OR NOT EXISTS(SELECT 1 FROM #FixtureOrderAddresses a WHERE a.OrderID=o.OrderID AND a.AddressType='Shipping')) x;
INSERT #AuditResults SELECT 'DQ03_ItemAmounts','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureOrderItems WHERE Quantity<=0 OR UnitPrice<0 OR UnitCostAtOrder<0 OR LineDiscount<0 OR AllocatedOrderDiscount<0 OR TaxAmount<0 OR LineDiscount+AllocatedOrderDiscount>Quantity*UnitPrice OR NetMerchandiseAmount<>Quantity*UnitPrice-LineDiscount-AllocatedOrderDiscount OR LinePayableAmount<>NetMerchandiseAmount+TaxAmount) x;
INSERT #AuditResults SELECT 'DQ04_OrderStateDates','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureOrders WHERE
CurrencyCode<>'USD' OR SalesChannel NOT IN ('Website','App') OR ShippingFee<0
OR ShippedAt<OrderDate OR DeliveredAt<ShippedAt OR CancelledAt<OrderDate
OR NOT ((OrderStatus IN ('Pending','Processing') AND ShippedAt IS NULL AND DeliveredAt IS NULL AND CancelledAt IS NULL)
 OR (OrderStatus='Shipped' AND ShippedAt IS NOT NULL AND DeliveredAt IS NULL AND CancelledAt IS NULL)
 OR (OrderStatus='Delivered' AND ShippedAt IS NOT NULL AND DeliveredAt IS NOT NULL AND CancelledAt IS NULL)
 OR (OrderStatus='Cancelled' AND CancelledAt IS NOT NULL AND ShippedAt IS NULL AND DeliveredAt IS NULL))) x;
INSERT #AuditResults SELECT 'DQ05_ReturnSameOrder','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureReturnItems ri JOIN #FixtureReturns r ON r.ReturnID=ri.ReturnID JOIN #FixtureOrderItems i ON i.OrderItemID=ri.OrderItemID WHERE r.OrderID<>i.OrderID) x;
INSERT #AuditResults SELECT 'DQ06_ReturnReceiptDecision','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureReturnItems ri JOIN #FixtureReturns r ON r.ReturnID=ri.ReturnID WHERE r.ReceivedAt<r.RequestedAt OR (ri.DecisionStatus<>'Pending' AND (r.ReceivedAt IS NULL OR ri.DecidedAt IS NULL OR ri.DecidedAt<r.ReceivedAt))) x;
INSERT #AuditResults SELECT 'DQ07_ReservedReturnQuantity','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT i.OrderItemID FROM #FixtureOrderItems i JOIN #FixtureReturnItems ri ON ri.OrderItemID=i.OrderItemID WHERE ri.DecisionStatus<>'Rejected' GROUP BY i.OrderItemID,i.Quantity HAVING SUM(CONVERT(bigint,ri.Quantity))>i.Quantity) q) x;
INSERT #AuditResults SELECT 'DQ08_ReturnAfterDelivery','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureReturns r JOIN #FixtureOrders o ON o.OrderID=r.OrderID WHERE o.OrderStatus<>'Delivered' OR o.DeliveredAt IS NULL OR r.RequestedAt<o.DeliveredAt OR NOT EXISTS(SELECT 1 FROM #FixtureReturnItems ri WHERE ri.ReturnID=r.ReturnID)) x;
INSERT #AuditResults SELECT 'DQ09_DecisionAmounts','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureReturnItems WHERE Quantity<=0 OR EligibleRefundAmount<0 OR
 (DecisionStatus='Pending' AND (ApprovedRefundAmount IS NOT NULL OR DecidedAt IS NOT NULL OR InspectionResult IS NOT NULL)) OR
 (DecisionStatus='ApprovedFull' AND (ApprovedRefundAmount IS NULL OR ApprovedRefundAmount<>EligibleRefundAmount OR InspectionResult IS NULL OR InspectionResult<>'Compliant' OR DecidedAt IS NULL)) OR
 (DecisionStatus='ApprovedPartial' AND (ApprovedRefundAmount IS NULL OR ApprovedRefundAmount<=0 OR ApprovedRefundAmount>=EligibleRefundAmount OR InspectionResult IS NULL OR InspectionResult<>'NonCompliant' OR DecidedAt IS NULL OR NULLIF(LTRIM(RTRIM(DecisionReason)),'') IS NULL)) OR
 (DecisionStatus='Rejected' AND (ApprovedRefundAmount IS NULL OR ApprovedRefundAmount<>0 OR InspectionResult IS NULL OR InspectionResult<>'NonCompliant' OR DecidedAt IS NULL OR NULLIF(LTRIM(RTRIM(DecisionReason)),'') IS NULL))) x;
INSERT #AuditResults SELECT 'DQ10_RefundPaymentOrderAndChronology','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureRefunds f JOIN #FixturePayments p ON p.PaymentID=f.PaymentID JOIN #FixtureReturnItems ri ON ri.ReturnItemID=f.ReturnItemID JOIN #FixtureReturns r ON r.ReturnID=ri.ReturnID WHERE p.OrderID<>r.OrderID OR p.PaymentStatus<>'Completed' OR p.CompletedAt IS NULL OR ri.DecisionStatus NOT IN ('ApprovedFull','ApprovedPartial') OR ri.DecidedAt IS NULL OR f.CreatedAt<ri.DecidedAt OR f.CreatedAt<p.CompletedAt OR f.Amount<=0 OR f.CompletedAt<f.CreatedAt OR (f.RefundStatus='Completed' AND f.CompletedAt IS NULL) OR (f.RefundStatus IN ('Pending','Failed') AND f.CompletedAt IS NOT NULL)) x;
INSERT #AuditResults SELECT 'DQ11_RefundReservationCap','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT ri.ReturnItemID FROM #FixtureReturnItems ri JOIN #FixtureRefunds f ON f.ReturnItemID=ri.ReturnItemID WHERE f.RefundStatus IN ('Pending','Completed') GROUP BY ri.ReturnItemID,ri.ApprovedRefundAmount HAVING ri.ApprovedRefundAmount IS NULL OR SUM(f.Amount)>ri.ApprovedRefundAmount) q) x;
INSERT #AuditResults SELECT 'DQ12_RefundPaymentReservationCap','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT p.PaymentID FROM #FixturePayments p JOIN #FixtureRefunds f ON f.PaymentID=p.PaymentID WHERE f.RefundStatus IN ('Pending','Completed') GROUP BY p.PaymentID,p.Amount HAVING SUM(f.Amount)>p.Amount) q) x;
INSERT #AuditResults SELECT 'DQ13_PaymentChronology','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixturePayments p JOIN #FixtureOrders o ON o.OrderID=p.OrderID WHERE p.Amount<=0 OR p.CreatedAt<o.OrderDate OR p.CompletedAt<p.CreatedAt OR (p.PaymentStatus='Completed' AND p.CompletedAt IS NULL) OR (p.PaymentStatus IN ('Pending','Failed') AND p.CompletedAt IS NOT NULL)) x;
INSERT #AuditResults SELECT 'DQ14_CollectedVsPayable','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureOrders o JOIN (SELECT OrderID,CAST(SUM(LinePayableAmount) AS decimal(28,2)) Payable FROM #FixtureOrderItems GROUP BY OrderID) i ON i.OrderID=o.OrderID LEFT JOIN (SELECT OrderID,SUM(Amount) Captured FROM #FixturePayments WHERE PaymentStatus='Completed' GROUP BY OrderID) p ON p.OrderID=o.OrderID WHERE COALESCE(p.Captured,0)>i.Payable+o.ShippingFee OR (o.OrderStatus='Delivered' AND COALESCE(p.Captured,0)<>i.Payable+o.ShippingFee)) x;
INSERT #AuditResults SELECT 'DQ15_ZeroPayableRefund','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureRefunds f JOIN #FixtureReturnItems ri ON ri.ReturnItemID=f.ReturnItemID JOIN #FixtureOrderItems i ON i.OrderItemID=ri.OrderItemID WHERE i.LinePayableAmount=0 AND f.RefundStatus IN ('Pending','Completed')) x;
INSERT #AuditResults SELECT 'DQ16_DuplicateHistoryEvent','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT OrderID,OrderStatus,ChangedAt FROM #FixtureOrderStatusHistory GROUP BY OrderID,OrderStatus,ChangedAt HAVING COUNT_BIG(*)>1) q) x;
INSERT #AuditResults SELECT 'DQ17_LatestHistoryMatches','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureOrders o LEFT JOIN (SELECT OrderID,OrderStatus,ROW_NUMBER() OVER(PARTITION BY OrderID ORDER BY ChangedAt DESC,OrderStatusHistoryID DESC) rn FROM #FixtureOrderStatusHistory) h ON h.OrderID=o.OrderID AND h.rn=1 WHERE h.OrderID IS NULL OR h.OrderStatus<>o.OrderStatus) x;
INSERT #AuditResults SELECT 'DQ18_HistoryContradictions','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM
(SELECT OrderStatus,LAG(OrderStatus) OVER(PARTITION BY OrderID ORDER BY ChangedAt,OrderStatusHistoryID) prev FROM #FixtureOrderStatusHistory) h
WHERE (prev IS NULL AND OrderStatus<>'Pending') OR (prev IS NOT NULL AND NOT
((prev='Pending' AND OrderStatus IN ('Processing','Cancelled')) OR
 (prev='Processing' AND OrderStatus IN ('Shipped','Cancelled')) OR
 (prev='Shipped' AND OrderStatus='Delivered')))) x;
INSERT #AuditResults SELECT 'DQ19_HistoryDates','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureOrderStatusHistory h JOIN #FixtureOrders o ON o.OrderID=h.OrderID WHERE h.ChangedAt<o.OrderDate OR (h.OrderStatus='Pending' AND h.ChangedAt<>o.OrderDate) OR (h.OrderStatus='Shipped' AND (o.ShippedAt IS NULL OR h.ChangedAt<>o.ShippedAt)) OR (h.OrderStatus='Delivered' AND (o.DeliveredAt IS NULL OR h.ChangedAt<>o.DeliveredAt)) OR (h.OrderStatus='Cancelled' AND (o.CancelledAt IS NULL OR h.ChangedAt<>o.CancelledAt))) x;
INSERT #AuditResults SELECT 'DQ20_BusinessKey','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT PaymentProvider,TransactionReference FROM #FixturePayments WHERE TransactionReference IS NOT NULL GROUP BY PaymentProvider,TransactionReference HAVING COUNT_BIG(*)>1) q) x;
INSERT #AuditResults SELECT 'DQ21_BusinessKey','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT Provider,TransactionReference FROM #FixtureRefunds WHERE TransactionReference IS NOT NULL GROUP BY Provider,TransactionReference HAVING COUNT_BIG(*)>1) q) x;
INSERT #AuditResults SELECT 'DQ22_BusinessKey','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT OrderID,LineNumber FROM #FixtureOrderItems  GROUP BY OrderID,LineNumber HAVING COUNT_BIG(*)>1) q) x;
INSERT #AuditResults SELECT 'DQ23_BusinessKey','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT ReturnID,OrderItemID FROM #FixtureReturnItems  GROUP BY ReturnID,OrderItemID HAVING COUNT_BIG(*)>1) q) x;
INSERT #AuditResults SELECT 'DQ24_BusinessKey','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM (SELECT SKU FROM #FixtureProducts  GROUP BY SKU HAVING COUNT_BIG(*)>1) q) x;
INSERT #AuditResults SELECT 'DQ25_Orphan_Products_CategoryID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureProducts c LEFT JOIN #FixtureCategories p ON c.CategoryID=p.CategoryID WHERE p.CategoryID IS NULL) x;
INSERT #AuditResults SELECT 'DQ26_Orphan_Orders_CustomerID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureOrders c LEFT JOIN #FixtureCustomers p ON c.CustomerID=p.CustomerID WHERE p.CustomerID IS NULL) x;
INSERT #AuditResults SELECT 'DQ27_Orphan_OrderAddresses_OrderID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureOrderAddresses c LEFT JOIN #FixtureOrders p ON c.OrderID=p.OrderID WHERE p.OrderID IS NULL) x;
INSERT #AuditResults SELECT 'DQ28_Orphan_OrderItems_OrderID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureOrderItems c LEFT JOIN #FixtureOrders p ON c.OrderID=p.OrderID WHERE p.OrderID IS NULL) x;
INSERT #AuditResults SELECT 'DQ29_Orphan_OrderItems_ProductID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureOrderItems c LEFT JOIN #FixtureProducts p ON c.ProductID=p.ProductID WHERE p.ProductID IS NULL) x;
INSERT #AuditResults SELECT 'DQ30_Orphan_Payments_OrderID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixturePayments c LEFT JOIN #FixtureOrders p ON c.OrderID=p.OrderID WHERE p.OrderID IS NULL) x;
INSERT #AuditResults SELECT 'DQ31_Orphan_Returns_OrderID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureReturns c LEFT JOIN #FixtureOrders p ON c.OrderID=p.OrderID WHERE p.OrderID IS NULL) x;
INSERT #AuditResults SELECT 'DQ32_Orphan_ReturnItems_ReturnID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureReturnItems c LEFT JOIN #FixtureReturns p ON c.ReturnID=p.ReturnID WHERE p.ReturnID IS NULL) x;
INSERT #AuditResults SELECT 'DQ33_Orphan_ReturnItems_OrderItemID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureReturnItems c LEFT JOIN #FixtureOrderItems p ON c.OrderItemID=p.OrderItemID WHERE p.OrderItemID IS NULL) x;
INSERT #AuditResults SELECT 'DQ34_Orphan_Refunds_PaymentID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureRefunds c LEFT JOIN #FixturePayments p ON c.PaymentID=p.PaymentID WHERE p.PaymentID IS NULL) x;
INSERT #AuditResults SELECT 'DQ35_Orphan_Refunds_ReturnItemID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureRefunds c LEFT JOIN #FixtureReturnItems p ON c.ReturnItemID=p.ReturnItemID WHERE p.ReturnItemID IS NULL) x;
INSERT #AuditResults SELECT 'DQ36_Orphan_OrderStatusHistory_OrderID','0',CONVERT(nvarchar(200),n),CASE WHEN n=0 THEN 'PASS' ELSE 'FAIL' END FROM (SELECT COUNT_BIG(*) n FROM #FixtureOrderStatusHistory c LEFT JOIN #FixtureOrders p ON c.OrderID=p.OrderID WHERE p.OrderID IS NULL) x;
;WITH Entitlement AS
(
 SELECT ri.ReturnItemID,ri.Quantity,ri.EligibleRefundAmount,i.Quantity SoldQuantity,i.LinePayableAmount,
 SUM(CONVERT(bigint,ri.Quantity)) OVER(PARTITION BY i.OrderItemID ORDER BY r.RequestedAt,r.ReturnID,ri.ReturnItemID ROWS UNBOUNDED PRECEDING) CQ
 FROM #FixtureReturnItems ri JOIN #FixtureReturns r ON r.ReturnID=ri.ReturnID
 JOIN #FixtureOrderItems i ON i.OrderItemID=ri.OrderItemID WHERE ri.DecisionStatus<>'Rejected'
)
INSERT #AuditResults
SELECT 'DQ37_EntitlementRounding','0',CONVERT(nvarchar(200),COUNT_BIG(*)),CASE WHEN COUNT_BIG(*)=0 THEN 'PASS' ELSE 'FAIL' END
FROM Entitlement WHERE EligibleRefundAmount<>
ROUND(LinePayableAmount*CQ/NULLIF(SoldQuantity,0),2)-ROUND(LinePayableAmount*(CQ-Quantity)/NULLIF(SoldQuantity,0),2);


SELECT * FROM #AuditResults ORDER BY TestID;
IF EXISTS(SELECT 1 FROM #AuditResults WHERE Result='FAIL') THROW 53400,'Fixture integrity gate failed.',1;
GO


CREATE TABLE #TargetChecks(TestID varchar(90) PRIMARY KEY,Expected nvarchar(100),Actual nvarchar(100),Result varchar(10));
INSERT #FixtureCustomers(FirstName,LastName,CountryCode,CreatedAt)
VALUES('NoPurchase','Edge','US','2026-01-01');
INSERT #FixtureOrderItems(OrderID,LineNumber,ProductID,Quantity,UnitPrice,UnitCostAtOrder,TaxAmount)
SELECT MAX(OrderID),3,(SELECT MIN(ProductID) FROM #FixtureProducts),1,0,0,0 FROM #FixtureOrders;
GO
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


GO
SET NOCOUNT ON;

-- REQUIRED coverage assertion: do not infer extraction coverage from purchases.
-- Large seed: 2026-10-01T00:00:00 (documented exclusive UTC cutoff).
-- Small demo policy selected with user authorization: observe through August 2026.
-- For the large seed set the declaration below to 2026-10-01T00:00:00.
-- This is a retrospective snapshot report, not historical status reconstruction.
DECLARE @ObservationCutoffExclusive datetime2(0)='2026-09-15T00:00:00';
IF @ObservationCutoffExclusive IS NULL
    THROW 50008, 'Set the verified exclusive UTC dataset coverage cutoff.', 1;
IF EXISTS
(
    SELECT 1 FROM
    (
        SELECT OrderDate EventAt FROM #FixtureOrders
        UNION ALL SELECT ShippedAt FROM #FixtureOrders
        UNION ALL SELECT DeliveredAt FROM #FixtureOrders
        UNION ALL SELECT CancelledAt FROM #FixtureOrders
        UNION ALL SELECT ChangedAt FROM #FixtureOrderStatusHistory
        UNION ALL SELECT CreatedAt FROM #FixturePayments
        UNION ALL SELECT CompletedAt FROM #FixturePayments
        UNION ALL SELECT RequestedAt FROM #FixtureReturns
        UNION ALL SELECT ReceivedAt FROM #FixtureReturns
        UNION ALL SELECT DecidedAt FROM #FixtureReturnItems
        UNION ALL SELECT CreatedAt FROM #FixtureRefunds
        UNION ALL SELECT CompletedAt FROM #FixtureRefunds
    ) e WHERE EventAt>=@ObservationCutoffExclusive
)
    THROW 50009, 'Snapshot contains events at/after cutoff; use a matching snapshot.', 1;
DECLARE @ObservationEndMonth date=DATEFROMPARTS(
    YEAR(DATEADD(SECOND,-1,@ObservationCutoffExclusive)),
    MONTH(DATEADD(SECOND,-1,@ObservationCutoffExclusive)),1);


IF NOT EXISTS(SELECT 1 FROM #FixtureOrders WHERE OrderStatus='Delivered')
BEGIN
    THROW 50007, 'No delivered orders are available for cohort analysis.', 1;
END;

DROP TABLE IF EXISTS #CohortPurchases;
DROP TABLE IF EXISTS #CohortRetention;

/* Build refund-adjusted order revenue before assigning purchase sequence. */
;WITH ItemTotals AS
(
    SELECT OrderID,CAST(SUM(NetMerchandiseAmount) AS decimal(28,2)) AS MerchandiseSales
    FROM #FixtureOrderItems
    GROUP BY OrderID
), RefundCashByItem AS
(
    SELECT ri.OrderItemID,CAST(SUM(r.Amount) AS decimal(18,2)) AS CompletedRefundAmount
    FROM #FixtureRefunds r
    JOIN #FixtureReturnItems ri ON ri.ReturnItemID=r.ReturnItemID
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
    JOIN #FixtureOrderItems oi ON oi.OrderItemID=rc.OrderItemID
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
    FROM #FixtureOrders o
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
INTO #EdgeMatrix
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
INTO #EdgeRates
FROM CohortRates
ORDER BY CohortMonth,AcquisitionChannelRankWithinCohort,AcquisitionChannel;

GO

/* DEMO INTERPRETATION
   - The small seed has four purchasing customers and no repeat customer.
   - Every cohort has M0=100%; observable later months equal 0%.
   - Future, unobservable months are NULL in the matrix.
   - Zero repeat retention reflects the compact demo seed, not a query error.
   Use the larger mock-data script for a meaningful retention heatmap.
*/

GO

INSERT #TargetChecks
SELECT 'EDGE01_SameMonthDistinctCustomer','1',CONVERT(nvarchar(100),ActiveCustomerCount),CASE WHEN ActiveCustomerCount=1 AND DeliveredOrderCount=2 THEN 'PASS' ELSE 'FAIL' END
FROM #CohortRetention WHERE CohortMonth='20260101' AND MonthIndex=0;
INSERT #TargetChecks
SELECT 'EDGE02_ObservedMissingMonthZero','0',CONVERT(nvarchar(100),M1),CASE WHEN M1=0 THEN 'PASS' ELSE 'FAIL' END FROM #EdgeMatrix WHERE CohortMonth='20260101';
INSERT #TargetChecks
SELECT 'EDGE03_FutureMonthNull','NULL',COALESCE(CONVERT(nvarchar(100),M9),'NULL'),CASE WHEN M9 IS NULL THEN 'PASS' ELSE 'FAIL' END FROM #EdgeMatrix WHERE CohortMonth='20260101';
INSERT #TargetChecks
SELECT 'EDGE04_PartialMonthFlag','1',CONVERT(nvarchar(100),IsLastMonthPartial),CASE WHEN IsLastMonthPartial=1 AND LastObservedMonth='20260901' THEN 'PASS' ELSE 'FAIL' END FROM #EdgeMatrix WHERE CohortMonth='20260101';
INSERT #TargetChecks
SELECT 'EDGE05_TimestampTieFirstChannel','Website',AcquisitionChannel,CASE WHEN AcquisitionChannel='Website' THEN 'PASS' ELSE 'FAIL' END FROM #CohortPurchases WHERE CustomerID=(SELECT MIN(CustomerID) FROM #FixtureCustomers) AND PurchaseNumber=1;
INSERT #TargetChecks
SELECT 'EDGE06_ZeroRevenueShareNull','NULL',COALESCE(CONVERT(nvarchar(100),RepeatRevenueSharePct),'NULL'),CASE WHEN ObservedCohortRevenue=0 AND RepeatRevenueSharePct IS NULL THEN 'PASS' ELSE 'FAIL' END FROM #EdgeRates WHERE CohortMonth='20260201' AND AcquisitionChannel='App';
INSERT #TargetChecks
SELECT 'EDGE07_ZeroPriceItemOrderRevenue','1.98',CONVERT(nvarchar(100),NetRevenue),CASE WHEN NetRevenue=1.98 THEN 'PASS' ELSE 'FAIL' END FROM #CohortPurchases WHERE OrderID=(SELECT MAX(OrderID) FROM #FixtureOrders);

GO
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

GO
SET NOCOUNT ON;

DROP TABLE IF EXISTS #CustomerPurchases;

;WITH ItemTotals AS
(
    -- One row per order prevents item/payment join duplication.
    SELECT OrderID, CAST(SUM(NetMerchandiseAmount) AS decimal(28,2)) AS MerchandiseSales
    FROM #FixtureOrderItems
    GROUP BY OrderID
), RefundCashByItem AS
(
    SELECT ri.OrderItemID,CAST(SUM(r.Amount) AS decimal(18,2)) AS CompletedRefundAmount
    FROM #FixtureRefunds r
    JOIN #FixtureReturnItems ri ON ri.ReturnItemID=r.ReturnItemID
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
    JOIN #FixtureOrderItems oi ON oi.OrderItemID=rc.OrderItemID
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
    FROM #FixtureOrders AS o
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
    FROM #FixtureCustomers AS c
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
INTO #EdgeCustomerMetrics
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

INSERT #TargetChecks
SELECT 'EDGE08_NoPurchaseCustomer','0 / NULL',CONCAT(DeliveredOrderCount,' / ',COALESCE(CONVERT(nvarchar(100),CustomerAOV),'NULL')),
CASE WHEN DeliveredOrderCount=0 AND CustomerAOV IS NULL AND RevenueRank IS NULL AND CustomerSegment='No purchase' THEN 'PASS' ELSE 'FAIL' END
FROM #EdgeCustomerMetrics WHERE CustomerID=(SELECT MAX(CustomerID) FROM #FixtureCustomers);
IF (SELECT COUNT(*) FROM #TargetChecks)<>8 THROW 53600,'Missing targeted output rows.',1;
SELECT * FROM #TargetChecks ORDER BY TestID;
IF EXISTS(SELECT 1 FROM #TargetChecks WHERE Result<>'PASS') THROW 53601,'Targeted output check failed.',1;
PRINT 'TARGETED_COHORT_CUSTOMER_CHECKS_COMPLETE';
GO
