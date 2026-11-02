CREATE OR REPLACE VIEW porto_proc.v_three_way_match AS
WITH gr AS (
    SELECT po_line_id,
       SUM(qty_diterima)              AS qty_gr,
       COALESCE(SUM(ekor_diterima),0) AS ekor_gr,
        COUNT(*)                       AS n_gr,
        MAX(gr_date)                   AS last_gr_date
  FROM porto_proc.gr_line GROUP BY po_line_id
),
inv_marked AS (            -- faktur ganda: nomor faktur + PO line + supplier yang sama muncul > 1x
  SELECT i.*,
         CASE WHEN COUNT(*) OVER (PARTITION BY supplier_id, inv_no, po_line_id) > 1 THEN 1 ELSE 0 END AS is_dup
  FROM porto_proc.inv_line i
),
inv AS (
  SELECT po_line_id,
         SUM(qty_faktur)    AS qty_inv,
         SUM(jumlah_faktur) AS inv_net,
         SUM(ppn_faktur)    AS inv_tax,
         COUNT(*)           AS n_inv,
         MAX(is_dup)        AS f_dup
  FROM inv_marked GROUP BY po_line_id
),
base AS (
  SELECT p.po_line_id, p.po_id, p.po_date, p.supplier_id, s.supplier_name, s.tarif_ppn,
         p.item_id, it.item_name, it.kategori,
         p.qty_po, p.harga_po, COALESCE(p.ekor_po,0) AS ekor_po, p.tgl_kirim_diharapkan,
         t.tol_gr_vs_po, t.tol_inv_vs_gr, t.tol_harga,
         COALESCE(g.qty_gr,0)  AS qty_gr,  COALESCE(g.ekor_gr,0) AS ekor_gr,
         COALESCE(g.n_gr,0)    AS n_gr,    g.last_gr_date,
         COALESCE(i.qty_inv,0) AS qty_inv, COALESCE(i.inv_net,0) AS inv_net,
         COALESCE(i.inv_tax,0) AS inv_tax, COALESCE(i.n_inv,0)   AS n_inv,
         COALESCE(i.f_dup,0)   AS f_dup
  FROM porto_proc.po_line p
  JOIN porto_proc.supplier s        ON s.supplier_id = p.supplier_id
  JOIN porto_proc.item it           ON it.item_id    = p.item_id
  JOIN porto_proc.param_tolerance t ON t.kategori    = it.kategori
  LEFT JOIN gr  g ON g.po_line_id = p.po_line_id
  LEFT JOIN inv i ON i.po_line_id = p.po_line_id
),
calc AS (
  SELECT base.*,
    CASE WHEN qty_inv > 0 THEN 1.0*inv_net/qty_inv END                           AS harga_inv,
    CASE WHEN qty_gr  > 0 THEN 1.0*(qty_gr-qty_po)/qty_po END                    AS var_gr_po,
    CASE WHEN qty_gr  > 0 AND qty_inv > 0 THEN 1.0*(qty_inv-qty_gr)/qty_gr END   AS var_inv_gr,
    ROUND(inv_net*tarif_ppn, 0)                                                  AS pajak_seharusnya
  FROM base
),
flags AS (
  SELECT calc.*,
    CASE WHEN qty_inv > 0 THEN (harga_inv - harga_po)/harga_po END               AS var_harga,
    CASE WHEN qty_inv > 0 AND qty_gr = 0 THEN 1 ELSE 0 END                       AS f_nogr,
    CASE WHEN qty_gr  > 0 AND qty_inv = 0 THEN 1 ELSE 0 END                      AS f_noinv,
    CASE WHEN qty_gr  = 0 AND qty_inv = 0 THEN 1 ELSE 0 END                      AS f_open,
    CASE WHEN qty_gr > 0 AND ( ABS(var_gr_po) > tol_gr_vs_po
          OR (ekor_po > 0 AND ekor_gr <> ekor_po) ) THEN 1 ELSE 0 END AS f_qty_gr,
    CASE WHEN qty_gr > 0 AND qty_inv > 0 AND ABS(var_inv_gr) > tol_inv_vs_gr THEN 1 ELSE 0 END AS f_qty_inv,
    CASE WHEN qty_inv > 0 AND ABS((harga_inv - harga_po)/harga_po) > tol_harga THEN 1 ELSE 0 END AS f_harga,
    CASE WHEN qty_inv > 0 AND ABS(inv_tax - pajak_seharusnya) > (SELECT tol_pajak FROM porto_proc.param_general) THEN 1 ELSE 0 END AS f_pajak,
    CASE WHEN qty_gr > 0 AND qty_inv > 0
         THEN LEAST(qty_gr, qty_inv) * harga_po ELSE 0 END AS dibayar_wajar
  FROM calc
)
SELECT flags.*,
  CASE WHEN inv_net > 0
       THEN GREATEST(inv_net - dibayar_wajar, 0) + GREATEST(inv_tax - pajak_seharusnya, 0)
       ELSE 0 END AS eksposur,
  CASE WHEN f_dup   = 1 THEN 'DUPLIKAT INVOICE'
       WHEN f_nogr  = 1 THEN 'INVOICE TANPA GR'
       WHEN f_open  = 1 THEN 'PO BELUM DITERIMA'
       WHEN f_noinv = 1 THEN 'GR BELUM DIFAKTURKAN'
       WHEN f_harga = 1 THEN 'SELISIH HARGA'
       WHEN f_qty_inv = 1 THEN 'SELISIH QTY INVOICE-GR'
       WHEN f_qty_gr  = 1 THEN 'SELISIH QTY GR-PO'
       WHEN f_pajak   = 1 THEN 'PAJAK TIDAK SESUAI'
       ELSE 'MATCH' END AS status
FROM flags;

-- ---------- QUERY ANALISIS ----------

-- Q1. Ringkasan status & eksposur
SELECT status,
       COUNT(*)                                        AS n_baris,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1)   AS pct_baris,
       SUM(eksposur)                                   AS eksposur_rp
FROM porto_proc.v_three_way_match
GROUP BY status
ORDER BY eksposur_rp DESC, n_baris DESC;

-- Q2. Pareto eksposur per supplier: kejadian tunggal vs pola berulang
WITH x AS (
  SELECT supplier_id, supplier_name,
         SUM(eksposur) AS eksposur,
         SUM(CASE WHEN status IN ('DUPLIKAT INVOICE','INVOICE TANPA GR') THEN eksposur ELSE 0 END) AS kejadian_tunggal
  FROM porto_proc.v_three_way_match GROUP BY supplier_id, supplier_name
)
SELECT supplier_id, supplier_name, eksposur, kejadian_tunggal, eksposur - kejadian_tunggal AS pola_berulang,
       ROUND(100.0*SUM(eksposur) OVER (ORDER BY eksposur DESC)/SUM(eksposur) OVER (),1) AS kumulatif_pct
FROM x
ORDER BY eksposur DESC;

-- Q3. First-pass match rate per kategori + interval Wilson 95%
WITH t AS (
  SELECT kategori, COUNT(*) AS n, SUM(CASE WHEN status='MATCH' THEN 1 ELSE 0 END) AS k
  FROM porto_proc.v_three_way_match WHERE qty_gr > 0 AND qty_inv > 0 GROUP BY kategori
), p AS (
    SELECT kategori, n, k, 1.0*k/n AS ph, 1.96 AS z FROM t
)
SELECT kategori, n AS baris_dok_lengkap, k AS match,
       ROUND(100.0*ph,1) AS match_rate_pct,
       ROUND(100.0*(ph + z*z/(2.0*n) - z*SQRT(ph*(1-ph)/n + z*z/(4.0*n*n)))/(1 + z*z/n),1) AS ci95_bawah_pct,
       ROUND(100.0*(ph + z*z/(2.0*n) + z*SQRT(ph*(1-ph)/n + z*z/(4.0*n*n)))/(1 + z*z/n),1) AS ci95_atas_pct
FROM p
ORDER BY match_rate_pct;

-- Q4. Uji bias per supplier: selisih qty faktur vs GR (tanpa duplikat)
WITH v AS (
  SELECT supplier_id, supplier_name, tol_inv_vs_gr, var_inv_gr AS x
  FROM porto_proc.v_three_way_match WHERE f_dup = 0 AND var_inv_gr IS NOT NULL
), s AS (
  SELECT supplier_id, supplier_name, tol_inv_vs_gr AS tol, COUNT(*) AS n, AVG(x) AS mean_x,
         SUM(x*x) AS sumsq, SUM(x) AS sumx
  FROM v GROUP BY supplier_id, supplier_name, tol_inv_vs_gr
), d AS (
  SELECT s.*, CASE WHEN n > 1 THEN SQRT((sumsq - sumx*sumx/n)/(n-1)) END AS sd FROM s
)
SELECT supplier_id, supplier_name, n, ROUND(100.0*mean_x,2) AS mean_pct, ROUND(100.0*sd,2) AS sd_pct, ROUND(100.0*tol,1) AS tol_pct,
       CASE WHEN sd > 0 THEN ROUND(mean_x/(sd/SQRT(n)),2) END       AS t_vs_0,
       CASE WHEN sd > 0 THEN ROUND((mean_x-tol)/(sd/SQRT(n)),2) END AS t_vs_toleransi
FROM d
ORDER BY mean_x DESC;

-- Q5. Outlier z-score selisih qty faktur vs GR dibanding kategorinya
WITH v AS (
  SELECT po_line_id, supplier_id, kategori, var_inv_gr AS x
  FROM porto_proc.v_three_way_match WHERE f_dup = 0 AND var_inv_gr IS NOT NULL 
), g AS (
  SELECT kategori, COUNT(*) AS n, AVG(x) AS mu, SUM(x*x) AS sumsq, SUM(x) AS sumx FROM v GROUP BY kategori
), g2 AS (
  SELECT kategori, mu, SQRT((sumsq - sumx*sumx/n)/(n-1)) AS sd FROM g WHERE n > 1
)
SELECT v.po_line_id, v.supplier_id, v.kategori, ROUND(100.0*v.x,2) AS selisih_pct,
       ROUND((v.x - g2.mu)/g2.sd, 2) AS z_score
FROM v JOIN g2 ON g2.kategori = v.kategori
WHERE g2.sd > 0 AND ABS((v.x - g2.mu)/g2.sd) > (SELECT z_outlier FROM porto_proc.param_general)
ORDER BY ABS((v.x - g2.mu)/g2.sd) DESC;

-- Q6. Antrian tindak lanjut (non-MATCH) dengan prioritas dan aging
WITH q AS (
  SELECT v.*, pg.cutoff_date, pg.thr_followup_hari, pg.thr_stale_hari, pg.thr_eksposur,
         CASE WHEN f_noinv = 1 THEN DATE_DIFF(pg.cutoff_date, last_gr_date, DAY)
              WHEN f_open  = 1 THEN DATE_DIFF(pg.cutoff_date, tgl_kirim_diharapkan, DAY) END AS aging_hari
  FROM porto_proc.v_three_way_match v CROSS JOIN porto_proc.param_general pg
  WHERE v.status <> 'MATCH'
)
SELECT po_line_id, supplier_name, item_name, status, eksposur, aging_hari,
       CASE WHEN f_dup = 1 OR f_nogr = 1 OR eksposur >= thr_eksposur THEN 'TINGGI'
            WHEN f_noinv = 1 THEN CASE WHEN aging_hari > thr_followup_hari THEN 'SEDANG' ELSE 'RENDAH' END
            WHEN f_open  = 1 THEN CASE WHEN aging_hari > thr_stale_hari   THEN 'SEDANG' ELSE 'RENDAH' END
            ELSE 'SEDANG' END AS prioritas
FROM q
ORDER BY CASE WHEN f_dup = 1 OR f_nogr = 1 OR eksposur >= thr_eksposur THEN 0 ELSE 1 END, eksposur DESC;

-- Q7. Tren bulanan match rate (berdasarkan bulan PO)
SELECT FORMAT_DATE('%Y-%m', po_date) AS bulan_po,
       COUNT(*) AS n_baris,
       SUM(CASE WHEN status = 'MATCH' THEN 1 ELSE 0 END) AS n_match,
       ROUND(100.0*SUM(CASE WHEN status = 'MATCH' THEN 1 ELSE 0 END)/COUNT(*),1) AS match_pct
FROM porto_proc.v_three_way_match
GROUP BY bulan_po
ORDER BY bulan_po;

