# Permintaan aset — FASE 4 (8 karakter party)

Status: **berhenti menunggu aset**, sesuai aturan brief §2 ("bila aset yang cocok
tidak ditemukan, berhenti dan tanyakan") dan aturan kerja kita ("sprite karakter
tidak boleh dibuat lewat kode").

## Kenapa FASE 4 belum bisa dikerjakan

Yang ada sekarang di `assets_src/characters/`:

| Karakter | Pack | Ukuran frame | Animasi | Potret | Ikon |
| --- | --- | --- | --- | --- | --- |
| `knight` (pemain) | pack ksatria (berlisensi, `License.txt`) | 112×96 | 12 | tidak ada | tidak ada |
| `soldier` (Penjaga Bram) | Tiny RPG Character Asset Pack 01 v2.0 | 100×100 | 7 | tidak ada | tidak ada |
| `orc` | Tiny RPG Character Asset Pack 01 v2.0 | 100×100 | 6 | tidak ada | tidak ada |

FASE 4 meminta **8 job**, masing-masing dengan: sprite overworld, sprite battle,
potret dialog 96×96 minimal **4 ekspresi**, dan ikon UI.

Yang kurang:

1. **5 job lain tidak punya aset sama sekali** (penyihir, penyembuh, pemanah,
   pedagang, pencuri, cendekiawan, penari — 7 job, hanya ksatria & penjaga yang
   ada wujudnya, dan penjaga bukan job party).
2. **Tidak ada potret dialog** (netral/senang/marah/sedih) untuk satu karakter pun.
3. **Tidak ada ikon UI karakter** 16×16 / 24×24.
4. Pack yang ada **bukan layered/modular** (badan, rambut, baju, senjata
   terpisah), padahal brief §2 meminta variasi job dibuat dari kombinasi layer.
5. Dua pack yang ada berasal dari **seniman berbeda** (ksatria vs Tiny RPG).
   Brief melarang mencampur gaya; menambah 7 karakter dari pack ketiga akan
   melanggar aturan itu.

Sprite karakter **tidak** akan saya gambar sendiri lewat kode maupun generator —
itu dilarang brief §2 dan sudah jadi aturan tetap proyek ini.

## Yang perlu dikirim (pilih salah satu jalur)

### Jalur A — satu pack modular berlayer (paling sesuai brief §2)

Satu pack, satu gaya, satu resolusi, dengan layer terpisah:

```
assets_src/characters_pack/
  body/            badan dasar (semua pose)
  hair/            4–6 variasi rambut
  outfit/          jubah, baju, kulit, rompi
  weapon/          pedang, tongkat, busur, belati, kipas, buku
  palette.txt      daftar warna + nomor palet tiap layer
  LICENSE.txt      lisensi (CC0 / CC-BY) + URL sumber
```

### Jalur B — pack yang sama dengan Penjaga/Oorc

Karakter tambahan dari **Tiny RPG Character Asset Pack** yang sama (seniman yang
sama), supaya gaya dan resolusi 100×100 tetap seragam. Sebutkan nama pack + versi
+ lisensi kalau memilih jalur ini.

## Format berkas yang saya butuhkan (kedua jalur)

Satu PNG per animasi, **strip horizontal, kiri→kanan, latar transparan,
menghadap KANAN** (kiri = `flip_h` di engine), **tanpa bayangan** (bayangan
dibuat engine):

```
assets_src/characters/<id>/
  idle.png          minimal 4 frame (6 lebih baik)
  walk.png          6–8 frame
  run.png           6–8 frame (boleh tidak ada; jalan saja cukup)
  attack_1.png      5–7 frame
  attack_2.png      opsional (kombo)
  attack_3.png      opsional
  hurt.png          3–4 frame
  death.png         4–5 frame
  LICENSE.txt       lisensi + URL sumber + nama seniman
  SOURCE.txt        nama pack + versi + tanggal unduh
assets_src/portraits/<id>/
  neutral.png  happy.png  angry.png  sad.png     minimal 96×96, latar transparan
assets_src/icons/<id>.png                        16×16 atau 24×24, satu grid
```

`<id>` yang saya siapkan di pipeline: `swordsman`, `mage`, `healer`, `archer`,
`merchant`, `thief`, `scholar`, `dancer` (job 1–8 dari brief §4), ditambah
`knight`, `soldier`, `orc` yang sudah ada.

Kalau ada karakter yang animasinya tidak selengkap tabel di atas, **kirim apa
adanya** — saya tidak akan memalsukan animasi yang tidak ada (aturan proyek:
tidak mengarang `cast`/`victory` dari frame lain). Yang tidak ada akan
dilaporkan sebagai "tidak ada", bukan diisi animasi buatan.

## Yang akan saya lakukan begitu aset masuk

1. Tambah entri ke `tools/import_character_sprites.py` (`SPEC`): ukuran frame,
   jumlah frame per animasi, pivot dari bbox kaki, `walk_stride_m`/`run_stride_m`,
   `body_radius_m`.
2. `--import` menyalin byte PNG apa adanya ke `game/game/assets/characters/<id>/`
   dan membuat `.tres`; **tanpa resampling**.
3. `--check` (dijalankan CI) menolak build bila lebar strip tidak habis dibagi
   ukuran frame, animasi kosong, atau pivot basi.
4. `CharacterTest` menampilkan semua karakter + semua animasi berdampingan,
   berlabel, plus potret & ikon, lalu saya kirim tangkapan layarnya.
5. `VisualTest` menaruh satu karakter di diorama (siang & malam).
6. Masuk `characters.pck` (sprite + potret) dan `ui.pck` (ikon); manifest +
   SHA-256 diperbarui; save pemain tidak disentuh.

## Lisensi

Untuk tiap pack saya butuh nama lisensi dan URL sumber. Kalau tidak jelas,
entri `CREDITS.md` akan ditulis **"lisensi: DIISI PEMILIK (TODO)"** — saya tidak
akan mengarang izin. Pack yang dipakai sekarang (Tiny RPG Soldier/Orc) masih
berstatus TODO itu.

## Keputusan ukuran kanvas — SUDAH DIAMBIL (25 Okt 2026)

**Semua karakter baru: 48×64** (brief §3). Karakter lama tetap dipakai apa adanya
sampai ada aset 48×64 dari pemilik — saya tidak akan menggambar ulang sendiri.
Lihat `DESIGN_NOTES.md` §16.

## Rincian keputusan

Brief §3 menyebut kanvas **48×64**. Kenyataan di game sekarang: ksatria
**112×96**, penjaga/orc **100×100** — dan spesifikasi itu sudah Anda verifikasi
di Fase 2/3 (pivot, tinggi meter, skala dunia 0,05 m per piksel). Dua angka ini
tidak bisa berlaku bersamaan tanpa mengubah semua aset dan mengulang uji visual.
