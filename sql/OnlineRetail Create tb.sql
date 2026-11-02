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
IF DB_ID(N'OnlineRetailDB') IS NOT NULL
    THROW 50001, 'Database already exists. Setup stopped without changes.', 1;
EXEC(N'CREATE DATABASE OnlineRetailDB');
EXEC(N'USE OnlineRetailDB;
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
