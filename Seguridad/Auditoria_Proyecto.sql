-- ==========================
-- AUDITORIA CONFIGURADA CON SQL SERVER AUDIT

USE master;
GO

-- 1. Crear el objeto Server Audit apuntando a una ruta en disco (ajusta la ruta según tu entorno)
IF EXISTS (SELECT * FROM sys.server_audits WHERE name = 'Audit_Cenit_Servidor')
BEGIN
    ALTER SERVER AUDIT Audit_Cenit_Servidor WITH (STATE = OFF);
    DROP SERVER AUDIT Audit_Cenit_Servidor;
END
GO

CREATE SERVER AUDIT Audit_Cenit_Servidor
TO FILE 
(
    FILEPATH = '/audit/Audit_Cenit', -- Asegúrate de que esta carpeta exista en el servidor o contenedor
    MAXSIZE = 100 MB,
    MAX_ROLLOVER_FILES = 5,
    RESERVE_DISK_SPACE = OFF
)
WITH 
(
    QUEUE_DELAY = 1000, -- 1 segundo de retraso máximo en escritura
    ON_FAILURE = CONTINUE
);
GO

-- Activar la auditoría a nivel de servidor
ALTER SERVER AUDIT Audit_Cenit_Servidor WITH (STATE = ON);
GO

-- 2. Crear la especificación de auditoría en la base de datos cenitDB
USE HotelDB;
GO

IF EXISTS (SELECT * FROM sys.database_audit_specifications WHERE name = 'AuditSpec_Facturacion_Sensible')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION AuditSpec_Facturacion_Sensible WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION AuditSpec_Facturacion_Sensible;
END
GO

CREATE DATABASE AUDIT SPECIFICATION AuditSpec_Facturacion_Sensible
FOR SERVER AUDIT Audit_Cenit_Servidor
    -- Auditar INSERTS y UPDATES en facturacion.factura ejecutados por cualquier usuario
    ADD (INSERT ON facturacion.factura BY public),
    ADD (UPDATE ON facturacion.factura BY public),
    -- Auditar INSERTS y UPDATES en facturacion.detalle_factura
    ADD (INSERT ON facturacion.detalle_factura BY public),
    ADD (UPDATE ON facturacion.detalle_factura BY public)
WITH (STATE = ON);
GO

-- Permisos
USE master;
GO

-- 1. Asegurar que el dueño de la base de datos sea 'sa'
ALTER AUTHORIZATION ON DATABASE::HotelDB TO sa;
GO

-- 2. Habilitar la confianza en la base de datos para permitir la ejecución de módulos con EXECUTE AS
ALTER DATABASE HotelDB SET TRUSTWORTHY ON;
GO

--- =======================
-- Verificacion y lectyura de registros auditados

UPDATE facturacion.factura 
SET metodo_pago = 'TARJETA' 
WHERE id_factura = 1;
GO
select * from facturacion.factura;

-- Leemos los eventos capturados mediante la funcion
SELECT 
    event_time AS FechaHora_UTC,
    server_principal_name AS LoginEjecutor,
    database_principal_name AS UsuarioBD,
    action_id AS CodigoAccion, -- 'IN' = INSERT, 'UP' = UPDATE
    schema_name AS Esquema,
    object_name AS TablaAfectada,
    statement AS SentenciaSQL_Ejecutada
FROM sys.fn_get_audit_file(N'/audit/Audit_Cenit/*.sqlaudit', DEFAULT, DEFAULT)
ORDER BY event_time DESC;
GO
--------------------------

EXECUTE AS USER = 'usr_Rodas_Rodriguez';

UPDATE facturacion.factura 
SET id_estadia = 11 
WHERE id_factura = 1;

REVERT;

-- ====================================
-- CALCULO DE DIMENSIONAMIENTO 
-- ===============
-- Tamaño real en disco

SELECT 
    s.name AS [Esquema],
    t.name AS [Tabla],
    SUM(ps.row_count) AS [Filas_Reales],
    SUM(ps.used_page_count) AS [Paginas_Usadas],
    (SUM(ps.used_page_count) * 8) AS [Espacio_Usado_KB],
    (SUM(ps.reserved_page_count) * 8) AS [Espacio_Reservado_KB],
    ROUND(((SUM(ps.used_page_count) * 8.0) / 1024), 2) AS [Espacio_Usado_MB]
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.dm_db_partition_stats ps ON t.object_id = ps.object_id
WHERE ps.index_id IN (0, 1) -- 0: Heap (montículo), 1: Clustered Index
GROUP BY s.name, t.name
ORDER BY [Espacio_Usado_KB] DESC;
GO
