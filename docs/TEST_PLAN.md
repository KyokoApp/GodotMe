# TEST PLAN & HASIL UJI — Launcher (Fase 1)

Semua uji berjalan otomatis di GitHub Actions (11 job + parse check), dan bisa
dijalankan lokal dengan satu perintah. Log tiap job otomatis ditempel ke Pull
Request supaya bisa diperiksa dari HP.

```bash
GODOT=/path/to/godot-4.7.2 tools/run_launcher_tests.sh           # semua skenario
GODOT=/path/to/godot-4.7.2 tools/run_launcher_tests.sh resume    # satu skenario
CAPTURES=/tmp/shots GODOT=... tools/run_launcher_tests.sh capture # tangkapan layar
```

Skrip ini mengimpor dua proyek, membangun fixture (`launcher/tests/FixtureBuilder.gd`),
menjalankan `tools/testserver.py` (mendukung HTTP Range, throttle, jumlah
request), lalu menjalankan tiap skenario di sandbox `user://` sendiri.

## Skenario wajib dari brief

| # | Yang diuji (brief §1.5) | Cara diuji | Hasil |
| --- | --- | --- | --- |
| 1 | Instalasi pertama | `first_install`: manifest v1.0.0, enam paket baru | ✅ 7 check lulus |
| 2 | Update normal | `partial_update`: v1.0.0 → v1.1.0 | ✅ 8 check lulus |
| 3 | Update sebagian (delta) | `partial_update`: hanya `characters.pck` berubah | ✅ jumlah berkas 6 → 7 (hanya satu paket baru); server mencatat 1 permintaan untuk paket itu |
| 4 | Unduhan terputus lalu lanjut | `resume`: unduhan 1,1 MB diperlambat, dijeda di ~25%, dilanjutkan | ✅ 7 check lulus; log "Melanjutkan …" + berkas `.tmp` bertambah, bukan mulai dari nol |
| 5 | Hash salah | `bad_hash`: manifest dengan `sha256` yang dirusak | ✅ ERROR `kind=hash`, `.tmp` dihapus, tidak ada versi aktif |
| 6 | Offline dengan versi lama | `offline`: v1.0.0 terpasang, lalu manifest server mati | ✅ state `OFFLINE_READY`, tombol MAIN aktif |
| 7 | Rollback saat game rusak | `crash`: v1.1.0 sehat → v1.2.0 berisi paket yang sengaja `OS.crash()` saat boot → proses mati → launcher dibuka lagi | ✅ proses memang mati (exit ≠ 0), launcher mendeteksi sentinel, rollback ke v1.1.0, v1.2.0 ditandai rusak (8 check) |
| 8 | Save tetap utuh setelah update | `partial_update`: tulis `user://save/slot1.json` (`gold: 4242`) sebelum update | ✅ data sama setelah update |
| 9 | Manifest butuh launcher baru | `launcher_too_old`: `min_launcher_version = 99` | ✅ state `LAUNCHER_UPDATE_REQUIRED`, versi lama tetap bisa dimainkan |
| 10 | Tanda tangan manifest | `signed_ok` (RSA-SHA256 valid) dan `signed_bad` (tanda tangan dirusak) | ✅ valid diterima, rusak ditolak |
| 11 | Versi bermasalah tidak dipasang ulang otomatis | `blocked`: v1.1.0 ditandai rusak, manifest menawarkan v1.1.0 | ✅ ditahan; tombol Coba Lagi memaksa pasang ulang |
| 12 | Sentuhan benar-benar sampai ke tombol | `ui_input`: menekan tombol lewat `Viewport.push_input` (bukan memanggil fungsi) | ✅ 11 check; MAIN & tombol sekunder bereaksi, modal menahan latar, dan tombol aktif lagi setelah modal ditutup |

> **Kenapa ada skenario 12:** pada APK pertama, menekan **MAIN** tidak
> menghasilkan apa pun di HP. Penyebabnya `CenterContainer` selebar layar di
> dalam lapisan modal yang selalu `visible` — sentuhan ditelan sebelum sampai ke
> tombol. Skrip tangkapan layar tidak menemukannya karena memanggil handler
> secara langsung, jadi sekarang ada uji yang menekan tombol lewat jalur input
> sungguhan.

Tambahan: `unit` (17 check) menguji format ukuran/kecepatan bahasa Indonesia,
resolusi URL relatif/absolut, SHA-256, dan validasi manifest (kolom hilang,
nama paket ganda, `sha256` salah, path tidak aman).

## Bukti tambahan yang dikumpulkan otomatis

* **Tangkapan layar** (`docs/screenshots/`): menyiapkan, mengunduh, siap,
  kendala, mode luring, modal pemulihan otomatis, **dan layar dunia setelah MAIN
  ditekan** (`07_dunia.png`, diambil dari proyek game langsung) — semua dengan GL
  software (llvmpipe) pada 1280×720.
* **Audit permintaan server**: satu paket yang berubah hanya diminta sekali
  selama delta update; paket yang tidak berubah tidak diunduh ulang.
* **APK**: diekspor setiap push (debug + release), diverifikasi dengan
  `apksigner verify`, lalu **isi APK-nya diperiksa**: CI membaca `build_id` dari
  `launcher/project.godot` dan memastikan nilai itu benar-benar ada di dalam
  setiap APK (`assets/project.binary`). Artefak basi tidak mungkin dipublikasikan
  tanpa ketahuan, dan nilai yang sama tampil di jurnal launcher supaya pengguna
  bisa memastikan build mana yang terpasang.

## Verifikasi end-to-end di rilis sungguhan

Job `release-demo` (`.github/workflows/release-demo.yml`) tidak berhenti pada
"APK berhasil diekspor". Setelah rilis terbit, ia mengambil
`https://github.com/<repo>/releases/latest/download/version.json` persis seperti
launcher, lalu meminta 64 byte pertama setiap paket dengan header
`Range: bytes=0-63` untuk memastikan aset benar-benar bisa diunduh dan mendukung
resume. Hasil terakhir: 6/6 paket menjawab `200/206`, rilis `demo-v0.1.0`
berisi `version.json` + 6 `.pck` + `re-traveller-launcher.apk` (29.428.024 byte).

## Uji manual di HP (yang tidak bisa diotomasi di sini)

| Uji | Langkah | Yang harus terlihat |
| --- | --- | --- |
| Instal & buka | pasang APK, buka | splash crest → layar update bertema, bukan layar default Godot |
| Update normal | rilis v baru di hosting, buka launcher | progress + kecepatan + sisa waktu; tombol MAIN aktif |
| Putus jaringan di tengah unduhan | mode pesawat 10 detik lalu nyalakan | unduhan lanjut, bukan dari 0% |
| Offline | mode pesawat, buka launcher | "Mode luring", MAIN tetap aktif, versi lama jalan |
| Rotasi/notch | putar layar | tetap landscape, UI tidak tertutup notch |
| Ukuran & kecepatan | — | APK < 35 MB, layar pertama < 2 detik di perangkat kelas menengah |

## Daftar berkas uji

```
launcher/tests/TestRunner.gd      # 12 skenario + screenshot capture
launcher/tests/FixtureBuilder.gd  # membuat 6 paket + 8 manifest uji
tools/run_launcher_tests.sh       # driver (lokal & CI)
tools/testserver.py               # server uji: Range, throttle, audit request
.github/workflows/ci.yml          # matrix 11 job + parse check + screenshot + APK
```
