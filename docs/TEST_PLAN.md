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

## Langkah 3A — kamera (0.9.0)

| # | Yang diuji | Cara | Lulus bila |
| --- | --- | --- | --- |
| C1 | Lensa dari berkas | `CameraTest`, bandingkan `lens_state()` dengan `camera.json` | pitch, FOV, jarak sama persis |
| C2 | Perspektif & arti pitch | vektor maju `Camera3D` | `PROJECTION_PERSPECTIVE`; sudut di bawah horizon = `pitch_deg` ± 0,5° |
| C3 | Tidak ada zoom | roda mouse, pinch trackpad, pan, dua jari sentuh dikirim ke rig | lensa tidak bergeser > 5 mm; rig tidak punya `_input`; tidak ada setelan "zoom" |
| C4 | Lensa tetap sepanjang rute | rekam tiap frame: jalan, berhenti, belok, dekat penjaga, dialog, menu, tepi peta | pitch/FOV/jarak tidak bergeser > 5 mm di seluruh rute |
| C5 | Spring tanpa overshoot | simulasi 2 s jalan + 1,5 s diam | kamera tidak pernah melewati target; sisa < 2 cm |
| C6 | Frame-rate independent | simulasi yang sama pada 1/60 s dan 1/30 s | selisih posisi akhir < 12 cm |
| C7 | Kehalusan | rekam 2,5 s jalan lurus | langkah per frame < 0,6 m; ayunan offset < 0,9 m; kamera tetap < 8 m dari pemain |
| C8 | Occlusion | `RegionView.occluders_for()` pada layout prop asli | prop di garis kamera–pemain memudar (0,25–1,0); koridor tidak menyapu hutan |

Tangkapan layar baru (job `screenshots`): `47_kamera_desa` (lensa default),
`48_kamera_halangan` (ksatria di belakang pohon), dan
`docs/screenshots/camera/sudut_kamera.png` — grid 6 pitch × 3 FOV berlabel, dengan
rekomendasi P30 F32 ditandai dan nilai lama P38 F30 ditandai terpisah.

## Langkah 3B — bangunan 3D (0.10.0)

Uji baru: `game/tests/BuildingTest.tscn` (aturan, headless) dan
`tools/kit_audit.py` (pemeriksaan manifest tanpa Godot). Job CI baru:
**Building rules**; tangkapan layar masuk job `screenshots`.

| # | Yang diuji | Cara | Lulus bila |
| --- | --- | --- | --- |
| B1 | Atlas dan manifest | `kit_audit.py` + `BuildingTest._test_manifest()` | 16 sel bernama unik, UV = rect/atlas, semua sel yang dipakai kode ada, PNG di disk seukuran yang dicatat |
| B2 | Sel benar-benar terisi | baca PNG sebagai byte mentah (bukan impor sRGB), potong tiap sel | tidak ada sel kosong atau satu warna |
| B3 | Mesh utuh | setiap jenis × varian: verteks/normal/UV2/warna sejajar, indeks di dalam batas, tidak ada NaN | semua varian terbangun, satu permukaan, satu bahan |
| B4 | Sel yang dipanggil kode ada di atlas | setiap `UV2` verteks harus sama dengan salah satu titik asal sel | 0 verteks menunjuk sel tak dikenal (menangkap salah ketik nama sel) |
| B5 | Varian benar-benar berbeda | bandingkan jumlah segitiga + tinggi tiap varian | rumah 3 bentuk, menara 2, papan 2 |
| B6 | Anggaran ponsel | jumlahkan segitiga seluruh 22 bangunan desa dari mesh sebenarnya | ≤ 16.000 segitiga desa, ≤ 900 per bangunan, ≤ 1.400 verteks per bangunan |
| B7 | Berdiri di tanah | `RegionView.building_layout()` vs `RegionData.height_at()` | kaki bangunan **tidak pernah** di atas tanah, tidak > 3,2 m di bawahnya |
| B8 | Kontrak tabrakan | `building.layout[row][7]` vs `RegionData.blocker_radius()` | sama untuk rumah, menara, gerbang, sumur (2,0 / 2,4 / 2,2 / 0,9) |
| B9 | Tidak ada bangunan ganda | `prop_layout()` tidak boleh memuat jenis bangunan | 0 baris; `stats().buildings` ≥ 20 |
| B10 | Occlusion ikut bangunan | `occluders_for()` dengan kamera di depan menara, ksatria di belakangnya | minimal satu kunci `b:…` memudar 0,24–1,0 |

Tangkapan layar baru (job `screenshots`), semuanya dari tahap uji yang
menjejarkan seluruh kit di satu landasan:

| Berkas | Isi |
| --- | --- |
| `docs/screenshots/bangunan/50_bangunan_{depan,kanan,belakang,kiri}_{siang,malam}.png` | 4 sisi × 2 fase, 640×360 |
| `docs/screenshots/bangunan/kit_bangunan.png` | kontak sheet 4×2 berlabel, disusun `tools/building_sheet.py` |

Hasil nyata (CI `ci` **40263694665**, semua job hijau): `BuildingTest`
**29 pemeriksaan, 0 gagal**; `kit_audit` **16 sel, 7 jenis, 123.416 B**;
`pack_audit` 6 paket, 1.270.793 B, 0 galat. Selain B1–B10, tes juga menjaga
empat hal yang tidak direncanakan di awal tetapi menangkap bug sungguhan:

- **normal bukan nol** untuk setiap verteks (`|n| = 1 ± 0,02`) — inilah yang
  menangkap jebakan `PackedVector3Array` (DESIGN_NOTES §22.8);
- **mesh deterministik**: kit yang sama membangun verteks pertama yang sama
  persis, supaya dua tangkapan bisa dibandingkan;
- **alpha kelas yang sah**: hanya 0, 0,4, atau 1,0 — nilai lain berarti kelas
  detail salah tulis;
- **PlayTest** kini memisahkan `Props_` dari `Buildings_` dan menuntut setiap
  prop tetap memakai `prop.gdshader` sementara setiap bangunan memakai
  `building.gdshader`, serta jumlah instance bangunan sama dengan isi
  `building_layout()`.

Yang **tidak** dibuktikan di sini: 30 FPS di GPU HP, dan apakah komposisi
desanya enak dilihat. Yang pertama diukur lewat jurnal `[PERF]` di perangkat,
yang kedua lewat tangkapan di atas — ditambah pemeriksaan mata pada delapan
tangkapan itu sendiri, yang sudah menangkap empat cacat (panggung tanpa kit,
atap terbuka di ujung, jendela menyala di siang hari, dan nyala obor mirip
konfeti) sebelum langkah ini dinyatakan selesai.

## Langkah 3C — pertarungan turn-based (0.11.0)

Uji baru: `game/tests/BattleTest.tscn` (aturan + simulator, headless) dan
`game/tests/BattleShot.tscn` (tangkapan layar). Job CI baru: **Battle rules**;
tangkapan masuk job `screenshots`. Perintah lokal:

```
godot --headless --path game res://game/tests/BattleTest.tscn
xvfb-run -a godot --path game --resolution 1280x720 \
    res://game/tests/BattleShot.tscn -- --state=break \
    --capture=/abs/docs/screenshots/pertarungan --capture-name=51_pertarungan_break
```

| # | Yang diuji | Cara | Lulus bila |
| --- | --- | --- | --- |
| C1 | Tabel masuk akal | `BattleData._validate()` | enam senjata, enam elemen, tiap skill menunjuk senjata yang ada, tiap item berelemen yang dikenal, Shield tiap musuh 2–8, tiap musuh punya ≥1 kelemahan dan EXP > 0, encounter 1–5 musuh |
| C2 | Ikon kelemahan benar-benar ada | baca `atlas_ui.json` | ≥27 entri; setiap `w_<senjata>` dan `e_<elemen>` ada (kalau tidak, baris "?" kosong) |
| C3 | Rumus | `resolve_hit` dengan DEF 10 vs 80, Break on/off, guard, power 130, Boost 3, senjata vs elemen, ATK 1 vs DEF 999 | DEF tinggi memotong damage; Break ≈1,5x (1,3–1,75); guard <0,6x; senjata memakai ATK dan elemen MATK; damage **tidak pernah** < 1; sebaran 200 pukulan di dalam 0,85–1,15 dari basis |
| C4 | Shield & BREAK | 3 pukulan tombak ke Orc Prajurit (Shield 3) | Shield habis ≤3 pukulan lemah, `broken` benar, Shield 0 saat break |
| C5 | Musuh yang BREAK kehilangan giliran | log `kehilangan giliran` + giliran orc berikutnya | pesan muncul **dan** saat orc kembali, Shield-nya penuh lagi |
| C6 | DEF terpotong saat break | `resolve_hit` DEF 100, break on/off | rasio > 1,8 |
| C7 | BP & Boost | Knight dengan 3 BP, `boost: 3` | tepat 4 event `hit`; BP terpakai ≤ `bp_spend_max`; BP tidak pernah > `bp_max` |
| C8 | Kelemahan dipelajari, bukan dicetak | skill tombak ke Pemimpin; Granat Api ke Prajurit; Botol Es ke Prajurit | `tombak` dan `api` terbuka, `es` **tidak** (bukan kelemahannya); `observed` kosong di awal |
| C9 | Fase bos | HP Pemimpin 50%+1 lalu satu skill | event `phase` muncul, `phase == 2`, kelemahan `petir` terbuka, Shield penuh; Pemimpin mulai Shield 6 |
| C10 | Kejutan | `apply_ambush()` | +1 BP untuk party, −1 Shield musuh pertama, encounter `pos_gunung` bertanda `ambush` |
| C11 | Kabur | bos: satu percobaan; orc biasa: sampai 30 percobaan | bos **tidak bisa** kabur dan pertarungan tidak berakhir; orc biasa berakhir dengan `result == "flee"` |
| C12 | Skill, item, buff | Tebas Naik (SP 6), Ramuan, Sumpah Penjaga | SP berkurang tepat 6, HP naik, item berkurang satu, `def_up` > 0 dan bertahan 3 giliran |
| C13 | 1000 pertarungan, policy Auto | `suggest_action()` + `submit()` | menang ≥95%; rata-rata 4,5–9 ronde; median 5–8; terburuk ≤30; BREAK di ≥90% pertarungan; Boost dipakai >1000 BP |
| C14 | Tanpa Break/Boost lebih buruk | 200 pertarungan `attack` boost 0 | menang < 120 dari 200 |
| C15 | Simpanan hasil pertarungan | `SaveGame` skema 3: tulis, muat ulang, dan simpanan skema 2 | `battles_won`, `leaf`, `observed` kembali utuh; simpanan lama tetap terbaca dengan `battle` kosong dan progres lama tidak hilang |
| C16 | Kamera pertarungan memakai rig lapangan | `BattleShot` membaca `view.camera` | kamera arena adalah `CameraRig/Camera3D` milik diorama (bukan `Camera3D` baru) dan `current == true` |
| C17 | `battle_frame`/`battle_release` simetris | `CameraTest._test_battle_handover` | yaw pertarungan −12; lensa kembali persis (pitch/fov/jarak/yaw/look-ahead); target follow kembali ke aktor |
| C18 | Latar jauh mengikuti **mata** kamera, bukan pemain dan bukan titik bidik | `CameraTest._test_far_follows_camera` (tanpa pemain) | posisi `RidgeNear` ≤ 0,75 m dari `Camera3D` (bukan dari rig: lensa berdiri 15,6 m di belakang titik bidik); tidak ada cincin yang tertinggal di titik nol |
| C19 | Semua petarung di dalam frame | `BattleShot._check_frame` → `[CHECK]` | kelima petarung berjarak ≥ 2 px dari tepi 1280×720 pada setiap state |
| C20 | Panel UI di dalam layar | `BattleShot._check_frame` → `[CHECK]` | menu perintah (termasuk BOOST) tidak melewati tepi kanan/bawah; lembar hasil terpusat |
| C23 | (belum ada) prop yang menutupi petarung | — | **belum diuji**: `Orc Pemimpin` tertutup gerbang batu di pos_gunung dan semua aturan C19/C22 tetap hijau (DESIGN_NOTES 23.11 poin 6) |
| C22 | Tidak ada petarung di dalam bangunan | `BattleShot._check_frame` → `[CHECK]` | setiap petarung yang hidup berdiri di ubin `walkable_tile` milik region (bukan di dalam pondok/tebing/air); `BattleView.build()` menggeser arena sampai itu benar |
| C21 | Teks di dalam bingkai dan nama chip utuh | `BattleShot._check_frame` → `[CHECK]` | margin kiri/kanan setiap `PanelContainer` yang tampil ≥ tebal bingkai 9-slice (teks tidak menempel di kuningan); tiap chip bar giliran adalah satu kata utuh dari nama unit (bukan potongan `substr`); bar giliran tidak menabrak tombol 1x/Auto |

C19, C20, C21 dan C22 **menggagalkan build**: job `screenshots` membaca `[CHECK] FAIL`
dari log dan keluar dengan kode 1. Ini satu-satunya cara aturan tentang *frame*
bisa ditegakkan - tes headless tidak punya layar.

Kalau langkah **Camera rules** gagal, alasan tiap `[CAMERA] FAIL` juga dikirim
sebagai anotasi `::error::`; kalau lulus, jumlah pemeriksaannya dikirim sebagai
anotasi `::notice::` (run `40619025766` membacanya: **38 pemeriksaan, 0 gagal** -
31 aturan lama, enam serah-terima C17, satu latar jauh C18). Anotasi `::error::`
tidak pernah dipakai untuk kabar baik, karena HP tidak bisa membuka log untuk
memeriksa bahwa tanda merahnya cuma informasi. Itu bukan hiasan: log mentah sebuah job disimpan di
blob storage yang tidak selalu bisa dibaca dari HP, sedangkan
`gh api repos/<owner>/<repo>/check-runs/<id>/annotations` selalu bisa.

Tangkapan layar baru (job `screenshots`, 1280×720), semuanya dari `BattleScene`
sungguhan yang berdiri di region sungguhan (`Diorama.tscn`):

| Berkas | Isi |
| --- | --- |
| `51_pertarungan_transisi.png` | layar pecah di tengah transisi (0,25 s ke dalam 0,55 s) |
| `51_pertarungan_awal.png` | arena, bar giliran, strip party, menu perintah |
| `51_pertarungan_menu.png` | target terpilih + papan kelemahan 6×6 terbuka |
| `51_pertarungan_kelemahan.png` | dua kelemahan Pemimpin dan dua Prajurit sudah terbuka, sisanya "?" |
| `51_pertarungan_boost.png` | tombol BOOST setelah dua kali ditekan |
| `51_pertarungan_break.png` | BREAK: Shield habis, angka melayang, plate berubah |
| `51_pertarungan_damage.png` | angka damage melayang di atas target |
| `51_pertarungan_fase2.png` | Pemimpin di fase 2 (kelemahan baru + Shield penuh) |
| `51_pertarungan_hasil.png` | layar hasil menang (EXP/Leaf/drop) |
| `51_pertarungan_kalah.png` | layar kalah (kembali ke simpanan, penalti Leaf) |

Yang **tidak** dibuktikan di sini: 30 FPS dengan lima musuh di GPU HP (diukur
lewat jurnal `[PERF]` di perangkat), dan apakah tampilan arena enak dilihat —
yang kedua hanya bisa dinilai dari sepuluh tangkapan di atas.
