# Tata letak HUD sentuh (LANTERNFALL)

Dokumen ini merangkum aturan tata letak `scenes/ui/TouchHUD.tscn` setelah penataan
ulang, supaya perubahan berikutnya tidak mengembalikan HUD yang berantakan.

Gambar pratinjau (kerangka, bukan tangkapan layar asli): **`docs/hud_layout_preview.png`**.

## Struktur pohon

```
TouchHUD (CanvasLayer, process_mode = ALWAYS)
└─ HudRoot (Control, full-rect, theme, mouse_filter = IGNORE)
   ├─ StatusBox      → HPBar / StaminaBar / OilBar / CoinRow
   ├─ ToastLabel     (sementara, fade out)
   ├─ RadialButton   ("MENU")
   ├─ BtnAttack, BtnDodge, BtnInteract
   ├─ DialoguePanel, JurnalPanel, CreditsPanel, SettingsPanel
   └─ RadialLayer    ← HARUS anak terakhir (digambar paling atas)
      └─ RadJurnal / RadKredit / RadSetelan / RadSinar / RadKelip / RadTutup
JoystickPad (Control, sibling dari TouchHUD)
```

## Aturan yang harus dipegang

1. **Satu elemen = satu anchor + offset.** Jangan membungkus semuanya ke dalam
   satu `MarginContainer` dengan banyak anak — itu penyebab HUD saling menutupi.
2. **Safe area dikonversi dulu.** `DisplayServer.get_display_safe_area()`
   mengembalikan piksel *fisik*. Kalikan dengan
   `get_viewport().get_visible_rect().size / DisplayServer.window_get_size()`
   sebelum dipakai sebagai inset satuan desain.
3. **Jangan menaruh tombol aksi di `VBoxContainer`/`HBoxContainer` yang
   `size_flags`-nya `SHRINK_CENTER`** — tombolnya akan melayang di tengah layar.
4. **Semua panel bersifat eksklusif.** Tidak ada dua panel yang boleh `visible`
   bersamaan; `_open_panel()` menutup panel lain lebih dulu.
5. **Panel → game di-pause** lewat `_update_pause_state()`. HUD sendiri tetap
   hidup karena `process_mode = PROCESS_MODE_ALWAYS`.
6. **Kontrol gerakan disembunyikan** saat menu terbuka atau dialog berjalan
   (`_sync_controls_visibility()`), karena posisinya berbenturan dengan panel
   bawah-tengah dan busur radial.
7. **RadialLayer tetap anak terakhir HudRoot**, kalau tidak panel dialog akan
   menutupi tombol-tombol radial.

## Geometri tetap (ruang desain 1280 × 720)

| Elemen | Posisi (x0, y0, x1, y1) | Catatan |
| --- | --- | --- |
| `StatusBox` | 20, 16, 300, 190 | VBox, separation 8 |
| `ToastLabel` | 380, 14, 900, 62 | hilang sendiri setelah 2,2 s |
| `RadialButton` | 1148, 24, 1252, 128 | pusat busur = **(1200, 76)** |
| `BtnAttack` | 1114, 504, 1246, 636 | selalu tampil |
| `BtnDodge` | 984, 564, 1096, 676 | selalu tampil |
| `BtnInteract` | 1120, 364, 1232, 476 | hanya saat ada objek yang bisa disentuh |
| `DialoguePanel` | 200, 340, 1080, 700 | bawah-tengah |
| `JurnalPanel` | 280, 130, 1000, 590 | tengah |
| `CreditsPanel` | 250, 120, 1030, 600 | tengah |
| `SettingsPanel` | 320, 90, 960, 630 | tengah |
| Zona joystick | lingkaran (150, 560) r = 72 | kiri bawah |

## Busur radial

Enam tombol 80 × 80 pada **R = 380** mengitari pusat (1200, 76), sudut
180° → 90° dengan langkah 18° (menyapu ke kiri lalu ke bawah).

| Tombol | Sudut | Pusat | Offset (kiri, atas, kanan, bawah) |
| --- | --- | --- | --- |
| RadJurnal | 180° | 820, 76 | −500, 36, −420, 116 |
| RadKredit | 162° | 838.6, 193.4 | −481.4, 153.4, −401.4, 233.4 |
| RadSetelan | 144° | 892.6, 299.4 | −427.4, 259.4, −347.4, 339.4 |
| RadSinar | 126° | 976.6, 383.4 | −343.4, 343.4, −263.4, 423.4 |
| RadKelip | 108° | 1082.6, 437.4 | −237.4, 397.4, −157.4, 477.4 |
| RadTutup | 90° | 1200, 456 | −120, 416, −40, 496 |

Rumus jarak antar tetangga: `2 · R · sin(Δθ/2)`.
Dengan 6 item pada busur 90° (Δθ = 18°) dan tombol 80 px, jarak terkecil berada
di pasangan tengah (144° ↔ 126°):

```
dx = dy = 2 · 380 · sin(9°) · sin(45°) = 84,0 px  >  80 px  ✓ tidak tabrakan
```

Kalau jumlah item atau ukuran tombol diubah, hitung ulang `R` minimalnya:

```
R_min = lebar_tombol / (2 · sin(Δθ/2) · min(sin|arah|, cos|arah|))
```

Versi lama memakai R = 160 dengan tombol 104 px — jarak antar pusat cuma 50 px,
jadi tombol-tombolnya saling tabrakan.

## Pemeriksaan otomatis

Sebelum commit, jalankan:

```bash
# 1. semua skrip harus bisa di-parse
for f in $(find . -name '*.gd' -not -path './.git/*'); do /tmp/venv/bin/gdparse "$f"; done

# 2. semua referensi res:// harus ada (kecuali .translation yang dibentuk saat import)
# 3. path @onready di controller harus cocok dengan node di .tscn
# 4. tidak ada dua node sedarah di HudRoot yang rect-nya bertumpang tindih
```

## Aset terkait

| Ikon | Sumber | Dipakai di |
| --- | --- | --- |
| `icon_bulu.png` | `Icon54_128px.png` | RadJurnal |
| `icon_gulungan.png` | `Icon86_128px.png` | RadKredit |
| `icon_gerigi.png` | `Icon18_128px.png` | RadSetelan |
| `icon_lentera.png` | `Icon44_128px.png` | RadSinar |
| `icon_kelip.png` | `Icon81_128px.png` | RadKelip |
| `icon_tutup.png` | `Icon97_128px.png` | RadTutup |
| `icon_pedang.png` | `Icon2_128px.png` | BtnAttack |
| `icon_koin.png` | `Icon79_128px.png` | CoinRow |

Ikon radial diperkecil ke 36 × 36 dan labelnya ke 18 px supaya muat di tombol 80 × 80.
Pemetaan gaya lengkap (panel, bar, tombol) ada di `docs/UI_ASSET_MAP.md`.
