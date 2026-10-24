# CREDITS — Re - Traveller

Semua aset di proyek ini **orisinil** atau berlisensi bebas. Tidak ada aset,
karakter, nama, atau UI dari Octopath Traveler (atau game lain) yang disalin.

## Font

| Berkas | Keluarga | Lisensi | Sumber |
| --- | --- | --- | --- |
| `PixelifySans-Regular.woff2`, `PixelifySans-SemiBold.woff2`, `PixelifySans-LatinExt.woff2` | Pixelify Sans | SIL Open Font License 1.1 | npm `@fontsource/pixelify-sans` (5.3.0) |
| `Jersey15-Regular.woff2` | Jersey 15 | SIL Open Font License 1.1 | npm `@fontsource/jersey-15` (5.3.0) |

Teks lisensi lengkap ada di `launcher/ui/fonts/OFL-pixelify-sans.txt` dan
`launcher/ui/fonts/OFL-jersey-15.txt`.

Keputusan tipografi: **satu keluarga** (Pixelify Sans) dipakai untuk seluruh UI.
Regular untuk teks isi, SemiBold untuk wordmark dan tombol aksi. Jersey 15
disimpan sebagai cadangan untuk angka damage/harga nanti. Font blackletter
(Jacquard 12) sempat dipakai lalu **dibuang**: hasil uji baca pada layar 720p
membuat kata "TRAVELLER" terbaca "TKAVELLEK", jadi tidak layak untuk UI.

## Seni & ilustrasi

| Aset | Cara dibuat | Catatan |
| --- | --- | --- |
| `launcher/ui/textures/logo_crest.png` | Gambar orisinal dibuat khusus untuk proyek ini dengan model gambar AI (24 Okt 2026), lalu diolah `tools/gen_logo.py` menjadi pixel art 256×256 (downscale integer + snap ke palet 32 warna) | Lambang kompas, perisai, jalan setapak, bintang, dan ranting oak. Tidak meniru lambang game mana pun. |
| `launcher/ui/textures/bg_sky.png` | Sama seperti di atas, lalu di-crop 16:9 dan diperkecil dua tahap ke 1280×720 | Pemandangan perbukitan, kastil, desa jerami, jalan setapak — fantasi klasik, bukan sci-fi. |
| `launcher/ui/textures/logo_wordmark.png` | Dirender dari font Pixelify Sans SemiBold dengan tracking lebar oleh `tools/gen_backdrop.py` | Bukan hasil ketik runtime, jadi bentuknya selalu sama. |
| `launcher/ui/textures/splash_boot.png` | Komposisi crest + wash hangat oleh `tools/gen_backdrop.py` | Dipakai sebagai boot splash. |
| `launcher/icon/icon.png`, `icon_bg.png` | Turunan crest untuk Android adaptive icon (foreground + background plate) | Safe zone ikon adaptif dijaga di 75% area tengah. |
| Panel, tombol, progress bar, ikon 24×24, divider, sudut ornamen, partikel | Digambar per piksel oleh `tools/gen_ui_kit.py` (palet tetap, outline 1px, hard edge, tanpa anti-alias) | Skrip = sumber kebenaran; PNG di-commit supaya build tidak butuh Python. |
| Latar vignette, scrim, glow, mote | `tools/gen_ui_kit.py` / `tools/gen_backdrop.py` | Semua bitmap PNG, filter Nearest saat runtime. |
| Dunia Fase 2: `tree_pine`, `tree_oak`, `cottage`, `bush`, `rock`, `grass_tile`, `path_tile` | Gambar orisinal dibuat khusus untuk proyek ini dengan model gambar AI (24 Okt 2026), sumber di `assets_src/world/`, lalu diolah `tools/process_world_assets.py`: chroma-key magenta, crop, downscale LANCZOS, kuantisasi palet 22–32 warna, alpha keras, dan edge-blend agar tile mulus | Satu gaya dan satu palet hangat untuk semua properti. Ukuran akhir: pinus 192×320, oak 320×240, cottage 352×264, semak 112×88, batu 144×96, tile 256×256. Tidak meniru aset game mana pun. |

Semua gambar diproses menjadi **bitmap PNG sungguhan** sebelum masuk game.
Tidak ada sprite/UI yang digambar lewat kode saat runtime (`draw_rect`,
polygon, gradient prosedural) — kode hanya memuat PNG dan menempatkannya.

## Kode & tooling

| Berkas | Lisensi |
| --- | --- |
| Seluruh skrip GDScript, skrip Python di `tools/`, dan workflow CI | milik proyek ini |

Aset pihak ketiga lain: tidak ada. Jika nanti memakai pack karakter dari
itch.io/OpenGameArt, tambahkan barisnya di sini **sebelum** dipakai, lengkap
dengan nama pack, penulis, lisensi, dan URL.
