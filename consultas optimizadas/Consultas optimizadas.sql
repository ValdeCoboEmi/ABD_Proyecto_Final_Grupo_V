/*
===============================================================================
HotelDB - Optimización de consultas con índices, vistas indexadas y funciones ventana
-------------------------------------------------------------------------------

ORDEN DE EJECUCIÓN
  1) cargar volumen con 00_carga_sintetica_HotelDB.sql
  2) A. crear las vistas -> B. mediciones BASE -> C. índices 

===============================================================================
*/
USE HotelDB;
GO
SET ANSI_NULLS ON; --Los valores NULL son desconocidos, por lo que no se pueden comparar usando los operadores de igualdad (=) o desigualdad (<>)/se debe usar IS NULL o IS NOT NULL
SET QUOTED_IDENTIFIER ON; --si esta activado, las comillas dobles (") identifican nombres de objetos, columnas o tablas y las simples (') delimitan texto
GO

IF OBJECT_ID('facturacion.vw_ranking_gastos_huespedes', 'V') IS NOT NULL --'V' indica que un tipo VISTA
    DROP VIEW facturacion.vw_ranking_gastos_huespedes;
GO
IF OBJECT_ID('facturacion.vw_variacion_mensual_ingresos_hotel', 'V') IS NOT NULL
    DROP VIEW facturacion.vw_variacion_mensual_ingresos_hotel;
GO
IF OBJECT_ID('facturacion.vw_top3_habitaciones_rentables', 'V') IS NOT NULL
    DROP VIEW facturacion.vw_top3_habitaciones_rentables;
GO

/* ===========================================================================
A. LAS TRES CONSULTAS COMO VIEWS (sin cambios)
=========================================================================== */

CREATE VIEW facturacion.vw_ranking_gastos_huespedes
AS
WITH gasto_huesped AS
(
    SELECT f.id_huesped,
           SUM(f.total_a_pagar) AS gasto_total,
           COUNT_BIG(*) AS num_facturas
    FROM facturacion.factura AS f
    GROUP BY f.id_huesped
)
SELECT h.id_huesped,
       h.nombre,
       h.tipo_documento,
       g.gasto_total,
       g.num_facturas,
       DENSE_RANK() OVER (ORDER BY g.gasto_total DESC) AS ranking_global,
       RANK() OVER
           (PARTITION BY h.tipo_documento ORDER BY g.gasto_total DESC) AS ranking_por_tipo_doc,
       CAST(100.0 * g.gasto_total / NULLIF(SUM(g.gasto_total) OVER (), 0)
            AS DECIMAL(7,2)) AS pct_del_total
FROM gasto_huesped AS g
JOIN operacion.huesped AS h ON h.id_huesped = g.id_huesped;
GO

CREATE VIEW facturacion.vw_variacion_mensual_ingresos_hotel
AS
WITH lineas_hotel AS
(
    SELECT df.id_factura,
           hab.id_hotel,
           SUM(df.precio_total) AS monto_hotel
    FROM facturacion.detalle_factura AS df
    JOIN operacion.habitacion AS hab
      ON hab.id_habitacion = df.id_habitacion
    WHERE df.id_habitacion IS NOT NULL
    GROUP BY df.id_factura, hab.id_hotel
),
ingresos_asignados AS
(
    SELECT f.fecha,
           lh.id_hotel,
           f.total_a_pagar * lh.monto_hotel
             / NULLIF(SUM(lh.monto_hotel) OVER (PARTITION BY lh.id_factura), 0) AS ingreso
    FROM facturacion.factura AS f
    JOIN lineas_hotel AS lh ON lh.id_factura = f.id_factura
),
ingresos_mensuales AS
(
    SELECT id_hotel,
           DATEFROMPARTS(YEAR(fecha), MONTH(fecha), 1) AS mes,
           SUM(ingreso) AS ingresos
    FROM ingresos_asignados
    GROUP BY id_hotel, DATEFROMPARTS(YEAR(fecha), MONTH(fecha), 1)
),
variacion AS
(
    SELECT id_hotel,
           mes,
           ingresos,
           LAG(ingresos) OVER (PARTITION BY id_hotel ORDER BY mes) AS ingresos_mes_anterior
    FROM ingresos_mensuales
)
SELECT h.id_hotel,
       h.nombre AS hotel,
       v.mes,
       CAST(v.ingresos AS DECIMAL(14,2)) AS ingresos,
       CAST(v.ingresos_mes_anterior AS DECIMAL(14,2)) AS ingresos_mes_anterior,
       CAST(v.ingresos - v.ingresos_mes_anterior AS DECIMAL(14,2)) AS variacion_abs,
       CAST(100.0 * (v.ingresos - v.ingresos_mes_anterior)
            / NULLIF(v.ingresos_mes_anterior, 0) AS DECIMAL(9,2)) AS variacion_pct
FROM variacion AS v
JOIN catalogo.hotel AS h ON h.id_hotel = v.id_hotel;
GO

CREATE VIEW facturacion.vw_top3_habitaciones_rentables
AS
WITH ingreso_habitacion AS
(
    SELECT hab.id_hotel,
           hab.id_habitacion,
           hab.numero_habitacion,
           hab.id_tipo_habitacion,
           SUM(df.precio_total) AS ingresos,
           COUNT_BIG(*) AS lineas_facturadas
    FROM facturacion.detalle_factura AS df
    JOIN operacion.habitacion AS hab
      ON hab.id_habitacion = df.id_habitacion
    WHERE df.id_habitacion IS NOT NULL
    GROUP BY hab.id_hotel, hab.id_habitacion,
             hab.numero_habitacion, hab.id_tipo_habitacion
),
habitaciones_rankeadas AS
(
    SELECT ih.*,
           ROW_NUMBER() OVER
             (PARTITION BY ih.id_hotel
              ORDER BY ih.ingresos DESC, ih.id_habitacion ASC) AS posicion
    FROM ingreso_habitacion AS ih
)
SELECT h.id_hotel,
       h.nombre AS hotel,
       r.posicion,
       r.id_habitacion,
       r.numero_habitacion,
       th.tipo_habitacion,
       r.lineas_facturadas,
       CAST(r.ingresos AS DECIMAL(14,2)) AS ingresos
FROM habitaciones_rankeadas AS r
JOIN catalogo.hotel AS h ON h.id_hotel = r.id_hotel
JOIN catalogo.tipo_habitacion AS th
  ON th.id_tipo_habitacion = r.id_tipo_habitacion
WHERE r.posicion <= 3;
GO

/* ===========================================================================
B. PRUEBA BASE: EJECUTAR ANTES DE LA SECCIÓN C
  - Ctrl+M (plan real) y, en SSMS, Query > Query Options > Results > "Discard
    results after execution": así el tiempo no incluye pintar filas en pantalla.
  - Compara sobre todo LECTURAS LÓGICAS (son estables); el tiempo varía.
=========================================================================== */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

/* B1. Ranking de huéspedes (devuelve 1 fila por huésped; lee todas las facturas) */
SELECT *
FROM facturacion.vw_ranking_gastos_huespedes
ORDER BY ranking_global, id_huesped;
GO

/* B2. Variación mensual: rango ESTRECHO (3 meses). Con el rango completo del
   proyecto (2025-01 a 2026-09) el filtro no descarta nada y no hay nada que
   mejorar. El filtro por mes se aplica después del LAG: la vista lee todo. */
SELECT *
FROM facturacion.vw_variacion_mensual_ingresos_hotel
WHERE mes >= '2026-03-01' AND mes < '2026-06-01'
ORDER BY hotel, mes;
GO

/* B3. Top 3 por hotel (devuelve ~9 filas; lee todas las líneas de habitación) */
SELECT *
FROM facturacion.vw_top3_habitaciones_rentables
ORDER BY hotel, posicion;
GO

/* ===========================================================================
C. ÍNDICES DE SOPORTE (ejecutar DESPUÉS de guardar las mediciones base)
=========================================================================== */

/* ---------------------------------------------------------------------------
C1. Índices en tablas base
--------------------------------------------------------------------------- */

IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'IX_factura_huesped'
             AND object_id = OBJECT_ID('facturacion.factura'))
    DROP INDEX IX_factura_huesped ON facturacion.factura;
GO
CREATE NONCLUSTERED INDEX IX_factura_huesped
    ON facturacion.factura (id_huesped)
    INCLUDE (total_a_pagar);
GO


IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'IX_factura_fecha'
             AND object_id = OBJECT_ID('facturacion.factura'))
    DROP INDEX IX_factura_fecha ON facturacion.factura;
GO
CREATE NONCLUSTERED INDEX IX_factura_fecha
    ON facturacion.factura (fecha)
    INCLUDE (total_a_pagar);
GO


IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'IX_detfac_habitacion'
             AND object_id = OBJECT_ID('facturacion.detalle_factura'))
    DROP INDEX IX_detfac_habitacion ON facturacion.detalle_factura;
GO
CREATE NONCLUSTERED INDEX IX_detfac_habitacion
    ON facturacion.detalle_factura (id_habitacion)
    INCLUDE (precio_total)
    WHERE id_habitacion IS NOT NULL;
GO


IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'IX_detfac_factura'
             AND object_id = OBJECT_ID('facturacion.detalle_factura'))
    DROP INDEX IX_detfac_factura ON facturacion.detalle_factura;
GO
CREATE NONCLUSTERED INDEX IX_detfac_factura
    ON facturacion.detalle_factura (id_factura)
    INCLUDE (id_habitacion, precio_total)
    WHERE id_habitacion IS NOT NULL;
GO

/* ---------------------------------------------------------------------------
C2. VISTAS INDEXADAS (agregados precalculados): la mejora de fondo.
    Cada una replica EXACTAMENTE la agregación de una vista de la sección A
--------------------------------------------------------------------------- */
IF OBJECT_ID('facturacion.ivw_gasto_huesped', 'V') IS NOT NULL
    DROP VIEW facturacion.ivw_gasto_huesped;
GO
IF OBJECT_ID('facturacion.ivw_monto_hotel_factura', 'V') IS NOT NULL
    DROP VIEW facturacion.ivw_monto_hotel_factura;
GO
IF OBJECT_ID('facturacion.ivw_ingreso_habitacion', 'V') IS NOT NULL
    DROP VIEW facturacion.ivw_ingreso_habitacion;
GO

/* Para la vista 1: gasto por huésped (1 fila por huésped en vez de 1 por factura) */
CREATE VIEW facturacion.ivw_gasto_huesped
WITH SCHEMABINDING
AS
SELECT f.id_huesped,
       SUM(f.total_a_pagar) AS gasto_total,
       COUNT_BIG(*)         AS num_facturas
FROM facturacion.factura AS f
GROUP BY f.id_huesped;
GO
CREATE UNIQUE CLUSTERED INDEX CIX_ivw_gasto_huesped
    ON facturacion.ivw_gasto_huesped (id_huesped); --Usa la IndexView para el indice
GO

/* Para la vista 2: monto de cada factura por hotel (reemplaza leer y agrupar
   todas las líneas de detalle en cada consulta) */
CREATE VIEW facturacion.ivw_monto_hotel_factura
WITH SCHEMABINDING
AS
SELECT df.id_factura,
       hab.id_hotel,
       SUM(df.precio_total) AS monto_hotel,
       COUNT_BIG(*)         AS num_lineas
FROM facturacion.detalle_factura AS df
JOIN operacion.habitacion AS hab
  ON hab.id_habitacion = df.id_habitacion
WHERE df.id_habitacion IS NOT NULL
GROUP BY df.id_factura, hab.id_hotel;
GO
CREATE UNIQUE CLUSTERED INDEX CIX_ivw_monto_hotel_factura
    ON facturacion.ivw_monto_hotel_factura (id_factura, id_hotel); 
GO

/* Para la vista 3: ingresos por habitación (1 fila por habitación, ~1000 filas,
   sin importar cuántas líneas de factura existan) */
CREATE VIEW facturacion.ivw_ingreso_habitacion
WITH SCHEMABINDING
AS
SELECT hab.id_hotel,
       hab.id_habitacion,
       hab.numero_habitacion,
       hab.id_tipo_habitacion,
       SUM(df.precio_total) AS ingresos,
       COUNT_BIG(*)         AS lineas_facturadas
FROM facturacion.detalle_factura AS df
JOIN operacion.habitacion AS hab
  ON hab.id_habitacion = df.id_habitacion
WHERE df.id_habitacion IS NOT NULL
GROUP BY hab.id_hotel, hab.id_habitacion,
         hab.numero_habitacion, hab.id_tipo_habitacion;
GO
CREATE UNIQUE CLUSTERED INDEX CIX_ivw_ingreso_habitacion
    ON facturacion.ivw_ingreso_habitacion (id_habitacion);
GO
/* Orden exacto del ROW_NUMBER (hotel, ingresos DESC, id_habitacion): el top 3
   por hotel se resuelve leyendo solo las primeras 3 filas de cada hotel. */
CREATE NONCLUSTERED INDEX IX_ivw_ingreso_habitacion_top
    ON facturacion.ivw_ingreso_habitacion (id_hotel, ingresos DESC, id_habitacion)
    INCLUDE (numero_habitacion, id_tipo_habitacion, lineas_facturadas);
GO

/* ---------------------------------------------------------------------------
C3. Verificar que el optimizador usa las vistas indexadas
    Debe aparecer ivw_gasto_huesped / ivw_monto_hotel_factura /
    ivw_ingreso_habitacion en vez de detalle_factura/factura.
--------------------------------------------------------------------------- */

/* ===========================================================================
D. FUNCIÓN CON RANGO DE FECHAS (variación mensual) -- para la consulta 2
   Filtra facturas ANTES de la ventana, así IX_factura_fecha hace seek y
   IX_detfac_factura trae solo las líneas de esas facturas.
   Incluye 1 mes antes de @desde para que el LAG del primer mes tenga con qué
   comparar. @desde y @hasta se interpretan por mes: devuelve los meses desde
   el mes de @desde hasta el mes anterior a @hasta (@hasta es exclusivo).
   Si un hotel no tiene facturas en el previo a @desde, la vista compararía contra un
   mes más antiguo y la función dará NULL en ese primer mes.
=========================================================================== */
IF OBJECT_ID('facturacion.fn_variacion_mensual_ingresos_hotel', 'IF') IS NOT NULL
    DROP FUNCTION facturacion.fn_variacion_mensual_ingresos_hotel;
GO
CREATE FUNCTION facturacion.fn_variacion_mensual_ingresos_hotel
(
    @desde DATE,
    @hasta DATE
)
RETURNS TABLE
AS
RETURN
WITH facturas_rango AS
(
    SELECT f.id_factura, f.fecha, f.total_a_pagar
    FROM facturacion.factura AS f
    WHERE f.fecha >= DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(@desde), MONTH(@desde), 1))
      AND f.fecha <  @hasta
),
lineas_hotel AS
(
    SELECT df.id_factura,
           hab.id_hotel,
           SUM(df.precio_total) AS monto_hotel
    FROM facturas_rango AS fr
    JOIN facturacion.detalle_factura AS df
      ON df.id_factura = fr.id_factura
    JOIN operacion.habitacion AS hab
      ON hab.id_habitacion = df.id_habitacion
    WHERE df.id_habitacion IS NOT NULL
    GROUP BY df.id_factura, hab.id_hotel
),
ingresos_asignados AS
(
    SELECT fr.fecha,
           lh.id_hotel,
           fr.total_a_pagar * lh.monto_hotel
             / NULLIF(SUM(lh.monto_hotel) OVER (PARTITION BY lh.id_factura), 0) AS ingreso
    FROM facturas_rango AS fr
    JOIN lineas_hotel AS lh ON lh.id_factura = fr.id_factura
),
ingresos_mensuales AS
(
    SELECT id_hotel,
           DATEFROMPARTS(YEAR(fecha), MONTH(fecha), 1) AS mes,
           SUM(ingreso) AS ingresos
    FROM ingresos_asignados
    GROUP BY id_hotel, DATEFROMPARTS(YEAR(fecha), MONTH(fecha), 1)
),
variacion AS
(
    SELECT id_hotel,
           mes,
           ingresos,
           LAG(ingresos) OVER (PARTITION BY id_hotel ORDER BY mes) AS ingresos_mes_anterior
    FROM ingresos_mensuales
)
SELECT h.id_hotel,
       h.nombre AS hotel,
       v.mes,
       CAST(v.ingresos AS DECIMAL(14,2)) AS ingresos,
       CAST(v.ingresos_mes_anterior AS DECIMAL(14,2)) AS ingresos_mes_anterior,
       CAST(v.ingresos - v.ingresos_mes_anterior AS DECIMAL(14,2)) AS variacion_abs,
       CAST(100.0 * (v.ingresos - v.ingresos_mes_anterior)
            / NULLIF(v.ingresos_mes_anterior, 0) AS DECIMAL(9,2)) AS variacion_pct
FROM variacion AS v
JOIN catalogo.hotel AS h ON h.id_hotel = v.id_hotel
WHERE v.mes >= DATEFROMPARTS(YEAR(@desde), MONTH(@desde), 1);
GO

/* ===========================================================================
E. PRUEBA CON ÍNDICES: mismas consultas, comparar lecturas lógicas, CPU y plan
=========================================================================== */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

/* E1. Ranking: ahora lee ivw_gasto_huesped (1 fila por huésped) */
SELECT *
FROM facturacion.vw_ranking_gastos_huespedes
ORDER BY ranking_global, id_huesped;
GO

/* E2. Variación mensual: MISMO rango que B2, pero filtrando antes de la ventana */
SELECT *
FROM facturacion.fn_variacion_mensual_ingresos_hotel('2026-03-01', '2026-06-01')
ORDER BY hotel, mes;
GO

/* E3. Top 3: lee ~3 filas por hotel del índice de la vista indexada */
SELECT *
FROM facturacion.vw_top3_habitaciones_rentables
ORDER BY hotel, posicion;
GO

/* E4. Comprobación de que la función devuelve lo mismo que la vista.
   Debe devolver 0 filas (si algún hotel no tuvo facturas el mes previo al
   rango, puede aparecer una diferencia solo en la columna del mes anterior). */
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
SELECT * FROM facturacion.vw_variacion_mensual_ingresos_hotel
WHERE mes >= '2026-03-01' AND mes < '2026-06-01'
EXCEPT
SELECT * FROM facturacion.fn_variacion_mensual_ingresos_hotel('2026-03-01', '2026-06-01');
GO


--Reiniciar la prueba (volver al estado base). 
DROP FUNCTION IF EXISTS facturacion.fn_variacion_mensual_ingresos_hotel;
DROP VIEW IF EXISTS facturacion.ivw_gasto_huesped;
DROP VIEW IF EXISTS facturacion.ivw_monto_hotel_factura;
DROP VIEW IF EXISTS facturacion.ivw_ingreso_habitacion;
DROP INDEX IF EXISTS IX_factura_huesped   ON facturacion.factura;
DROP INDEX IF EXISTS IX_factura_fecha     ON facturacion.factura;
DROP INDEX IF EXISTS IX_detfac_habitacion ON facturacion.detalle_factura;
DROP INDEX IF EXISTS IX_detfac_factura    ON facturacion.detalle_factura;
