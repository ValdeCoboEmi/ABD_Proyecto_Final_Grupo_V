# CÉNIT · Sistema de Reservas de Hotel

Proyecto final de **Administración de Bases de Datos** (Grupo V).

CÉNIT administra las operaciones de un hotel: habitaciones, huéspedes, reservaciones, consumos de servicios y facturación. Este repositorio reúne la base de datos en **Microsoft SQL Server** (`HotelDB`), su documentación técnica y el material de la defensa.

> El proyecto retoma la base desarrollada en el ciclo anterior para Bases de Datos, que operaba sobre PostgreSQL. Su migración a SQL Server implicó adaptar tipos de datos, reescribir funciones y triggers a T-SQL y resolver diferencias en secuencias y restricciones de integridad.

## Qué incluye esta etapa

| Área | Qué se implementó |
|---|---|
| **Modelo** | 18 tablas en 3FN, repartidas en 4 esquemas de datos (`catalogo`, `operacion`, `facturacion`, `calidad`) y un esquema `reportes` con 13 vistas analíticas |
| **Lógica de negocio** | 1 función (`fn_buscar_habitaciones_disponibles`), 1 procedimiento (`sp_calcular_total_factura`) y 4 triggers |
| **Seguridad** | 7 roles de base de datos con permisos por esquema, `DENY` explícito al auditor y SQL Server Audit sobre facturación |
| **Optimización** | 3 consultas analíticas con funciones ventana, índices de cobertura y vistas indexadas (reducción de 91 % a 99 % en lecturas lógicas) |
| **Dimensionamiento** | Proyección de crecimiento a 5 años y configuración recomendada |
| **Continuidad** | Modelo de recuperación FULL; respaldos Full, Diferencial y Log automatizados con SQL Server Agent |
| **Recuperación** | RPO de 15 minutos y RTO de 1 hora, con procedimiento de restauración encadenada |
| **Analítica** | Dashboard en Power BI conectado a las vistas del esquema `reportes` |

## Esquemas

| Esquema | Propósito |
|---|---|
| `catalogo` | Datos de referencia y tarifas: `hotel`, `tipo_habitacion`, `tipo_comodidad`, `tipo_empleado`, `servicio`, `descuento`, `aumento_costos`, `comodidad_tipo_habitacion` |
| `operacion` | Núcleo transaccional: `habitacion`, `empleado`, `huesped`, `reservacion`, `detalle_reservacion`, `estadia`, `consumo_servicio` |
| `facturacion` | Datos financieros: `factura`, `detalle_factura` |
| `calidad` | Opiniones de los huéspedes: `resenia` |
| `reportes` | Capa analítica de solo lectura (13 vistas) |

La separación por esquemas permite otorgar permisos por esquema y no por tabla (principio de menor privilegio).

## Reglas de negocio principales

- Un huésped puede realizar múltiples reservaciones a lo largo del tiempo.
- Una reservación cubre una o más habitaciones en un rango de fechas.
- Durante la estadía se pueden cargar consumos de servicios (restaurante, lavandería, spa).
- Al hacer check-out se genera una factura consolidada, con temporadas (aumentos) y descuentos.
- **Una habitación no puede reservarse ni ocuparse dos veces en el mismo período**; lo valida el trigger `trg_verificar_reserva`.

## Seguridad

Siete roles, cada uno con su login y usuario de base de datos:

`rol_programador` · `rol_gerente` · `rol_recepcionista` · `rol_cajero` · `rol_auditor` · `rol_mesero_servicio` · `rol_atencion_cliente`

Los permisos se otorgan al rol sobre esquemas. El auditor tiene lectura global y `DENY` de `INSERT`, `UPDATE` y `DELETE`. Un SQL Server Audit registra los `INSERT` y `UPDATE` sobre `facturacion.factura` y `facturacion.detalle_factura`. Cada rol se probó con `EXECUTE AS USER` (una operación permitida y una denegada).

> Las contraseñas no se incluyen en el repositorio. En el entorno académico los logins se crearon con `CHECK_POLICY = OFF`; en producción deben activarse `CHECK_POLICY` y `CHECK_EXPIRATION`.

## Optimización de consultas

Se optimizaron tres consultas de facturación, medidas con `SET STATISTICS IO ON` y `SET STATISTICS TIME ON` sobre una carga sintética de ~200,000 facturas:

| Consulta | Técnica | Lecturas lógicas (sin → con índice) |
|---|---|---|
| 1 · Ranking de gasto por huésped | `DENSE_RANK`, `RANK`, `SUM OVER` | 1,964 → 32 |
| 2 · Variación mensual de ingresos por hotel | `LAG` | 6,794 → 618 |
| 3 · Top 3 habitaciones más rentables por hotel | `ROW_NUMBER` | 4,597 → 59 |

Los planes de ejecución de cada consulta se analizan en el documento de análisis de planes.

## Analítica y Dashboard (Power BI)

El proyecto cuenta con un dashboard interactivo publicado en Power BI Service, alimentado directamente desde las 13 vistas de solo lectura del esquema `reportes`. Esto evita exponer las tablas transaccionales y asegura métricas consistentes sobre ocupación, ingresos mensuales y anuales, rendimiento por tipo de habitación, consumos de servicios y calificaciones promedio de los hoteles.

- **Acceso al reporte en línea:** [Ver Dashboard de CÉNIT en Power BI](https://app.powerbi.com/links/y6S5bSxvgP?ctid=ff1cb486-d912-49e3-9434-122e9c45895e&pbi_source=linkShare)
- **Archivo fuente:** disponible en la carpeta `powerbi/` (`.pbix`) para inspección local en Power BI Desktop.

## Respaldo y recuperación

| Tipo | Job de SQL Server Agent | Frecuencia | Retención |
|---|---|---|---|
| Completo | `HotelDB_Auto_Backup_Full` | Semanal, lunes 00:00 | 4 semanas |
| Diferencial | `HotelDB_Auto_Backup_Diff` | Diario, 01:00 | 7 días |
| Log de transacciones | `HotelDB_Auto_Backup_Log` | Cada 15 minutos | 7 días |

- **RPO:** 15 minutos · **RTO:** 1 hora (estimado de 40 a 45 minutos).
- La restauración es encadenada: último Full, último Diferencial y todos los logs posteriores, en orden. Solo el último paso usa `WITH RECOVERY`.

## Requisitos

- Microsoft SQL Server (con SQL Server Agent para los respaldos automáticos).
- SQL Server Management Studio o Azure Data Studio.
- Power BI Desktop, para abrir el dashboard.
- Un volumen `/backup` distinto al de datos y log, con al menos 10 GB.

## Cómo reproducir el proyecto

1. Crear la base `HotelDB` y los objetos del modelo (esquemas, tablas, funciones, procedimiento y triggers).
2. Cargar los datos de prueba.
3. (Opcional, para medir optimización) ejecutar el script `00_carga_sintetica_hoteldb.sql`, que genera ~200,000 facturas y permite revertir los datos al terminar.
4. Crear los índices y las vistas indexadas, y repetir las mediciones con `STATISTICS IO`.
5. Crear los roles, logins, usuarios y permisos, y configurar SQL Server Audit.
6. Crear los jobs de respaldo en SQL Server Agent y verificarlos con `sp_start_job`.
7. Conectar Power BI Desktop a `HotelDB` con un login de solo lectura y cargar las vistas del esquema `reportes`.

> Los scripts de seguridad y auditoría hacen referencia a la misma base con el nombre `cenitDB`; el resto de los scripts usa `HotelDB`.

## Documentación

- **Documento técnico:** descripción del sistema, modelo ER y 3FN, diccionario de datos, seguridad, optimización, dimensionamiento, respaldo y recuperación, dashboard y conclusiones.
- **Análisis de planes de ejecución:** comparación de las consultas C1, C2 y C3 sin índice y optimizadas.
- **Presentación de la defensa:** exposición del proyecto con el esquema pedido por el docente.

## Mejoras pendientes

- Activar `CHECK_POLICY` y `CHECK_EXPIRATION` en los logins.
- Firmar los módulos con certificado y desactivar `TRUSTWORTHY`.
- Cifrar los respaldos y aplicar TDE.
- Verificar los respaldos con `WITH CHECKSUM` y `RESTORE VERIFYONLY`.
- Guardar una copia de los respaldos fuera del servidor.

## Equipo

| Integrante | Carné |
|---|---|
| Josué Abdel Ortiz Deodanes | 00017125 |
| Osmar Alejandro Rodas Rodriguez | 00068125 |
| Kevin Vladimir Rodriguez Alvarado | 00039425 |
| Anderson José Turcios Fores | 00003925 |
| Josué Emiliano Valdés Jacobo | 00003525 |
