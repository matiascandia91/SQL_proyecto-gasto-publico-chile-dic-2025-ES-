-- 04_verificacion.sql
-- Una sola consulta que devuelve una tabla de chequeos (en pgAdmin solo se muestra
-- el resultado de la ULTIMA consulta, por eso va todo junto).

SELECT 'ordenes_compra (esperado 155260)' AS chequeo,
       COUNT(*)::text AS resultado
FROM compras.ordenes_compra

UNION ALL
SELECT 'items_oc (esperado 428043)', COUNT(*)::text
FROM compras.items_oc

UNION ALL
SELECT 'proveedores', COUNT(*)::text
FROM compras.proveedores

UNION ALL
SELECT 'filas de staging descartadas (esperado 0)',
       ((SELECT COUNT(*) FROM staging.oc_raw) - (SELECT COUNT(*) FROM compras.items_oc))::text

UNION ALL
SELECT 'ordenes con cabecera inconsistente entre sus items (esperado 0)', COUNT(*)::text
FROM (
    SELECT codigo
    FROM staging.oc_raw
    GROUP BY codigo
    HAVING COUNT(DISTINCT montototaloc_pesoschilenos) > 1
        OR COUNT(DISTINCT codigoproveedor) > 1
        OR COUNT(DISTINCT codigoorganismopublico) > 1
        OR COUNT(DISTINCT estado) > 1
) x

UNION ALL
SELECT 'montos CLP que no se pudieron convertir (esperado 0)', COUNT(*)::text
FROM staging.oc_raw
WHERE staging.limpiar_texto(montototaloc_pesoschilenos) IS NOT NULL
  AND staging.a_numero(montototaloc_pesoschilenos) IS NULL

UNION ALL
SELECT 'totales de linea que no se pudieron convertir (esperado 0)', COUNT(*)::text
FROM staging.oc_raw
WHERE staging.limpiar_texto(totallineaneto) IS NOT NULL
  AND staging.a_numero(totallineaneto) IS NULL

UNION ALL
SELECT 'fechas de envio que no se pudieron convertir (esperado 0)', COUNT(*)::text
FROM staging.oc_raw
WHERE staging.limpiar_texto(fechaenvio) IS NOT NULL
  AND staging.a_fecha(fechaenvio) IS NULL

UNION ALL
SELECT 'nombres de proveedor con caracteres mal codificados (esperado 0)', COUNT(*)::text
FROM compras.proveedores
WHERE nombre ~ ('[' || chr(195) || chr(194) || ']')

UNION ALL
SELECT 'productos con caracteres de control (esperado 0)', COUNT(*)::text
FROM compras.items_oc
WHERE producto ~ '[\u0080-\u009f]'

UNION ALL
SELECT 'SUMA INCORRECTA: monto CLP sumado por item (CLP)',
       ROUND(SUM(staging.a_numero(montototaloc_pesoschilenos)))::text
FROM staging.oc_raw

UNION ALL
SELECT 'SUMA CORRECTA: monto CLP sumado por orden (CLP)',
       ROUND(SUM(monto_total_clp))::text
FROM compras.ordenes_compra;
