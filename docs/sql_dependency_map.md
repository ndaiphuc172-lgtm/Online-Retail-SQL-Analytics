# SQL dependency map

| Final report file | Direct dbo references |
|---|---|
| OnlineRetail - Cohort Retention.sql | OrderItems, OrderStatusHistory, Orders, Payments, Refunds, ReturnItems, Returns |
| OnlineRetail - Customer Analysis.sql | Customers, OrderItems, Orders, Refunds, ReturnItems |
| OnlineRetail - Delivery Analysis.sql | OrderStatusHistory, Orders |
| OnlineRetail - Return Refund Analysis.sql | Categories, OrderItems, Orders, Products, Refunds, ReturnItems, Returns |
| OnlineRetail - Sales Analysis.sql | Categories, OrderItems, OrderStatusHistory, Orders, Payments, Products, Refunds, ReturnItems, Returns |

Schema defines eleven retail tables: Categories, Customers, Products, Orders, OrderAddresses, OrderItems, Payments, OrderStatusHistory, Returns, ReturnItems, Refunds. Reports create session-local analytical facts; fixtures use #Fixture counterparts. G uses #CohortPurchases, D uses #CustomerPurchases.

The core A–G workflow does not require the legacy views found in the existing database. Their definitions, remediation and database-diagram infrastructure are excluded from this SQL-focused portfolio.
