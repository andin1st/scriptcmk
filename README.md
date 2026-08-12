# Panduan Deployment Agen Checkmk Otomatis (GitHub Bootstrap)

Repositon ini berisi skrip otomatisasi untuk memasang, mengonfigurasi, dan memperbarui agen pemantauan **Checkmk 2.5 (Community Edition)** beserta skrip pemantau kustom (_local checks_) pada sistem operasi **Linux (Debian/Ubuntu & Fedora/RHEL)** dan **Windows Client**.

---

## Arsitektur & Alur Kerja

1. **GitHub sebagai Pusat Kode**: Semua installer bootstrap dan skrip _local checks_ kustom disimpan di repositori Git.
2. **Bootstrap Satu Baris (One-Liner)**: Tim IT mengeksekusi satu baris perintah di komputer client. Skrip akan mendeteksi tipe OS, menginstal paket dependensi, mengunduh installer agen Checkmk langsung dari server lokal Anda, mendaftarkan penjadwal tes RAM, dan menarik skrip pemantau dari GitHub.
3. **Pemantauan Asinkron**: Tugas berat seperti pengujian perangkat keras RAM (`memtester`) dijadwalkan berjalan secara asinkron setiap 2 minggu sekali agar tidak mengganggu performa kerja harian pengguna.

---

## Struktur Direktori Repositori

```text
├── .gitignore
├── README.md
├── linux/
│   ├── install-v6.sh           # Skrip Installer Otomatis Linux (Debian & RPM)
│   └── local_checks/
│       ├── cpu_os_info.sh      # Metrik OS, Detail CPU, & Suhu
│       ├── ram_health.sh       # Pembaca Log Tes RAM Memtester (Asinkron)
│       ├── disk_nvme_health.sh # Analisis Kesehatan Storage HDD & NVMe (smartctl)
│       ├── remote_apps.sh      # Detektor ID AnyDesk & RustDesk
│       └── battery_health.sh   # Detektor Baterai Akurat (UPower dengan fallback Sysfs)
└── windows/
    ├── install.ps1             # Skrip Installer Otomatis Windows (PowerShell)
    └── local_checks/
        ├── os_cpu_health.ps1
        ├── ram_health.ps1
        ├── disk_nvme_health.ps1
        ├── remote_apps.ps1
        └── ms_office_status.ps1
```

---

## Panduan Deployment Client

### 1. Client Linux (Debian/Ubuntu & Fedora/RHEL/Rocky/Alma)

Skrip installer **`install-v6.sh`** secara otomatis mendeteksi distribusi Linux Anda, menginstal manajer paket yang cocok (`apt-get` atau `dnf`/`yum`), menginstal dependensi (termasuk `upower` untuk pelacakan baterai presisi), dan mengunduh format agen yang sesuai (`.deb` atau `.rpm`).

#### **Opsi A: Jalankan Secara Interaktif (Sangat Ramah Pengguna)**

Jalankan perintah ini di terminal client, skrip akan meminta input IP Server, Site ID, dan Versi Agen secara aman langsung dari keyboard (`/dev/tty`):

```bash
curl -sSL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install-v6.sh | sudo bash
```

#### **Opsi B: Jalankan Secara Instan (Sangat Cocok untuk Massal / SSH)**

Gunakan parameter CLI untuk mengotomatiskan seluruh alur tanpa interaksi layar sama sekali:

```bash
curl -sSL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install-v6.sh | sudo bash -s -- -s <IP_SERVER_CHECKMK> -d <SITE_ID> -v 2.5.0p9-1
```

_Argumen yang Tersedia:_

- `-s, --server`: IP atau Hostname server Checkmk (Wajib pada mode instan).
- `-d, --site`: Site ID instansi Checkmk (Default: `cmk`).
- `-v, --version`: Versi spesifik agen Checkmk di server Anda (Default: `2.5.0p9-1`).
- `-g, --github`: Nama repositori kustom Anda (Format: `andin1st/scriptcmk`).

---

### 2. Client Windows

Eksekusi perintah berikut di dalam terminal **PowerShell (Run as Administrator)**:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/andin1st/scriptcmk/main/windows/install.ps1'))
```

---

## Logika Pemantauan Khas (Highlight)

- **Deteksi Kesehatan Baterai (`battery_health.sh`)**: Menggunakan `upower` sebagai pembaca data D-Bus baterai utama yang sangat akurat. Jika dijalankan di server CLI minimal / PC Desktop biasa, skrip otomatis melakukan deteksi dan _fallback_ tanpa memicu error.
- **Pengujian RAM Asinkron (`ram_health.sh`)**: Berjalan dua minggu sekali via Cron/Task Scheduler, mengalokasikan **20% dari Free RAM** (`SAMPLE_SIZE`) untuk diuji kesehatannya, lalu menulis log statis agar bisa dibaca kapan saja oleh agen Checkmk secara instan.
