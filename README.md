# Gasto público en compras del Estado de Chile (diciembre 2025)

Proyecto de análisis en **SQL (PostgreSQL)** sobre los datos abiertos de ChileCompra: **155.260 órdenes de compra** y **428.043 líneas de productos** enviadas durante diciembre de 2025.

El foco no es solo consultar, sino **llevar datos reales y sucios hasta un modelo confiable**: carga, limpieza, modelado relacional, verificación contra la fuente y análisis con CTEs y window functions.

## Hallazgos

### 1. Sumar directamente la tabla original más que duplica el gasto
En los datos originales cada fila es una línea de producto, y el monto total de la orden se repite en todas sus líneas. Sobre los datos sin depurar:

| Cálculo | Monto (CLP) |
|---|---|
| Sumando sobre la tabla original (una fila por línea) | 3,59 billones |
| Contando cada orden una sola vez | 1,78 billones |
| **Sobreestimación** | **+101%** |

El modelo normalizado (`ordenes_compra` + `items_oc`) elimina este error de raíz.

### 2. Tres órdenes con montos erróneos de origen explicaban el 21% del gasto
Al revisar las órdenes de mayor monto contra su ficha en mercadopublico.cl, tres presentaban errores en la fuente (≈ $380 mil millones en total):

| Orden | Qué ocurre |
|---|---|
| `3833-1046-SE25` (arriendo de vehículos, municipalidad) | La ficha muestra **$5.242.181** en pesos, pero el dataset la trae como UF y se convirtió a $208.200 millones |
| `766404-26-SE25` (compra de 225 botellones de agua) | La ficha muestra **$56.492** en pesos, pero el dataset la trae como UF y se convirtió a $2.242 millones |
| `2699-120-SE25` (seguros de bienes municipales) | Monto mal digitado: la orden registra UF 4,27 millones (≈ $169.500 millones), pero el total bruto indicado por el proveedor es UF 9.622,52 (≈ $381 millones) |

Las tres se **excluyen del análisis** y quedan registradas con su motivo en la tabla `compras.ordenes_excluidas`. Un chequeo sistemático detectó 5 órdenes más con el mismo patrón, por unos $1.180 millones: se mantienen por su efecto marginal. El chequeo está documentado en `sql/05_analisis.sql`.

Tras la depuración, el gasto analizado es de **≈ $1,40 billones** en **154.911 órdenes**.

### 3. El gasto está concentrado en pocos organismos y en pocos proveedores
- **Organismos:** Cenabast concentra el **9,3%** del gasto y el Ministerio de Obras Públicas el 4,9%. Los 10 mayores organismos suman el **27,1%**.
- **Proveedores:** de 26.513 proveedores con órdenes, **201 (0,8%) concentran el 50% del gasto** y **1.496 (5,6%) el 80%**.
- Los tres mayores proveedores son constructoras con entre 1 y 4 órdenes cada una (entre $25.900 y $30.000 millones): el ranking refleja contratos de obras puntuales más que compras recurrentes. Más abajo aparecen proveedores de medicamentos (Roche, MSD, Johnson & Johnson), combustible (Copec) y beneficios (Edenred).

### 4. El trato directo pesa mucho más en dinero que en número de órdenes, sobre todo en Salud

| Sector | Órdenes | Gasto (millones CLP) | % de órdenes por trato directo | % del monto por trato directo |
|---|---|---|---|---|
| Salud | 50.679 | 444.225 | 7,8% | **29,2%** |
| Municipalidades | 52.126 | 390.311 | 6,2% | 5,1% |
| Gob. Central y Universidades | 26.233 | 270.347 | 8,7% | 12,6% |
| Obras Públicas | 2.657 | 142.598 | 7,2% | 1,9% |
| FFAA | 11.167 | 61.013 | 3,4% | 8,1% |
| Otros | 4.456 | 39.499 | 5,1% | 6,4% |
| Sin sector informado | 5.766 | 32.307 | 5,8% | 12,0% |
| Legislativo y Judicial | 1.827 | 20.729 | 6,1% | 6,1% |

En Salud, menos del 8% de las órdenes se compra por trato directo, pero representan casi el 30% del monto: las compras directas son de montos mucho mayores. Entre las órdenes más grandes del mes aparecen varias de trato directo emitidas por Cenabast.

## Modelo de datos

```
proveedores (1) ──── (N) ordenes_compra (1) ──── (N) items_oc
                                │
                     ordenes_excluidas (motivo de cada exclusión)
```

- `proveedores`: una fila por proveedor.
- `ordenes_compra`: **una fila por orden**, con fechas (`DATE`), montos (`NUMERIC`) y banderas booleanas.
- `items_oc`: una fila por línea de producto.
- `v_ordenes_validas`: vista base del análisis (sin cancelaciones solicitadas ni órdenes excluidas).

## Limpieza de datos aplicada

- Archivo en **Latin-1**, separado por `;`, con textos multilínea y bytes sin definir.
- Valores `NA` convertidos a nulos; textos con caracteres de control y comillas curvas normalizados.
- Fechas en formato `aaaa-mm-dd` y montos en **notación científica** (por ejemplo `3e+06`) convertidos a nativos.
- Montos en cinco monedas (CLP, UF, UTM, USD, EUR): se usa la columna ya convertida a pesos que entrega la fuente.
- Verificación automatizada (`04_verificacion.sql`): conteos, consistencia de cabeceras entre líneas de una misma orden, conversiones fallidas y caracteres mal codificados.

## Técnicas de SQL utilizadas

CTEs encadenadas, window functions (`SUM() OVER`, `RANK`, `ROW_NUMBER`, sumas acumuladas), `DISTINCT ON`, agregación condicional con `FILTER`, `NOT EXISTS`, vistas, claves primarias y foráneas, y funciones SQL de limpieza.

## Estructura del repositorio

```
├── README.md
├── data/
│   └── README.md          # instrucciones de descarga (el CSV no se incluye debido a su peso)
└── sql/
    ├── 01_staging.sql         # esquema de carga (todo texto)
    ├── 02_carga.sql           # comando de carga y formato real del archivo
    ├── 03_modelo.sql          # funciones de limpieza y tablas normalizadas
    ├── 04_verificacion.sql    # chequeos de calidad
    └── 05_analisis.sql        # exclusiones documentadas y consultas de negocio
```

## Cómo reproducirlo

1. Descargar el CSV de órdenes de compra de diciembre 2025 (ver `data/README.md`).
2. Crear la base: `CREATE DATABASE chilecompra;`
3. Ejecutar `sql/01_staging.sql`.
4. Carga el archivo con `\copy` desde `psql`, usando el comando de `sql/02_carga.sql` utilizando la ruta del archivo.
5. Ejecuta `sql/03_modelo.sql` y luego `sql/04_verificacion.sql`.
6. Ejecuta `sql/05_analisis.sql`.

Probado con PostgreSQL 18.

## Limitaciones

- Cubre **un solo mes** (diciembre 2025). 
- Los montos incluyen impuestos y corresponden a órdenes enviadas en el mes, en cualquier estado excepto cancelación solicitada.
- 5.766 órdenes (3,7%) no informan sector.
- La región viene escrita con formatos mixtos en la fuente (por ejemplo, "Región de Valparaíso" y "Valparaíso").


## Fuente de datos

ChileCompra, Datos Abiertos: https://datos-abiertos.chilecompra.cl/descargas. Consulta los términos de uso de los datos en el sitio.
