# DESIGN NOTES — Re - Traveller

Catatan keputusan desain, termasuk hal-hal yang **tidak** boleh dilanggar di
fase berikutnya. Dibaca bersama `docs/CREDITS.md` dan `docs/GAME_CONTRACT.md`.

---

## 0. Versi engine (dikunci)

| Item | Nilai |
| --- | --- |
| Engine | **Godot 4.7.2-stable** (`4.7.2.stable.official`) |
| Renderer | `gl_compatibility` (OpenGL 3 / ES 3) — target Android menengah luas |
| Bahasa | GDScript saja. **Tanpa** GDExtension, plugin native, atau `.so`. |
| Launcher | Proyek A, `launcher/` → APK |
| Game | Proyek B, `game/` → `.pck` (nama modul: core, characters, enemies, world, ui, audio) |

Alasan memilih Compatibility renderer: HD-2D di chibi 48×64 tidak butuh
deferred/SSAO, tetapi butuh jalan lancar di GPU Android kelas menengah. Efek
"modern" (bloom lembut, DOF/tilt-shift, god rays) akan dibuat dengan post-process
2D/3D kustom yang aman di Compatibility, bukan dengan fitur Forward+.

**Kenaikan versi engine = APK baru.** Itu satu-satunya alasan selain perubahan
kode launcher. Manifest punya `min_launcher_version` untuk memberi tahu pemain
lama.

---

## 1. Nada visual: fantasi klasik bergaya dongeng

Yang dipakai:

* palet hangat seperti cat air — oker, jingga senja, hijau lumut, terakota,
  teal gelap sebagai bayangan;
* bahan: perkamen, kayu walnut, kuningan tua, besi, sulaman krem;
* bentuk: sudut membulat kecil, bingkai bertepi 1px, ornamen daun dan bintang;
* tipografi piksel yang tetap terbaca di layar 5–6 inci.

Yang **dilarang** (aturan mutlak dari brief):

* cyberpunk, neon, glow biru/ungu, hologram, garis-garis sci-fi, HUD futuristik,
  grid digital, glitch, font teknologi;
* abu-abu kusam dan palet desaturasi;
* placeholder: kotak, lingkaran, stick figure, warna polos, teks default Godot.

Uji cepat: kalau sebuah layar bisa muncul di game sci-fi tanpa diubah, berarti
desainnya salah.

---

## 2. Tipografi

* **Satu keluarga: Pixelify Sans (OFL).** Regular untuk isi, SemiBold untuk
  wordmark dan tombol aksi.
* Ukuran minimum 16 px pada kanvas 1280×720 (≈ 9 pt di layar 6 inci). Judul
  status 34 px, detail 19 px, log 16 px.
* Font blackletter (Jacquard 12) **dibuang**. Pada uji baca 720p, "TRAVELLER"
  terbaca "TKAVELLEK". Blackletter tidak dipakai untuk kata apa pun di UI.
* Wordmark "RE - TRAVELLER" adalah **bitmap** (`logo_wordmark.png`) yang
  dirender sekali dari Pixelify SemiBold dengan tracking 18%. Alasannya:
  bentuknya selalu sama, tidak bergantung pada pembulatan font runtime, dan
  bisa dipakai di splash/ikon/Store nanti.
* Semua font disetel `antialiasing=none`, `hinting=none`,
  `subpixel_positioning=disabled` supaya tetap piksel murni.

---

## 3. Logo & ikon

* Lambang: kompas kuningan 8 arah + perisai dengan jalan berliku menuju bintang
  + dua tongkat pengembara bersilang + ranting oak + pita kosong (tanpa teks).
  Maknanya: "perjalanan menuju sesuatu yang dituju".
* Palet lambang dibatasi 32 warna hangat (kuningan, teal, krem, cokelat tua).
* `logo_crest.png` 256×256 adalah **master**; semua ukuran lain adalah
  pembagian integer (128, 64) supaya tetap tajam.
* Ikon aplikasi: adaptive icon (foreground 512 + background plate 512), crest
  dijaga di dalam safe zone 75%.

---

## 4. UI kit (bitmap, bukan gambar runtime)

Semua panel/tombol/ikon dibuat `tools/gen_ui_kit.py` lalu di-commit sebagai PNG:

| Aset | Ukuran | Aturan |
| --- | --- | --- |
| `panel_parchment.png` | 64×64, 9-slice margin 20 | bingkai kuningan + bidang perkamen polos |
| `panel_ink.png` | 48×48, margin 14 | kartu teal gelap untuk log/status |
| `button_wood_*` | 64×32, margin 14 | papan kayu, dua paku kuningan |
| `button_gold_*` | 96×40, margin 12 | tombol utama (MAIN) |
| `bar_track/fill/cap` | 64×20 / 64×20 / 10×20 | progress unduhan |
| ikon 24×24 | play, retry, check, warn, download, offline, gear, scroll | grid sama, outline 1px |
| `ornament_divider.png` | 128×16 | pembatas daun + berlian |

Pelajaran yang sudah dibayar mahal:

1. **Jangan menaruh noise di tengah 9-slice.** Bagian tengah diregangkan, jadi
   titik-titik berubah menjadi blok besar. Panel harus rata di tengah.
2. **StyleBox variation harus didaftarkan** (`set_type_variation("X",
   "PanelContainer")`). Tanpa itu tema diam-diam jatuh ke gaya default dan
   panel jadi kotak gelap.
3. **CanvasLayer tidak mewarisi tema.** Modal yang hidup di CanvasLayer harus
   diberi `theme` sendiri.
4. **Overlay halus pakai filter linear**, bukan nearest. Vignette/scrim/glow
   adalah gradien, bukan pixel art; kalau di-nearest 5× hasilnya bergaris.
5. **Kontainer mengatur posisi anak.** Animasi masuk tidak boleh menggeser
   `position` anak kontainer (bisa bertabrakan dengan layout). Pakai alpha +
   scale.

---

## 5. Tata letak launcher (1280×720, landscape)

```
┌───────────────────────────────────────────────────────────────┐
│ crest 124px            │  panel perkamen 560×…               │
│ RE - TRAVELLER         │  CATATAN PEMBARUAN           v2.0.0 │
│ Kisah Delapan Pengembara│  Judul status (34px)               │
│ ── divider ──          │  Detail (19px)                     │
│                        │  [progress bar]  ukuran/kecepatan   │
│                        │  ── divider ──                     │
│ (ruang untuk ilustrasi)│  catatan rilis (scroll)            │
│                        │  PAKET TERPASANG (6)               │
│                        │  [Coba Lagi]              [ MAIN ] │
│ jurnal 2 baris         │                                     │
└───────────────────────────────────────────────────────────────┘
```

* Kolom kiri 560 px minimum, kanan 540 px, jarak 28 px, margin aman 44 px
  (menghindari notch dan tepi gestur).
* Tombol utama 212×66 px — target sentuh besar, di kanan bawah (jempol kanan).
* Status selalu terlihat tanpa scroll. Changelog satu-satunya area yang scroll.

---

## 6. Bahasa

* Seluruh teks pemain: **Bahasa Indonesia** yang hangat dan sederhana
  ("Mencari kabar dari kerajaan…", "Mode luring").
* Angka: pemisah desimal koma, ribuan titik (`1,1 MB`, `312 KB/s`).
* Nama paket dan istilah teknis tidak diterjemahkan (core, characters, …).
* Kode, komentar, dan dokumentasi internal: Inggris untuk kode, Indonesia untuk
  dokumen pemain/kerja.

---

## 7. Yang berlaku untuk fase game (2+)

Sudah dicatat supaya fase berikutnya tidak mengulang kesalahan:

* Renderer `gl_compatibility`; kamera 35–45°, FOV sempit (≈ 30–35).
* Sprite karakter 48×64 kanvas, pivot di kaki, billboard, filter nearest,
  posisi snap ke piksel, bayangan oval terpisah di tanah.
* Tilt-shift dibuat sebagai post-process layar penuh (dua blur band), punya
  saklar di pengaturan.
* Semua aset tekstur piksel: nearest + kompresi ETC2/ASTC saat ekspor Android
  (`rendering/textures/vram_compression/import_etc2_astc=true` — sudah aktif).
* Dunia wajib diisi: rumput, bunga, batu, ranting bervariasi; tidak boleh ada
  bidang kosong.
* Partikel "debu" memakai sprite kecil (4×4), jangan kotak.

---

## 8. Fase 2 — mesin diorama HD-2D (tahap 1)

Tambahan pada 24 Okt 2026. Tujuannya: membuktikan "HD-2D" di atas renderer yang
dipaksa APK (`gl_compatibility`), tanpa satu pun sprite karakter.

**Yang membentuk tampilan**

| Unsur | Keputusan | Alasan |
| --- | --- | --- |
| Kamera | rig sudut tetap: pitch −38°, yaw −22°, FOV 30°, zoom awal 19 | Sudut miring rendah = kesan miniatur/diorama. Kamera tidak pernah tilt supaya ilusi tidak pecah. |
| Pergerakan kamera | geser satu jari/mouse, cubit dua jari atau gulir untuk zoom (11–32) | Semua lewat sentuhan; tidak ada joystick di layar. |
| Sprite properti | `QuadMesh` billboard, `alpha_scissor` 0,45, filter Nearest | Alpha-scissor (bukan transparan) supaya sinar matahari benar-benar mengenai sprite dan bayangannya jatuh di rumput. |
| Cahaya | satu `DirectionalLight3D` hangat-netral, bayangan ortho 60 m, bias 0,04/1,2, blur 1,4 | Bayangan panjang dari kiri atas adalah ciri khas diorama; bias dijaga agar tidak "peter-panning". |
| Udara | fog 0,0045 warna netral-hangat | Memberi kedalaman. Density 0,011 pernah membuat seluruh padang berwarna pasir — jangan dinaikkan tanpa cek tangkapan layar. |
| Warna | ACES, exposure 1,0, kontras 1,08, saturasi 1,12, glow 0,30 | Hijau harus tetap hijau; matahari terlalu kuning membuat rumput tampak jerami. |
| Depth of field | **tidak ada di Compatibility** → shader tilt-shift layar penuh (`tiltshift.gdshader`) | Blur vertikal bertahap dari garis fokus; inilah yang membuat tampilan terasa miniatur. |
| Jalan setapak | quad per segmen + `path.gdshader` (decal) | Dekal mencampur tekstur tanah dengan tekstur rumput yang sama dengan lantai, tepinya diberi noise, jadi tidak terlihat seperti pita yang ditempel. |

**Pelajaran teknis (jangan diulang)**

* `node.position = Vector3(x, 0, z)` menimpa offset Y yang sudah dipasang; sprite
  jadi setengah terkubur. Tulis `.x`/`.z` saja.
* Node rig kamera harus punya `Camera3D` **sebelum** masuk tree, kalau tidak
  `@onready` gagal dan pan/zoom mati tanpa error yang terlihat.
* Mesh strip datar buatan tangan bisa ter-cull dan teksturnya memanjang; quad per
  segmen jauh lebih dapat diprediksi.
* Tile hasil generator punya rim gelap di pinggir gambar → crop 10% sebelum
  edge-blend, kalau tidak seam-nya terlihat sebagai grid.
* `alpha_scissor` butuh tepi alpha keras; PNG hasil `pixelate()` sudah dibuat
  biner (ambang 110/255).

---

## 9. Fase 2 — tahap 2: karakter (sprite, pivot, langkah)

Tambahan 25 Okt 2026. Tiga karakter hidup di lembah: **Ksatria = pemain**,
**Penjaga = NPC**, **Orc = musuh**. Semua data, bukan kode: satu
`CharacterDef.tres` per karakter (id, peran, folder sprite, daftar animasi,
frame size, frame count, fps, loop, pivot, pixel size, langkah). Menambah
karakter = tambah PNG + satu entri di `tools/import_character_sprites.py`.

**Frame yang diverifikasi (jangan diubah tanpa ukur ulang)**

| Karakter | Kanvas | Animasi (frame) | fps awal | Tinggi dunia |
| --- | --- | --- | --- | --- |
| Ksatria | 112×96 | idle 14, walk 8, run 8, attack_1 8, attack_2 9, attack_3 11, block 6, hurt 8, death 15, jump_start/transition/fall 3/3/3 (disimpan, belum dipakai) | 9 / 11 / 13 / 14 / 14 / 15 / 10 / 12 / 11 | 1,80 m |
| Penjaga | 100×100 | idle 6, walk 8, attack_1 6, attack_2 6, attack_3 9, hurt 4, death 4 (+ arrow 100×100 & 32×32 disimpan) | 8 / 10 / 13 / 13 / 14 / 12 / 11 | 1,61 m |
| Orc | 100×100 | idle 6, walk 8, attack_1 6, attack_2 6, hurt 4, death 4 | 9 / 10 / 13 / 13 / 12 / 11 | 1,40 m |

`tools/import_character_sprites.py --check` menghitung ulang
`lebar PNG == jumlah frame × lebar frame`; kalau tidak cocok, **build gagal**
(bukan ditebak atau dipotong paksa). Pemeriksaan yang sama dijalankan ulang di
runtime (`CharacterAssets.problems_for`) dan di `ValidateCharacters.tscn`.

**Pivot kaki, bukan tengah kanvas**

Pivot = `(tengah bbox IDLE horizontal, bawah bbox IDLE)` dalam piksel sumber:
Ksatria `(53, 85)`, Penjaga `(48.5, 57)`, Orc `(55, 57)`. Node aktor berdiri di
titik itu, jadi karakter menapak di tanah. Kuad sprite digeser sebesar
`(w/2 − pivot.x, pivot.y − h/2) × pixel_world`; saat `flip_h` aktif, komponen X
dibalik supaya kaki tidak bergeser saat menghadap kiri.

**Satu `pixel_size` dunia, pengali per karakter (dicatat, disengaja)**

`world_pixel_size = 0,05 m/piksel`. Ketiga pack digambar pada resolusi berbeda
(tinggi badan: Ksatria 36 px, Penjaga 19 px setelah bayangan bake dihapus,
Orc 16 px), jadi `pixel_scale` per karakter 1,0 / 1,7 / 1,75 menghasilkan
1,80 / 1,61 / 1,40 m. Tanpa pengali, penjaga akan setinggi anak-anak.

**Bayangan bake dihapus di pipeline, bukan ditambal di engine.** Lembar Penjaga
dari pack membawa bayangan jatuh sendiri: satu warna datar `(83, 69, 69)` yang
hanya muncul di lima baris di bawah kaki, di **setiap** frame (termasuk death),
berbentuk elips mengelilingi sepatu. `tools/import_character_sprites.py` membuat
warna itu transparan (`erase_colors`), sehingga (a) tidak ada bayangan ganda,
(b) blob shadow engine sama untuk ketiga karakter, (c) pivot kaki jatuh di sepatu
(y=57), bukan di bayangan (y=60). Ksatria dan Orc tidak punya bayangan bake.
Jumlah piksel yang dihapus dicetak saat `--import` (mis. idle 276 px).

> **Risiko visual yang harus disebut jujur:** Ksatria dan Penjaga/Orc berasal
> dari dua pack dengan gaya, kerapatan piksel, dan palet berbeda. Ini arahan
> pemilik (tiga peran itu yang diminta), tetapi secara tampilan mereka tidak
> satu keluarga. Pack **Blacksmith** yang ikut terkirim gayanya sejalan dengan
> pack Ksatria; kalau nanti penjaga perlu seragam dengan ksatria, itu kandidat
> yang paling murah. Belum dipakai di tahap ini.

**Tanpa foot sliding — dihitung, bukan dikira**

Tiap karakter punya `walk_stride_m` (jarak tanah per satu siklus animasi):
Ksatria 0,90 m (lari 1,90 m), Penjaga 0,75 m, Orc 0,70 m. Kecepatan nominal
diturunkan dari situ:

```
speed = stride / (frames / fps)      # mis. Ksatria: 0.90 / (8/11) = 1.24 m/s
speed_scale = speed_sekarang / speed_nominal
```

Dorongan stik setengah berarti kecepatan setengah **dan** irama langkah
setengah, jadi kaki tetap menapak. Nilai rasionya dicetak oleh
`ValidateCharacters.tscn` (harus 1,000).

**Tampilan**

| Unsur | Keputusan | Alasan |
| --- | --- | --- |
| Sprite aktor | `AnimatedSprite3D`, billboard, `alpha_cut = DISCARD` 0,45, Nearest, `shaded = true`, `pixel_size = 0,05 × pixel_scale` | Menerima cahaya matahari dan bisa diurutkan terhadap pohon, bukan stiker datar. Bayangan asli dimatikan (`cast_shadow = OFF`) karena penggantinya blob. |
| Tekstur | PNG mentah di dalam `.pck`, didekode runtime menjadi RGBA8, **tanpa mipmap**, Nearest | Tidak ada `.import`, jadi tidak ada kompresi ETC2/ASTC yang mengotori tepi piksel atau mipmap yang mengaburkan saat zoom jauh. Biayanya memori, dan untuk ~25 strip kecil itu tidak terasa. |
| Bayangan | satu `blob_shadow.gdshader` (oval lembut, unshaded) di semua aktor | Semua pack dipakai **tanpa bayangan bawaan**, jadi tidak ada bayangan ganda dan tidak ada karakter yang "melayang". |
| Anti-shimmer | posisi aktor di-snap ke **¼ piksel sumber** (`SNAP_FRACTION = 0.25`) | Snap satu piksel penuh (≈3,5 px layar di zoom 19) membuat jalan terasa patah-patah; ¼ piksel menghapus getaran tepi tanpa mengorbankan kehalusan. Sisa shimmer saat menggeser kamera tidak bisa hilang total di 3D — dicatat sebagai batas, dicek di `VisualTest`. |
| Debu langkah | `CPUParticles3D` + `dust_puff.gdshader` (billboard, radial) | Tidak perlu tekstur tambahan; muncul tiap setengah langkah. |
| Flash hurt | `modulate` 1,0 → 2,3 selama 0,09 s | Putih sesaat tanpa mengubah tekstur. |
| Hit-stop | 0,05 s (≈3 frame @60 fps) saat kena pukulan | Memberi bobot pukulan tanpa menambah animasi. |
| Squash/stretch | skala `Visual` 9%/11% selama 0,18 s | Ringan saja; sumbu X/Y dari kaki, jadi tidak menggeser tapak. |
| Getar kamera | rotasi rig ±0,35° dengan redaman | Halus; bukan shake ala game aksi. |

**State machine & aturan main**

* `idle → walk → run` mengikuti besaran stik; `run` hanya untuk karakter yang
  punya animasi lari (Ksatria). Penjaga/Orc berjalan.
* Serangan pemain bersiklus `attack_1 → attack_2 → attack_3 → idle`; menekan
  lagi saat masih menyerang menyiapkan serangan berikutnya. Orc memilih
  `attack_1`/`attack_2` secara acak (pack-nya tidak punya attack_3).
* Blok: animasi diputar sekali lalu **menahan frame terakhir** selama tombol
  ditahan.
* Hurt: sekali, lalu kembali ke idle; memotong serangan yang sedang berjalan.
* Death: menahan frame terakhir. Orc lalu memudar (~0,9 s) dan disembunyikan.
* Orc: patroli antar titik; radius deteksi 4,5 m → mendekat pelan; jarak ≤1,0 m
  → `battle_triggered` (belum ada sistem pertempuran, jadi tidak ada yang
  dipalsukan) dan pemberitahuan di layar.

**Animasi yang TIDAK ada di aset — jangan dipalsukan**

Tidak ada `cast`, `victory`, `boost`, atau panah yang ditembakkan pada ketiga
pack ini. Tahap ini tidak membuatnya dari kode. **Butuh aset tambahan** kalau
nanti mau: sihir, kemenangan, lompatan (Ksatria sudah punya 3 frame lompat yang
disimpan), dan pemanah (panahnya sudah ada, busurnya belum).

**Kontrol sentuh**

Stik 196 px di kiri bawah (dorong kecil = jalan, penuh = lari); tiga tombol
kanan bawah: **Serang** 140 px, **Tahan** 120 px, **Bicara** 120 px. Semua
≥96 px agar nyaman dijempol. Saat salah satu disentuh, kamera tidak ikut
menggeser (`DioramaCamera.touch_blockers`); kamera juga mengikuti pemain dengan
redaman dan berhenti mengikuti 2,5 s setelah pengguna menggeser sendiri.

**Penyempurnaan setelah tangkapan layar pertama (25 Okt 2026)**

Yang diubah setelah melihat hasil CI, bukan setelah "kira-kira":

- **Jalur tanah.** Tile tanah yang dipakai apa adanya terbaca sebagai pita emas
  di atas padang rumput. `path.gdshader` sekarang menariknya 34% ke arah
  luminansinya sendiri lalu mengalikannya 0,82, dan `dirt_tint` turun dari
  (1,08; 1,00; 0,88) ke (0,94; 0,90; 0,84). Hasilnya tanah kecokelatan yang
  menyatu, bukan garis menyala.
- **Posisi penjaga.** Dari (-6,6; 1,4) — di luar bingkai kamera pemain — ke
  (2,4; 4,2): dua langkah dari titik awal ksatria, di tepi jalur, jadi tombol
  Bicara menyala tanpa pemain harus mencari. Ia berdiri *di samping* jalur,
  bukan menghalanginya (`body_radius_m` 0,28 dan ia bukan blocker).
- **Panel dialog.** Tinggi panel dulu dipaku 210 px, sehingga pilihan kedua
  terpotong tepi bawah layar. Panel kini tumbuh **ke atas** dari margin bawah
  (`grow_vertical = GROW_DIRECTION_BEGIN`), jadi berapa pun panjang teks dan
  pilihan, semuanya masuk layar.
- **Kontrol sentuh saat bicara.** Stik dan tiga tombol disembunyikan selama
  dialog terbuka (signal `closed` dari `DialogueBox` mengembalikannya), karena
  panel perkamen menutupi ibu jari kanan dan gerakan memang dikunci.
- **Bayangan ganda penjaga.** Lihat §9: bayangan bake dihapus di pipeline.
- **`root.sort_children = true` di `Diorama`** dihapus: properti itu milik
  `SpriteBase3D`, bukan `Node3D`, dan setiap frame mencetak SCRIPT ERROR di CI.

Tangkapan layar yang menjadi bukti: `09_karakter.png` (tiga karakter + penggaris
+ penanda pivot), `10_visual_siang.png`, `11_visual_malam.png`, `12_dialog.png`
(satu halaman dialog), `13_pilihan.png` (dua cabang).

## 10. Kenapa game tidak pernah boot di HP (25 Okt 2026) — dan aturannya

Gejala di perangkat: tekan **MAIN** → layar hitam → launcher kembali dengan
"Versi 0.2.0 ditahan". Versi 0.1.0 juga pernah gagal dengan cara yang sama.

Penyebab pastinya ditemukan dari CI, bukan dari perangkat. Skenario uji baru
`boot_packs` (memuat `res://game/Main.tscn` dari paket `.pck` yang benar-benar
dipasang, persis seperti HP):

```
SCRIPT ERROR: Parse Error: Identifier "Diorama" not declared in the current scope.
          at: GDScript::reload (res://game/Main.gd:121)
ERROR: Failed to load script "res://game/Main.gd" with error "Parse error".
```

`Main.gd` memakai `Diorama.AREA_NAME` — nama kelas **global** dari
`world/Diorama.gd` (`class_name Diorama`). Nama global hanya dikenal oleh
*cache kelas* proyek tempat skrip itu didaftarkan. Game kita dimuat ke dalam
proses launcher, yang cache-nya tidak pernah melihat skrip dari `.pck`. Akibatnya
`Main.gd` gagal **di-parse** → scene tetap ter-instantiate tapi tanpa skrip →
tidak ada `_ready()`, tidak ada `boot_ok.json` → layar hitam → watchdog 25 detik
→ rollback + "versi ditahan". Semua job CI hijau karena semuanya menjalankan
proyek `game/` langsung, bukan dari paket.

**Aturan yang sekarang berlaku untuk semua skrip game:**

1. **Dilarang memakai `class_name` sebagai tipe atau akses statis di skrip game.**
   Ketiga `class_name` di paket dunia (`Diorama`, `DioramaCamera`, `WorldArt`)
   dihapus.
2. Untuk helper di **paket yang sama**, gunakan `preload` sebagai konstanta:
   `const ART := preload("res://game/world/WorldArt.gd")`, lalu `ART.tex(...)`.
   Paketnya sudah ter-mount sebelum skripnya di-parse, jadi ini aman.
3. Untuk data dari **paket lain** (core ↔ world), jangan `preload` (paket lain
   boleh tidak ada) dan jangan nama global. Ambil saat runtime:
   `(node.get_script() as Script).get_script_constant_map()` — dipakai
   `Main._area_constant()` untuk `AREA_NAME`/`AREA_SUBTITLE`.
4. Isi paket boleh berubah, jadi `.pck` lama tetap kompatibel: aturan ini hanya
   soal cara skrip saling menemukan.

Uji regresi: `boot_packs` di `tools/run_launcher_tests.sh` (matrix CI) yang
memeriksa skrip menempel & terkompilasi, `boot_ok.json` menyebut versi aktif,
node `Diorama`, `HUD`, dan `Diorama/Characters` benar-benar terbangun, plus
tangkapan layar `docs/screenshots/14_game_dari_paket.png`.

## 11. Dua bug perangkat dari laporan pemilik (25 Okt 2026)

Laporan: *"tiba-tiba stuck saat dipukul monster, dan objek kayaknya melayang —
pohon, batu, dan lain-lain"*. Keduanya direproduksi dulu sebagai uji
`game/tests/PlayTest.tscn` (headless, masuk CI sebagai "Play rules"), **gagal**
dengan perbaikan belum dipasang, lalu hijau setelahnya.

### 11.1 Ksatria terkunci setelah dipukul (lampu putih berhenti)

Penyebabnya hit-stop. `_process()` menghentikan animasi dengan
`sprite.speed_scale = 0.0` selama 0,05 s, tetapi **tidak pernah
mengembalikannya**. Akibatnya animasi `hurt` berhenti di frame pertamanya.
Frame pertama `hurt` dari pack Ksatria adalah siluet putih — itulah yang terlihat
di tangkapan layar pemilik. Karena animasi tidak pernah maju,
`animation_finished` tidak pernah datang, dan `_on_anim_finished()` adalah
satu-satunya jalan keluar dari state `hurt`:

```
stuck = hurt (speed_scale 0) -> animasi mati -> tak ada animation_finished
      -> state tetap HURT -> drive() & try_attack() keduanya menolak
```

Perbaikan (semua di `Actor.gd`):

1. `_anim_speed` menyimpan kecepatan animasi; ketika hit-stop selesai,
   `speed_scale` dikembalikan ke nilai itu (bukan dibiarkan 0).
2. `_play(anim, speed, restart)`: parameter `restart` memaksa `sprite.play()`
   walau nama animasinya sama. Dulu flinch kedua tidak pernah memutar ulang
   strip karena `_anim` masih `"hurt"`.
3. Flinch tidak bisa dirantai: `take_hit()` diabaikan bila masih di `hurt`
   kurang dari 0,2 s (dua orc yang memukul bersamaan dulu mengunci pemain).
4. Pengawas `_watch_one_shot()`: kalau `animation_finished` tetap tidak datang
   (tree dijeda, sinyal hilang), state `hurt`/`attack` dilepas setelah durasi
   animasi + 0,35 s dan karakter kembali `idle`. Ada `push_warning` supaya
   kejadiannya terlihat di log, bukan hilang diam-diam.
5. Semua perpindahan state memakai `_enter_state()` yang juga mereset
   `_state_time` (dipakai pengawas dan jendela anti-rantai).

### 11.2 Pohon, batu, dan semak melayang

Kuad prop digambar terpusat pada origin node, jadi ia menapak hanya bila
`position.y = tinggi/2`. Kode lama memakai tinggi **tanpa** skala:

```gdscript
mi.scale = Vector3(s, s, s)
mi.position.y = size.y * 0.5        # benar hanya bila s == 1
```

Semua prop berskala 0,85–1,2, sehingga prop kecil melayang sampai **0,324 m**
(diukur uji) dan prop besar tenggelam. Sekarang `mi.position.y = size.y * 0.5 * s`.

**Aturan:** setiap kuad yang "berdiri di tanah" harus menghitung tinggi
**setelah** skala. Uji `PlayTest` mengukur tepi bawah setiap prop di diorama
sungguhan dan menuntut |y| ≤ 0,02 m, jadi kesalahan seperti ini tidak bisa
lolos lagi.

## 12. "Masih melayang", kamera, dan stik (25 Okt 2026)

Tiga laporan pemilik setelah paket 0.2.2. Yang pertama ternyata **bukan** skala
prop (itu bug lain, sudah diperbaiki di §11.2), melainkan cara kuad menghadap
kamera.

### 12.1 Akar "melayang": billboard yang ikut miring

Semua sprite (karakter dan prop) memakai `BaseMaterial3D.BILLBOARD_ENABLED`.
Billboard penuh **memiringkan kuad ke belakang sebesar pitch kamera** (−38°) dan
rotasinya berpusat di **titik tengah kuad** — untuk ksatria itu ±1,85 m di atas
kaki. Titik kaki karena itu terangkat dan bergeser ke arah kamera:

```
dy = h/2 (1 - cos 38°) = 1.85 x 0.212 = 0.39 m
dz = h/2  sin 38°       = 1.85 x 0.616 = 1.14 m
```

Kaki terlihat 0,39 m di atas rumput sementara blob shadow tetap di y = 0, jadi
seluruh karakter (dan setiap pohon/batu) tampak melayang dengan "bayangan yang
tertinggal". Karena pergeserannya bergantung tinggi, orc (1,4 m) tampak lebih
ringan gejalanya daripada ksatria (1,8 m).

Perbaikan: `BILLBOARD_FIXED_Y` untuk karakter **dan** prop — kuad hanya berputar
pada sumbu Y dunia, tetap tegak, dan titik kakinya persis di pivot. Ini juga
menghapus dua sumber kedipan: billboard penuh mengubah tinggi efektif setiap
kali kamera bergeser.

Uji: `PlayTest` memeriksa `sprite.billboard == FIXED_Y` untuk karakter dan untuk
**setiap** prop di diorama.

### 12.2 Kamera tidak mengikuti pemain

`DioramaCamera` sudah punya `set_follow_target()`, tetapi `CharacterWorld`
memanggilnya **sebelum** `_wire_ground()`/spawn selesai pada beberapa jalur, dan
yang lebih penting: `_pan_screen()` mengunci follow selama 2,5 detik setiap kali
ada satu jari menggeser layar. Di HP, satu jari di luar stik langsung dianggap
"pan", jadi kamera praktis tidak pernah mengikuti.

Sekarang:

- follow memakai **deadzone** 0,55 m: kamera diam selama ksatria masih dekat,
  lalu meluncur dengan laju 5,5 (bukan mengejar tiap milimeter, yang membuat
  gambar bergetar);
- `set_follow_target()` langsung **snap** ke posisi aktor, jadi frame pertama
  sudah benar;
- pan hanya untuk **dua jari** dan jedanya pendek (1,2 s).

Uji: `PlayTest` memindahkan ksatria 4 m lalu menuntut kamera ikut > 2,5 m dan
berhenti < 1,2 m dari aktor.

### 12.3 Stik: dinamis, di mana pun ibu jari mendarat

Stik lama dipaku di satu posisi (kiri bawah, 196 px). Pemain harus melihat ke
bawah untuk menemukannya, dan sentuhan yang meleset di luar lingkarannya
**menggeser kamera**, bukan menggerakkan ksatria — persis keluhan pemilik.

Sekarang stik **muncul di titik sentuhan** di mana pun dalam zona kiri
(55% lebar layar, 85% tinggi) dan hilang saat jari diangkat. Satu jari di zona
itu selalu untuk berjalan, tidak pernah untuk kamera. Tombol kanan tetap
hit-test normal; kamera memakai daftar `block_rects()` supaya tombol tidak
dianggap gestur.

Uji: `PlayTest` (6 pemeriksaan) — stik tersembunyi sebelum disentuh, muncul di
titik sentuh, arah dorongan benar, hilang saat diangkat, dan layar kanan tidak
memunculkan stik.

---

## 13. Cerita sebagai data + save berversi (0.3.1)

### 13.1 Kenapa cerita keluar dari kode

Percakapan penjaga dulu berupa `const DIALOGUE := [...]` di `CharacterWorld.gd`.
Menambah karakter berarti menyunting skrip, dan setiap penyuntingan skrip berarti
membangun ulang satu paket yang juga memuat seluruh mesin permainan.

Sekarang satu karakter = satu berkas data:

```
game/game/characters/data/bram.json     + spritesheet PNG + entri di def .tres
```

tanpa satu baris GDScript baru. `DialogueTree.gd` membaca skema berikut:

```json
{ "schema": 1, "speaker": "Penjaga Bram",
  "entry": ["setelah_bersih", "pertemuan", "ulangan"],
  "nodes": {
    "pertemuan": {
      "when": { "no_flags": ["bram_kenal"] },
      "pages": [ { "speaker": "Penjaga Bram", "text": "..." } ],
      "choices": [ { "label": "...", "set_flags": ["bram_janji"] } ],
      "set_flags": ["bram_kenal"] } } }
```

Aturan pemilihan: `entry` dicoba berurutan, node pertama yang **semua** syaratnya
lolos dipakai; `ulangan` tanpa syarat jadi jaring pengaman. Kondisi yang didukung
`flags`, `no_flags`, `min_counters`, `max_counters`. `problems()` memeriksa
skema, titik masuk, node kosong, pilihan tanpa label, dan flag yang dirujuk tapi
tidak pernah diset di mana pun — validator ini dijalankan di CI, jadi berkas
cerita yang salah ketik menggagalkan build sebelum sampai ke HP.

Nama pembicara boleh berganti tiap halaman (`{ "speaker": "Ksatria", ... }`),
sehingga percakapan terasa dua arah tanpa membuat sistem dialog baru.

Tiga cabang Bram: **pertemuan** (4 halaman, 2 pilihan, menandai `bram_kenal`),
**ulangan** (sudah kenal, belum bersih), **setelah_bersih** (butuh
`bram_kenal` + `orcs_defeated >= 3` — ceritanya berubah, bukan sekadar diulang).

### 13.2 Save: satu slot, tulis atomik, tidak pernah menghilangkan progres

`user://save/slot1.json` — **di luar** `user://retraveller/` yang dipakai
peluncur, jadi Periksa Lagi/hapus paket tidak menyentuh progres pemain.

```
{ "game": "re-traveller", "schema": 1, "saved_at": ..., 
  "flags": {...}, "counters": {"orcs_defeated": 2},
  "position": {"x": 3.6, "z": 7.2}, "play_time_s": 91.5, "sha256": "..." }
```

- **atomik**: tulis `slot1.json.tmp` → baca ulang & verifikasi hash → baru
  `rename` menimpa slot. Mati listrik di tengah tulis tidak menghasilkan save
  separuh jadi.
- **cadangan**: sebelum menimpa, slot lama disalin ke `slot1.json.bak`. Bila
  slot rusak/terpotong, `load_game()` memakai `.bak` dan melaporkan
  `save_dipulihkan_dari_cadangan` (bukan diam-diam menganggap permainan baru).
- **migrasi**: berkas tanpa `schema` dianggap skema 0; dibaca, field yang hilang
  diisi nilai awal, lalu ditulis ulang sebagai skema 1. Flag lama ikut pindah.
- **versi lebih baru**: `schema > 1` → `read_only`; `save_now()` menolak menulis.
  Build lama yang dibuka setelah build baru tidak boleh merusak save pemain.
- **hash**: semua angka dinormalkan `"%.3f"` sebelum di-hash, karena
  `JSON.stringify` menulis `2` tapi `JSON.parse_string` mengembalikan `2.0` —
  tanpa normalisasi, save yang baru ditulis langsung dianggap rusak.

Status yang dilaporkan ke layar: `save_baru`, `save_dibaca`,
`save_dipulihkan_dari_cadangan`, `save_rusak`.

### 13.3 Progres yang terasa

`CharacterWorld` menyimpan: bendera cerita, `orcs_defeated`, posisi ksatria, dan
waktu bermain. Autosave tiap 12 s, saat pilihan dialog dibuat, saat dialog
ditutup, dan saat orc mati. Saat boot, orc dengan indeks < `orcs_defeated`
**tidak di-spawn** — lembah yang sudah dibersihkan tetap bersih setelah aplikasi
ditutup, dan ksatria berdiri kembali di tempat ia berhenti.

Untuk pengujian, folder save bisa dialihkan lewat `RT_SAVE_DIR` (dipakai
`SaveTest`/`PlayTest` dan QA di perangkat); build normal tidak menyetelnya.

---

## 14. Taruhan dan tujuan (0.3.2)

Fase 3 membuat progres bisa disimpan; fase ini membuat progres **terasa**.
Sebelumnya orc memukul dan ksatria hanya berkedip — tidak ada yang dipertaruhkan.

### 14.1 Tiga hati

| Angka | Nilai | Alasan |
| --- | --- | --- |
| `MAX_HEARTS` | 3 | satu kesalahan masih termaafkan, dua orc serentak tidak |
| `INVULN_SEC` | 0,9 s | lebih panjang dari flinch guard 0,2 s bawaan `Actor`, supaya dua pukulan dalam detik yang sama = satu hati |

Kehilangan hati terjadi di **dunia**, bukan di `Actor`: `Actor` tetap hanya tahu
"aku dipukul" (sinyal `hurt`), sedangkan `CharacterWorld` yang memutuskan
harganya. Dengan begitu seluruh perbaikan fase 2 (hit-stop, re-flinch, watchdog)
tidak disentuh sama sekali.

### 14.2 Perisai yang benar-benar menahan

Sebelumnya tombol **Tahan** hanya memutar animasi `block`; pukulan tetap
dihitung. Sekarang `Actor.take_hit()` keluar lebih awal bila state = `block`:
kilau singkat, sinyal `hurt` tetap dikirim (dunia perlu tahu ada pukulan), tetapi
ksatria tidak terlempar ke animasi `hurt` dan tidak kehilangan hati. Jadi menahan
memang pilihan, bukan hiasan.

### 14.3 Terjatuh, lalu bangun — tanpa kehilangan apa pun

Hati habis → animasi `death` ksatria dimainkan, kontrol disembunyikan, pesan
"Kau terjatuh" muncul, lalu setelah 2,6 s ia bangun di awal jalan dengan tiga
hati. Counter `deaths` disimpan, tetapi **tidak ada** yang dihapus: orc yang sudah
dikalahkan tetap mati, flag cerita tetap ada, dan save ditulis ulang saat bangun.
Alasannya sederhana: hukuman yang menghapus progres membuat pemain berhenti
bermain, dan itu bukan jenis kesulitan yang diinginkan brief.

### 14.4 Panel tujuan

HUD kiri atas kini punya blok **TUJUAN** + **Nyawa x / 3**. Teks tujuan
diturunkan dari save, bukan dari variabel sesi:

| Kondisi save | Yang dibaca pemain |
| --- | --- |
| `orcs_defeated < 3` | "Bersihkan jalur — n dari 3 orc" |
| `orcs_defeated = 3`, flag `bram_ucap_terima_kasih` belum ada | "Kembali ke Penjaga Bram" |
| flag itu ada | "Jalur aman — teruskan perjalanan" |

Karena sumbernya save, menutup aplikasi di tengah jalan tidak menghilangkan
petunjuk berikutnya.

### 14.5 Jeda dan simpan manual

Tombol **Jeda** membuka lembar perkamen: *Lanjutkan*, *Simpan sekarang*,
*Peluncur*. Selama jeda `get_tree().paused = true`, tetapi lembar itu sendiri
memakai `PROCESS_MODE_WHEN_PAUSED`, jadi tombolnya tetap hidup sementara dunia
berhenti. "Simpan sekarang" memanggil jalur yang sama dengan autosave
(`save_progress()`); tidak ada penulis save kedua yang bisa menyimpang.

Catatan kecil: teks lama "Orc menghadang — pertempuran menyusul." dihapus. Itu
janji fitur yang tidak ada, dan sekarang orc memang menghadang.

Satu bug ditemukan justru lewat tangkapan layar ini: pukulan terakhir memanggil
`take_hit()` → sinyal `hurt` → dunia memanggil `die()` → **lalu** `take_hit()`
melanjutkan barisnya dan memutar animasi `hurt`, menimpa animasi `death`. Hasilnya
ksatria "mati sambil berdiri". Perbaikannya: `take_hit()` berhenti setelah sinyal
bila aktornya sudah mati. Pelajarannya: uji status saja tidak cukup, animasi yang
sedang diputar juga harus diperiksa.

---

## 15. Siklus hari dan atmosfer (0.4.0)

### 15.1 Satu angka, empat fase

Sebelum fase ini "waktu" hanyalah boolean: `set_time_of_day(true/false)` menukar
matahari ke satu malam tetap. Sekarang `WorldClock.gd` memegang satu angka 0–1
yang berjalan **480 detik per hari penuh** dan menurunkan semua yang berhubungan
dengan cahaya dari angka itu:

| Fase | Matahari | Ambien | Kabut | Lampu pondok |
| --- | --- | --- | --- | --- |
| pagi | 0,78 · putih kebiruan | 0,50 · biru lembut | **paling tebal (0,0090)** | 0,10 |
| siang | 1,15 · putih | 0,46 · netral | paling tipis (0,0034) | 0,00 |
| sore | 1,10 · emas | 0,47 · hangat | 0,0048 | 0,45 |
| malam | 0,30 · biru pucat | 0,34 · biru tua | 0,0048 | **1,25** |

Transisi memakai `smoothstep(0.62, 1.0, frac)`: cahaya duduk tenang di sebagian
besar fase lalu bergeser halus di sepertiga terakhir, jadi pemain membaca "sore"
sebagai sore, bukan sebagai slider yang terus bergerak.

`set_time_of_day(bool)` lama tetap ada dan hanya melompat ke fase; `VisualTest`
dan paket dunia lama tidak perlu diubah.

### 15.2 Atmosfer: empat sistem, bukan empat node yang lahir-mati

| Sistem | Muncul saat | Isi |
| --- | --- | --- |
| `dust` | pagi & siang | serbuk sari 4×4 px, melayang pelan |
| `petals` | sore | daun 12×7 px, jatuh miring |
| `fireflies` | malam | kunang-kunang 11×11 px, aditif (cahaya, bukan cat) |
| `fog` | pagi & malam | kabut tanah, kuad 7×4 m, alpha rendah |

Semua memakai `CPUParticles3D`, bukan GPU: renderer Compatibility di Android
kelas menengah tidak perlu membayar particle GPU untuk empat puluh butir debu.
`amount` tetap; yang berubah hanya alpha dan `emitting`, jadi tidak ada alokasi
saat jam berputar dan tidak ada "ledakan" partikel di pergantian fase.

Tekstur dibuat `tools/gen_atmosphere.py` (PNG sungguhan, skrip disimpan bersama
hasilnya, sama seperti `gen_ui_kit.py`).

### 15.3 Pelajaran mahal: dither pada kabut = kotak-kotak

Versi pertama memberi alpha ber-dither Bayer pada keempat tekstur, karena aturan
proyek melarang anti-aliasing. Tangkapan layar pertama fase ini memperlihatkan
akibatnya: **seluruh layar penuh kotak-kotak abu-abu**. Kuad kabut lebarnya 7 m,
jadi satu pola dither 2 px membesar menjadi ±7 px di layar dan mata membacanya
sebagai papan catur, bukan kabut.

Aturan yang sekarang dipegang:

* **cahaya dan kabut** (firefly, fog, dust) memakai alpha halus — cahaya memang
  kontinu, dan di ukuran itu dither terbaca sebagai artefak;
* **benda** (daun, sprite karakter, prop) tetap piksel keras tanpa anti-alias.

Daun juga diperbesar dari 6×4 ke 12×7: pada 6×4, saat diperbesar menjadi 20 px di
layar, bentuknya jadi kotak oranye yang tidak terbaca sebagai daun.

### 15.4 Yang bisa dilihat pemain

`docs/screenshots/17_pagi.png`, `18_sore.png`, `10_visual_siang.png`,
`11_visual_malam.png` — empat fase, satu diorama. Lampu jendela pondok menyala
sendiri saat sore dan menerangi ambang pintu sepanjang malam; kunang-kunang hanya
muncul setelah gelap.

---

## 16. Keputusan ukuran kanvas karakter (25 Okt 2026)

Brief §3 meminta kanvas **48×64**; aset yang sudah diverifikasi di Fase 2–3
adalah ksatria **112×96** dan penjaga/orc **100×100**. Pemilik memilih:
**48×64 untuk semua karakter baru** (FASE 4 dan seterusnya).

Konsekuensi yang dicatat:

* karakter yang ada **tidak** digambar ulang diam-diam; mereka tetap dipakai
  sampai ada aset 48×64 dari pemilik. Mengubahnya tanpa aset berarti mengarang
  sprite, dan itu dilarang;
* `world_pixel_size` 0,05 m tetap satu angka global; karakter 48×64 akan memakai
  `pixel_scale` per karakter supaya tingginya tetap ±1,6–1,8 m (dicatat di
  `characters/data/*.tres`, bukan ditebak di kode);
* uji `ValidateCharacters` + `CharacterTest` akan melaporkan ukuran frame
  sebenarnya, jadi kalau ada aset baru yang ukurannya beda, build gagal sebelum
  terlihat aneh di HP.

---

## 17. UI lengkap: kit, pengaturan, menu, jarak aman (0.5.0)

### 17.1 Satu kit, bukan dua salinan

`Main.gd` dan `DialogueBox.gd` masing-masing punya `_font`, `_tex`, `_nine`
sendiri. Dua salinan pasti melenceng (margin 20 px di satu tempat, 22 px di
tempat lain), dan parchment mulai terlihat seperti dua bahan berbeda.

Sekarang `game/ui/UiKit.gd` memegang: font (dengan tracking), pembacaan PNG dari
paket, nine-patch parchment, ikon 24×24, label, dan tombol. Aturannya: **UI baru
wajib lewat kit**; `DialogueBox.gd` yang sudah stabil dibiarkan dan dimigrasikan
saat ia disentuh lagi (migrasi besar tanpa alasan = risiko regresi).

Warna juga dipusatkan: `INK`, `INK_SOFT`, `BRASS`, `CREAM`, `DANGER`.

### 17.2 Ikon 24×24 dari skrip

`tools/gen_game_ui.py` menghasilkan 7 ikon: `heart_full`, `heart_empty`, `sun`,
`moon`, `gear`, `save`, `arrow_left`. Semua digambar sekali oleh skrip (PNG
sungguhan, NEAREST), palet hangat yang sama, outline 1 px.

Catatan desain dari percobaan pertama: matahari yang ditulis sebagai ASCII
terbaca seperti **koin**, dan gear sebagai ASCII terbaca seperti **bintang**.
Keduanya lalu digambar sebagai bentuk (cakram + 8 sinar, cincin + 8 gigi) dan
barulah keduanya terbaca. Hati dan scroll tetap ASCII karena bentuknya sederhana.

### 17.3 Pengaturan perangkat, terpisah dari save

`game/ui/Settings.gd` → `user://settings.json`, skema 1, tiga nilai:

| Kunci | Nilai | Efek |
| --- | --- | --- |
| `tilt_shift` | nyala/mati | `blur_pixels` 0 atau sesuai kualitas |
| `shake` | nyala/mati | `CharacterWorld.set_shake_scale(0/1)` |
| `quality` | rendah / sedang / tinggi | bayangan matahari, skala partikel atmosfer, blur, vignette |

Aturan yang sama dengan save: kunci yang hilang diisi bawaan, berkas rusak
kembali ke bawaan (dengan peringatan, bukan crash), dan **skema lebih baru tidak
ditimpa** — build lama tidak boleh merusak pilihan pemain dari build baru.

Kenapa terpisah dari save: menghapus progres tidak boleh mengembalikan blur, dan
mengubah grafik tidak boleh menyentuh cerita.

### 17.4 Menu dua halaman

Tombol **Jeda** membuka satu lembar parchment dengan dua halaman:

* **Jeda** — Lanjutkan · Simpan sekarang · Pengaturan · Peluncur, dengan satu
  baris status ("Orc 0 / 3 · Nyawa 3 / 3 · Sore") supaya pemain tahu posisinya
  tanpa menutup menu;
* **Pengaturan** — Tilt-shift · Getar kamera · Kualitas · Kembali. Setiap tekan
  langsung ditulis ke disk.

Perpindahan halaman memudar 0,16 s; lembar muncul dengan fade + skala 0,96 → 1,0.

**Bug yang tertangkap tangkapan layar, bukan uji:** tween yang dibuat saat tree
di-pause tidak pernah berjalan. `_pause_root.visible` sudah `true`, UiTest lulus,
tetapi alpha tetap 0 → menekan Jeda hanya membekukan dunia tanpa menampilkan
apa pun. Perbaikannya `Tween.set_pause_mode(TWEEN_PAUSE_PROCESS)` untuk semua
tween menu, dan UiTest sekarang juga memeriksa `modulate.a > 0,95`, bukan cuma
`visible`.

### 17.5 HUD: hati sebagai ikon, fase sebagai ikon

"Nyawa 3 / 3" diganti tiga ikon hati (penuh/kosong) — lebih cepat dibaca di layar
5 inci — dengan teks kecil di sampingnya, dan warna teks berubah merah kecokelatan
saat nyawa tinggal satu. Tambahan dari fase 6: ikon matahari/bulan + nama fase
(`Sore`) di panel tujuan.

### 17.6 Jarak aman dari notch

`Main._safe_insets()` membaca `DisplayServer.get_display_safe_area()` dan
menggeser semua jangkar HUD (plakat area, panel tujuan, tombol Jeda/Peluncur,
panel catatan, hint) sebesar inset kiri/atas, diskalakan dari piksel layar ke
kanvas 1280×720. Di desktop inset = 0, jadi tidak ada biaya. Ini yang membuat
plakat tidak tertutup poni (notch) atau sudut membulat di HP.

### 17.7 Tata letak paket: UI pindah ke `ui.pck`

Sampai fase ini `ui.pck` hampir kosong (dua font) dan `core.pck` membawa
parchment/crest/font. Sekarang:

* `core.pck` = `Main.tscn`, `Main.gd`, `UiKit.gd`, `Settings.gd` (kode saja);
* `ui.pck` = font, parchment, crest, divider, bg, dan 7 ikon.

Konsekuensinya update UI tidak lagi memaksa pemain mengunduh paket kode, dan
sebaliknya.

---

## 18. Optimasi Android (0.6.0)

Target brief: 30–60 FPS, paket sekecil mungkin, preset grafis. Isi fase ini:

### 18.1 Atlas ikon

Tujuh ikon 24×24 menjadi satu `atlas_ui.png` (182×26) + `atlas_ui.json` yang
dibuat `tools/gen_atlas.py`. `UiKit.icon()` membaca region lewat `AtlasTexture`.
Alasannya draw call: satu tekstur untuk seluruh HUD berarti satu bind, bukan
tujuh, dan di GPU HP itulah yang lebih terasa daripada ukuran berkasnya.

Yang dikirim di `ui.pck` hanya atlas; PNG tunggal tetap di repositori sebagai
sumber (dan fallback saat dijalankan dari editor). Supaya ikon yang lupa
dimasukkan ke atlas tidak menjadi tombol tak terlihat, `UiTest` memeriksa bahwa
**setiap** nama di `UiKit.ICONS` punya entri atlas, dan bahwa `icon()` benar-benar
mengembalikan `AtlasTexture`.

### 18.2 Preset grafis yang benar-benar menghemat

| Preset | Bayangan | Partikel | Blur | Skala 3D | Batas FPS |
| --- | --- | --- | --- | --- | --- |
| rendah | mati | ×0,35 | 1,2 | 0,78 | 30 |
| sedang | nyala | ×1,0 | 2,0 | 0,92 | 60 |
| tinggi | nyala | ×1,35 | 2,8 | 1,00 | 60 |

`Engine.max_fps` dipasang dari preset — ponsel yang merender 60 fps untuk game
yang animasinya 8–14 fps hanya menghangatkan kantong. `Viewport.scaling_3d_scale`
menurunkan resolusi 3D saja: sprite adalah kuad 2D, jadi yang mengendur lebih
dulu adalah detail tanah, bukan karakternya.

### 18.3 Alat ukur di perangkat, bukan di desktop

Menambahkan toggle **Tampilkan FPS** (bawaan mati) dan satu baris log tiap 5
detik:

```
[PERF] fps=52 kualitas=sedang skala3d=0.92 partikel=116 bayangan=true
```

Dengan begitu pemilik bisa membaca angka dari `adb logcat` di HP, bukan menebak
dari tangkapan layar CI yang memakai renderer software.

### 18.4 Audit paket: 1,7 MB sampah ditemukan

`tools/pack_audit.py` membaca daftar paket dari `FixtureBuilder.gd`, lalu:

* memastikan setiap path benar-benar ada (galat);
* memastikan setiap aset **disebut** di kode/resource — aset yang hanya muncul di
  daftar paket berarti tidak ada yang memuatnya (galat);
* melaporkan path yang dipakai dua paket dan total byte per paket.

Hasil pertama: `bg.png` 1,17 MB terpaket di **dua** paket tanpa satu baris kode
memuatnya (dibuang di 0.5.0), dan `arrow_100.png`/`arrow_32.png` terpaket untuk
pemanah yang belum ada (dikeluarkan; tetap di `assets_src` sampai job pemanah
dibuat). Sekarang audit bersih: **6 paket, 0 galat**, dan langkah ini menjadi
gerbang CI supaya kebiasaan itu tidak kembali.

### 18.5 Yang belum dikerjakan di fase ini

**Kompresi tekstur ETC2/ASTC belum diterapkan.** Alasannya teknis, bukan lupa:
paket kita adalah arsip `PCKPacker` berisi PNG mentah tanpa `.import`, dan game
memuatnya sebagai byte (`Image.load_png_from_buffer`) — justru itu yang membuat
update paket bisa mengganti aset tanpa membangun ulang proyek. Mengompres ke
ETC2/ASTC berarti salah satu dari dua hal:

1. membangun `.ctex`/`.res` terkompresi di CI (menambah langkah impor Godot dan
   mengubah cara pack dibuat), atau
2. memanggil `Image.compress(COMPRESS_ETC2)` saat memuat di perangkat — hemat
   VRAM, tetapi menambah waktu muad dan berisiko membuat pixel art bertepi keras
   tampak kabur pada alpha.

Keduanya perlu diukur di HP sungguhan sebelum dipilih, jadi keputusannya saya
tinggalkan untuk pemilik; angka VRAM sekarang masih kecil (±0,7 MB total paket,
karakter 100×100 dan 112×96). Ini satu-satunya butir brief FASE 8 yang belum
selesai, dan saya tidak mau mengklaimnya sudah.

## 19. Lapangan, minimap dan kamera (langkah 1)

Tujuan langkah ini satu kalimat: **layar lapangan harus hampir kosong**. Dunia
yang jadi bintang; UI hanya muncul saat perlu. Semua yang dulu menetap di layar
— kotak tujuan, tiga hati, paragraf narasi, angka FPS, tombol Jeda dan Peluncur —
pindah ke dalam satu menu, atau hilang sama sekali.

### 19.1 Apa yang tersisa di lapangan

| Posisi | Isi | Catatan |
| --- | --- | --- |
| kiri atas | minimap 20 % tinggi layar | bingkai kulit + tepi kuningan, bukan kotak perkamen besar |
| bawah minimap | ikon matahari/bulan + satu kata | tanpa panel: ikonnya menempel di dunia |
| kanan atas | **satu** tombol Menu (ikon roda gigi + label) | Jeda dan Peluncur ada di dalamnya |
| kanan bawah | **satu** tombol aksi kontekstual | Bicara / Masuk / Periksa / Ambil; memudar bila tak ada target |
| kiri bawah | stik jalan | mengambang (bawaan) atau tetap, sesuai Pengaturan |
| tengah atas | banner nama lokasi | 3 detik, geser masuk lalu pudar |
| tepi layar | panah tujuan + jarak meter | hanya bila tujuan di luar pandangan |

Yang **tidak** ada lagi: kotak "Tujuan", hati "Nyawa", paragraf narasi kiri
bawah, teks FPS permanen, tombol Jeda/Peluncur terpisah, dan tombol Serang/Tahan.

### 19.2 Minimap dari data, bukan kamera kedua

`game/world/WorldMap.gd` menyimpan tanah sebagai grid: 26×20 ubin, 1 m per ubin,
enam jenis (rumput, tanah, air, batu, hutan, bangunan) dengan palet hangat yang
sama dengan perkamen dan rumput diorama. `Diorama.gd` mengecat grid itu dari
`LAYOUT` dan `PATH` yang **sudah** dipakai untuk menaruh prop, jadi peta tidak
mungkin melenceng dari dunia yang digambarnya.

Kenapa data: kamera kedua berarti satu render pass penuh tambahan di HP, untuk
gambar yang isinya kotak warna. Grid beberapa ratus bit jauh lebih murah.

Biaya dijaga di tiga tempat:

* jendela minimap **tetap** 14 ubin (dekat) atau 34 ubin (jauh) — peta 10× lebih
  besar tidak menambah satu piksel pun tekstur minimap (diuji F19–F21);
* tekstur dibangun ulang hanya saat pemain **pindah ubin** atau ada ubin fog yang
  baru terbuka (`fog_revision`), bukan tiap frame;
* peta penuh (tab Peta / ketuk minimap) adalah satu-satunya tempat yang
  membangun gambar seluruh peta, dan itu tindakan pemain, bukan tiap frame.

Interaksi: satu ketukan = peta penuh, dua ketukan = dua tingkat zoom minimap.

**Fog of war** disimpan sebagai string bit 520 karakter (satu karakter per ubin)
di dalam `fog` pada save, lengkap dengan `schema`, ukuran peta dan ukuran ubin.
Save skema 1 mendapat `fog: {}` lewat rantai migrasi — artinya "belum pernah ke
mana-mana", bukan "peta rusak". Fog dari peta berukuran lain atau dari skema yang
lebih baru **ditolak utuh** (peta tetap seperti sebelumnya), alasannya dicatat.

### 19.3 Kamera: mengikuti, berhenti di tepi, zoom menempel

| Parameter | Nilai | Kenapa |
| --- | --- | --- |
| pitch / yaw | −38° / −22° | sudut diorama; tidak pernah berubah |
| FOV | 30° | sempit, seperti kamera mainan |
| zoom | 11 … 32 m, **diturunkan otomatis** oleh ukuran peta | di lembah 26×20 batas nyatanya ±21 |
| tangga zoom | 11 · 12 · 12,5 · 14 · 16 · 18 · 20 · 22,5 · 25 · 28 · 32 | pinch berhenti di anak tangga, bukan 17,43 |
| dead zone | 0,55 m | gambar tenang saat pemain berhenti |
| laju ikut | 4,5 per detik | menyusul tanpa menyentak |
| jarak fokus dialog | ×0,86 | lensa mendekat saat bicara |

Pan satu jari **dihapus**: satu jari milik stik. Dua jari masih boleh menggeser
pandangan (dan mencubit untuk zoom), lalu kamera mengambil alih lagi setelah 1,2
detik. `recentre()` (tombol di menu / nanti ketuk ganda) mengembalikan lensa ke
pemain.

Batas gerak dihitung dari apa yang **benar-benar terlihat** lensa pada zoom saat
itu: separuh lebar dan separuh kedalaman frame, dikali 0,9, dibatasi 45 % dari
separuh peta. Konsekuensinya, di peta kecil pemain boleh bergeser dari tengah
layar saat mendekati tepi — memang itu yang diminta — dan di peta besar batas itu
tidak pernah terasa.

**Yang belum sempurna, dan saya tidak menyembunyikannya:** pada lembah 26×20 m,
zoom 19° menampilkan tanah lebih luas daripada petanya, jadi di pojok selatan
kadang masih terlihat "rok" tanah gelap di luar batas. Itu bukan void (tidak ada
lubang hitam), tetapi juga bukan jawaban final. Jawaban finalnya peta yang lebih
besar — langkah 2. Batas zoom otomatis di atas sudah dibuat supaya begitu peta
membesar, masalah ini hilang tanpa mengubah satu angka pun.

### 19.4 Ukuran sentuh, notch, dan satu tombol "ukuran UI"

Kanvas desain 1280×720 di-*stretch* mengikuti tinggi layar. Di HP 2340×1080
(±400 dpi) satu piksel desain = 1,5 piksel perangkat ≈ 0,6 dp, jadi:

* 48 dp ≈ **80 piksel desain** → `UiKit.TOUCH_MIN = 80`
* 72 dp ≈ **120 piksel desain** → tombol aksi `TOUCH_BIG = 132`

Safe area diambil dari `DisplayServer.get_display_safe_area()`; inset kiri/atas
dipakai juga untuk kanan/bawah (di landscape, notch dan sudut membulat saling
berdekatan, dan empat angka terpisah hanya menambah cara untuk salah).

**Ukuran UI** satu knop: `Settings.ui_scale()` mengembalikan 0,86 / 1,0 / 1,14 dan
`UiKit.apply_layer_scale()` mengalikan transform CanvasLayer HUD dan menu. Tidak
ada daftar ukuran font kedua yang bisa basi saat ada tombol baru.

Ikon baru (satu keluarga, grid 24×24, palet yang sama): `talk`, `door`,
`inspect`, `take`, `map`, `close`, `book`. Atlas ikon kini 14 sel (364×26 px).

### 19.5 Satu menu

Tombol Menu membuka **satu** lembar perkamen dengan tujuh tab: **Lanjut, Jurnal,
Peta, Inventori, Pengaturan, Simpan, Peluncur**. Dunia berhenti selama panel
terbuka (tween panel memakai `TWEEN_PAUSE_PROCESS`, jadi panelnya tetap hidup —
bug yang sama pernah terjadi pada menu fase 7).

* Jurnal memuat tujuan aktif, progres orc, nyawa, waktu bermain, dan paragraf
  narasi area yang dulu menetap di layar;
* Inventori: 16 kotak tertata dengan teks "Belum ada isi." — bukan kotak rusak;
* Pengaturan: grafis, ukuran UI, sensitivitas stik, stik mengambang/tetap, mode
  debug, tampilkan FPS (hanya muncul saat mode debug), tilt-shift, getar;
* Peluncur minta **dua** ketukan.

### 19.6 Papan nama penjaga

Satu tambahan kecil yang muncul saat bermain sungguhan: kalau ksatria berdiri
dalam jangkauan bicara, `DialogueBox` menampilkan **papan nama** — potret
penjaga, namanya, dan satu kalimat ("Orc masih berkeliaran di tepi hutan…").
Alasannya jujur: tanpa itu, satu-satunya cara memberi tahu "orang ini bisa
diajak bicara" adalah teks bantu melayang tepat di atas kepalanya — dan teks
melayang di atas kepala adalah hal pertama yang membuat layar terasa ramai.
Papan nama memakai wadah yang sama dengan dialog (jadi tetap satu gaya), hilang
sendiri saat pemain melangkah pergi, dan tidak pernah muncul bersamaan dengan
tombol Bicara di layar yang sama saat dialog berjalan.

### 19.7 Dialog

Ringkas, di bawah layar, satu strip: potret berbingkai, nama, teks mengetik, dan
"ketuk untuk lanjut" di pojok. Tombol Lanjut dihapus — seluruh layar adalah
tombolnya. **Potret diambil dari strip idle karakter itu sendiri** (bingkai
pertama, dipangkas, diisi ke kanvas 3:4). Tidak ada wajah yang digambar lewat
kode, dan tidak ada potret placeholder. Kalau nanti pemilik mengirim
`portrait.png` di folder karakter, berkas itu yang dipakai lebih dulu.

### 19.8 Uji dan tangkapan layar

Gate headless baru `FieldTest` (23 pemeriksaan): data peta untuk beberapa ukuran,
fog yang berpindah lewat save, jendela minimap yang tidak tumbuh, kamera yang
tidak bisa keluar peta di tiga arah pada dua ukuran peta, tangga zoom, minimap
pada peta 26×20 dan 160×120, tombol aksi yang muncul/memudar menurut jarak, dan
dialog yang tidak menimpa minimap/tombol menu.

Tangkapan layar CI bertambah: `22_lapangan`, `22b_lapangan_kosong`, `22c_stik`,
`23_banner`, `24_dialog`,
`25_jurnal`, `26_peta`, `27_fog`, `28_rasio_20x9`, `29_rasio_4x3`, plus
`20_menu`/`21_pengaturan` yang digambar ulang.

### 19.9 Batas langkah ini

* Peta besar bertingkat **belum ada** (itu langkah 2). Semua antarmuka yang
  dibutuhkan sudah bekerja pada ukuran peta berapa pun, tetapi isi dunia masih
  satu lembah.
* Pertarungan **belum ada**. Karena tombol Serang/Tahan dihapus, orc tidak lagi
  memukul: mereka berpatroli, menghadang, dan memicu pemberitahuan. Kerusakan
  real-time dimatikan lewat `CharacterWorld._combat_live` (bawaan mati) —
  bukan karena lupa, tetapi karena damage tanpa cara menjawab itu tidak adil.
  `_strike_orcs()` disimpan untuk layar pertarungan nanti.
* `KIND_WATER` sudah ada di data dan palet, tetapi diorama belum punya kolam.
  Saya tidak menambahkan air yang tidak ada di dunia hanya agar legendanya genap.
* FPS di HP tetap belum diukur dari sandbox ini.

### 19.10 Dua perbaikan kecil dari tangkapan layar

**Label tombol aksi ditulis kapital.** Pada 20 px, huruf kecil "c" di Pixelify
Sans punya ekor bawah yang membuat **"Bicara"** terbaca **"Bigara"** — terlihat
di tangkapan layar `22_lapangan` versi 1280×720. Alih-alih menebak ukuran font
yang lebih besar (yang bisa mendorong label keluar dari lingkaran 132 px),
label sekarang memakai huruf kapital pada 18 px: perbedaan huruf besar/kecil
selalu terbaca, berapa pun kerapatan pikselnya. Semua label tombol
(`BICARA`/`MASUK`/`PERIKSA`/`AMBIL`) lewat satu jalur `to_upper()`.

**Stik difoto dalam keadaan didorong.** Stik mengambang hanya muncul saat ibu
jari menyentuh layar, jadi tangkapan layar HUD kosong selalu tampak "tanpa
stik". Harness tangkapan memanggil `TouchControls.preview_stick(true)`, yang
menggambar pangkalan + kenop pada posisi dorong **tanpa** menggerakkan ksatria
(tidak menyentuh `stick_vector`). Hanya dipakai CI; permainan tidak pernah
memanggilnya. Sekalian opasitas stik dinaikkan tipis (cincin 0,22 → 0,30; kenop
0,36 → 0,50) karena di tangkapan layar pertama cincinnya nyaris hilang di atas
rumput terang — ibu jari harus bisa menemukannya tanpa melihat ke bawah.
