-- =====================================================================
-- OLIST BRAZILIAN E-COMMERCE — ¿Qué factores están asociados con malas reseñas?
-- =====================================================================
/* Dataset: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
   Dialecto: SQLite 3.25+ (utiliza funciones de ventana y julianday())

   Tablas utilizadas (nombres tal como fueron importadas en este proyecto):
     customers    -> olist_customers_dataset.csv
     orders       -> olist_orders_dataset.csv
     items        -> olist_order_items_dataset.csv
     payments     -> olist_order_payments_dataset.csv
     reviews      -> olist_order_reviews_dataset.csv
     products     -> olist_products_dataset.csv
     sellers      -> olist_sellers_dataset.csv
     geolocation  -> olist_geolocation_dataset.csv
     product_category_name_translation
   ===================================================================== */


-- ============================================================
-- 1 - EXPLORACIÓN DE LOS DATOS
-- ============================================================

/* La estructura de la base de datos fue revisada utilizando
   DB Browser for SQLite.

   La revisión incluyó:
   - Tablas
   - Columnas
   - Tipos de datos
   - Cantidad de registros
   - Registros de ejemplo

   Las siguientes consultas se enfocan en la exploración
   directamente relacionada con la pregunta de negocio.
*/


-- ------------------------------------------------------------
-- 1.1 - DISTRIBUCIÓN DE LAS PUNTUACIONES DE LAS RESEÑAS
-- ------------------------------------------------------------

SELECT
    review_score,
    COUNT(*) AS reviews,
    ROUND(
        COUNT(*) * 100.0 /
        (SELECT COUNT(*) FROM reviews),
        2
    ) AS percentage
FROM reviews
GROUP BY review_score
ORDER BY review_score;


-- ------------------------------------------------------------
-- 1.2 - COBERTURA DE LAS RESEÑAS A LO LARGO DEL TIEMPO
-- ------------------------------------------------------------

SELECT
    SUBSTR(review_creation_date, 1, 7) AS month,
    COUNT(*) AS reviews
FROM reviews
GROUP BY month
ORDER BY month;


-- ------------------------------------------------------------
-- 1.3 - RESEÑAS CON Y SIN COMENTARIOS
-- ------------------------------------------------------------

SELECT
    CASE
        WHEN review_comment_message IS NULL
             OR TRIM(review_comment_message) = ''
        THEN 'Without comment'
        ELSE 'With comment'
    END AS comment_status,
    COUNT(*) AS reviews,
    ROUND(
        COUNT(*) * 100.0 /
        (SELECT COUNT(*) FROM reviews),
        2
    ) AS percentage
FROM reviews
GROUP BY comment_status;


-- ------------------------------------------------------------
-- 1.4 - DISTRIBUCIÓN DEL ESTADO DE LOS PEDIDOS
-- ------------------------------------------------------------

SELECT
    order_status,
    COUNT(*) AS orders,
    ROUND(
        COUNT(*) * 100.0 /
        (SELECT COUNT(*) FROM orders),
        2
    ) AS percentage
FROM orders
GROUP BY order_status
ORDER BY orders DESC;


-- ------------------------------------------------------------
-- 1.5 - PEDIDOS A LO LARGO DEL TIEMPO
-- ------------------------------------------------------------

SELECT
    SUBSTR(order_purchase_timestamp, 1, 7) AS month,
    COUNT(*) AS orders
FROM orders
GROUP BY month
ORDER BY month;


/* ============================================================
   HALLAZGOS DE LA EXPLORACIÓN
   ============================================================

   Las reseñas están fuertemente concentradas en puntuaciones positivas:
   5 estrellas: 57.78% | 4 estrellas: 19.29% | 3 estrellas: 8.24%
   2 estrellas: 3.18%  | 1 estrella: 11.51%

   Las reseñas de 1 y 2 estrellas representan el 14.69% de todas
   las reseñas y serán el principal foco del análisis.

   La mayoría de las reseñas no contienen comentarios escritos,
   por lo que las puntuaciones serán la principal medida de
   satisfacción del cliente, mientras que los comentarios se
   utilizarán para investigar las razones detrás de las
   puntuaciones bajas.

   La mayoría de los pedidos fueron entregados y la actividad
   de los pedidos varía a lo largo del tiempo, lo que permite
   investigar factores relacionados con las entregas y patrones
   temporales.
*/


-- ============================================================
-- 2 - CONTROL DE CALIDAD DE LOS DATOS
-- ============================================================

/* Los controles de calidad se realizan para identificar valores
   faltantes, registros inválidos, inconsistencias o duplicados
   que podrían afectar el análisis de las reseñas y de los
   factores asociados con las puntuaciones bajas.
*/


-- ------------------------------------------------------------
-- 2.1 - PUNTUACIONES DE RESEÑAS FALTANTES
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS total_reviews,
    COUNT(review_score) AS reviews_with_score,
    COUNT(*) - COUNT(review_score) AS missing_scores,
    ROUND(
        (COUNT(*) - COUNT(review_score)) * 100.0 /
        COUNT(*),
        2
    ) AS missing_percentage
FROM reviews;


-- ------------------------------------------------------------
-- 2.2 - PUNTUACIONES DE RESEÑAS INVÁLIDAS
-- ------------------------------------------------------------

SELECT
    review_score,
    COUNT(*) AS reviews
FROM reviews
WHERE review_score < 1
   OR review_score > 5
   OR review_score IS NULL
GROUP BY review_score
ORDER BY review_score;


-- ------------------------------------------------------------
-- 2.3 - RESEÑAS DUPLICADAS
-- ------------------------------------------------------------

SELECT
    review_id,
    COUNT(*) AS occurrences
FROM reviews
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;


-- ------------------------------------------------------------
-- 2.3.1 - IDs DE RESEÑAS REPETIDOS
-- ------------------------------------------------------------

SELECT
    review_id,
    COUNT(*) AS occurrences,
    COUNT(DISTINCT order_id) AS distinct_orders
FROM reviews
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;


-- ------------------------------------------------------------
-- 2.3.2 - DETALLE DE LOS IDs DE RESEÑAS REPETIDOS
-- ------------------------------------------------------------

SELECT
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp
FROM reviews
WHERE review_id IN (
    SELECT review_id
    FROM reviews
    GROUP BY review_id
    HAVING COUNT(*) > 1
)
ORDER BY review_id, order_id;


-- ------------------------------------------------------------
-- 2.3.3 - REGISTROS DE RESEÑAS EXACTAMENTE DUPLICADOS
-- ------------------------------------------------------------

SELECT
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp,
    COUNT(*) AS occurrences
FROM reviews
GROUP BY
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;


-- ------------------------------------------------------------
-- 2.3.4 - IDs DE RESEÑAS REPETIDOS Y PUNTUACIONES BAJAS
-- ------------------------------------------------------------

WITH repeated_reviews AS (
    SELECT
        review_id,
        MAX(review_score) AS review_score
    FROM reviews
    GROUP BY review_id
    HAVING COUNT(DISTINCT order_id) > 1
)

SELECT
    COUNT(*) AS repeated_review_ids,

    ROUND(
        COUNT(*) * 100.0 /
        (SELECT COUNT(DISTINCT review_id) FROM reviews),
        2
    ) AS percentage_repeated_reviews,

    SUM(
        CASE
            WHEN review_score IN (1, 2)
            THEN 1
            ELSE 0
        END
    ) AS repeated_poor_reviews,

    ROUND(
        SUM(
            CASE
                WHEN review_score IN (1, 2)
                THEN 1
                ELSE 0
            END
        ) * 100.0 /
        (SELECT COUNT(DISTINCT review_id) FROM reviews),
        2
    ) AS percentage_poor_repeated_reviews

FROM repeated_reviews;


-- ------------------------------------------------------------
-- 2.4 - FECHAS DE PEDIDOS FALTANTES
-- ------------------------------------------------------------

SELECT
    COUNT(CASE WHEN order_purchase_timestamp IS NOT NULL THEN 1 END) AS purchase_date_not_nulls,
    COUNT(CASE WHEN order_approved_at IS NULL THEN 1 END) AS approved_date_nulls,
    COUNT(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 END) AS carrier_date_nulls,
    COUNT(CASE WHEN order_delivered_customer_date IS NULL THEN 1 END) AS customer_delivery_date_nulls,
    COUNT(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 END) AS estimated_delivery_date_nulls
FROM orders;


-- ------------------------------------------------------------
-- 2.5 - FECHAS DE PEDIDOS INCONSISTENTES
-- ------------------------------------------------------------

-- Entrega anterior a la compra
SELECT
    order_id,
    order_purchase_timestamp,
    order_delivered_customer_date
FROM orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_delivered_customer_date < order_purchase_timestamp;


-- Entrega al cliente anterior al envío al transportista
SELECT
    order_id,
    order_delivered_carrier_date,
    order_delivered_customer_date
FROM orders
WHERE order_delivered_carrier_date IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL
  AND order_delivered_customer_date < order_delivered_carrier_date;


-- ------------------------------------------------------------
-- 2.6 - CONSISTENCIA ENTRE ESTADO DEL PEDIDO Y FECHA DE ENTREGA
-- ------------------------------------------------------------

SELECT
    order_status,
    COUNT(*) AS orders,
    SUM(
        CASE
            WHEN order_delivered_customer_date IS NOT NULL
            THEN 1
            ELSE 0
        END
    ) AS with_delivery_date,
    SUM(
        CASE
            WHEN order_delivered_customer_date IS NULL
            THEN 1
            ELSE 0
        END
    ) AS without_delivery_date
FROM orders
GROUP BY order_status
ORDER BY orders DESC;


-- ------------------------------------------------------------
-- 2.7 - VALORES FALTANTES EN VARIABLES POTENCIALES DE ANÁLISIS
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS total_items,
    COUNT(price) AS price_not_null,
    COUNT(freight_value) AS freight_not_null
FROM items;


SELECT
    COUNT(*) AS total_products,
    COUNT(product_category_name) AS category_not_null,
    COUNT(product_weight_g) AS weight_not_null,
    COUNT(product_length_cm) AS length_not_null,
    COUNT(product_height_cm) AS height_not_null,
    COUNT(product_width_cm) AS width_not_null
FROM products;


-- ------------------------------------------------------------
-- 2.8 - VALORES NUMÉRICOS INVÁLIDOS
-- ------------------------------------------------------------

-- Precios negativos o iguales a cero
SELECT
    COUNT(*) AS invalid_prices
FROM items
WHERE price <= 0;


-- Dimensiones de productos inválidas
SELECT
    COUNT(*) AS invalid_dimensions
FROM products
WHERE product_weight_g <= 0
   OR product_length_cm <= 0
   OR product_height_cm <= 0
   OR product_width_cm <= 0;


-- ------------------------------------------------------------
-- 2.9 - INTEGRIDAD REFERENCIAL
-- ------------------------------------------------------------

-- Reseñas sin un pedido correspondiente
SELECT
    r.review_id,
    r.order_id
FROM reviews r
LEFT JOIN orders o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;


-- Items sin un producto correspondiente
SELECT
    i.order_id,
    i.product_id
FROM items i
LEFT JOIN products p
    ON i.product_id = p.product_id
WHERE p.product_id IS NULL;


-- Items sin un vendedor correspondiente
SELECT
    i.order_id,
    i.seller_id
FROM items i
LEFT JOIN sellers s
    ON i.seller_id = s.seller_id
WHERE s.seller_id IS NULL;


/* ============================================================
   HALLAZGOS DEL CONTROL DE CALIDAD
   ============================================================

   789 IDs de reseñas están asociados con múltiples pedidos
   (aproximadamente el 0.8% de todos los IDs de reseñas).
   No son duplicados exactos y serán conservados.

   23 pedidos tienen una fecha de entrega al cliente anterior
   a la fecha de entrega al transportista (0.023% de los pedidos).
   Estos registros serán conservados y considerados al analizar
   el tiempo de entrega.

   8 pedidos entregados no tienen fecha de entrega al cliente,
   mientras que 6 pedidos cancelados tienen una fecha de entrega.
   Estos casos serán conservados para análisis posteriores.

   610 productos no tienen categoría, lo que puede limitar el
   análisis basado en categorías.

   4 productos contienen dimensiones inválidas y serán excluidos
   cuando se utilicen las dimensiones de los productos.

   Algunas variables contienen una cantidad no despreciable de
   valores faltantes. Estas observaciones serán conservadas,
   ya que las funciones de agregación de SQL generalmente
   ignoran los valores NULL por defecto.
*/


-- ============================================================
-- 3 - ANÁLISIS DE LOS DATOS
-- ============================================================

/*
   Notas de compatibilidad con SQLite:
     - EXTRACT() no está disponible; las diferencias entre fechas
       se calculan mediante julianday(date_a) - julianday(date_b),
       lo que devuelve directamente los días (con decimales).
     - Los campos de fecha provenientes del CSV deben permanecer
       como TEXT en el formato 'YYYY-MM-DD HH:MM:SS' para que
       julianday() pueda interpretarlos correctamente.
     - CAST(... AS REAL) se utiliza para evitar la división entera.

   Definiciones utilizadas:
     "Reseña negativa" = review_score IN (1, 2)
     "Reseña positiva" = review_score IN (4, 5)
*/


/* ---------------------------------------------------------------------
   3.1 - TIEMPO DE ENTREGA vs PUNTUACIÓN DE LA RESEÑA

   Hipótesis: los pedidos que tardan más en llegar reciben
   peores puntuaciones.
--------------------------------------------------------------------- */

WITH orders_delivery AS (
    SELECT
        o.order_id,
        julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp)
            AS delivery_days,

        julianday(o.order_delivered_customer_date) - julianday(o.order_estimated_delivery_date)
            AS delay_days   -- positivo = llegó después de lo estimado

    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)

SELECT
    r.review_score,
    ROUND(AVG(d.delivery_days), 1) AS avg_delivery_days,
    ROUND(AVG(d.delay_days), 1)    AS avg_delay_vs_estimate,
    COUNT(*)                       AS n_orders
FROM orders_delivery d
JOIN reviews r ON r.order_id = d.order_id
GROUP BY r.review_score
ORDER BY r.review_score;


/* ---------------------------------------------------------------------
   3.1.2 - ENTREGA TARDÍA vs EN TIEMPO — COMPARACIÓN DIRECTA
--------------------------------------------------------------------- */

WITH orders_delivery AS (
    SELECT
        o.order_id,
        CASE
            WHEN julianday(o.order_delivered_customer_date) > julianday(o.order_estimated_delivery_date)
                THEN 'Late delivery'
            ELSE 'On-time delivery'
        END AS delivery_status
    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)

SELECT
    d.delivery_status,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN r.review_score <= 2
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS pct_poor_reviews,
    COUNT(*) AS n_orders
FROM orders_delivery d
JOIN reviews r ON r.order_id = d.order_id
GROUP BY d.delivery_status
ORDER BY avg_review_score;


/* ---------------------------------------------------------------------
   3.2 - COSTO DE ENVÍO (freight_value) vs PUNTUACIÓN DE LA RESEÑA
--------------------------------------------------------------------- */

WITH order_freight AS (
    SELECT
        oi.order_id,
        SUM(oi.price) AS total_price,
        SUM(oi.freight_value) AS total_freight,
        ROUND(
            SUM(oi.freight_value) /
            NULLIF(CAST(SUM(oi.price) AS REAL), 0),
            3
        ) AS freight_ratio
    FROM items oi
    GROUP BY oi.order_id
)

SELECT
    r.review_score,
    ROUND(AVG(f.total_price), 2)   AS avg_price,
    ROUND(AVG(f.total_freight), 2) AS avg_freight,
    ROUND(AVG(f.freight_ratio), 3) AS avg_freight_ratio,
    COUNT(*)                       AS n_orders
FROM order_freight f
JOIN reviews r ON r.order_id = f.order_id
GROUP BY r.review_score
ORDER BY r.review_score;


/* ---------------------------------------------------------------------
   3.3 - CATEGORÍA DEL PRODUCTO vs PUNTUACIÓN DE LA RESEÑA

   Principales categorías con menor puntuación promedio
   (mínimo 50 reseñas).
--------------------------------------------------------------------- */

SELECT
    COALESCE(
        t.product_category_name_english,
        p.product_category_name
    ) AS category,

    ROUND(AVG(r.review_score), 2) AS avg_review_score,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN r.review_score <= 2
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS pct_poor_reviews,

    COUNT(*) AS n_reviews

FROM items oi

JOIN products p
    ON p.product_id = oi.product_id

LEFT JOIN product_category_name_translation t
    ON t.product_category_name = p.product_category_name

JOIN reviews r
    ON r.order_id = oi.order_id

GROUP BY category
HAVING COUNT(*) >= 50
ORDER BY avg_review_score ASC
LIMIT 15;


/* ---------------------------------------------------------------------
   3.4 - MÉTODO DE PAGO Y CUOTAS vs PUNTUACIÓN DE LA RESEÑA
--------------------------------------------------------------------- */

SELECT
    pay.payment_type,
    ROUND(AVG(pay.payment_installments), 1) AS avg_installments,
    ROUND(AVG(r.review_score), 2)           AS avg_review_score,
    COUNT(*)                                AS n_orders
FROM payments pay
JOIN reviews r ON r.order_id = pay.order_id
GROUP BY pay.payment_type
ORDER BY avg_review_score;


-- Cuotas agrupadas en rangos
SELECT
    CASE
        WHEN payment_installments = 1 THEN '1 (paid in full)'
        WHEN payment_installments BETWEEN 2 AND 4 THEN '2-4 installments'
        WHEN payment_installments BETWEEN 5 AND 8 THEN '5-8 installments'
        ELSE '9+ installments'
    END AS installment_bucket,

    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    COUNT(*)                      AS n_orders

FROM payments pay
JOIN reviews r ON r.order_id = pay.order_id

GROUP BY installment_bucket
ORDER BY avg_review_score;


/* ---------------------------------------------------------------------
   3.5 - VALOR DEL PEDIDO vs PUNTUACIÓN DE LA RESEÑA
--------------------------------------------------------------------- */

WITH order_value AS (
    SELECT
        order_id,
        SUM(price) AS total_price
    FROM items
    GROUP BY order_id
)

SELECT
    CASE
        WHEN v.total_price < 50  THEN '< R$50'
        WHEN v.total_price < 150 THEN 'R$50-150'
        WHEN v.total_price < 300 THEN 'R$150-300'
        ELSE '> R$300'
    END AS price_bucket,

    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    COUNT(*)                      AS n_orders

FROM order_value v
JOIN reviews r ON r.order_id = v.order_id

GROUP BY price_bucket
ORDER BY avg_review_score;


/* ---------------------------------------------------------------------
   3.6 - DESEMPEÑO DE LOS VENDEDORES

   Vendedores con más de 20 ventas, ordenados según la menor
   puntuación promedio.
--------------------------------------------------------------------- */

SELECT
    oi.seller_id,
    COUNT(DISTINCT oi.order_id)   AS n_orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN r.review_score <= 2
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS pct_poor_reviews

FROM items oi
JOIN reviews r ON r.order_id = oi.order_id

GROUP BY oi.seller_id
HAVING COUNT(DISTINCT oi.order_id) >= 20
ORDER BY avg_review_score ASC
LIMIT 20;


/* ---------------------------------------------------------------------
   3.7 - DISTANCIA GEOGRÁFICA
   (estado del cliente != estado del vendedor)
--------------------------------------------------------------------- */

WITH order_states AS (
    SELECT
        o.order_id,

        CASE
            WHEN c.customer_state = s.seller_state
            THEN 'Same state'
            ELSE 'Different states'
        END AS route_type

    FROM orders o

    JOIN customers c
        ON c.customer_id = o.customer_id

    JOIN items oi
        ON oi.order_id = o.order_id

    JOIN sellers s
        ON s.seller_id = oi.seller_id
)

SELECT
    os.route_type,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    COUNT(DISTINCT os.order_id)   AS n_orders

FROM order_states os
JOIN reviews r ON r.order_id = os.order_id

GROUP BY os.route_type
ORDER BY avg_review_score;


/* ---------------------------------------------------------------------
   3.8 - % DE ENTREGAS TARDÍAS SOBRE EL TOTAL DE ENTREGAS

   Base: todos los pedidos con estado 'delivered' y con una
   fecha de entrega registrada.
--------------------------------------------------------------------- */

SELECT
    COUNT(*) AS total_delivered_orders,

    SUM(
        CASE
            WHEN julianday(order_delivered_customer_date)
               > julianday(order_estimated_delivery_date)
            THEN 1
            ELSE 0
        END
    ) AS late_orders,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN julianday(order_delivered_customer_date)
                   > julianday(order_estimated_delivery_date)
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS pct_late_deliveries

FROM orders

WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;


/* ---------------------------------------------------------------------
   3.9 - % DE RESEÑAS NEGATIVAS (puntuación 1 o 2)
   POR CATEGORÍA DE PRODUCTO

   Mínimo 30 reseñas por categoría para evitar resultados
   demasiado sensibles a categorías con pocas observaciones.
--------------------------------------------------------------------- */

SELECT
    COALESCE(
        t.product_category_name_english,
        p.product_category_name
    ) AS category,

    COUNT(*) AS total_reviews,

    SUM(
        CASE
            WHEN r.review_score <= 2
            THEN 1
            ELSE 0
        END
    ) AS poor_reviews,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN r.review_score <= 2
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS pct_poor_reviews

FROM items i

JOIN products p
    ON p.product_id = i.product_id

LEFT JOIN product_category_name_translation t
    ON t.product_category_name = p.product_category_name

JOIN reviews r
    ON r.order_id = i.order_id

GROUP BY category
HAVING COUNT(*) >= 30
ORDER BY pct_poor_reviews DESC;


/* ---------------------------------------------------------------------
   3.10 - DE LAS RESEÑAS NEGATIVAS (puntuación 1 o 2),
   ¿QUÉ % TUVO UN TIEMPO DE ENTREGA SUPERIOR AL PROMEDIO?

   Definición: "tiempo de entrega" = cantidad de días entre
   la compra (order_purchase_timestamp) y la entrega efectiva
   al cliente (order_delivered_customer_date).

   Esto NO se compara con la fecha estimada de entrega.

   El promedio se calcula sobre TODOS los pedidos entregados
   (no solamente sobre las reseñas negativas), para establecer
   un punto de referencia general.
--------------------------------------------------------------------- */

WITH delivery_times AS (
    SELECT
        o.order_id,

        julianday(o.order_delivered_customer_date)
        - julianday(o.order_purchase_timestamp)
        AS delivery_days

    FROM orders o

    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
),

overall_average AS (
    SELECT
        AVG(delivery_days) AS avg_delivery_days
    FROM delivery_times
)

SELECT

    (
        SELECT ROUND(avg_delivery_days, 2)
        FROM overall_average
    ) AS avg_delivery_time_days,

    COUNT(*) AS total_negative_reviews,

    SUM(
        CASE
            WHEN dt.delivery_days >
                 (SELECT avg_delivery_days
                  FROM overall_average)
            THEN 1
            ELSE 0
        END
    ) AS negative_reviews_above_average,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN dt.delivery_days >
                     (SELECT avg_delivery_days
                      FROM overall_average)
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS pct_negative_reviews_above_average

FROM delivery_times dt

JOIN reviews r
    ON r.order_id = dt.order_id

WHERE r.review_score <= 2;


/* ---------------------------------------------------------------------
   3.10.b - MISMO CÁLCULO DESAGREGADO POR CADA PUNTUACIÓN (1 A 5)

   Permite observar la tendencia completa en lugar de analizar
   únicamente el grupo de reseñas negativas.
--------------------------------------------------------------------- */

WITH delivery_times AS (
    SELECT
        o.order_id,

        julianday(o.order_delivered_customer_date)
        - julianday(o.order_purchase_timestamp)
        AS delivery_days

    FROM orders o

    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
),

overall_average AS (
    SELECT
        AVG(delivery_days) AS avg_delivery_days
    FROM delivery_times
)

SELECT
    r.review_score,

    COUNT(*) AS total_orders,

    ROUND(
        AVG(dt.delivery_days),
        2
    ) AS avg_delivery_time_for_score,

    SUM(
        CASE
            WHEN dt.delivery_days >
                 (SELECT avg_delivery_days
                  FROM overall_average)
            THEN 1
            ELSE 0
        END
    ) AS orders_above_average,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN dt.delivery_days >
                     (SELECT avg_delivery_days
                      FROM overall_average)
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS pct_above_average

FROM delivery_times dt

JOIN reviews r
    ON r.order_id = dt.order_id

GROUP BY r.review_score
ORDER BY r.review_score;


/* ---------------------------------------------------------------------
   3.11 - DE TODAS LAS ENTREGAS TARDÍAS
   (fecha real > fecha estimada),
   ¿QUÉ % CORRESPONDE A CADA PUNTUACIÓN?

   La base del 100% es el total de entregas tardías,
   y ese 100% se distribuye entre las diferentes puntuaciones.
--------------------------------------------------------------------- */

WITH late_deliveries AS (
    SELECT
        o.order_id

    FROM orders o

    WHERE o.order_status = 'delivered'

      AND o.order_delivered_customer_date IS NOT NULL

      AND o.order_estimated_delivery_date IS NOT NULL

      AND julianday(o.order_delivered_customer_date)
          > julianday(o.order_estimated_delivery_date)
)

SELECT
    r.review_score,

    COUNT(*) AS late_delivery_count,

    ROUND(
        100.0 * COUNT(*)
        /
        (SELECT COUNT(*)
         FROM late_deliveries),
        2
    ) AS pct_of_total_late_deliveries

FROM late_deliveries ld

JOIN reviews r
    ON r.order_id = ld.order_id

GROUP BY r.review_score
ORDER BY r.review_score;


/* ============================================================
   3 - ANÁLISIS DE LOS DATOS — PRINCIPALES HALLAZGOS
   ============================================================

   El análisis evaluó varios factores que podrían estar asociados
   con las reseñas negativas, distinguiendo entre factores que están
   dentro de la influencia de Olist y aquellos que dependen
   principalmente de las características del producto, vendedor
   o cliente.

   Entre los factores fuera del control directo de Olist, algunas
   categorías de productos y vendedores muestran proporciones
   relativamente altas de puntuaciones bajas. Por ejemplo, ciertas
   categorías, como productos de oficina y ropa para hombres,
   presentan proporciones de puntuaciones bajas de aproximadamente
   26-27%.

   Sin embargo, ni las categorías individuales ni los vendedores
   representan una proporción suficientemente grande del total
   de pedidos como para tener un impacto significativo sobre la
   tasa general de reseñas negativas.

   El precio del producto presenta una asociación débil con la
   satisfacción del cliente, ya que los productos de mayor precio
   tienden a recibir puntuaciones promedio más bajas.

   Las compras superiores a $300 tienen una puntuación promedio
   de 3.96, frente a 4.17 para las compras inferiores a $50.

   Una posible explicación es que los productos más costosos
   generan mayores expectativas por parte de los clientes, por
   lo que la insatisfacción puede ser más pronunciada cuando el
   producto no cumple con esas expectativas.

   La distancia geográfica entre el vendedor y el cliente también
   presenta una asociación negativa con las puntuaciones, aunque
   la diferencia es relativamente pequeña.

   Una posible explicación es que las mayores distancias tienden
   a incrementar los tiempos de entrega. Sin embargo, la distancia
   por sí misma no parece ser un factor principal de las reseñas
   negativas.

   Entre los factores que Olist puede influir más directamente,
   los costos de envío y los métodos de pago muestran poca
   asociación con las puntuaciones.

   El número de cuotas presenta una relación negativa contraintuitiva
   con las puntuaciones: las compras realizadas en un mayor número
   de cuotas tienden a recibir puntuaciones más bajas.

   Sin embargo, esta relación probablemente se explica en parte
   por los precios más elevados de los productos comprados en
   cuotas y no necesariamente por el método de pago en sí.


   ------------------------------------------------------------
   EL TIEMPO DE ENTREGA COMO FACTOR CLAVE
   ------------------------------------------------------------

   El desempeño de las entregas surge como el factor más relevante
   identificado en el análisis.

   Aproximadamente el 8.11% de las entregas ocurrieron después
   de la fecha estimada, y solamente el 34% de estas entregas
   tardías recibieron una puntuación de 4 o 5 estrellas.

   Sin embargo, debido a que las entregas tardías representan
   una proporción relativamente pequeña del total de pedidos,
   por sí solas no explican la mayoría de las reseñas negativas.

   Un hallazgo aún más importante es que aproximadamente el 60%
   de las reseñas negativas estuvieron asociadas con entregas
   que tardaron más que el tiempo promedio de entrega.

   Esto sugiere que la insatisfacción de los clientes no se limita
   a las entregas que superan formalmente la fecha límite estimada.

   Los tiempos de entrega más largos parecen afectar la satisfacción
   del cliente incluso cuando el pedido técnicamente llega dentro
   del plazo prometido.


   ------------------------------------------------------------
   CONCLUSIÓN
   ------------------------------------------------------------

   En general, el análisis sugiere que varios factores están
   asociados con la satisfacción del cliente, pero la mayoría
   presenta un efecto relativamente pequeño o se encuentra fuera
   del control directo de Olist.

   Entre los factores que Olist puede influir, el tiempo de entrega
   se destaca como la principal oportunidad de mejora.

   Reducir los tiempos promedio de entrega podría mejorar la
   satisfacción del cliente incluso sin enfocarse exclusivamente
   en eliminar las entregas que superan la fecha estimada.

   Esto es particularmente relevante para el modelo de negocio
   de Olist, que coordina transacciones y logística entre una gran
   cantidad de vendedores independientes y clientes distribuidos
   a lo largo de un mercado geográficamente extenso.

   Por lo tanto, mejorar la eficiencia logística y reducir los
   tiempos de entrega podría ser una de las formas más efectivas
   para que Olist mejore la experiencia del cliente y,
   consecuentemente, las puntuaciones de las reseñas.
*/


------------------------------------------------------------------------------------------------------------------------------------------
/* OPCIONAL:
   =====================================================================
   EXPORTACIÓN PARA POWER BI Y PYTHON — Olist (SQLite)

   Una fila por pedido, con todas las dimensiones y métricas necesarias
   para construir un dashboard o realizar análisis más detallados:
   fechas, entregas, precio, flete, categoría principal, pagos,
   geografía y puntuación de la reseña.
   ===================================================================== */

WITH order_items_agg AS (

    /* Métricas agregadas a nivel de pedido */
    SELECT
        order_id,
        COUNT(*) AS n_items,
        COUNT(DISTINCT seller_id) AS n_sellers,
        SUM(price) AS total_price,
        SUM(freight_value) AS total_freight,

        ROUND(
            SUM(freight_value) /
            NULLIF(CAST(SUM(price) AS REAL), 0),
            3
        ) AS freight_ratio

    FROM items
    GROUP BY order_id
),

main_item AS (

    /* Selecciona el producto de mayor precio del pedido.
       Se utiliza como "producto principal" para asignar una
       categoría y un vendedor de referencia cuando el pedido
       contiene varios productos diferentes. */

    SELECT
        order_id,
        product_id,
        seller_id

    FROM (
        SELECT
            i.order_id,
            i.product_id,
            i.seller_id,

            ROW_NUMBER() OVER (
                PARTITION BY i.order_id
                ORDER BY i.price DESC
            ) AS rn

        FROM items i
    )

    WHERE rn = 1
),

category_por_pedido AS (

    SELECT
        mi.order_id,

        COALESCE(
            t.product_category_name_english,
            p.product_category_name
        ) AS main_category

    FROM main_item mi

    JOIN products p
        ON p.product_id = mi.product_id

    LEFT JOIN product_category_name_translation t
        ON t.product_category_name = p.product_category_name
),

seller_por_pedido AS (

    SELECT
        mi.order_id,
        s.seller_state AS main_seller_state

    FROM main_item mi

    JOIN sellers s
        ON s.seller_id = mi.seller_id
),

pagos_por_pedido AS (

    /* Un pedido puede tener múltiples registros de pago
       (por ejemplo, tarjeta de crédito + voucher).

       Se conserva el tipo de pago con el mayor importe como
       "pago principal", y se calcula el importe total pagado
       junto con el número máximo de cuotas utilizadas. */

    SELECT
        order_id,
        SUM(payment_value) AS total_payment_value,
        MAX(payment_installments) AS max_installments

    FROM payments

    GROUP BY order_id
),

tipo_pago_principal AS (

    SELECT
        order_id,
        payment_type

    FROM (
        SELECT
            order_id,
            payment_type,

            ROW_NUMBER() OVER (
                PARTITION BY order_id
                ORDER BY payment_value DESC
            ) AS rn

        FROM payments
    )

    WHERE rn = 1
),

base_pedido AS (

    SELECT
        o.order_id,

        DATE(o.order_purchase_timestamp)
            AS purchase_date,

        strftime(
            '%Y-%m',
            o.order_purchase_timestamp
        ) AS purchase_year_month,

        o.order_status,

        c.customer_state,

        CASE
            WHEN o.order_delivered_customer_date IS NULL
            THEN NULL

            ELSE ROUND(
                julianday(o.order_delivered_customer_date)
                - julianday(o.order_purchase_timestamp),
                1
            )
        END AS delivery_days,

        CASE
            WHEN o.order_delivered_customer_date IS NULL
              OR o.order_estimated_delivery_date IS NULL
            THEN NULL

            ELSE ROUND(
                julianday(o.order_delivered_customer_date)
                - julianday(o.order_estimated_delivery_date),
                1
            )
        END AS delay_vs_estimate_days,

        CASE
            WHEN o.order_delivered_customer_date IS NULL
              OR o.order_estimated_delivery_date IS NULL
            THEN NULL

            WHEN julianday(o.order_delivered_customer_date)
               > julianday(o.order_estimated_delivery_date)
            THEN 1

            ELSE 0
        END AS is_late

    FROM orders o

    JOIN customers c
        ON c.customer_id = o.customer_id
)

SELECT
    b.order_id,
    b.purchase_date,
    b.purchase_year_month,
    b.order_status,
    r.review_score,
    b.is_late,
    b.delivery_days,
    b.delay_vs_estimate_days,

    oia.n_items,
    oia.n_sellers,
    oia.total_price,
    oia.total_freight,
    oia.freight_ratio,

    pp.total_payment_value,
    pp.max_installments,

    tpp.payment_type,

    cp.main_category,

    b.customer_state,

    sp.main_seller_state,

    CASE
        WHEN b.customer_state = sp.main_seller_state
        THEN 'Same state'
        ELSE 'Different states'
    END AS route_type

FROM base_pedido b

JOIN reviews r
    ON r.order_id = b.order_id

LEFT JOIN order_items_agg oia
    ON oia.order_id = b.order_id

LEFT JOIN category_por_pedido cp
    ON cp.order_id = b.order_id

LEFT JOIN seller_por_pedido sp
    ON sp.order_id = b.order_id

LEFT JOIN pagos_por_pedido pp
    ON pp.order_id = b.order_id

LEFT JOIN tipo_pago_principal tpp
    ON tpp.order_id = b.order_id

WHERE b.order_status = 'delivered';
*/
