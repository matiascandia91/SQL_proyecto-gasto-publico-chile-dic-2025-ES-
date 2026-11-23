# Datos

Los datos **no se incluyen en el repositorio** por su tamaño. Hay que descargarlos desde la fuente original.

## Fuente

ChileCompra, Datos Abiertos: https://datos-abiertos.chilecompra.cl/descargas


## Cómo descargarlos

1. Entra a https://datos-abiertos.chilecompra.cl/descargas.
2. Abre la pestaña **Descarga masiva por URL**.
3. Elige **Tipo de reporte:** Órdenes de compra, **Año:** 2025, **Mes:** Diciembre.
4. Pulsa **Descargar archivo** (o abre la URL que muestra la página: `https://transparenciachc.blob.core.windows.net/oc-da/2025-12.zip`).
5. Descomprime el `.zip` y guarda el CSV dentro de la carpeta (`data/`).

## Formato del archivo

| Característica | Valor |
|---|---|
| Codificación | Latin-1 (Windows-1252) |
| Separador | `;` |
| Textos | Entre comillas dobles, algunos con saltos de línea |
| Fechas | `aaaa-mm-dd` |
| Montos | Algunos en notación científica (por ejemplo `3e+06`) |
| Valores nulos | `NA` |
| Granularidad | Una fila por **línea de producto** (el monto de la orden se repite en cada línea) |
| Tamaño (dic. 2025) | 428.043 filas, 155.260 órdenes de compra, 79 columnas |

La carga a PostgreSQL con `\copy` está documentada en `sql/02_carga.sql`.


