# BlockZone — Battle Royale (arsip pulihan)

Game **BlockZone** yang repo GitHub aslinya sudah terhapus. Isi folder ini
dipulihkan **apa adanya (byte-per-byte)** dari APK `BlockZone.apk` yang masih
tersimpan di Google Drive pemilik akun. Tidak ada satu baris pun yang diubah,
dirapikan, atau ditambahi — semua `md5` di bawah cocok dengan aslinya.

> Sumber: [`BlockZone.apk`](BlockZone.apk) (10.433.482 byte,
> md5 `bdb589afe82f3791f710750e46dff641`) — ikut disimpan di folder ini.
> Dibongkar: 4 November 2026. Isi game diambil dari `assets/public/` di dalam APK.

## Identitas build (versi terakhir yang tersisa)

| Item | Nilai |
| --- | --- |
| Nama aplikasi | **BlockZone** |
| Package / appId | `com.kyoko.squarezone` |
| versionName | **1.0.3** |
| versionCode | 3 |
| minSdk / targetSdk | 24 / 36 |
| Android Gradle Plugin | 8.13.0 |
| Pembungkus | Capacitor (WebView), plugin `@capacitor-community/admob` |
| Stempel build | `20260921.b6ca728`, `build: 1789981882` |
| Waktu build | 21 September 2026, 09:11:22 UTC |
| Orientasi | kunci landscape (`enterFullscreenLandscape` di `game.html`) |

Angka `b6ca728` di `version.json` adalah short-SHA commit repo game saat build
tersebut dibuat — commit itu ikut hilang bersama repo-nya, jadi APK ini
satu-satunya salinan yang masih ada.

## Isi

```
blockzone/
├── capacitor.config.json     # konfigurasi asli dari APK (assets/capacitor.config.json)
├── capacitor.plugins.json    # daftar plugin asli (AdMob)
├── APK_INFO.json             # metadata APK + md5 semua berkas
├── serve.sh                  # jalankan game di browser lokal
└── www/                      # == assets/public di dalam APK (identik)
    ├── game.html             # SELURUH game: 3.286 baris HTML+CSS+JS, tanpa dependensi eksternal
    ├── index.html            # layar pembuka: cek update → jalankan game
    ├── updater.js            # pengunduh update (memakai Cache API)
    ├── update-config.js      # window.BZ_UPDATE = https://KyokoApp.github.io/rpg/
    ├── version.json          # versi paket game
    ├── ads-config.js         # window.SQ_ADS — AdMob (masih testing: true)
    ├── icon.jpg
    ├── cordova.js            # kosong (0 byte, bawaan Capacitor)
    └── cordova_plugins.js    # kosong (0 byte, bawaan Capacitor)
```

## Checksum (verifikasi keaslian)

```
97a926966df2181f04a964f0dbc334be  ads-config.js
d41d8cd98f00b204e9800998ecf8427e  cordova.js
d41d8cd98f00b204e9800998ecf8427e  cordova_plugins.js
a94e4545d2d199ed8f563e1811105240  game.html
a903c742229fd72f5901e88428e671dc  icon.jpg
450a4e6669fd3eba2c844a9286324066  index.html
9a5dee8c81447cf7a82d6a668aa798e4  update-config.js
a538b54c916f95497a647cdd49c272ce  updater.js
fbf2238e32154497faa1741e258ed9af  version.json
```

## Cara main sekarang

```bash
./serve.sh          # atau: python3 -m http.server -d www 8080
```

Lalu buka `http://localhost:8080/` (layar pembuka) atau langsung
`http://localhost:8080/game.html` (lompat ke game tanpa cek update).
`game.html` mandiri total — tidak ada CDN, font, atau API luar.

## Catatan yang perlu diketahui

- **Updater mati.** `update-config.js` menunjuk ke
  `https://KyokoApp.github.io/rpg/` yang sekarang 404 (repo-nya terhapus).
  `index.html` sudah menangani kegagalan ini: kalau unduh gagal, game tetap
  jalan dari `game.html` lokal. Jadi jangan panik saat melihat pesan gagal —
  tombol/auto-fallback tetap memainkan versi di dalam paket.
- **Iklan.** `ads-config.js` memakai AdMob unit asli tapi `testing: true`.
  Di luar pembungkus Capacitor (mis. di browser biasa) yang dipakai adalah
  `fakeAd()` — iklan palsu, jadi game tetap bisa dicoba.
- **Native project tidak tersimpan di APK.** Yang tersisa hanya `classes.dex`
  terkompilasi, jadi untuk membangun ulang APK perlu `npx cap add android`
  dengan `capacitor.config.json` yang ada di folder ini (appId & appName sama),
  lalu pasang plugin AdMob.
- APK aslinya **ikut disimpan** di [`blockzone/BlockZone.apk`](BlockZone.apk)
  (10.433.482 byte, md5 `bdb589afe82f3791f710750e46dff641`). `.gitignore` repo ini
  mengabaikan `*.apk` untuk hasil build, jadi berkas ini diberi pengecualian
  eksplisit — ini satu-satunya salinan utuh yang tersisa dan tidak boleh hilang.

## Isi game (ringkas)

Battle royale top-down: arena kotak, musuh bot dengan level, HP bar, minimap,
leaderboard, skill (shield, attack speed, laser), trail peluru & trail tubuh
yang bisa dibeli di **SHOP**, pengaturan bahasa (ID/EN) dan suara, plus layar
kalah/menang dengan skor terbaik di `localStorage`.
