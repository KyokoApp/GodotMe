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
