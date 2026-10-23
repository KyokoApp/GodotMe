# LANTERNFALL (Part 1: Lentera Terakhir) — Game Design & Technical Document

**Engine Target:** [Godot Engine 4.7.2 Stable](https://godotengine.org/download/archive/4.7.2-stable/) (`GL Compatibility` / OpenGL ES 3)  
**Bahasa Pemrograman:** GDScript 2.0 dengan *static typing* penuh  
**Target Platform:** Android (`arm64-v8a`, `minSdk 24`, `targetSdk 34`, *offline single-player*, hanya input sentuh)

## 1. Struktur Folder & Arsitektur Proyek

Proyek dirancang modular tanpa ketergantungan silang (*zero hardcode data inside logic scripts*):

```text
LANTERNFALL_Godot47/
├── project.godot                   # Konfigurasi Godot 4.7, GL Compatibility, input sentuh, autoloads
├── default_bus_layout.tres         # Audio Bus: Master, BGM, SFX, Ambient
├── export_presets.cfg              # Preset ekspor Android (arm64-v8a, minSdk 24, debug keystore)
├── build_android.sh                # Skrip otomatis pembuatan keystore & build APK/AAB via CLI
├── autoload/
│   ├── EventBus.gd                 # Sinyal global terketik untuk komunikasi antar-sistem
│   ├── GameState.gd                # State pemain, mata uang, pohon skill, bendera moral Part 2
│   ├── SaveSystem.gd               # JSON 3 slot, auto-save pindah chunk, migrasi versi v1->v2->v3
│   └── AudioBus.gd                 # Object pool AudioStreamPlayer untuk SFX & crossfade BGM
├── shaders/
│   ├── lantern_restore.gdshader    # Shader Toon 3-step + transisi monokrom Senyap ke palet pastel
│   ├── sway_foliage.gdshader       # Goyangan rumput/jamur responsif angin & radius lentera
│   ├── water_fog_sea.gdshader      # Riak permukaan Lautan Kabut "Selimut"
│   └── post_vignette_colorblind.gdshader # Post-processing vignette senja & 3 mode buta warna
├── resources/
│   ├── classes/                    # Definisi class_name Resource (ItemData, RecipeData, EnemyData, QuestData, DialogNodeData)
│   ├── items/                      # 12 file .tres item, senjata, jubah, lentera, masakan
│   ├── enemies/                    # 10 file .tres (8 musuh reguler + 2 Boss multi-fase)
│   └── quests/                     # 8 file .tres quest utama bercabang & quest sampingan bercerita
├── scenes/
│   ├── main/GameRoot.tscn          # SubViewport 640x360 upscale nearest-neighbor + World3D + TouchHUD
│   ├── entities/Player.tscn        # Nara + Sprite3D billboard + OmniLight3D Lentera + Kelip
│   └── ui/TouchHUD.tscn            # Virtual joystick kiri, tombol kanan >=48dp, dialog, kredit
├── scripts/
│   ├── entities/                   # PlayerController.gd, EnemyController.gd, NPCController.gd
│   ├── world/                      # WorldStreamer.gd, DayNightWeather.gd, BoatController.gd, Camera25DRig.gd
│   ├── systems/                    # EconomyManager.gd, InventorySystem.gd, CraftingSystem.gd, DialogueManager.gd, PondokAndProgression.gd
│   └── ui/                         # TouchHUDController.gd
├── translations/
│   └── lanternfall_id_en.csv       # Tabel lokalisasi Bahasa Indonesia & Inggris
└── assets/                         # Spritesheet 32x48 pastel terkuantisasi, ikon UI, dan efek suara WAV PCM
```

## 2. Ringkasan Pengerjaan per Milestone (M1 – M7)

### Milestone 1 (M1): Gerak, Kamera 2.5D, Render Pixel & Kontrol Sentuh
* **File yang Dikerjakan:** `project.godot`, `scenes/main/GameRoot.tscn`, `scripts/world/Camera25DRig.gd`, `shaders/lantern_restore.gdshader`, `shaders/post_vignette_colorblind.gdshader`, `scenes/ui/TouchHUD.tscn`, `scripts/ui/TouchHUDController.gd`.
* **Implementasi Inti:** Dunia 3D low-poly dirender melalui `SubViewport` berukuran `640×360` dengan filter `Nearest` (`canvas_item_default_texture_filter = 0`) dan di-*upscale* 2× ke layar `1280×720`. Kamera miring `-40°` dengan FOV rendah (`32°`) menjaga estetika diorama 2.5D. Kontrol sentuh memisahkan paruh kiri layar untuk *floating virtual joystick* dan paruh kanan untuk 5 tombol aksi berukuran minimal `68×68 px` (> `48dp`), dilengkapi *raycast tap-to-interact* pada objek 3D serta penyesuaian otomatis *safe area* layar berponi (*notch*).

### Milestone 2 (M2): Animasi Hidup, State Machine & Combat Real-Time
* **File yang Dikerjakan:** `autoload/EventBus.gd`, `autoload/GameState.gd`, `autoload/AudioBus.gd`, `scenes/entities/Player.tscn`, `scripts/entities/PlayerController.gd`, `scripts/entities/EnemyController.gd`, `resources/classes/EnemyData.gd`, `resources/enemies/*.tres`.
* **Implementasi Inti:** Gerakan Nara memakai akselerasi (`26.0`) dan deselerasi (`32.0`) mulus, *squash-and-stretch* prosedural saat mengayun senjata dan berguling, *hit-stop* `2–3 frame` (`Engine.time_scale = 0.08`), *screen shake* terukur, serta *auto-aim assist* ke musuh terdekat dalam radius `4.5m`. Mekanik **Minyak Cahaya** melucuti perisai bayangan *Senyap* (`senyap_armor_active = false`) dan mengaktifkan kelemahan cahaya (`1.25×` hingga `1.60×` damage). Seluruh 8 jenis musuh dan 2 Boss memiliki indikator *telegraph* oranye terang sebelum menyerang.

### Milestone 3 (M3): Dunia Chunk Kepulauan, Siklus Hari/Cuaca & Perahu
* **File yang Dikerjakan:** `scripts/world/WorldStreamer.gd`, `scripts/world/DayNightWeather.gd`, `scripts/world/BoatController.gd`, `shaders/sway_foliage.gdshader`, `shaders/water_fog_sea.gdshader`, `autoload/SaveSystem.gd`.
* **Implementasi Inti:** Kepulauan di atas Lautan Kabut "Selimut" dibagi ke dalam *chunk* berukuran `48×48m` yang dimuat dan dibersihkan secara dinamis berdasarkan jarak Chebyshev pemain, ditambah *manual distance culling* (`42m`) untuk menjaga 60 FPS di perangkat mobile. Cuaca mengubah mekanik secara nyata: **Hujan Abu** mempercepat konsumsi Minyak Cahaya sebesar `+0.18/detik`, **Kabut Tipis** mempersempit jarak deteksi musuh, dan **Angin Selimut** mempercepat laju perahu layar.

### Milestone 4 (M4): Inventori Grid, Crafting, Pondok Pemain & Ekonomi Dinamis
* **File yang Dikerjakan:** `scripts/systems/InventorySystem.gd`, `scripts/systems/CraftingSystem.gd`, `scripts/systems/EconomyManager.gd`, `scripts/systems/PondokAndProgression.gd`, `resources/classes/ItemData.gd`, `resources/classes/RecipeData.gd`, `resources/items/*.tres`, `ECONOMY_BALANCE.csv`.
* **Implementasi Inti:** Inventori *grid* mendukung tumpukan (*stack*), batas beban (`25.0 kg` awal), dan 3 tingkat upgrade tas. Sistem Pondok Nara memungkinkan pemain meningkatkan Lentera Halaman, Rak Gudang, Tungku Masak, dan Meja Tempa.

### Milestone 5 & 6 (M5 – M6): Dialog Bercabang, Lokalisasi, Prolog – Bab 3 & Finale Part 1
* **File yang Dikerjakan:** `scripts/systems/DialogueManager.gd`, `scripts/entities/NPCController.gd`, `resources/classes/QuestData.gd`, `resources/quests/*.tres`, `translations/lanternfall_id_en.csv`, `STORY_SCRIPT_PART1.md`.
* **Implementasi Inti:** Sistem dialog bercabang dengan penyimpan bendera moral (*story flags*) dan perubahan reputasi faksi. Menyelesaikan seluruh alur cerita Part 1 dari **Prolog (Desa Rembang)**, **Bab 1 (Pulau Embun + Boss Penjaga Kabut)**, **Bab 2 (Hutan Jamur Senja + Twist Guru Soka)**, **Bab 3 (Pelabuhan Karam + Boss Nakhoda Abu)**, hingga **Finale Part 1 (Pertemuan Sang Pemadam)** yang menyimpan pilihan moral ke `GameState.story_flags["part1_ending_moral_choice"]` untuk Part 2.

### Milestone 7 (M7): Polish, Optimasi Mobile, Save Migrasi & Build APK
* **File yang Dikerjakan:** `export_presets.cfg`, `build_android.sh`, `android/keystore/debug.keystore`.
* **Implementasi Inti:** Mode hemat baterai 30 FPS, 3 mode aksesibilitas buta warna (Protanopia, Deuteranopia, Tritanopia), layar atribusi Kredit di dalam game, serta skrip *build* otomatis APK Android (`arm64-v8a`).

## 3. Rumus Matematika Ekonomi & Pengendalian Inflasi

Ekonomi **LANTERNFALL** dirancang sebagai sistem tertutup tanpa *microtransaction* (tanpa IAP, tanpa iklan) yang mengutamakan eksplorasi dan penyelesaian cerita di atas *farming* berulang:

1. **Rumus Harga Beli Pedagang (`FinalBuyPrice`)**:
   $$\text{Harga Beli} = \max\left(1, \text{round}\left(P_{\text{dasar}} \times M_{\text{pulau}} \times M_{\text{reputasi}} \times M_{\text{peristiwa}} \times 1.15\right)\right)$$
   - $P_{\text{dasar}}$: Harga dasar item di `ECONOMY_BALANCE.csv`.
   - $M_{\text{pulau}}$: Modifier suplai-permintaan lokal pulau (`0.75` untuk komoditas lokal melimpah hingga `1.35` untuk barang impor langka).
   - $M_{\text{reputasi}} = \text{clamp}(1.0 - 0.002 \times R_{\text{faksi}}, 0.80, 1.15)$: Diskon hingga 20% pada reputasi penuh (`+100`) atau penalti 15% jika reputasi buruk.
   - $M_{\text{peristiwa}}$: Diskon `0.92` jika pemain memilih membela nelayan pada cabang Quest Utama Bab 1.

2. **Rumus Harga Jual Pemain & Anti-Grind Diminishing Return (`FinalSellPrice`)**:
   $$\text{Harga Jual} = \max\left(1, \text{round}\left(P_{\text{dasar}} \times M_{\text{pulau}} \times M_{\text{jenuh}} \times 0.65\right)\right)$$
   - $M_{\text{jenuh}} = \max(0.40, 1.0 - 0.035 \times Q_{\text{terjual}})$: Setiap unit barang identik yang dijual berulang menurunkan harga belinya sebesar `3.5%` hingga batas bawah `40%`. Nilai $Q_{\text{terjual}}$ pulih perlahan (`-3 unit` setiap 120 detik bersamaan dengan *restock* stok pedagang).
   - Dengan mekanik ini, *farming* monster yang sama terus-menerus menghasilkan imbal hasil menurun, sedangkan berdagang lintas pulau (misalnya membawa **Ikan Kabut** dari Pulau Embun `0.80` ke Hutan Jamur `1.25`, atau **Spora Jamur** `0.75` ke Pulau Embun `1.30`) dan menuntaskan quest memberikan keuntungan bersih yang sehat (`+35` s/d `+55 Koin Embun` per jam bermain).

## 4. Profil Performa Mobile & Target Anggaran Teknis

Dirancang khusus untuk smartphone Android kelas menengah (SoC setara Snapdragon 680 / Helio G99, RAM 4 GB, GPU Adreno 610 / Mali-G57) dengan renderer **GL Compatibility (OpenGL ES 3)**:

| Metrik Performa | Target Anggaran (HP RAM 4GB) | Hasil Arsitektur LANTERNFALL Part 1 | Teknik Optimasi yang Diterapkan |
| :--- | :--- | :--- | :--- |
| **Resolusi Render Internal** | `640×360` (Upscale `1280×720`) | `640×360` (`stretch_shrink = 2`) | Mengurangi beban *fragment shader* sebesar 75% dibanding render native 1080p |
| **Frame Rate (Normal / Hemat Baterai)** | `60 FPS` / `30 FPS` | `60 FPS` stabil / Kunci `30 FPS` | `Engine.max_fps` dinamis di `GameState.apply_runtime_settings()` |
| **Draw Calls per Frame** | `< 120 draw calls` | `45 – 85 draw calls` | Satu chunk aktif + tetangga dekat, *manual distance culling* `42m`, shared `ShaderMaterial` |
| **Penggunaan VRAM & RAM** | `< 350 MB RAM` | `~145 MB RAM` / `~48 MB VRAM` | Tekstur piksel terkuantisasi ukuran kecil, audio SFX pooled (8 channel) |
| **Lampu Real-Time Aktif** | Maksimal 4 per layar | 1 `DirectionalLight3D` + 1 `OmniLight3D` Lentera + maks 2 suar | Lampu lentera di luar radius chunk dinonaktifkan otomatis |

## 5. Cara Menjalankan di Godot 4.7 & Langkah Build APK/AAB

1. **Membuka & Menjalankan di Editor**:
   - Unduh dan buka [Godot Engine 4.7.2 Stable](https://godotengine.org/download/archive/4.7.2-stable/).
   - Klik **Import**, arahkan ke folder `LANTERNFALL_Godot47/project.godot`, lalu tekan **Import & Edit**.
   - Tekan **F5** (atau tombol *Play*). Karena `emulate_touch_from_mouse=true` aktif, kamu bisa langsung menguji *virtual joystick* kiri dan tombol aksi kanan menggunakan mouse di PC, atau langsung mengekspor ke perangkat Android.
2. **Membangun File APK / AAB melalui Baris Perintah (CLI)**:
   - Pastikan Android SDK (`minSdk 24`, `targetSdk 34`) dan template ekspor Godot 4.7 sudah terpasang.
   - Jalankan skrip otomatis yang sudah disertakan:
     ```bash
     cd LANTERNFALL_Godot47
     ./build_android.sh
     ```
   - Untuk menghasilkan **Android App Bundle (`.aab`)** bagi Google Play Store, ubah `gradle_build/export_format=0` menjadi `1` di `export_presets.cfg`, lalu jalankan perintah ekspor yang sama.
3. **Daftar Hal yang Masih Bisa Dikembangkan Menuju Part 2**:
   - Impor model `.glb` dekorasi tambahan dari paket Quaternius untuk memperkaya variasi siluet tebing di perbatasan chunk.
   - Penambahan cabang pohon skill tingkat 4 (Mastery) saat batas level dinaikkan di Part 2.
