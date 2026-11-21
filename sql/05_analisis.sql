-- 05_analisis.sql
-- Analisis del gasto en compras publicas (ChileCompra, ordenes enviadas en diciembre 2025)
--
-- Definicion de "gasto": suma de monto_total_clp (en pesos chilenos, CON impuestos) de las
-- ordenes enviadas en diciembre 2025, excluyendo las con cancelacion solicitada
-- (346 ordenes, 0,06% del monto). Cada orden se cuenta UNA sola vez.
--
-- COMO EJECUTAR: en pgAdmin, selecciona con el mouse UNA consulta (desde su SELECT/WITH
-- hasta el punto y coma) y pulsa F5. Si ejecutas todo el archivo, solo veras el resultado
-- de la ultima consulta.

-- =====================================================================
-- 0) Vista base: ordenes validas para el analisis
-- =====================================================================
CREATE OR REPLACE VIEW compras.v_ordenes_validas AS
SELECT *
FROM compras.ordenes_compra
WHERE estado IS DISTINCT FROM 'Cancelacion solicitada';


-- =====================================================================
-- 1) Que organismos concentran mas gasto?
--    Tecnicas: GROUP BY, window function SUM() OVER ()
-- =====================================================================
SELECT organismo,
       COUNT(*)                                             AS ordenes,
       ROUND(SUM(monto_total_clp) / 1e6)                    AS millones_clp,
       ROUND(100.0 * SUM(monto_total_clp)
             / SUM(SUM(monto_total_clp)) OVER (), 2)        AS pct_del_gasto_total
FROM compras.v_ordenes_validas
GROUP BY organismo
ORDER BY SUM(monto_total_clp) DESC
LIMIT 10;


-- =====================================================================
-- 2) Quienes son los 10 mayores proveedores?
--    Tecnicas: JOIN, RANK()
-- =====================================================================
SELECT RANK() OVER (ORDER BY SUM(o.monto_total_clp) DESC) AS ranking,
       p.nombre                                           AS proveedor,
       COUNT(*)                                           AS ordenes,
       ROUND(SUM(o.monto_total_clp) / 1e6)                AS millones_clp,
       ROUND(100.0 * SUM(o.monto_total_clp)
             / SUM(SUM(o.monto_total_clp)) OVER (), 2)    AS pct_del_gasto_total
FROM compras.v_ordenes_validas o
JOIN compras.proveedores p USING (codigo_proveedor)
GROUP BY p.codigo_proveedor, p.nombre
ORDER BY ranking
LIMIT 10;


-- =====================================================================
-- 3) Que tan concentrado esta el gasto? (curva de Pareto)
--    Cuantos proveedores hacen falta para llegar al 50% y al 80% del gasto?
--    Tecnicas: CTE, suma acumulada con window function, FILTER
-- =====================================================================
WITH por_proveedor AS (
    SELECT codigo_proveedor, SUM(monto_total_clp) AS monto
    FROM compras.v_ordenes_validas
    WHERE codigo_proveedor IS NOT NULL
    GROUP BY codigo_proveedor
),
acumulado AS (
    SELECT codigo_proveedor,
           ROW_NUMBER() OVER (ORDER BY monto DESC, codigo_proveedor)      AS ranking,
           SUM(monto) OVER (ORDER BY monto DESC, codigo_proveedor)
             / SUM(monto) OVER ()                                         AS pct_acumulado
    FROM por_proveedor
)
SELECT COUNT(*)                                            AS total_proveedores,
       MIN(ranking) FILTER (WHERE pct_acumulado >= 0.50)   AS proveedores_para_50pct,
       MIN(ranking) FILTER (WHERE pct_acumulado >= 0.80)   AS proveedores_para_80pct
FROM acumulado;


-- =====================================================================
-- 4) Cuanto se compra por trato directo, segun sector?
--    Tecnicas: agregacion condicional con FILTER
-- =====================================================================
SELECT sector,
       COUNT(*)                                                       AS ordenes,
       ROUND(SUM(monto_total_clp) / 1e6)                              AS millones_clp,
       ROUND(100.0 * COUNT(*) FILTER (WHERE es_trato_directo)
             / COUNT(*), 1)                                           AS pct_ordenes_trato_directo,
       ROUND(100.0 * SUM(monto_total_clp) FILTER (WHERE es_trato_directo)
             / SUM(monto_total_clp), 1)                               AS pct_monto_trato_directo
FROM compras.v_ordenes_validas
GROUP BY sector
HAVING COUNT(*) >= 100
ORDER BY SUM(monto_total_clp) DESC;


-- =====================================================================
-- 5) Como se distribuye el gasto por region del organismo comprador?
-- =====================================================================
SELECT region_comprador,
       COUNT(*)                                             AS ordenes,
       ROUND(SUM(monto_total_clp) / 1e6)                    AS millones_clp,
       ROUND(100.0 * SUM(monto_total_clp)
             / SUM(SUM(monto_total_clp)) OVER (), 2)        AS pct_del_gasto_total
FROM compras.v_ordenes_validas
GROUP BY region_comprador
ORDER BY SUM(monto_total_clp) DESC;


-- =====================================================================
-- 6) Como evoluciona el gasto dia a dia durante diciembre?
--    Tecnicas: window functions con marco (acumulado y media movil de 7 dias)
-- =====================================================================
WITH diario AS (
    SELECT fecha_envio,
           COUNT(*)                          AS ordenes,
           SUM(monto_total_clp) / 1e6        AS millones_clp
    FROM compras.v_ordenes_validas
    GROUP BY fecha_envio
)
SELECT fecha_envio,
       ordenes,
       ROUND(millones_clp)                                                   AS millones_clp,
       ROUND(SUM(millones_clp) OVER (ORDER BY fecha_envio))                  AS millones_acumulado,
       ROUND(AVG(millones_clp) OVER (ORDER BY fecha_envio
                                     ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)) AS media_movil_7d
FROM diario
ORDER BY fecha_envio;


-- =====================================================================
-- 7) Que rubros se compran mas?
--    Se usan los totales de linea NETOS (sin IVA) de items en CLP; los items en
--    otras monedas se excluyen porque no hay columna convertida a pesos.
--    Tecnicas: JOIN entre items y ordenes
-- =====================================================================
SELECT i.rubro_n1                                           AS rubro,
       COUNT(DISTINCT i.codigo_oc)                          AS ordenes,
       ROUND(SUM(i.total_linea_neto) / 1e6)                 AS millones_clp_neto,
       ROUND(100.0 * SUM(i.total_linea_neto)
             / SUM(SUM(i.total_linea_neto)) OVER (), 2)     AS pct_del_total
FROM compras.items_oc i
JOIN compras.v_ordenes_validas o ON o.codigo = i.codigo_oc
WHERE i.moneda_item = 'CLP'
GROUP BY i.rubro_n1
ORDER BY SUM(i.total_linea_neto) DESC
LIMIT 10;


-- =====================================================================
-- 8) Cuantos dias tarda un proveedor en aceptar una orden, segun sector?
--    Tecnicas: percentile_cont (mediana), resta de fechas
-- =====================================================================
SELECT sector,
       COUNT(*)                                                                AS ordenes,
       percentile_cont(0.5) WITHIN GROUP
           (ORDER BY (fecha_aceptacion - fecha_envio)::float8)                 AS mediana_dias,
       ROUND(AVG(fecha_aceptacion - fecha_envio), 1)                           AS promedio_dias
FROM compras.v_ordenes_validas
WHERE fecha_aceptacion IS NOT NULL
  AND fecha_aceptacion >= fecha_envio
GROUP BY sector
HAVING COUNT(*) >= 100
ORDER BY ordenes DESC;
