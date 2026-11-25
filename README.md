# Olist E-Commerce End-to-End Analytics (MySQL & Power BI)

Proyek analisis data end-to-end atas dataset e-commerce publik **Olist** (`db_olist`), menggabungkan **MySQL** (audit kualitas data, validasi nilai transaksi per status pesanan, pembangunan *view* dan rekonsiliasi data, performa logistik, gradasi dampak keterlambatan pengiriman terhadap ulasan pelanggan, analisis rute/`state` dan penjual, rasio ongkos kirim tertimbang terhadap harga produk, serta tingkat pembelian ulang) dengan **Power BI** (pemodelan data bintang, penanganan *cross-filtering* antar-granularitas, dan *dashboard* interaktif 16:9 berbasis *Delivered Orders Scope*).

## Pertanyaan Bisnis Utama
Apakah keterlambatan pengiriman menurunkan kepuasan pelanggan (skor ulasan dan proporsi ulasan buruk), serta bagaimana pengaruhnya terhadap tingkat pembelian ulang (*repeat purchase rate*) dan keputusan operasional pada transaksi *delivered* di platform **Olist**?

## Ringkasan Eksekutif
Keterlambatan pengiriman memang terjadi pada sebagian kecil pesanan *delivered* (`6.77%` dari `96,470` pesanan bertanggal valid; `6,534` pesanan terlambat), tetapi dampaknya terhadap kepuasan pelanggan sangat tajam—rata-rata skor ulasan turun dari **`4.29`** (tepat waktu/lebih cepat) menjadi **`2.27`** (terlambat), sementara ulasan buruk (`<= 2`) melonjak hingga **`62.4%`** pada pesanan terlambat ber-ulasan dibanding **`9.2%`** pada pesanan tepat waktu (dengan pola serupa pada *state* `SP` dan skenario potensi pengurangan hingga **`3,390`** ulasan buruk jika keterlambatan ditekan), sekaligus berkaitan dengan *repeat purchase rate* yang masih rendah (`3.00%` secara keseluruhan; `3.04%` pada pesanan pertama tepat waktu vs. `2.52%` pada pesanan pertama terlambat). Oleh karena itu, perbaikan operasional sebaiknya diprioritaskan pada rute/*state* dan penjual dengan tingkat keterlambatan tinggi serta skema ongkir/bundling yang lebih relevan bagi pelanggan.

---

## Sumber & Cakupan Data

- **Sumber Data:** Dataset publik [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) di **Kaggle** (data mentah tidak disertakan di repositori ini).
- **Cakupan Analisis:** Seluruh metrik pendapatan, pengiriman, rasio ongkir, ulasan, dan *repeat purchase* difokuskan pada pesanan berstatus `delivered` dengan validasi nilai/tanggal yang sesuai, sementara status non-*delivered* dianalisis pada tahap audit untuk mencegah overestimasi realisasi.

---

## Ringkasan KPI Utama

| KPI / Metrik | Temuan Utama | Catatan Cakupan |
| :--- | :--- | :--- |
| **Delivered GMV** | `R$ 13,221,498.11` (`96,478` pesanan) | Cakupan pesanan `delivered` (`Year Month = All`) pada *dashboard* Power BI dan validasi *delivered* (`BRL`) |
| **Avg Review Score** | **`4.16`** | Rata-rata skor ulasan (`1–5`) pada cakupan pesanan `delivered` |
| **Selisih Waktu Pengiriman vs. Estimasi** | Rata-rata **`-11.88` hari** (`89,936` tepat waktu/lebih cepat vs. `6,534` terlambat dari `96,470` pesanan) | Selisih `DATEDIFF` aktual dikurangi estimasi pada pesanan `delivered` |
| **Skor Ulasan vs. Ketepatan Waktu** | **`4.29`** (tepat waktu/lebih cepat, `89,943` ulasan) vs. **`2.27`** (terlambat, `6,409` ulasan) | Pesanan `delivered` yang terhubung dengan `order_reviews` |
| **Late Delivery % & Bad Review %** | **`6.77%`** terlambat (`Late Delivery %`) & **`13.44%`** ulasan buruk (`Bad Review %`) | Ringkasan metrik risiko operasional dan ulasan pada cakupan pesanan `delivered` |
| **Weighted Freight Ratio** | **`16.63%`** keseluruhan (`135.49%` tertinggi pada `dvds_blu_ray` di analisis kategori rasio ongkir) | Rasio ongkos kirim tertimbang terhadap nilai produk (`delivered`, `BRL`) |
| **Repeat Purchase Rate** | **`3.00%`** (`2,801` pelanggan repeat dari `93,358` pelanggan unik) | Berdasarkan `customer_unique_id` pada pesanan berstatus `delivered` |

![Olist E-Commerce Performance Dashboard](olist_dashboard.png)

---

## Temuan Utama & Rekomendasi Bisnis

### 1. Audit Kualitas Data, Validasi Status & Metode Pembayaran (`01_data_cleaning_and_audit.sql` & `03_business_and_operational_analysis.sql`)
- **Integritas harga `order_items`:** Pemeriksaan `price` (bertipe teks) menemukan `0` nilai `NULL`/kosong dan `0` nilai `<= 0`, sehingga kolom harga layak dipakai untuk agregasi finansial.
- **Pemisahan status pesanan:** Nilai transaksi tidak hanya berada pada status `delivered` (`R$ 13,221,498.11`), tetapi juga muncul pada status non-*delivered* seperti `shipped`, `canceled`, `invoiced`, dan `processing`. Memisahkan `delivered` mencegah overestimasi pendapatan terealisasi.
- **Distribusi metode pembayaran (`COUNT(DISTINCT order_id)`):** Pembayaran didominasi `credit_card` (`76,505` pesanan unik dari `76,795` baris pembayaran; `R$ 12,542,084.19`) dan `boleto` (`19,784` pesanan unik dan `19,784` baris pembayaran; `R$ 2,869,361.27`), diikuti `voucher` (`3,866` pesanan unik vs. `5,775` baris pembayaran; `R$ 379,436.87`) dan `debit_card` (`1,528` pesanan unik vs. `1,529` baris pembayaran; `R$ 217,989.79`). Selisih antara jumlah pesanan unik dan jumlah baris pembayaran—terutama pada `credit_card` dan `voucher`—menunjukkan satu pesanan dapat terdiri dari beberapa baris atau kombinasi pembayaran.

### 2. Performa Logistik, Gradasi Keterlambatan & Konsentrasi Rute/Penjual
- **Performa pengiriman secara keseluruhan:** Dari `96,470` pesanan `delivered` dengan tanggal valid (`8` pesanan `delivered` tanpa tanggal terima), `6,534` pesanan mengalami keterlambatan (`6.77%` pada cakupan *delivered*) sementara rata-rata selisih keseluruhan berada di **`-11.88` hari** karena estimasi pengiriman cenderung longgar.
- **Gradasi keterlambatan terhadap skor & ulasan buruk (`<= 2`):**
  - **Tepat waktu / lebih cepat (`89,442` pesanan):** rata-rata skor **`4.29`**, porsi ulasan buruk **`9.2%`**.
  - **Telat 1–3 hari (`1,852` pesanan):** rata-rata skor **`3.29`**, porsi ulasan buruk **`32.2%`**.
  - **Telat 4–7 hari (`1,748` pesanan):** rata-rata skor **`2.11`**, porsi ulasan buruk **`67.6%`**.
  - **Telat > 7 hari (`2,781` pesanan):** rata-rata skor **`1.70`**, porsi ulasan buruk **`79.2%`**.
- **Sebaran lokasi & distribusi skor ulasan:** Volume pesanan terkonsentrasi pada pusat kota dan negara bagian utama pelanggan, sementara distribusi skor ulasan memperlihatkan bahwa meskipun skor tinggi mendominasi secara keseluruhan (`Avg Review Score` **`4.16`** pada cakupan *delivered*), proporsi ulasan buruk (`<= 2`) melonjak tajam seiring bertambahnya hari keterlambatan.
- **Konsentrasi rute (`customer_state`) & penjual (`seller_id`):** Pada negara bagian dengan keterlambatan tinggi seperti `AL` (`21.4%` terlambat dari `397` pesanan; rata-rata `3.4` hari proses penjual vs. `21.1` hari kurir) dan `MA` (`17.4%` terlambat dari `717` pesanan; `3.6` hari proses penjual vs. `17.9` hari kurir), waktu pengiriman kurir lebih panjang dibanding proses penjual. Pada tingkat penjual (`>= 30` pesanan `delivered`), tingkat keterlambatan tertinggi mencapai `32.6%` (`43` pesanan) dan `30.1%` (`73` pesanan).
- **Rekomendasi:** Prioritaskan pemantauan pengiriman pada rute/`state` dengan durasi kurir panjang (`AL`, `MA`) dan evaluasi SLA penjual ber-keterlambatan tinggi, serta sesuaikan akurasi estimasi tanggal tiba dengan waktu tempuh aktual.

### 3. Beban Ongkos Kirim vs. Harga Produk & Kategori Teratas
- Pada kategori bernilai satuan rendah seperti `dvds_blu_ray` (rata-rata harga `R$ 15.90`, rata-rata ongkir `R$ 21.71`), rata-rata biaya kirim mencapai **`135.49%`** dari harga barang, diikuti kategori seperti `fashion_underwear_beach` (`75.63%`) dan `signaling_and_security` (`58.18%`), sementara perhitungan tertimbang dengan batas volume (`>= 500` item) membantu menyaring kategori kecil.
- Pada *dashboard* **Top 10 Product Categories by Delivered GMV** (cakupan `delivered`, mengecualikan `(Blank)` dan diurutkan menurun), kategori seperti `health_beauty`, `watches_gifts`, `bed_bath_table`, dan `sports_leisure` memimpin nilai GMV, dengan *tooltip* `Weighted Freight Ratio` (misalnya `22.23%` pada `housewares` vs. `16.63%` rata-rata tertimbang keseluruhan) untuk memantau proporsi biaya kirim per kategori.
- **Rekomendasi:** Uji skema *bundling* multi-item, batas minimum belanja untuk promo ongkir, atau opsi pengiriman hemat pada kategori berharga rendah agar biaya kirim tidak terasa membebani saat *checkout*.

### 4. Retensi Pelanggan / *Repeat Purchase Rate*
- Dari `93,358` pelanggan unik (`customer_unique_id`) dengan pesanan `delivered`, hanya `2,801` pelanggan (**`3.00%`**) yang melakukan lebih dari satu transaksi *delivered*.
- Berdasarkan pengalaman pesanan pertama, pelanggan dengan pesanan pertama tepat waktu memiliki *repeat purchase rate* **`3.04%`** (`86,995` pelanggan), sedikit lebih tinggi dibanding pelanggan dengan pesanan pertama terlambat sebesar **`2.52%`** (`6,355` pelanggan).
- **Rekomendasi:** Jaga ketepatan waktu pengiriman sejak pesanan pertama dan dorong pembelian kedua melalui kampanye *follow-up* pasca-pengiriman serta rekomendasi produk komplementer.

---

## Catatan Metodologi & Teknis (SQL & Power BI)

- **Konversi tipe data & pembulatan (SQL):** Kolom numerik dan tanggal dikonversi secara eksplisit menggunakan `CAST(... AS DECIMAL(10,2))` atau `CAST(... AS DATETIME)` dan dirapikan dengan `ROUND(..., 2)`.
- **Antiganda pada level pesanan (SQL):** Penggunaan `COUNT(DISTINCT o.order_id)` saat menggabungkan `orders` dan `order_items` (serta pada analisis metode pembayaran di `order_payments`) mencegah satu pesanan terhitung lebih dari satu kali.
- **Identitas pelanggan unik (SQL):** Analisis *repeat purchase* menggunakan `c.customer_unique_id` alih-alih `c.customer_id` agar pembelian berulang oleh pelanggan yang sama teridentifikasi secara akurat.
- **Pemodelan bintang & `CROSSFILTER` antar-granularitas (Power BI):** Model data menggunakan skema bintang yang menghubungkan `Fact_Orders` (level pesanan), `Fact_OrderItems` (level item pesanan), `Dim_Products`, `Dim_Date`, dan `Dim_Sellers`. Karena `Delivered GMV` dievaluasi pada level pesanan (`Fact_Orders`) sementara kategori produk berada di `Dim_Products` yang berelasi *single-direction* melalui `Fact_OrderItems`, diterapkan `CROSSFILTER(Fact_OrderItems[order_id], Fact_Orders[order_id], Both)` secara eksplisit di dalam DAX `Delivered GMV` agar *filter* kategori mengalir akurat tanpa mengaktifkan *bidirectional cross-filtering* permanen pada model.
- **Struktur *Dashboard* & Validasi Visual (Power BI):** Kanvas 16:9 dengan judul *Olist E-Commerce Performance*, subjudul *Delivered Orders Scope*, *slicer* `Year Month`, baris 7 kartu KPI (*accent bar* biru untuk performa/retensi dan kuning/jingga untuk risiko/biaya), *combo chart* `Delivered GMV and Delivered Orders` (`2016-09` s.d. `2018-08`), *line & column chart* `Late Delivery % and Bad Review % Trend`, serta *clustered bar chart* `Top 10 Product Categories by Delivered GMV` (`Top N = 10` *descending*, tanpa `(Blank)`, dengan *tooltip* `Weighted Freight Ratio`).

File laporan interaktif tersedia pada [dashboard_ecommerce_performance.pbix](dashboard_ecommerce_performance.pbix).

---

## Metric Dictionary (Kamus Metrik)

| Metrik / Kolom | Definisi & Formula | Cakupan & Catatan |
| :--- | :--- | :--- |
| **Delivered GMV / Nilai Produk** | `CALCULATE(SUM(Fact_Orders[gmv]), Fact_Orders[order_status] = "delivered", CROSSFILTER(Fact_OrderItems[order_id], Fact_Orders[order_id], Both))` (di SQL: `SUM(CAST(price AS DECIMAL(10, 2)))` pada `delivered`) | Nilai GMV / produk dalam **R$ (BRL)** pada cakupan pesanan `delivered`, dengan *cross-filter* eksplisit agar responsif terhadap *filter* kategori produk. |
| **Avg Review Score** | Rata-rata skor ulasan (`1–5`) pada pesanan `delivered` | Mengukur kepuasan pelanggan pada transaksi yang terkirim (`4.16` keseluruhan). |
| **Weighted Freight Ratio / Rasio Ongkir Tertimbang** | `100 * SUM(ongkir) / SUM(gmv)` | Rasio total ongkir terhadap total nilai produk pada pesanan `delivered` (`price > 0`), dengan batas minimum volume item (`16.63%` keseluruhan). |
| **Selisih Pengiriman (`hari_telat`)** | `DATEDIFF(tgl_terima, tgl_estimasi)` | Negatif/nol = tiba lebih cepat atau tepat estimasi; positif (`> 0`) = terlambat melewati tanggal estimasi. |
| **Late Delivery % (`pct_terlambat`)** | `100 * AVG(hari_telat > 0)` | Proporsi pesanan `delivered` bertanggal valid yang tiba melewati tanggal estimasi (`6.77%` pada cakupan *delivered*). |
| **Bad Review % (`pct_ulasan_buruk`)** | `100 * AVG(skor_ulasan <= 2)` | Proporsi ulasan bernilai `1` atau `2` (skala `1–5`) pada cakupan/kelompok keterlambatan (`13.44%` keseluruhan). |
| **Repeat Purchase Rate** | `100 * AVG(jml_order_delivered > 1)` | Proporsi pelanggan unik (`customer_unique_id`) dengan lebih dari 1 pesanan berstatus `delivered` (`3.00%`). |

---

## Decision Log (Catatan Keputusan Analisis)

- **Memisahkan pesanan `delivered` dari status non-*delivered*:** Pesanan `shipped`, `invoiced`, `processing`, dan `canceled` diaudit terpisah agar metrik pendapatan, pengiriman, ulasan, dan retensi hanya mencerminkan transaksi yang benar-benar diterima pelanggan.
- **Mengeluarkan `8` pesanan `delivered` tanpa tanggal terima pada analisis keterlambatan (`96,478` menjadi `96,470`):** Pesanan tanpa `order_delivered_customer_date` tidak dapat dihitung selisih hari pengirimannya (`hari_telat`), sehingga dicatat eksplisit agar selisih jumlah pesanan transparan.
- **Menyusun *view* per pesanan (`v_order_base` & `v_order_summary`) dan menguji rekonsiliasi:** Mengagregasi item dan ulasan per `order_id` sebelum digabung mencegah duplikasi baris dan memusatkan konversi tipe data, lalu diverifikasi melalui uji rekonsiliasi jumlah baris dan total GMV.
- **Menggunakan `customer_unique_id` untuk analisis retensi:** Menghindari distorsi perhitungan karena satu pelanggan dapat memiliki lebih dari satu `customer_id` pada skema Olist.
- **Memakai `LEFT JOIN` dengan label `'unknown'` (SQL) dan mengecualikan `(Blank)` pada Top 10 kategori *dashboard* (Power BI):** Di SQL, `LEFT JOIN` dengan `'unknown'` menjaga total GMV dan rasio ongkir tidak hilang; di *visual* Top 10 kategori Power BI, `(Blank)` dikecualikan agar 10 baris teratas menampilkan kategori produk valid dan mengaktifkan *tooltip* `Weighted Freight Ratio`.
- **Menjaga *single-direction* model & memakai `CROSSFILTER` di DAX `Delivered GMV`:** Menghindari ambiguitas jalur filter antar-tabel fakta sekaligus memungkinkan *filter* kategori produk memengaruhi `Delivered GMV` secara terkendali.

---

## Batasan Analisis

- **Asosiasi vs. kausalitas:** Perbedaan skor ulasan, proporsi ulasan buruk, dan *repeat purchase rate* pada pesanan terlambat mencerminkan pola historis pada data, bukan bukti kausalitas tunggal.
- **Bias ulasan pelanggan:** Tidak seluruh pesanan memiliki ulasan (`order_reviews`), dan pelanggan yang mengalami pengalaman ekstrem cenderung lebih sering memberikan ulasan.
- **Estimasi pengiriman yang cenderung longgar:** Selisih rata-rata keseluruhan `-11.88` hari menunjukkan tanggal estimasi Olist memiliki penyangga waktu yang relatif lebar, sehingga keterlambatan aktual terjadi ketika pengiriman melewati batas estimasi tersebut.
- **Periode data historis & bulan awal/akhir parsial:** Dataset Olist merupakan data historis dengan volume transaksi yang lebih tipis/parsial pada bulan awal dan akhir rentang waktu, sehingga pembacaan tren bulanan perlu memperhatikan kelengkapan periode.
- **GMV bukan laba bersih:** Nilai GMV / nilai produk (`R$`) mencerminkan nilai transaksi barang dalam *Brazilian Real* (`BRL`), belum memperhitungkan ongkos kirim, diskon/biaya promosi, komisi *marketplace*, maupun biaya operasional/HPP.

---

## Panduan Reproducibility (Cara Menjalankan Ulang)

1. **Siapkan Database:** Buat database `db_olist` di **MySQL Server 8.0** dan impor tabel dataset *Brazilian E-Commerce Public Dataset by Olist* dari Kaggle.
2. **Audit Data:** Jalankan `01_data_cleaning_and_audit.sql` untuk memverifikasi kelengkapan data, tipe kolom, dan distribusi status pesanan.
3. **Bangun *View* & Rekonsiliasi:** Jalankan `02_view_and_reconcilation.sql` untuk membuat `v_order_base` dan `v_order_summary` beserta kueri rekonsiliasi jumlah baris dan total GMV.
4. **Jalankan Analisis Bisnis & Operasional:** Jalankan `03_business_and_operational_analysis.sql` untuk menghasilkan tren bulanan, metode pembayaran, kategori produk, gradasi keterlambatan, kinerja rute/penjual, rasio ongkir tertimbang, dan *repeat purchase rate*.
5. **Buka & Validasi Dashboard Power BI:** Buka `dashboard_ecommerce_performance.pbix` di Power BI Desktop, pastikan *slicer* `Year Month` berada pada `All`, periksa koneksi model bintang (`Fact_Orders`, `Fact_OrderItems`, `Dim_Products`, `Dim_Date`, `Dim_Sellers`) serta rumus DAX `Delivered GMV`, dan tinjau ketiga visual utama (*Delivered GMV and Delivered Orders*, *Late Delivery % and Bad Review % Trend*, dan *Top 10 Product Categories by Delivered GMV*).

---

## Struktur Repositori

```text
├── 01_data_cleaning_and_audit.sql
├── 02_view_and_reconciliation.sql
├── 03_business_and_operational_analysis.sql
├── dashboard_ecommerce_performance.pbix
├── olist_dashboard.png
└── README.md