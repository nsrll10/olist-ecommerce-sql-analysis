USE db_olist;

CREATE OR REPLACE VIEW v_order_base AS
SELECT 
    o.order_id,
    c.customer_unique_id,
    c.customer_state,
    o.order_status,
    CAST(o.order_purchase_timestamp AS DATETIME)         AS tgl_beli,
    CAST(o.order_delivered_carrier_date AS DATETIME)     AS tgl_kurir,
    CAST(o.order_delivered_customer_date AS DATETIME)    AS tgl_terima,
    CAST(o.order_estimated_delivery_date AS DATETIME)    AS tgl_estimasi,
    i.gmv,
    i.ongkir,
    r.skor_ulasan
FROM orders o
JOIN customers c 
    ON c.customer_id = o.customer_id
LEFT JOIN (
    SELECT 
        order_id,
        SUM(CAST(price AS DECIMAL(10, 2)))         AS gmv,
        SUM(CAST(freight_value AS DECIMAL(10, 2))) AS ongkir
    FROM order_items
    GROUP BY order_id
) i 
    ON i.order_id = o.order_id
LEFT JOIN (
    SELECT 
        order_id, 
        AVG(CAST(review_score AS DECIMAL(3, 2))) AS skor_ulasan
    FROM order_reviews
    GROUP BY order_id
) r 
    ON r.order_id = o.order_id;

CREATE OR REPLACE VIEW v_order_summary AS
SELECT 
    b.*,
    DATEDIFF(b.tgl_terima, b.tgl_estimasi) AS hari_telat,
    DATEDIFF(b.tgl_terima, b.tgl_beli)     AS hari_kirim,
    DATEDIFF(b.tgl_kurir, b.tgl_beli)      AS hari_proses_penjual,
    DATEDIFF(b.tgl_terima, b.tgl_kurir)    AS hari_kurir
FROM v_order_base b;

SELECT 
    COUNT(*) AS baris_view,
    COUNT(DISTINCT order_id) AS distinct_order_view,
    (SELECT COUNT(*) FROM orders) AS baris_orders
FROM v_order_summary;

SELECT 
    ROUND(SUM(gmv), 2) AS total_gmv_view,
    (SELECT ROUND(SUM(CAST(NULLIF(TRIM(price), '') AS DECIMAL(10, 2))), 2)
     FROM order_items) AS total_price_order_items
FROM v_order_summary;