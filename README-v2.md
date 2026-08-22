# Standardisasi Monitoring Checkmk Agent - Suite Script Kustom

Repositori ini memuat suite script pemantauan kustom (*local checks*) untuk agen **Checkmk** yang dirancang khusus untuk memenuhi kebutuhan standarisasi pemantauan aset infrastruktur IT Anda. Semua skrip dikonfigurasi untuk berjalan secara otomatis dan mengirimkan laporan visual yang seragam ke server Checkmk.

*   **Repositori Resmi**: `andin1st/scriptcmk`
*   **Target Dukungan**: Linux (Ubuntu, Debian, Fedora, RedHat/CentOS) & Windows Host

---

## 🚀 Fast Deployment (Deployment Cepat)

Untuk melakukan instalasi agen Checkmk beserta seluruh suite skrip *local checks* secara otomatis menggunakan repositori `andin1st/scriptcmk`, Anda cukup menjalankan perintah satu baris (*one-liner bootstrap*) berikut di terminal host target:

### **Sistem Linux (Bash)**

```bash
curl -sSfgL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install.sh | bash
```

*Untuk kebutuhan deployment massal (non-interaktif), Anda dapat melewatkan parameter konfigurasi Checkmk Server secara langsung:*
```bash
curl -sSfgL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install.sh | bash -s -- -s 192.168.1.100 -d mysite -v 2.2.0p17
```

### **Sistem Windows (PowerShell)**

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/andin1st/scriptcmk/main/windows/install.ps1'))
```

---

## 📂 Struktur Direktori Repositori

```text
andin1st/scriptcmk/
├── linux/
│   ├── install.sh                  # Skrip instalasi & bootstrap agen otomatis Linux
│   └── local_checks/               # Folder tempat 10 skrip local checks aktif
│       ├── battery_health.sh       # Pemantau kesehatan baterai laptop via UPower
│       ├── cpu_info.sh             # Utilisasi, spesifikasi, clock, dan suhu CPU
│       ├── disk_nvme_health.sh     # Pemantau terpadu NVMe, SATA SSD (Heuristik), & HDD
│       ├── fan_health.sh           # Pemantau kecepatan putaran kipas pendingin (RPM)
│       ├── info_network.sh         # Real-time network throughput, RX/TX rate, & IP info
│       ├── info_OS_office.sh       # Detail distro OS & versi Office terpasang (Timestamped)
│       ├── ram_health.sh           # Log reader uji memori asinkron memtester
│       ├── ram_usage.sh            # Penggunaan RAM fisik aktif (/proc/meminfo)
│       ├── remote_apps.sh          # Pelacak AnyDesk ID & RustDesk ID unik
│       └── storage_usage.sh        # Penggunaan partisi disk fisik aktif (Non-virtual)
├── windows/
│   ├── install.ps1                 # Skrip instalasi otomatis Windows Host
│   └── local_checks/               # Skrip kustom PowerShell untuk Windows
└── README.md                       # Panduan dokumentasi utama
```

---

## 📊 Matriks Standardisasi Threshold (Checkmk)

Sesuai dokumen **Standarisasi Monitoring CheckMK**, berikut adalah batas acuan nilai (*threshold limits*) untuk penentuan kode status layanan (**0 = OK**, **1 = WARNING**, **2 = CRITICAL**):

| Metrik Pemantauan | Batas Aman (OK) | Batas Peringatan (Warning) | Batas Kritis (Critical) |
| :--- | :--- | :--- | :--- |
| **Suhu CPU** | $\le 75^\circ\text{C}$ | $> 85^\circ\text{C}$ | - |
| **FAN Processor** | $> 1600\text{ RPM}$ (atau $0\text{ RPM}$ jika tiada) | $< 1600\text{ RPM}$ | - |
| **Battery Health** | $\ge 60\%$ | $\le 40\%$ | $\le 20\%$ |
| **SSD Health** | $> 90\%$ | $\le 90\%$ | $\le 80\%$ |
| **Storage Usage** | $< 85\%$ | $\ge 85\%$ | $\ge 95\%$ |
| **RAM Usage** | $< 85\%$ | $\ge 85\%$ | $\ge 95\%$ |
| **RAM Health** | Passed | Failed | Failed |

---

## ⚙️ Detail 10 Skrip Local Checks (Linux Host)

Berikut adalah rincian fungsionalitas beserta contoh tampilan keluaran (*output format*) resmi dari masing-masing 10 skrip pemantauan:

### 1. `battery_health.sh`
*   **Deskripsi**: Memantau tingkat kesehatan (*SOH - State of Health*) dan sisa daya baterai perangkat keras laptop secara real-time via UPower D-Bus interface. Dilengkapi sistem deteksi cerdas yang otomatis menghasilkan status aman jika dijalankan pada PC Desktop (tidak memiliki baterai).
*   **Keluaran**:
    ```text
    0 "Battery_Health" - Status : OK ❘ Charge: 95% ❘ Health: 100% ❘ Remaining: 3h 15m
    ```

### 2. `cpu_info.sh`
*   **Deskripsi**: Menyajikan rincian utilitas beban CPU, spesifikasi core/thread, kecepatan clock speed, serta pembacaan suhu sensor fisik (CPUTIN/k10temp) yang dijamin akurat tanpa gangguan bug ACPI thermal zone virtual.
*   **Keluaran**:
    ```text
    0 "CPU_Info" - Spesifikasi : AMD Ryzen 5 5600H | Clock Speed : 3.3Ghz | Core/Thread : 6/12 | CPU Load : 15% | CPU Temperature: 46 Celcius
    ```

### 3. `disk_nvme_health.sh`
*   **Deskripsi**: Solusi monitoring disk terintegrasi. Skrip ini secara dinamis mendeteksi jenis penyimpanan Anda:
    *   **NVMe SSD**: Membaca parameter % usage, suhu, dan total TBW.
    *   **SATA SSD**: Menggunakan **Algoritma Heuristik Mandiri** yang mengonversi LBA ke TBW pada pengontrol non-standar (seperti Apacer CS900 atau V-Gen) sehingga metrik Read/Written tidak bernilai $0\text{ TB}$.
    *   **SATA HDD**: Otomatis mengubah skema pelaporan untuk mendeteksi bad sector (Reallocated/Pending Sectors) dan jam aktif kerja (POH).
*   **Keluaran (SATA SSD)**:
    ```text
    0 "Storage_Health_sda" - Status : OK ❘ Model: CS900 SSD 120GB (111.79 GB) ❘ Status: PASSED ❘ Temp: 26C ❘ Health: 100% ❘ Read: 6.5 TB ❘ Written: 5.4 TB ❘ Write/Day: 108.64 GB ❘ Est. Life: >10 Years
    ```
*   **Keluaran (SATA HDD)**:
    ```text
    0 "Storage_Health_sdb" - Status : OK ❘ Model: ST1000LM035-1RK172 1TB (931.51 GB) ❘ Status: PASSED ❘ Temp: 31C ❘ Disk Type: HDD ❘ Reallocated Sectors: 0 ❘ Pending Sectors: 0 ❘ Power On Hours: 12345 Hrs ❘ Remark: Disk Condition Good
    ```

### 4. `fan_health.sh`
*   **Deskripsi**: Memantau kecepatan kipas pendingin processor utama dalam satuan RPM menggunakan modul kernel `lm-sensors`.
*   **Keluaran**:
    ```text
    0 "FAN_Health" - Status : OK | FAN Speed : 2319rpm | Remark: FAN Condition Good
    ```

### 5. `info_network.sh`
*   **Deskripsi**: Melacak statistik performa jaringan secara real-time. Skrip mengukur volume akumulatif data terunduh/terunggah serta menghitung kecepatan transfer RX/TX Rate sesungguhnya per detik (B/s, KB/s, MB/s) pada setiap kartu jaringan (*interface*) yang sedang aktif.
*   **Keluaran**:
    ```text
    0 "Info_Network_wlo1" in=122554432c|out=3586048c OK - IP Address: 192.168.43.33 | Total Download: 114.14 GB | Total Upload: 3.34 GB | RX Rate : 250.20 KB/s | TX Rate : 123.00 KB/s
    ```

### 6. `info_OS_office.sh`
*   **Deskripsi**: Menyajikan rincian nama sistem operasi distribusi Linux, versi kernel, serta melakukan pendeteksian terintegrasi terhadap seluruh aplikasi office terpasang (LibreOffice, WPS Office, Onlyoffice), baik dari paket lokal, Snap, maupun Flatpak user/system level. Output dilengkapi penanda waktu (*timestamped*) dan terproteksi dari bug output teks error `rpm`.
*   **Keluaran**:
    ```text
    0 "Info_OS" - OK - OS: Fedora Linux 44 (Workstation Edition) | Kernel: 7.1.5-201.fc44.x86_64 | Arch: x86_64 ❘ Checked At: 2026-08-13 07:12:27
    0 "Info_Office" - OK - Product: LibreOffice 26.2.5.2 620(Build:2) + Onlyoffice v7.2.1 | Status: Native Linux Application ❘ Checked At: 2026-08-13 07:12:27
    ```

### 7. `ram_health.sh`
*   **Deskripsi**: Membaca file log lokal hasil pengetesan integritas sel memori RAM fisik asinkron yang dijalankan berkala setiap 2 minggu sekali via Cron Job menggunakan utilitas `memtester`.
*   **Keluaran**:
    ```text
    0 "RAM_Health" - Status: Passed ❘ Diagnostic: Memory Test Completed Successfully ❘ Checked At: 2026-08-11 00:00:00
    ```

### 8. `ram_usage.sh`
*   **Deskripsi**: Memantau kapasitas total, sisa ruang, serta persentase real-time penggunaan memori RAM fisik yang aktif dari sistem `/proc/meminfo`.
*   **Keluaran**:
    ```text
    0 "RAM_Usage" - Status : OK ❘ Used: 45% ❘ Used Space: 3.60 GB ❘ Free: 4.40 GB ❘ Total: 8.00 GB
    ```

### 9. `remote_apps.sh`
*   **Deskripsi**: Memindai file konfigurasi sistem untuk mendapatkan ID unik dari aplikasi bantuan jarak jauh AnyDesk dan RustDesk untuk keperluan pencatatan inventaris dan pengawasan keamanan akses remote.
*   **Keluaran**:
    ```text
    0 "Remote_Apps" - Status : OK ❘ AnyDesk ID: 123456789 ❘ RustDesk ID: 987654321
    ```

### 10. `storage_usage.sh`
*   **Deskripsi**: Memantau kapasitas seluruh partisi penyimpanan fisik yang terpasang (*mounted*) secara aman. Secara cerdas mengecualikan sistem berkas virtual/semu (`tmpfs`, `devtmpfs`, `sysfs`, `proc`, dll) dan kontainer Docker terisolasi agar laporan di Checkmk tetap bersih.
*   **Keluaran**:
    ```text
    0 "Storage_Usage_root" - Status : OK ❘ Partition: / ❘ Used: 42% ❘ Free: 139.20 GB ❘ Total: 240.00 GB
    ```

---

## 🛠️ Aturan Pengembangan & Keamanan Pembatas (Unicode Light Pipe)

Demi menjaga kompatibilitas parser di sisi server Checkmk, semua skrip *local checks* kustom ini wajib mengikuti aturan teknis berikut:
*   Karakter pipa standar (**`|`**) **HANYA** boleh digunakan di kolom data kinerja (*performance data* atau *perfdata*) di bagian awal baris.
*   Seluruh tanda pembatas visual di dalam teks deskripsi status wajib menggunakan karakter *Unicode Light Vertical Bar* (**`❘` - U+2758**) agar parser Checkmk tidak mengalami galat `Invalid data`.
*   Jika skrip tidak mengirimkan data kinerja (*perfdata*), karakter placeholder minus (**`-`**) wajib diletakkan di kolom ketiga sebelum penulisan teks status visual.
