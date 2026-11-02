CREATE SCHEMA IF NOT EXISTS porto_proc OPTIONS (location = 'asia-southeast2');
CREATE OR REPLACE TABLE porto_proc.supplier (
    supplier_id STRING, supplier_name STRING, kategori_utama STRING, tipe_supplier STRING, terms_hari INT64, tarif_ppn FLOAT64, status_pkp STRING
); 
CREATE OR REPLACE TABLE porto_proc.item (
    item_id STRING, item_name STRING, kategori STRING, uom STRING, harga_acuan FLOAT64
);
CREATE OR REPLACE TABLE porto_proc.param_tolerance (
    kategori STRING,
      tol_gr_vs_po FLOAT64,   -- toleransi qty GR vs PO (±)
      tol_inv_vs_gr FLOAT64,  -- toleransi qty faktur vs GR (±)
      tol_harga FLOAT64       -- toleransi harga faktur vs PO (±)
);
CREATE OR REPLACE VIEW porto_proc.param_general AS
SELECT
  DATE '2026-10-15' AS cutoff_date,
    14                AS thr_followup_hari,  -- GR belum difakturkan > N hari -> SEDANG
    14                AS thr_stale_hari,     -- PO terbuka lewat tgl kirim > N hari -> SEDANG
    5000000.0         AS thr_eksposur,
    1.0               AS tol_pajak,
    3.0               AS z_outlier;
CREATE OR REPLACE TABLE porto_proc.po_line (
    po_line_id STRING, po_id STRING, line_no INT64, po_date DATE, supplier_id STRING, item_id STRING,
    qty_po FLOAT64, uom STRING, ekor_po INT64, harga_po FLOAT64, nilai_po FLOAT64,
    terms_hari INT64, tgl_kirim_diharapkan DATE
);
CREATE OR REPLACE TABLE porto_proc.gr_line (
    gr_line_id STRING, gr_no STRING, gr_date DATE, po_line_id STRING, supplier_id STRING,
    qty_diterima FLOAT64, ekor_diterima INT64, surat_jalan STRING, lokasi_terima STRING, catatan STRING
);
CREATE OR REPLACE TABLE porto_proc.inv_line (
    inv_line_id STRING, inv_no STRING, inv_date DATE, tgl_input DATE, supplier_id STRING, po_line_id STRING,
    qty_faktur FLOAT64, harga_faktur FLOAT64, jumlah_faktur FLOAT64, ppn_faktur FLOAT64, total_faktur FLOAT64
);
