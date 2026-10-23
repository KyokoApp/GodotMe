# LANTERNFALL — NASKAH CERITA, PROFIL NPC & QUEST PART 1

## 1. Premis Dunia & Tema Inti
Matahari di atas kepulauan retak bagai cangkang telur tua dan perlahan meredup. Di bawah pulau-pulau karang, terhampar lautan kabut kelabu bernama **Selimut**. Dari dalam Selimut, merayap **Senyap**—entitas bayangan hening yang mengisap warna, suara, dan ingatan manusia hingga menyisakan dunia monokrom yang dingin. Satu-satunya penghalang Senyap adalah menara-menara lentera tua yang dirawat oleh **Para Penjaga**.

* **Protagonis — Nara (Nama Dapat Diganti):** Murid Penjaga muda di Desa Rembang. Lentera utama desanya padam untuk pertama kalinya dalam seratus tahun tepat di malam Guru Soka menghilang.
* **Pendamping — Kelip:** Roh ngengat lentera bersayap lavender kusam yang cerewet, gemar mengomentari masakan dan cuaca, tetapi diam-diam menyimpan rahasia pahit: setiap lentera agung diciptakan dari jiwa Penjaga masa lalu.
* **Antagonis — Sang Pemadam (Mantan Penjaga Agung Arkan):** Sosok tenang bersuara lembut yang memadamkan menara-menara lentera di kepulauan. Ia tidak haus kekuasaan; setelah menyaksikan ratusan murid dan sahabatnya dijadikan bahan bakar jiwa untuk menyalakan lentera abadi, ia berkesimpulan bahwa membiarkan malam turun secara alami adalah satu-satunya cara mengakhiri pengorbanan manusia yang kejam.

## 2. Profil 6 NPC Kunci di Pulau Embun (Bab 1) & Suara Dialognya

Setiap NPC memiliki diksi, ritme kalimat, dan konflik pribadi yang khas:

| ID & Nama NPC | Peran di Pulau Embun | Konflik Pribadi | Gaya Bahasa & Kebiasaan Bicara |
| :--- | :--- | :--- | :--- |
| **1. Tetua Damar** | Kepala Dermaga Tua | Terjepit antara tuntutan pajak minyak Serikat Layar Abu dan keselamatan nelayan kecil. | Kalimat tenang, sering memakai metafora laut, garam, dan kayu lapuk; memanggil Nara dengan *"Nak Nara"*. |
| **2. Nenek Marni** | Penambal Jaring & Ibu Kehilangan | Putranya hilang di kabut tiga musim lalu; ia menyembunyikan lentera kaca retak berisi surat terakhir sang anak. | Kalimat pendek-pendek, sering mengulang kata di akhir kalimat (*"...begitu kan, ya?"*), hangat namun menyimpan duka. |
| **3. Bima** | Nelayan Muda Pemberani | Ingin melaut menembus kabut senja demi memberi makan adiknya, tetapi perahunya belum punya lentera haluan. | Cepat, lugas, antusias, sering menggunakan kata seru khas pesisir (*"Astaga angin!"*, *"Gas dayung!"*). |
| **4. Saudagar Lira** | Utusan Serikat Layar Abu | Ditugaskan menagih kuota minyak desa, namun hati kecilnya muak melihat korupsi para petinggi Serikat di Pelabuhan Karam. | Formal, terukur, sering menghitung angka atau untung-rugi di tengah kalimat, nada bicara diplomatis. |
| **5. Perajin Raka** | Pembuat Lentera & Apoteker | Mulai kehilangan ingatan tentang wajah mendiang istrinya karena terlalu sering memperbaiki lentera yang tercemar jelaga Senyap. | Puitis, agak pelupa, sering berhenti sejenak mencari kata yang hilang (*"Apa namanya tadi... ah, kelopak senja"*). |
| **6. Dara** | Penjaga Gudang Garam & Pengamat Burung | Menemukan jalur rahasia penyelundup minyak di balik bukit kunang-kunang tetapi takut melapor sendirian. | Berbisik, waspada, kalimat rapat dan penuh detail pengamatan visual. |

## 3. Struktur Quest Utama Bercabang, Quest Sampingan & Rahasia per Bab

### PROLOG: "Lentera Terakhir Rembang"
* **Tujuan Tutorial Tersamar:** Menggerakkan Nara dengan *virtual joystick*, memeriksa jejak lensa retak Guru Soka (*tap-to-interact*), menghindari sergapan *Rayap Jelaga* (*dodge i-frame*), dan menyalakan **Lentera Gerbang Rembang** yang mengembalikan warna pastel desa melalui transisi shader.
* **Naskah Dialog Pembuka:**
  > **Kelip:** "Nara! Bangun, jangan melamun terus! Lentera Utama Desa Rembang baru saja batuk tiga kali lalu padam. Seratus tahun api itu menyala, dan malam ini kabut Senyap sudah menjilat pagar dermaga!"  
  > **Nara (Pilihan A):** "Tenang, Kelip. Di mana Guru Soka sekarang?"  
  > **Nara (Pilihan B):** "Ambil lentera kuningan dulu, kita nyalakan Menara Gerbang."  
  > **Kelip:** "Guru Soka turun ke tepi Selimut Kabut sejak senja tadi. Hanya lensa retaknya yang tertinggal di jembatan tali. Kalau kita tidak menyalakan Lentera Gerbang sekarang, warga Rembang bakal lupa nama mereka sendiri!"

### BAB 1: "Pulau Embun" (Hub Pertama)
* **Quest Utama (`q_main_1_pulau_embun` — *Bara di Pulau Embun*):**
  - **Pilihan Bercabang Bermakna:**
    1. *Bela Nelayan (`bela_nelayan`):* Tolak upeti tambahan Serikat Layar Abu dan alihkan minyak untuk perahu nelayan. Reputasi `tetua_rembang +20`, harga ikan & penginapan di Pulau Embun turun 8%, tetapi Serikat mengirim patroli di Bab 3.
    2. *Kompromi Serikat (`kompromi_serikat`):* Bagi cadangan minyak desa agar jalur dagang tetap buka. Reputasi `serikat_layar_abu +20`, membuka stok **Besi Kapal Karam** lebih awal di pedagang.
* **5 Quest Sampingan Bercerita (Tanpa Filler):**
  1. *Surat di Dalam Lentera Kaca (`q_side_1_surat_botol`):* Menemukan lentera kaca putra Nenek Marni di karang dangkal dan memilih apakah membacakan surat pengakuan sang anak secara jujur atau menyembunyikan bagian pahitnya agar hati Nenek Marni tenang.
  2. *Jaring Benang Kunang (`q_side_1_jaring_terang`):* Menemani Bima memanen lumut bercahaya di tebing senja sambil melindunginya dari *Anjing Abu Dermaga*.
  3. *Catatan Harga Saudagar Lira:* Membantu Lira memeriksa pembukuan gudang yang dimanipulasi atasannya, membuka diskon dagang antar-pulau.
  4. *Lonceng Angin Dara:* Memasang tiga lonceng kuningan di jalur bukit agar warga tahu kapan kabut Senyap naik dari laut.
  5. *Sup Hangat Pondok Pertama:* Memasak *Teh Hangat Rembang* bersama warga untuk memulihkan ingatan seorang kakek penambal perahu.
* **Rahasia Tersembunyi Bab 1:** Ruang bawah tanah di bawah sumur kering dekat Pondok Nara yang menyimpan `1 Pecahan Kelip` dan catatan harian masa muda Guru Soka.
* **Boss 1 — Penjaga Kabut Terlupa (`boss_penjaga_kabut`):**
  - *Fase 1 (100% – 50% HP):* Menyerang dengan ayunan tongkat lentera padam dan memanggil 2 *Rayap Jelaga*. Perisai bayangannya harus dilucuti dengan berada dalam radius lentera Nara.
  - *Fase 2 (< 50% HP):* Memadamkan lampu arena dan melepaskan *Gelombang Kabut Pekat* (telegraph cincin oranye 0.45 detik). Nara harus menggunakan *Skill 1: Sinar Fokus* untuk menghentikan serudukannya.

### BAB 2: "Hutan Jamur Senja"
* **Quest Utama (`q_main_2_hutan_jamur` — *Gema di Hutan Jamur Senja*):**
  - Eksplorasi vertikal melintasi jembatan akar dan payung jamur raksasa, memantulkan cahaya lentera pada **Altar Cermin Cahaya** untuk membuka jalan yang tertutup sulur bayangan.
  - **Twist Cerita & Pilihan Bercabang:** Di Gua Ingatan, Nara menemukan bahwa Guru Soka tidak diculik melainkan sedang menyatukan dirinya ke inti lentera hutan yang retak. Nara menemukan bukti bahwa **Kelip** dulunya adalah manusia—Penjaga pertama Rembang.
    1. *Bebaskan Sisa Ingatan Guru Soka (`bebaskan_ingatan`):* Memberi Guru Soka ketenangan terakhir; Nara memperoleh item kunci `Lensa Retak Guru Soka` (menambah daya serang cahaya).
    2. *Segel Kembali ke Lentera (`segel_ke_lentera`):* Memperkuat tingkat restorasi warna Hutan Jamur Senja ke 90% secara permanen dan meningkatkan reputasi `penjaga_menara +25`.
* **4 Quest Sampingan Bercerita:**
  1. *Takaran Ingatan Perajin (`q_side_2_apoteker_buta`):* Mencari spora emas untuk membantu Perajin Raka mengingat kembali lagu pengantar tidur mendiang istrinya.
  2. *Anak Tersesat di Bawah Payung Jamur:* Menuntun bocah pencari jamur kembali ke kemah hanya dengan mengikuti jejak kunang-kunang tanpa menyalakan senjata (stealth cahaya).
  3. *Jembatan Tali yang Putus:* Memperbaiki jalur gantung antara dua tebing jamur agar pedagang keliling bisa lewat.
  4. *Suara Tiruan di Kabut:* Mengungkap sarang *Penenun Bisik* yang meniru suara tangisan warga untuk menjebak pengembara.
* **Rahasia Tersembunyi Bab 2:** Teras tertinggi Pohon Jamur Purba yang hanya bisa dicapai saat angin kencang, berisi resep masakan legendaris *Sup Jamur Kelip* dan `1 Pecahan Kelip`.

### BAB 3: "Pelabuhan Karam" & Akhir Part 1
* **Quest Utama (`q_main_3_pelabuhan_karam` — *Layar di Atas Abu*):**
  - Mengemudikan **Perahu Layar Kabut** (`BoatController.gd`) melintasi perairan Selimut menuju Pelabuhan Karam, membongkar konspirasi Serikat Layar Abu yang menimbun minyak lentera demi memonopoli harga di tengah krisis.
  - **Pilihan Bercabang:** Membakar kapal penyelundup minyak (`bakar_kapal_gelap`) untuk membagikan minyaknya langsung ke warga, atau menyelamatkan awak kapal yang disandera di palka (`selamatkan_awak`).
* **4 Quest Sampingan Bercerita:**
  1. *Jangkar Warisan Ayah:* Membantu pandai besi tua mengangkat besi kapal karam dari perairan dangkal untuk menempa *Tombak Suar Kuningan*.
  2. *Lentera Mercusuar Retak:* Menyalakan kembali suar kecil di ujung dermaga agar perahu nelayan Pulau Embun bisa berdagang langsung tanpa perantara Serikat.
  3. *Buku Log Kapten yang Hilang:* Mengembalikan catatan pelayaran terakhir kepada keluarga kelasi yang kapalnya karam sepuluh tahun silam.
  4. *Perjamuan Terakhir di Dermaga:* Memasak hidangan hangat bagi para pengungsi pulau luar yang baru tiba dengan perahu rusak.
* **Boss 2 — Nakhoda Abu Karam (`boss_nakhoda_abu`):**
  - Pertarungan dua fase di atas dek kapal karam yang miring. Fase 2 memanggil gelombang pasang kabut dan lemparan jangkar rantai berarah yang menuntut kombinasi *dodge i-frame* dan serangan balik *Tombak Suar*.
* **Finale Part 1 (`q_main_4_finale_pemadam` — *Harga Sebuah Cahaya*):**
  - Di **Pelataran Bara Terakhir**, Nara berhadapan dengan **Sang Pemadam**. Setelah pertarungan sinematik di mana lentera Nara hampir retak, Sang Pemadam menahan pukulannya dan memperlihatkan kebenaran di balik lentera agung. Ia meninggalkan Nara hidup-hidup bersama pilihan moral penutup Part 1 (`part1_ending_moral_choice`):
    - **Pilihan 1 (`jaga_bara_terakhir`):** *"Meski sakit, ingatan dan harapan manusia layak dijaga tetap menyala!"* -> Membuka jalur Part 2 sebagai **Penjaga Fajar Baru** dengan bonus kekuatan cahaya lentera.
    - **Pilihan 2 (`terima_kebenaran_pemadam`):** *"Kalau lentera memakan jiwa... kita harus mencari fajar baru tanpa lentera."* -> Membuka jalur Part 2 sebagai **Penempuh Senja** yang mencari cara menyembuhkan Matahari Retak tanpa mengorbankan jiwa Penjaga lagi.
