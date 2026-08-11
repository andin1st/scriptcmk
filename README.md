# Blueprint Deployment & Monitoring Checkmk (Community Edition 2.5)

Repositori ini berisi infrastruktur monitoring otomatis menggunakan **Checkmk Community Edition 2.5** di atas **Docker (Ubuntu 26)** dan otomatisasi deployment agen client untuk **Linux (Ubuntu/Debian)** dan **Windows** via GitHub Bootstrap.

---

## 🏗️ Arsitektur Proyek

1. **Server Monitoring (Self-Hosted)**:
   * **OS**: Linux Ubuntu 26
   * **Platform**: Docker & Docker Compose
   * **Image**: `checkmk/check-mk-raw:2.5.0-latest` (Community Edition)
   * **Port Utama**: Web GUI (`8080`), TLS Registration Agent (`8000`)

2. **Client Agen (Deployment Otomatis)**:
   * **Metode**: One-Liner Bootstrap Script (Instalasi 1 baris perintah).
   * **Mekanisme**: Mengunduh installer langsung dari server Checkmk lokal secara aman, menginstal paket agen, memasang semua dependensi lokal, mendaftarkan tugas asinkron, dan menyalin semua script *local checks* dari GitHub.

---

## 📁 Struktur Repositori GitHub

```text
checkmk-agent-deploy/
├── README.md                 # Panduan tim IT (Dokumen ini)
├── .gitignore                # File filter Git untuk keamanan data
├── docker-compose.yml         # Konfigurasi container Checkmk CE 2.5 di Server
├── linux/
│   ├── install-v5.sh         # Script installer otomatis Linux (Input Dinamis)
│   └── local_checks/         # Script pemantauan kustom Linux
│       ├── cpu_os_info.sh     # Detail OS, Spesifikasi CPU & Suhu
│       ├── ram_health.sh      # RAM Health (Membaca hasil memtester)
│       ├── disk_nvme_health.sh# Kesehatan drive SATA HDD & NVMe SSD
│       ├── remote_apps.sh     # Deteksi ID AnyDesk & RustDesk
│       └── battery_health.sh  # Deteksi baterai Laptop vs PC (Baru!)
└── windows/
    ├── install.ps1           # Script installer otomatis Windows (PowerShell)
    └── local_checks/         # Script pemantauan kustom Windows
        ├── os_cpu_health.ps1  # Detail OS, Lisensi Windows & Suhu CPU
        ├── ram_health.ps1     # RAM Health (Membaca log Windows Memory)
        ├── disk_nvme_health.ps1 # Kesehatan Disk & SSD NVMe (Wearout, TBW)
        ├── remote_apps.ps1    # Deteksi ID AnyDesk & RustDesk Windows
        └── ms_office_status.ps1 # Versi & Status Lisensi MS Office (ospp.vbs)
```

---

## 🚀 Panduan Deployment Cepat (Tim IT)

### 1. Sisi Server (Ubuntu 26)
Masuk ke server monitoring Anda, buat direktori, dan jalankan Docker Compose:
```bash
mkdir -p ~/checkmk && cd ~/checkmk
# Buat docker-compose.yml lalu jalankan:
docker compose up -d
```
Akses dashboard di `http://<IP_SERVER_UBUNTU>:8080/monitoring` dengan user `cmkadmin`.

### 2. Sisi Client Linux (Ubuntu/Debian)
Pilih salah satu metode instalasi di bawah ini pada komputer client:

* **Metode A: Interaktif (Dipandu Tanya Jawab)**
  ```bash
  curl -sSL https://raw.githubusercontent.com/<username>/<repo_name>/main/linux/install-v5.sh | sudo bash
  ```
  *Script akan otomatis meminta Anda memasukkan IP Server, Site ID, dan Versi Agen secara interaktif melalui `/dev/tty`.*

* **Metode B: Otomatis (Instan tanpa interaksi - Cocok untuk SSH Massal)**
  ```bash
  curl -sSL https://raw.githubusercontent.com/<username>/<repo_name>/main/linux/install-v5.sh | sudo bash -s -- -s <IP_SERVER> -d <SITE_ID> -v 2.5.0p9-1
  ```

### 3. Sisi Client Windows
Buka PowerShell sebagai Administrator pada client Windows dan jalankan:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/<username>/<repo_name>/main/windows/install.ps1'))
```

---

## 📊 Detail Pembaruan Logika Pemantauan (Penting!)

### A. Kesehatan RAM (`ram_health.sh`) - Sistem Pengujian Asinkron
Guna menghindari beban berat saat polling berkala, pengujian RAM dialihkan secara asinkron menggunakan Cron Job / Task Scheduler yang dijalankan setiap 2 minggu sekali:
* **Runner Script (`run_memtester.sh`)**: Berjalan otomatis, menghitung kapasitas **20% dari Free RAM** saat itu secara dinamis, lalu menulis parameter `SAMPLE_SIZE: <nilai>M` ke dalam `/var/log/checkmk_custom/memtester_health.log` sebelum memicu *memtester*.
* **Local Check (`ram_health.sh`)**: Membaca log tersebut, melakukan parsing besaran sampel (misal mengonversi `2048M` -> `2GB`), lalu melaporkannya ke Checkmk dengan format output presisi:
  ```text
  Status Memory: Ok, tidak ditemukan error saat pengecekan | Sample Pengujian : 2GB | <timestamp>
  ```

### B. Kesehatan Baterai (`battery_health.sh`) - Deteksi Otomatis Laptop vs PC
Script ini sekarang memiliki kecerdasan deteksi hardware (*autodetect*):
* **Jika Laptop**: Membaca sirkuit `/sys/class/power_supply/`, mengonversi mikro-Wh ke Wh, menghitung persentase keausan (*battery health status*), dan mengembalikan data:
  ```text
  Status Battery : Charging/Discharging | Design Capacity : 40w/h | Current Capacity : 20w/h | Health : 50% | Battery Level : 100%
  ```
* **Jika PC/Desktop**: Secara cerdas mendeteksi ketiadaan baterai dan melaporkan status normal:
  ```text
  Device is PC/Desktop, there is no battery.
  ```

---

## 🔧 Pemeliharaan & Modifikasi Script
Jika Anda ingin menambahkan metrik baru atau mengubah fungsionalitas:
1. Simpan script pemantauan baru Anda ke dalam folder `linux/local_checks/` atau `windows/local_checks/`.
2. Buka file installer (`install-v5.sh` atau `install.ps1`), lalu tambahkan nama file script baru tersebut pada variabel **Array** (`SCRIPTS` di Linux atau `$Scripts` di Windows) agar ikut terunduh secara otomatis pada client baru berikutnya.
