/* ==========================================================================
   ANALISIS 3 – OTIF (On-Time In-Full) DAN SUPPLIER SCORECARD
   
   Definisi: OTIF = tepat waktu (GR terakhir - tgl kirim PO <= grace) DAN lengkap
   (qty GR >= qty PO x (1 - toleransi); bakalan: ekor juga penuh).
   Baris "INVOICE TANPA GR" tidak dinilai. PO belum diterima = gagal.
   ========================================================================== */

CREATE OR REPLACE VIEW porto_proc.v_otif AS
WITH prm AS (
  SELECT 1 AS grace, DATE '2026-10-15' AS cutoff                       
),
b AS (
  SELECT v.*, prm.grace, prm.cutoff,
         CASE WHEN v.qty_gr = 0 AND v.status = 'INVOICE TANPA GR' THEN 0 ELSE 1 END AS dinilai,
         CASE WHEN v.qty_gr > 0 THEN DATE_DIFF(v.last_gr_date, v.tgl_kirim_diharapkan, DAY)
              ELSE DATE_DIFF(prm.cutoff, v.tgl_kirim_diharapkan, DAY) END AS hari_telat,
         CASE WHEN v.qty_inv > 0 THEN 1 ELSE 0 END AS ada_faktur,
         CASE WHEN v.qty_gr > 0 AND v.qty_inv > 0 THEN 1 ELSE 0 END AS complete,
         EXTRACT(YEAR FROM v.tgl_kirim_diharapkan)*100 + EXTRACT(MONTH FROM v.tgl_kirim_diharapkan) AS bulan
  FROM porto_proc.v_three_way_match v CROSS JOIN prm
),
c AS (
  SELECT b.*,
    CASE WHEN dinilai = 1 AND qty_gr > 0 AND hari_telat <= grace THEN 1 ELSE 0 END AS ontime,
    CASE WHEN dinilai = 1 AND qty_gr > 0 AND qty_gr >= qty_po*(1 - tol_gr_vs_po)
              AND (ekor_po = 0 OR ekor_gr >= ekor_po) THEN 1 ELSE 0 END AS infull
  FROM b
)
SELECT c.*,
       ontime*infull AS otif,
       CASE WHEN dinilai = 1 THEN LEAST(qty_gr, qty_po) ELSE 0 END AS fill_qty,
       CASE WHEN dinilai = 1 AND qty_gr > 0 AND hari_telat > grace THEN 1 ELSE 0 END AS f_telat,
       CASE WHEN dinilai = 0 THEN 'Tidak dinilai'
            WHEN ontime*infull = 1 THEN 'OTIF'
            WHEN qty_gr = 0 THEN 'Belum diterima'
            WHEN ontime = 0 AND infull = 0 THEN 'Telat & kurang'
            WHEN ontime = 0 THEN 'Telat' ELSE 'Kurang' END AS penyebab
FROM c;

-- ---------- Q1. OTIF per kategori ----------
SELECT kategori, SUM(dinilai) AS n, SUM(otif) AS k,
       ROUND(100.0*SUM(otif)/SUM(dinilai),1) AS otif_pct,
       ROUND(100.0*SUM(ontime)/SUM(dinilai),1) AS ontime_pct,
       ROUND(100.0*SUM(infull)/SUM(dinilai),1) AS infull_pct
FROM porto_proc.v_otif GROUP BY kategori ORDER BY kategori;

-- ---------- Q2. Scorecard per supplier ----------
WITH s AS (
  SELECT supplier_id, supplier_name,
         SUM(dinilai) AS n, SUM(otif) AS k,
         SUM(complete) AS n_complete, SUM(CASE WHEN status='MATCH' THEN 1 ELSE 0 END) AS n_match,
         SUM(ada_faktur) AS n_inv, SUM(f_harga) AS n_harga,
         SUM(CASE WHEN dinilai=1 AND ekor_po>0 THEN ekor_po ELSE 0 END) AS ekor_po,
         SUM(CASE WHEN dinilai=1 AND ekor_po>0 THEN LEAST(ekor_gr,ekor_po) ELSE 0 END) AS ekor_ok
  FROM porto_proc.v_otif GROUP BY supplier_id, supplier_name
),
d AS (
  SELECT s.*,
    100.0*k/n AS sk_kirim,
    CASE WHEN n_complete>0 THEN 100.0*n_match/n_complete END AS sk_tagihan,
    CASE WHEN n_inv>0 THEN 100.0*(1.0-1.0*n_harga/n_inv) END AS sk_harga,
    CASE WHEN ekor_po>0 THEN 100.0*ekor_ok/ekor_po END AS sk_fisik
  FROM s
),
w AS (SELECT 0.40 AS w1, 0.30 AS w2, 0.20 AS w3, 0.10 AS w4)
SELECT supplier_id, supplier_name, n, k,
       ROUND(sk_kirim,1) AS sk_kirim, ROUND(sk_tagihan,1) AS sk_tagihan, ROUND(sk_harga,1) AS sk_harga, ROUND(sk_fisik,1) AS sk_fisik,
       ROUND((w1*sk_kirim + CASE WHEN sk_tagihan IS NOT NULL THEN w2*sk_tagihan ELSE 0 END
              + CASE WHEN sk_harga IS NOT NULL THEN w3*sk_harga ELSE 0 END
              + CASE WHEN sk_fisik IS NOT NULL THEN w4*sk_fisik ELSE 0 END)
             /(w1 + CASE WHEN sk_tagihan IS NOT NULL THEN w2 ELSE 0 END
                  + CASE WHEN sk_harga IS NOT NULL THEN w3 ELSE 0 END
                  + CASE WHEN sk_fisik IS NOT NULL THEN w4 ELSE 0 END),1) AS skor
FROM d CROSS JOIN w ORDER BY skor DESC;

-- ---------- Q3. Interval Wilson 95% OTIF per supplier ----------
WITH s AS (SELECT supplier_id, SUM(dinilai) AS n, SUM(otif) AS k FROM porto_proc.v_otif GROUP BY supplier_id),
p AS (SELECT supplier_id, n, k, 1.0*k/n AS ph, 1.96 AS z FROM s)
SELECT supplier_id, n, k, ROUND(100*ph,1) AS otif_pct,
  ROUND(100*((ph + z*z/(2*n) - z*SQRT(ph*(1-ph)/n + z*z/(4.0*n*n)))/(1+z*z/n)),1) AS ci_bawah,
  ROUND(100*((ph + z*z/(2*n) + z*SQRT(ph*(1-ph)/n + z*z/(4.0*n*n)))/(1+z*z/n)),1) AS ci_atas
FROM p ORDER BY supplier_id;

-- ---------- Q4. P-chart: OTIF per bulan jatuh tempo + batas kontrol 3 sigma ----------
WITH m AS (SELECT bulan, SUM(dinilai) AS n, SUM(otif) AS k FROM porto_proc.v_otif GROUP BY bulan),
t AS (SELECT 1.0*SUM(k)/SUM(n) AS pbar FROM m)
SELECT bulan, n, k, ROUND(100.0*k/n,1) AS p_pct, ROUND(100*pbar,1) AS pbar_pct,
       ROUND(100*LEAST(1.0, pbar + 3*SQRT(pbar*(1-pbar)/n)),1) AS ucl,
       ROUND(100*GREATEST(0.0, pbar - 3*SQRT(pbar*(1-pbar)/n)),1) AS lcl
FROM m CROSS JOIN t ORDER BY bulan;

-- ---------- Q5. Distribusi keterlambatan (pengiriman yang sudah diterima & dinilai) ----------
SELECT CASE WHEN hari_telat<=0 THEN '1. <=0' WHEN hari_telat=1 THEN '2. 1 hari' WHEN hari_telat=2 THEN '3. 2 hari'
            WHEN hari_telat=3 THEN '4. 3 hari' WHEN hari_telat<=5 THEN '5. 4-5 hari' ELSE '6. >=6 hari' END AS kelas,
       COUNT(*) AS jumlah
FROM porto_proc.v_otif WHERE dinilai=1 AND qty_gr>0 GROUP BY 1 ORDER BY 1;

-- ---------- Q6. Lead time janji vs aktual per kategori + lead time disarankan (~P80) ----------
WITH x AS (
  SELECT kategori, hari_telat AS delta,
         DATE_DIFF(tgl_kirim_diharapkan, po_date, DAY) AS janji,
         DATE_DIFF(last_gr_date, po_date, DAY) AS aktual
  FROM porto_proc.v_otif WHERE dinilai=1 AND qty_gr>0
),
g AS (SELECT kategori, COUNT(*) AS n, AVG(1.0*janji) AS janji, AVG(1.0*aktual) AS aktual, AVG(1.0*delta) AS d,
             SUM(1.0*delta*delta) AS ss FROM x GROUP BY kategori)
SELECT kategori, n, ROUND(janji,2) AS lt_janji, ROUND(aktual,2) AS lt_aktual, ROUND(d,2) AS selisih,
       ROUND(SQRT((ss - n*d*d)/(n-1)),2) AS sd,
       ROUND(d/(SQRT((ss - n*d*d)/(n-1))/SQRT(n)),2) AS t_stat       -- p-value: gunakan tabel t / fungsi statistik di luar SQL
FROM g ORDER BY kategori;

-- ---------- Q7. Sensitivitas definisi tepat waktu (grace 0-3 hari) ----------
WITH gs AS (SELECT g FROM UNNEST([0,1,2,3]) AS g)
SELECT g AS grace,
       ROUND(100.0*SUM(CASE WHEN dinilai=1 AND qty_gr>0 AND hari_telat<=g AND infull=1 THEN 1 ELSE 0 END)/SUM(dinilai),1) AS otif_pct
FROM porto_proc.v_otif CROSS JOIN gs GROUP BY g ORDER BY g;

-- ---------- Q8. Penyebab kegagalan OTIF ----------
SELECT penyebab, COUNT(*) AS jumlah FROM porto_proc.v_otif WHERE penyebab NOT IN ('OTIF','Tidak dinilai') GROUP BY penyebab ORDER BY jumlah DESC;
