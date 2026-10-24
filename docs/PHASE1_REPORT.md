# LAPORAN FASE 1 — Proyek Launcher (APK)

Status: **selesai**. Semua uji otomatis hijau, APK ter-*sign* dan bisa dipasang,
dan rilis demo sudah terbit sehingga seluruh pipa unduh → verifikasi → muat
paket bisa dicoba di HP hari ini tanpa hosting sendiri.

* Repo rilis: <https://github.com/KyokoApp/GodotMe/releases/tag/demo-v0.1.0>
* Manifest yang dibaca launcher secara default:
  <https://github.com/KyokoApp/GodotMe/releases/latest/download/version.json>
* Pull Request kerja: [#3](https://github.com/KyokoApp/GodotMe/pull/3)

---

## 1. Yang dibangun

Dua proyek Godot terpisah, sesuai aturan brief bahwa APK tidak boleh ikut berubah
saat konten diperbarui:

| Proyek | Isi | Keluaran | Ukuran |
| --- | --- | --- | --- |
| `launcher/` (A) | splash, layar update bertema, pengunduh + resume, verifikator SHA-256, pemuat paket, tombol MAIN | `re-traveller-launcher.apk` | **29.423.721 byte (± 29,4 MB)**, arm64-v8a |
| `game/` (B) | seluruh game | 6 paket `.pck` | lihat tabel paket di bawah |

Launcher **tidak memuat** logika permainan, sprite, nama karakter, atau data
dunia apa pun. Satu-satunya hal yang ia tahu tentang game: nama paket, urutan
muat, dan path scene boot (`res://game/Main.tscn`) — kontraknya ditulis di
[`GAME_CONTRACT.md`](GAME_CONTRACT.md).

Paket yang dipublikasikan pada rilis demo:

| Paket | Ukuran | Urutan muat | Isi pada demo |
| --- | --- | --- | --- |
| `core_100.pck` | 26.796 B | 10 | kode inti + scene boot |
| `characters_100.pck` | 1.164 B | 20 | data karakter |
| `enemies_100.pck` | 612 B | 30 | data musuh |
| `world_100.pck` | 1.170.300 B | 40 | diorama contoh |
| `ui_100.pck` | 26.540 B | 50 | tekstur UI game |
| `audio_100.pck` | 352 B | 60 | audio |

Total unduhan pertama ± 1,23 MB; itulah yang membuat APK tetap kecil dan
ruang penyimpanan di HP tidak terpakai dua kali.

### Izin & konfigurasi Android

* Izin: **hanya** `INTERNET` + `ACCESS_NETWORK_STATE` (yang kedua dipakai untuk
  membedakan "offline" dari "server mati" sebelum memulai unduhan).
* Landscape, `gl_compatibility`, `textures/vram_compression/import_etc2_astc=true`
  agar tekstur terkompresi dibaca GPU HP.
* Tanpa GDExtension, tanpa plugin native, tanpa `.so` tambahan — semua kode
  bisa diperbarui lewat PCK.
* Tampilan: perkamen, kayu, logam tua; wordmark bitmap, bukan font bawaan Godot.

---

## 2. Alur yang dijalankan launcher

```
buka APP
  └─ sentinel boot_ok.json ada?  → tidak: bump gagal-boot, mungkin rollback
  └─ versi terpasang valid?      → ya : MAIN aktif seketika (main offline-first)
  └─ GET version.json (HTTPS)    → gagal: pakai versi valid terakhir (OFFLINE_READY)
       └─ min_launcher_version > versi APK? → LAUNCHER_UPDATE_REQUIRED (versi lama tetap main)
       └─ verifikasi tanda tangan manifest bila ada (RSA-SHA256, kunci publik di Config.gd)
       └─ hitung delta: paket yang nama/versi/hash-nya berubah saja
            └─ cek ruang kosong ≥ total paket + margin
            └─ unduh per paket ke <name>.pck.tmp, HTTP Range bila .tmp sudah ada
            └─ SHA-256 streaming; salah → hapus .tmp, ulangi sekali, lalu ERROR
            └─ pindahkan .tmp → paket content-addressed, tulis versi aktif
       └─ load_resource_pack() berurutan → change_scene_to_file(scene boot)
  └─ game menulis boot_ok.json; 3 kegagalan beruntun → rollback 1 versi
```

Detail teknis yang penting:

* **Versi lokal** disimpan di `user://` (`Store.gd`), termasuk daftar versi baik
  dan versi yang ditandai rusak, plus GC paket yang tak terpakai.
* **Resume** memakai `Range: bytes=<offset>-`; server yang tidak mendukung Range
  (balas 200) ditangani dengan memulai ulang paket itu saja, bukan seluruh unduhan.
* **Hash salah** tidak pernah dipasang: `.tmp` dihapus, tidak ada versi aktif
  yang berubah, dan paket itu dicoba ulang satu kali sebelum menyerah.
* **Rollback** bekerja antar-proses lewat sentinel `boot_ok.json`, karena proses
  yang `OS.crash()` tidak bisa melaporkan apa pun.
* Semua angka di UI (ukuran, kecepatan, sisa waktu) diformat bahasa Indonesia.

---

## 3. Hasil uji (semua otomatis, log di PR #3)

`tools/run_launcher_tests.sh` menjalankan 11 skenario; tiap skenario memakai
sandbox `user://` sendiri dan server uji lokal (`tools/testserver.py`) yang
mendukung Range, throttle, dan penghitung permintaan.

| # | Skenario wajib dari brief | Kasus uji | Hasil |
| --- | --- | --- | --- |
| 1 | Instalasi pertama | `first_install` | ✅ 7 check |
| 2 | Update normal | `partial_update` (1.0.0 → 1.1.0) | ✅ 8 check |
| 3 | Update sebagian / delta | `partial_update` | ✅ hanya paket yang berubah diunduh (server mencatat 1 permintaan) |
| 4 | Unduhan terputus lalu lanjut | `resume` | ✅ 7 check; lanjut dari offset, bukan dari nol |
| 5 | Hash salah | `bad_hash` | ✅ 5 check; `.tmp` dihapus, tidak ada versi aktif |
| 6 | Offline dengan versi lama | `offline` | ✅ 5 check; state `OFFLINE_READY`, MAIN aktif |
| 7 | Rollback saat game rusak | `crash` | ✅ 8 check; proses game mati → launcher rollback ke versi sebelumnya |
| 8 | Save utuh setelah update | `partial_update` | ✅ `user://save/slot1.json` identik sebelum/sesudah |
| 9 | Manifest menuntut launcher baru | `launcher_too_old` | ✅ 2 check; versi lama tetap bisa dimainkan |
| 10 | Tanda tangan manifest | `signed_ok`, `signed_bad` | ✅ 2 + 2 check; rusak ditolak |
| 11 | Versi rusak tidak dipasang ulang | `blocked` | ✅ 5 check; ditahan sampai pengguna menekan Coba Lagi |
| 12 | Unit (format, URL, hash, validasi manifest) | `unit` | ✅ 17 check |

Tidak ada kegagalan. Rincian cara uji + tabel manual di HP ada di
[`TEST_PLAN.md`](TEST_PLAN.md).

Bukti visual (diambil otomatis oleh CI, 1280×720):

| Berkas | Isi |
| --- | --- |
| `docs/screenshots/01_menyiapkan.png` | splash + memeriksa versi |
| `docs/screenshots/02_mengunduh.png` | progress bar, ukuran, kecepatan (dengan tombol Jeda aktif) |
| `docs/screenshots/03_siap.png` | enam paket siap, tombol MAIN |
| `docs/screenshots/04_kendala.png` | unduhan gagal + Coba Lagi |
| `docs/screenshots/05_luring.png` | mode luring memakai versi valid terakhir |
| `docs/screenshots/06_pemulihan.png` | modal pemulihan otomatis setelah game gagal boot |

### Status CI terakhir

| Job | Hasil |
| --- | --- |
| `parse check` (semua skrip GDScript) | ✅ |
| 11 × `test / …` (matriks skenario) | ✅ |
| `screenshots` | ✅ |
| `build launcher APK` (debug + release, keduanya `apksigner verify` = 0) | ✅ |
| `release-demo` (bangun 6 paket → APK → terbitkan rilis → verifikasi URL live) | ✅ |

Catatan perbaikan penting selama Fase 1: ekspor *release* sebelumnya menulis APK
tetapi gagal menandatanganinya, dan CI tidak menyadarinya karena kode keluaran
diambil setelah perintah lain. Sekarang kunci rilis diberikan lewat variabel
lingkungan yang memang dibaca Godot
(`GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD`), kode keluaran ekspor
diperiksa, dan setiap APK diverifikasi dengan `apksigner verify`.

---

## 4. Cara menjalankan & mencoba

### a. Di HP (paling cepat, tanpa alat apa pun)

1. Buka <https://github.com/KyokoApp/GodotMe/releases/tag/demo-v0.1.0>.
2. Unduh `re-traveller-launcher.apk`, izinkan "instal dari sumber tidak dikenal".
3. Buka aplikasi → launcher memeriksa `version.json` dari rilis itu (default
   `MANIFEST_URL`), menampilkan changelog, lalu mengunduh 6 paket (± 1,23 MB).
4. Tekan **MAIN** → dunia contoh dimuat dari paket `.pck`.

### b. Uji lokal (pengembang)

```bash
# semua skenario (butuh Godot 4.7.2 + python3)
GODOT=/path/to/godot-4.7.2 tools/run_launcher_tests.sh

# satu skenario saja
GODOT=/path/to/godot-4.7.2 tools/run_launcher_tests.sh resume

# tangkapan layar ulang
CAPTURES=/tmp/shots GODOT=/path/to/godot-4.7.2 tools/run_launcher_tests.sh capture
```

Menjalankan launcher di desktop terhadap server uji:

```bash
python3 tools/testserver.py --dir /tmp/fixtures --port 8060 &
GODOT=/path/to/godot-4.7.2 godot --path launcher -- --manifest=http://127.0.0.1:8060/v100.json
```

### c. Merilis konten baru (semuanya bisa dari HP lewat GitHub Actions)

```bash
python3 tools/make_release.py --version 1.2.0 \
    --packs core=build/core.pck characters=build/characters.pck \
    --out dist/v1.2.0 --sign-key ~/retraveller_private.pem
```

Lalu unggah isi `dist/v1.2.0/` (manifest + `packs/*.pck`). Langkah lengkap,
termasuk ekspor PCK dari Godot dan kebijakan hosting, ada di
[`BUILD_AND_RELEASE.md`](BUILD_AND_RELEASE.md).
Untuk demo ini, seluruh rantai itu dijalankan otomatis oleh
`.github/workflows/release-demo.yml` (ubah satu baris `RELEASE_DEMO` untuk
membangun ulang).

---

## 5. Risiko & hal yang perlu diketahui

1. **Kunci tanda tangan demo** memakai kunci debug Android. Untuk distribusi
   nyata, buat keystore sendiri dan simpan sebagai secret CI; APK yang sudah
   dipasang hanya bisa diperbarui oleh APK dengan kunci yang sama.
2. **Google Play** membatasi aplikasi yang mengunduh kode yang dapat dieksekusi
   (kebijakan "Deceptive Behavior"/"Device and Network Abuse" terkait dynamic
   code). Pola launcher + PCK seperti ini umum untuk sideload/itch.io, tapi
   untuk Play sebaiknya pakai Play Asset Delivery atau kirim seluruh konten
   lewat pembaruan APK. Keputusan distribusi diserahkan ke Anda — risikonya
   dicatat di `BUILD_AND_RELEASE.md`.
3. **Resume unduhan** bergantung pada server yang mengirim `Accept-Ranges` dan
   membalas `206`. GitHub Releases mendukung Range; kalau hosting Anda tidak,
   unduhan tetap benar tetapi dimulai dari awal paket tersebut.
4. **Tanda tangan manifest bersifat opsional**: bila rilis tidak menyertakan
   `version.json.sig`, launcher tetap memverifikasi SHA-256 tiap paket tetapi
   tidak bisa membuktikan asal manifest. Kunci publiknya ada di `Config.gd`.
5. **Aset contoh di `game/`** hanya untuk membuktikan pipa paket; aset karakter
   sesungguhnya (spritesheet PNG, 48×64, palet 24–32 warna) belum dipilih dan
   akan dikonfirmasi ke Anda di awal Fase 2 sesuai brief.
6. `min_launcher_version` hanya bisa menaikkan versi; tidak ada mekanisme
   memaksa pembaruan APK otomatis (memang tidak diizinkan oleh Android tanpa
   izin tambahan).

---

## 6. Batas Fase 1 (tidak dikerjakan di sini)

* Tidak ada gameplay, kamera HD-2D, peta, dialog, atau sistem battle — itu Fase 2+.
* Tidak ada akun, cloud save, atau analytics.
* Belum ada lokalisasi selain bahasa Indonesia.
* Belum ada CI untuk build iOS/desktop.

Fase 1 berhenti di sini menunggu arahan Anda untuk Fase 2.
