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
| `atlas_ui.png` + `atlas_ui.json` | Digabung `tools/gen_atlas.py` dari ikon 24×24 (grid + padding 1 px, JSON berisi region) | Satu tekstur untuk seluruh HUD; PNG tunggal tetap sumbernya |
| Ikon UI game 24×24 (`heart_full`, `heart_empty`, `sun`, `moon`, `gear`, `save`, `arrow_left`) | Digambar per piksel oleh `tools/gen_game_ui.py` (grid 24×24, outline 1px, palet hangat, NEAREST) | Satu keluarga dengan ikon launcher; hati, matahari, bulan, gear, scroll, panah |
| Panel, tombol, progress bar, ikon 24×24, divider, sudut ornamen, partikel | Digambar per piksel oleh `tools/gen_ui_kit.py` (palet tetap, outline 1px, hard edge, tanpa anti-alias) | Skrip = sumber kebenaran; PNG di-commit supaya build tidak butuh Python. |
| Latar vignette, scrim, glow, mote | `tools/gen_ui_kit.py` / `tools/gen_backdrop.py` | Semua bitmap PNG, filter Nearest saat runtime. |
| Dunia Fase 2: `tree_pine`, `tree_oak`, `cottage`, `bush`, `rock`, `grass_tile`, `path_tile` | Gambar orisinal dibuat khusus untuk proyek ini dengan model gambar AI (24 Okt 2026), sumber di `assets_src/world/`, lalu diolah `tools/process_world_assets.py`: chroma-key magenta, crop, downscale LANCZOS, kuantisasi palet 22–32 warna, alpha keras, dan edge-blend agar tile mulus | Satu gaya dan satu palet hangat untuk semua properti. Ukuran akhir: pinus 192×320, oak 320×240, cottage 352×264, semak 112×88, batu 144×96, tile 256×256. Tidak meniru aset game mana pun. |

Semua gambar diproses menjadi **bitmap PNG sungguhan** sebelum masuk game.
Tidak ada sprite/UI yang digambar lewat kode saat runtime (`draw_rect`,
polygon, gradient prosedural) — kode hanya memuat PNG dan menempatkannya.

## Karakter (tahap sprite, Fase 2)

Semua sprite karakter adalah **PNG dari pack pihak ketiga yang diunggah pemilik
proyek**, bukan gambar hasil kode dan bukan hasil model gambar. Tidak ada satu
piksel pun yang digambar runtime: `AnimatedSprite3D` hanya memotong strip yang
sudah ada.

| Pack | Berkas yang dipakai | Lisensi | Catatan |
| --- | --- | --- | --- |
| **FREE Knight 2D Pixel Art v1.2** | `game/assets/characters/knight/*.png` (12 strip: idle, walk, run, attack_1–3, block, hurt, death, jump_start/transition/fall), `LICENSE.txt` | Komersial & pribadi boleh; **dilarang menjual/menyebarkan ulang sebagai aset** (harus jadi bagian dari proyek); kredit tidak wajib tetapi dihargai; boleh dimodifikasi; **dilarang** dijadikan NFT | Ksatria = pemain. Teks lisensi asli disalin apa adanya ke `game/assets/characters/knight/LICENSE.txt`. Nama kreator tidak tercantum di dalam berkas lisensi pack, jadi tidak dikarang di sini. |
| **Tiny RPG Character Asset Pack 01 v2.0 — Free Soldier & Orc** | `game/assets/characters/soldier/*.png`, `game/assets/characters/orc/*.png` | **DIISI PEMILIK (TODO)** — zip yang diunggah **tidak memuat berkas lisensi**, sumber/kreator belum terverifikasi | Penjaga (NPC) + orc (musuh). Varian "with shadows" **tidak dipakai**; disimpan sebagai cadangan di `assets_src/characters/*/_with_shadows/`. Lembar Penjaga ternyata membawa bayangan jatuh sendiri (warna datar `(83,69,69)` di lima baris bawah setiap frame); `tools/import_character_sprites.py` menghapus warna itu agar engine memakai satu blob shadow seragam. Tidak ada piksel karakter yang diubah. Arrow projectile (100×100 & 32×32) disimpan untuk pemanah nanti. Jangan publikasikan sebelum kolom lisensi diisi. |

Catatan lisensi yang perlu diingat sebelum rilis publik:

1. Pack Knight melarang **menjual atau menyebarkan ulang asetnya sebagai aset**.
   Karena itu strip mentah tidak boleh dipublikasikan sebagai "asset pack" di
   repo/release terpisah; di repo ini ia hanya ada sebagai bagian dari game.
2. Pack Soldier/Orc belum punya berkas lisensi. Statusnya masih **TODO pemilik**;
   `game/assets/characters/soldier/SOURCE.txt` dan `.../orc/SOURCE.txt` menuliskan
   ini secara eksplisit di dalam paketnya sendiri.
3. Pack **FREE Blacksmith 2D Pixel Art** ikut terkirim di zip yang sama. Belum
   dipakai di tahap ini; disimpan di `assets_src/characters/_extra_blacksmith/`
   lengkap dengan lisensinya (isinya sama dengan lisensi Knight).

## Kode & tooling

| Berkas | Lisensi |
| --- | --- |
| Seluruh skrip GDScript, skrip Python di `tools/`, dan workflow CI | milik proyek ini |

Aset pihak ketiga lain: tidak ada. Jika nanti memakai pack karakter dari
itch.io/OpenGameArt, tambahkan barisnya di sini **sebelum** dipakai, lengkap
dengan nama pack, penulis, lisensi, dan URL.

## Ikon UI (langkah 1, 0.7.0)

Tujuh ikon baru untuk antarmuka lapangan: **talk** (Bicara), **door** (Masuk),
**inspect** (Periksa), **take** (Ambil), **map** (peta), **close** (tutup), dan
**book** (Jurnal). Semuanya digambar sebagai bentuk oleh pemilik proyek lewat
skrip yang ikut di repositori, bukan diambil dari sumber pihak ketiga:

```
python3 tools/gen_game_ui.py     # 14 PNG 24x24 di game/assets/ui/icons/
python3 tools/gen_atlas.py       # atlas_ui.png + atlas_ui.json (14 sel)
```

Grid 24×24, palet hangat yang sama dengan ikon fase 7 (kayu, kuningan, krem,
merah hati). Tidak ada ikon pihak ketiga, tidak ada aset berlisensi lain.

## Aset dunia langkah 2 (0.8.0)

Semua tekstur dan prop dunia di langkah 2 dibuat sendiri untuk proyek ini,
secara prosedural dan deterministik, lalu disimpan sebagai PNG:

| aset | sumber | lisensi |
| --- | --- | --- |
| 9 tekstur medan (`cliff`, `sand`, `snow`, `stone_floor`, `wood`, `water`, `flowers`, `reeds`, `stump`) | `tools/gen_region_tiles.py` (karya sendiri) | CC0 — karya pemilik proyek |
| `terrain_atlas.png` (8 sel) | gabungan tekstur di atas | CC0 |
| `dock`, `gate`, `sign`, `torch`, `tower`, `well` | `tools/gen_world_props.py` (karya sendiri) | CC0 |
| `prop_atlas.png` (14 sel) + `prop_atlas.json` | gabungan prop di atas + 5 prop lama | CC0 |

Tidak ada sprite karakter baru di langkah ini: karakter tetap dari paket yang
sudah ada, dan tidak ada karakter yang digambar lewat kode.

## Aset bangunan langkah 3B (0.10.0)

Bangunan di Yaros kini model 3D low-poly, dan **tidak ada satu model, tekstur,
atau mesh pun yang diambil dari pihak ketiga**. Semuanya dirakit sendiri:

| aset | sumber | lisensi |
| --- | --- | --- |
| `game/world/textures/building_atlas.png` (16 sel 128×128) | `tools/gen_building_kit.py` — dilukis per piksel oleh skrip, seed tetap, deterministik | **CC0** — karya pemilik proyek |
| `game/world/building_kit.json` (nama sel, ukuran meter, jenis, radius tabrakan) | ditulis skrip yang sama | CC0 |
| Mesh rumah, menara, gerbang, sumur, dermaga, papan, obor | `game/world/BuildingKit.gd` — dirakit dari primitif (kotak, atap pelana, cincin 8 sisi) saat region dimuat | CC0 |
| `game/world/building.gdshader` | karya sendiri | CC0 |

Kenapa CC0 dan bukan CC-BY: tidak ada karya orang lain di dalamnya, jadi tidak
ada yang perlu diatribusikan. Palet dan gaya mengikuti tekstur dunia langkah 2
yang juga CC0, supaya seluruh lembah satu tangan.

Alasannya tekstur ini dibuat prosedural, bukan dari model gambar AI seperti aset
dunia Fase 2: sebuah atlas harus **bisa diulang (tileable)** dan ukurannya harus
tepat dalam meter (satu sel dinding = 2 m), dan dua hal itu tidak bisa dijamin
dari gambar hasil model. Skrip juga membuat perubahan bisa ditinjau di PR.
