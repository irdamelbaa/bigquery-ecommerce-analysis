-- ============================================================
-- PROYEK  : Analisis E-commerce dengan BigQuery + Looker Studio
-- SUMBER  : bigquery-public-data.thelook_ecommerce
-- PROJECT : portfolio-bigquery-512504
-- DATASET : thelook_analysis (lokasi: US, sama dengan dataset publik)
--
-- Urutan pakai: 00 -> 01 -> 02 -> 03 -> 04 -> 05 -> 06 -> 07
-- Catatan: di mode sandbox, tabel dan view kedaluwarsa setelah 60 hari.
-- Jalankan ulang bagian 01 dan 03-06 untuk membangun ulang semuanya.
-- ============================================================


-- ============================================================
-- 00. TES KONEKSI KE DATASET PUBLIK
-- ============================================================
SELECT *
FROM `bigquery-public-data.thelook_ecommerce.order_items`
LIMIT 10;


-- ============================================================
-- 01. SALIN TABEL KE DATASET SENDIRI (thelook_analysis)
-- ============================================================
CREATE OR REPLACE TABLE `portfolio-bigquery-512504.thelook_analysis.order_items` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.order_items`;

CREATE OR REPLACE TABLE `portfolio-bigquery-512504.thelook_analysis.orders` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.orders`;

CREATE OR REPLACE TABLE `portfolio-bigquery-512504.thelook_analysis.products` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.products`;

CREATE OR REPLACE TABLE `portfolio-bigquery-512504.thelook_analysis.users` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.users`;

CREATE OR REPLACE TABLE `portfolio-bigquery-512504.thelook_analysis.distribution_centers` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.distribution_centers`;

CREATE OR REPLACE TABLE `portfolio-bigquery-512504.thelook_analysis.inventory_items` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.inventory_items`;

-- OPSIONAL: tabel events berukuran besar. Cek ukurannya dulu (tab Details,
-- Total logical bytes) dan pastikan jauh di bawah batas penyimpanan sandbox (~10 GB).
-- CREATE OR REPLACE TABLE `portfolio-bigquery-512504.thelook_analysis.events` AS
-- SELECT * FROM `bigquery-public-data.thelook_ecommerce.events`;


-- ============================================================
-- 02. CEK JUMLAH BARIS TABEL YANG DISALIN
-- ============================================================
SELECT 'order_items' AS tabel, COUNT(*) AS jumlah_baris
FROM `portfolio-bigquery-512504.thelook_analysis.order_items`
UNION ALL
SELECT 'orders', COUNT(*)
FROM `portfolio-bigquery-512504.thelook_analysis.orders`
UNION ALL
SELECT 'products', COUNT(*)
FROM `portfolio-bigquery-512504.thelook_analysis.products`
UNION ALL
SELECT 'users', COUNT(*)
FROM `portfolio-bigquery-512504.thelook_analysis.users`;


-- ============================================================
-- 03. VIEW: TREN OMZET BULANAN
-- Pertanyaan: bagaimana tren omzet dari bulan ke bulan?
-- Pesanan Cancelled dan Returned dikecualikan agar omzet mencerminkan penjualan nyata.
-- ============================================================
CREATE OR REPLACE VIEW `portfolio-bigquery-512504.thelook_analysis.monthly_revenue` AS
SELECT
  DATE_TRUNC(DATE(created_at), MONTH) AS bulan,
  COUNT(DISTINCT order_id) AS jumlah_order,
  ROUND(SUM(sale_price), 2) AS omzet
FROM `portfolio-bigquery-512504.thelook_analysis.order_items`
WHERE status NOT IN ('Cancelled', 'Returned')
GROUP BY bulan;


-- ============================================================
-- 04. VIEW: PROFIT PER KATEGORI PRODUK (dengan kolom tanggal)
-- Pertanyaan: kategori mana yang paling menguntungkan?
-- Kolom tanggal ditambahkan agar kontrol date range di Looker Studio berfungsi.
-- ============================================================
CREATE OR REPLACE VIEW `portfolio-bigquery-512504.thelook_analysis.category_profit` AS
SELECT
  DATE(oi.created_at) AS tanggal,
  p.category,
  COUNT(*) AS unit_terjual,
  ROUND(SUM(oi.sale_price), 2) AS omzet,
  ROUND(SUM(oi.sale_price - p.cost), 2) AS profit
FROM `portfolio-bigquery-512504.thelook_analysis.order_items` AS oi
JOIN `portfolio-bigquery-512504.thelook_analysis.products` AS p
  ON oi.product_id = p.id
WHERE oi.status NOT IN ('Cancelled', 'Returned')
GROUP BY tanggal, p.category;


-- ============================================================
-- 05. VIEW: OMZET PER SUMBER TRAFIK (dengan kolom tanggal)
-- Pertanyaan: dari sumber trafik mana omzet terbanyak datang?
-- Hanya kolom omzet, karena hitungan unik per hari tidak bisa dijumlahkan antar hari.
-- ============================================================
CREATE OR REPLACE VIEW `portfolio-bigquery-512504.thelook_analysis.traffic_source_revenue` AS
SELECT
  DATE(oi.created_at) AS tanggal,
  u.traffic_source,
  ROUND(SUM(oi.sale_price), 2) AS omzet
FROM `portfolio-bigquery-512504.thelook_analysis.users` AS u
JOIN `portfolio-bigquery-512504.thelook_analysis.order_items` AS oi
  ON oi.user_id = u.id
WHERE oi.status NOT IN ('Cancelled', 'Returned')
GROUP BY tanggal, u.traffic_source;


-- ============================================================
-- 06. VIEW: SEGMENTASI PELANGGAN (RFM)
-- Pertanyaan: siapa pelanggan paling bernilai dan siapa yang berisiko pergi?
-- Frekuensi tidak dibagi dengan NTILE karena sebagian besar pelanggan hanya
-- punya 1 order, sehingga pembagian kuintil menjadi tidak adil.
-- Segmentasi dihitung dari seluruh riwayat, jadi tidak diberi kolom tanggal.
-- ============================================================
CREATE OR REPLACE VIEW `portfolio-bigquery-512504.thelook_analysis.rfm_segmen` AS
WITH rfm_base AS (
  SELECT
    user_id,
    DATE_DIFF(
      (SELECT MAX(DATE(created_at))
       FROM `portfolio-bigquery-512504.thelook_analysis.order_items`),
      MAX(DATE(created_at)), DAY) AS recency,
    COUNT(DISTINCT order_id) AS frequency,
    ROUND(SUM(sale_price), 2) AS monetary
  FROM `portfolio-bigquery-512504.thelook_analysis.order_items`
  WHERE status NOT IN ('Cancelled', 'Returned')
  GROUP BY user_id
),
rfm_score AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
    LEAST(frequency, 5) AS f_score,
    NTILE(5) OVER (ORDER BY monetary) AS m_score
  FROM rfm_base
)
SELECT *,
  CASE
    WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
    WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal'
    WHEN r_score >= 4 AND f_score <= 2 THEN 'Pelanggan Baru'
    WHEN r_score <= 2 AND f_score >= 3 THEN 'Berisiko Pergi'
    WHEN r_score <= 2 AND f_score <= 2 THEN 'Hilang'
    ELSE 'Lainnya'
  END AS segmen
FROM rfm_score;


-- ============================================================
-- 07. QUERY UNTUK MENGAMBIL TEMUAN (angka untuk README)
-- ============================================================

-- 07a. Lihat seluruh tren omzet bulanan
SELECT *
FROM `portfolio-bigquery-512504.thelook_analysis.monthly_revenue`
ORDER BY bulan;

-- 07b. Lima bulan dengan omzet tertinggi
SELECT bulan, omzet
FROM `portfolio-bigquery-512504.thelook_analysis.monthly_revenue`
ORDER BY omzet DESC
LIMIT 5;

-- 07c. Lima kategori dengan profit terbesar
SELECT category, ROUND(SUM(profit), 2) AS profit
FROM `portfolio-bigquery-512504.thelook_analysis.category_profit`
GROUP BY category
ORDER BY profit DESC
LIMIT 5;

-- 07d. Omzet per sumber trafik beserta persentasenya
SELECT
  traffic_source,
  ROUND(SUM(omzet), 2) AS omzet,
  ROUND(100 * SUM(omzet) / SUM(SUM(omzet)) OVER (), 1) AS persen
FROM `portfolio-bigquery-512504.thelook_analysis.traffic_source_revenue`
GROUP BY traffic_source
ORDER BY omzet DESC;

-- 07e. Jumlah dan persentase pelanggan per segmen RFM
SELECT
  segmen,
  COUNT(*) AS jumlah_pelanggan,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS persen
FROM `portfolio-bigquery-512504.thelook_analysis.rfm_segmen`
GROUP BY segmen
ORDER BY jumlah_pelanggan DESC;
