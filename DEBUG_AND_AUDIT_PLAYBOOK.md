# Playbook Debug & Audit Aplikasi (Multi-Tool + Subagent)

Panduan ringkas dan **umum (bisa dipakai di aplikasi Web, Mobile/Flutter, Desktop, maupun Backend API apa saja)** untuk memetakan arsitektur kode, menjalankan audit paralel via subagent, dan memverifikasi bug logic/UI/performa dengan kombinasi tool otomatis.

---

## 1. Petakan Arsitektur Dulu dengan Graphify

Gunakan **Graphify** sebelum mengaudit agar fokus langsung ke file inti (*god nodes*), ketergantungan antar-modul, dan file yang baru berubah:

* **Build awal pada repo baru:**
  ```text
  /graphify .
  ```
* **Update incremental setelah edit kode:**
  ```text
  /graphify . --update
  ```
* **Cek laporan ringkas:** baca `graphify-out/GRAPH_REPORT.md` untuk melihat:
  * **God Nodes** (fungsi/class dengan edge terbanyak — biasanya titik rawan bug bila diubah)
  * **Import Cycles** (dependency melingkar)
  * **Graph Health Check** (pastikan 0 dangling/missing edges)

> **Catatan token:** Jika perubahan hanya pada file kode (`.py`, `.dart`, `.ts`, `.js`, dll.), cukup jalankan ekstraksi AST incremental — cepat dan **0 token LLM**.

---

## 2. Cara Mengaktifkan & Mengatur Subagent Audit Paralel

Agar hemat token dan cepat, jalankan **maksimal 2–3 subagent read-only** sesuai layer aplikasi.

### A. Lewat Prompt Langsung ke Agent Utama
Tulis instruksi spesifik yang membatasi ruang lingkup, durasi, dan format output:

```text
Spawankan 2 subagent tipe research (read-only) secara paralel:
1. "Backend Auditor": cek folder backend untuk bug SQL, race condition, validasi input, timezone UTC vs lokal, dan API contract.
2. "Frontend Auditor": cek UI/state untuk memory leak (Timer/Controller), filter/pagination tidak sinkron, eager rendering list besar, dan layout overflow mobile vs desktop.

Aturan ketat:
- Hanya laporkan bug nyata dengan path file, nomor baris, dan skenario reproduksi singkat.
- Jangan buat laporan panjang atau mengulang isi file.
```

### B. Tips Agar Subagent Tidak Boros Token
1. **Batasi folder/file target** (misal hanya `backend/` atau komponen tertentu) alih-alih menyuruh membaca satu repo penuh.
2. **Minta format poin singkat** (`file:baris — akar masalah — dampak`).
3. Jika sudah cukup atau terasa terlalu lama, **hentikan subagent** (`kill` / minta agent utama menghentikan) dan langsung lanjut ke perbaikan.
4. Untuk proyek besar yang butuh koordinasi banyak worker edit paralel, gunakan slash command `/teamwork` atau `/boost`.

---

## 3. Urutan Pengujian Lintas Tool (General Checklist)

Jalankan secara berurutan dari yang paling cepat ke end-to-end:

### Tahap 1 — Static & Syntax Check (Detik Pertama)
Tangkap typo, unused variable, type mismatch, dan sintaks rusak:
* **Python:** `python -m py_compile <file>.py` atau `ruff check .`
* **Flutter/Dart:** `flutter analyze`
* **TypeScript/JS:** `npx tsc --noEmit` / `npm run lint`

### Tahap 2 — Unit & Backend API Test (`pytest` / `unittest` / `vitest`)
Uji logika database, filter, pagination, dan rekonsiliasi data **tanpa menyentuh database asli**:
* Gunakan database sementara (`tmp_path` + `monkeypatch` di `pytest`) dan API test client (misal `fastapi.testclient.TestClient` atau `supertest`).
* Checklist wajib yang sering jadi bug logic:
  1. **Default saat startup**: nilai awal limit/filter selalu reset benar atau tersimpan sesuai spesifikasi.
  2. **Boundary & edge case**: halaman melebihi total halaman, limit tidak valid, string pencarian kosong, range tanggal/durasi di batas minimum & maksimum.
  3. **Concurrency / Race / Sync**: data dari 2 sumber (misal HP vs Laptop) memakai timestamp terbaru (`updated_at`) agar perubahan lama tidak menimpa perubahan baru.
  4. **Zero Deprecation Warnings**: perbaiki warning library sejak dini (misal `@app.on_event` -> `lifespan`, Pydantic `.dict()` -> `.model_dump()`).

### Tahap 3 — Component / Widget Test (`flutter test` / Testing Library)
Uji perilaku interaksi UI di memori (cepat dan deterministik):
* Posisi relatif & tata letak tombol di layar Desktop (`1280x900`) dan Mobile (`390x844`).
* Alur interaksi lengkap: buka filter -> ubah opsi -> angka total & badge langsung berubah.
* Gesture khusus (misal tahan 1 detik `startGesture` + `pump(1150ms)`, dialog/tanpa dialog).

### Tahap 4 — End-to-End Real Browser dengan Playwright (`playwright`)
Sering menangkap bug yang lolos di unit test! Jalankan browser headless asli (Chromium) ke build rilis web:
1. **Tangkap `page.on("pageerror")`** -> pastikan **0 uncaught JS exception**.
2. **Tangkap `page.on("console")`** -> periksa `console.error` (misal error CORS, aset hilang, atau **HTTP 429** karena komponen me-render ribuan gambar sekaligus alih-alih lazy `ListView.builder`).
3. **Tangkap `page.on("response")`** -> cek apakah ada endpoint internal gagal (`status >= 400`).
4. **Uji multi-viewport** (`1280x900` desktop dan `390x844` mobile) serta cek elemen interaktif benar-benar muncul dan bisa diklik.
5. **Selalu uji terhadap DB/server terisolasi** (atau kembalikan data uji setelah tes selesai) agar data produksi tidak kotor.

---

## 4. Checklist Cepat Bug yang Paling Sering Terjadi
- [ ] **Eager List Rendering**: Daftar panjang memakai `.map()` di dalam `Column`/`ListView` biasa -> ganti `ListView.builder` / virtualized list agar memori & network aman.
- [ ] **Async Stale Response**: Request lama datang lebih lambat daripada request baru -> pakai sequence counter (`_fetchSeq`) atau abort token.
- [ ] **Timer / Listener / Controller Leak**: Lupa `.cancel()` atau `.dispose()` saat widget/halaman ditutup.
- [ ] **Offline/Online State Drift**: Perubahan offline tidak ikut tersimpan atau tertimpa oleh respons `/state` server karena tidak ada merge timestamp.
- [ ] **Timezone Drift**: Tanggal lokal dibanding UTC di query range hari/minggu/bulan.
- [ ] **Mobile Overflow**: Teks panjang atau deretan tombol tidak memakai `Expanded`/`Flexible` atau `TextOverflow.ellipsis`.
