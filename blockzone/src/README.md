# Sumber BlockZone (hasil pecah, terverifikasi identik)

`game.html` asli 3.287 baris / 113.415 byte dipecah jadi bagian-bagian yang
nyaman dibaca **tanpa mengubah satu byte pun**. Buktinya bukan klaim — ada
skripnya:

```bash
python3 blockzone/tools/build_game.py      # susun ulang + bandingkan dengan arsip
# identik: 113415 byte, sha256 c92c8a0d486fef93b4ef5466546389bb466afc96d0e9bc3e6e1437fe48efaf20
```

Kalau ada yang tidak sengaja mengubah `src/`, skrip itu gagal dan menunjuk
offset byte pertama yang berbeda. Arsip aslinya tetap `blockzone/www/game.html`
(md5 `a94e4545d2d199ed8f563e1811105240`) dan tidak pernah ditimpa.

## Isi

| Berkas | Isi | Baris asli di `game.html` |
| --- | --- | --- |
| `game.template.html` | kerangka HTML + semua markup (menu, HUD, shop, canvas) dengan tiga token | 1-8, 533-544, 571-701, 3285-3287 |
| `style.css` | seluruh CSS di dalam `<style>` | 9-532 |
| `js/01-boot.js` | layar boot "ようこそ" (ikon + fade ke menu) | 545-570 |
| `js/02-game.js` | inti game: render canvas, bot, skill, iklan, i18n | 702-3284 |

Token di template:

| Token | Diganti dengan |
| --- | --- |
| `{{STYLE}}` | isi `style.css` |
| `{{BOOT_JS}}` | isi `js/01-boot.js` |
| `{{GAME_JS}}` | isi `js/02-game.js` |

## Aturan main

* **Jangan** menambah/menghapus newline di akhir berkas bagian — builder membuang
  tepat satu newline penutup sebelum menyisipkan. Itu sebabnya hasilnya bisa
  byte-identik sementara berkasnya tetap rapi di editor.
* `www/game.html` adalah **acuan (golden)**. Setelah refactor apa pun, jalankan
  `build_game.py`; kalau keluar "identik", aman.
* Mengubah perilaku game itu urusan lain: edit `src/`, build, lalu salin hasilnya
  ke `www/game.html` **dan** perbarui `APK_INFO.json` (md5 + `version.json`
  build baru) — itu berarti versi baru, bukan lagi arsip apa adanya.

## Cara bagian ini dibuat

`blockzone/tools/split_game.py` — dijalankan sekali, memotong berdasarkan nomor
baris (diproses dari bawah ke atas supaya indeks tidak bergeser), lalu menyusun
ulang di memori dan membandingkan hasilnya dengan berkas asli sebelum menulis
apa pun.
