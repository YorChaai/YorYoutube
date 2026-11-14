# Aturan Kerja Proyek YorYoutube

Setiap kali memproses chat atau permintaan perbaikan/penambahan fitur pada proyek ini:

1. **Selalu Update & Baca Graphify Lebih Dulu**
   - Sebelum menganalisis bug, menjawab pertanyaan kode, atau mengedit file, periksa perubahan file kode terbaru dan perbarui knowledge graph di `graphify-out/` secara incremental (`graphify --update` / AST re-extraction untuk file berubah) jika sudah tertinggal.
   - Gunakan hasil Graphify (`graphify-out/GRAPH_REPORT.md` dan `graphify query` terhadap `graphify-out/graph.json`) **bersamaan dengan memahami permintaan user** untuk memetakan fungsi, relasi, dan lokasi file sebelum membuka/mengedit kode.
   - Setelah selesai mengubah file kode dan memverifikasi tes, perbarui kembali Graphify agar tetap sinkron.

2. **Dilarang Menghapus Data / Perubahan Lokal (`No git checkout`)**
   - **JANGAN PERNAH** menjalankan `git checkout`, `git reset --hard`, `git restore`, `git clean`, atau perintah apa pun yang membuang perubahan lokal user yang belum di-commit.
   - Jangan menimpa atau menghapus data lokal maupun database pengguna (seperti `backend/youtube_personal.db` atau aset lokal lain) kecuali atas perintah eksplisit user.
   - Saat melakukan `git add`, pilih file spesifik yang relevan saja—jangan membuang atau mengikutsertakan file sementara/tidak terkait secara sembarangan.
