-- 03_modelo.sql
-- Transforma staging.oc_raw (todo texto, una fila por ITEM) en tablas tipadas y
-- normalizadas en el esquema "compras":
--     proveedores  1 ---- N  ordenes_compra  1 ---- N  items_oc
--
-- Se puede ejecutar varias veces: borra y recrea el esquema "compras".
-- Ejecutar completo (en pgAdmin: abrir el archivo en el Query Tool y pulsar F5).

-- =====================================================================
-- 1) FUNCIONES DE LIMPIEZA (viven en staging)
-- =====================================================================

-- Texto limpio: corrige caracteres propios de Windows-1252 leidos como Latin-1,
-- elimina caracteres de control, recorta espacios y convierte '' y 'NA' en NULL.
--   chr(145)/chr(146) -> comilla simple    chr(147)/chr(148) -> comilla doble
--   chr(150)/chr(151) -> guion
CREATE OR REPLACE FUNCTION staging.limpiar_texto(t TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT NULLIF(NULLIF(btrim(
        regexp_replace(
            translate(t,
                      chr(145) || chr(146) || chr(147) || chr(148) || chr(150) || chr(151),
                      '''''""--'),
            '[\u0080-\u009f]', '', 'g')
    ), ''), 'NA')
$$;

-- Numero -> NUMERIC. Acepta enteros, decimales con punto o con coma ('59790211,25')
-- y notacion cientifica ('3e+06', que el archivo usa para algunos montos redondos).
-- Si no calza, devuelve NULL.
CREATE OR REPLACE FUNCTION staging.a_numero(t TEXT) RETURNS NUMERIC
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN btrim(t) ~ '^-?[0-9]+([.,][0-9]+)?([eE][+-]?[0-9]+)?$'
                THEN replace(btrim(t), ',', '.')::numeric END
$$;

-- Entero (codigos). Si no calza, devuelve NULL.
CREATE OR REPLACE FUNCTION staging.a_entero(t TEXT) RETURNS BIGINT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN btrim(t) ~ '^[0-9]{1,18}$' THEN btrim(t)::bigint END
$$;

-- Fecha -> DATE. El archivo trae aaaa-mm-dd ('2025-12-02'); tambien se acepta
-- dd-mm-aaaa por si otros meses usan ese formato. 'NA' o formato distinto -> NULL.
CREATE OR REPLACE FUNCTION staging.a_fecha(t TEXT) RETURNS DATE
LANGUAGE sql AS $$
    SELECT CASE
        WHEN btrim(t) ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])'
            THEN to_date(left(btrim(t), 10), 'YYYY-MM-DD')
        WHEN btrim(t) ~ '^(0[1-9]|[12][0-9]|3[01])-(0[1-9]|1[0-2])-[0-9]{4}'
            THEN to_date(left(btrim(t), 10), 'DD-MM-YYYY')
    END
$$;

-- =====================================================================
-- 2) ESQUEMA LIMPIO
-- =====================================================================
DROP SCHEMA IF EXISTS compras CASCADE;
CREATE SCHEMA compras;

-- ---------------------------------------------------------------------
-- proveedores: una fila por codigo de proveedor
-- (el RUT esta a nivel de sucursal y a veces viene como NA, por eso no se usa como clave)
-- ---------------------------------------------------------------------
CREATE TABLE compras.proveedores (
    codigo_proveedor BIGINT PRIMARY KEY,
    nombre           TEXT,
    actividad        TEXT,
    comuna           TEXT,
    region           TEXT,
    pais             TEXT
);

INSERT INTO compras.proveedores (codigo_proveedor, nombre, actividad, comuna, region, pais)
SELECT DISTINCT ON (codigo_proveedor)
       codigo_proveedor, nombre, actividad, comuna, region, pais
FROM (
    SELECT staging.a_entero(codigoproveedor)         AS codigo_proveedor,
           staging.limpiar_texto(nombreproveedor)    AS nombre,
           staging.limpiar_texto(actividadproveedor) AS actividad,
           staging.limpiar_texto(comunaproveedor)    AS comuna,
           staging.limpiar_texto(regionproveedor)    AS region,
           staging.limpiar_texto(paisproveedor)      AS pais
    FROM staging.oc_raw
) s
WHERE codigo_proveedor IS NOT NULL
ORDER BY codigo_proveedor, nombre;

-- ---------------------------------------------------------------------
-- ordenes_compra: UNA fila por orden (en staging se repite en cada item)
-- ---------------------------------------------------------------------
CREATE TABLE compras.ordenes_compra (
    codigo                    TEXT PRIMARY KEY,
    nombre                    TEXT,
    tipo_oc                   TEXT,
    procedencia               TEXT,
    es_trato_directo          BOOLEAN,
    es_compra_agil            BOOLEAN,
    estado                    TEXT,
    fecha_creacion            DATE,
    fecha_envio               DATE,
    fecha_aceptacion          DATE,
    fecha_cancelacion         DATE,
    fecha_ultima_modificacion DATE,
    moneda                    TEXT,
    monto_total               NUMERIC,   -- en la moneda original de la orden
    monto_total_clp           NUMERIC,   -- convertido a pesos chilenos (usar este para sumar)
    impuestos                 NUMERIC,
    descuentos                NUMERIC,
    cargos                    NUMERIC,
    total_neto                NUMERIC,
    codigo_organismo          BIGINT,
    organismo                 TEXT,
    sector                    TEXT,
    codigo_unidad_compra      BIGINT,
    unidad_compra             TEXT,
    ciudad_comprador          TEXT,
    region_comprador          TEXT,
    codigo_proveedor          BIGINT REFERENCES compras.proveedores (codigo_proveedor),
    codigo_licitacion         TEXT,
    financiamiento            TEXT
);

INSERT INTO compras.ordenes_compra (
    codigo, nombre, tipo_oc, procedencia, es_trato_directo, es_compra_agil, estado,
    fecha_creacion, fecha_envio, fecha_aceptacion, fecha_cancelacion, fecha_ultima_modificacion,
    moneda, monto_total, monto_total_clp, impuestos, descuentos, cargos, total_neto,
    codigo_organismo, organismo, sector, codigo_unidad_compra, unidad_compra,
    ciudad_comprador, region_comprador, codigo_proveedor, codigo_licitacion, financiamiento)
SELECT DISTINCT ON (codigo)
    btrim(codigo),
    staging.limpiar_texto(nombre),
    staging.limpiar_texto(codigoabreviadotipooc),
    staging.limpiar_texto(procedenciaoc),
    btrim(estratodirecto) ILIKE 'S%',
    btrim(escompraagil)   ILIKE 'S%',
    staging.limpiar_texto(estado),
    staging.a_fecha(fechacreacion),
    staging.a_fecha(fechaenvio),
    staging.a_fecha(fechaaceptacion),
    staging.a_fecha(fechacancelacion),
    staging.a_fecha(fechaultimamodificacion),
    staging.limpiar_texto(tipomonedaoc),
    staging.a_numero(montototaloc),
    staging.a_numero(montototaloc_pesoschilenos),
    staging.a_numero(impuestos),
    staging.a_numero(descuentos),
    staging.a_numero(cargos),
    staging.a_numero(totalnetooc),
    staging.a_entero(codigoorganismopublico),
    staging.limpiar_texto(organismopublico),
    staging.limpiar_texto(sector),
    staging.a_entero(codigounidadcompra),
    staging.limpiar_texto(unidadcompra),
    staging.limpiar_texto(ciudadunidadcompra),
    staging.limpiar_texto(regionunidadcompra),
    staging.a_entero(codigoproveedor),
    staging.limpiar_texto(codigolicitacion),
    staging.limpiar_texto(financiamiento)
FROM staging.oc_raw
WHERE codigo IS NOT NULL AND btrim(codigo) <> ''
ORDER BY codigo, iditem;

-- ---------------------------------------------------------------------
-- items_oc: una fila por linea de cada orden
-- (no se copian las especificaciones largas de comprador/proveedor)
-- ---------------------------------------------------------------------
CREATE TABLE compras.items_oc (
    codigo_oc           TEXT   NOT NULL REFERENCES compras.ordenes_compra (codigo),
    id_item             BIGINT NOT NULL,
    codigo_categoria    BIGINT,
    categoria           TEXT,
    codigo_producto_onu BIGINT,
    producto            TEXT,
    rubro_n1            TEXT,
    rubro_n2            TEXT,
    rubro_n3            TEXT,
    cantidad            NUMERIC,
    unidad_medida       TEXT,
    moneda_item         TEXT,
    precio_neto         NUMERIC,
    total_cargos        NUMERIC,
    total_descuentos    NUMERIC,
    total_impuestos     NUMERIC,
    total_linea_neto    NUMERIC,
    PRIMARY KEY (codigo_oc, id_item)
);

INSERT INTO compras.items_oc (
    codigo_oc, id_item, codigo_categoria, categoria, codigo_producto_onu, producto,
    rubro_n1, rubro_n2, rubro_n3, cantidad, unidad_medida, moneda_item,
    precio_neto, total_cargos, total_descuentos, total_impuestos, total_linea_neto)
SELECT DISTINCT ON (codigo_oc, id_item)
    codigo_oc, id_item, codigo_categoria, categoria, codigo_producto_onu, producto,
    rubro_n1, rubro_n2, rubro_n3, cantidad, unidad_medida, moneda_item,
    precio_neto, total_cargos, total_descuentos, total_impuestos, total_linea_neto
FROM (
    SELECT btrim(codigo)                              AS codigo_oc,
           staging.a_entero(iditem)                   AS id_item,
           staging.a_entero(codigocategoria)          AS codigo_categoria,
           staging.limpiar_texto(categoria)           AS categoria,
           staging.a_entero(codigoproductoonu)        AS codigo_producto_onu,
           staging.limpiar_texto(nombreroductogenerico) AS producto,
           staging.limpiar_texto(rubron1)             AS rubro_n1,
           staging.limpiar_texto(rubron2)             AS rubro_n2,
           staging.limpiar_texto(rubron3)             AS rubro_n3,
           staging.a_numero(cantidad)                 AS cantidad,
           staging.limpiar_texto(unidadmedida)        AS unidad_medida,
           staging.limpiar_texto(monedaitem)          AS moneda_item,
           staging.a_numero(precioneto)               AS precio_neto,
           staging.a_numero(totalcargos)              AS total_cargos,
           staging.a_numero(totaldescuentos)          AS total_descuentos,
           staging.a_numero(totalimpuestos)           AS total_impuestos,
           staging.a_numero(totallineaneto)           AS total_linea_neto
    FROM staging.oc_raw
    WHERE codigo IS NOT NULL AND btrim(codigo) <> ''
) s
WHERE id_item IS NOT NULL
ORDER BY codigo_oc, id_item;

ANALYZE compras.proveedores;
ANALYZE compras.ordenes_compra;
ANALYZE compras.items_oc;
