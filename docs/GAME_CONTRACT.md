# KONTRAK LAUNCHER ↔ GAME

Dokumen ini adalah kesepakatan yang mengikat **Proyek A (launcher)** dan
**Proyek B (game)**. Launcher tidak tahu apa pun soal isi game selain kontrak
ini. Selama kontrak dipatuhi, game bisa diganti total lewat unduhan paket.

## 1. Letak berkas di dalam paket

Semua berkas game **wajib** berada di bawah `res://game/`.

```
res://game/Main.tscn          <- main_scene (dideklarasikan di manifest)
res://game/...
```

Alasannya: launcher memuat paket dengan `ProjectSettings.load_resource_pack()`
ke filesystem virtual yang sama dengan berkasnya sendiri. Kalau paket boleh
menaruh berkas di `res://scripts/` atau `res://ui/`, paket bisa menimpa UI/font
launcher. Launcher menolak boot jika `main_scene` tidak diawali `res://game/`.

## 2. Manifest (`version.json`)

```json
{
  "schema": 1,
  "game": "re-traveller",
  "version": "1.2.0",
  "min_launcher_version": 1,
  "released_at": "2026-10-24T10:00:00Z",
  "main_scene": "res://game/Main.tscn",
  "changelog": ["Baris pertama", "Baris kedua"],
  "packages": [
    { "name": "core",       "url": "packs/core.pck",       "size": 12345,
      "sha256": "<64 hex>", "load_order": 10 },
    { "name": "characters", "url": "packs/characters.pck", "size": 54321,
      "sha256": "<64 hex>", "load_order": 20 }
  ]
}
```

Aturan:
* `url` boleh absolut atau relatif terhadap lokasi `version.json`.
* `size` dan `sha256` **wajib** dan harus cocok dengan berkas di server.
  Launcher menghapus berkas dan mengunduh ulang bila tidak cocok.
* `load_order` unik; paket dimuat berurutan menaik (core dulu, audio terakhir).
* `min_launcher_version` menaik **hanya** bila game butuh API launcher baru
  atau engine lebih baru. Bila lebih besar dari versi launcher, game tidak
  dipasang dan pemain diminta memasang APK baru.
* `version` harus naik setiap rilis. Launcher membandingkan `version` +
  `sha256` per paket untuk menentukan apa yang perlu diunduh.

### Tanda tangan (opsional tapi disarankan)

`version.json.sig` = base64 dari `openssl dgst -sha256 -sign private.pem version.json`.
Bila `Config.REQUIRE_SIGNATURE = true`, launcher menolak manifest tanpa tanda
tangan yang valid. Kunci publik yang dipakai ada di `launcher/signing/public_key.pem`
dan ikut masuk ke APK.

## 3. Laporan boot sehat (`user://retraveller/boot_ok.json`)

Scene utama **wajib** menulis berkas ini pada frame pertama yang sehat:

```gdscript
func _ready() -> void:
    ...  # bangun dunia
    var version := "..."   # ambil dari user://retraveller/active.json bila ada
    var f := FileAccess.open("user://retraveller/boot_ok.json", FileAccess.WRITE)
    f.store_string(JSON.stringify({"version": version, "schema": 1, "at": Time.get_datetime_string_from_system(true)}))
    f.flush()
```

Launcher memakai berkas ini sebagai bukti bahwa versi yang dipasang memang bisa
hidup. Bila setelah boot tidak ada laporan dalam `Config.BOOT_SENTINEL_TIMEOUT_S`
(25 detik), atau proses mati sebelum laporan ditulis, launcher otomatis
kembali ke versi sebelumnya dan menandai versi rusak agar tidak dipasang ulang.

## 4. Batasan teknis

* **GDScript + resource Godot saja.** Dilarang GDExtension, plugin native,
  `.so`, atau apa pun yang harus ada di APK. Semua yang tidak bisa dimuat dari
  `.pck` akan memaksa pemain memasang ulang APK.
* Paket dibuat dengan *Export → PCK/ZIP* memakai template resmi Godot yang sama
  dengan engine launcher. Ekspor APK tidak dipakai untuk game.
* Jangan menyentuh `res://` di luar `res://game/`.
* Jangan menulis ke `res://` (hanya baca). Data yang berubah → `user://`.

## 5. Data simpanan pemain

* Lokasi: `user://` (bukan di dalam paket). Update paket tidak pernah
  menyentuh `user://`, jadi progres aman.
* Setiap berkas simpan **wajib** punya nomor versi skema, mis.

```json
{ "schema": 3, "slot": 1, "chapter": 4, "party": [...] }
```

* Saat memuat, bandingkan `schema` dengan versi terkini dan jalankan migrasi
  bertahap (v1→v2→v3). Jangan pernah membuang simpanan tanpa migrasi; simpan
  cadangan `save.v<lama>.bak` sebelum menulis format baru.
* Migrasi dijalankan di dalam game (Proyek B), bukan di launcher. Launcher
  hanya menjamin berkas tidak tersentuh saat update/rollback.

## 6. Alur yang dijamin launcher

1. Ambil manifest (HTTPS), fallback ke cache bila offline.
2. Bandingkan per paket → unduh hanya yang berubah, dengan resume HTTP Range.
3. Verifikasi SHA-256 tiap paket; `.tmp` baru dipindah setelah lolos.
4. Muat paket berurutan, boot `main_scene`.
5. Bila boot gagal → rollback ke versi sebelumnya + pesan.
6. Simpan 1 versi sebelumnya; paket disimpan content-addressed sehingga rollback
   tidak perlu mengunduh ulang.
