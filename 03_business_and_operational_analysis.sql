-- ============================================================================
-- PROYEK  : Olist E-Commerce Data Analytics (MySQL)
-- FILE    : 03_business_and_operational_analysis.sql
-- TUJUAN  : Analisis performa transaksi, demografi, produk, logistik, kepuasan
--           pelanggan, beban ongkir, dan retensi pelanggan pada db_olist.
-- ============================================================================

USE db_olist;

-- ----------------------------------------------------------------------------
-- 1. TREN BULANAN BERBASIS WAKTU & PERTUMBUHAN MOM
-- Menampilkan pesanan, GMV, AOV, dan pertumbuhan GMV bulan ke bulan secara
-- kronologis (mengecualikan status canceled dan unavailable).
-- ----------------------------------------------------------------------------
WITH bulanan AS (
    SELECT 
        DATE_FORMAT(tgl_beli, '%Y-%m') AS bulan,
        COUNT(*) AS jml_pesanan,
        SUM(gmv) AS gmv
    FROM v_order_summary
    WHERE order_status NOT IN ('canceled', 'unavailable')
      AND gmv IS NOT NULL
      AND tgl_beli IS NOT NULL
    GROUP BY bulan
)
SELECT 
    bulan,
    jml_pesanan,
    ROUND(gmv, 0) AS gmv,
    ROUND(gmv / jml_pesanan, 2) AS aov,
    ROUND(100 * (gmv / LAG(gmv) OVER (ORDER BY bulan) - 1), 1) AS gmv_mom_pct
FROM bulanan
ORDER BY bulan ASC;


-- ----------------------------------------------------------------------------
-- 2. TREN PENDAPATAN BULANAN (PESANAN DELIVERED)
-- Menghitung total nilai produk per bulan-tahun untuk pesanan berstatus
-- delivered secara kronologis (perhatikan bulan awal/akhir jika data parsial).
-- ----------------------------------------------------------------------------
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS bulan_tahun,
    ROUND(SUM(CAST(oi.price AS DECIMAL(10, 2))), 2) AS total_pendapatan
FROM orders o
JOIN order_items oi 
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
  AND oi.price IS NOT NULL
  AND TRIM(oi.price) != ''
GROUP BY bulan_tahun
ORDER BY bulan_tahun ASC;


-- ----------------------------------------------------------------------------
-- 3. SEBARAN PESANAN BERDASARKAN KOTA & NEGARA BAGIAN PELANGGAN
-- Mengidentifikasi lokasi geografis dengan volume pesanan tertinggi.
-- ----------------------------------------------------------------------------
SELECT 
    COUNT(o.order_id) AS total_pesanan, 
    c.customer_city, 
    c.customer_state
FROM customers c
JOIN orders o 
    ON c.customer_id = o.customer_id
GROUP BY c.customer_city, c.customer_state
ORDER BY total_pesanan DESC;


-- ----------------------------------------------------------------------------
-- 4. DISTRIBUSI METODE PEMBAYARAN
-- Membandingkan frekuensi transaksi dan total nilai pembayaran tiap metode.
-- ----------------------------------------------------------------------------
SELECT 
    payment_type, 
    COUNT(DISTINCT order_id) AS jumlah_pesanan_unik,
    COUNT(*) AS jumlah_baris_pembayaran,
    ROUND(SUM(CAST(NULLIF(TRIM(payment_value), '') AS DECIMAL(10, 2))), 2) AS total_nilai_pembayaran
FROM order_payments
WHERE payment_value IS NOT NULL
  AND TRIM(payment_value) != ''
GROUP BY payment_type
ORDER BY total_nilai_pembayaran DESC;


-- ----------------------------------------------------------------------------
-- 5. KATEGORI PRODUK TERATAS BERDASARKAN GMV (PESANAN DELIVERED)
-- Memakai LEFT JOIN agar produk tanpa kategori/terjemahan tetap masuk sebagai
-- 'unknown', serta menampilkan persentase kontribusi terhadap total GMV.
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


-- ----------------------------------------------------------------------------
-- 6. DISTRIBUSI SKOR ULASAN PELANGGAN
-- Melihat sebaran jumlah ulasan per rating (review_score).
-- ----------------------------------------------------------------------------
SELECT 
    review_score, 
    COUNT(review_id) AS jumlah_ulasan
FROM order_reviews
GROUP BY review_score
ORDER BY jumlah_ulasan DESC;


-- ----------------------------------------------------------------------------
-- 7. RINGKASAN KETERLAMBATAN & LAMA PENGIRIMAN (PESANAN DELIVERED)
-- Menampilkan persentase pesanan terlambat, rata-rata lama kirim aktual,
-- rata-rata hari terlambat khusus kasus terlambat, dan rata-rata hari estimasi.
-- ----------------------------------------------------------------------------
SELECT 
    COUNT(*) AS pesanan_delivered,
    ROUND(100 * AVG(hari_telat > 0), 2) AS pct_terlambat,
    ROUND(AVG(hari_kirim), 1) AS rata2_hari_kirim,
    ROUND(AVG(CASE WHEN hari_telat > 0 THEN hari_telat END), 1) AS rata2_hari_telat_jika_terlambat,
    ROUND(AVG(DATEDIFF(tgl_estimasi, tgl_beli)), 1) AS rata2_hari_estimasi
FROM v_order_summary
WHERE order_status = 'delivered'
  AND hari_telat IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 8. DAMPAK KETERLAMBATAN PENGIRIMAN TERHADAP SKOR ULASAN
-- Membandingkan jumlah ulasan dan rata-rata review_score antara pesanan
-- terlambat (> 0 hari) dan tepat waktu/lebih cepat (<= 0 hari) pada status delivered.
-- ----------------------------------------------------------------------------
SELECT
    COUNT(r.review_id) AS jumlah_ulasan,
    ROUND(AVG(CAST(r.review_score AS DECIMAL(3, 2))), 2) AS rata_rata_score,
    CASE
        WHEN DATEDIFF(
            CAST(o.order_delivered_customer_date AS DATETIME),
            CAST(o.order_estimated_delivery_date AS DATETIME)
        ) > 0 THEN 'Terlambat'
        ELSE 'Tepat Waktu / Lebih Cepat'
    END AS status_pengiriman
FROM orders o
JOIN order_reviews r 
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND TRIM(o.order_delivered_customer_date) != ''
  AND TRIM(o.order_estimated_delivery_date) != ''
GROUP BY status_pengiriman
ORDER BY rata_rata_score DESC;


-- ----------------------------------------------------------------------------
-- 9. RASIO ONGKOS KIRIM TERTIMBANG TERHADAP HARGA PRODUK (TOP 10)
-- Menghitung rasio total ongkir dibagi total harga (bobot volume) pada pesanan
-- delivered dengan filter minimal 500 item dan LEFT JOIN kategori.
-- ----------------------------------------------------------------------------
SELECT 
    COALESCE(NULLIF(TRIM(pc.product_category_name_english), ''),
             NULLIF(TRIM(p.product_category_name), ''),
             'unknown') AS kategori,
    COUNT(*) AS jml_item,
    ROUND(SUM(CAST(oi.price AS DECIMAL(10, 2))), 0) AS gmv,
    ROUND(100 * SUM(CAST(oi.freight_value AS DECIMAL(10, 2)))
              / SUM(CAST(oi.price AS DECIMAL(10, 2))), 1) AS ongkir_vs_harga_pct
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


-- ----------------------------------------------------------------------------
-- 10. REPEAT PURCHASE RATE PELANGGAN UNIK (PESANAN DELIVERED)
-- Menggunakan customer_unique_id untuk menghitung proporsi pelanggan yang
-- melakukan lebih dari 1 pesanan delivered.
-- ----------------------------------------------------------------------------
SELECT 
    COUNT(CASE WHEN total_orders > 1 THEN 1 END) AS jumlah_pelanggan_repeat,
    COUNT(*) AS total_pelanggan_unik,
    ROUND(
        (COUNT(CASE WHEN total_orders > 1 THEN 1 END) * 100.0) / COUNT(*), 
        2
    ) AS repeat_purchase_rate_persen
FROM (
    SELECT 
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM orders o
    JOIN customers c 
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND c.customer_unique_id IS NOT NULL
      AND TRIM(c.customer_unique_id) != ''
    GROUP BY c.customer_unique_id
) AS subquery_pelanggan;

-- ============================================================================
-- PROYEK  : Olist E-Commerce Data Analytics (MySQL)
-- FILE    : 03_business_and_operational_analysis.sql
-- TUJUAN  : Analisis performa transaksi, demografi, produk, logistik, kepuasan
--           pelanggan, beban ongkir, dan retensi pelanggan pada db_olist.
-- ============================================================================

USE db_olist;

-- ----------------------------------------------------------------------------
-- 1. TREN BULANAN BERBASIS WAKTU & PERTUMBUHAN MOM
-- Menampilkan pesanan, GMV, AOV, dan pertumbuhan GMV bulan ke bulan secara
-- kronologis (mengecualikan status canceled dan unavailable).
-- ----------------------------------------------------------------------------
WITH bulanan AS (
    SELECT 
        DATE_FORMAT(tgl_beli, '%Y-%m') AS bulan,
        COUNT(*) AS jml_pesanan,
        SUM(gmv) AS gmv
    FROM v_order_summary
    WHERE order_status NOT IN ('canceled', 'unavailable')
      AND gmv IS NOT NULL
      AND tgl_beli IS NOT NULL
    GROUP BY bulan
)
SELECT 
    bulan,
    jml_pesanan,
    ROUND(gmv, 0) AS gmv,
    ROUND(gmv / jml_pesanan, 2) AS aov,
    ROUND(100 * (gmv / LAG(gmv) OVER (ORDER BY bulan) - 1), 1) AS gmv_mom_pct
FROM bulanan
ORDER BY bulan ASC;


-- ----------------------------------------------------------------------------
-- 2. TREN PENDAPATAN BULANAN (PESANAN DELIVERED)
-- Menghitung total nilai produk per bulan-tahun untuk pesanan berstatus
-- delivered secara kronologis (perhatikan bulan awal/akhir jika data parsial).
-- ----------------------------------------------------------------------------
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS bulan_tahun,
    ROUND(SUM(CAST(oi.price AS DECIMAL(10, 2))), 2) AS total_pendapatan
FROM orders o
JOIN order_items oi 
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
  AND oi.price IS NOT NULL
  AND TRIM(oi.price) != ''
GROUP BY bulan_tahun
ORDER BY bulan_tahun ASC;


-- ----------------------------------------------------------------------------
-- 3. SEBARAN PESANAN BERDASARKAN KOTA & NEGARA BAGIAN PELANGGAN
-- Mengidentifikasi lokasi geografis dengan volume pesanan tertinggi.
-- ----------------------------------------------------------------------------
SELECT 
    COUNT(o.order_id) AS total_pesanan, 
    c.customer_city, 
    c.customer_state
FROM customers c
JOIN orders o 
    ON c.customer_id = o.customer_id
GROUP BY c.customer_city, c.customer_state
ORDER BY total_pesanan DESC;


-- ----------------------------------------------------------------------------
-- 4. DISTRIBUSI METODE PEMBAYARAN
-- Membandingkan frekuensi transaksi dan total nilai pembayaran tiap metode.
-- ----------------------------------------------------------------------------
SELECT 
    payment_type, 
    COUNT(DISTINCT order_id) AS jumlah_pesanan_unik,
    COUNT(*) AS jumlah_baris_pembayaran,
    ROUND(SUM(CAST(NULLIF(TRIM(payment_value), '') AS DECIMAL(10, 2))), 2) AS total_nilai_pembayaran
FROM order_payments
WHERE payment_value IS NOT NULL
  AND TRIM(payment_value) != ''
GROUP BY payment_type
ORDER BY total_nilai_pembayaran DESC;


-- ----------------------------------------------------------------------------
-- 5. KATEGORI PRODUK TERATAS BERDASARKAN GMV (PESANAN DELIVERED)
-- Memakai LEFT JOIN agar produk tanpa kategori/terjemahan tetap masuk sebagai
-- 'unknown', serta menampilkan persentase kontribusi terhadap total GMV.
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


-- ----------------------------------------------------------------------------
-- 6. DISTRIBUSI SKOR ULASAN PELANGGAN
-- Melihat sebaran jumlah ulasan per rating (review_score).
-- ----------------------------------------------------------------------------
SELECT 
    review_score, 
    COUNT(review_id) AS jumlah_ulasan
FROM order_reviews
GROUP BY review_score
ORDER BY jumlah_ulasan DESC;


-- ----------------------------------------------------------------------------
-- 7. RINGKASAN KETERLAMBATAN & LAMA PENGIRIMAN (PESANAN DELIVERED)
-- Menampilkan persentase pesanan terlambat, rata-rata lama kirim aktual,
-- rata-rata hari terlambat khusus kasus terlambat, dan rata-rata hari estimasi.
-- ----------------------------------------------------------------------------
SELECT 
    COUNT(*) AS pesanan_delivered,
    ROUND(100 * AVG(hari_telat > 0), 2) AS pct_terlambat,
    ROUND(AVG(hari_kirim), 1) AS rata2_hari_kirim,
    ROUND(AVG(CASE WHEN hari_telat > 0 THEN hari_telat END), 1) AS rata2_hari_telat_jika_terlambat,
    ROUND(AVG(DATEDIFF(tgl_estimasi, tgl_beli)), 1) AS rata2_hari_estimasi
FROM v_order_summary
WHERE order_status = 'delivered'
  AND hari_telat IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 8. DAMPAK KETERLAMBATAN PENGIRIMAN TERHADAP SKOR ULASAN
-- Membandingkan jumlah ulasan dan rata-rata review_score antara pesanan
-- terlambat (> 0 hari) dan tepat waktu/lebih cepat (<= 0 hari) pada status delivered.
-- ----------------------------------------------------------------------------
SELECT
    COUNT(r.review_id) AS jumlah_ulasan,
    ROUND(AVG(CAST(r.review_score AS DECIMAL(3, 2))), 2) AS rata_rata_score,
    CASE
        WHEN DATEDIFF(
            CAST(o.order_delivered_customer_date AS DATETIME),
            CAST(o.order_estimated_delivery_date AS DATETIME)
        ) > 0 THEN 'Terlambat'
        ELSE 'Tepat Waktu / Lebih Cepat'
    END AS status_pengiriman
FROM orders o
JOIN order_reviews r 
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND TRIM(o.order_delivered_customer_date) != ''
  AND TRIM(o.order_estimated_delivery_date) != ''
GROUP BY status_pengiriman
ORDER BY rata_rata_score DESC;


-- ----------------------------------------------------------------------------
-- 9. RASIO ONGKOS KIRIM TERTIMBANG TERHADAP HARGA PRODUK (TOP 10)
-- Menghitung rasio total ongkir dibagi total harga (bobot volume) pada pesanan
-- delivered dengan filter minimal 500 item dan LEFT JOIN kategori.
-- ----------------------------------------------------------------------------
SELECT 
    COALESCE(NULLIF(TRIM(pc.product_category_name_english), ''),
             NULLIF(TRIM(p.product_category_name), ''),
             'unknown') AS kategori,
    COUNT(*) AS jml_item,
    ROUND(SUM(CAST(oi.price AS DECIMAL(10, 2))), 0) AS gmv,
    ROUND(100 * SUM(CAST(oi.freight_value AS DECIMAL(10, 2)))
              / SUM(CAST(oi.price AS DECIMAL(10, 2))), 1) AS ongkir_vs_harga_pct
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


-- ----------------------------------------------------------------------------
-- 10. REPEAT PURCHASE RATE PELANGGAN UNIK (PESANAN DELIVERED)
-- Menggunakan customer_unique_id untuk menghitung proporsi pelanggan yang
-- melakukan lebih dari 1 pesanan delivered.
-- ----------------------------------------------------------------------------
SELECT 
    COUNT(CASE WHEN total_orders > 1 THEN 1 END) AS jumlah_pelanggan_repeat,
    COUNT(*) AS total_pelanggan_unik,
    ROUND(
        (COUNT(CASE WHEN total_orders > 1 THEN 1 END) * 100.0) / COUNT(*), 
        2
    ) AS repeat_purchase_rate_persen
FROM (
    SELECT 
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM orders o
    JOIN customers c 
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND c.customer_unique_id IS NOT NULL
      AND TRIM(c.customer_unique_id) != ''
    GROUP BY c.customer_unique_id
) AS subquery_pelanggan;

-- 1. Gradasi keterlambatan, rata-rata skor ulasan, dan persen ulasan buruk (<= 2)
SELECT 
    CASE 
        WHEN hari_telat <= 0 THEN '1. Tepat waktu / lebih cepat'
        WHEN hari_telat <= 3 THEN '2. Telat 1-3 hari'
        WHEN hari_telat <= 7 THEN '3. Telat 4-7 hari'
        ELSE '4. Telat > 7 hari'
    END AS kelompok_keterlambatan,
    COUNT(*)                              AS jml_pesanan,
    ROUND(AVG(skor_ulasan), 2)            AS skor_rata2,
    ROUND(100 * AVG(skor_ulasan <= 2), 1) AS pct_ulasan_buruk
FROM v_order_summary
WHERE order_status = 'delivered'
  AND hari_telat IS NOT NULL
  AND skor_ulasan IS NOT NULL
GROUP BY kelompok_keterlambatan
ORDER BY kelompok_keterlambatan;

-- 2. Konsentrasi keterlambatan per state pelanggan & durasi proses penjual vs kurir
SELECT 
    customer_state,
    COUNT(*)                                AS jml_pesanan,
    ROUND(100 * AVG(hari_telat > 0), 1)     AS pct_terlambat,
    ROUND(AVG(hari_proses_penjual), 1)      AS rata2_hari_penjual,
    ROUND(AVG(hari_kurir), 1)               AS rata2_hari_kurir,
    ROUND(AVG(hari_kirim), 1)               AS rata2_hari_kirim,
    ROUND(AVG(skor_ulasan), 2)              AS skor_rata2
FROM v_order_summary
WHERE order_status = 'delivered'
  AND hari_telat IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY pct_terlambat DESC;

-- 3. Konsentrasi keterlambatan per penjual (minimal 30 pesanan delivered)
SELECT 
    sp.seller_id,
    COUNT(*)                              AS jml_pesanan,
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

-- 4. Repeat purchase rate berdasarkan pengalaman pesanan pertama (delivered)
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
    SELECT 
        customer_unique_id,
        COUNT(*) AS jml_order_delivered
    FROM urut
    GROUP BY customer_unique_id
)
SELECT 
    CASE 
        WHEN u.hari_telat > 0 THEN 'Pesanan pertama terlambat'
        ELSE 'Pesanan pertama tepat waktu'
    END AS kelompok_pesanan_pertama,
    COUNT(*)                                          AS jml_pelanggan,
    ROUND(100 * AVG(t.jml_order_delivered > 1), 2)    AS pct_repeat
FROM urut u
JOIN total_pesanan_pelanggan t
    ON t.customer_unique_id = u.customer_unique_id
WHERE u.rn = 1
GROUP BY kelompok_pesanan_pertama;

-- ----------------------------------------------------------------------------
-- 11. UJI KETAHANAN (ROBUSTNESS CHECK) PADA STATE BESAR (SP)
-- Memastikan pola penurunan skor ulasan dan kenaikan ulasan buruk (<= 2)
-- akibat keterlambatan tetap konsisten pada salah satu state bervolume besar.
-- ----------------------------------------------------------------------------
SELECT 
    CASE 
        WHEN hari_telat <= 0 THEN '1. Tepat waktu / lebih cepat'
        WHEN hari_telat <= 3 THEN '2. Telat 1-3 hari'
        WHEN hari_telat <= 7 THEN '3. Telat 4-7 hari'
        ELSE '4. Telat > 7 hari'
    END AS kelompok_keterlambatan,
    COUNT(*)                              AS jml_pesanan,
    ROUND(AVG(skor_ulasan), 2)            AS skor_rata2,
    ROUND(100 * AVG(skor_ulasan <= 2), 1) AS pct_ulasan_buruk
FROM v_order_summary
WHERE order_status = 'delivered'
  AND customer_state = 'SP'
  AND hari_telat IS NOT NULL
  AND skor_ulasan IS NOT NULL
GROUP BY kelompok_keterlambatan
ORDER BY kelompok_keterlambatan;


-- ----------------------------------------------------------------------------
-- 12. ESTIMASI SKENARIO BERSYARAT ULASAN BURUK (<= 2)
-- Membandingkan tingkat ulasan buruk antara pesanan terlambat (> 0) dan
-- tepat waktu/lebih cepat (<= 0) pada pesanan delivered ber-ulasan untuk
-- memperkirakan potensi pengurangan ulasan buruk jika keterlambatan ditekan.
-- Catatan: Bersifat ilustrasi/skenario berbasis asosiasi historis, bukan
-- klaim sebab-akibat mutlak.
-- ----------------------------------------------------------------------------
WITH ringkasan_status AS (
    SELECT 
        CASE WHEN hari_telat > 0 THEN 'terlambat' ELSE 'tepat_waktu' END AS status_kirim,
        COUNT(*) AS jml_pesanan,
        AVG(CASE WHEN skor_ulasan <= 2 THEN 1.0 ELSE 0.0 END) AS prop_buruk
    FROM v_order_summary
    WHERE order_status = 'delivered'
      AND hari_telat IS NOT NULL
      AND skor_ulasan IS NOT NULL
    GROUP BY CASE WHEN hari_telat > 0 THEN 'terlambat' ELSE 'tepat_waktu' END
)
SELECT 
    MAX(CASE WHEN status_kirim = 'terlambat' THEN jml_pesanan END) AS pesanan_terlambat_berulasan,
    ROUND(100 * MAX(CASE WHEN status_kirim = 'terlambat' THEN prop_buruk END), 1) AS pct_buruk_terlambat,
    ROUND(100 * MAX(CASE WHEN status_kirim = 'tepat_waktu' THEN prop_buruk END), 1) AS pct_buruk_tepat_waktu,
    ROUND(
        MAX(CASE WHEN status_kirim = 'terlambat' THEN jml_pesanan END) *
        GREATEST(
            0,
            MAX(CASE WHEN status_kirim = 'terlambat' THEN prop_buruk END) -
            MAX(CASE WHEN status_kirim = 'tepat_waktu' THEN prop_buruk END)
        ),
        0
    ) AS estimasi_ulasan_buruk_potensial_terhindari
FROM ringkasan_status;

-- ----------------------------------------------------------------------------
-- 1. Gradasi keterlambatan, rata-rata skor ulasan, dan persen ulasan buruk (<= 2)
SELECT 
    CASE 
        WHEN hari_telat <= 0 THEN '1. Tepat waktu / lebih cepat'
        WHEN hari_telat <= 3 THEN '2. Telat 1-3 hari'
        WHEN hari_telat <= 7 THEN '3. Telat 4-7 hari'
        ELSE '4. Telat > 7 hari'
    END AS kelompok_keterlambatan,
    COUNT(*)                              AS jml_pesanan,
    ROUND(AVG(skor_ulasan), 2)            AS skor_rata2,
    ROUND(100 * AVG(skor_ulasan <= 2), 1) AS pct_ulasan_buruk
FROM v_order_summary
WHERE order_status = 'delivered'
  AND hari_telat IS NOT NULL
  AND skor_ulasan IS NOT NULL
GROUP BY kelompok_keterlambatan
ORDER BY kelompok_keterlambatan;

-- 2. Konsentrasi keterlambatan per state pelanggan & durasi proses penjual vs kurir
SELECT 
    customer_state,
    COUNT(*)                                AS jml_pesanan,
    ROUND(100 * AVG(hari_telat > 0), 1)     AS pct_terlambat,
    ROUND(AVG(hari_proses_penjual), 1)      AS rata2_hari_penjual,
    ROUND(AVG(hari_kurir), 1)               AS rata2_hari_kurir,
    ROUND(AVG(hari_kirim), 1)               AS rata2_hari_kirim,
    ROUND(AVG(skor_ulasan), 2)              AS skor_rata2
FROM v_order_summary
WHERE order_status = 'delivered'
  AND hari_telat IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY pct_terlambat DESC;

-- 3. Konsentrasi keterlambatan per penjual (minimal 30 pesanan delivered)
SELECT 
    sp.seller_id,
    COUNT(*)                              AS jml_pesanan,
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

-- 4. Repeat purchase rate berdasarkan pengalaman pesanan pertama (delivered)
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
    SELECT 
        customer_unique_id,
        COUNT(*) AS jml_order_delivered
    FROM urut
    GROUP BY customer_unique_id
)
SELECT 
    CASE 
        WHEN u.hari_telat > 0 THEN 'Pesanan pertama terlambat'
        ELSE 'Pesanan pertama tepat waktu'
    END AS kelompok_pesanan_pertama,
    COUNT(*)                                          AS jml_pelanggan,
    ROUND(100 * AVG(t.jml_order_delivered > 1), 2)    AS pct_repeat
FROM urut u
JOIN total_pesanan_pelanggan t
    ON t.customer_unique_id = u.customer_unique_id
WHERE u.rn = 1
GROUP BY kelompok_pesanan_pertama;

