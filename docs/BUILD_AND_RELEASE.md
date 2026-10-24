# BUILD & RELEASE — Re - Traveller

Panduan lengkap: dari nol sampai pemain menerima update, **tanpa memasang
ulang APK**. Setiap langkah bisa dijalankan dari HP lewat GitHub Actions
(bagian 6) atau dari komputer dengan Godot 4.7.2 terpasang.

> **Versi engine terkunci: Godot 4.7.2-stable** (lihat `docs/DESIGN_NOTES.md`).
> Launcher dan paket game harus diekspor dengan versi engine yang sama.

---

## 1. Yang perlu disiapkan sekali

| Kebutuhan | Keterangan |
| --- | --- |
| Godot 4.7.2-stable | Editor + *Export Templates* versi yang sama |
| Android SDK | build-tools + platforms; hanya untuk membuat APK |
| JDK 17 | untuk Gradle/apksigner |
| Python 3 | untuk `tools/make_release.py` |
| `openssl` | untuk tanda tangan manifest |

Di repo ini semuanya sudah diotomasi di `.github/workflows/ci.yml`; tidak ada
yang perlu dipasang di komputer kalau memakai jalur CI.

---

## 2. Ekspor paket game (PCK)

Proyek game ada di `game/` (sekarang masih paket contoh; nanti diganti proyek
game penuh). Buat **enam preset ekspor** di `game/export_presets.cfg`, satu per
paket, semuanya platform *PCK/ZIP* dan bukan APK:

| Preset | Filter yang disertakan | Contoh folder di proyek game |
| --- | --- | --- |
| `core` | `game/**/*.gd`, `game/**/*.tscn`, `game/**/*.tres` | `game/` |
| `characters` | `game/characters/**` | `game/characters/` |
| `enemies` | `game/enemies/**` | `game/enemies/` |
| `world` | `game/world/**` | `game/world/` |
| `ui` | `game/ui/**` | `game/ui/` |
| `audio` | `game/audio/**` | `game/audio/` |

Contoh isi satu preset (`game/export_presets.cfg`):

```ini
[preset.1]

name="core"
platform="Linux"          ; platform apa pun; yang diekspor hanya .pck
runnable=false
export_filter="resources"
include_filter="game/*.gd, game/*.tscn, game/**/*.tres"
exclude_filter="game/characters/*, game/enemies/*, game/world/*, game/ui/*, game/audio/*"
export_path="build/core.pck"

[preset.1.options]

binary_format/embed_pck=false
```

Ekspor (headless, bisa diulang):

```bash
for p in core characters enemies world ui audio; do
  godot --headless --path game --export-pack "$p" "build/$p.pck"
done
```

> **Penting:** setiap berkas game harus di bawah `res://game/` — lihat
> `docs/GAME_CONTRACT.md`. Launcher menolak boot bila `main_scene` keluar dari
> `res://game/`.

Ukuran paket contoh saat ini: core 26 KB, characters 1 KB, enemies 0,6 KB,
world 1,1 MB, ui 26 KB, audio 0,4 KB.

---

## 3. Susun rilis (manifest + hash)

```bash
python3 tools/make_release.py \
  --version 1.2.0 \
  --packs core=build/core.pck characters=build/characters.pck \
          enemies=build/enemies.pck world=build/world.pck \
          ui=build/ui.pck audio=build/audio.pck \
  --changelog "Rambut dan jubah karakter diperbarui." \
  --changelog "Bayangan di biome salju diperhalus." \
  --out dist/v1.2.0 \
  --sign-key ~/retraveller_manifest_private.pem
```

Hasil:

```
dist/v1.2.0/
  version.json
  version.json.sig
  packs/core.pck ... packs/audio.pck
```

Skrip ini:
1. menyalin tiap `.pck` ke `packs/` dengan **nama tanpa versi**
   (`packs/core.pck`), sehingga server bisa menimpa berkas yang berubah saja;
2. menghitung `size` + `sha256` tiap paket;
3. mengisi `load_order` sesuai urutan muat (core 10 … audio 60);
4. menulis `version.json` (`main_scene`, `changelog`, `min_launcher_version`);
5. menandatangani manifest secara terpisah (`openssl dgst -sha256 -sign`)
   lalu menyimpan base64-nya di `version.json.sig`.

Cek manifest tanpa menulis apa pun: tambahkan `--dry-run`.

`min_launcher_version` otomatis diambil dari `Config.LAUNCHER_VERSION`. Naikkan
hanya bila game benar-benar butuh launcher/engine baru.

---

## 4. Tanda tangan manifest

Sekali saja:

```bash
openssl genrsa -out retraveller_manifest_private.pem 2048
openssl rsa -in retraveller_manifest_private.pem -pubout \
        -out launcher/signing/public_key.pem
```

* `launcher/signing/public_key.pem` **di-commit** (ikut masuk APK).
* `retraveller_manifest_private.pem` **jangan** di-commit (sudah di `.gitignore`).
* Aktifkan kewajiban tanda tangan: `Config.REQUIRE_SIGNATURE = true`, atau
  `--require-signature=1` saat menjalankan launcher, atau
  `{"require_signature": true}` di `user://retraveller/launcher_settings.json`.
  Disarankan baru diaktifkan setelah rilis pertama dengan kunci asli, karena
  launcher lama di tangan pemain tidak punya kunci tersebut.

---

## 5. Unggah ke hosting

Struktur folder di server harus sama persis dengan hasil `make_release.py`:

```
https://hosting-anda/re-traveller/
    version.json
    version.json.sig
    packs/core.pck
    packs/characters.pck
    packs/enemies.pck
    packs/world.pck
    packs/ui.pck
    packs/audio.pck
```

Aturan hosting:

* **HTTPS wajib** (Android memblokir HTTP polos untuk aplikasi rilis).
* Harus mendukung **HTTP Range** (`Accept-Ranges: bytes`) agar unduhan bisa
  dilanjutkan. GitHub Releases, Cloudflare R2, S3, Bun/CDN statis umumnya
  mendukung; beberapa penyedia gratis tidak.
* Jangan pakai URL bertanda tangan yang kedaluwarsa — launcher menyimpan URL
  manifest sampai rilis berikutnya.

Lalu ubah satu konstanta saja di `launcher/scripts/Config.gd`:

```gdscript
const MANIFEST_URL: String = "https://hosting-anda/re-traveller/version.json"
```

`MANIFEST_URL_FALLBACK` boleh diisi URL cermin kedua.

**Jalur tanpa server sendiri (dipakai default repo ini):** unggah isi
`dist/v1.2.0/` sebagai aset **GitHub Release** dengan tag rilis, lalu pakai
`https://github.com/<owner>/<repo>/releases/latest/download/version.json`.
Alamat `latest/download/` selalu menunjuk rilis terbaru, jadi `MANIFEST_URL`
tidak pernah berubah.

---

## 6. Semua dari HP (GitHub Actions)

Workflow `.github/workflows/ci.yml` menjalankan:

1. **parse check** — semua skrip GDScript dikompilasi;
2. **test matrix** — 11 skenario launcher (lihat `docs/TEST_PLAN.md`), satu job
   per skenario, log tiap job otomatis ditempel sebagai komentar di Pull Request;
3. **screenshots** — mengambil tangkapan layar launcher dan meng-commit-nya ke
   `docs/screenshots/`;
4. **build launcher APK** — menghasilkan artefak `re-traveller-launcher-apk`.

Menjalankan dari HP: buka repo di aplikasi GitHub → tab **Actions** →
**ci** → **Run workflow**. Unduh APK dari bagian *Artifacts* run tersebut.

Membuat rilis game dari HP: lihat `docs/BUILD_AND_RELEASE.md` bagian 7
(pakai GitHub Release untuk hosting, atau jalankan `make_release.py` di
Termux).

---

## 7. Rilis lewat GitHub Release (disarankan)

```bash
# 1. siapkan folder rilis
python3 tools/make_release.py --version 1.2.0 --packs ... --out dist/v1.2.0 \
        --sign-key ~/retraveller_manifest_private.pem

# 2. buat rilis + unggah seluruh isi folder (manifest harus ikut)
gh release create game-v1.2.0 dist/v1.2.0/version.json dist/v1.2.0/version.json.sig \
        dist/v1.2.0/packs/*.pck -t "Game 1.2.0" -n "Catatan rilis"

# 3. pastikan manifest bisa diakses dan tiap paket menjawab Range
curl -sL https://github.com/<owner>/<repo>/releases/latest/download/version.json | head
curl -sI -H "Range: bytes=0-63" \
     https://github.com/<owner>/<repo>/releases/latest/download/<nama_paket>.pck | grep -i "206\|content-range"
```

Launcher akan otomatis melihat `version.json` terbaru pada peluncuran
berikutnya dan hanya mengunduh paket yang `sha256`-nya berubah.

> **Aset GitHub Release itu datar** — tidak ada sub-folder. Karena
> `MANIFEST_URL` default memakai `releases/latest/download/<url>`, kolom `url`
> di manifest harus berupa nama berkas saja (`core_100.pck`), bukan
> `packs/core_100.pck`. Kalau memakai `tools/make_release.py` yang menulis
> `packs/<file>`, ubah `url` menjadi nama berkas saat mengunggah ke GitHub
> Release, atau pakai `tools/publish_release.sh` yang sudah menangani ini:
>
> ```bash
> # folder datar: version.json + <paket>.pck + APK launcher
> REL=dist/v1.2.0-flat TAG=game-v1.2.0 REPO=<owner>/<repo> tools/publish_release.sh
> ```
>
> Skrip itu menolak menerbitkan bila daftar paket di manifest dan berkas di
> folder tidak sama persis, dan menghapus aset lama sebelum mengunggah ulang
> supaya paket yang sudah tidak dipakai tidak tertinggal.

---

## 8. Membuat APK launcher

Hanya perlu bila launcher berubah (mis. `Config.MANIFEST_URL` diganti, kunci
publik ditanam, ikon baru) atau versi engine naik.

```bash
# siapkan editor settings sekali: path Android SDK, path JDK, debug keystore
godot --headless --path launcher --import
godot --headless --path launcher --export-debug "Android" dist/re-traveller-launcher.apk

# untuk rilis (APK bertanda tangan kunci rilis)
godot --headless --path launcher --export-release "Android" dist/re-traveller-launcher.apk
```

### Kunci tanda tangan: pakai variabel lingkungan

Godot membaca kunci dari **variabel lingkungan lebih dulu** daripada preset
(`EditorExportPreset::get_or_env`), jadi tidak perlu menyunting
`export_presets.cfg` — dan kunci pribadi tidak pernah masuk repo:

```bash
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/keystore.jks
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=nama_alias
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=rahasia
godot --headless --path launcher --export-release "Android" dist/re-traveller-launcher.apk

# selalu periksa hasilnya: ekspor bisa "berhasil" menulis APK tanpa tanda tangan
$ANDROID_HOME/build-tools/<ver>/apksigner verify --print-certs dist/re-traveller-launcher.apk
```

Di GitHub Actions, isi ketiganya dari repository secret
(`env: GODOT_ANDROID_KEYSTORE_RELEASE_PATH: ...`). Yang penting: nama variabel
password adalah `..._PASSWORD`, bukan `..._PASS`. Kalau hanya sebagian yang
diisi, Godot menolak ekspor dengan pesan *"Either Release Keystore, Release User
AND Release Password settings must be configured OR none of them."*

Preset `Android` sudah disetel di `launcher/export_presets.cfg`:
`arm64-v8a` saja (APK kecil), landscape, `permissions/internet=true`,
`permissions/access_network_state=true`, **tanpa izin lain**, ikon adaptif dari
`launcher/icon/`, paket aplikasi `app.retraveller.launcher`.

Izin Android lengkap yang dipakai:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

> `ACCESS_NETWORK_STATE` dipakai hanya untuk memberi pesan "tidak ada internet"
> yang jelas; kalau ingin benar-benar minimal, matikan baris itu di preset —
> launcher tetap berfungsi (hanya pesannya lebih umum).

---

## 9. Uji sebelum mengumumkan rilis

```bash
GODOT=/path/to/godot tools/run_launcher_tests.sh          # 11 skenario
GODOT=/path/to/godot tools/run_launcher_tests.sh resume   # satu skenario
```

Untuk uji manual di HP, arahkan launcher ke manifest uji tanpa membangun ulang:

```bash
adb shell "run-as app.retraveller.launcher sh -c 'echo https://.../version.json > files/retraveller/manifest_url.txt'"
```

(Atau pakai build uji dengan `Config.MANIFEST_URL` berbeda.)

---

## 10. Catatan kebijakan distribusi

* Distribusi saat ini: **APK langsung (sideload)**. Ini tidak melanggar
  kebijakan Google Play karena tidak lewat Play.
* Bila nanti ingin masuk **Google Play**: aplikasi yang mengunduh kode yang
  dapat dieksekusi (GDScript di dalam `.pck`) **berisiko melanggar** kebijakan
  *Device and Network Abuse* / *Deceptive Behavior* Play, dan Google kadang
  mensyaratkan pembaruan lewat Play. Jangan putuskan sendiri — konsultasikan
  dulu, dan siapkan opsi: (a) tetap sideload, (b) rilis konten hanya sebagai
  aset non-eksekusi, (c) kirim game penuh di APK dan pakai `.pck` hanya untuk
  aset. Launcher saat ini murni untuk sideload.
* Kunci penandatanganan APK: simpan baik-baik. APK dengan kunci berbeda tidak
  bisa menimpa instalasi lama (pemain harus uninstall dulu, progres `user://`
  ikut hilang).

---

## 11. Kalau perlu naik versi engine

Naik engine = **APK baru** (satu-satunya alasan selain perubahan launcher):

1. Ubah `GODOT_VERSION` di CI, pasang editor + template baru.
2. Uji ulang seluruh skenario.
3. Naikkan `Config.LAUNCHER_VERSION`.
4. Ekspor ulang paket game dengan engine baru, rilis dengan
   `min_launcher_version` = versi launcher baru, sehingga pemain dengan APK
   lama diberi tahu bahwa mereka perlu memasang APK baru (dan tetap bisa
   memainkan versi lama sampai memasangnya).

---

## 12. Paket karakter & pipeline sprite (tahap sprite)

### Isi `characters.pck`

Paket ini sekarang memuat **seluruh** lapisan karakter: skrip
(`CharacterDef`, `CharacterAssets`, `Actor`, `Npc`, `Enemy`, `CharacterWorld`,
`TouchControls`, `DialogueBox`), dua shader kecil (`blob_shadow`, `dust_puff`),
tiga definisi (`characters/data/{knight,soldier,orc}.tres`), dan semua strip
PNG di `game/assets/characters/<id>/` berikut berkas lisensinya. Daftar
lengkapnya ada di `launcher/tests/FixtureBuilder.gd` (`PACK_FILES["characters"]`)
— **setiap berkas baru wajib didaftarkan di sana**, kalau tidak ia tidak akan
pernah ikut ke dalam paket.

`world.pck` tetap sama sejak tahap 1. `core.pck` ikut berubah karena `Main.gd`
sekarang menambahkan lapisan karakter ke dalam diorama.

### Nama berkas paket sengaja tidak berubah

Rilis memakai nama stabil (`characters_100.pck`, `core_100.pck`, …) dan
`version.json` menyebut versi **0.2.0**. Alasannya: launcher menghitung selisih
dari **hash**, bukan dari nama. Kalau nama berkas dinaikkan versinya, URL semua
paket berubah dan HP akan mengunduh ulang paket yang sebenarnya tidak berubah.
Dengan nama stabil, update tahap ini hanya mengunduh `core.pck` +
`characters.pck`; `world.pck`, `ui.pck`, `enemies.pck`, `audio.pck` dilewati
karena hash-nya sama.

### Memeriksa aset karakter (dijalankan CI, bisa juga manual)

```bash
# 1. kontrak strip: lebar PNG harus = jumlah frame x lebar frame
python3 -m venv /tmp/venv && /tmp/venv/bin/pip install pillow       # sekali
/tmp/venv/bin/python tools/import_character_sprites.py --check       # gagal = exit 1
/tmp/venv/bin/python tools/import_character_sprites.py --report      # inventaris + pivot

# 2. data + SpriteFrames di dalam Godot (gagal = exit 1)
godot --headless --path game res://game/tests/ValidateCharacters.tscn

# 3. dua scene uji visual
godot --path game res://game/tests/CharacterTest.tscn
godot --path game res://game/tests/VisualTest.tscn -- --time=night
godot --path game res://game/tests/VisualTest.tscn -- --dialog=page     # 12_dialog
godot --path game res://game/tests/VisualTest.tscn -- --dialog=choices  # 13_pilihan
```

Kalau `--check` gagal, **jangan** mengakali dengan memotong gambar: perbaiki
sumbernya di `assets_src/characters/<id>/`, lalu jalankan
`--import` untuk menyalin ulang dan memperbarui pivot di `.tres`.

### Menambah karakter baru

1. Taruh strip di `assets_src/characters/<id>/` (huruf kecil, `snake_case`,
   tanpa spasi atau `&` di nama berkas).
2. Tambahkan satu entri di `SPEC` pada `tools/import_character_sprites.py`
   (kanvas, daftar animasi + jumlah frame + fps + loop, `pixel_scale`,
   `walk_stride_m`, `body_radius_m`).
3. `python3 tools/import_character_sprites.py --import` → menyalin PNG ke
   `game/game/assets/characters/<id>/` dan menulis `characters/data/<id>.tres`.
4. Daftarkan berkas-berkasnya di `PACK_FILES["characters"]`.
5. Taruh di dunia lewat `CharacterWorld.gd` (satu baris `_spawn(...)`).

Tidak ada nama karakter yang ditulis di kode game; semuanya membaca `.tres`.

### Save pemain

Tahap ini **belum punya sistem save** (yang ada hanya `user://retraveller/active.json`
dan `boot_ok.json` milik peluncur, dan keduanya tidak disentuh). Jadi tidak ada
data pemain yang bisa hilang oleh pembaruan paket. Sistem save berversi adalah
tahap berikutnya.

### Rilis demo-v0.1.0, paket versi 0.2.0 (tahap sprite) — terbit 25 Okt 2026

Rilis yang sama (`demo-v0.1.0`, selalu jadi `releases/latest`) diperbarui lewat
`.github/workflows/release-demo.yml`; `RELEASE_DEMO` di akar repo adalah
pemicunya. Isi rilis setelah pembaruan:

| Aset | Ukuran | Berubah di tahap ini? |
| --- | --- | --- |
| `re-traveller-launcher.apk` | 29.428.024 B | tidak (APK tetap peluncur; build id `rt-launcher-v2-main-fix`) |
| `characters_100.pck` | 153.884 B | **ya** — 3 `.tres`, 9 skrip, 25 strip PNG, lisensi/sumber |
| `world_100.pck` | 1.614.884 B | **ya** — warna jalur (`path.gdshader`), `Diorama.gd` |
| `core_100.pck` | 41.056 B | **ya** — penanda build |
| `enemies_100.pck` | 612 B | tidak |
| `ui_100.pck` | 26.540 B | tidak |
| `audio_100.pck` | 352 B | tidak |
| `version.json` | 1.735 B | **ya** — `version` 0.2.0 + changelog + SHA-256 tiap paket |

**Kenapa namanya tetap `characters_100.pck`, bukan `characters_101.pck`?**
Nomor di nama berkas adalah tag build internal (fixture CI memakai `100` dan
`110` untuk menguji delta), sedangkan yang dibaca launcher adalah
`version.json` → `url: "characters.pck"` dari `releases/latest/download/`.
Menambah angka di nama berkas hanya akan membuat URL baru tanpa memberi tahu
launcher apa pun; yang menentukan "perlu unduh atau tidak" adalah **SHA-256**
per paket di manifest. Isi paket berubah, hash berubah, launcher mengunduh
`characters.pck` + `world.pck` saja.

Langkah di HP: buka launcher → **Periksa Lagi** → unduh paket yang berubah →
**MAIN**. Save pemain tidak tersentuh karena **belum ada sistem save** di tahap
ini; satu-satunya state di `user://retraveller/` milik launcher
(`active.json`, `boot_ok.json`) dan tidak diubah oleh tahap sprite.

Verifikasi yang dijalankan CI untuk rilis ini: `periksa` strip
(`tools/import_character_sprites.py --check`), gate headless
`ValidateCharacters.tscn`, empat scene tangkapan (09/10/11/12/13), 13 skenario
peluncur, dan pemeriksaan `BUILD_ID` di dalam APK sebelum aset diunggah.
