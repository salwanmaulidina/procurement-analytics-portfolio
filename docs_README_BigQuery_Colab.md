# Panduan BigQuery dan Google Colab (versi gratis)

Panduan menjalankan analisis 1-4 dengan **BigQuery sandbox** dan **Google Colab**, tanpa billing dan tanpa kartu kredit. Semua data adalah simulasi.

## 1. Pilih jalur

| | Jalur A: CSV | Jalur B: BigQuery |
|---|---|---|
| Butuh akun Google Cloud | Tidak | Ya (project sandbox) |
| Yang dijalankan | Notebook analisis | Notebook 00, file SQL, notebook analisis |
| Pengaturan `SUMBER` | `"csv"` | `"bigquery"` |
| Cocok untuk | Mencoba cepat, melihat hasil | Menunjukkan keterampilan SQL di BigQuery |

Hasil analisis sama di kedua jalur. Notebook dan SQL menghitung logika yang sama.

## 2. Jalur A: CSV saja (paling mudah)

1. Buka notebook di Colab lewat tombol di `README.md`.
2. Pastikan sel pengaturan berisi `SUMBER = "csv"`. `PROJECT` / `PROJECT_ID` tidak perlu diisi.
3. Jalankan semua sel (*Runtime > Run all*). Saat diminta, unggah `data/data_csv.zip` (zip berisi folder `csv/` dengan 6 file).
4. Urutan: `analisis_1_3_three_way_ppv_otif.ipynb`, lalu `analisis_4_tco_per_kg_karkas.ipynb`.
5. Unduh isi folder `hasil/` (ikon folder di sisi kiri Colab) bila ingin menyimpan keluaran analisis 4.

## 3. Jalur B: BigQuery sandbox

### 3.1 Siapkan project
1. Buka <https://console.cloud.google.com/bigquery> dengan akun Google. Terima syarat penggunaan.
2. Buat project baru. Pilih sandbox (tanpa menambahkan billing).
3. Catat **Project ID**: klik nama project di bar atas, lalu salin kolom **ID**. Jangan salin kolom **Name**; keduanya bisa berbeda.

### 3.2 Muat data (notebook 00)
1. Buka `notebooks/00_muat_data_ke_bigquery.ipynb` di Colab.
2. Isi `PROJECT_ID` dengan Project ID. Biarkan `DATASET = "porto_proc"` dan `LOCATION = "asia-southeast2"`.
3. Run all, login Google saat diminta, lalu unggah `data/data_csv.zip`.
4. Hasil: dataset `porto_proc` berisi 6 tabel (`supplier`, `item`, `param_tolerance`, `po_line`, `gr_line`, `inv_line`) dan view `param_general`. Notebook mencocokkan jumlah baris (112, 116, 110, 16, 9, 4).

Notebook ini memakai **load job** yang gratis di sandbox. Alternatif tanpa notebook: jalankan `sql/00_setup.sql` di Console lalu unggah tiap CSV lewat *Create table > Upload* (*Header rows to skip* = 1).

### 3.3 Jalankan SQL di Console
Buka satu tab query per file, tempel isinya, dan jalankan:

| Urutan | File | Isi |
|---|---|---|
| (opsional) | `sql/00_setup.sql` | Dataset, tabel kosong, view `param_general`. Lewati bila sudah memakai notebook 00. |
| 1 | `sql/01_three_way_match.sql` | View `v_three_way_match` dan Q1-Q7 |
| 2 | `sql/02_ppv.sql` | View `v_ppv` dan Q1-Q7 |
| 3 | `sql/03_otif_scorecard.sql` | View `v_otif` dan Q1-Q8. **Butuh view dari file 01.** |

Cara menjalankan per tab: blok bagian `CREATE OR REPLACE VIEW ...;` lalu klik **Run** (tombol berubah jadi *Run selected*). Setelah itu blok satu query (Q1, Q2, ...) dan jalankan satu per satu. Simpan tiap tab lewat **Save query**.

P-value uji-t, ANOVA, dan regresi tidak tersedia di SQL BigQuery. SQL menghasilkan statistiknya; p-value dihitung di notebook Python.

### 3.4 Notebook analisis dari tabel BigQuery
Di notebook analisis, ubah `SUMBER = "bigquery"` dan isi `PROJECT` / `PROJECT_ID`. Notebook membaca tabel dengan `SELECT` biasa.

## 4. Nama dataset dan lokasi

| Pengaturan | Nilai di repositori | Harus sama dengan |
|---|---|---|
| `DATASET` | `porto_proc` | Nama dataset di BigQuery dan awalan tabel di semua file `.sql` |
| `LOCATION` | `asia-southeast2` (Jakarta) | *Data location* dataset (Console: klik dataset > Details) |
| `PROJECT_ID` | diisi sendiri | Project ID, bukan nama project |

Bila memakai nama atau lokasi lain, ubah di keempat notebook dan di semua file `.sql` (di Console: Ctrl+H untuk cari-ganti).

## 5. Batas sandbox dan penyesuaian kode

Kode awal memakai fitur yang butuh billing. Penyesuaian yang dilakukan, tanpa mengubah logika analisis:

| Fitur berbayar | Penggantinya |
|---|---|
| `INSERT` untuk tabel parameter (DML) | `param_general` berupa **view** berisi konstanta |
| `bq load` di Cloud Shell | Notebook 00 (load job) atau unggah lewat Console |
| `CREATE TABLE AS` untuk staging | `SELECT` biasa, atau padanan pandas di mode CSV |
| BigQuery Storage API | `to_dataframe(create_bqstorage_client=False)` |
| Tipe `Int64`/`Float64` nullable dari BigQuery | `_samakan_dtype()` mengubahnya ke numpy biasa agar hasil sama dengan mode CSV |

Batas lain: tabel sandbox kedaluwarsa dalam 60 hari. Karena itu keluaran analisis disimpan juga sebagai CSV di folder `hasil/`. Jalankan ulang notebook 00 bila tabel hilang.

## 6. Status pengujian

- **Mode CSV:** notebook analisis 1-3 dan 4 sudah dijalankan di Google Colab tanpa error; keluarannya tersimpan di notebook.
- **SQL:** logika 22 query diuji dengan mesin SQL tiruan (DuckDB) dan identik dengan versi sebelum penyesuaian.
- **Mode BigQuery di notebook:** diuji dengan klien BigQuery tiruan; hasilnya sama dengan mode CSV baris demi baris.
- **BigQuery sungguhan:** belum dikonfirmasi. Aturan sandbox (tanpa DML, tabel kedaluwarsa 60 hari) diambil dari dokumentasi pihak ketiga, bukan dari halaman resmi Google. Bagian yang paling mungkin perlu penyesuaian: `CREATE SCHEMA ... OPTIONS(...)`, `CREATE VIEW`, dan load job.

*Perbarui bagian ini setelah Anda menjalankannya di project sendiri.*

## 7. Pemecahan masalah

| Pesan atau gejala | Penyebab dan solusi |
|---|---|
| `Not found: Dataset ... was not found in location ...` | `LOCATION` tidak sama dengan lokasi dataset. Cek *Data location* di Details dataset, lalu samakan di notebook. |
| `Not found: Dataset <project>:portofolio_procurement` | Masih ada sisa nama dataset lama di file SQL atau notebook. Cari `portofolio_procurement` dan ganti dengan `porto_proc`. |
| `Project ... not found` atau 403 | `PROJECT_ID` diisi nama project. Pakai kolom **ID**. Pastikan login dengan akun pemilik project. |
| Error DML / billing (`INSERT`, `UPDATE`, `DELETE`, `MERGE`) | Fitur itu tidak ada di sandbox. Gunakan load job (notebook 00) dan view, bukan DML. |
| `Not found: Table ...` setelah beberapa minggu | Tabel sandbox kedaluwarsa 60 hari. Jalankan ulang notebook 00. |
| Query di `sql/03` gagal: view `v_three_way_match` tidak ada | Jalankan `sql/01_three_way_match.sql` lebih dulu. |
| `FileNotFoundError` di mode CSV | Zip belum diunggah, atau tidak berisi folder `csv/`. Unggah `data/data_csv.zip`. |
| Hasil mode `bigquery` berbeda dari mode `csv` | Pastikan jumlah baris tabel benar (notebook 00 menampilkannya) dan lokasi dataset sama. Kirim selisihnya agar bisa ditelusuri. |

## 8. Menyimpan hasil ke GitHub

1. Setelah notebook dijalankan: *File > Download > Download .ipynb*. Berkas yang diunduh memuat tabel dan grafik, sehingga terlihat langsung di GitHub.
2. Kembalikan `PROJECT_ID` ke teks placeholder sebelum mengunduh bila tidak ingin ID project tampil di repositori publik.
3. Unggah notebook ke `notebooks/`, SQL ke `sql/`, dan CSV hasil ke `hasil/`.
