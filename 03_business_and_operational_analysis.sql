-- ============================================================================
-- PROYEK  : Olist E-Commerce Data Analytics (MySQL 8.0)
-- FILE    : 03_business_and_operational_analysis.sql
-- TUJUAN  : Analisis performa transaksi, produk, logistik, kepuasan pelanggan,
--           konsentrasi keterlambatan, beban ongkir, dan retensi pelanggan.
-- PRASYARAT: Jalankan 01_data_cleaning_and_audit.sql dan
--           02_view_and_reconciliation.sql lebih dulu (view v_order_summary).
-- CAKUPAN : Semua metrik memakai pesanan berstatus 'delivered' kecuali
--           dinyatakan lain pada komentar kueri.
-- ============================================================================

USE db_olist;


-- ############################################################################
-- A. PROFIL BISNIS
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 1. TREN BULANAN: PESANAN, GMV, AOV, DAN PERTUMBUHAN MoM (DELIVERED)
-- ----------------------------------------------------------------------------
WITH bulanan AS (
    SELECT
        DATE_FORMAT(tgl_beli, '%Y-%m') AS bulan,
        COUNT(*)                       AS jml_pesanan,
        SUM(gmv)                       AS gmv
    FROM v_order_summary
    WHERE order_status = 'delivered'
      AND gmv IS NOT NULL
      AND tgl_beli >= '2017-01-01'
      AND tgl_beli <  '2018-09-01'
    GROUP BY bulan
)
SELECT
    bulan,
    jml_pesanan,
    ROUND(gmv, 0)                                                   AS gmv,
    ROUND(gmv / jml_pesanan, 2)                                     AS aov,
    ROUND(100 * (gmv / LAG(gmv) OVER (ORDER BY bulan) - 1), 1)      AS gmv_mom_pct
FROM bulanan
ORDER BY bulan;


-- ----------------------------------------------------------------------------
-- 2. SEBARAN PESANAN DAN GMV PER STATE PELANGGAN (DELIVERED)
-- ----------------------------------------------------------------------------
SELECT
    customer_state,
    COUNT(*)                                          AS jml_pesanan,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_pesanan,
    ROUND(SUM(gmv), 0)                                AS gmv_total,
    ROUND(100 * SUM(gmv) / SUM(SUM(gmv)) OVER (), 1)  AS pct_gmv,
    ROUND(SUM(gmv) / COUNT(gmv), 2)                   AS aov
FROM v_order_summary
WHERE order_status = 'delivered'
GROUP BY customer_state
ORDER BY gmv_total DESC;


-- ----------------------------------------------------------------------------
-- 3. DISTRIBUSI METODE PEMBAYARAN (PESANAN DELIVERED)
-- ----------------------------------------------------------------------------
SELECT
    p.payment_type,
    COUNT(DISTINCT p.order_id)                                     AS jml_pesanan_unik,
    ROUND(100 * COUNT(DISTINCT p.order_id)
          / (SELECT COUNT(*) FROM orders WHERE order_status = 'delivered'), 1)
                                                                   AS pct_dari_pesanan_delivered,
    COUNT(*)                                                       AS jml_baris_pembayaran,
    ROUND(SUM(CAST(NULLIF(TRIM(p.payment_value), '') AS DECIMAL(10, 2))), 2)
                                                                   AS total_nilai_pembayaran
FROM order_payments p
JOIN orders o
    ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY p.payment_type
ORDER BY total_nilai_pembayaran DESC;


-- ----------------------------------------------------------------------------
-- 4. KATEGORI PRODUK TERATAS BERDASARKAN GMV (DELIVERED)
-- ----------------------------------------------------------------------------
SELECT
    COALESCE(NULLIF(TRIM(pc.product_category_name_english), ''),
             NULLIF(TRIM(p.product_category_name), ''),
             'unknown')                                                  AS kategori,
    COUNT(*)                                                             AS jml_item,
    ROUND(SUM(CAST(oi.price AS DECIMAL(10, 2))), 0)                      AS gmv,
    ROUND(100 * SUM(CAST(oi.price AS DECIMAL(10, 2)))
              / SUM(SUM(CAST(oi.price AS DECIMAL(10, 2)))) OVER (), 1)   AS pct_gmv
FROM order_items oi
JOIN orders o
    ON o.order_id = oi.order_id
LEFT JOIN products p
    ON p.product_id = oi.product_id
LEFT JOIN product_category_name_translation pc
    ON pc.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
  AND oi.price IS NOT NULL
  AND TRIM(oi.price) != ''
GROUP BY kategori
ORDER BY gmv DESC
LIMIT 10;

-- 4b. Cek rekonsiliasi: GMV delivered dari view harus sama dengan dari order_items
SELECT
    ROUND(SUM(gmv), 2) AS gmv_delivered_view,
    (SELECT ROUND(SUM(CAST(oi.price AS DECIMAL(10, 2))), 2)
       FROM order_items oi
       JOIN orders o ON o.order_id = oi.order_id
      WHERE o.order_status = 'delivered') AS gmv_delivered_order_items
FROM v_order_summary
WHERE order_status = 'delivered';


-- ----------------------------------------------------------------------------
-- 5. BEBAN ONGKOS KIRIM TERHADAP HARGA PRODUK (DELIVERED)
-- ----------------------------------------------------------------------------

-- 5a. Rasio tertimbang keseluruhan
SELECT
    ROUND(SUM(ongkir), 0)                  AS total_ongkir,
    ROUND(SUM(gmv), 0)                     AS total_gmv,
    ROUND(100 * SUM(ongkir) / SUM(gmv), 2) AS ongkir_vs_harga_pct
FROM v_order_summary
WHERE order_status = 'delivered'
  AND gmv > 0;

-- 5b. Top 10 kategori dengan rasio ongkir tertinggi (minimal 500 item agar
SELECT
    COALESCE(NULLIF(TRIM(pc.product_category_name_english), ''),
             NULLIF(TRIM(p.product_category_name), ''),
             'unknown')                                               AS kategori,
    COUNT(*)                                                          AS jml_item,
    ROUND(SUM(CAST(oi.price AS DECIMAL(10, 2))), 0)                   AS gmv,
    ROUND(100 * SUM(CAST(oi.freight_value AS DECIMAL(10, 2)))
              / SUM(CAST(oi.price AS DECIMAL(10, 2))), 1)             AS ongkir_vs_harga_pct
FROM order_items oi
JOIN orders o
    ON o.order_id = oi.order_id
LEFT JOIN products p
    ON p.product_id = oi.product_id
LEFT JOIN product_category_name_translation pc
    ON pc.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
  AND oi.price IS NOT NULL
  AND oi.freight_value IS NOT NULL
  AND TRIM(oi.price) != ''
  AND TRIM(oi.freight_value) != ''
  AND CAST(oi.price AS DECIMAL(10, 2)) > 0
GROUP BY kategori
HAVING COUNT(*) >= 500
ORDER BY ongkir_vs_harga_pct DESC
LIMIT 10;

-- 5c. Rasio ongkir pada 10 kategori ber-GMV terbesar (kategori yang paling
SELECT
    COALESCE(NULLIF(TRIM(pc.product_category_name_english), ''),
             NULLIF(TRIM(p.product_category_name), ''),
             'unknown')                                               AS kategori,
    COUNT(*)                                                          AS jml_item,
    ROUND(SUM(CAST(oi.price AS DECIMAL(10, 2))), 0)                   AS gmv,
    ROUND(100 * SUM(CAST(oi.freight_value AS DECIMAL(10, 2)))
              / SUM(CAST(oi.price AS DECIMAL(10, 2))), 1)             AS ongkir_vs_harga_pct
FROM order_items oi
JOIN orders o
    ON o.order_id = oi.order_id
LEFT JOIN products p
    ON p.product_id = oi.product_id
LEFT JOIN product_category_name_translation pc
    ON pc.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
  AND oi.price IS NOT NULL
  AND oi.freight_value IS NOT NULL
  AND TRIM(oi.price) != ''
  AND TRIM(oi.freight_value) != ''
  AND CAST(oi.price AS DECIMAL(10, 2)) > 0
GROUP BY kategori
ORDER BY gmv DESC
LIMIT 10;


-- ############################################################################
-- B. KETERLAMBATAN PENGIRIMAN DAN KEPUASAN PELANGGAN
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 6. RINGKASAN KETERLAMBATAN DAN LAMA PENGIRIMAN (DELIVERED)
-- ----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                       AS pesanan_delivered,
    ROUND(100 * AVG(hari_telat > 0), 2)                            AS pct_terlambat,
    ROUND(AVG(hari_kirim), 1)                                      AS rata2_hari_kirim,
    ROUND(AVG(CASE WHEN hari_telat > 0 THEN hari_telat END), 1)    AS rata2_hari_telat_jika_terlambat,
    ROUND(AVG(DATEDIFF(tgl_estimasi, tgl_beli)), 1)                AS rata2_hari_estimasi,
    ROUND(AVG(hari_telat), 2)                                      AS rata2_selisih_vs_estimasi
FROM v_order_summary
WHERE order_status = 'delivered'
  AND hari_telat IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 7. DISTRIBUSI SKOR ULASAN (DELIVERED, SATUAN: ULASAN)
-- ----------------------------------------------------------------------------
SELECT
    CAST(r.review_score AS UNSIGNED)                              AS skor,
    COUNT(*)                                                      AS jml_ulasan,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)              AS pct_ulasan
FROM order_reviews r
JOIN orders o
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND NULLIF(TRIM(r.review_score), '') IS NOT NULL
GROUP BY skor
ORDER BY skor;

-- 7b. Rekonsiliasi definisi Bad Review % (skor <= 2).
SELECT
    ROUND(100 * AVG(CAST(r.review_score AS UNSIGNED) <= 2), 2) AS pct_buruk_per_ulasan,
    (SELECT ROUND(100 * AVG(skor_ulasan <= 2), 2)
       FROM v_order_summary
      WHERE order_status = 'delivered'
        AND skor_ulasan IS NOT NULL)                           AS pct_buruk_per_pesanan
FROM order_reviews r
JOIN orders o
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND NULLIF(TRIM(r.review_score), '') IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 8. GRADASI KETERLAMBATAN, SKOR ULASAN, DAN ULASAN BURUK (DELIVERED)
-- ----------------------------------------------------------------------------
SELECT
    CASE
        WHEN hari_telat <= 0 THEN '1. Tepat waktu / lebih cepat'
        WHEN hari_telat <= 3 THEN '2. Telat 1-3 hari'
        WHEN hari_telat <= 7 THEN '3. Telat 4-7 hari'
        ELSE '4. Telat > 7 hari'
    END                                                              AS kelompok_keterlambatan,
    COUNT(*)                                                         AS jml_pesanan,
    ROUND(AVG(skor_ulasan), 2)                                       AS skor_rata2,
    SUM(skor_ulasan <= 2)                                            AS jml_ulasan_buruk,
    ROUND(100 * AVG(skor_ulasan <= 2), 1)                            AS pct_ulasan_buruk,
    ROUND(100 * SUM(skor_ulasan <= 2)
              / SUM(SUM(skor_ulasan <= 2)) OVER (), 1)               AS pct_dari_semua_ulasan_buruk
FROM v_order_summary
WHERE order_status = 'delivered'
  AND hari_telat IS NOT NULL
  AND skor_ulasan IS NOT NULL
GROUP BY kelompok_keterlambatan
ORDER BY kelompok_keterlambatan;


-- ----------------------------------------------------------------------------
-- 9. SKENARIO BERSYARAT: ULASAN BURUK YANG BISA DIHINDARI
-- ----------------------------------------------------------------------------
WITH ringkasan AS (
    SELECT
        CASE WHEN hari_telat > 0 THEN 'terlambat' ELSE 'tepat_waktu' END AS status_kirim,
        COUNT(*)                                                       AS jml_pesanan,
        SUM(skor_ulasan <= 2)                                          AS jml_buruk,
        AVG(skor_ulasan <= 2)                                          AS prop_buruk,
        AVG(skor_ulasan)                                               AS skor
    FROM v_order_summary
    WHERE order_status = 'delivered'
      AND hari_telat IS NOT NULL
      AND skor_ulasan IS NOT NULL
    GROUP BY status_kirim
)
SELECT
    MAX(CASE WHEN status_kirim = 'terlambat'   THEN jml_pesanan END)             AS pesanan_terlambat_berulasan,
    ROUND(MAX(CASE WHEN status_kirim = 'terlambat'   THEN skor END), 2)          AS skor_terlambat,
    ROUND(MAX(CASE WHEN status_kirim = 'tepat_waktu' THEN skor END), 2)          AS skor_tepat_waktu,
    ROUND(100 * MAX(CASE WHEN status_kirim = 'terlambat'   THEN prop_buruk END), 1) AS pct_buruk_terlambat,
    ROUND(100 * MAX(CASE WHEN status_kirim = 'tepat_waktu' THEN prop_buruk END), 1) AS pct_buruk_tepat_waktu,
    ROUND(
        MAX(CASE WHEN status_kirim = 'terlambat' THEN jml_pesanan END) *
        GREATEST(0,
                 MAX(CASE WHEN status_kirim = 'terlambat'   THEN prop_buruk END) -
                 MAX(CASE WHEN status_kirim = 'tepat_waktu' THEN prop_buruk END)),
        0)                                                                       AS estimasi_buruk_terhindari,
    ROUND(100 * MAX(CASE WHEN status_kirim = 'terlambat' THEN jml_buruk END)
              / SUM(jml_buruk), 1)                                               AS pct_ulasan_buruk_dari_pesanan_terlambat
FROM ringkasan;


-- ----------------------------------------------------------------------------
-- 10. UJI KETAHANAN PADA TIGA STATE TERBESAR (SP, RJ, MG)
-- ----------------------------------------------------------------------------
SELECT
    customer_state,
    CASE
        WHEN hari_telat <= 0 THEN '1. Tepat waktu / lebih cepat'
        WHEN hari_telat <= 3 THEN '2. Telat 1-3 hari'
        WHEN hari_telat <= 7 THEN '3. Telat 4-7 hari'
        ELSE '4. Telat > 7 hari'
    END                                         AS kelompok_keterlambatan,
    COUNT(*)                                    AS jml_pesanan,
    ROUND(AVG(skor_ulasan), 2)                  AS skor_rata2,
    ROUND(100 * AVG(skor_ulasan <= 2), 1)       AS pct_ulasan_buruk
FROM v_order_summary
WHERE order_status = 'delivered'
  AND customer_state IN ('SP', 'RJ', 'MG')
  AND hari_telat IS NOT NULL
  AND skor_ulasan IS NOT NULL
GROUP BY customer_state, kelompok_keterlambatan
ORDER BY customer_state, kelompok_keterlambatan;


-- ############################################################################
-- C. KONSENTRASI KETERLAMBATAN (RUTE DAN PENJUAL)
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 11. KETERLAMBATAN PER STATE: PERSEN, KONTRIBUSI ABSOLUT, DAN PENYEBAB
-- ----------------------------------------------------------------------------
WITH per_state AS (
    SELECT
        customer_state,
        COUNT(*)                                AS jml_pesanan,
        SUM(hari_telat > 0)                     AS jml_telat,
        ROUND(100 * AVG(hari_telat > 0), 1)     AS pct_terlambat,
        ROUND(AVG(hari_proses_penjual), 1)      AS rata2_hari_penjual,
        ROUND(AVG(hari_kurir), 1)               AS rata2_hari_kurir,
        ROUND(AVG(hari_kirim), 1)               AS rata2_hari_kirim,
        ROUND(AVG(skor_ulasan), 2)              AS skor_rata2
    FROM v_order_summary
    WHERE order_status = 'delivered'
      AND hari_telat IS NOT NULL
    GROUP BY customer_state
)
SELECT
    s.*,
    ROUND(100 * s.jml_telat / SUM(s.jml_telat) OVER (), 1)  AS pct_dari_semua_telat,
    ROUND(100 * SUM(s.jml_telat) OVER (ORDER BY s.jml_telat DESC, s.customer_state)
              / SUM(s.jml_telat) OVER (), 1)                 AS pct_kumulatif
FROM per_state s
ORDER BY s.jml_telat DESC, s.customer_state;


-- ----------------------------------------------------------------------------
-- 12a. PENJUAL DENGAN PERSEN TERLAMBAT TERTINGGI (MINIMAL 30 PESANAN DELIVERED)
-- ----------------------------------------------------------------------------
SELECT
    sp.seller_id,
    COUNT(*)                              AS jml_pesanan,
    SUM(v.hari_telat > 0)                 AS jml_telat,
    ROUND(100 * AVG(v.hari_telat > 0), 1) AS pct_terlambat,
    ROUND(AVG(v.hari_proses_penjual), 1)  AS rata2_hari_penjual,
    ROUND(AVG(v.hari_kurir), 1)           AS rata2_hari_kurir
FROM v_order_summary v
JOIN (
    SELECT DISTINCT order_id, seller_id
    FROM order_items
    WHERE seller_id IS NOT NULL AND TRIM(seller_id) != ''
) sp
    ON sp.order_id = v.order_id
WHERE v.order_status = 'delivered'
  AND v.hari_telat IS NOT NULL
GROUP BY sp.seller_id
HAVING COUNT(*) >= 30
ORDER BY pct_terlambat DESC
LIMIT 20;

-- 12b. Pareto penjual: berapa persen keterlambatan berasal dari N penjual
WITH per_penjual AS (
    SELECT
        sp.seller_id,
        COUNT(*)              AS jml_pesanan,
        SUM(v.hari_telat > 0) AS jml_telat
    FROM v_order_summary v
    JOIN (
        SELECT DISTINCT order_id, seller_id
        FROM order_items
        WHERE seller_id IS NOT NULL AND TRIM(seller_id) != ''
    ) sp
        ON sp.order_id = v.order_id
    WHERE v.order_status = 'delivered'
      AND v.hari_telat IS NOT NULL
    GROUP BY sp.seller_id
),
urut AS (
    SELECT
        seller_id,
        jml_pesanan,
        jml_telat,
        ROW_NUMBER() OVER (ORDER BY jml_telat DESC, seller_id) AS peringkat,
        SUM(jml_telat)   OVER (ORDER BY jml_telat DESC, seller_id) AS telat_kumulatif,
        SUM(jml_pesanan) OVER (ORDER BY jml_telat DESC, seller_id) AS pesanan_kumulatif
    FROM per_penjual
)
SELECT
    peringkat                                                   AS top_n_penjual,
    (SELECT COUNT(*) FROM per_penjual)                          AS total_penjual,
    telat_kumulatif,
    ROUND(100 * telat_kumulatif   / (SELECT SUM(jml_telat)   FROM per_penjual), 1) AS pct_dari_semua_telat,
    ROUND(100 * pesanan_kumulatif / (SELECT SUM(jml_pesanan) FROM per_penjual), 1) AS pct_dari_semua_pesanan
FROM urut
WHERE peringkat IN (10, 50, 100, 200, 500);


-- ############################################################################
-- D. RETENSI PELANGGAN
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 13. REPEAT PURCHASE RATE (PELANGGAN UNIK, PESANAN DELIVERED)
-- ----------------------------------------------------------------------------
SELECT
    SUM(total_orders > 1)                          AS jumlah_pelanggan_repeat,
    COUNT(*)                                       AS total_pelanggan_unik,
    ROUND(100 * AVG(total_orders > 1), 2)          AS repeat_purchase_rate_persen
FROM (
    SELECT customer_unique_id, COUNT(*) AS total_orders
    FROM v_order_summary
    WHERE order_status = 'delivered'
      AND customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id
) t;


-- ----------------------------------------------------------------------------
-- 14. REPEAT PURCHASE MENURUT PENGALAMAN PESANAN PERTAMA (DELIVERED)
-- ----------------------------------------------------------------------------
WITH urut AS (
    SELECT
        customer_unique_id,
        hari_telat,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY tgl_beli ASC, order_id ASC
        ) AS rn
    FROM v_order_summary
    WHERE order_status = 'delivered'
      AND hari_telat IS NOT NULL
      AND tgl_beli IS NOT NULL
      AND customer_unique_id IS NOT NULL
),
total_pesanan_pelanggan AS (
    SELECT customer_unique_id, COUNT(*) AS jml_order_delivered
    FROM urut
    GROUP BY customer_unique_id
)
SELECT
    CASE
        WHEN u.hari_telat > 0 THEN 'Pesanan pertama terlambat'
        ELSE 'Pesanan pertama tepat waktu'
    END                                              AS kelompok_pesanan_pertama,
    COUNT(*)                                         AS jml_pelanggan,
    SUM(t.jml_order_delivered > 1)                   AS jml_pelanggan_repeat,
    ROUND(100 * AVG(t.jml_order_delivered > 1), 2)   AS pct_repeat
FROM urut u
JOIN total_pesanan_pelanggan t
    ON t.customer_unique_id = u.customer_unique_id
WHERE u.rn = 1
GROUP BY kelompok_pesanan_pertama;
