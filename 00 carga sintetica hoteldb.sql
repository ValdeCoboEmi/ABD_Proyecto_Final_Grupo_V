/*
===============================================================================
HotelDB - Carga SINTÉTICA de volumen (solo para pruebas de rendimiento)
-------------------------------------------------------------------------------
HotelDB cuenta con alrededor de 190 facturas y 1,400 líneas de detalle, siendo pocos datos.
Con ese tamaño un scan completo es lo más barato y ningún índice puede mostrar una mejora
visible. Este script agrega facturas y líneas inventadas para que las lecturas 
lógicas muestren una mejora real dentro de la base.

COMO USAR:
  1) Ejecutar la sección 1 (marca) y la sección 2 (carga).
  2) Ejecutar las pruebas BASE del script (antes de los índices).
  3) Crear los índices, repetir las pruebas y compara.
  4) Al terminar, ejecutar la sección 3 de este script para volver a los datos reales.

===============================================================================
*/
USE HotelDB;
GO
SET ANSI_NULLS ON; --Los valores NULL son desconocidos, por lo que no se pueden comparar usando los operadores de igualdad (=) o desigualdad (<>)/se debe usar IS NULL o IS NOT NULL
SET QUOTED_IDENTIFIER ON; --si esta activado, las comillas dobles (") identifican nombres de objetos, columnas o tablas y las simples (') delimitan texto
GO

/* ===========================================================================
1. TABLA MARCA (guarda el id máximo original para poder limpiar después)
=========================================================================== */
IF OBJECT_ID('dbo.carga_sintetica_marca', 'U') IS NULL
    CREATE TABLE dbo.carga_sintetica_marca
    (
        max_id_factura BIGINT       NOT NULL,
        fecha_carga    DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
    );
GO

/* ===========================================================================
2. CARGA
   @N = cantidad de facturas nuevas. Cada una trae de 1 a 4 líneas.
   100000 -> rápido; 200000 -> recomendado; 1000000 -> pesado (cuida el log).
=========================================================================== */
SET NOCOUNT ON;
DECLARE @N INT = 200000;

IF EXISTS (SELECT 1 FROM dbo.carga_sintetica_marca)
BEGIN
    RAISERROR('Ya hay una carga sintética registrada. Ejecuta primero la sección 3 (limpieza).', 16, 1);
    RETURN;
END;

BEGIN TRY
    BEGIN TRAN;

    INSERT dbo.carga_sintetica_marca (max_id_factura)
    SELECT MAX(id_factura) FROM facturacion.factura;

    DECLARE @max_f BIGINT = (SELECT max_id_factura FROM dbo.carga_sintetica_marca);

    DISABLE TRIGGER ALL ON facturacion.factura;
    DISABLE TRIGGER ALL ON facturacion.detalle_factura;

    /* Listas de ids existentes, numeradas para poder elegirlas con aritmética */
    SELECT ROW_NUMBER() OVER (ORDER BY id_estadia) AS rn, id_estadia
    INTO #est
    FROM (SELECT DISTINCT id_estadia FROM facturacion.factura WHERE id_factura <= @max_f) AS x;

    SELECT ROW_NUMBER() OVER (ORDER BY id_empleado) AS rn, id_empleado
    INTO #emp
    FROM (SELECT DISTINCT id_empleado FROM facturacion.factura WHERE id_factura <= @max_f) AS x;

    SELECT ROW_NUMBER() OVER (ORDER BY id_huesped) AS rn, id_huesped
    INTO #hue
    FROM operacion.huesped;

    SELECT ROW_NUMBER() OVER (ORDER BY id_habitacion) AS rn, id_habitacion
    INTO #hab
    FROM operacion.habitacion;

    SELECT ROW_NUMBER() OVER (ORDER BY id_servicio) AS rn, id_servicio
    INTO #srv
    FROM (SELECT DISTINCT id_servicio
          FROM facturacion.detalle_factura
          WHERE id_servicio IS NOT NULL) AS x;

    DECLARE @E INT = (SELECT COUNT(*) FROM #est),
            @M INT = (SELECT COUNT(*) FROM #emp),
            @H INT = (SELECT COUNT(*) FROM #hue),
            @R INT = (SELECT COUNT(*) FROM #hab),
            @S INT = (SELECT COUNT(*) FROM #srv);

    IF @N > @E * @H * @M
        THROW 50001, 'Reduce @N: no hay suficientes combinaciones únicas (empleado, huésped, estadía).', 1;

    /* --- Facturas ------------------------------------------------------- */
    ;WITH n AS
    (
        SELECT TOP (@N) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
        FROM sys.all_objects AS a
        CROSS JOIN sys.all_objects AS b
    )
    INSERT facturacion.factura (id_empleado, id_huesped, id_estadia, fecha, metodo_pago, total_a_pagar)
    SELECT emp.id_empleado,
           hue.id_huesped,
           est.id_estadia,
           /* fecha repartida entre 2025-01-01 y 2026-08-31 */
           DATEADD(SECOND,
                   (CHECKSUM(n.i, 11) & 0x7FFFFFFF) % (86400 * 608),
                   CAST('2025-01-01' AS DATETIME2(3))),
           CHOOSE((CHECKSUM(n.i, 12) & 0x7FFFFFFF) % 5 + 1,
                  N'EFECTIVO', N'TRANSFERENCIA', N'TARJETA', N'BITCOIN', N'PAYPAL'),
           0.00                                   -- se recalcula abajo con las líneas
    FROM n
    JOIN #est AS est ON est.rn = n.i % @E + 1
    JOIN #hue AS hue ON hue.rn = (n.i / @E) % @H + 1
    JOIN #emp AS emp ON emp.rn = (n.i / (@E * @H)) % @M + 1
    WHERE NOT EXISTS (SELECT 1
                      FROM facturacion.factura AS f
                      WHERE f.id_empleado = emp.id_empleado
                        AND f.id_huesped  = hue.id_huesped
                        AND f.id_estadia  = est.id_estadia);

    /* --- Líneas de detalle: ~75% habitación, ~25% servicio ---------------- */
    INSERT facturacion.detalle_factura
           (id_factura, id_servicio, id_habitacion, concepto,
            precio_unitario, cantidad, subtotal, precio_total)
    SELECT f.id_factura,
           CASE WHEN x.es_hab = 1 THEN NULL ELSE srv.id_servicio END,
           CASE WHEN x.es_hab = 1 THEN hab.id_habitacion ELSE NULL END,
           CASE WHEN x.es_hab = 1 THEN N'Estadía de habitación (sintético)'
                                  ELSE N'Servicio (sintético)' END,
           x.precio,
           x.cant,
           x.precio * x.cant,
           x.precio * x.cant
    FROM facturacion.factura AS f
    CROSS APPLY (VALUES (1), (2), (3), (4)) AS k(k)
    CROSS APPLY (SELECT
            CASE WHEN @S = 0 OR (CHECKSUM(f.id_factura, k.k, 21) & 0x7FFFFFFF) % 4 < 3
                 THEN 1 ELSE 0 END                                          AS es_hab,
            CAST(30 + (CHECKSUM(f.id_factura, k.k, 22) & 0x7FFFFFFF) % 371
                 AS DECIMAL(10,2))                                          AS precio,
            1 + (CHECKSUM(f.id_factura, k.k, 23) & 0x7FFFFFFF) % 5          AS cant,
            (CHECKSUM(f.id_factura, k.k, 24) & 0x7FFFFFFF) % @R + 1         AS rn_hab,
            (CHECKSUM(f.id_factura, k.k, 25) & 0x7FFFFFFF) % NULLIF(@S, 0) + 1 AS rn_srv
         ) AS x
    LEFT JOIN #hab AS hab ON hab.rn = x.rn_hab
    LEFT JOIN #srv AS srv ON srv.rn = x.rn_srv
    WHERE f.id_factura > @max_f
      AND k.k <= 1 + (CHECKSUM(f.id_factura, 20) & 0x7FFFFFFF) % 4;

    /* --- El total de cada factura nueva = suma de sus líneas -------------- */
    UPDATE f
       SET f.total_a_pagar = s.suma
    FROM facturacion.factura AS f
    JOIN (SELECT id_factura, SUM(precio_total) AS suma
          FROM facturacion.detalle_factura
          WHERE id_factura > @max_f
          GROUP BY id_factura) AS s
      ON s.id_factura = f.id_factura
    WHERE f.id_factura > @max_f;

    ENABLE TRIGGER ALL ON facturacion.factura;
    ENABLE TRIGGER ALL ON facturacion.detalle_factura;

    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    ENABLE TRIGGER ALL ON facturacion.factura;
    ENABLE TRIGGER ALL ON facturacion.detalle_factura;
    THROW;
END CATCH;

UPDATE STATISTICS facturacion.factura;
UPDATE STATISTICS facturacion.detalle_factura;

SELECT (SELECT COUNT_BIG(*) FROM facturacion.factura)          AS facturas,
       (SELECT COUNT_BIG(*) FROM facturacion.detalle_factura)  AS lineas_detalle;
GO

/* ===========================================================================
3. LIMPIEZA: volver a los datos reales (ejecutar al terminar las pruebas)
=========================================================================== */

SET NOCOUNT ON;
DECLARE @max_f BIGINT = (SELECT MAX(max_id_factura) FROM dbo.carga_sintetica_marca);

IF @max_f IS NULL
    PRINT 'No hay carga sintética registrada.';
ELSE
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        DISABLE TRIGGER ALL ON facturacion.factura;
        DISABLE TRIGGER ALL ON facturacion.detalle_factura;

        DELETE FROM facturacion.detalle_factura WHERE id_factura > @max_f;
        DELETE FROM facturacion.factura         WHERE id_factura > @max_f;

        ENABLE TRIGGER ALL ON facturacion.factura;
        ENABLE TRIGGER ALL ON facturacion.detalle_factura;
        DELETE FROM dbo.carga_sintetica_marca;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        ENABLE TRIGGER ALL ON facturacion.factura;
        ENABLE TRIGGER ALL ON facturacion.detalle_factura;
        THROW;
    END CATCH;
END;
