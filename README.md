# Standardisasi Monitoring Checkmk (andin1st/scriptcmk)

Proyek ini bertujuan untuk membangun sistem monitoring aset perusahaan menggunakan **Checkmk** secara terpusat, otomatis, dan seragam. Semua berkas konfigurasi, skrip instalasi (*installer*), dan skrip pemantauan (*local checks*) dikelola secara terpusat melalui repositori GitHub resmi: **`andin1st/scriptcmk`**.

---

## 📂 Struktur Repositori GitHub

```text
andin1st/scriptcmk/
├── .gitignore
├── README.md
├── linux/
│   ├── install.sh                  # Skrip Bootstrap Installer Linux (Multi-Distro)
│   └── local_checks/               # 10 Skrip Pemantauan Lokal Linux (Local Checks)
│       ├── battery_health.sh       # Deteksi Baterai (Laptop via UPower vs PC Desktop)
│       ├── cpu_info.sh             # Metrik CPU (Model, Speed, Cores, Load, Temp)
│       ├── cpu_os_info.sh          # Informasi Sistem & CPU Gabungan (Legacy)
│       ├── disk_nvme_health.sh     # Pemantau Kesehatan Disk (SATA HDD, SATA SSD, NVMe)
│       ├── fan_health.sh           # Pemantau Kipas (RPM vs Suhu CPU)
│       ├── OS_info.sh              # Informasi Distribusi OS & Versi Kernel
│       ├── ram_health.sh           # Log Reader Pengujian RAM asinkron (memtester)
│       ├── ram_usage.sh            # Penggunaan RAM fisik real-time (Used, Free, Total)
│       ├── remote_apps.sh          # Deteksi ID Aplikasi Remote (AnyDesk & RustDesk)
│       └── storage_usage.sh        # Penggunaan Kapasitas Partisi Penyimpanan Lokal
└── windows/
    ├── install.ps1                 # Skrip Bootstrap Installer Windows PowerShell
    └── local_checks/               # Skrip Pemantauan Lokal Windows
        ├── battery_health.ps1
        ├── cpu_info.ps1
        ├── disk_health.ps1
        ├── ram_health.ps1
        ├── remote_apps.ps1
        └── volume_usage.ps1
```

---

## 🚀 Panduan Deployment Cepat (One-Liner Bootstrap)

Deployment ke komputer client menggunakan perintah satu baris (*one-liner*) untuk mengotomatisasi seluruh proses: pemasangan paket agen Checkmk, penyiapan dependensi, pengunduhan 10 skrip *local checks*, pengaturan Task Scheduler/Cron Job, hingga registrasi agen ke server.

### **1. Platform Linux (Debian, Ubuntu, Fedora, RHEL, Rocky, Alma)**

#### **A. Mode Interaktif (Manual & Interaktif)**
Perintah ini akan menanyakan IP Server, Site ID, dan versi agen secara interaktif:
```bash
curl -sSfgL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install.sh | bash
```

#### **B. Mode Instan / Silent (Sangat cocok untuk deployment massal)**
Gunakan parameter CLI untuk instalasi otomatis tanpa interaksi keyboard:
```bash
curl -sSfgL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install.sh | bash -s -- \
  -s 192.168.1.100 \
  -d mysite \
  -v 2.5.0p14-1 \
  -g andin1st/scriptcmk
```
*   `-s` : IP Address / Domain Server Checkmk.
*   `-d` : Site ID Checkmk Anda.
*   `-v` : Versi Agen Checkmk yang ingin dipasang (contoh: `2.5.0p14-1`). Skrip otomatis menyesuaikan format paket (`.deb` untuk Debian/Ubuntu, `.rpm` untuk Fedora/RHEL).
*   `-g` : Target repositori GitHub kustom (Default: `andin1st/scriptcmk`).

---

### **2. Platform Windows**

Jalankan perintah ini melalui **PowerShell (Administrator)**:

#### **A. Mode Interaktif (3 Inputan Ringkas)**
Perintah ini secara otomatis menanyakan alamat server + port, Site ID, dan versi agen secara interaktif:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/andin1st/scriptcmk/main/windows/install.ps1'))
```
*   **1. Alamat Server**: IP dan Port Web GUI (contoh: `192.168.43.188:8080`).
*   **2. Site ID**: Site ID Checkmk (Default: `cmk`).
*   **3. Versi Agen**: Versi paket agen Checkmk (Default: `2.5.0p14-1`).

#### **B. Mode Non-Interaktif / Fast CLI Arguments**
Gunakan argumen baris perintah untuk pendeployan otomatis tanpa interaksi pengguna:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex "& { $(New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/andin1st/scriptcmk/main/windows/install.ps1') } -s 192.168.43.188:8080 -d cmk -v 2.5.0p14-1"
```
*   `-s` : IP Address dan Port Web GUI Server Checkmk (contoh: `192.168.43.188:8080`).
*   `-d` : Site ID Checkmk (Default: `cmk`).
*   `-v` : Versi Agen Checkmk (Default: `2.5.0p14-1`).

---

## 🔒 Pendaftaran Sertifikat Keamanan Agen (mTLS Registration)

Setelah instalasi agen selesai, lakukan pendaftaran sertifikat digital satu kali (*one-time mTLS registration*) agar komunikasi agen ke server terenkripsi via port TLS `8000`.

### **A. Client Linux**
```bash
sudo cmk-agent-ctl register \
  --hostname <NAMA_HOST_CLIENT> \
  --server <IP_SERVER_CHECKMK>:8000 \
  --site <SITE_ID> \
  --user cmkadmin
```

### **B. Client Windows (PowerShell Administrator)**
```powershell
$ctlPath = "C:\Program Files (x86)\checkmk\service\cmk-agent-ctl.exe"
if (-not (Test-Path $ctlPath)) {
    $ctlPath = "C:\Program Files\checkmk\service\cmk-agent-ctl.exe"
}

& "$ctlPath" register `
  --hostname <NAMA_HOST_CLIENT> `
  --server <IP_SERVER_CHECKMK>:8000 `
  --site <SITE_ID> `
  --user cmkadmin
```

---

## 📊 Detail 10 Skrip Pemantauan Lokal (Linux)

Seluruh output local check menggunakan placeholder data kinerja (`-`) serta pembatas visual Unicode Light Vertical Bar (**`❘`**) untuk menjamin keakuratan parsing data Checkmk dan menghindari kegagalan status (*Invalid data*).

### **1. `OS_info.sh`**
Mendeteksi distribusi OS dan kernel yang digunakan host secara dinamis.
*   **Format Output**:
    `0 "OS_Detail" - OS: Ubuntu 24.04 LTS, Kernel: 6.8.0-40-generic`

### **2. `cpu_info.sh`**
Menampilkan informasi CPU yang bersih (bebas simbol dagang kotor) serta performa load real-time dan sensor temperatur hardware.
*   **Format Output**:
    `0 "CPU_Info" - Spesifikasi : Intel Core i3 13100 | Clock Speed : 3.4Ghz | Core/Thread : 4/8 | CPU Load : 12% | CPU Temperature: 48 Celcius`

### **3. `cpu_os_info.sh`**
Skrip gabungan warisan (*legacy script*) untuk menyajikan ringkasan cepat info OS dan CPU dalam satu baris layanan.

### **4. `disk_nvme_health.sh`**
Skrip pemantauan penyimpanan terpadu berbasis Python 3 yang memiliki kecerdasan buatan lokal untuk mendeteksi jenis disk secara otomatis:
*   **Mode SSD (NVMe & SATA SSD)**: Menggunakan **Algoritma Heuristik Mandiri (*Self-Calibrating Heuristic*)**. Skrip ini secara dinamis mengidentifikasi apakah vendor SSD (seperti PNY CS900, Apacer AS340, V-Gen) mencatat nilai SMART ID 241/242 dalam skala **GB** atau **Sektor (512B)**. Ini memperbaiki *bug* di mana TBW terbaca `0.0 TB` pada SSD non-Samsung.
*   **Mode HDD (SATA Harddisk)**: Otomatis menyesuaikan template laporan ke metrik mekanis vital, yaitu: **Sektor Rusak yang Direalokasi (Reallocated Sectors)**, **Sektor Menunggu Remap (Pending Sectors)**, dan total waktu aktif piringan dalam satuan Jam (*Power On Hours*).
*   **Format Output (SATA SSD - Apacer CS900)**:
    `0 "Storage_Health_sda" - Status : OK ❘ Model: CS900 SSD 120GB (111.79 GB) ❘ Status: PASSED ❘ Temp: 26C ❘ Health: 100% ❘ Read: 4.8 TB ❘ Written: 5.2 TB ❘ Write/Day: 35.50 GB ❘ Est. Life: >10 Years`
*   **Format Output (SATA HDD - ST1000)**:
    `0 "Storage_Health_sdb" - Status : OK ❘ Model: ST1000LM035-1RK172 1TB (931.51 GB) ❘ Status: PASSED ❘ Temp: 31C ❘ Disk Type: HDD ❘ Reallocated Sectors: 0 ❘ Pending Sectors: 0 ❘ Power On Hours: 12345 Hrs ❘ Remark: Disk Condition Good`

### **5. `fan_health.sh`**
Memantau kecepatan kipas pendingin (*fan speed*) dengan membandingkannya terhadap suhu CPU saat ini untuk mendeteksi indikasi kegagalan pendinginan.
*   **Kriteria Keputusan**:
    *   **CRITICAL**: Suhu CPU `> 85°C` dan Kipas `< 1600 RPM`.
    *   **WARNING**: Suhu CPU `> 65°C` dan Kipas `< 1000 RPM`.
    *   **OK**: Suhu CPU `< 65°C` dengan kecepatan kipas berapa pun.
*   **Format Output**:
    `0 "FAN_Health" - Status : OK | FAN Speed : 2319rpm | Remark: FAN Condition Good`

### **6. `battery_health.sh`**
Deteksi tipe perangkat keras secara otomatis. Memanfaatkan subsistem D-Bus **UPower** yang sangat akurat untuk laptop (mengatasi perbedaan label `BAT0`/`BAT1`) dan memiliki sistem *fallback* aman ke *sysfs*, serta otomatis memberikan status OK tanpa alarm palsu pada PC/Desktop.
*   **Format Output (Laptop)**:
    `0 "Battery_Health" - Status Battery : Discharging | Design Capacity : 40w/h | Current Capacity : 20w/h | Health: 50% | Battery Level : 100%`
*   **Format Output (PC/Desktop)**:
    `0 "Battery_Health" - Device is PC/Desktop, there is no battery.`

### **7. `ram_health.sh`**
Membaca file log hasil pengujian RAM asinkron (`/var/log/checkmk_custom/memtester_health.log`) yang dijalankan otomatis setiap Sabtu pukul 11:00 AM via Cron Job / Scheduled Task dengan kapasitas dinamis **20% dari Free RAM**.
*   **Format Output**:
    `0 "RAM_Health" - Status Memory: Ok, tidak ditemukan error saat pengecekan | Sample Pengujian : 2.5GB | Mon Aug 10 02:00:15 UTC 2026`

### **8. `ram_usage.sh`**
Memantau persentase penggunaan memori fisik (RAM) real-time berdasarkan pencatatan akurat di `/proc/meminfo`.
*   **Format Output**:
    `0 "RAM_Usage" - Status : OK ❘ Used: 45% ❘ Used Space: 3.60 GB ❘ Free: 4.40 GB ❘ Total: 8.00 GB`

### **9. `remote_apps.sh`**
Mengidentifikasi keberadaan dan mendeteksi ID unik dari aplikasi remote desktop yang terpasang di client (AnyDesk & RustDesk via `rustdesk.exe --get-id`) untuk mempercepat proses bantuan teknis oleh tim IT.
*   **Format Output**:
    `0 "Remote_Support" - AnyDesk ID: 123456789 ❘ RustDesk ID: 987654321`

### **10. `storage_usage.sh`**
Memantau persentase kapasitas partisi penyimpanan fisik yang terpasang (*mounted*). Skrip secara cerdas mengabaikan partisi virtual/sistem (`tmpfs`, `devtmpfs`, `proc`, dll.) serta mengisolasi jalur kontainer Docker agar visualisasi dashboard tetap bersih.
*   **Format Output**:
    `0 "Storage_Usage_root" - Status : OK ❘ Partition: / ❘ Used: 42% ❘ Free: 139.20 GB ❘ Total: 240.00 GB`

---

## 📋 Matriks Standardisasi Batas Parameter (Threshold)

Berikut adalah tabel acuan ambang batas parameter untuk penentuan status kesehatan aset pada dashboard Checkmk perusahaan sesuai dokumen standarisasi:

| Parameter Monitoring | OK (Status: 0) | WARNING (Status: 1) | CRITICAL (Status: 2) | Keterangan / Sumber Data |
| :--- | :--- | :--- | :--- | :--- |
| **Suhu CPU** | `≤ 75°C` | `> 75°C` s.d `≤ 85°C` | `> 85°C` | Sensor ACPI / CPUTIN / Coretemp |
| **Kipas (FAN) CPU** | `> 1600 RPM` atau `0 RPM` (Jika Fanless/PC) | `< 1600 RPM` (Saat suhu tinggi) | `< 1600 RPM` (Suhu `> 85°C`) | sensors (lm-sensors) |
| **Kesehatan Baterai** | `≥ 60%` | `40% - 59%` | `≤ 20%` | UPower / sysfs power_supply |
| **Kesehatan SSD (SATA/NVMe)**| `> 90%` | `81% - 90%` | `≤ 80%` | Remaining Life / Percentage Used |
| **Kesehatan HDD (SATA)** | Bad Sector = 0 | Reallocated Sector `> 0` atau Pending `> 0` | SMART `FAILED` / Reallocated `≥ 50` | Reallocated & Pending Sector Count |
| **RAM Usage** | `< 85%` | `≥ 85%` s.d `< 95%` | `≥ 95%` | `/proc/meminfo` |
| **RAM Health** | Passed | - | Failed | Hasil uji dinamis 20% Free RAM |
| **Storage Usage** | `< 85%` | `≥ 85%` s.d `< 95%` | `≥ 95%` | Perintah `df -P` |
| **Aplikasi Remote** | Terdeteksi ID | - | Aplikasi tidak terpasang | Pembacaan CLI / konfigurasi lokal |
| **Lisensi OS / Office** | Aktif / Terlisensi | Akan kedaluwarsa | Tidak Aktif / Trial | `slmgr.vbs` & `ospp.vbs` |

---
*Dokumen ini diperbarui secara berkala mengikuti pengembangan standardisasi infrastruktur monitoring IT.*
