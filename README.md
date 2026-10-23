# 🏮 LANTERNFALL — Part 1: Lentera Terakhir

Game **2.5D dark-pastel action RPG** offline single-player, dibuat dengan **Godot 4.7.2 Stable** (renderer `GL Compatibility` / OpenGL ES 3), kontrol penuh sentuh, target **Android `arm64-v8a`** (minSdk 24 / Android 7.0+, targetSdk 34).

| | |
| :--- | :--- |
| **Engine** | Godot 4.7.2 Stable |
| **Paket Android** | `id.rembangstudio.lanternfall` |
| **Scene utama** | `res://scenes/main/GameRoot.tscn` |
| **Versi** | `1.0.0-part1` (`project.godot` → `config/version`) |
| **Platform** | Android `arm64-v8a` (offline, single-player) |

> **Catatan riwayat repo:** repo ini sebelumnya berisi **KyokoBeat** (music player React + Capacitor). Seluruh berkasnya sudah dibersihkan; kalau perlu lagi, masih tersimpan di branch `main` / riwayat Git (`git log 7894ff8`).

---

## 1. Cara cepat: dapatkan APK-nya

APK dibangun otomatis oleh GitHub Actions (`.github/workflows/build-android.yml`):

1. Buka tab **Actions** → workflow **Build LANTERNFALL APK** → **Run workflow**.
2. Centang **"Unggah APK ke GitHub Release"** kalau mau langsung dipublikasikan.
3. Tunggu selesai → APK ada di:
   - **Artifact** `LANTERNFALL-APK` (selalu diunggah), atau
   - **Releases** → asset `LANTERNFALL.apk`.

Atau unduh rilis terbaru langsung:

```
https://github.com/KyokoApp/GodotMe/releases/latest/download/LANTERNFALL.apk
```

**Pasang di HP Android:** unduh `LANTERNFALL.apk` → izinkan *"Install unknown apps"* untuk browser/kamu → buka berkasnya → Install.

Rilis juga otomatis dibuat setiap kali ada **tag `v*`** yang di-push.

---

## 2. Build lokal

Butuh `godot` 4.7.2-stable di `PATH` + export templates 4.7.2.stable terpasang + Android SDK (untuk `apksigner`).

```bash
# Sekali saja: daftarkan path Android SDK & Java SDK ke editor settings Godot
python3 scripts/setup-godot-ci.py --sdk "$ANDROID_HOME" --java "$JAVA_HOME"

# Build APK debug (pakai debug keystore bawaan repo)
./scripts/build_android.sh

# Build APK release (butuh keystore rilis, lihat §3)
./scripts/build_android.sh release
```

Hasilnya: `build/LANTERNFALL_Part1_arm64.apk`

Satu baris manual kalau mau pakai Godot CLI langsung:

```bash
godot --headless --path . --import
godot --headless --path . --export-release "Android (arm64-v8a Release/Debug)" build/LANTERNFALL.apk
```

---

## 3. Penandatanganan APK (signing)

Tanpa konfigurasi apa pun, CI **tetap menghasilkan APK yang bisa dipasang** — ditandatangani dengan debug keystore (`android/keystore/debug.keystore`). Konsekuensinya: setiap rilis beda tanda tangan, jadi pembaruan harus **uninstall dulu**.

Supaya rilis konsisten (bisa update tanpa uninstall + siap ke Play Store), siapkan keystore rilis lalu simpan sebagai **GitHub Secrets**:

```bash
keytool -genkeypair -v \
  -keystore lanternfall-release.keystore \
  -alias lanternfall \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass <PASSWORD> -keypass <PASSWORD> \
  -dname "CN=LANTERNFALL,O=Rembang Studio,C=ID"

base64 -w0 lanternfall-release.keystore > keystore.b64
```

Lalu di **Settings → Secrets and variables → Actions** tambahkan:

| Secret | Isi |
| :--- | :--- |
| `KEYSTORE_BASE64` | isi `keystore.b64` (base64, 1 baris) |
| `KEYSTORE_ALIAS` | `lanternfall` |
| `KEYSTORE_PASSWORD` | password keystore |

Kalau ketiga secret terisi, workflow otomatis memakai `--export-release`; kalau tidak, fallback ke `--export-debug`. `version.json` ikut diperbarui dan diunggah ke release.

---

## 4. Struktur proyek

```text
.
├── project.godot                  # Konfigurasi Godot 4.7, GL Compatibility, autoload, sentuh
├── export_presets.cfg             # Preset ekspor Android (arm64-v8a, non-gradle)
├── default_bus_layout.tres        # Audio bus: Master, BGM, SFX, Ambient
├── autoload/                      # EventBus, GameState, SaveSystem, AudioBus
├── scenes/
│   ├── main/GameRoot.tscn         # SubViewport 640×360 (pixel upscale) + World3D + TouchHUD
│   ├── entities/Player.tscn       # Nara: Sprite3D billboard + OmniLight3D lentera + Kelip
│   └── ui/TouchHUD.tscn           # Joystick virtual kiri, 5 tombol aksi kanan, dialog, kredit
├── scripts/
│   ├── entities/                  # PlayerController, EnemyController, NPCController
│   ├── world/                     # WorldStreamer, DayNightWeather, BoatController, Camera25DRig
│   ├── systems/                   # Economy, Inventory, Crafting, Dialogue, Progression
│   ├── ui/                        # TouchHUDController
│   ├── build_android.sh           # Build APK lokal
│   └── setup-godot-ci.py          # Tulis Android/Java SDK ke editor settings (CI)
├── resources/                     # classes/ (Resource), items/, enemies/, quests/ (.tres)
├── shaders/                       # lantern_restore, sway_foliage, water_fog_sea, post_vignette
├── assets/                        # sprites + SFX WAV PCM
├── translations/                  # lanternfall_id_en.csv (ID + EN)
├── android/keystore/              # debug.keystore (keystore rilis TIDAK di-commit)
├── docs/                          # GDD, story script, asset credits, economy balance
└── .github/workflows/             # build-android.yml
```

---

## 5. Catatan penting

- **Mode ekspor non-gradle.** `gradle_build/use_gradle_build=false` supaya build APK di CI cuma butuh export template + `apksigner` (tanpa Android Gradle Plugin). Konsekuensinya `minSdk`/`targetSdk` memakai nilai bawaan template Godot 4.7 (`24` / `36`) — itu sudah sesuai target. Untuk bikin **AAB / upload ke Play Store** atau mengubah SDK, setel kembali ke `true` dan pasang *Android Build Template* dari editor (Project ▸ Install Android Build Template).
- **Kompresi tekstur ETC2/ASTC** (`rendering/textures/vram_compression/import_etc2_astc`) wajib `true`; tanpa itu Godot menolak ekspor Android.
- **Translasi:** `locale/translations` harus menunjuk file `.translation` hasil import (`lanternfall_id_en.id.translation`, `.en.translation`), bukan CSV-nya. File itu dibuat otomatis saat `godot --headless --import` dan tidak di-commit (lihat `.gitignore`).
- **Ikon proyek** `assets/sprites/ui/icon_lantern.png` berukuran 64×64 dan dipakai sebagai ikon launcher. Untuk hasil terbaik di HP, ganti dengan PNG ≥ 192×192 (atau isi opsi *Launcher Icons* di preset ekspor).
- **Aset eksternal:** lihat `docs/ASSET_CREDITS.md` — sebagian besar CC0 1.0, ada musik Kevin MacLeod berlisensi **CC-BY 4.0** yang wajib dikreditkan di layar Kredit game.
- **Dokumen desain:** `docs/GDD_LANTERNFALL.md` (arsitektur + milestone M1–M7), `docs/STORY_SCRIPT_PART1.md` (naskah), `docs/ECONOMY_BALANCE.csv` (balans ekonomi).
- **Validasi:** seluruh 22 skrip GDScript lolos parse GDScript 2.0 (`gdparse`), dan semua referensi `res://` di `.tscn`/`.tres`/`.gd` terpenuhi.

---

## 6. Lisensi

Kode proyek ini mengikuti lisensi pemilik repo. Aset pihak ketiga mengikuti lisensi masing-masing — lihat [`docs/ASSET_CREDITS.md`](docs/ASSET_CREDITS.md).
