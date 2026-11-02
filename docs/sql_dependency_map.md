# SQL dependency map

| Final report file | Direct dbo references |
|---|---|
| O.R.DB cohort retention analysist.sql | OrderItems, OrderStatusHistory, Orders, Payments, Refunds, ReturnItems, Returns |
| O.R.DB customer analysist.sql | Customers, OrderItems, Orders, Refunds, ReturnItems |
| O.R.DB fulfillment_delivery analysist.sql | OrderStatusHistory, Orders |
| O.R.DB return_refund analysist.sql | Categories, OrderItems, Orders, Products, Refunds, ReturnItems, Returns |
| OnlineRetailDB Querry.sql | Categories, OrderItems, OrderStatusHistory, Orders, Payments, Products, Refunds, ReturnItems, Returns |

Schema defines eleven retail tables: Categories, Customers, Products, Orders, OrderAddresses, OrderItems, Payments, OrderStatusHistory, Returns, ReturnItems, Refunds. Reports create session-local analytical facts; fixtures use #Fixture counterparts. G uses #CohortPurchases, D uses #CustomerPurchases.

Live metadata: CustomerOrders depends on Customers/Orders/OrderItems/Products; ProductDeails on Products/Categories; RecentOrders on Customers/Orders/OrderItems. Corrected CustomerOrders removes the Products join. Live views are unchanged. sp_*diagram and fn_diagramobjects are SSMS infrastructure. Complete columns/definitions are in evidence/runtime_live_view_details.txt.
