/* REVIEW PATCH ONLY. Does not authorize execution on live OnlineRetailDB.
   Requires the existing dbo.vw_RecentOrders and verified OrderItems.UnitPrice.
   Fixes only the absent oi.Price reference; preserves all-order, before-discount
   merchandise amount and output columns. No time window is invented.
   Test in an authorized disposable database before any live deployment. */
ALTER VIEW dbo.vw_RecentOrders
AS
SELECT o.OrderID, o.OrderDate, c.CustomerID, c.FirstName, c.LastName,
       SUM(oi.Quantity * oi.UnitPrice) AS OrderAmount
FROM dbo.Customers AS c
INNER JOIN dbo.Orders AS o ON c.CustomerID=o.CustomerID
INNER JOIN dbo.OrderItems AS oi ON o.OrderID=oi.OrderID
GROUP BY o.OrderID,o.OrderDate,c.CustomerID,c.FirstName,c.LastName;
GO
