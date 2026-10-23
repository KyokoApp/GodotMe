# LANTERNFALL — ASSET CREDITS & LISENSI (PART 1)

Dokumen ini memuat atribusi resmi untuk seluruh aset eksternal siap pakai berlisensi aman (CC0 1.0 Public Domain & CC-BY 4.0) yang direferensikan atau dinormalisasi ke dalam proyek **LANTERNFALL**, serta daftar kata kunci pencarian untuk ekspansi aset tambahan. Seluruh atribusi ini juga ditampilkan secara langsung pada layar **Kredit** di dalam game (`scenes/ui/TouchHUD.tscn` -> `CreditsPanel`).

## 1. Tabel Aset Terverifikasi yang Digunakan / Direferensikan

| Nama Aset / Pack | Pembuat / Studio | Sumber Resmi (URL Terverifikasi) | Lisensi | Penggunaan di LANTERNFALL |
| :--- | :--- | :--- | :--- | :--- |
| **Ultimate Stylized Nature Pack** | Quaternius | [quaternius.com/packs/ultimatestylizednature.html](https://quaternius.com/packs/ultimatestylizednature.html) | CC0 1.0 (Public Domain) | Pepohonan rendah poligon, tebing pulau, semak, batu lumut di Desa Rembang, Pulau Embun, dan Hutan Jamur Senja |
| **Medieval Village Pack** | Quaternius | [quaternius.com/packs/medievalvillage.html](https://quaternius.com/packs/medievalvillage.html) | CC0 1.0 (Public Domain) | Pondok kayu, dermaga, menara lentera tua, gudang pelabuhan, dan struktur Pondok Nara |
| **Ships Pack** | Quaternius | [quaternius.com/packs/ships.html](https://quaternius.com/packs/ships.html) | CC0 1.0 (Public Domain) | Perahu layar kecil pemain (`BoatController.gd`) dan bangkai kapal di Pelabuhan Karam |
| **Nature Kit (3D Low-Poly)** | Kenney | [kenney.nl/assets/nature-kit](https://kenney.nl/assets/nature-kit) | CC0 1.0 (Public Domain) | Jembatan gantung, batu pijakan sungai kabut, kayu apung, dan penanda jalan |
| **Tiny Dungeon & Tiny Town** | Kenney | [kenney.nl/assets?search=tiny+dungeon](https://kenney.nl/assets?search=tiny+dungeon) | CC0 1.0 (Public Domain) | Ikon item inventori, peti harta tersembunyi, botol minyak lentera, senjata tombak/dayung, dan bahan kerajinan |
| **RPG Urban Pack** | Kenney | [kenney.nl/assets/rpg-urban-pack](https://kenney.nl/assets/rpg-urban-pack) | CC0 1.0 (Public Domain) | Basis prop lentera jalan, bangku kayu, tenda pedagang keliling, dan kotak kargo dermaga |
| **Input Prompts & UI Pack** | Kenney | [kenney.nl/assets](https://kenney.nl/assets) | CC0 1.0 (Public Domain) | Tombol aksi sentuh (>=48dp), bingkai jurnal pastel, indikator interaksi kontekstual, dan ikon kategori |
| **CC0 Walk Cycles & 3/4 Directional Sprite Sets** | Technopeasant & Kontributor OGA | [opengameart.org/content/cc0-walk-cycles](https://opengameart.org/content/cc0-walk-cycles) / [opengameart.org/content/34-directional-sprite-sets](https://opengameart.org/content/34-directional-sprite-sets) | CC0 1.0 (Public Domain) | Basis template proporsi sprite karakter 4-arah (32x48 px) untuk Nara, 6 NPC Pulau Embun, dan kelasi |
| **RPG Audio, Impact Sounds & Interface Sounds** | Kenney | [kenney.nl/assets/category:Audio](https://kenney.nl/assets/category:Audio) | CC0 1.0 (Public Domain) | Efek suara langkah kaki (`sfx_step.wav`), ayunan senjata (`sfx_swing.wav`), benturan (`sfx_hit.wav`), dan ketukan UI (`sfx_ui_tap.wav`) |
| **CC0 Fantasy Music & Sounds** | Kontributor OpenGameArt | [opengameart.org/content/cc0-fantasy-music-sounds](https://opengameart.org/content/cc0-fantasy-music-sounds) | CC0 1.0 (Public Domain) | Ambience angin kabut Selimut, derit kayu dermaga, dan lonceng lentera (`sfx_quest_chime.wav`) |
| **Royalty-Free Ambient & Folk Tracks** (*Teller of the Tales*, *Suonatore di Liuto*, *Evening Fall Harp*) | Kevin MacLeod | [incompetech.com/music/royalty-free/music.html](https://incompetech.com/music/royalty-free/music.html) | CC-BY 4.0 | Musik latar redup akustik untuk Desa Rembang, Pulau Embun, dan Hutan Jamur Senja (wajib mencantumkan kredit Kevin MacLeod) |

## 2. Normalisasi Gaya Visual & Palet Global

Agar seluruh aset dari pembuat yang berbeda menyatu ke dalam satu dunia **2.5D Pixel Gelap Pastel (Bukan Cyber)**, proyek ini menerapkan tiga aturan penyeragaman otomatis:
1. **Ukuran Sprite Standar**: Seluruh karakter dan NPC dinormalisasi ke kanvas sel **32×48 piksel** (`pixel_size = 0.032` pada `Sprite3D`, `texture_filter = Nearest`), sementara ikon item menggunakan ukuran **16×16 piksel** yang di-upscale bulat.
2. **Palet Global Pastel Redup**: Seluruh tekstur lingkungan dan sprite melewati kuantisator warna dan shader `res://shaders/lantern_restore.gdshader` dengan enam warna inti:
   - *Outline Arang Senja*: `#231F2E`
   - *Lavender Kabut*: `#9B8CB8`
   - *Biru Teh Redup*: `#6E8B9E`
   - *Peach Kusam*: `#D49B87`
   - *Hijau Lumut Lembap*: `#7A9A7E`
   - *Krem Lentera Hangat*: `#F2E6D0`
3. **Render SubViewport Nearest-Neighbor**: Dunia 3D dirender ke `SubViewport` beresolusi rendah (`640×360`) dengan `stretch_shrink = 2` pada `SubViewportContainer`, menghasilkan tepian piksel yang tegas di layar Android modern.

## 3. Daftar Aset Spesifik Tambahan yang Dapat Dicari Mandiri (Kata Kunci Pencarian)

Jika kamu ingin mengganti atau memperkaya variasi animasi spesifik (misalnya 8-arah penuh untuk Boss atau variasi jamur raksasa bercahaya), berikut adalah daftar kata kunci pencarian terverifikasi di **itch.io**, **OpenGameArt**, dan **Freesound**:

| Kebutuhan Aset | Situs Tujuan | Kata Kunci Pencarian & Filter Lisensi | Alternatif Pack Nyata yang Bisa Diperiksa |
| :--- | :--- | :--- | :--- |
| **Sprite Ngengat / Roh Pendamping (Kelip)** | OpenGameArt / itch.io | `"moth sprite sheet" OR "butterfly pixel art" license:CC0` | 1) *Bevouliin Free Flying Monster Sprite Sheets* ([opengameart.org](https://opengameart.org/)); 2) *Kenney Pixel Platformer Flying Critters* ([kenney.nl/assets](https://kenney.nl/assets)) |
| **Monster Jamur & Bayangan (8 Jenis Musuh)** | itch.io / OpenGameArt | `"mushroom monster pixel" OR "shadow creature 4 direction" tag:pixel-art free` | 1) *Enemies and Characters (Pixel Art)* ([opengameart.org/content/enemies-and-characters-pixel-art](https://opengameart.org/content/enemies-and-characters-pixel-art)); 2) *Quaternius Bestiary Dungeon Monsters* ([quaternius.com](https://quaternius.com/)) |
| **Portrait Ekspresi Dialog NPC (6 Emosi)** | itch.io / OpenGameArt | `"48x48 faces" OR "RPG portrait pack pastel" license:CC0` | 1) *48x48 Faces Sheet* di koleksi Characters OGA ([opengameart.org/content/characters-7](https://opengameart.org/content/characters-7)) |
| **Suara Kobaran Lentera & Angin Laut Kabut** | Freesound.org | `"lantern fire crackle loop" OR "harbor creak wind" license:"Creative Commons 0"` | Filter `License: Creative Commons 0`, format `.wav` / `.ogg` 44.1kHz mono untuk `AudioStreamPlayer3D` |
