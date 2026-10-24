# Re - Traveller

RPG piksel HD-2D bergaya dongeng fantasi, dibuat dengan Godot 4.7.2 untuk
Android (landscape).

Repo ini punya **dua proyek terpisah**, persis seperti arsitektur yang diminta:

| Folder | Proyek | Keluaran | Isi |
| --- | --- | --- | --- |
| `launcher/` | **A — Peluncur** | APK (± 29 MB) | splash, layar update bertema, pengunduh, verifikasi SHA-256, pemuat paket, rollback. Tidak berisi logika atau aset game. |
| `game/` | **B — Game** | `.pck` per modul | seluruh game. Diunduh launcher; APK tidak pernah diganti untuk update konten. |

Pemain memasang APK **sekali**. Setelah itu semua update — kode, karakter,
dunia, UI, audio — datang sebagai paket yang diunduh, diperiksa, lalu dimuat.

---

## Mulai cepat

**Pemain / uji di HP**

1. Unduh `re-traveller-launcher.apk` dari
   [rilis demo `demo-v0.1.0`](https://github.com/KyokoApp/GodotMe/releases/tag/demo-v0.1.0)
   (manifest-nya sudah publik, jadi langsung jalan tanpa hosting sendiri).
2. Pasang (izinkan "instal dari sumber tidak dikenal"), buka.
3. Launcher membaca `version.json`, mengunduh paket, lalu tombol **MAIN** aktif.

**Pengembang**

```bash
# 1. uji semuanya (butuh Godot 4.7.2 + python3)
GODOT=/path/to/godot-4.7.2 tools/run_launcher_tests.sh

# 2. buat rilis game baru (pack -> version.json + tanda tangan)
python3 tools/make_release.py --version 1.2.0 \
    --packs core=build/core.pck characters=build/characters.pck \
    --out dist/v1.2.0 --sign-key ~/retraveller_manifest_private.pem

# 3. unggah isi dist/v1.2.0/ ke hosting (atau GitHub Release)
```

Panduan lengkap: [`docs/BUILD_AND_RELEASE.md`](docs/BUILD_AND_RELEASE.md).

---

## Struktur repo

```
launcher/                  PROYEK A - APK
  project.godot            engine terkunci 4.7.2, landscape, gl_compatibility
  scripts/
    Config.gd              satu-satunya tempat konfigurasi (MANIFEST_URL, dll.)
    Log.gd                 jurnal + berkas log
    Store.gd               versi terpasang, paket content-addressed, rollback, GC
    Guard.gd               sentinel boot + watchdog (anti game rusak)
    UpdateManager.gd       cek → delta unduh → verifikasi → pasang → muat
    Http.gd                HTTPClient + Range resume + deteksi stall
    Manifest.gd            validasi + verifikasi tanda tangan
    Hasher.gd              SHA-256 streaming
    PackLoader.gd          load_resource_pack berurutan + boot scene
    Util.gd                util JSON/berkas/format angka
  ui/                      tema, 30+ tekstur bitmap, font OFL
  scenes/Launcher.tscn     layar update
  tests/                   TestRunner + FixtureBuilder (tidak ikut ke APK)
  icon/                    ikon Android (adaptive)

game/                      PROYEK B - PAKET
  game/Main.gd|tscn        scene utama paket contoh (menulis boot_ok)
  game/assets/             aset contoh

tools/                     generator seni/UI, make_release.py, testserver.py, driver uji
docs/                      DESIGN_NOTES, CREDITS, GAME_CONTRACT, BUILD_AND_RELEASE,
                           TEST_PLAN, screenshots/
.github/workflows/ci.yml   parse check + 11 skenario uji + screenshot + APK
.github/workflows/release-demo.yml   paket + APK + GitHub Release + verifikasi URL
```

---

## Dokumentasi

* [`docs/DESIGN_NOTES.md`](docs/DESIGN_NOTES.md) — versi engine, palet, tipografi,
  aturan UI, pelajaran desain.
* [`docs/CREDITS.md`](docs/CREDITS.md) — sumber & lisensi semua aset.
* [`docs/GAME_CONTRACT.md`](docs/GAME_CONTRACT.md) — kontrak launcher ↔ game
  (layout `res://game/`, manifest, boot_ok, versi skema save).
* [`docs/BUILD_AND_RELEASE.md`](docs/BUILD_AND_RELEASE.md) — ekspor PCK, manifest,
  tanda tangan, hosting, APK, kebijakan distribusi.
* [`docs/TEST_PLAN.md`](docs/TEST_PLAN.md) — 11 skenario uji + hasilnya.
* [`docs/PHASE1_REPORT.md`](docs/PHASE1_REPORT.md) — laporan Fase 1 lengkap
  (arsitektur, ukuran APK/paket, tabel hasil uji, cara menjalankan, risiko).

---

## Status fase

* **FASE 1 — Launcher: selesai.** Lihat [`docs/PHASE1_REPORT.md`](docs/PHASE1_REPORT.md).
* FASE 2 — proyek game, kamera HD-2D, diorama pertama: belum dimulai.

Aset karakter/musuh/dunia untuk fase berikutnya belum ada di repo ini — sesuai
brief, pack karakter akan dipilih dengan lisensi aman dan dicatat di
`docs/CREDITS.md` sebelum dipakai.
