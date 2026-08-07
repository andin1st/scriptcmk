# 🚀 Blueprint Proyek Monitoring Checkmk (Self-Hosted & Automated Deployment)

Repositori ini berisi berkas konfigurasi dan script otomatisasi untuk membangun serta mengelola sistem pemantauan aset perusahaan menggunakan **Checkmk Community Edition** [1]. 

Dengan sistem ini, tim IT dapat melakukan deployment agen pemantau ke puluhan hingga ratusan *host* (Linux & Windows) hanya dengan **satu baris perintah** (*one-liner bootstrap*) [1]. Semua konfigurasi, script monitoring (*local checks*), dan dependensi akan terpasang secara otomatis [1].

---

## 🏗️ Arsitektur Sistem

Sistem monitoring ini terbagi menjadi dua komponen utama:

1. **Server Checkmk (Self-Hosted)** [1]:
   * Berjalan di atas sistem operasi **Linux Ubuntu 26** [1].
   * Dikemas menggunakan **Docker & Docker Compose** untuk mempermudah pemeliharaan, manajemen, dan proses pembaruan kontainer [1].

2. **Client Agents (Host)** [1]:
   * Menggunakan agen resmi Checkmk yang terpasang di host Linux (**v2.5 .deb**) dan Windows (**v2.5 .msi**) [1].
   * Pemantauan metrik khusus ditangani oleh **Checkmk Local Checks** (script kustom Bash dan PowerShell) yang diunduh langsung dari repositori GitHub ini [1].

---

## 📁 Struktur Repositori

```text
checkmk-agent-deploy/
├── README.md                   # Panduan dokumentasi ini
├── docker-compose.yml          # Konfigurasi server Checkmk di Ubuntu 26
├── linux/
│   ├── install.sh              # Script bootstrap/installer otomatis untuk Linux
│   └── local_checks/           # Script monitoring khusus host Linux
│       ├── cpu_os_info.sh      # Monitoring OS, detail CPU, dan suhu
│       ├── ram_health.sh       # Pembaca hasil log pengujian RAM
│       ├── disk_nvme_health.sh # Monitoring kesehatan HDD (smartctl) & NVMe (TBW, suhu)
│       └── remote_apps.sh      # Ekstraksi ID AnyDesk & RustDesk
└── windows/
    ├── install.ps1             # Script bootstrap/installer otomatis untuk Windows
    └── local_checks/           # Script monitoring khusus host Windows
        ├── os_cpu_health.ps1   # Monitoring OS, lisensi Windows, utilitas CPU, dan suhu
        ├── ram_health.ps1      # Pembaca hasil log pengujian RAM Windows
        ├── disk_nvme_health.ps1# Monitoring HDD Bad Sectors & NVMe (TBW, % wearout, suhu)
        ├── remote_apps.ps1     # Ekstraksi ID AnyDesk & RustDesk dari Registry/Config
        └── ms_office_status.ps1# Pengecekan versi & partial license Office (ospp.vbs)
```

---

## 🚀 Panduan Deployment ke Host (Client)

Sebelum memulai, pastikan Anda telah memperbarui URL mentah (*raw URL*) repositori GitHub Anda di dalam script installer masing-masing sistem operasi.

### 🐧 1. Deployment pada Client Linux (Ubuntu/Debian)
Buka terminal di komputer client Linux, lalu jalankan perintah berikut:

```bash
curl -sSL https://raw.githubusercontent.com/<username>/<repo-name>/main/linux/install.sh | sudo bash
```

**Proses yang berjalan otomatis di Linux [1]:**
* Memasang utilitas pendukung: `smartmontools`, `memtester`, `lm-sensors`, dan `jq` [1].
* Mengunduh dan menginstal agen Checkmk (`.deb`) secara otomatis [1].
* Memasang semua script pemantau (*local checks*) ke direktori `/usr/lib/check_mk_agent/local/` [1].
* Mendaftarkan **Cron Job** untuk melakukan pengujian RAM secara asinkron setiap 2 minggu sekali [1].

---

### 🪟 2. Deployment pada Client Windows (Windows 10/11 / Server)
Buka **PowerShell sebagai Administrator** di komputer client Windows, lalu jalankan perintah berikut:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/<username>/<repo-name>/main/windows/install.ps1'))
```

**Proses yang berjalan otomatis di Windows [1]:**
* Mengunduh dan menginstal agen Checkmk (`.msi`) secara diam-diam (*silent install*) [1].
* Membuat direktori tujuan local checks di `C:\ProgramData\checkmk\agent\local\` [1].
* Mengunduh semua script monitoring PowerShell dari GitHub [1].
* Mendaftarkan **Windows Task Scheduler** bernama `Checkmk_RAM_Health_Test` untuk menjalankan pengujian RAM asinkron setiap 2 minggu sekali [1].

---

## 📊 Metrik yang Dipantau (Local Checks)

Setiap script kustom akan melaporkan metrik berikut ke server Checkmk Anda [1]:

* **Sistem Operasi**: Menampilkan detail distribusi OS, versi kernel, serta potongan *license product key* khusus untuk Windows [1].
* **CPU**: Menampilkan persentase utilitas saat ini, detail model spesifikasi hardware, serta sensor suhu inti CPU [1].
* **RAM Health (Asinkron)** [1]:
  * *Mengapa asinkron?* Pengujian RAM dengan `memtester` memakan banyak daya CPU dan waktu. Oleh karena itu, pengujian tidak dipicu setiap polling menit agen [1].
  * *Solusi*: Cron/Task Scheduler menjalankan tes setiap 2 minggu sekali dan menulis hasilnya ke file log lokal [1]. Script local check agen hanya akan membaca status dari log statis tersebut untuk dilaporkan ke Checkmk [1].
* **Disk Health (HDD)**: Menampilkan detail disk, ukuran kapasitas, suhu, dan jumlah kerusakan sektor (*bad sectors*) menggunakan `smartctl` [1].
* **NVMe Health**: Menampilkan status kesehatan, persentase keausan (*% usage*), total data yang ditulis (*Total TBW*), total baca/tulis, dan suhu operasi [1].
* **Aplikasi Remote**: Menemukan dan menampilkan ID unik AnyDesk atau RustDesk yang terinstal di komputer client untuk memudahkan tim IT melakukan bantuan jarak jauh [1].
* **MS Office Status (Khusus Windows)**: Menampilkan versi lengkap Microsoft Office beserta potongan lisensi aktif yang diambil melalui script internal Microsoft `ospp.vbs` [1].

---

## 🔧 Pemeliharaan & Kustomisasi Script

Jika Anda ingin melakukan penyesuaian atau perbaikan logika pada script monitoring di kemudian hari:
1. Anda **tidak perlu** mengonfigurasi ulang komputer client satu per satu.
2. Cukup lakukan perubahan pada berkas script yang ada di dalam repositori GitHub ini dan lakukan *commit/push*.
3. Pada komputer client yang sudah aktif, jalankan kembali perintah *one-liner bootstrap* di atas untuk memperbarui script lokal mereka ke versi terbaru secara otomatis.
