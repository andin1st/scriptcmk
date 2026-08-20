# Checkmk Client Monitoring Agent Script Suite

Sistem pemantauan agen kustom Checkmk berbasis skrip otomatis untuk melakukan pengawasan terstandarisasi pada seluruh host client Linux dan Windows. Seluruh konfigurasi dan skrip monitoring ini dikelola secara terpusat pada repositori GitHub resmi **`andin1st/scriptcmk`**.

---

## 📂 Struktur Repositori GitHub (`andin1st/scriptcmk`)

```text
andin1st/scriptcmk/
├── .gitignore
├── README.md
├── linux/
│   ├── install.sh                       # Skrip installer otomatis Linux Host (v6)
│   └── local_checks/
│       ├── battery_health.sh            # 1. Monitoring kesehatan baterai laptop (Setiap 16:00)
│       ├── cpu_info.sh                  # 2. Detail spesifikasi, clock, load & suhu CPU (Real-time)
│       ├── disk_nvme_health.sh          # 3. Kesehatan SSD NVMe/SATA & HDD (Setiap 16:00)
│       ├── fan_health.sh                # 4. Monitoring kec. kipas vs suhu CPU (Real-time)
│       ├── info_network.sh              # 5. Real-time network throughput & IP info (Real-time)
│       ├── info_OS_office.sh            # 6. Detail OS & Aplikasi Office Terpasang (Setiap 16:00)
│       ├── ram_health.sh                # 7. Log reader pengujian RAM memtester (Setiap Sabtu 11:00)
│       ├── ram_usage.sh                 # 8. Kapasitas & persentase penggunaan RAM (Real-time)
│       ├── remote_apps.sh               # 9. Deteksi ID Remote AnyDesk & RustDesk (Setiap 16:00)
│       └── storage_usage.sh             # 10. Kapasitas partisi penyimpanan aktif (Setiap 16:00)
└── windows/
    ├── install.ps1                      # Skrip installer otomatis Windows Host
    └── local_checks/
        ├── battery_health.ps1
        ├── cpu_info.ps1
        ├── disk_health.ps1
        ├── OS_info.ps1
        ├── ram_health.ps1
        ├── ram_usage.ps1
        ├── remote_apps.ps1
        └── volume_usage.ps1
```

---

## 🚀 Panduan Deployment Cepat (Fast Deployment)

### **A. Linux Host (Ubuntu, Debian, Fedora, RHEL, dll.)**

Gunakan skrip bootstrap satu baris (*one-liner*) berikut untuk melakukan pemasangan otomatis agen Checkmk, konfigurasi dependensi, dan sinkronisasi seluruh skrip *local checks*.

#### **1. Mode Interaktif (Manual)**
```bash
curl -sSfgL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install.sh | sudo bash
```

#### **2. Mode Instan Skala Massal (Non-Interaktif)**
Sangat ideal digunakan bersama Ansible, Puppet, SSH Loop, atau skrip otomatisasi deployment Anda:
```bash
curl -sSfgL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install.sh | sudo bash -s -- \
  -s 192.168.1.100 \
  -d mysite \
  -v 2.5.0p9 \
  -g andin1st/scriptcmk
```

**Detail Parameter CLI:**
*   `-s` : IP Address atau Domain Server Checkmk (Contoh: `192.168.1.100`).
*   `-d` : Nama Instansi / Site ID Checkmk Server (Contoh: `mysite`).
*   `-v` : Versi Agen Checkmk yang ingin dipasang (Contoh: `2.5.0p9`).
*   `-g` : Target repositori GitHub kustom Anda (Default: `andin1st/scriptcmk`).

---

## 📋 Detail 10 Skrip Monitoring Linux (`linux/local_checks/`)

Seluruh skrip monitoring menggunakan standar pemisahan visual **Unicode Light Vertical Bar (`❘` - U+2758)** agar laporan visual tampil sangat rapi di dashboard Checkmk dan kebal terhadap kegagalan *parsing* data kinerja (*performance data*).

Metrik yang bersifat **Real-time** akan diperbarui secara instan pada setiap interval penarikan data agen. Sementara metrik **Terjadwal (Non-Realtime)** menggunakan **Scheduled Self-Caching** untuk mengurangi beban kerja CPU klien dan server dengan diperbarui setiap hari pada pukul **16:00** (atau hari **Sabtu pukul 11:00** khusus untuk kesehatan RAM).

### **1. battery_health.sh (Terjadwal - 16:00)**
*   **Fungsi**: Mendeteksi kesehatan baterai menggunakan subsistem `UPower` D-Bus. Jika dipasang pada PC Desktop, skrip secara cerdas melaporkan kondisi normal tanpa baterai.
*   **Standardisasi Threshold**:
    *   **OK (0)**: Kesehatan \(\ge 60\%\)
    *   **Warning (1)**: Kesehatan \(\le 40\%\)
    *   **Critical (2)**: Kesehatan \(\le 20\%\)
*   **Format Output**:
    ```text
    0 "Battery_Health" - Status : OK ❘ Health: 94% ❘ Cycle: 45 ❘ State: fully-charged
    ```

### **2. cpu_info.sh (Real-time)**
*   **Fungsi**: Menampilkan detail spesifikasi prosesor real-time yang bersih dari logo dagang (`(R)`, `(TM)`, dll.), clock speed dinamis dalam GHz, rasio Core/Thread fisik, beban utilitas, serta sensor suhu hardware terarah (`CPUTIN`/`k10temp`).
*   **Standardisasi Threshold**:
    *   **OK (0)**: Suhu CPU \(\le 75^\circ\text{C}\)
    *   **Warning (1)**: Suhu CPU \(> 75^\circ\text{C}\)
    *   **Critical (2)**: Suhu CPU \(> 85^\circ\text{C}\) (Status kritis dipicu jika kipas bermasalah)
*   **Format Output**:
    ```text
    0 "CPU_Info" - Spesifikasi : Intel Core i3 13100 | Clock Speed : 3.4Ghz | Core/Thread : 4/8 | CPU Load : 12% | CPU Temperature: 48 Celcius
    ```

### **3. disk_nvme_health.sh (Terjadwal - 16:00)**
*   **Fungsi**: Skrip berbasis Python terpadu untuk mendeteksi SSD NVMe, SSD SATA, dan SATA HDD secara otomatis. Dilengkapi dengan **Algoritma Heuristik Mandiri** untuk konversi LBA ke TBW pada SSD SATA kelas konsumen (seperti Apacer CS900) agar nilai baca/tulis tidak bernilai `0.0 TB`. Keterangan estimasi lifetime kustom (`Est. Life`) dihilangkan untuk menjaga kebersihan data visual, serta otomatis beralih ke mode pelacakan bad sector khusus HDD.
*   **Standardisasi Threshold (SSD/NVMe Health)**:
    *   **OK (0)**: Kesehatan \(> 90\%\)
    *   **Warning (1)**: Kesehatan \(\le 90\%\)
    *   **Critical (2)**: Kesehatan \(\le 80\%\)
*   **Format Output (SSD NVMe / SATA SSD)**:
    ```text
    0 "Storage_Health_sda" - Status : OK ❘ Model: CS900 SSD 120GB (111.79 GB) ❘ Status: PASSED ❘ Temp: 34C ❘ Health: 100% ❘ Read: 6.5 TB ❘ Written: 5.4 TB ❘ Write/Day: 108.64 GB
    ```
*   **Format Output (SATA HDD - Deteksi Bad Sector & Power On Hours)**:
    ```text
    0 "Storage_Health_sdb" - Status : OK ❘ Model: ST1000LM035-1RK172 1TB (931.51 GB) ❘ Status: PASSED ❘ Temp: 31C ❘ Disk Type: HDD ❘ Reallocated Sectors: 0 ❘ Pending Sectors: 0 ❘ Power On Hours: 12345 Hrs ❘ Remark: Disk Condition Good
    ```

### **4. fan_health.sh (Real-time)**
*   **Fungsi**: Membandingkan kecepatan putaran kipas pendingin (*fan speed*) secara dinamis dengan tingkat suhu prosesor untuk mengantisipasi kegagalan sistem pendingin aktif.
*   **Standardisasi Threshold**:
    *   **Critical (2)**: Suhu CPU \(> 85^\circ\text{C}\) dengan kipas \(< 1600\text{ RPM}\).
    *   **Warning (1)**: Suhu CPU \(> 65^\circ\text{C}\) dengan kipas \(< 1000\text{ RPM}\).
    *   **OK (0)**: Suhu CPU \(< 65^\circ\text{C}\) dengan kipas \(\ge 0\text{ RPM}\) (mendukung mode fanless/dingin).
*   **Format Output**:
    ```text
    0 "FAN_Health" - Status : OK | FAN Speed : 2319rpm | Remark: FAN Condition Good
    ```

### **5. info_network.sh (Real-time)**
*   **Fungsi**: Melacak statistik performa jaringan secara real-time. Skrip mengukur volume akumulatif data terunduh/terunggah serta menghitung kecepatan transfer RX/TX Rate sesungguhnya per detik (B/s, KB/s, MB/s) pada setiap kartu jaringan (*interface*) yang sedang aktif.
*   **Format Output**:
    ```text
    0 "Info_Network_wlo1" in=122554432c|out=3586048c OK - IP Address: 192.168.43.33 | Total Download: 114.14 GB | Total Upload: 3.34 GB | RX Rate : 250.20 KB/s | TX Rate : 123.00 KB/s
    ```

### **6. info_OS_office.sh (Terjadwal - 16:00)**
*   **Fungsi**: Menyajikan rincian nama sistem operasi distribusi Linux, versi kernel, serta melakukan pendeteksian terintegrasi terhadap seluruh aplikasi office terpasang (LibreOffice, WPS Office, Onlyoffice), baik dari paket lokal, Snap, maupun Flatpak user/system level. Output dilengkapi penanda waktu (*timestamped*) dan terproteksi dari bug output teks error `rpm`.
*   **Format Output**:
    ```text
    0 "Info_OS" - OK - OS: Fedora Linux 44 (Workstation Edition) | Kernel: 7.1.5-201.fc44.x86_64 | Arch: x86_64 ❘ Checked At: 2026-08-13 16:00:00
    0 "Info_Office" - OK - Product: LibreOffice 26.2.5.2 + Onlyoffice v7.2.1 | Status: Native Linux Application ❘ Checked At: 2026-08-13 16:00:00
    ```

### **7. ram_health.sh (Terjadwal - Setiap Sabtu 11:00 AM)**
*   **Fungsi**: Membaca file log lokal hasil pengetesan integritas sel memori RAM fisik asinkron yang dijalankan berkala **setiap hari Sabtu pukul 11:00 AM** menggunakan utilitas `memtester`. Caching skrip ini dikonfigurasi secara khusus agar selaras dengan jadwal pengujian tersebut guna menghemat utilitas sistem.
*   **Standardisasi Threshold**:
    *   **OK (0)**: Log pengujian RAM bernilai `Passed`
    *   **Critical (2)**: Log pengujian RAM bernilai `Failed` (mengindikasikan bad sector fisik pada keping RAM)
*   **Format Output**:
    ```text
    0 "RAM_Health" - Status : OK ❘ Result: Passed ❘ Tested Size: 1024M ❘ Last Test: 2026-08-15 11:00 ❘ Log: memtester passed successfully.
    ```

### **8. ram_usage.sh (Real-time)**
*   **Fungsi**: Menampilkan kapasitas total, sisa ruang, serta persentase real-time penggunaan memori RAM fisik yang aktif dari sistem `/proc/meminfo`.
*   **Standardisasi Threshold**:
    *   **OK (0)**: Utilisasi RAM \(< 85\%\)
    *   **Warning (1)**: Utilisasi RAM \(\ge 85\%\)
    *   **Critical (2)**: Utilisasi RAM \(\ge 95\%\)
*   **Format Output**:
    ```text
    0 "RAM_Usage" - Status : OK ❘ Used: 45% ❘ Used Space: 3.60 GB ❘ Free: 4.40 GB ❘ Total: 8.00 GB
    ```

### **9. remote_apps.sh (Terjadwal - 16:00)**
*   **Fungsi**: Memindai file konfigurasi sistem untuk mendapatkan ID unik dari aplikasi bantuan jarak jauh AnyDesk dan RustDesk untuk keperluan pencatatan inventaris dan pengawasan keamanan akses remote.
*   **Format Output**:
    ```text
    0 "Remote_Apps" - Status : OK ❘ AnyDesk ID: 123456789 ❘ RustDesk ID: 987654321
    ```

### **10. storage_usage.sh (Terjadwal - 16:00)**
*   **Fungsi**: Memantau kapasitas seluruh partisi penyimpanan fisik yang terpasang (*mounted*) secara aman. Secara cerdas mengecualikan sistem berkas virtual/semu (`tmpfs`, `devtmpfs`, `sysfs`, `proc`, dll) dan kontainer Docker terisolasi agar laporan di Checkmk tetap bersih.
*   **Standardisasi Threshold**:
    *   **OK (0)**: Penggunaan Storage \(< 85\%\)
    *   **Warning (1)**: Penggunaan Storage \(\ge 85\%\)
    *   **Critical (2)**: Penggunaan Storage \(\ge 95\%\)
*   **Format Output**:
    ```text
    0 "Storage_Usage_root" - Status : OK ❘ Partition: / ❘ Used: 42% ❘ Free: 139.20 GB ❘ Total: 240.00 GB
    ```

---

## 🛠️ Ringkasan Matriks Standardisasi Threshold (Checkmk)

| Parameter | OK (0) | Warning (1) | Critical (2) |
| :--- | :--- | :--- | :--- |
| **Suhu CPU** | \(\le 75^\circ\text{C}\) | \(> 75^\circ\text{C}\) | \(> 85^\circ\text{C}\) |
| **Kipas Prosesor** | \(> 1600\text{ RPM}\) / 0 (Fanless) | \(< 1600\text{ RPM}\) | Kombinasi Suhu Tinggi |
| **Kesehatan Baterai** | \(\ge 60\%\) | \(\le 40\%\) | \(\le 20\%\) |
| **Kesehatan SSD/NVMe** | \(> 90\%\) | \(\le 90\%\) | \(\le 80\%\) |
| **Penggunaan Storage** | \(< 85\%\) | \(\ge 85\%\) | \(\ge 95\%\) |
| **Penggunaan RAM** | \(< 85\%\) | \(\ge 85\%\) | \(\ge 95\%\) |
| **Hasil Uji RAM (`memtester`)** | Passed | - | Failed |

---

## 🔧 Panduan Keamanan & Aturan Parser Checkmk
*   Karakter pipa standar (**`|`**) **HANYA** diperbolehkan sebagai pemisah metrik data kinerja (*performance data* atau *perfdata*) di bagian depan baris.
*   Teks deskripsi kustom wajib menggunakan pembatas visual **Unicode Light Vertical Bar (`❘` - U+2758)** agar sistem tidak mengalami galat *Invalid data*.
*   Karakter placeholder minus (**`-`**) wajib disisipkan di kolom ketiga jika skrip tidak mengirimkan data kinerja (*perfdata*).

---

## 📝 Kontribusi & Penyelarasan
Setiap penyesuaian fungsionalitas skrip *local checks* wajib disinkronkan ke dalam repositori GitHub utama demi menjaga keandalan peringatan otomatis (*alarm metrics*) di server monitoring pusat.
