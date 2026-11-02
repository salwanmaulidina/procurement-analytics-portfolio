/* ==========================================================================
   ANALISIS 2 – PURCHASE PRICE VARIANCE (PPV)  
   Harga standar = item.harga_acuan (simulasi).
   PPV = (harga aktual - harga standar) x qty diterima (GR); positif = lebih mahal.
   Dekomposisi (menjumlah persis ke PPV):
     efek pasar    = (indeks pasar - 1) x nilai standar
     efek supplier = nilai PO - indeks pasar x nilai standar
     efek faktur   = nilai aktual - nilai PO
   indeks pasar = nilai PO / nilai standar per kategori-bulan (proksi internal).
   ========================================================================== */

CREATE OR REPLACE VIEW porto_proc.v_ppv AS
WITH gr AS (
  SELECT po_line_id, SUM(qty_diterima) AS qty_gr FROM porto_proc.gr_line GROUP BY po_line_id
),
inv AS (
  SELECT po_line_id, SUM(qty_faktur) AS qty_inv, SUM(jumlah_faktur) AS inv_net
  FROM porto_proc.inv_line GROUP BY po_line_id
),
base AS (
  SELECT p.po_line_id, p.po_date, p.supplier_id, s.supplier_name, p.item_id, it.item_name, it.kategori,
         it.harga_acuan AS std, p.harga_po,
         EXTRACT(YEAR FROM p.po_date)*100 + EXTRACT(MONTH FROM p.po_date) AS bulan,
         COALESCE(g.qty_gr,0) AS qty_gr, COALESCE(i.qty_inv,0) AS qty_inv, COALESCE(i.inv_net,0) AS inv_net
  FROM porto_proc.po_line p
  JOIN porto_proc.supplier s ON s.supplier_id = p.supplier_id
  JOIN porto_proc.item it    ON it.item_id    = p.item_id
  LEFT JOIN gr  g ON g.po_line_id  = p.po_line_id
  LEFT JOIN inv i ON i.po_line_id  = p.po_line_id
),
v AS (
  SELECT base.*,
         CASE WHEN qty_gr > 0 THEN 1 ELSE 0 END AS dipakai,
         CASE WHEN qty_inv > 0 THEN 1.0*inv_net/qty_inv ELSE harga_po END AS harga_aktual
  FROM base
),
w AS (
  SELECT v.*,
         CASE WHEN dipakai = 1 THEN qty_gr*std          ELSE 0 END AS nilai_std,
         CASE WHEN dipakai = 1 THEN qty_gr*harga_po     ELSE 0 END AS nilai_po,
         CASE WHEN dipakai = 1 THEN qty_gr*harga_aktual ELSE 0 END AS nilai_aktual
  FROM v
),
idx AS (
  SELECT kategori, bulan,
         CASE WHEN SUM(nilai_std) > 0 THEN 1.0*SUM(nilai_po)/SUM(nilai_std) ELSE 1.0 END AS idx_pasar
  FROM w GROUP BY kategori, bulan
)
SELECT w.*, idx.idx_pasar,
       CASE WHEN dipakai = 1 THEN (idx_pasar - 1)*nilai_std      ELSE 0 END AS efek_pasar,
       CASE WHEN dipakai = 1 THEN nilai_po - idx_pasar*nilai_std ELSE 0 END AS efek_supplier,
       nilai_aktual - nilai_po AS efek_faktur,
       nilai_aktual - nilai_std AS ppv,
       CASE WHEN dipakai = 1 THEN 1.0*harga_po/(idx_pasar*std) END AS rpi,   -- indeks harga relatif thd pasar
       1.0*harga_po/std AS idx_line
FROM w JOIN idx ON idx.kategori = w.kategori AND idx.bulan = w.bulan;

-- Q1. PPV per kategori dan dekomposisinya
SELECT kategori,
       SUM(nilai_std) AS nilai_standar, SUM(nilai_aktual) AS nilai_aktual, SUM(ppv) AS ppv,
       ROUND(100.0*SUM(ppv)/SUM(nilai_std),2) AS ppv_pct,
       SUM(efek_pasar) AS efek_pasar, ROUND(SUM(efek_supplier),0) AS efek_supplier, SUM(efek_faktur) AS efek_faktur
FROM porto_proc.v_ppv WHERE dipakai = 1
GROUP BY kategori ORDER BY ppv DESC;

-- Q2. Indeks pasar bulanan per kategori (1.00 = sama dengan standar)
SELECT kategori, bulan, ROUND(MAX(idx_pasar),4) AS idx_pasar, SUM(efek_pasar) AS efek_pasar_rp
FROM porto_proc.v_ppv GROUP BY kategori, bulan ORDER BY kategori, bulan;

-- Q3. PPV per supplier: pasar vs supplier vs faktur
SELECT supplier_id, supplier_name, ROUND(SUM(efek_pasar),0) AS efek_pasar, ROUND(SUM(efek_supplier),0) AS efek_supplier,
       SUM(efek_faktur) AS efek_faktur, SUM(ppv) AS ppv_total,
       ROUND(100.0*SUM(ppv)/SUM(nilai_std),2) AS ppv_pct
FROM porto_proc.v_ppv WHERE dipakai = 1
GROUP BY supplier_id, supplier_name ORDER BY ppv_total DESC;

-- Q4. Komponen ANOVA satu arah: apakah supplier berbeda untuk item yang sama? (indeks harga relatif)
WITH g AS (
  SELECT item_id, supplier_id, COUNT(*) AS n, AVG(rpi) AS mu, SUM(rpi*rpi) AS ss, SUM(rpi) AS s
  FROM porto_proc.v_ppv WHERE dipakai = 1 GROUP BY item_id, supplier_id
), g2 AS (
  SELECT g.*, CASE WHEN n > 1 THEN (ss - s*s/n) ELSE 0 END AS within_ss   -- = (n-1) x varians
  FROM g
), multi AS (
  SELECT item_id FROM g2 GROUP BY item_id HAVING COUNT(*) >= 2
), tot AS (
  SELECT item_id, COUNT(*) AS k, SUM(n) AS big_n, 1.0*SUM(n*mu)/SUM(n) AS grand, SUM(within_ss) AS ssw
  FROM g2 WHERE item_id IN (SELECT item_id FROM multi) GROUP BY item_id
), b AS (
  SELECT g2.item_id, SUM(g2.n*(g2.mu - tot.grand)*(g2.mu - tot.grand)) AS ssb
  FROM g2 JOIN tot ON tot.item_id = g2.item_id GROUP BY g2.item_id
)
SELECT tot.item_id, k, big_n, ROUND(ssb,6) AS ssb, ROUND(ssw,6) AS ssw,
       ROUND((ssb/(k-1))/(ssw/(big_n-k)),4) AS f_stat, (k-1) AS df1, (big_n-k) AS df2
FROM tot JOIN b ON b.item_id = tot.item_id
ORDER BY tot.item_id;

-- Q5. Tren harga per kategori: regresi indeks (harga PO / standar) terhadap hari sejak 2026-04-01
WITH d AS (
  SELECT kategori, CAST(DATE_DIFF(po_date, DATE '2026-04-01', DAY) AS FLOAT64) AS x, idx_line AS y
  FROM porto_proc.v_ppv WHERE dipakai = 1
), s AS (
  SELECT kategori, COUNT(*) AS n, SUM(x) AS sx, SUM(y) AS sy, SUM(x*y) AS sxy, SUM(x*x) AS sxx, SUM(y*y) AS syy
  FROM d GROUP BY kategori
), r AS (
  SELECT s.*, (n*sxy - sx*sy)/(n*sxx - sx*sx) AS slope FROM s
)
SELECT kategori, n,
       ROUND(100.0*30*slope,3) AS perubahan_pct_per_30_hari,
       ROUND(((n*sxy - sx*sy)*(n*sxy - sx*sy))/((n*sxx - sx*sx)*(n*syy - sy*sy)),4) AS r2,
       ROUND(slope / SQRT(((syy - sy*sy/n) - slope*slope*(sxx - sx*sx/n))/(n-2)/(sxx - sx*sx/n)),3) AS t_stat
FROM r ORDER BY kategori;

-- Q6. Profil harga per item: rentang, rata-rata berbobot, simpangan baku, CV
WITH s AS (
  SELECT item_id, item_name, COUNT(*) AS n, SUM(qty_gr) AS qty, MIN(harga_po) AS hmin, MAX(harga_po) AS hmax,
         1.0*SUM(nilai_po)/SUM(qty_gr) AS h_wavg, AVG(1.0*harga_po) AS h_mean,
         SUM(1.0*harga_po*harga_po) AS ss, SUM(1.0*harga_po) AS s1, SUM(ppv) AS ppv
  FROM porto_proc.v_ppv WHERE dipakai = 1 GROUP BY item_id, item_name
)
SELECT item_id, item_name, n, qty, hmin, hmax, ROUND(h_wavg,0) AS h_wavg,
       CASE WHEN n > 1 THEN ROUND(SQRT((ss - s1*s1/n)/(n-1)),1) END AS sd,
       CASE WHEN n > 1 THEN ROUND(100.0*SQRT((ss - s1*s1/n)/(n-1))/h_mean,2) END AS cv_pct,
       ppv
FROM s ORDER BY cv_pct DESC;

-- Q7. Sepuluh baris dengan PPV tidak menguntungkan terbesar
SELECT po_line_id, supplier_name, item_name, ppv, ROUND(100.0*ppv/NULLIF(nilai_std,0),2) AS ppv_pct,
       efek_pasar, efek_supplier, efek_faktur
FROM porto_proc.v_ppv WHERE dipakai = 1
ORDER BY ppv DESC
LIMIT 10;
