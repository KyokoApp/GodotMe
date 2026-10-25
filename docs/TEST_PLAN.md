# TEST PLAN & HASIL UJI — Launcher (Fase 1)

Semua uji berjalan otomatis di GitHub Actions (11 job + parse check), dan bisa
dijalankan lokal dengan satu perintah. Log tiap job otomatis ditempel ke Pull
Request supaya bisa diperiksa dari HP.

```bash
GODOT=/path/to/godot-4.7.2 tools/run_launcher_tests.sh           # semua skenario
GODOT=/path/to/godot-4.7.2 tools/run_launcher_tests.sh resume    # satu skenario
CAPTURES=/tmp/shots GODOT=... tools/run_launcher_tests.sh capture # tangkapan layar
```

Skrip ini mengimpor dua proyek, membangun fixture (`launcher/tests/FixtureBuilder.gd`),
menjalankan `tools/testserver.py` (mendukung HTTP Range, throttle, jumlah
request), lalu menjalankan tiap skenario di sandbox `user://` sendiri.

## Skenario wajib dari brief

| # | Yang diuji (brief §1.5) | Cara diuji | Hasil |
| --- | --- | --- | --- |
| 1 | Instalasi pertama | `first_install`: manifest v1.0.0, enam paket baru | ✅ 7 check lulus |
| 2 | Update normal | `partial_update`: v1.0.0 → v1.1.0 | ✅ 8 check lulus |
| 3 | Update sebagian (delta) | `partial_update`: hanya `characters.pck` berubah | ✅ jumlah berkas 6 → 7 (hanya satu paket baru); server mencatat 1 permintaan untuk paket itu |
| 4 | Unduhan terputus lalu lanjut | `resume`: unduhan 1,1 MB diperlambat, dijeda di ~25%, dilanjutkan | ✅ 7 check lulus; log "Melanjutkan …" + berkas `.tmp` bertambah, bukan mulai dari nol |
| 5 | Hash salah | `bad_hash`: manifest dengan `sha256` yang dirusak | ✅ ERROR `kind=hash`, `.tmp` dihapus, tidak ada versi aktif |
| 6 | Offline dengan versi lama | `offline`: v1.0.0 terpasang, lalu manifest server mati | ✅ state `OFFLINE_READY`, tombol MAIN aktif |
| 7 | Rollback saat game rusak | `crash`: v1.1.0 sehat → v1.2.0 berisi paket yang sengaja `OS.crash()` saat boot → proses mati → launcher dibuka lagi | ✅ proses memang mati (exit ≠ 0), launcher mendeteksi sentinel, rollback ke v1.1.0, v1.2.0 ditandai rusak (8 check) |
| 8 | Save tetap utuh setelah update | `partial_update`: tulis `user://save/slot1.json` (`gold: 4242`) sebelum update | ✅ data sama setelah update |
| 9 | Manifest butuh launcher baru | `launcher_too_old`: `min_launcher_version = 99` | ✅ state `LAUNCHER_UPDATE_REQUIRED`, versi lama tetap bisa dimainkan |
| 10 | Tanda tangan manifest | `signed_ok` (RSA-SHA256 valid) dan `signed_bad` (tanda tangan dirusak) | ✅ valid diterima, rusak ditolak |
| 11 | Versi bermasalah tidak dipasang ulang otomatis | `blocked`: v1.1.0 ditandai rusak, manifest menawarkan v1.1.0 | ✅ ditahan; tombol Coba Lagi memaksa pasang ulang |
| 12 | Sentuhan benar-benar sampai ke tombol | `ui_input`: menekan tombol lewat `Viewport.push_input` (bukan memanggil fungsi) | ✅ 11 check; MAIN & tombol sekunder bereaksi, modal menahan latar, dan tombol aktif lagi setelah modal ditutup |

> **Kenapa ada skenario 12:** pada APK pertama, menekan **MAIN** tidak
> menghasilkan apa pun di HP. Penyebabnya `CenterContainer` selebar layar di
> dalam lapisan modal yang selalu `visible` — sentuhan ditelan sebelum sampai ke
> tombol. Skrip tangkapan layar tidak menemukannya karena memanggil handler
> secara langsung, jadi sekarang ada uji yang menekan tombol lewat jalur input
> sungguhan.

Tambahan: `unit` (17 check) menguji format ukuran/kecepatan bahasa Indonesia,
resolusi URL relatif/absolut, SHA-256, dan validasi manifest (kolom hilang,
nama paket ganda, `sha256` salah, path tidak aman).

## Bukti tambahan yang dikumpulkan otomatis

* **Tangkapan layar** (`docs/screenshots/`): menyiapkan, mengunduh, siap,
  kendala, mode luring, modal pemulihan otomatis, **dan layar dunia setelah MAIN
  ditekan** (`08_diorama.png`, diambil dari proyek game langsung) — semua dengan GL
  software (llvmpipe) pada 1280×720.
* **Audit permintaan server**: satu paket yang berubah hanya diminta sekali
  selama delta update; paket yang tidak berubah tidak diunduh ulang.
* **APK**: diekspor setiap push (debug + release), diverifikasi dengan
  `apksigner verify`, lalu **isi APK-nya diperiksa**: CI membaca `build_id` dari
  `launcher/project.godot` dan memastikan nilai itu benar-benar ada di dalam
  setiap APK (`assets/project.binary`). Artefak basi tidak mungkin dipublikasikan
  tanpa ketahuan, dan nilai yang sama tampil di jurnal launcher supaya pengguna
  bisa memastikan build mana yang terpasang.

## Verifikasi end-to-end di rilis sungguhan

Job `release-demo` (`.github/workflows/release-demo.yml`) tidak berhenti pada
"APK berhasil diekspor". Setelah rilis terbit, ia mengambil
`https://github.com/<repo>/releases/latest/download/version.json` persis seperti
launcher, lalu meminta 64 byte pertama setiap paket dengan header
`Range: bytes=0-63` untuk memastikan aset benar-benar bisa diunduh dan mendukung
resume. Hasil terakhir: 6/6 paket menjawab `200/206`, rilis `demo-v0.1.0`
berisi `version.json` + 6 `.pck` + `re-traveller-launcher.apk` (29.428.024 byte).

## Uji manual di HP (yang tidak bisa diotomasi di sini)

| Uji | Langkah | Yang harus terlihat |
| --- | --- | --- |
| Instal & buka | pasang APK, buka | splash crest → layar update bertema, bukan layar default Godot |
| Update normal | rilis v baru di hosting, buka launcher | progress + kecepatan + sisa waktu; tombol MAIN aktif |
| Putus jaringan di tengah unduhan | mode pesawat 10 detik lalu nyalakan | unduhan lanjut, bukan dari 0% |
| Offline | mode pesawat, buka launcher | "Mode luring", MAIN tetap aktif, versi lama jalan |
| Rotasi/notch | putar layar | tetap landscape, UI tidak tertutup notch |
| Ukuran & kecepatan | — | APK < 35 MB, layar pertama < 2 detik di perangkat kelas menengah |

## Daftar berkas uji

```
launcher/tests/TestRunner.gd      # 12 skenario + screenshot capture
launcher/tests/FixtureBuilder.gd  # membuat 6 paket + 8 manifest uji
tools/run_launcher_tests.sh       # driver (lokal & CI)
tools/testserver.py               # server uji: Range, throttle, audit request
.github/workflows/ci.yml          # matrix 11 job + parse check + screenshot + APK
```

---

## Tahap sprite (Fase 2, tahap 2)

| # | Uji | Cara | Lulus bila |
| --- | --- | --- | --- |
| S1 | Lebar strip = jumlah frame × lebar frame | `tools/import_character_sprites.py --check` di job `lint` | exit 0; kalau ada yang tidak cocok, build merah dan berkas yang salah disebut namanya |
| S2 | Animasi termuat & tidak kosong | `godot --headless --path game res://game/tests/ValidateCharacters.tscn` | exit 0; tiap animasi punya frame > 0 di `SpriteFrames`, pivot di dalam frame, rasio langkah 1,000 |
| S3 | Ketiga karakter berdampingan, semua animasi berlabel, penggaris, pivot | `CharacterTest.tscn` → `docs/screenshots/09_karakter.png` | tiga karakter terlihat, label menyebut nama animasi + jumlah frame + fps, penggaris 0–2 m, silang kuning tepat di kaki |
| S4 | Karakter hidup di diorama, siang | `VisualTest.tscn --time=day` → `10_visual_siang.png` | ksatria & penjaga terlihat di lembah, bayangan oval di bawah kaki, tidak ada tepi sprite yang kabur |
| S5 | Karakter hidup di diorama, malam | `VisualTest.tscn --time=night` → `11_visual_malam.png` | sprite tetap terbaca di cahaya rendah, warna tidak "nyala sendiri" (bukan unshaded) |
| S5b | Dialog perkamen terbuka | `VisualTest.tscn --dialog=page` → `12_dialog.png` | panel perkamen, nama pembicara, teks mengetik, tombol Lanjut; kontrol sentuh disembunyikan selama bicara |
| S5c | Cabang pilihan | `VisualTest.tscn --dialog=choices` → `13_pilihan.png` | dua pilihan terbaca penuh (tidak terpotong tepi bawah layar) |
| S6 | Tanpa foot sliding | cetak `rasio` di S2 + tonton `VisualTest` | rasio 1,000; kaki tidak meluncur saat stik setengah |
| S7 | Pivot benar saat flip | `CharacterTest` (aktornya menghadap kanan) + main di HP: jalan ke kiri | kaki tidak bergeser saat sprite dibalik |
| S8 | Tanpa blur / tanpa mipmap | Nearest + PNG tanpa `.import`; dicek pada S4/S5 | tepi piksel tajam, tidak ada halo |
| S9 | Update hanya mengunduh paket yang berubah | `release-demo` → manifest 0.2.0 | `core.pck` + `characters.pck` berubah hash; `world/ui/enemies/audio` sama |

Yang **tidak** bisa diotomasi di sandbox dan harus dicoba di HP: rasa stik dan
ukuran tombol dengan jempol, ketajaman pada layar sungguhan, getar kamera,
dan apakah dialog terbaca saat matahari rendah.

### Uji aturan permainan (`PlayTest`, headless, masuk CI)

```bash
godot --headless --path game res://game/tests/PlayTest.tscn   # exit 1 bila ada yang gagal
```

| # | Yang diuji | Kenapa |
| --- | --- | --- |
| P1 | satu pukulan masuk state `hurt`, lalu pulih ke `idle` | dasar flinch |
| P2 | flinch kedua memutar ulang dari frame awal | dulu strip tidak di-restart → terkunci |
| P3 | tetap bisa berjalan setelah dipukul | hit-stop dulu membekukan animasi selamanya |
| P4 | `death` menahan frame terakhir | animasi mati tidak boleh loop |
| P5 | orc memukul berkali-kali: ksatria tetap bisa dikendalikan | laporan perangkat "stuck saat dipukul" |
| P6 | tepi bawah setiap prop di diorama = 0 m (toleransi 2 cm) | laporan perangkat "pohon/batu melayang" |

Tambahan `PlayTest` (25 Okt 2026):

| # | Yang diuji | Kenapa |
| --- | --- | --- |
| P7 | sprite karakter memakai billboard sumbu Y | billboard penuh memiringkan kuad → karakter melayang 0,39 m |
| P8 | setiap prop memakai billboard sumbu Y | pohon/batu ikut melayang karena sebab yang sama |
| P9 | kamera mengikuti aktor (pindah > 2,5 m saat aktor jalan 4 m) | keluhan "kamera tidak mengikuti" |
| P10 | kamera berhenti dekat aktor (< 1,2 m) | follow yang tertinggal terlalu jauh sama saja tidak mengikuti |
| P11 | stik tersembunyi sebelum disentuh | stik dinamis, bukan dipaku |
| P12 | stik muncul di titik sentuhan pada zona kiri | keluhan "analog muncul ketika disentuh" |
| P13 | arah dorongan benar (kanan → kanan) | pemetaan layar → dunia |
| P14 | stik hilang & dorongan nol setelah jari diangkat | tidak boleh berjalan sendiri |
| P15 | layar kanan tidak memunculkan stik | zona tombol tidak boleh jadi stik |

Tambahan `PlayTest` (25 Okt 2026, fase cerita):

| # | Yang diuji | Kenapa |
| --- | --- | --- |
| P16 | progres bisa ditulis sebelum boot | dasar semua uji berikutnya |
| P17 | orc yang sudah dikalahkan tidak muncul lagi | lembah harus tetap bersih setelah restart |
| P18 | ksatria kembali ke posisi tersimpan (±0,6 m) | progres posisi, bukan hanya cerita |
| P19 | counter & flag terbaca dari save | data cerita harus konsisten dengan dunia |
| P20 | penjaga memakai `setelah_bersih` setelah 3 orc | cerita berganti, bukan diulang |

`SaveTest` — `godot --headless --path game res://game/tests/SaveTest.tscn`
(25 pemeriksaan):

| # | Yang diuji | Kenapa |
| --- | --- | --- |
| S1 | slot kosong = permainan baru | pemain baru tidak melihat error |
| S2 | tulis → baca kembali: flag, counter, posisi, waktu | isi save lengkap |
| S3 | `.tmp` dibersihkan setelah sukses; `tmp` nyasar tidak dipakai | sisa tulisan gagal tak boleh menang |
| S4 | `.bak` dibuat saat menimpa, dan dipakai bila slot terpotong | kehilangan save adalah bug terburuk |
| S5 | skema 0 → 1 (migrasi, flag lama ikut, field baru default, bisa disimpan lagi) | save 0.2.x harus tetap terbaca |
| S6 | skema 99 → `read_only`, penyimpanan ditolak, berkas tidak berubah | build lama tak boleh merusak save baru |
| S7 | lokasi `user://save/`, di luar pohon data peluncur | Periksa Lagi tidak menghapus progres |
| S8 | hash konsisten setelah angka dinormalkan | `2` vs `2.0` dulu membuat save "rusak" sendiri |

`DialogueTest` — `godot --headless --path game res://game/tests/DialogueTest.tscn`
(18 pemeriksaan):

| # | Yang diuji | Kenapa |
| --- | --- | --- |
| D1 | `bram.json` lolos validator (skema, entry, node, pilihan) | salah ketik JSON menggagalkan build |
| D2 | minimal tiga percakapan berbeda & lebih dari satu titik masuk | cerita bercabang nyata |
| D3 | pemain baru → `pertemuan`, ≥ 4 halaman, ≥ 1 cabang dua pilihan | pertemuan pertama |
| D4 | node pertama menandai `bram_kenal` | tidak diulang selamanya |
| D5 | 3 orc + `bram_kenal` → `setelah_bersih`; 2 orc → belum | progres mengubah cerita |
| D6 | sudah kenal tapi belum bersih → `ulangan` yang tetap berisi | kunjungan ulang tidak kosong |
| D7 | pilihan menyetel flag, flag tersimpan, dan nama pembicara berganti per halaman | cabang + penyajian dua arah |

Tambahan `PlayTest` (25 Okt 2026, fase taruhan):

| # | Yang diuji | Kenapa |
| --- | --- | --- |
| P21 | ksatria mulai dengan tiga hati dan tujuan "Bersihkan jalur" | dasar HUD |
| P22 | satu pukulan memakan satu hati | harga pukulan |
| P23 | pukulan beruntun dalam satu detik tetap satu hati | dua orc dulu menguras semua hati |
| P24 | perisai menahan pukulan tanpa kehilangan hati, state tetap `block` | tombol Tahan harus berarti |
| P25 | hati 0 → `down` (animasi mati dimainkan, kontrol hilang) | taruhan nyata |
| P26 | bangun setelah 2,6 s: tiga hati, di awal jalan, tidak `is_dead` | tidak boleh macet mati |
| P27 | terjatuh tidak menghapus progres orc | hukuman bukan penghapusan |
| P28 | tujuan berganti ke "Kembali ke Penjaga Bram" lalu "Jalur aman" | HUD dibaca dari save |
| P29 | "Simpan sekarang" menulis berkas dan count `deaths` ikut tersimpan | jalur simpan manual = autosave |
| P30 | `16_terjatuh.png` memotret ksatria di tanah dengan pesan terjatuh | bukti visual, bukan klaim |
| P31 | animasi `death` yang dimainkan saat terjatuh (bukan `hurt`) | pukulan terakhir dulu menimpa animasi mati sehingga ksatria "mati sambil berdiri" |

Yang **belum** teruji otomatis: tombol di lembar jeda (butuh layar sungguhan
untuk menilai tata letaknya) — diperiksa manual di HP: Jeda → Simpan sekarang →
tutup aplikasi → buka lagi, tujuan dan posisi harus sama.

## FASE 6 — siklus hari & atmosfer (0.4.0)

`WorldTest` — `godot --headless --path game res://game/tests/WorldTest.tscn`
(**26 pemeriksaan**, 0 gagal):

| # | Yang diuji | Kenapa |
| --- | --- | --- |
| W1 | diorama punya `WorldClock` dan `Atmosphere` | fase ini tidak boleh diam-diam tidak terpasang |
| W2 | mulai di fase `sore` | tampilan default game |
| W3 | empat fase (`pagi/siang/sore/malam`) dikenal | daftar fase satu sumber |
| W4 | tiap fase bisa dipilih dan namanya benar | jam tidak boleh "nyangkut" |
| W5 | cahaya malam > 0,3 lebih redup dari siang | malam harus malam |
| W6 | cahaya malam kebiruan (b > r), bukan neon | aturan tema |
| W7 | matahari siang lebih tinggi dari pagi | arah bayangan ikut berubah |
| W8 | kabut pagi lebih tebal dari siang | lembah berkabut saat subuh |
| W9 | ambient tiap fase dalam 0,15–0,75 | tidak ada fase yang hitam pekat/putih jebol |
| W10 | lampu pondok < 0,05 saat siang, > 0,8 saat malam | lampu menyala sendiri |
| W11 | empat sistem atmosfer ada | debu, kelopak, kunang-kunang, kabut |
| W12 | keempat tekstur partikel termuat dari paket | PNG hilang = partikel tak terlihat, bukan error |
| W13 | kunang-kunang > 0,25 saat malam, < 0,1 saat siang | tidak ada kunang-kunang siang hari |
| W14 | debu > 0,4 saat siang, < 0,1 saat malam | debu hanya di cahaya |
| W15 | kelopak > 0,5 saat sore | daun jatuh saat sore |
| W16 | jam berjalan siang → sore, dan sehari penuh kembali | siklus tidak macet/drift |
| W17 | `set_time_of_day(true/false)` masih kompatibel | VisualTest & paket dunia lama |

Tangkapan layar wajib: `17_pagi`, `10_visual_siang`, `18_sore`, `11_visual_malam`
(satu diorama, empat fase), diperiksa manual untuk: warna hijau tidak hilang saat
sore, kabut tidak menjadi kotak-kotak, kunang-kunang bulat (bukan kotak), lampu
pondok menerangi ambang pintu.

Catatan jujur: uji ini headless (CPU) dan tidak mengukur FPS di GPU HP. Beban
baru: 4 sistem `CPUParticles3D` (46 + 26 + 34 + 10 partikel). Kalau di HP terasa
berat, angka `amount` di `Atmosphere.gd` adalah tombol pertama, bukan mematikan
seluruh atmosfer.

## FASE 7 — UI, pengaturan, menu (0.5.0)

`UiTest` — `godot --headless --path game res://game/tests/UiTest.tscn`
(**30 pemeriksaan**, 0 gagal):

| # | Yang diuji | Kenapa |
| --- | --- | --- |
| U1–U3 | 7 ikon ada di paket ui, semuanya 24×24, tidak ada yang kosong | ikon hilang = tombol kosong tanpa error |
| U4–U7 | parchment + crest termuat dari paket, font termuat, nine-patch bermargin, tombol kit memakai ukuran yang diminta | kit adalah satu sumber tampilan |
| U8 | bawaan: tilt-shift nyala, getar nyala, kualitas sedang | pemain baru dapat tampilan penuh |
| U9–U10 | kualitas "tinggi" diterima, "ultra" ditolak | nilai asing tidak boleh masuk |
| U11–U12 | simpan lalu baca ulang mempertahankan nilai | pengaturan harus bertahan setelah app ditutup |
| U13 | settings rusak → bawaan + catatan "rusak" | berkas rusak tidak boleh menggagalkan boot |
| U14 | settings skema 99 → tidak ditimpa | build lama tidak merusak pilihan build baru |
| U15 | preset "rendah" mematikan bayangan, blur < 2,0, atmosfer < 0,5 | preset benar-benar menghemat |
| U16 | tilt-shift mati → blur 0 | tombol berarti |
| U17 | `Main` boot: lembar jeda ada & tersembunyi | menu tidak muncul tanpa diminta |
| U18 | safe area tidak negatif | notch tidak boleh menggeser HUD ke luar layar |
| U19 | HUD punya tiga ikon hati | nyawa terbaca tanpa teks |
| U20 | Jeda membuka lembar **dan menghentikan dunia** | tombol benar-benar menjeda |
| U21 | lembar jeda **benar-benar tampak** (`modulate.a > 0,95`) | tween saat pause dulu tidak berjalan → menu tak terlihat |
| U22–U23 | halaman jeda 4 tombol, halaman pengaturan 4 tombol | tidak ada tombol hantu |
| U24 | pindah ke halaman pengaturan | navigasi dua halaman |
| U25–U26 | tombol pengaturan mengubah nilai dan langsung menulis disk | pilihan tidak hilang saat app dimatikan |
| U27 | kualitas yang dipilih diterapkan ke bayangan matahari | setelan benar-benar sampai ke renderer |
| U28 | tilt-shift menerima nilai blur | shader tersambung |
| U29 | status menu memuat "Orc" dan "Nyawa" | baris status tidak kosong |
| U30 | Lanjutkan melepas jeda | dunia bergerak lagi |

Tangkapan layar wajib: `20_menu.png` dan `21_pengaturan.png` — diperiksa manual
untuk: teks terbaca di 720p, tombol tidak bertumpuk, lembar benar-benar tampil,
status menunjukkan angka yang masuk akal.

Yang belum teruji otomatis: posisi tombol sentuh di layar HP nyata (ukuran ibu
jari), dan notch sungguhan — CI headless selalu memberi safe area 0.

### Tambahan FASE 8 (0.6.0)

| # | Yang diuji | Kenapa |
| --- | --- | --- |
| U31 | atlas memuat ketujuh ikon | ikon lupa dimasukkan = tombol tak terlihat di HP |
| U32 | tidak ada nama ikon di `UiKit.ICONS` yang hilang dari atlas | daftar dan atlas tidak boleh melenceng |
| U33 | `icon()` mengembalikan `AtlasTexture` 24×24 | membuktikan jalur atlas dipakai, bukan PNG tunggal |
| U34 | preset rendah → batas FPS ≤ 30, tinggi ≥ 60 | preset harus menghemat daya |
| U35 | preset rendah menurunkan skala resolusi 3D | detail tanah yang dikorbankan, bukan karakter |
| U36 | `Engine.max_fps` benar-benar disetel | setelan sampai ke engine |
| U37 | `Viewport.scaling_3d_scale` benar-benar disetel | idem |
| U38 | penghitung FPS muncul saat diaktifkan | alat ukur di perangkat |
| U39 | penghitung FPS hilang saat dimatikan | tidak ada label hantu di HUD |

`pack_audit` di CI (bukan bagian `UiTest`):

```
python3 tools/pack_audit.py     # exit 1 bila ada aset hilang / tidak dipakai
```

Jujur soal batas: **FPS tidak diukur di CI**. Renderer CI adalah llvmpipe tanpa
GPU; angka FPS di sana tidak berarti apa-apa untuk sebuah ponsel. Yang tersedia
untuk pemilik adalah log `[PERF] ...` tiap 5 detik di `adb logcat` dan penghitung
di layar.

### Tambahan langkah 1 (0.7.0) — lapangan, minimap, kamera

Gate headless baru: `godot --headless --path game res://game/tests/FieldTest.tscn`

| # | Yang diuji | Kenapa (dan apa yang gagal tanpa uji ini) |
| --- | --- | --- |
| F1 | peta 26×20 ubin, `bounds()` = 26×20 m di sekitar titik nol | kamera dan minimap membaca kotak yang sama |
| F2 | `world_to_tile` dan `tile_centre` saling konsisten (< 0,75 m) | pemain bisa "berada di ubin" yang salah dan fog terbuka di tempat lain |
| F3 | luar peta tidak bisa dijalankan, rumput bisa | peta data harus setuju dengan dunia |
| F4 | ubin bisa dicat jadi tanah | jalur dan bangunan digambar dari `LAYOUT` |
| F5 | peta mulai dalam gelap; `reveal` membuka fog dan menaikkan `fog_revision` | `fog_revision` adalah satu-satunya pemicu gambar ulang minimap |
| F6 | `reveal` kedua pada titik yang sama tidak mengubah apa pun | tanpa ini minimap akan digambar ulang tiap frame |
| F7 | `reveal_all` = 100 % | dipakai tangkapan layar dan peta penuh |
| F8 | fog disimpan 520 bit untuk 26×20 | satu karakter per ubin, muat di JSON save |
| F9 | fog yang sama dipulihkan utuh (jumlah ubin sama) | pemain kembali tidak kehilangan peta |
| F10 | fog dari peta lain ditolak tanpa merusak peta sekarang | save dari peta besar tidak boleh mengotori peta kecil |
| F11 | fog skema lebih baru ditolak dengan alasan | jangan menebak data versi masa depan |
| F12 | save dengan fog bisa ditulis dan dibaca lagi | fog benar-benar ikut tersimpan |
| F13–F15 | jendela minimap tetap 56×56 px pada peta 26×20, 120×90 dan 3×3 | biaya minimap tidak boleh tumbuh bersama peta |
| F16–F18 | peta penuh bisa digambar pada ketiga ukuran itu | tab Peta tidak boleh kosong di peta besar |
| F19–F20 | kamera 26×20 m: batas tidak terbalik, dan tetap di dalam peta setelah pemain "berjalan" ke luar tiga kali | inilah yang diminta: tepi dunia tidak boleh terlihat kosong |
| F21–F22 | kamera 208×160 m: sama | antarmuka harus bekerja untuk ukuran peta berapa pun |
| F23 | zoom menempel ke tangga (17,43 → nilai tangga) | sprite tidak boleh digambar pada skala pecahan |
| F24–F25 | zoom maksimum mengikuti ukuran peta; zoom minimum 11 | zoom-out di lembah kecil tidak boleh memperlihatkan kekosongan |
| F26–F29 | minimap 26×20 dan 160×120 menggambar jendela yang benar, membuka fog saat dipakai, dan ketuk dua kali mengubah zoom | | 
| F30–F33 | tombol aksi tersembunyi saat jauh, muncul sebagai "Bicara" di dekat penjaga, memudar lagi setelah menjauh, dan berukuran ≥ 132 px desain | permintaan brief: muncul/hilang, bukan abu-abu menetap |
| F34–F35 | menu 1280×720, 960×720 (4:3) dan 1440×648 (20:9) muat di layar; tab tidak melebar melewati perkamen | versi pertama menu terpotong di 4:3 — tangkapan layar menemukannya, uji ini menjaganya |
| F36–F40 | dialog terbuka, tombol aksi disembunyikan, dialog tidak menimpa minimap / tombol menu, dialog di bawah 45 % tinggi layar, dan hilang total setelah selesai | "tidak ada elemen yang menimpa dialog" |

`UiTest` naik dari 39 → 50 pemeriksaan (ukuran UI satu knop, stik tetap,
sensitivitas dijepit, tujuh tab, Jurnal memuat tujuan, FPS butuh mode debug,
peluncur minta konfirmasi, peta penuh buka/tutup).
`PlayTest` 46 → 45: dua cek perisai diganti satu cek bahwa pintu perisai
lapangan memang sudah tidak ada lagi.

Tangkapan layar baru di CI: `22_lapangan`, `22b_lapangan_kosong` (tidak ada
siapa pun dalam jangkauan: HUD paling kosong), `22c_stik` (stik mengambang
dalam keadaan didorong — saat diam ia memang tidak terlihat), `23_banner`, `24_dialog`,
`25_jurnal`, `26_peta`, `27_fog`, `28_rasio_20x9`, `29_rasio_4x3`, ditambah
`20_menu` / `21_pengaturan` yang digambar ulang.

Tetap **tidak** terukur otomatis: rasa stik di ibu jari, kecepatan kamera yang
enak dilihat, dan pinch zoom dengan dua jari sungguhan. CI hanya bisa
membuktikan logikanya, bukan rasanya.

### Tambahan langkah 2 (0.8.0) — region Yaros

Dijalankan otomatis di CI lewat `res://game/tests/RegionTest.tscn`
(step **Region rules**), lalu tangkapan layar di job `screenshots`.

| # | Yang diuji | Cara | Lulus bila |
| --- | --- | --- | --- |
| R1 | Peta termuat | `RegionData.load_file` | 192×192, chunk 32, level 1,8 m, 36 chunk |
| R2 | Isi peta | statistik | ≥25 000 ubin berjalan, jalur utama ≥450 ubin |
| R3 | Aturan tinggi | sapu seluruh peta, 4 arah | 0 pelanggaran: dh≤1 selalu boleh, dh=2 hanya lewat tangga, dh≥3 tidak pernah boleh |
| R4 | Tidak ada area terisolasi | flood fill dari `player_start` | ubin terjangkau == total ubin berjalan |
| R5 | Semua tujuan terjangkau | flood fill + marker | 33 marker; dua blokir sengaja (gerbang, jembatan rusak) memang tidak terjangkau |
| R6 | Jalur A* sah | `find_path` desa → gerbang | >40 ubin, tiap langkah lolos `step_ok` |
| R7 | Zona | `zone_at` | titik awal = Lembah Senja, gerbang = Pos Gunung, 9+ zona lengkap (nama, biome, cuaca, musik) |
| R8 | Sambungan chunk | bangun chunk (2,2) vs (3,2) dan (2,2) vs (2,3) | verteks di bidang batas sama persis, ≥4 verteks/ubin |
| R9 | Atlas prop | `prop_atlas.json` | ≥14 sel, semua UV di dalam 0–1, ukuran > 0 |
| R10 | Teleport 10 titik | `RegionView.force_build` | selalu 3×3 chunk, hitch terburuk <1,5 s (headless) |
| R11 | Waktu tempuh | `routes[0]` ÷ 3,5 m/s | 110–175 s (2–3 menit) |

Tangkapan layar baru (job `screenshots`): `30_zona_lembah` … `38_zona_pos`
(sembilan zona, teleport lewat **nama marker** supaya tidak menunjuk rumput saat
peta dibangun ulang), `39_tangga`, `40_tebing_luar`, `41_tebing_dalam`,
`42_air_dekat`, `43_danau_jauh` (zoom 30), `44_desa_siang`, `45_hutan_senja`,
`46_peta_penuh`.
