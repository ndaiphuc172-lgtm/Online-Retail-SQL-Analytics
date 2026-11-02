/* Connect explicitly to the intended server, master database. Read only.
Record environment disposability separately with the owner before ANY setup/seed.
No connection string or credentials should be saved in evidence. */
SET NOCOUNT ON;
SELECT CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) ServerName,
 CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion')) ProductVersion,
 CONVERT(nvarchar(128),SERVERPROPERTY('Edition')) Edition,DB_NAME() ConnectedDatabase;
SELECT name,compatibility_level,state_desc,is_read_only FROM sys.databases WHERE name=N'OnlineRetailDB';
SELECT 'ENV01' TestID,'Owner confirms disposable target before writes' Expected,
 'Not inferable from database name' Actual,'BLOCKED' Result;
