-- ============================================================================
-- PROYEK  : Olist E-Commerce Data Analytics (MySQL)
-- FILE    : 01_data_cleaning_and_audit.sql
-- TUJUAN  : Audit kualitas data (missing values & anomali harga) serta validasi
--           distribusi pesanan dan nilai produk berdasarkan status pesanan.
-- ============================================================================

USE db_olist;

-- ----------------------------------------------------------------------------
-- 1. AUDIT MISSING VALUES & ANOMALI HARGA PADA TABEL ORDER_ITEMS
-- Tujuan : Memastikan kolom price (bertipe TEXT) bebas dari NULL, string kosong,
--          maupun nilai <= 0 sebelum digunakan dalam perhitungan pendapatan.
-- Hasil  : 0 missing/kosong dan 0 harga <= 0 dari seluruh baris order_items.
-- ----------------------------------------------------------------------------
SELECT 
    COUNT(*) AS total_baris,
    SUM(CASE WHEN price IS NULL OR TRIM(price) = '' THEN 1 ELSE 0 END) AS missing_atau_kosong,
    SUM(CASE WHEN CAST(price AS DECIMAL(10, 2)) <= 0 THEN 1 ELSE 0 END) AS harga_nol_atau_negatif
FROM order_items;


-- ----------------------------------------------------------------------------
-- 2. DISTRIBUSI JUMLAH PESANAN BERDASARKAN STATUS (TABEL ORDERS)
-- Tujuan : Melihat komposisi status seluruh pesanan di database.
-- ----------------------------------------------------------------------------
SELECT 
    order_status, 
    COUNT(order_id) AS jumlah_pesanan
FROM orders
GROUP BY order_status
ORDER BY jumlah_pesanan DESC;


-- ----------------------------------------------------------------------------
-- 3. VALIDASI NILAI PRODUK BERDASARKAN STATUS PESANAN
-- Tujuan : Memisahkan nilai produk yang benar-benar terealisasi (delivered)
--          dari pesanan yang masih berjalan atau batal (canceled/unavailable).
-- Catatan: Menggunakan COUNT(DISTINCT o.order_id) agar pesanan multi-item
--          tidak terhitung ganda.
-- ----------------------------------------------------------------------------
SELECT 
    o.order_status, 
    COUNT(DISTINCT o.order_id) AS jumlah_pesanan, 
    ROUND(SUM(CAST(oi.price AS DECIMAL(10, 2))), 2) AS total_nilai_produk
FROM orders o
JOIN order_items oi 
    ON o.order_id = oi.order_id
GROUP BY o.order_status
ORDER BY total_nilai_produk DESC;

-- ----------------------------------------------------------------------------
-- 4. AUDIT KELENGKAPAN PESANAN PER BULAN (ORDERS)
-- Mengidentifikasi bulan dengan volume pesanan terlalu sedikit/parsial
-- (awal atau akhir periode) dibanding bulan operasional penuh.
-- ----------------------------------------------------------------------------
SELECT 
    LEFT(TRIM(order_purchase_timestamp), 7) AS bulan,
    COUNT(*) AS jumlah_pesanan
FROM orders
WHERE order_purchase_timestamp IS NOT NULL
  AND TRIM(order_purchase_timestamp) != ''
GROUP BY bulan
ORDER BY bulan ASC;


-- ----------------------------------------------------------------------------
-- 5. AUDIT PESANAN DELIVERED TANPA TANGGAL TERIMA
-- Menghitung pesanan berstatus delivered yang tidak memiliki tanggal terima
-- (order_delivered_customer_date) sehingga keterlambatannya tidak dihitung.
-- ----------------------------------------------------------------------------
SELECT 
    COUNT(*) AS pesanan_delivered_tanpa_tgl_terima
FROM orders
WHERE order_status = 'delivered'
  AND (order_delivered_customer_date IS NULL OR TRIM(order_delivered_customer_date) = '');


-- ----------------------------------------------------------------------------
-- 6. AUDIT PESANAN DENGAN LEBIH DARI SATU ULASAN (ORDER_REVIEWS)
-- Mendeteksi order_id yang muncul lebih dari satu kali pada order_reviews.
-- ----------------------------------------------------------------------------
SELECT 
    COUNT(*) AS jumlah_order_dengan_ulasan_ganda
FROM (
    SELECT order_id
    FROM order_reviews
    WHERE order_id IS NOT NULL AND TRIM(order_id) != ''
    GROUP BY order_id
    HAVING COUNT(*) > 1
) AS dup_reviews;


-- ----------------------------------------------------------------------------
-- 7. AUDIT PRODUK TANPA KATEGORI & KATEGORI BELUM DITERJEMAHKAN
-- Memeriksa produk yang tidak memiliki kategori atau kategori yang belum
-- terdaftar pada product_category_name_translation.
-- ----------------------------------------------------------------------------
SELECT 
    COUNT(*) AS produk_tanpa_kategori
FROM products
WHERE product_category_name IS NULL
   OR TRIM(product_category_name) = '';

SELECT DISTINCT 
    p.product_category_name AS kategori_belum_terjemahan
FROM products p
LEFT JOIN product_category_name_translation t
    ON t.product_category_name = p.product_category_name
WHERE t.product_category_name IS NULL
  AND p.product_category_name IS NOT NULL
  AND TRIM(p.product_category_name) != '';
  
  SELECT 
    COUNT(*) AS total_baris_orders,
    SUM(CASE WHEN DATE_FORMAT(CAST(NULLIF(TRIM(order_purchase_timestamp), '') AS DATETIME), '%Y-%m') IS NULL THEN 1 ELSE 0 END) AS baris_bulan_null,
    SUM(CASE WHEN DATE_FORMAT(CAST(NULLIF(TRIM(order_purchase_timestamp), '') AS DATETIME), '%Y-%m') IS NOT NULL THEN 1 ELSE 0 END) AS baris_bulan_valid
FROM orders;

SELECT 
    DATE_FORMAT(CAST(NULLIF(TRIM(order_purchase_timestamp), '') AS DATETIME), '%Y-%m') AS bulan,
    COUNT(*) AS jumlah_pesanan
FROM orders
GROUP BY bulan
HAVING bulan IS NOT NULL
ORDER BY bulan ASC;