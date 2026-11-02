# Portofolio Procurement Analytics

Empat analisis atas siklus pembelian sapi bakalan, pakan, dan obat di sebuah pemasok daging sapi skala keluarga, dari pencocokan dokumen sampai biaya per kg karkas.

> **Data simulasi.** Seluruh angka berasal dari dataset simulasi yang meniru pola operasional pemasok daging sapi, bukan dari catatan perusahaan nyata. Analisis 4 menambahkan asumsi biologis dan biaya (pertambahan bobot, rendemen, biaya kandang, bunga modal).

**Halaman portofolio:** https://salwanmaulidina.github.io/procurement-analytics-portfolio/

## Temuan utama

Pemasok dengan skor scorecard tertinggi menanggung 71% eksposur faktur (Rp 281,8 jt dari Rp 399,6 jt). Skor berbasis frekuensi kejadian tidak menangkap besarnya rupiah, sehingga scorecard perlu satu komponen berbobot nilai.

## Isi analisis

| # | Analisis | Pertanyaan | Angka kunci |
|---|---|---|---|
| 1 | Three-way match | Apakah tagihan sesuai PO dan penerimaan barang? | Match rate 68,3%; eksposur Rp 399,6 jt |
| 2 | Purchase Price Variance | Mengapa harga berbeda dari standar? | PPV Rp 19,1 jt (0,58%) |
| 3 | OTIF dan scorecard pemasok | Seberapa andal pemasok? | OTIF 63,3% (CI 95%: 53,9–71,8%) |
| 4 | TCO per kg karkas | Berapa biaya riil 1 kg karkas? | ±Rp 115 rb per kg karkas |

## Struktur folder

```
index.html            halaman portofolio (dibuka lewat GitHub Pages)
notebooks/            notebook Google Colab (00 muat data ke BigQuery, analisis 1-3, analisis 4)
sql/                  skrip BigQuery SQL untuk analisis 1-3 (tanpa DML)
data/data_csv.zip     dataset simulasi (6 file CSV)
hasil/                CSV keluaran notebook (analisis 4)
docs/                 panduan menjalankan BigQuery + Colab
```

## Cara menjalankan

Ada dua jalur. Hasilnya sama.

**Jalur CSV (paling mudah, tanpa akun Google Cloud)**

1. Buka notebook analisis di Google Colab.
2. Biarkan `SUMBER = "csv"`.
3. Run all. Saat diminta, unggah `data/data_csv.zip`.

**Jalur BigQuery (sandbox gratis, tanpa billing)**

1. Buka `notebooks/00_muat_data_ke_bigquery.ipynb` di Colab, isi `PROJECT_ID` (ID project, bukan nama project), lalu unggah `data/data_csv.zip`. Hasilnya 6 tabel dan view `param_general`.
2. Di BigQuery Console, jalankan `sql/01`, `sql/02`, `sql/03` berurutan (satu tab per file).
3. Di notebook analisis, ubah `SUMBER = "bigquery"` dan isi `PROJECT_ID`.

Tabel sandbox kedaluwarsa 60 hari, karena itu hasil juga disimpan sebagai CSV di `hasil/`.

| Notebook | Buka di Colab |
|---|---|
| Analisis 1-3 | [![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/salwanmaulidina/procurement-analytics-portfolio/blob/main/notebooks/analisis_1_3_three_way_ppv_otif.ipynb) |
| Analisis 4 | [![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/salwanmaulidina/procurement-analytics-portfolio/blob/main/notebooks/analisis_4_tco_per_kg_karkas.ipynb) |

## Batas analisis

- Dataset simulasi dengan 112 baris PO dan 5–19 baris per pemasok, sehingga interval kepercayaan lebar dan peringkat belum stabil.
- Analisis 4 bergantung pada asumsi pertambahan bobot, rendemen, dan biaya kandang. Parameter ini bukan data; ganti dengan angka riil sebelum dipakai untuk keputusan.
- Kode belum diuji pada project BigQuery sungguhan. Aturan sandbox (tanpa DML, tabel kedaluwarsa 60 hari) diambil dari dokumentasi pihak ketiga.

## Alat

BigQuery SQL, Python (pandas, scipy, matplotlib), Google Colab.
