-- Analisis del gasto en compras publicas (ordenes enviadas en diciembre 2025)

-- Definicion de "gasto": suma de monto_total_clp de las
-- ordenes enviadas en diciembre 2025, excluyendo las con cancelacion solicitada
-- (346 ordenes, 0,06% del monto) y 3 ordenes con monto erroneo de origen.

-- 0) Calidad de datos y vista base
--    Se excluyen las ordenes con cancelacion solicitada y las ordenes cuyo monto
--    es un error de origen, verificadas contra la ficha en mercadopublico.cl.

DROP TABLE IF EXISTS compras.ordenes_excluidas CASCADE;

CREATE TABLE compras.ordenes_excluidas(
	codigo TEXT PRIMARY KEY REFERENCES compras.ordenes_compra (codigo),
	motivo TEXT NOT NULL
);

INSERT INTO compras.ordenes_excluidas (codigo, motivo) VALUES
('3833-1046-SE25', 'Moneda mal registrada: la ficha en Mercado Publico muestra TOTAL OC $5.242.181 pesos, pero el dataset la trae como CLF y se convirtio a $208.200 millones.'),
('2699-120-SE25', 'Monto mal digitado: la orden registra UF 4.267.520, pero la especificacion del proveedor indica un total bruto de UF 9.622,52.'),
('766404-26-SE25', 'Moneda mal registrada: la ficha en Mercado Publico muestra TOTAL OC $56.492 pesos por la compra de 225 botellones de agua, pero el dataset la trae como CLF y se convirtio a $2.242 millones.');

CREATE OR REPLACE VIEW compras.v_ordenes_validas AS
SELECT
	o.*
FROM
	compras.ordenes_compra o
WHERE
	o.estado IS DISTINCT FROM 'Cancelacion solicitada' AND
	NOT EXISTS(
		SELECT 1
		FROM compras.ordenes_excluidas e
		WHERE e.codigo = o.codigo
	);


-- 0b) Chequeo de calidad: moneda de la orden vs moneda de sus items
--     Una orden en moneda extranjera cuyos items estan todos en CLP sugiere que la
--     moneda del encabezado esta mal registrada.
--     Las 2 ordenes verificadas contra la ficha ya estan excluidas en el
--     bloque 0. En diciembre 2025 las restantes son 5 ordenes que suman $1.180 millones
--     (cerca de 0,08% del gasto): se mantienen en el analisis por su efecto marginal.
--     Tecnicas: CTE, NOT EXISTS (anti-join)

WITH ordenes_sospechosas AS(
	SELECT
		o.moneda,
		o.monto_total,
		o.monto_total_clp
	FROM
		compras.v_ordenes_validas o
	WHERE
		o.moneda <> 'CLP' AND
		NOT EXISTS(
			SELECT 1
			FROM compras.items_oc i
			WHERE i.codigo_oc = o.codigo AND i.moneda_item <> 'CLP'
		)
)
SELECT
	moneda,
	COUNT(*) AS ordenes,
	ROUND(SUM(monto_total_clp)/1e6) AS millones_clp_registrado,
	ROUND(SUM(monto_total)/1e6,2) AS millones_si_fueran_pesos
FROM
	ordenes_sospechosas
GROUP BY
	moneda
ORDER BY
	SUM(monto_total_clp) DESC;



-- 1) Que organismos concentran mas gasto?
--    Tecnicas: CTE, GROUP BY, window function SUM() OVER()

WITH gasto_organismo AS(
	SELECT
		organismo,
		COUNT(*) AS ordenes,
		SUM(monto_total_clp) AS monto_clp
	FROM
		compras.v_ordenes_validas
	GROUP BY
		organismo
)
SELECT
	organismo,
	ordenes,
	ROUND(monto_clp/1e6) AS millones_clp,
	ROUND(100*monto_clp/SUM(monto_clp) OVER(),2) AS pct_gasto_total
FROM
	gasto_organismo
ORDER BY
	monto_clp DESC
LIMIT 10;


-- 2) Quienes son los 10 mayores proveedores?
--    Tecnicas: CTEs encadenadas, JOIN, RANK()

WITH gasto_proveedor AS(
	SELECT
		p.codigo_proveedor,
		p.nombre AS proveedor,
		COUNT(*) AS ordenes,
		SUM(o.monto_total_clp) AS monto_clp
	FROM
		compras.v_ordenes_validas o
	JOIN
		compras.proveedores p ON o.codigo_proveedor = p.codigo_proveedor
	GROUP BY
		p.codigo_proveedor,
		p.nombre
), ranking_proveedor AS(
	SELECT
		RANK() OVER(ORDER BY monto_clp DESC) AS ranking,
		proveedor,
		ordenes,
		monto_clp,
		ROUND(100*monto_clp/SUM(monto_clp) OVER(),2) AS pct_gasto_total
	FROM
		gasto_proveedor
)
SELECT
	ranking,
	proveedor,
	ordenes,
	ROUND(monto_clp/1e6) AS millones_clp,
	pct_gasto_total
FROM
	ranking_proveedor
WHERE
	ranking <= 10
ORDER BY
	ranking;


-- 3) Que tan concentrado esta el gasto?
--    Cuantos proveedores hacen falta para llegar al 50% y al 80% del gasto?
--    Tecnicas: CTEs, suma acumulada con window function, FILTER

WITH gasto_proveedor AS(
	SELECT
		codigo_proveedor,
		SUM(monto_total_clp) AS monto_clp
	FROM
		compras.v_ordenes_validas
	WHERE
		codigo_proveedor IS NOT NULL
	GROUP BY
		codigo_proveedor
), acumulado_proveedor AS(
	SELECT
		ROW_NUMBER() OVER(ORDER BY monto_clp DESC, codigo_proveedor) AS ranking,
		SUM(monto_clp) OVER(ORDER BY monto_clp DESC, codigo_proveedor)/SUM(monto_clp) OVER() AS pct_acumulado
	FROM
		gasto_proveedor
)
SELECT
	COUNT(*) AS total_proveedores,
	MIN(ranking) FILTER(WHERE pct_acumulado >= 0.50) AS proveedores_para_50pct,
	MIN(ranking) FILTER(WHERE pct_acumulado >= 0.80) AS proveedores_para_80pct
FROM
	acumulado_proveedor;



-- 4) Cuanto se compra por trato directo, segun sector?
--    Tecnicas: CTE con agregacion condicional 
WITH gasto_sector AS(
	SELECT
		sector,
		COUNT(*) AS ordenes,
		COUNT(*) FILTER(WHERE es_trato_directo) AS ordenes_trato_directo,
		SUM(monto_total_clp) AS monto_clp,
		SUM(monto_total_clp) FILTER(WHERE es_trato_directo) AS monto_trato_directo
	FROM
		compras.v_ordenes_validas
	GROUP BY
		sector
	HAVING
		COUNT(*) >= 100
)
SELECT
	sector,
	ordenes,
	ROUND(monto_clp/1e6) AS millones_clp,
	ROUND(100.0*ordenes_trato_directo/ordenes,1) AS pct_ordenes_trato_directo,
	ROUND(100*COALESCE(monto_trato_directo,0)/monto_clp,1) AS pct_monto_trato_directo
FROM
	gasto_sector
ORDER BY
	monto_clp DESC;
