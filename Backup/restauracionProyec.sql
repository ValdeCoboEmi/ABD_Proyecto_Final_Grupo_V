
USE msdb;
GO

SELECT 
    b.database_name AS Base_Datos,
    CASE b.type 
        WHEN 'D' THEN 'Full (Completo)'
        WHEN 'I' THEN 'Diferencial'
        WHEN 'L' THEN 'Log de Transacciones'
    END AS Tipo_Backup,
    f.physical_device_name AS Ruta_Completa_Archivo,
    b.backup_start_date AS Fecha_Y_Hora
FROM msdb.dbo.backupset b
JOIN msdb.dbo.backupmediafamily f ON b.media_set_id = f.media_set_id
WHERE b.database_name = N'HotelDB'
ORDER BY b.backup_start_date DESC;
GO

USE master;
GO

---Si la base existela borramos por completo
IF EXISTS (SELECT name FROM sys.databases WHERE name = N'HotelDB')
BEGIN
    DROP DATABASE [HotelDB];
END
GO

--Restaurar el Respaldo Full con NORECOVERY
RESTORE DATABASE [HotelDB] 
FROM DISK = N'/backup/HotelDB_Full_20261109_014956.bak'
WITH 
    REPLACE,         
    NORECOVERY,      
    STATS = 10;
GO

--Restaurar el Respaldo Diferencial con NORECOVERY
RESTORE DATABASE [HotelDB] 
FROM DISK = N'/backup/HotelDB_Diff_Diario.bak' 
WITH 
    NORECOVERY,      
    STATS = 10;
GO

--Restaurar el Respaldo de Log NORECOVERY
RESTORE LOG [HotelDB] 
FROM DISK = N'/backup/HotelDB_Log_15min.trn' 
WITH 
    NORECOVERY,      
    STATS = 10;
GO

RESTORE LOG [HotelDB] WITH RECOVERY;
GO

ALTER DATABASE [HotelDB] SET MULTI_USER;
GO

--Verificación final de datos restaurados
USE HotelDB;
GO

SELECT 'Huéspedes' AS Tabla, COUNT(*) AS Total FROM operacion.huesped
UNION ALL
SELECT 'Reservaciones' AS Tabla, COUNT(*) AS Total FROM operacion.reservacion
UNION ALL
SELECT 'Facturas' AS Tabla, COUNT(*) AS Total FROM facturacion.factura;
GO

DBCC CHECKDB ('HotelDB');
GO