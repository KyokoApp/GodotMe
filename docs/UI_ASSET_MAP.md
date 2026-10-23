# Peta Aset UI — LANTERNFALL

Seluruh UI/GUI dalam game memakai **Fantasy RPG UI Pack (versi DEMO)** karya **dobo_ui**
([dobo-ui.itch.io/fantasy-rpg-ui-pack](https://dobo-ui.itch.io/fantasy-rpg-ui-pack)).

```
assets/ui/
├── doboui/                     # 171 file asli dari pack (struktur foldernya dipertahankan)
│   ├── Buttons/                # SquareButtons, PatternButtons, FantasyButtons (4 warna)
│   ├── Containers/             # panel latar
│   ├── Modals/                 # modal persegi
│   ├── Dialogues/              # panel dialog, pelat nama, pemisah, pilihan
│   ├── Progress_bars/          # latar & isi bar
│   ├── Item_slots/             # slot inventori / perlengkapan
│   ├── Headers/, Labels/       # pita judul & label
│   ├── Controls/               # panah & toggle
│   ├── Cards/                  # kartu (belum dipakai)
│   ├── Icons/                  # 170 ikon (32/64/128/256px + versi outline)
│   └── CREDITS_dobo_ui.txt     # catatan lisensi dari pembuat
├── styles/                     # StyleBoxTexture 9-patch .tres (satu per gaya)
├── lanternfall_theme.tres      # Theme Godot: menghubungkan style ke tiap jenis kontrol
└── icons/                      # ikon 48px yang sudah dipakai HUD (turunan dari Icons/)
```

## 1. Yang dipakai di HUD (`scenes/ui/TouchHUD.tscn`)

| Bagian UI | Style (`.tres`) | Sumber PNG | Ukuran | Margin 9-patch (L/T/R/B) |
| :--- | :--- | :--- | :--- | :--- |
| Tombol aksi bulat (SERANG/HINDAR/SINAR/KELIP/AKSI) — normal | `button_normal.tres` | `Buttons/SquareButtons/SquareButton3_ultramarine.png` | 104×107 | 17/15/17/15 |
| … hover | `button_hover.tres` | `…SquareButton3_cyan.png` | 104×107 | 17/15/17/15 |
| … ditekan | `button_pressed.tres` | `…SquareButton3_purple.png` | 104×107 | 17/15/17/15 |
| … fokus | `button_focus.tres` | `…SquareButton3_green.png` | 104×107 | 17/15/17/15 |
| … nonaktif | `button_disabled.tres` | `…SquareButton3_ultramarine.png` + `modulate_color` abu | 104×107 | 17/15/17/15 |
| Tombol Jurnal / Kredit | sama (tema global) | `…SquareButton3_ultramarine.png` | 104×107 | 17/15/17/15 |
| Pilihan dialog | `button_wide_normal/hover/pressed.tres` | `Buttons/PatternButtons/PatternLongButton2_{ultramarine,cyan,purple}.png` | 401×107 | 49/46/50/46 |
| Panel dialog & kredit | `panel_large.tres` | `Containers/Container1_default.png` | 787×195 | 43/45/45/43 |
| Panel jurnal (modal) | `panel_modal.tres` | `Modals/Modal12.png` | 409×409 | 15/16/15/17 |
| Pelat teks (banner wilayah, mata uang, nama pembicara) | `panel_default.tres` | `Containers/Container3_default.png` | 721×129 | 18/17/17/17 |
| Latar bar HP/Stamina/Minyak | `bar_background.tres` | `Progress_bars/ProgressBarBackground4.png` | 803×46 | 14/12/14/12 |
| Isi bar HP & Stamina | `bar_fill_blue.tres` | `Progress_bars/ProgressBarMaxFill5_blue.png` | 787×29 | 5/4/5/4 |
| Isi bar Minyak Lentera | `bar_fill_yellow.tres` | `Progress_bars/ProgressBarMaxFill5_yellow.png` | 787×30 | 6/4/6/5 |
| Slot perlengkapan (Jurnal) | `slot_normal.tres` | `Item_slots/itemSlot1_gray.png` | 129×129 | 32/29/33/29 |
| Slot terpilih / kosong | `slot_selected.tres`, `slot_empty.tres` | `itemSlot1_sky.png`, `EmptyItemSlot10_darkTheme.png` | 129×129 | 32/29/33/29 |
| Pemisah dialog | TextureRect langsung | `Dialogues/Separator3.png` | 791×19 | — (Keep Aspect) |
| Pita judul Jurnal | TextureRect langsung | `Headers/Header2_ultramarine.png` | 820×135 | — (Keep Aspect) |
| Ikon tombol SERANG | `icons/icon_pedang.png` | `Icons/Icons/128px/Icon2_128px.png` (diperkecil 48px) | 48×41 | — |
| Ikon tombol Jurnal | `icons/icon_bulu.png` | `Icons/Icons/128px/Icon54_128px.png` | 48×48 | — |
| Ikon tombol Kredit | `icons/icon_gulungan.png` | `Icons/Icons/128px/Icon86_128px.png` | 46×48 | — |

> **Catatan jujur:** penamaan ikon di atas adalah *tebakan bentuk* dari analisis piksel, bukan
> hasil melihat gambar. Kalau ternyata meleset, tinggal ganti berkasnya — lihat §3.

## 2. Cara kerja temanya

- `assets/ui/lanternfall_theme.tres` dipasang di `SafeAreaMargin` (node induk seluruh HUD),
  jadi semua kontrol di bawahnya mewarisi gaya: tombol, label, panel, progress bar.
- Tombol **pilihan dialog** dibuat saat runtime oleh `TouchHUDController._on_dialogue_started()`,
  karena itu gayanya dipasang lewat `add_theme_stylebox_override()` (pakai varian *wide*).
  Varian wide **tidak** dipasang di tema global karena margin ujungnya 46px → butuh tinggi ≥ 92px.
- `texture_filter` HUD diset **Linear** (di `SafeAreaMargin`) supaya seni pack yang halus tidak
  terlihat bergerigi; dunia game tetap Nearest karena dirender di `SubViewport` 640×360 sendiri.

## 3. Cara menyesuaikan

**Ganti varian warna tombol** — ganti `path` di `assets/ui/styles/button_*.tres`, atau pakai
warna lain yang tersedia di pack: `ultramarine`, `cyan`, `green`, `purple`.

**Ganti ikon** — ikon dipasang di `scenes/ui/TouchHUD.tscn` lewat properti `icon` pada
`BtnAttack`, `BtnPauseMenu`, `BtnCredits`. Pilihan lain yang tersedia di
`assets/ui/doboui/Icons/Icons/128px/` (salin dulu lalu perkecil ke ~48px):

| Berkas asli | Bentuk (tebakan) | Cocok untuk |
| :--- | :--- | :--- |
| `Icon2_128px.png` | pedang / senjata | SERANG ✅ (dipakai) |
| `Icon54_128px.png` | bulu / pena | JURNAL ✅ (dipakai) |
| `Icon86_128px.png` | gulungan / naskah | KREDIT ✅ (dipakai) |
| `Icon9_128px.png` | bola / orb bercahaya | skill cahaya |
| `Icon18_128px.png` | salib / kompas 4 arah | interaksi, target |
| `Icon20_128px.png` | perisai lebar | HINDAR / bertahan |
| `Icon44_128px.png` | helm / anvil berornamen | perlengkapan |
| `Icon79_128px.png` | medali / koin bulat | mata uang |
| `Icon81_128px.png` | kantong / tas | inventori |
| `Icon95_128px.png` | perisai bulat berlambang | bertahan |
| `Icon97_128px.png` | medalion bergaris silang | quest |
| `Icons/Shapes/StarShape*.png` | bintang | skill, pencapaian |

**Ubah margin 9-patch** — kalau hasil regangan terasa aneh (hiasan ujung ikut melar),
edit nilai `texture_margin_*` di berkas `.tres` terkait. Patokan: margin = radius sudut
+ lebar hiasan ujung; makin besar margin, makin sedikit bagian tengah yang diregangkan.

**Tambah gaya baru** — salin salah satu `.tres` di `assets/ui/styles/`, ganti `path` dan
margin, lalu pasang lewat `theme_override_styles/...` di node yang diinginkan.
