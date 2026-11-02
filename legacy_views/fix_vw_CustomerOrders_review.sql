/* Owner-selected legacy semantics: all order statuses, historical gross
   merchandise before discounts/refunds; tax and shipping excluded.
   REVIEW PATCH ONLY; test on disposable database before live deployment. */
ALTER VIEW dbo.vw_CustomerOrders
AS
SELECT c.CustomerID,c.FirstName,c.LastName,
       COUNT(DISTINCT o.OrderID) AS TotalOrders,
       SUM(oi.Quantity*oi.UnitPrice) AS TotalAmount
FROM dbo.Customers AS c
INNER JOIN dbo.Orders AS o ON c.CustomerID=o.CustomerID
INNER JOIN dbo.OrderItems AS oi ON o.OrderID=oi.OrderID
GROUP BY c.CustomerID,c.FirstName,c.LastName;
GO
