-- ==============================
USE HotelDB;
GO

-- =========================
-- Creacion de Login
-- =========================

-- 1. CREACIÓN DE LOGINS EN EL SERVIDOR
CREATE LOGIN login_dev WITH PASSWORD = 'Password2020!', CHECK_POLICY = OFF;
CREATE LOGIN login_gerente WITH PASSWORD = 'Password2021!', CHECK_POLICY = OFF;
CREATE LOGIN login_recepcion WITH PASSWORD = 'Password2022!', CHECK_POLICY = OFF;
CREATE LOGIN login_cajero WITH PASSWORD = 'Password2023!', CHECK_POLICY = OFF;
CREATE LOGIN login_auditor WITH PASSWORD = 'Password2024!', CHECK_POLICY = OFF;
CREATE LOGIN login_mesero WITH PASSWORD = 'Password2025!', CHECK_POLICY = OFF;
CREATE LOGIN login_supervisor_servicio WITH PASSWORD = 'Password2027!', CHECK_POLICY = OFF;
CREATE LOGIN login_atencion WITH PASSWORD = 'Password2028!', CHECK_POLICY = OFF;
GO

-- 2. CREACIÓN DE USUARIOS ASOCIADOS EN LA BASE DE DATOS
CREATE USER usr_Rodas_Rodriguez FOR LOGIN login_dev; -- Programador
CREATE USER usr_Alexander_Vazquez FOR LOGIN login_gerente;
CREATE USER usr_Kenia_Abigail FOR LOGIN login_recepcion;
CREATE USER usr_Cesar_Ramirez FOR LOGIN login_cajero;
CREATE USER usr_Oscar_Olivo FOR LOGIN login_auditor;
CREATE USER usr_Bryan_Ortiz FOR LOGIN login_mesero;
CREATE USER usr_Sofia_Guardado FOR LOGIN login_supervisor_servicio;
CREATE USER usr_Steven_Roque FOR LOGIN login_atencion;
GO

-- 3. ASIGNACIÓN DE ROLES (INCLUYENDO MULTIRROLES)

-- Programador: IT + Auditoría Técnica
ALTER ROLE rol_programador ADD MEMBER usr_Rodas_Rodriguez;
-- ALTER ROLE rol_auditor ADD MEMBER usr_Rodas_Rodriguez;
ALTER ROLE rol_auditor DROP MEMBER usr_Rodas_Rodriguez;

-- Gerente: Dirección + Auditoría
ALTER ROLE rol_gerente ADD MEMBER usr_Alexander_Vazquez;
-- ALTER ROLE rol_auditor ADD MEMBER usr_Alexander_Vazquez;
ALTER ROLE rol_auditor DROP MEMBER usr_Alexander_Vazquez;

-- Recepcionista: Front-Desk + Cobros + Atención inicial (Multirrol Operativo)
ALTER ROLE rol_recepcionista ADD MEMBER usr_Kenia_Abigail;
-- ALTER ROLE rol_cajero ADD MEMBER usr_Kenia_Abigail;
-- ALTER ROLE rol_atencion_cliente ADD MEMBER usr_Kenia_Abigail;
ALTER ROLE rol_cajero DROP MEMBER usr_Kenia_Abigail;
ALTER ROLE rol_atencion_cliente DROP MEMBER usr_Kenia_Abigail;

-- Cajero: Solo tesorería
ALTER ROLE rol_cajero ADD MEMBER usr_Cesar_Ramirez;

-- Auditor: Fiscalización exclusiva
ALTER ROLE rol_auditor ADD MEMBER usr_Oscar_Olivo;

-- Mesero: Solo restaurante/room service
ALTER ROLE rol_mesero_servicio ADD MEMBER usr_Bryan_Ortiz;

-- Supervisor de Sala: Servicio + Calidad
ALTER ROLE rol_mesero_servicio ADD MEMBER usr_Sofia_Guardado;
ALTER ROLE rol_atencion_cliente ADD MEMBER usr_Sofia_Guardado;

-- Atención al Cliente: Calidad + Reportes de auditoría
ALTER ROLE rol_atencion_cliente ADD MEMBER usr_Steven_Roque;
ALTER ROLE rol_auditor ADD MEMBER usr_Steven_Roque ;


-- ===========================
-- Script de Verificación de Membresías Multirrol
SELECT 
    m.name AS [Usuario_BD],
    r.name AS [Rol_Asignado]
FROM sys.database_role_members rm
INNER JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
INNER JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
WHERE m.name IN (
'usr_Rodas_Rodriguez'
)
ORDER BY m.name, r.name;

-- ==================== 
-- PRUEBA DE MULTIROLES
-- ====================

-- 0. Verificar la identidad activa y que ambos roles estén vigentes
SELECT SUSER_NAME() AS LoginActivo, USER_NAME() AS UsuarioBD;

-- Comprobar si el motor reconoce la pertenencia a los múltiples roles (debe dar 1 en los 3)
SELECT 
    IS_MEMBER('rol_recepcionista')     AS Es_Recepcionista,
    IS_MEMBER('rol_cajero')            AS Es_Cajero,
    IS_MEMBER('rol_atencion_cliente')  AS Es_AtencionCliente;
GO

-- =========================================================================
-- PRUEBA 1: Prueba de Éxito: Gestión estructural (DDL) y lectura de datos en esquemas.
-- Prueba de Error: Intento de modificación/borrado de datos (DML) o elevación a nivel de servidor.
-- =========================================================================
EXECUTE AS USER = 'usr_Rodas_Rodriguez';

-- [ÉXITO] Crear y consultar un objeto DDL estructural
CREATE TABLE catalogo.prueba_desarrollo (
    id INT IDENTITY PRIMARY KEY,
    nombre VARCHAR(50)
);
SELECT TOP 2 * FROM operacion.huesped;

-- Limpieza
DROP TABLE catalogo.prueba_desarrollo;

-- [FALLO ESPERADO 2]: Intentar eliminar una factura
-- Error: Msg 229, The DELETE permission was denied on the object 'factura'
DELETE FROM facturacion.factura 
WHERE id_factura = 1;
GO

REVERT;
GO

-- =========================================================================
-- PRUEBA 2: Prueba de Éxito: Control operacional transversal DML y lectura de reportes analíticos..
-- Prueba de Error: Creación de objetos estructurales (carece de permisos DDL)
-- =========================================================================
EXECUTE AS USER = 'usr_Alexander_Vazquez';

-- [ÉXITO] Consulta de reportes gerenciales y actualización operativa
SELECT TOP 3 * FROM reportes.v_factura_completa;
SELECT TOP 3 * FROM calidad.resenia;

-- [FALLO ESPERADO] El gerente administra datos, pero no la estructura de la BD
-- Error: Msg 262 - CREATE TABLE permission denied in database 'cenitDB'
CREATE TABLE catalogo.nueva_sucursal (id INT);

REVERT;
GO
-- =========================================================================
-- PRUEBA 3: Prueba de Éxito: Consulta de disponibilidad de habitaciones y gestión de huéspedes/estancias.
-- Prueba de Error: Intentos de cobranza directa (facturación) o creación de habitaciones físicas.
-- =========================================================================
GO

EXECUTE AS USER = 'usr_Kenia_Abigail';

-- [ÉXITO] Consulta de disponibilidad física y datos de clientes
SELECT TOP 3 * FROM reportes.v_habitaciones_disponibles;
SELECT TOP 3 * FROM operacion.huesped;

-- [FALLO ESPERADO 1] Alterar inventario físico de habitaciones (solo lectura en habitacion)
-- Error: Msg 229 - The UPDATE permission was denied on the object 'habitacion'
UPDATE operacion.habitacion SET id_tipo_habitacion = 1 WHERE id_habitacion = 1;

-- [FALLO ESPERADO 2] Cobrar o modificar facturas (exclusivo de rol_cajero)
-- Error: Msg 229 - The UPDATE permission was denied on the object 'factura'
UPDATE facturacion.factura SET metodo_pago = 'EFECTIVO' WHERE id_factura = 1;

REVERT;
GO
-- =========================================================================
-- PRUEBA 4: Prueba de Éxito: Consulta de consumos de estancia y actualización del estado de pago en facturas.
-- Prueba de Error: Inserción de reservas u operaciones de mostrador/atención al cliente.
-- =========================================================================
EXECUTE AS USER = 'usr_Cesar_Ramirez';

-- [ÉXITO] Consulta de consumos y cobranza/actualización de facturas
SELECT TOP 3 * FROM reportes.v_factura_completa;
UPDATE facturacion.factura 
SET metodo_pago = 'EFECTIVO' 
WHERE id_factura = 1;

-- [FALLO ESPERADO 2] No tiene acceso a opiniones de clientes
-- Error: Msg 229 - The SELECT permission was denied on the object 'resenia'
SELECT * FROM calidad.resenia;

REVERT;
GO

-- =========================================================================
-- PRUEBA 5: Prueba de Éxito: Lectura irrestricta en todos los esquemas (SELECT) y ejecución de reportes.
-- Prueba de Error: Bloqueo explícito por DENY ante cualquier intento de inserción, actualización o borrado.
-- =========================================================================
EXECUTE AS USER = 'usr_Oscar_Olivo';

-- [ÉXITO] Lectura transversal de catálogos, operaciones y finanzas
SELECT TOP 2 * FROM catalogo.hotel;
SELECT TOP 2 * FROM operacion.estadia;
SELECT TOP 2 * FROM facturacion.factura;
SELECT TOP 2 * FROM reportes.v_factura_completa;

-- [FALLO ESPERADO 1] Candado DENY en modificación financiera
-- Error: Msg 229 - The UPDATE permission was denied on the object 'factura'
UPDATE facturacion.factura SET monto_total = 0.00 WHERE id_factura = 1;

-- [FALLO ESPERADO 2] Candado DENY en alteración de catálogos
-- Error: Msg 229 - The DELETE permission was denied on the object 'servicio'
DELETE FROM catalogo.servicio WHERE id_servicio = 1;

REVERT;
GO

-- =========================
-- Prueba de usuario auditor
-- =========================
EXECUTE AS USER = 'usr_Oscar_Olivo';

-- 1. DEBE FUNCIONAR (Lectura global y vistas analíticas):
SELECT TOP 3 * FROM catalogo.hotel;

SELECT TOP 3 * FROM facturacion.factura;
SELECT TOP 3 * FROM reportes.v_ingresos_mes;

-- 2. DEBE FALLAR (DENY explícito en modificación de datos):
INSERT INTO calidad.resenia (id_estadia, calificacion, comentario) 
VALUES (1, 5, 'Prueba de auditor');
DELETE FROM catalogo.servicio WHERE id_servicio = 1;

REVERT;
GO