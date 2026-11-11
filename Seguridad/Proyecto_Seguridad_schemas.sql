restore filelistonly from disk='/backup/cenitDB-backup-30-09-2026.bak';

RESTORE DATABASE HotelDB
FROM DISK = '/backup/cenitDB-backup-30-09-2026.bak'
WITH
    MOVE 'HotelDB' TO '/var/opt/mssql/data/cenitDB-backup-30-09-2026.mdf',
    MOVE 'HotelDB_log' TO '/var/opt/mssql/data/cenitDB-backup-30-09-2026_log.ldf',
    REPLACE,
    RECOVERY,
    STATS = 10;

use HotelDB;

-- Visualizacion de schemas


-- Creacion de schemas
-- 1. Esquema para tablas maestras y catálogos generales
CREATE SCHEMA catalogo;
GO

-- 2. Esquema para el flujo diario del hotel (reservas, habitaciones, estancias)
CREATE SCHEMA operacion;
GO

-- 3. Esquema para cobros, facturas y pagos
CREATE SCHEMA facturacion;
GO

-- 4. Esquema para opiniones, calificaciones y reseñas
CREATE SCHEMA calidad;
GO

-- 5. Esquema para vistas, procedimientos o tablas de reportes y auditoría
CREATE SCHEMA reportes;
GO

SELECT name FROM sys.schemas 
WHERE name IN ('catalogo', 'operacion', 'facturacion', 'calidad', 'reportes');

-- Nos paramos en la base de datos del hotel
USE HotelDB;
GO

-- Con esta consulta revisamos las tablas y vistas que viven dentro de un esquema en específico
SELECT 
    s.name AS Esquema,
    o.name AS Objeto,
    -- Le ponemos la etiqueta para saber si es una tabla física o una vista virtual
    CASE o.type
        WHEN 'U' THEN 'Tabla'
        WHEN 'V' THEN 'Vista'
    END AS TipoObjeto,
    o.create_date AS FechaCreacion
FROM sys.objects o
-- Conectamos los objetos del sistema con su esquema correspondiente
INNER JOIN sys.schemas s 
    ON o.schema_id = s.schema_id
WHERE 
    -- Filtramos únicamente tablas ('U') y vistas ('V')
    o.type IN ('U', 'V')
    -- Aquí pones el esquema que quieres espiar (ej. 'operacion', 'catalogo', 'facturacion', etc.)
    AND s.name = 'reportes'
ORDER BY 
    TipoObjeto ASC, 
    Objeto ASC;

    -----------------
    -- Creacion de roles --
    -- 1. CREACIÓN DE ROLES DE BASE DE DATOS
-- =========================================================================
CREATE ROLE rol_programador;
CREATE ROLE rol_gerente;
CREATE ROLE rol_recepcionista;
CREATE ROLE rol_cajero;
CREATE ROLE rol_auditor;
CREATE ROLE rol_mesero_servicio;
CREATE ROLE rol_atencion_cliente;

-- =========================================================================
-- 2. ASIGNACIÓN DE PRIVILEGIOS POR ROL

-- =============================================================================
-- 1. ROL PROGRAMADOR (IT / DESARROLLO / DBA)
-- Acceso irrestricto estructural, operacional, mantenimiento y control
-- =============================================================================
-- Control estructural y de objetos (DDL) por esquema sin control total
GRANT ALTER ON SCHEMA::catalogo TO rol_programador;
GRANT ALTER ON SCHEMA::operacion TO rol_programador;
GRANT ALTER ON SCHEMA::facturacion TO rol_programador;
GRANT ALTER ON SCHEMA::calidad TO rol_programador;
GRANT ALTER ON SCHEMA::reportes TO rol_programador;

-- Permisos DDL a nivel de base de datos
GRANT CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE FUNCTION TO rol_programador;

-- Manipulación select de datos (DML) sobre todos los esquemas
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::catalogo TO rol_programador;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::operacion TO rol_programador;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::calidad TO rol_programador;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::reportes TO rol_programador;
-- Select unicamente en facturacion
GRANT SELECT ON SCHEMA::facturacion TO rol_programador;

-- Ejecución de rutinas y lógica de negocio
GRANT EXECUTE ON SCHEMA::operacion TO rol_programador;
GRANT EXECUTE ON SCHEMA::facturacion TO rol_programador;
GRANT EXECUTE ON SCHEMA::calidad TO rol_programador;
GRANT EXECUTE ON SCHEMA::reportes TO rol_programador;

-- Diagnóstico, auditoría técnica y respaldos
GRANT VIEW DEFINITION TO rol_programador;
GRANT SHOWPLAN TO rol_programador;
GRANT BACKUP DATABASE TO rol_programador;
GRANT BACKUP LOG TO rol_programador;
GO

-- =============================================================================
-- 2. ROL GERENTE (DIRECCIÓN GENERAL)
-- Control operativo transversal del negocio y supervisión de reportes analíticos
-- =============================================================================

-- DML operacional y administrativo
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::catalogo TO rol_gerente;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::operacion TO rol_gerente;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::facturacion TO rol_gerente;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::calidad TO rol_gerente;

-- Lectura completa de todas las vistas del esquema reportes
GRANT SELECT ON SCHEMA::reportes TO rol_gerente;

-- Ejecución de rutinas operativas, contables y reportes analíticos
GRANT EXECUTE ON SCHEMA::operacion TO rol_gerente;
GRANT EXECUTE ON SCHEMA::facturacion TO rol_gerente;
GRANT EXECUTE ON SCHEMA::calidad TO rol_gerente;
GRANT EXECUTE ON SCHEMA::reportes TO rol_gerente;
GO

-- =============================================================================
-- 3. ROL RECEPCIONISTA (FRONT-DESK / MOSTRADOR)
-- Gestión de estancias, reservas, folios preliminares y encuestas en check-out
-- =============================================================================

-- Catálogos: Solo lectura de tarifas, tipos de habitación y servicios
GRANT SELECT ON SCHEMA::catalogo TO rol_recepcionista;
----------
-- Operación: Gestión de clientes, cuartos y reservas (incluye UPDATE para corregir datos o reservas)
GRANT SELECT, INSERT, UPDATE ON operacion.huesped TO rol_recepcionista;
GRANT SELECT ON operacion.habitacion TO rol_recepcionista;
GRANT SELECT, INSERT, UPDATE ON operacion.reservacion TO rol_recepcionista;
GRANT SELECT, INSERT, UPDATE ON operacion.detalle_reservacion TO rol_recepcionista;
GRANT SELECT, INSERT, UPDATE ON operacion.estadia TO rol_recepcionista;
GRANT SELECT ON operacion.consumo_servicio TO rol_recepcionista;
----------
-- Facturación: Generación de folios de liquidación al egreso
GRANT SELECT, INSERT ON SCHEMA::facturacion TO rol_recepcionista;

-- Calidad: Registro de calificaciones/reseñas tomadas directamente en lobby
GRANT SELECT, INSERT ON calidad.resenia TO rol_recepcionista;

-- Vistas operativas autorizadas de reportes
GRANT SELECT ON reportes.v_habitaciones_disponibles TO rol_recepcionista;
GRANT SELECT ON reportes.v_dias_restantes_reservacion TO rol_recepcionista;
GRANT SELECT ON reportes.v_detalle_habitaciones_y_comodidades TO rol_recepcionista;
GRANT SELECT ON reportes.v_total_habitaciones_por_tipo TO rol_recepcionista;
GRANT SELECT ON reportes.v_consumo_estadia TO rol_recepcionista;

-- Ejecución de rutinas operativas y calidad acordada
GRANT EXECUTE ON SCHEMA::operacion TO rol_recepcionista;
GRANT EXECUTE ON SCHEMA::facturacion TO rol_recepcionista;
GRANT EXECUTE ON SCHEMA::calidad TO rol_recepcionista;
GO

-- =============================================================================
-- 4. ROL CAJERO (TESORERÍA / CAJA)
-- Liquidación de cobros, registro de métodos de pago y actualización de facturas
-- =============================================================================

-- Catálogos: Consulta de cargos, servicios, descuentos y recargos
GRANT SELECT ON catalogo.servicio TO rol_cajero;
GRANT SELECT ON catalogo.descuento TO rol_cajero;
GRANT SELECT ON catalogo.aumento_costos TO rol_cajero;

-- Operación: Validación de consumos y datos del huésped para cobro
GRANT SELECT ON operacion.huesped TO rol_cajero;
GRANT SELECT ON operacion.estadia TO rol_cajero;
GRANT SELECT ON operacion.consumo_servicio TO rol_cajero;

-- Facturación: Emisión, detalle y cambio de estado a 'Pagada'
GRANT SELECT, INSERT, UPDATE ON SCHEMA::facturacion TO rol_cajero;

-- Vistas analíticas financieras autorizadas
GRANT SELECT ON reportes.v_consumo_estadia TO rol_cajero;
GRANT SELECT ON reportes.v_factura_completa TO rol_cajero;

-- Ejecución exclusiva de procedimientos de facturación y cobro
GRANT EXECUTE ON SCHEMA::facturacion TO rol_cajero;
GO

-- =============================================================================
-- 5. ROL AUDITOR (FISCALIZACIÓN Y CONTROL INTERNO)
-- Lectura global irrestricta con candado estricto contra alteraciones DML/DDL
-- =============================================================================

-- Lectura de todos los esquemas
GRANT SELECT ON SCHEMA::catalogo TO rol_auditor;
GRANT SELECT ON SCHEMA::operacion TO rol_auditor;
GRANT SELECT ON SCHEMA::facturacion TO rol_auditor;
GRANT SELECT ON SCHEMA::calidad TO rol_auditor;
GRANT SELECT ON SCHEMA::reportes TO rol_auditor;

-- Bloqueo absoluto de cualquier modificación de datos
DENY INSERT, UPDATE, DELETE ON SCHEMA::catalogo TO rol_auditor;
DENY INSERT, UPDATE, DELETE ON SCHEMA::operacion TO rol_auditor;
DENY INSERT, UPDATE, DELETE ON SCHEMA::facturacion TO rol_auditor;
DENY INSERT, UPDATE, DELETE ON SCHEMA::calidad TO rol_auditor;
DENY INSERT, UPDATE, DELETE ON SCHEMA::reportes TO rol_auditor;

-- Ejecución de procedimientos de auditoría y revisión de estructura lógica
GRANT EXECUTE ON SCHEMA::reportes TO rol_auditor;
GRANT VIEW DEFINITION TO rol_auditor;
GO

-- =============================================================================
-- 6. ROL MESERO SERVICIO (PUNTOS DE VENTA / RESTAURANTE / ROOM SERVICE)
-- Menor privilegio: lectura puntual y cargo exclusivo de pedidos a estancias
-- =============================================================================

-- Catálogo: Solo lectura de productos y servicios ofrecidos
GRANT SELECT ON catalogo.servicio TO rol_mesero_servicio;

-- Operación: Validación de cuarto y estancia activa para vincular consumo
GRANT SELECT ON operacion.habitacion TO rol_mesero_servicio;
GRANT SELECT ON operacion.estadia TO rol_mesero_servicio;
GRANT SELECT, INSERT ON operacion.consumo_servicio TO rol_mesero_servicio;
GO

-- =============================================================================
-- 7. ROL ATENCIÓN AL CLIENTE (EXPERIENCIA DEL HUÉSPED)
-- Seguimiento post-venta y resolución de encuestas (sin borrado de reseñas)
-- =============================================================================

-- Catálogos: Lectura informativa de hoteles y habitaciones
GRANT SELECT ON catalogo.hotel TO rol_atencion_cliente;
GRANT SELECT ON catalogo.tipo_habitacion TO rol_atencion_cliente;

-- Operación: Consulta de historial del cliente y sus estancias
GRANT SELECT ON operacion.huesped TO rol_atencion_cliente;
GRANT SELECT ON operacion.estadia TO rol_atencion_cliente;

-- Calidad: Registro y actualización de reseñas (se excluye DELETE para no eliminar quejas)
GRANT SELECT, INSERT, UPDATE ON calidad.resenia TO rol_atencion_cliente;

-- Vistas cualitativas de satisfacción
GRANT SELECT ON reportes.v_resumen_hotel TO rol_atencion_cliente;
GRANT SELECT ON reportes.v_huespedes_por_hotel TO rol_atencion_cliente;

-- Ejecución acordada de rutinas de calidad y seguimiento
GRANT EXECUTE ON SCHEMA::calidad TO rol_atencion_cliente;
GO
-- =========================================================================
-- 3. CONSULTA PARA COMPROBAR QUE LOS PERMISOS
-- =========================================================================
SELECT 
    pr.name AS Rol,
    pe.permission_name AS Permiso,
    pe.state_desc AS EstadoPermiso,
    s.name AS EsquemaAfectado
FROM sys.database_permissions pe
INNER JOIN sys.database_principals pr 
    ON pe.grantee_principal_id = pr.principal_id
INNER JOIN sys.schemas s 
    ON pe.major_id = s.schema_id
WHERE pr.name IN ('rol_programador', 'rol_gerente', 'rol_recepcionista', 'rol_cajero', 'rol_auditor')
ORDER BY 
    Rol ASC, 
    EsquemaAfectado ASC;


    --- Verificacion 2
    USE HotelDB;
GO

SELECT 
    r.name AS [Rol],
    dp.permission_name AS [Permiso],
    dp.state_desc AS [Estado], -- GRANT o DENY
    dp.class_desc AS [Nivel],  -- SCHEMA u OBJECT_OR_COLUMN
    CASE 
        WHEN dp.class_desc = 'SCHEMA' THEN s_schema.name
        WHEN dp.class_desc = 'OBJECT_OR_COLUMN' THEN s_obj.name
        ELSE 'BASE DE DATOS'
    END AS [Esquema],
    CASE 
        WHEN dp.class_desc = 'SCHEMA' THEN '(Todo el esquema)'
        WHEN dp.class_desc = 'OBJECT_OR_COLUMN' THEN o.name
        ELSE 'N/A'
    END AS [Objeto_Fisico],
    o.type_desc AS [Tipo_Objeto]
FROM sys.database_permissions dp
INNER JOIN sys.database_principals r 
    ON dp.grantee_principal_id = r.principal_id
-- Cruce para cuando el permiso es a nivel de Esquema
LEFT JOIN sys.schemas s_schema 
    ON dp.major_id = s_schema.schema_id AND dp.class_desc = 'SCHEMA'
-- Cruce para cuando el permiso es a nivel de Objeto (Tabla, Vista, Procedimiento)
LEFT JOIN sys.objects o 
    ON dp.major_id = o.object_id AND dp.class_desc = 'OBJECT_OR_COLUMN'
LEFT JOIN sys.schemas s_obj 
    ON o.schema_id = s_obj.schema_id
WHERE r.name IN (
    'rol_cajero'
)
ORDER BY 
    r.name, 
    [Nivel], 
    [Esquema], 
    [Objeto_Fisico], 
    dp.permission_name;
GO