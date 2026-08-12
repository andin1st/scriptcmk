# Blueprint Sistem Pemantauan Aset Terpadu - Checkmk

Dokumen ini berisi spesifikasi teknis, arsitektur, dan panduan operasional lengkap untuk deployment sistem pemantauan aset perusahaan berbasis **Checkmk** secara otomatis (_GitHub Bootstrap_) untuk host Linux dan Windows.

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

## 1. Arsitektur & Deployment Server

Sistem Server Checkmk dijalankan secara mandiri (_self-hosted_) menggunakan Docker dan dikelola melalui Docker Compose untuk kemudahan manajemen dan portabilitas.

### Berkas Konfigurasi: `docker-compose-checkmk.yml`

Server berjalan menggunakan citra (_image_) Checkmk Enterprise/Raw Edition dengan konfigurasi volume persisten untuk menyimpan data situs monitoring secara aman.

```bash
# Cara Menjalankan Server Checkmk
docker compose -f docker-compose-checkmk.yml up -d
```

---

## 2. Strategi Deployment Agen (GitHub Bootstrap)

Pemasangan agen di sisi client dilakukan secara otomatis menggunakan skrip installer satu baris (_one-liner bootstrap_) yang mengunduh seluruh dependensi langsung dari repositori GitHub perusahaan.

### A. Linux Host Installer (`install-v6.sh`)

Skrip ini memiliki kecerdasan **Multi-Distribusi** untuk mendukung berbagai varian sistem operasi Linux:

- **Debian/Ubuntu**: Menggunakan manajer paket `apt-get` dan memasang berkas agen berformat `.deb` (misal: `check-mk-agent_2.5.0p9-1_all.deb`).
- **Fedora/RHEL/CentOS/Rocky**: Mengaktifkan EPEL repository secara aman, menggunakan manajer paket `dnf`/`yum`, dan memasang berkas agen berformat `.rpm` (misal: `check-mk-agent-2.5.0p9-1.noarch.rpm`).

#### Fitur Utama `install-v6.sh`:

1.  **Pemasangan Dependensi**: Menginstal otomatis paket pendukung seperti `smartmontools` (smartctl), `memtester`, `lm-sensors`, dan `upower`.
2.  **Keamanan Eksekusi Pipa (`curl | bash`)**: Menggunakan pengalihan input `/dev/tty` pada perintah `read` interaktif untuk mencegah pemotongan kode (_pipe truncation_) dan error sintaksis `fi`.
3.  **Mode Otomatisasi Penuh (Silent/Non-Interaktif)**: Mendukung argumen CLI untuk deployment massal via SSH:
    ```bash
    curl -sSL https://raw.githubusercontent.com/<username>/<repo>/main/linux/install-v6.sh | sudo bash -s -- -s <IP_SERVER_CHECKMK> -d <SITE_ID> -v 2.5.0p9-1
    ```

### B. Windows Host Installer (`install.ps1`)

Menjalankan perintah PowerShell bypass, memasang agen berformat `.msi` secara senyap (_silent installation_), mengunduh skrip pemantauan PowerShell, dan membuat _Windows Task Scheduler_ untuk pengetesan RAM asinkron.

Buka PowerShell sebagai Administrator pada client Windows dan jalankan:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/<username>/<repo_name>/main/windows/install.ps1'))
```

---

## 3. Spesifikasi Metrik Pemantauan (Local Checks) - Linux

Seluruh skrip diletakkan di bawah direktori `/usr/lib/check_mk_agent/local/` pada client dan dieksekusi oleh Checkmk Agent secara berkala.

### 1. Sistem Operasi (`OS_info.sh`)

- **Fungsi**: Membaca `/etc/os-release` dan menampilkan detail distribusi OS serta versi kernel secara dinamis.
- **Format Output**:
  ```text
  0 "OS_Detail" - OS: Ubuntu 24.04 LTS, Kernel: 6.8.0-40-generic
  ```

### 2. Unit Pemrosesan Sentral (`cpu_info.sh`)

- **Fungsi**: Mengidentifikasi spesifikasi CPU murni (menyaring kata kotor dagang), menghitung kecepatan core maksimal (GHz), rasio core/thread, utilitas CPU real-time via `/proc/stat`, serta suhu real-time.
- **Sensor Suhu Pintar**: Memprioritaskan sensor fisik CPU (`CPUTIN` atau `k10temp`) dan mengabaikan sensor virtual ACPI kosong (yang sering memicu pembacaan salah `16°C`).
- **Format Output**:
  ```text
  0 "CPU_Info" - Spesifikasi : Intel Core i3 13100 | Clock Speed : 3.4Ghz | Core/Thread : 4/8 | CPU Load : 12% | CPU Temperature: 46 Celcius
  ```

### 3. Kesehatan RAM Asinkron (`ram_health.sh`)

- **Fungsi**: Membaca file log `/var/log/checkmk_custom/memtester_health.log` hasil pengujian perangkat lunak `memtester` yang dijalankan otomatis setiap 2 minggu sekali sebesar **20% dari Free RAM** (diatur oleh scheduler `/usr/local/bin/run_memtester.sh`).
- **Format Output**:
  ```text
  0 "RAM_Health" - Status Memory: Ok, tidak ditemukan error saat pengecekan | Sample Pengujian : 2GB | Mon Aug 10 02:00:15 UTC 2026
  ```

### 4. Penggunaan RAM Real-Time (`ram_usage.sh`)

- **Fungsi**: Memantau tingkat penggunaan memori RAM fisik aktif secara real-time berdasarkan `/proc/meminfo` dengan fallback perintah `free`.
- **Ambang Batas**: OK (`< 85%`), Warning (`≥ 85%`), Critical (`≥ 95%`).
- **Format Output**:
  ```text
  0 "RAM_Usage" - Status : OK ❘ Used: 45% ❘ Used Space: 3.60 GB ❘ Free: 4.40 GB ❘ Total: 8.00 GB
  ```

### 5. Penggunaan Penyimpanan Disk (`storage_usage.sh`)

- **Fungsi**: Memantau kapasitas penggunaan ruang penyimpanan di seluruh partisi lokal aktif secara otomatis. Menggunakan penyaringan sistem berkas virtual untuk mengecualikan partisi semu seperti `tmpfs`, `devtmpfs`, `shm`, dll.
- **Ambang Batas**: OK (`< 85%`), Warning (`≥ 85%`), Critical (`≥ 95%`).
- **Format Output**:
  ```text
  0 "Storage_Usage_root" - Status : OK ❘ Partition: / ❘ Used: 42% ❘ Free: 139.20 GB ❘ Total: 240.00 GB
  ```

### 6. Kesehatan Penyimpanan Terpadu (`disk_nvme_health.sh`)

- **Fungsi**: Skrip berbasis Python 3 yang memantau kesehatan SSD NVMe dan SATA secara seragam.
- **Algoritma Heuristik Penulisan (SATA TBW Fix)**: Otomatis mendeteksi jika kontroler SSD (seperti Apacer, V-Gen, Phison, SMI, dll.) menyimpan Atribut ID 241 (`Total_LBAs_Written`) dalam skala **Gigabyte** (GB) langsung, bukan skala sektor standar industri (512B), guna mencegah pembacaan error `0.0 TB`.
- **Estimasi Sisa Umur**: Menghitung sisa usia operasional SSD secara dinamis berdasarkan persentase keausan terhadap waktu aktif (_Power-On Hours_).
- **Format Output**:
  ```text
  0 "Storage_Health_sda" - Status : OK ❘ Model: Apacer AS340 240GB (223.57 GB) ❘ Status: PASSED ❘ Temp: 34C ❘ Health: 100% ❘ Read: 6.5 TB ❘ Written: 5.4 TB ❘ Write/Day: 108.64 GB ❘ Est. Life: >10 Years
  ```

### 7. Kesehatan Baterai (`battery_health.sh`)

- **Fungsi**: Mendeteksi otomatis jenis perangkat keras client (_Laptop vs Desktop_). Membaca status pengisian, kapasitas desain/saat ini, tingkat kesehatan %, dan level baterai menggunakan utilitas `upower` (dengan fallback otomatis ke `/sys/class/power_supply/` jika paket `upower` absen).
- **Format Output Laptop**:
  ```text
  0 "Battery_Health" - Status Battery : Discharging | Design Capacity : 40w/h | Current Capacity : 36w/h | Health : 90% | Battery Level : 95%
  ```
- **Format Output PC/Desktop**:
  ```text
  0 "Battery_Health" - Device is PC/Desktop, there is no battery.
  ```

### 8. Hubungan Suhu & Kipas (`fan_health.sh`)

- **Fungsi**: Mengorelasikan suhu CPU terhadap kecepatan putaran kipas pendingin (_FAN speed RPM_) dari sensor motherboard secara dinamis.
- **Logika Aturan**:
  - **Critical**: Jika suhu `> 85°C` dan kecepatan kipas `< 1600 RPM`.
  - **Warning**: Jika suhu `> 65°C` dan kecepatan kipas `< 1000 RPM`.
  - **OK**: Jika suhu `< 65°C` dengan kecepatan kipas berapa pun (sehat/aman).
- **Format Output**:
  ```text
  0 "FAN_Health" - Status : OK | FAN Speed : 2319rpm | Remark: FAN Condition Good
  ```

### 9. Aplikasi Dukungan Jarak Jauh (`remote_apps.sh`)

- **Fungsi**: Memindai sistem untuk mendeteksi ID aplikasi remote support yang terpasang seperti AnyDesk atau RustDesk untuk mempermudah inventarisasi tim helpdesk.

---

## 4. Parameter Standarisasi Ambang Batas (Sesuai PDF Proyek)

Berikut adalah ringkasan matriks parameter ambang batas keputusan status peringatan (_alert threshold_) yang diimplementasikan di dalam seluruh skrip monitoring:

| Parameter Pemantauan  | Status OK (0)                                                 | Status Warning (1)                                   | Status Critical (2)                                  | Catatan Teknik                  |
| :-------------------- | :------------------------------------------------------------ | :--------------------------------------------------- | :--------------------------------------------------- | :------------------------------ |
| **Suhu CPU**          | $\le 75^\circ\text{C}$                                        | $> 75^\circ\text{C}$ s.d $85^\circ\text{C}$          | $> 85^\circ\text{C}$                                 | Diisolasi dari CPUTIN/k10temp   |
| **Kecepatan Kipas**   | $> 1600\text{ RPM}$ atau $0\text{ RPM}$ (Desktop Tanpa Kipas) | $< 1600\text{ RPM}$ (saat suhu $> 85^\circ\text{C}$) | $< 1600\text{ RPM}$ (saat suhu $> 85^\circ\text{C}$) | Mencegah false-alarm PC fanless |
| **Kesehatan Baterai** | $\ge 60\%$                                                    | $\le 40\%$                                           | $\le 20\%$                                           | Terintegrasi via UPower         |
| **Kesehatan SSD**     | $> 90\%$                                                      | $\le 90\%$                                           | $\le 80\%$                                           | Berdasarkan wearout %           |
| **Sisa Umur SSD**     | $> 1\text{ Tahun}$                                            | $\le 1\text{ Tahun}$                                 | $\le 0.5\text{ Tahun}$                               | Perhitungan linier akumulatif   |
| **Storage Usage**     | $< 85\%$                                                      | $\ge 85\%$                                           | $\ge 95\%$                                           | Menyaring partisi semu/virtual  |
| **RAM Usage**         | $< 85\%$                                                      | $\ge 85\%$                                           | $\ge 95\%$                                           | Berdasarkan MemAvailable riil   |
| **RAM Health (Log)**  | `Passed`                                                      | -                                                    | `Failed`                                             | Hasil pengujian memtester       |

---

_Dokumen ini diperbarui secara berkala mengikuti perkembangan penyesuaian parameter dan dukungan sensor pada infrastruktur aset perusahaan._
