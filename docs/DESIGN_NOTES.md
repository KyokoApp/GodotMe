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
