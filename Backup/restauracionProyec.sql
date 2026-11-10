
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

---- 1. Si la base existe (incluso colgada en restoring), la borramos por completo
IF EXISTS (SELECT name FROM sys.databases WHERE name = N'HotelDB')
BEGIN
    DROP DATABASE [HotelDB];
END
GO

-- 2. Restaurar el Respaldo Full (Completo) con NORECOVERY
RESTORE DATABASE [HotelDB] 
FROM DISK = N'/backup/HotelDB_Full_20261109_014956.bak'  -- (O usa el nombre dinámico generado ej: /backup/HotelDB_Full_20261104_XXXXXX.bak)
WITH 
    REPLACE,         
    NORECOVERY,      
    STATS = 10;
GO

-- 3. Restaurar el Respaldo Diferencial con NORECOVERY
RESTORE DATABASE [HotelDB] 
FROM DISK = N'/backup/HotelDB_Diff_Diario.bak'   -- (O el archivo diferencial dinámico correspondiente)
WITH 
    NORECOVERY,      
    STATS = 10;
GO

-- 4. Restaurar el Respaldo de Log en orden cronológico con NORECOVERY
-- *(Asegúrate de colocar el nombre exacto del archivo .trn que exista en tu carpeta)*
RESTORE LOG [HotelDB] 
FROM DISK = N'/backup/HotelDB_Log_15min.trn' 
WITH 
    NORECOVERY,      
    STATS = 10;
GO

-- 5. Cierre de la cadena con RECOVERY (Pone la base en línea y usable)
RESTORE LOG [HotelDB] WITH RECOVERY;
GO

-- 6. Devolver la base de datos a modo multi-usuario
ALTER DATABASE [HotelDB] SET MULTI_USER;
GO

-- 7. Verificación final de datos restaurados e integridad
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