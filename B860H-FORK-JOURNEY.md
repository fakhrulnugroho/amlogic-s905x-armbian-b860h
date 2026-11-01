# Journey Fork OPHUB untuk B860H

Dokumen ini merangkum rencana menjadikan repo ini fork khusus STB ZTE B860H (Amlogic S905X, RAM 2 GB), board `s905x-b860h`, ID 106.

- **Dibuat:** 2026-10-31
- **Status:** fase 0 dan 1 selesai, perubahan fase 2 dan 3 sudah dikerjakan tapi belum dibuild dan belum diuji boot
- **Tujuan akhir:** image server minimal dengan SSH dari repo ini, untuk unit lain dengan hardware sama persis
- **Kebutuhan:** koneksi LAN, tanpa WiFi, dan tanpa backup eMMC atas keputusan pemilik unit
- **Repo:** `fakhrulnugroho/amlogic-s905x-armbian-b860h`
- **Keputusan:** murni fork OPHUB berbasis Armbian, tidak mengikuti upstream, dan tidak membuat sistem baru (`s905x-linux`/BusyBox)
- **Kernel:** tetap memakai `ophub/kernel`. Rencana build kernel sendiri dibatalkan karena terlalu berisiko dan tidak ada kebutuhan yang menuntutnya
- **Yang tetap dipakai:** `rebuild`, `recompile`, Armbian, dan semua skrip pemulihan

Temuan di dokumen ini berasal dari membaca kode, DTB, dan isi kernel 6.12.114 serta 6.18.59. Di hardware, baru boot image fase 1 dari flashdisk yang sudah diuji.

## Peta fase

| Fase | Fokus | Selesai kalau |
|---|---|---|
| 0 | Baseline di unit | Data unit tercatat, image bisa diuji dari SD |
| 1 | Lepas dari upstream | Image dari fork bisa boot dari SD |
| 2 | Hapus data | Build dan boot sama seperti fase 1 |
| 3 | Hapus cabang kode | `bash -n` lolos, build dan boot tetap sama |
| 4 | Tuning di image | Image hasil tuning bisa boot dan dipasang ke eMMC unit uji |

Tiap kelompok perubahan masuk commit terpisah, supaya kegagalan di satu fase mudah dibatalkan. Target hanya unit B860H dengan hardware sama, jadi fase 2 dan 3 berjalan sesuai daftar. Fase 4 boleh dikerjakan sebelum fase 2.

## Fase 0: Baseline di unit

**Tujuan:** mengetahui hardware yang sebenarnya dan memastikan ada jalur pemulihan sebelum mengubah apa pun.

- [x] Catat RAM, versi kernel, model, dan ID chip WiFi.
- [x] Pastikan image bisa dibooting dari SD atau flashdisk tanpa menulis ke eMMC.

Backup eMMC dilewati atas keputusan pemilik unit, jadi unit ini hanya menguji image dari SD.

Hasil dari unit (2026-10-31):

| Item | Hasil | Dampak ke rencana |
|---|---|---|
| Model | `ZTE B860H` | Board `s905x-b860h` sudah benar |
| RAM | 1792 MiB terbaca, swap 0 | Unit 2 GB, dan zram belum aktif |
| Kernel | `6.12.85-ophub` | Tetap di `6.12.y`, karena sudah terbukti jalan |
| WiFi | SDIO `024c:f179` (keluarga RTL8188F/8189FS) | Tidak dibutuhkan, cukup LAN |
| Storage | Root di `mmcblk2`, tanpa SD | Sistem sudah berjalan dari eMMC |
| Partisi | `p1` 511 MiB, `p2` 6,7 GiB | Ukurannya cocok dengan layout 117 MiB, bukan 700 MiB, belum dipastikan |

Layout 117 MiB adalah layout yang di #3558 dilaporkan bermasalah untuk s905x, tapi unit ini sudah stabil lebih dari 6 bulan. Jangan menjalankan `armbian-install` di unit ini, karena tanpa backup sistem dan bootloader yang berjalan tidak bisa dikembalikan.

**Selesai kalau:** data unit tercatat dan image bisa dibooting dari SD.

## Fase 1: Lepas dari upstream

**Tujuan:** build berjalan dari repo sendiri, dan perangkat tidak lagi mengambil skrip dari ophub. Belum ada yang dihapus di fase ini.

- [x] Buat repo sendiri dan jadikan `origin`. Repo harus public.
- [x] Alihkan `script_repo` di `armbian-sync`, `armbian-software`, dan `armbian-kernel`.
- [x] Alihkan URL repo di `armbian-openvfd`, `build_armbian_rootfs_file.sh`, dan `REBUILD_REPOSITORY` di `rebuild`.
- [x] Ganti `uses:` dan path `_actions/ophub/...` di workflow ke repo sendiri.
- [x] Lengkapi `.gitignore` untuk `build-armbian/armbian-files/common-files/usr/lib/firmware` dan `ccache/`.
- [x] Jadikan kernel `6.12.y` sebagai default B860H di `model_database.conf`.
- [x] Commit dan push ke fork, karena workflow memakai kode dari `main` di GitHub.
- [x] Commit dan push perbaikan nama repo.
- [x] Bangun image pertama dengan `build-armbian-arm64-server-image.yml`.
- [x] Uji boot dari flashdisk.

Hasil build dan uji (2026-11-01):

| Item | Hasil |
|---|---|
| Release | `Armbian_trixie_arm64_server_2026.11` |
| Image | `Armbian_26.11.0_amlogic_s905x-b860h_trixie_6.12.114_server_2026.11.01.img.gz` |
| Input workflow | `set_release=trixie`, `armbian_board=s905x-b860h`, `armbian_kernel=6.12.y` |
| Uji di unit | Boot dari flashdisk berhasil, eMMC tidak dipasangi image ini |

Biarkan input `config_board` di `odroidn2`. Input itu nama board di `armbian/build` untuk base image, bukan target perangkat, jadi nilai `b860h` membuat build gagal.

**Selesai kalau:** `sudo ./rebuild -b s905x-b860h -k 6.12.y`, atau workflow di fork, menghasilkan image yang bisa boot dari SD atau flashdisk. Build lokal butuh base image `*-trunk_*.img`.

## Fase 2: Hapus data

**Tujuan:** membuang data perangkat lain tanpa menyentuh logika skrip. Ukuran image praktis tidak berubah, karena manfaatnya ada pada kesederhanaan repo. Daftar di bawah mengasumsikan target hanya unit B860H, dan harus disesuaikan kalau perangkat lain ikut didukung.

- [x] Hapus `platform-files/rockchip` (176 file) dan `platform-files/allwinner` (24 file).
- [x] Hapus isi `different-files/` (84 board, 368 file). Tidak ada folder untuk B860H di sana.
- [x] Di `model_database.conf`, sisakan baris 105 dan 106. Baris 105 memakai DTB P212 dan menjadi cadangan.
- [x] Hapus workflow x86 dan `build-armbian-using-official-image.yml`.
- [x] Pangkas daftar `armbian_board` di dua workflow build yang tersisa. Default-nya sekarang `s905x-b860h`.
- [x] Hapus README `.cn.md` dan `.ja.md`.
- [x] Pertahankan `LICENSE`, `CONTRIBUTORS.md`, header copyright, dokumentasi kernel, dan bagian 12.3 soal pemulihan.
- [ ] Merge ke `main`, push, lalu bangun image. Workflow selalu memakai `rebuild` dari `main`, jadi branch tidak bisa diuji sendiri.
- [ ] Uji boot dari flashdisk.

Penghapusan DTB non-GXL tidak termasuk fase ini, karena kernel mengembalikannya saat build sehingga tidak ada hasilnya.

**Selesai kalau:** build dan boot sama seperti fase 1.

## Fase 3: Hapus cabang kode

**Tujuan:** membuang logika Rockchip dan Allwinner setelah datanya terbukti aman dihapus.

- [x] Buang cabang Rockchip dan Allwinner dari `rebuild`. `PLATFORM` tetap ada sebagai data, karena nama file kernel dan `/boot/dtb/amlogic` bergantung padanya.
- [x] Buang logika board lain dari `start_service.sh`.
- [x] Sederhanakan `armbian-update` dan `armbian-fix`.
- [x] Pangkas `armbian-install` ke cabang s905x, termasuk menu ID 0 (model kustom).
- [x] Cegah layout 117 MiB. Logika ampart dan opsi `-a` dibuang, sedangkan binary `ampart` tetap ada untuk diagnosa eMMC.
- [x] Pangkas daftar u-boot jadi `amlogic_uboot=("p212.bin")`.
- [x] Ubah cek unduhan u-boot supaya mencari file overload, bukan menghitung folder `u-boot/rockchip`.
- [x] Perbarui "Functions list" dan `CLAUDE.md`.
- [ ] Bangun image dan uji boot dari flashdisk.

Isi image berubah di fase ini: `/boot` tidak lagi memuat 5 file `u-boot-*.bin` selain P212, dan `/etc/ophub-release` tidak lagi punya `AMPART_STATUS`. Uji boot jadi lebih penting dibanding fase 2.

**Selesai kalau:** `bash -n` lolos untuk semua skrip, lalu build dan boot tetap sama.

## Fase 4: Tuning di image

**Tujuan:** memasukkan penyesuaian RAM 2 GB dan koneksi LAN ke image, supaya semua perangkat mendapat hasil yang sama.

- [ ] Simpan penyesuaian di `different-files/s905x-b860h/rootfs/`, bukan di box.
- [ ] Sediakan cara pasang untuk unit baru: boot SD, `armbian-install`, dan bootloader HG680P kalau dibutuhkan.
- [ ] Uji `armbian-install` hanya di unit uji yang boleh dihapus isinya. Unit kedua sudah tersedia untuk ini.
- [ ] Pastikan zram aktif dengan `zramctl`. Image Release sudah mengaktifkan `armbian-zram-config` dengan setelan bawaan, jadi overlay hanya perlu berubah kalau nilainya mau diganti.
- [x] Turunkan `commit=600` ke `commit=60` di `rebuild`, `armbian-install`, dan `fstab`. Nilai di `rebuild` yang menentukan isi image, karena `sed` menimpa baris root di `fstab`. Belum diuji boot.
- [x] Perkecil CMA dari 256 MiB ke `cma=64M` di `uEnv.txt` dan `extlinux.conf.bak`, karena box dipakai tanpa HDMI. Belum diuji boot.
- [ ] Ganti ke `BUILD_MINIMAL=yes` di workflow base image, karena targetnya server minimal. Uji terpisah, karena belum teruji dengan `rebuild`.
- [ ] Pastikan paket `armbian-install` ada di image minimal: `parted`, `mkfs.*`, `hexdump`, `fdisk`, dan `lsblk`.
- [x] Mask `wpa_supplicant`, `man-db.timer`, `openvpn`, `rpcbind`, `nfs-client.target`, dan `vnstat` di `rebuild`. Unit tidak memakai VPN maupun NFS. Belum diuji boot.
- [x] Pangkas firmware di `rebuild`: hanya `meson`, `rtl_nic`, dan `regulatory.db*` yang disimpan, dan `ophub/firmware` tidak lagi diunduh. Belum dibuild dan belum diuji boot.

**Selesai kalau:** image hasil tuning bisa boot dari SD, lalu terpasang dan boot dari eMMC unit uji tanpa SD.

## Risiko dan jebakan

| Risiko | Dampak | Penanganan |
|---|---|---|
| eMMC unit harian ditulis ulang tanpa backup | Sistem dan bootloader yang berjalan tidak bisa dikembalikan | Uji dari SD, dan jalankan `armbian-install` hanya di unit uji |
| Bootloader HG680P ditulis ke unit baru | Ada laporan bootloop pada box berlabel 2 GB yang terbaca 1 GiB | Uji di unit yang boleh gagal |
| Unit B860H lain berbeda varian | RAM bisa 1 GB, dan WiFi bisa berbeda | Cek RAM dan model tiap unit sebelum pasang |
| File HG680P tidak ada di `ophub/u-boot` | Kolom `BOOTLOADER_IMG` belum bisa langsung dipakai | Sediakan dan verifikasi file sendiri |
| DTB di repo diubah | Ditimpa kernel saat `rebuild` dan `armbian-update` | Pakai DTB bawaan kernel apa adanya |
| Skrip perangkat masih ke upstream | `armbian-sync` menimpa skrip kustom | Selesaikan fase 1 sebelum image dipakai |
| Modul kernel dinonaktifkan berdasarkan nama | Contohnya `MDIO_BUS_MUX_MESON_GXL` kemungkinan dibutuhkan LAN internal | Nonaktifkan satu per satu dan uji LAN tiap perubahan |
| Ketergantungan pada ophub setelah fase 3 | Build gagal kalau `ophub/kernel`, `ophub/u-boot`, atau image Docker berubah | Pindahkan yang penting ke repo sendiri |

## Jangan dihapus

- `rebuild`, `recompile`, dan `action.yml`
- `compile-kernel/`, termasuk `tools/script/docker/`
- File boot Amlogic: `*_autoscript`, `boot.*`, `u-boot.*`, dan `uEnv.txt`
- `armbian-install`, `armbian-update`, `armbian-ddbr`, dan `armbian-tf`
- `LICENSE`, `CONTRIBUTORS.md`, dan header copyright

## Input yang dibutuhkan sebelum fase 1

- [x] Hasil perintah fase 0: RAM dan ID chip WiFi.
- [x] Nama repo: `fakhrulnugroho/amlogic-s905x-armbian-b860h`.
- [x] WiFi tidak dibutuhkan, cukup LAN.
- [x] Perangkat target: unit lain dengan hardware sama persis.
- [x] Cara uji: boot dari SD atau flashdisk.
- [x] Isi image: server minimal dengan SSH, tanpa paket yang tidak berguna.
