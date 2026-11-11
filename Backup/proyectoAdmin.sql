USE master;
GO

-- Forzar desconexión de usuarios activos
ALTER DATABASE HotelDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO

-- Restaurar el respaldo inicial
RESTORE DATABASE HotelDB
FROM DISK = '/backup/cenitDB-backup-30-09-2026.bak' -- Semanal
WITH RECOVERY, REPLACE, STATS = 10;
GO

ALTER DATABASE HotelDB SET MULTI_USER;
GO

    ---semana 1 y 2 --
--- Recovery full
ALTER DATABASE HotelDB SET RECOVERY FULL;
GO

USE HotelDB;
GO

INSERT INTO operacion.huesped (nombre, correo, telefono, documento, tipo_documento)
VALUES ('Villegas', 'Gayse2@hoteldb.com', '5455-5545', '1234000-1', 'DUI');
GO

-- Monitoreo previo del espacio del Log
DBCC SQLPERF(LOGSPACE);
GO


--respaldos manuales Full, Diff, Log
BACKUP DATABASE HotelDB
TO DISK = '/backup/HotelDB_Full_Semanal.bak'
WITH FORMAT, COMPRESSION,
     NAME = 'HotelDB - Backup Completo Semanal',
     STATS = 10;
GO

BACKUP DATABASE HotelDB
TO DISK = '/backup/HotelDB_Diff_Diario.bak'
WITH FORMAT, COMPRESSION,
     NAME = 'HotelDB - Backup Diferencial Diario',
     STATS = 10;
GO

BACKUP LOG HotelDB
TO DISK = '/backup/HotelDB_Log_15min.trn'
WITH FORMAT, COMPRESSION,
     NAME = 'HotelDB - Backup Log de Transacciones',
     STATS = 10;
GO



-- restauracion encadenada Full + Diff + Log

USE master;
GO

-- Desconectar sesiones para evitar el error de base en uso
ALTER DATABASE HotelDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO

--Restaurar Full
RESTORE DATABASE HotelDB
FROM DISK = '/backup/HotelDB_Full_Semanal.bak'
WITH NORECOVERY, REPLACE, STATS = 10;
GO

--Restaurar Diff
RESTORE DATABASE HotelDB
FROM DISK = '/backup/HotelDB_Diff_Diario.bak'
WITH NORECOVERY, STATS = 10;
GO

--Restaurar Log
RESTORE LOG HotelDB
FROM DISK = '/backup/HotelDB_Log_15min.trn'
WITH RECOVERY, STATS = 10;
GO

ALTER DATABASE HotelDB SET MULTI_USER;
GO



--Ver si estan los datos

USE HotelDB;
GO

-- Conteo general de registros
SELECT 'Huéspedes' AS Tabla, COUNT(*) AS Total FROM operacion.huesped
UNION ALL
SELECT 'Reservaciones' AS Tabla, COUNT(*) AS Total FROM operacion.reservacion
UNION ALL
SELECT 'Facturas' AS Tabla, COUNT(*) AS Total FROM facturacion.factura;
GO

DBCC CHECKDB ('HotelDB');
GO


------------------------------------------------------------------------------------------
---semana 3 ---

USE msdb;
GO

USE msdb;
GO

-- =========================================================================
-- 0. LIMPIEZA PREVIA (Elimina los jobs si ya existen para evitar duplicados)
-- =========================================================================
IF EXISTS (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'HotelDB_Auto_Backup_Full')
    EXEC dbo.sp_delete_job @job_name = N'HotelDB_Auto_Backup_Full';

IF EXISTS (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'HotelDB_Auto_Backup_Diff')
    EXEC dbo.sp_delete_job @job_name = N'HotelDB_Auto_Backup_Diff';

IF EXISTS (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'HotelDB_Auto_Backup_Log')
    EXEC dbo.sp_delete_job @job_name = N'HotelDB_Auto_Backup_Log';
GO

-- =========================================================================
-- 1. JOB PARA BACKUP FULL (Semanal)
-- =========================================================================
EXEC dbo.sp_add_job 
    @job_name = N'HotelDB_Auto_Backup_Full',
    @enabled = 1,
    @description = N'Automatización del respaldo completo semanal con nombre dinámico';

EXEC dbo.sp_add_jobstep 
    @job_name = N'HotelDB_Auto_Backup_Full',
    @step_name = N'Paso_Backup_Full',
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @Archivo NVARCHAR(500);
        SET @Archivo = N''/backup/HotelDB_Full_'' + CONVERT(VARCHAR(8), GETDATE(), 112) +''_'' + REPLACE(CONVERT(VARCHAR(8), GETDATE(), 108), '':'', '''') + ''.bak'';
        BACKUP DATABASE [HotelDB] TO DISK = @Archivo WITH FORMAT, COMPRESSION, NAME = ''HotelDB - Full Dinamico'', STATS = 10;
    ',
    @database_name = N'master';

-- Programación automática: Cada semana (Lunes a las 00:00 hrs)
EXEC dbo.sp_add_jobschedule 
    @job_name = N'HotelDB_Auto_Backup_Full',
    @name = N'Calendario_Semanal',
    @freq_type = 8,              -- Semanal
    @freq_interval = 2,          -- 2 = Lunes
    @freq_recurrence_factor = 1, -- Cada 1 semana
    @active_start_time = 000000;

EXEC dbo.sp_add_jobserver 
    @job_name = N'HotelDB_Auto_Backup_Full';
GO

-- =========================================================================
-- 2. JOB PARA BACKUP DIFERENCIAL (Diario)
-- =========================================================================
EXEC dbo.sp_add_job 
    @job_name = N'HotelDB_Auto_Backup_Diff',
    @enabled = 1,
    @description = N'Automatización del respaldo diferencial diario con nombre dinámico';

EXEC dbo.sp_add_jobstep 
    @job_name = N'HotelDB_Auto_Backup_Diff',
    @step_name = N'Paso_Backup_Diff',
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @Archivo NVARCHAR(500);
        SET @Archivo = N''/backup/HotelDB_Diff_'' + CONVERT(VARCHAR(8), GETDATE(), 112) +''_'' + REPLACE(CONVERT(VARCHAR(8), GETDATE(), 108), '':'', '''') + ''.bak'';
        BACKUP DATABASE [HotelDB] TO DISK = @Archivo WITH FORMAT, COMPRESSION, DIFFERENTIAL, NAME = ''HotelDB - Diff Dinamico'', STATS = 10;
    ',
    @database_name = N'master';

-- Programación automática: Diario (Todos los días a la 01:00 AM)
EXEC dbo.sp_add_jobschedule 
    @job_name = N'HotelDB_Auto_Backup_Diff',
    @name = N'Calendario_Diario',
    @freq_type = 4,              -- Diario
    @freq_interval = 1,          -- Cada 1 día
    @active_start_time = 010000;

EXEC dbo.sp_add_jobserver 
    @job_name = N'HotelDB_Auto_Backup_Diff';
GO


-- 3. JOB PARA BACKUP DE LOG (Cada 15 minutos)
EXEC dbo.sp_add_job 
    @job_name = N'HotelDB_Auto_Backup_Log',
    @enabled = 1,
    @description = N'Automatización del respaldo de logs cada 15 min con nombre dinámico';

EXEC dbo.sp_add_jobstep 
    @job_name = N'HotelDB_Auto_Backup_Log',
    @step_name = N'Paso_Backup_Log',
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @Archivo NVARCHAR(500);
        SET @Archivo = N''/backup/HotelDB_Log_'' + CONVERT(VARCHAR(8), GETDATE(), 112) +''_'' + REPLACE(CONVERT(VARCHAR(8), GETDATE(), 108), '':'', '''') + ''.trn'';
        BACKUP LOG [HotelDB] TO DISK = @Archivo WITH COMPRESSION, NOINIT, NAME = ''HotelDB - Log Dinamico'', STATS = 10;
    ',
    @database_name = N'master';

-- Programación automática: Cada 15 minutos de forma continua
EXEC dbo.sp_add_jobschedule 
    @job_name = N'HotelDB_Auto_Backup_Log',
    @name = N'Calendario_Cada_15_Minutos',
    @freq_type = 4,              -- Diario
    @freq_interval = 1,          -- Cada 1 día
    @freq_subday_type = 4,       -- Repetición en minutos
    @freq_subday_interval = 15,  -- Cada 15 minutos
    @active_start_time = 000000;

EXEC dbo.sp_add_jobserver 
    @job_name = N'HotelDB_Auto_Backup_Log';
GO
-- Prueba manual
EXEC msdb.dbo.sp_start_job @job_name = N'HotelDB_Auto_Backup_Full';
GO

EXEC msdb.dbo.sp_start_job @job_name = N'HotelDB_Auto_Backup_Diff';
GO

EXEC msdb.dbo.sp_start_job @job_name = N'HotelDB_Auto_Backup_Log';
GO

-----semana4-----

USE msdb;
GO
----Historial de ejecucion de los jobs----
SELECT 
    j.name AS Nombre_Job,
    h.step_name AS Paso,
    -- Convierte la fecha y hora numérica de SQL a un formato legible
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS Fecha_Hora_Ejecucion,
    -- 0 = Fracasado, 1 = Exitoso, 3 = Cancelado
    CASE h.run_status 
        WHEN 0 then 'Fallido'
        WHEN 1 then 'Exitoso'
        WHEN 2 then 'Reintentando'
        WHEN 3 then 'Cancelado'
        ELSE 'Desconocido'
    END AS Estado_Ejecucion,
    -- Duración del proceso en formato hh:mm:ss
    STUFF(STUFF(RIGHT('000000' + CAST(h.run_duration AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') AS Duracion
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE j.name LIKE N'HotelDB_Auto_Backup%'
ORDER BY Fecha_Hora_Ejecucion DESC;
GO

---backups generados---

SELECT 
    b.database_name AS Base_Datos,
    CASE b.type 
        WHEN 'D' THEN 'Respaldo Full (Completo)'
        WHEN 'I' THEN 'Respaldo Diferencial'
        WHEN 'L' THEN 'Respaldo de Log'
    END AS Tipo_Backup,
    f.physical_device_name AS Ruta_Y_Nombre_Archivo,
    b.backup_start_date AS Fecha_Creacion,
    CAST(b.backup_size / 1024 / 1024 AS DECIMAL(10,2)) AS Tamano_MB
FROM msdb.dbo.backupset b
JOIN msdb.dbo.backupmediafamily f ON b.media_set_id = f.media_set_id
WHERE b.database_name = N'HotelDB'
ORDER BY b.backup_start_date DESC;
GO



