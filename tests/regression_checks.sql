/* Rebuilt regression checks. Session-local fixtures only. SQL Server 2016+.
   These assertions supplement actual-module integration; they are not evidence
   that every analytical output is correct. Run the entire file. */
SET NOCOUNT ON;
DROP TABLE IF EXISTS #Regression;
CREATE TABLE #Regression(TestID varchar(80) PRIMARY KEY,Expected decimal(28,8),Actual decimal(28,8));
DECLARE @Cases TABLE(TestID varchar(80),CashCents decimal(18,0),MerchCents decimal(18,0),PayableCents decimal(18,0),ExpectedCents decimal(18,0));
INSERT @Cases VALUES
('FIN01_BelowHalfCent',1,499999999999999999,999999999999999999,0),
('FIN02_ExactHalfCent',1,1,2,1),
('FIN03_AboveHalfCent',1,500000000000000000,999999999999999999,1),
('FIN04_FullRefundLarge',999999999999999999,499999999999999999,999999999999999999,499999999999999999),
('FIN05_ZeroCash',0,100,108,0);
INSERT #Regression
SELECT TestID,ExpectedCents,
 (a.Numerator-(a.Numerator % PayableCents))/PayableCents
 +CASE WHEN (a.Numerator % PayableCents)*2>=PayableCents THEN 1 ELSE 0 END
FROM @Cases c CROSS APPLY(VALUES(c.CashCents*c.MerchCents)) a(Numerator);
INSERT #Regression VALUES('FIN06_RoundedRefundIdentity',0.99,CAST(1.00-CAST(ROUND(CAST(0.005 AS decimal(18,8)),2) AS decimal(18,2)) AS decimal(18,2)));
DECLARE @Money TABLE(Gross decimal(18,2),Refund decimal(18,2));
INSERT @Money VALUES(30.00,0.01),(66.00,0.01),(1.00,0.01);
INSERT #Regression SELECT 'FIN07_AggregatePrecision',96.97,CAST(SUM(Gross) AS decimal(28,2))-CAST(SUM(Refund) AS decimal(28,2)) FROM @Money;
DECLARE @SLA TABLE(TestID varchar(80),LimitSeconds int,ObservedSeconds int,Expected int);
INSERT @SLA VALUES
('SLA01_ShipBelow',172800,172799,0),('SLA02_ShipEqual',172800,172800,0),('SLA03_ShipAbove',172800,172801,1),
('SLA04_TransitBelow',259200,259199,0),('SLA05_TransitEqual',259200,259200,0),('SLA06_TransitAbove',259200,259201,1),
('SLA07_TotalBelow',432000,431999,0),('SLA08_TotalEqual',432000,432000,0),('SLA09_TotalAbove',432000,432001,1);
INSERT #Regression SELECT TestID,Expected,CASE WHEN ObservedSeconds>LimitSeconds THEN 1 ELSE 0 END FROM @SLA;
INSERT #Regression VALUES('SLA10_FractionalHours',1.5,DATEDIFF_BIG(SECOND,CAST('20260101' AS datetime2),CAST('2026-01-01T01:30:00' AS datetime2))/3600.0);
DECLARE @Attempts TABLE(OrderID int,Status varchar(20),CreatedAt datetime2);
INSERT @Attempts VALUES(1,'Completed','20260101'),(1,'Failed','20260102'),(2,'Failed','20260101'),(2,'Completed','20260102');
INSERT #Regression SELECT 'PAY01_EarlierSuccessNotRecovery',0,COUNT(*) FROM (SELECT DISTINCT f.OrderID FROM @Attempts f WHERE f.OrderID=1 AND f.Status='Failed' AND EXISTS(SELECT 1 FROM @Attempts s WHERE s.OrderID=f.OrderID AND s.Status='Completed' AND s.CreatedAt>f.CreatedAt)) q;
INSERT #Regression SELECT 'PAY02_LaterSuccessRecovery',1,COUNT(*) FROM (SELECT DISTINCT f.OrderID FROM @Attempts f WHERE f.OrderID=2 AND f.Status='Failed' AND EXISTS(SELECT 1 FROM @Attempts s WHERE s.OrderID=f.OrderID AND s.Status='Completed' AND s.CreatedAt>f.CreatedAt)) q;
DECLARE @Cutoff datetime2='2026-09-01T00:00:00';
INSERT #Regression VALUES('COH01_ExclusiveBoundary',0,CASE WHEN CAST('2026-09-01T00:00:00' AS datetime2)<@Cutoff THEN 1 ELSE 0 END),
('COH02_BeforeBoundary',1,CASE WHEN CAST('2026-08-31T23:59:59' AS datetime2)<@Cutoff THEN 1 ELSE 0 END),
('COH03_YearBoundary',1,DATEDIFF(MONTH,CAST('20251201' AS date),CAST('20260101' AS date)));
SELECT TestID,Expected,Actual,CASE WHEN Expected=Actual THEN 'PASS' ELSE 'FAIL' END Result FROM #Regression ORDER BY TestID;
IF EXISTS(SELECT 1 FROM #Regression WHERE Expected<>Actual OR Actual IS NULL) THROW 53500,'Regression failure; inspect result rows.',1;
PRINT 'ALL_REGRESSION_COMPLETE';
GO
