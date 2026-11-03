USE OnlineRetailDB;
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

IF DB_NAME() <> N'OnlineRetailDB'
    THROW 51000, 'Run this script inside OnlineRetailDB.', 1;

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
