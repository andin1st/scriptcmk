# Standardisasi & Panduan Deployment Agen Checkmk

Repositori Utama: **andin1st/scriptcmk**

Dokumen ini adalah panduan teknis resmi bagi Tim IT untuk melakukan instalasi, konfigurasi, dan pemantauan perangkat keras (server, desktop, dan laptop) menggunakan **Checkmk** secara otomatis dan terstandarisasi.

---

## 1. Peta Struktur Repositori (`andin1st/scriptcmk`)

Seluruh berkas installer, konfigurasi, dan skrip _local checks_ disimpan secara terpusat pada repositori GitHub **`andin1st/scriptcmk`** dengan struktur sebagai berikut:

```text
andin1st/scriptcmk/
├── .gitignore
├── README.md                          # Panduan utama ini
├── docker-compose-checkmk.yml         # Konfigurasi container Server Checkmk
└── linux/
    ├── install.sh                     # Skrip bootstrap utama Linux (v6 Multi-Distro)
    └── local_checks/                  # Folder berisi 10 skrip local checks Linux
        ├── battery_health.sh          # Deteksi baterai laptop vs PC (via UPower)
        ├── cpu_info.sh                # Spesifikasi CPU, core/thread, load & suhu real-time
        ├── disk_nvme_health.sh        # Deteksi kesehatan & TBW SSD NVMe & SATA (Python-based)
        ├── fan_health.sh              # Deteksi putaran kipas vs suhu CPU
        ├── OS_info.sh                 # Informasi spesifik distribusi OS & versi Kernel
        ├── ram_health.sh              # Pembaca log pengujian memtester asinkron
        ├── ram_usage.sh               # Informasi kapasitas & persentase RAM terpakai
        ├── remote_apps.sh             # Informasi ID AnyDesk / RustDesk yang aktif
        └── storage_usage.sh           # Pemantau kapasitas partisi disk (non-virtual)
```

---

## 2. Panduan Deployment Cepat (One-Liner Bootstrap)

Proses instalasi Checkmk Agent beserta seluruh skrip _local checks_ di atas telah diotomatisasi penuh. Tim IT cukup menjalankan perintah satu baris (_one-liner_) di bawah ini langsung dari terminal komputer client.

### **A. Instalasi pada Host Linux (Ubuntu, Debian, Fedora, RHEL, CentOS)**

Skrip installer `install.sh` akan mendeteksi varian distribusi OS secara otomatis, mengunduh file paket agen (`.deb` atau `.rpm`), menginstal semua dependensi (`smartmontools`, `memtester`, `lm-sensors`, `upower`), lalu mendaftarkan cron job pengujian RAM otomatis.

#### **Opsi 1: Mode Interaktif (Direkomendasikan untuk mesin tunggal)**

Jalankan perintah berikut, lalu masukkan IP Server Checkmk dan Site ID saat diminta di layar terminal:

```bash
curl -sSfgL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install-v6.sh -o /tmp/install.sh && bash /tmp/install.sh
```

#### **Opsi 2: Mode Instan (Direkomendasikan untuk deployment massal / scripting)**

Jalankan perintah dengan langsung menyuplai parameter IP Server (`-s`), Site ID (`-d`), versi agen (`-v`), dan repositori target (`-g`):

```bash
curl -sSfgL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install-v6.sh | bash -s -- -s 192.168.1.100 -d mysite -v 2.5.0p9-1 -g andin1st/scriptcmk
```

---

## 3. Matriks Parameter & Standardisasi Threshold

Sesuai dengan dokumen **Standarisasi Monitoring CheckMK**, berikut adalah batas ambang kebijakan (_threshold_) keputusan status monitoring yang diterapkan di seluruh mesin:

| No  | Parameter                     | OK (0)                                                 | Warning (1)          | Critical (2) | Sumber Data & Mekanisme                           |
| --- | ----------------------------- | ------------------------------------------------------ | -------------------- | ------------ | ------------------------------------------------- |
| 1   | **Suhu CPU**                  | $\le 75^\circ\text{C}$                                 | $> 85^\circ\text{C}$ | -            | Dibaca dari sensor termal core CPU terdekat       |
| 2   | **Kipas Processor**           | $> 1600\text{ RPM}$ atau $0\text{ RPM}$ (jika fanless) | $< 1600\text{ RPM}$  | -            | Membandingkan kecepatan kipas terhadap suhu       |
| 3   | **Kesehatan Baterai**         | $\ge 60\%$                                             | $\le 40\%$           | $\le 20\%$   | Membaca UPower D-Bus, fallback ke Sysfs           |
| 4   | **Kesehatan SSD (SATA/NVMe)** | $> 90\%$                                               | $\le 90\%$           | $\le 80\%$   | Membaca persentase keausan (_wearout rate_) SMART |
| 5   | **Storage Usage**             | $< 85\%$                                               | $\ge 85\%$           | $\ge 95\%$   | Kapasitas terpakai pada semua partisi riil        |
| 6   | **RAM Usage**                 | $< 85\%$                                               | $\ge 85\%$           | $\ge 95\%$   | Persentase RAM terpakai via `/proc/meminfo`       |
| 7   | **RAM Health**                | Passed                                                 | Failed               | Failed       | Pengujian asinkron `memtester` tiap 2 minggu      |

---

## 4. Rincian 10 Skrip Local Checks Linux

Setiap skrip diletakkan di direktori `/usr/lib/check_mk_agent/local/` dan menghasilkan keluaran terstandarisasi dengan pemisah tanda **Unicode Light Vertical Bar (`❘`)** agar aman dari kesalahan pemotongan parser Checkmk:

### 1. `battery_health.sh`

- **Fungsi**: Mendeteksi secara dinamis apakah perangkat menggunakan baterai (Laptop) atau catu daya langsung (PC/Desktop).
- **Mekanisme**: Membaca sensor dari UPower (D-Bus), dengan fallback ke `/sys/class/power_supply/`.
- **Keluaran Laptop**:
  `0 "Battery Health" - Status Battery : Discharging ❘ Design Capacity : 40w/h ❘ Current Capacity : 20w/h ❘ Health : 50% ❘ Battery Level : 100%`
- **Keluaran PC/Desktop**:
  `0 "Battery Health" - Device is PC/Desktop, there is no battery.`

### 2. `cpu_info.sh`

- **Fungsi**: Membaca spesifikasi teknis CPU murni tanpa noise dagang, mengukur clock speed, core/thread, utilisasi, serta suhu CPU secara real-time.
- **Keluaran**:
  `0 "CPU Info" - Spesifikasi : Intel Core i3 13100 ❘ Clock Speed : 3.4Ghz ❘ Core/Thread : 4/8 ❘ CPU Load : 12% ❘ CPU Temperature: 48 Celcius`

### 3. `disk_nvme_health.sh`

- **Fungsi**: Skrip Python terpadu untuk SSD NVMe & SATA. Menghitung Total Bytes Written (TBW) SSD SATA menggunakan algoritma konversi sektor LBA ke Terabyte desimal, serta dilengkapi pendeteksian heuristik untuk brand controller (Apacer, V-Gen, Kingmax, dll).
- **Keluaran**:
  `0 "SSD Health sda" - Status : OK ❘ Model: Apacer AS340 240GB (223.57 GB) ❘ Status: PASSED ❘ Temp: 35C ❘ Health: 100% ❘ Read: 6.5 TB ❘ Written: 5.4 TB ❘ Write/Day: 108.64 GB ❘ Est. Life: >10 Years`

### 4. `fan_health.sh`

- **Fungsi**: Membandingkan kecepatan kipas (RPM) dan suhu CPU secara dinamis.
- **Aturan**: Status Critical (2) jika suhu $> 85^\circ\text{C}$ dan kipas $< 1600\text{ RPM}$. Status Warning (1) jika suhu $> 65^\circ\text{C}$ dan kipas $< 1000\text{ RPM}$.
- **Keluaran**:
  `0 "FAN Health" - Status : OK ❘ FAN Speed : 2319rpm ❘ Remark: FAN Condition Good`

### 5. `OS_info.sh`

- **Fungsi**: Melacak distribusi Linux yang terpasang secara dinamis beserta detail versi kernel yang sedang berjalan.
- **Keluaran**:
  `0 "OS Detail" - OS: Ubuntu 24.04 LTS, Kernel: 6.8.0-40-generic`

### 6. `ram_health.sh`

- **Fungsi**: Membaca file log `/var/log/checkmk_custom/memtester_health.log` hasil uji RAM asinkron 20% Free RAM yang dijalankan scheduler `run_memtester.sh`.
- **Keluaran**:
  `0 "RAM Health" - Status Memory: Ok, tidak ditemukan error saat pengecekan ❘ Sample Pengujian : 2GB ❘ Mon Aug 10 02:00:15 UTC 2026`

### 7. `ram_usage.sh`

- **Fungsi**: Memantau kapasitas penggunaan RAM fisik secara presisi (Used, Used Space, Free, dan Total).
- **Keluaran**:
  `0 "RAM Usage" - Status : OK ❘ Used: 45% ❘ Used Space: 3.60 GB ❘ Free: 4.40 GB ❘ Total: 8.00 GB`

### 8. `remote_apps.sh`

- **Fungsi**: Membaca file konfigurasi AnyDesk atau RustDesk untuk memunculkan ID remote support perangkat secara instan di dashboard Checkmk.
- **Keluaran**:
  `0 "Remote Support" - AnyDesk ID: 123456789 ❘ RustDesk ID: 987654321`

### 9. `storage_usage.sh`

- **Fungsi**: Memantau kapasitas partisi fisik lokal yang terpasang di sistem dan otomatis mengabaikan file system virtual.
- **Keluaran**:
  `0 "Storage Usage root" - Status : OK ❘ Partition: / ❘ Used: 42% ❘ Free: 139.20 GB ❘ Total: 240.00 GB`

---

## 5. Rencana & Langkah Pengembangan Selanjutnya

1.  **Standardisasi Host Windows**: Menyinkronkan fungsionalitas monitoring penyimpanan (`volume_usage.ps1`) dan RAM (`ram_usage.ps1`) pada Windows menggunakan kerangka kerja PowerShell yang serupa.
2.  **Pemolesan Otomasi Deployment MSI Windows**: Menyelaraskan argumen parameter instalasi silent MSI pada Windows Host agar setara dengan keandalan skrip `install.sh` Linux.
