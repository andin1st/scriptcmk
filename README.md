# Checkmk Client Monitoring Agent Script Suite

Sistem pemantauan agen kustom Checkmk berbasis skrip otomatis untuk melakukan pengawasan terstandarisasi pada seluruh host client Linux dan Windows. Seluruh konfigurasi dan skrip monitoring ini dikelola secara terpusat pada repositori GitHub resmi **`andin1st/scriptcmk`**.

---

## 📂 Struktur Repositori GitHub (`andin1st/scriptcmk`)

```text
andin1st/scriptcmk/
├── .gitignore
├── README.md
├── linux/
│   ├── install.sh                       # Skrip installer otomatis Linux Host (Multi-Distro, Non-Interactive)
│   └── local_checks/
│       ├── battery_health.sh            # 1. Monitoring kesehatan baterai laptop (Health_Battery)
│       ├── cpu_info.sh                  # 2. Detail spesifikasi, clock, load & suhu CPU (CPU_Info)
│       ├── disk_nvme_health.sh          # 3. Kesehatan SSD NVMe/SATA (Heuristik, Tanpa Est. Life) & HDD (SATA)
│       ├── fan_health.sh                # 4. Monitoring kec. kipas vs suhu CPU (FAN_Health)
│       ├── info_network.sh              # 5. Throughput jaringan kustom real-time, RX/TX rate & IP
│       ├── info_OS_office.sh            # 6. Informasi OS (Info_OS) & Detektor Office (Info_Office) terpadu
│       ├── ram_health.sh                # 7. Log reader pengujian RAM memtester + Slot Fisik RAM (Health_RAM)
│       ├── ram_usage.sh                 # 8. Kapasitas & persentase penggunaan RAM (RAM_Usage)
│       ├── remote_apps.sh               # 9. Deteksi ID Remote (AnyDesk & RustDesk)
│       └── storage_usage.sh             # 10. Kapasitas partisi penyimpanan aktif (Non-virtual)
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

#### **1. Mode Instan Skala Massal (Non-Interaktif)**
Sangat ideal digunakan bersama Ansible, Puppet, SSH Loop, atau skrip otomatisasi deployment Anda. Secara default menggunakan default Site ID **`cmk`**:
```bash
curl -sSfgL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install.sh | sudo bash -s -- \
  -s 192.168.43.100 \
  -d cmk \
  -v 2.5.0p9 \
  -g andin1st/scriptcmk
```

**Detail Parameter CLI:**
*   `-s` : IP Address atau Domain Server Checkmk (Contoh: `192.168.43.100`).
*   `-d` : Nama Instansi / Site ID Checkmk Server (Default: `cmk`).
*   `-v` : Versi Agen Checkmk yang ingin dipasang (Contoh: `2.5.0p9`).
*   `-g` : Target repositori GitHub kustom Anda (Default: `andin1st/scriptcmk`).

---

## 📋 Detail 10 Skrip Monitoring Linux (`linux/local_checks/`)

Seluruh skrip monitoring menggunakan standar pemisahan visual **Unicode Light Vertical Bar (`❘` - U+2758)** agar laporan visual tampil sangat rapi di dashboard Checkmk dan kebal terhadap kegagalan *parsing* data kinerja (*performance data*).

### **1. battery_health.sh**
*   **Fungsi**: Mendeteksi kesehatan baterai menggunakan subsistem `UPower` D-Bus. Jika dipasang pada PC Desktop, skrip secara cerdas melaporkan kondisi normal tanpa baterai. Skrip ini bersifat non-realtime (diperbarui terjadwal harian pada pukul **16:00**).
*   **Standardisasi Threshold**:
    *   **OK (0)**: Kesehatan $\ge 60\%$
    *   **Warning (1)**: Kesehatan $\le 40\%$
    *   **Critical (2)**: Kesehatan $\le 20\%$
*   **Format Output (Laptop)**:
    ```text
    0 "Health_Battery" -  Status Battery : Fully Charged ❘ Design Capacity : 35w/h ❘ Current Capacity : 10w/h ❘ Health : 28% ❘ Battery Level : 100%
    ```
*   **Format Output (PC/Desktop)**:
    ```text
    0 "Health_Battery" -  Status Battery : N/A ❘ Device is PC/Desktop, there is no battery.
    ```

### **2. cpu_info.sh**
*   **Fungsi**: Menampilkan detail spesifikasi prosesor real-time yang bersih dari logo dagang (`(R)`, `(TM)`, dll.), clock speed dinamis dalam GHz, rasio Core/Thread fisik, beban utilitas, serta sensor suhu hardware terarah (`CPUTIN`/`k10temp`). Diperbarui secara *real-time*.
*   **Standardisasi Threshold**:
    *   **OK (0)**: Suhu CPU $\le 75^\circ	ext{C}$
    *   **Warning (1)**: Suhu CPU $> 75^\circ	ext{C}$
    *   **Critical (2)**: Suhu CPU $> 85^\circ	ext{C}$
*   **Format Output**:
    ```text
    0 "CPU_Info" - Spesifikasi : Intel Core i3 13100 | Clock Speed : 3.4Ghz | Core/Thread : 4/8 | CPU Load : 12% | CPU Temperature: 48 Celcius
    ```

### **3. disk_nvme_health.sh**
*   **Fungsi**: Skrip berbasis Python terpadu untuk mendeteksi SSD NVMe, SSD SATA, dan SATA HDD secara otomatis. Dilengkapi dengan **Algoritma Heuristik Mandiri** untuk konversi LBA ke TBW pada SSD SATA kelas konsumen (seperti Apacer CS900) agar nilai baca/tulis tidak bernilai `0.0 TB`. Skrip ini juga beralih otomatis ke mode pelacakan bad sector khusus HDD. Skrip ini bersifat non-realtime (diperbarui terjadwal harian pada pukul **16:00**), serta **bersih dari parameter estimasi masa pakai (`Est. Life`)** untuk SSD/NVMe guna menghindari kebingungan administratif.
*   **Standardisasi Threshold (SSD/NVMe Health)**:
    *   **OK (0)**: Kesehatan $> 90\%$
    *   **Warning (1)**: Kesehatan $\le 90\%$
    *   **Critical (2)**: Kesehatan $\le 80\%$
*   **Format Output (SSD NVMe / SATA SSD)**:
    ```text
    0 "Storage_Health_sda" - Status : OK ❘ Type: SSD Sata (111.79 GB) ❘ Status: PASSED ❘ Temp: 34C ❘ Health: 100% ❘ Read: 6.5 TB ❘ Written: 5.4 TB ❘ Write/Day: 108.64 GB
    ```
*   **Format Output (SATA HDD)**:
    ```text
    0 "Storage_Health_sdb" - Status : OK ❘ Model: ST1000LM035-1RK172 1TB (931.51 GB) ❘ Status: PASSED ❘ Temp: 31C ❘ Disk Type: HDD ❘ Reallocated Sectors: 0 ❘ Pending Sectors: 0 ❘ Power On Hours: 12345 Hrs ❘ Remark: Disk Condition Good
    ```

### **4. fan_health.sh**
*   **Fungsi**: Membandingkan kecepatan putaran kipas pendingin (*fan speed*) secara dinamis dengan tingkat suhu prosesor untuk mengantisipasi kegagalan sistem pendingin aktif. Diperbarui secara *real-time*.
*   **Standardisasi Threshold**:
    *   **Critical (2)**: Suhu CPU $> 85^\circ	ext{C}$ dengan kipas $< 1600	ext{ RPM}$.
    *   **Warning (1)**: Suhu CPU $> 65^\circ	ext{C}$ dengan kipas $< 1000	ext{ RPM}$.
    *   **OK (0)**: Suhu CPU $< 65^\circ	ext{C}$ dengan kipas $\ge 0	ext{ RPM}$ (mendukung mode fanless/dingin).
*   **Format Output**:
    ```text
    0 "FAN_Health" - Status : OK | FAN Speed : 2319rpm | Remark: FAN Condition Good
    ```

### **5. info_network.sh**
*   **Fungsi**: Melacak statistik performa jaringan secara *real-time*. Skrip mengukur volume akumulatif data terunduh/terunggah serta menghitung kecepatan transfer RX/TX Rate sesungguhnya per detik (B/s, KB/s, MB/s) pada setiap kartu jaringan (*interface*) yang sedang aktif. Diperbarui secara *real-time*.
*   **Format Output**:
    ```text
    0 "Info_Network_wlo1" in=122554432c|out=3586048c OK - IP Address: 192.168.43.33 | Total Download: 114.14 GB | Total Upload: 3.34 GB | RX Rate : 250.20 KB/s | TX Rate : 123.00 KB/s
    ```

### **6. info_OS_office.sh**
*   **Fungsi**: Menyajikan rincian nama sistem operasi distribusi Linux, versi kernel, serta melakukan pendeteksian terintegrasi terhadap seluruh aplikasi office terpasang (LibreOffice, WPS Office, Onlyoffice), baik dari paket lokal, Snap, maupun Flatpak user/system level. Output dilengkapi penanda waktu (*timestamped*) dan terproteksi dari bug output teks error `rpm`. Skrip ini bersifat non-realtime (diperbarui terjadwal harian pada pukul **16:00**).
*   **Format Output**:
    ```text
    0 "Info_OS" - OK - OS: Fedora Linux 44 (Workstation Edition) | Kernel: 7.1.5-201.fc44.x86_64 | Arch: x86_64 ❘ Checked At: 2026-08-13 16:00:00
    0 "Info_Office" - OK - Product: LibreOffice 26.2.5.2 + Onlyoffice v7.2.1 | Status: Native Linux Application ❘ Checked At: 2026-08-13 16:00:00
    ```

### **7. ram_health.sh**
*   **Fungsi**: Membaca file log lokal hasil pengujian modul memori RAM asinkron oleh utilitas `memtester` yang dipicu secara berkala setiap hari **Sabtu pukul 11:00 AM** via Cron Job, serta secara dinamis mendeteksi konfigurasi slot fisik RAM motherboard (`dmidecode`) untuk melacak slot terisi/kosong guna mempermudah peningkatan (*upgrade*) RAM. Skrip ini bersifat non-realtime (diperbarui terjadwal mingguan).
*   **Standardisasi Threshold**:
    *   **OK (0)**: Log pengujian RAM bernilai `Passed`
    *   **Critical (2)**: Log pengujian RAM bernilai `Failed` (mengindikasikan bad sector fisik pada keping RAM)
*   **Format Output (Ditemukan Slot RAM Fisik Akurat)**:
    ```text
    0 "Health_RAM" - Status : OK ❘ Result: Passed ❘ Tested Size: 128M ❘ Last Test: 2026-08-22 11:50 ❘ Used Slots: 2/2 (0 Empty) ❘ Active Modules: [4GiB,4GiB] ❘ Log: memtester passed successfully.
    ```

### **8. ram_usage.sh**
*   **Fungsi**: Menampilkan kapasitas RAM terpasang, ruang bebas, sisa ruang kosong, dan persentase penggunaan RAM fisik real-time berbasis data `/proc/meminfo`. Diperbarui secara *real-time*.
*   **Standardisasi Threshold**:
    *   **OK (0)**: Utilisasi RAM $< 85\%$
    *   **Warning (1)**: Utilisasi RAM $\ge 85\%$
    *   **Critical (2)**: Utilisasi RAM $\ge 95\%$
*   **Format Output**:
    ```text
    0 "RAM_Usage" - Status : OK ❘ Used: 45% ❘ Used Space: 3.60 GB ❘ Free: 4.40 GB ❘ Total: 8.00 GB
    ```

### **9. remote_apps.sh**
*   **Fungsi**: Memindai file konfigurasi sistem untuk mendapatkan ID unik dari aplikasi bantuan jarak jauh AnyDesk dan RustDesk untuk keperluan pencatatan inventaris dan pengawasan keamanan akses remote. Skrip ini bersifat non-realtime (diperbarui terjadwal harian pada pukul **16:00**).
*   **Format Output**:
    ```text
    0 "Remote_Apps" - Status : OK ❘ AnyDesk ID: 123456789 ❘ RustDesk ID: 987654321
    ```

### **10. storage_usage.sh**
*   **Fungsi**: Memantau tingkat penggunaan kapasitas pada partisi aktif dan secara otomatis mengabaikan tipe sistem berkas virtual/semu (*pseudofilesystem*). Skrip ini adaptif sehingga aman digunakan pada host fisik, VPS (LXC), maupun dalam kontainer Docker. Skrip ini bersifat non-realtime (diperbarui terjadwal harian pada pukul **16:00**).
*   **Standardisasi Threshold**:
    *   **OK (0)**: Penggunaan Storage $< 85\%$
    *   **Warning (1)**: Penggunaan Storage $\ge 85\%$
    *   **Critical (2)**: Penggunaan Storage $\ge 95\%$
*   **Format Output**:
    ```text
    0 "Storage_Usage_root" - Status : OK ❘ Partition: / ❘ Used: 42% ❘ Free: 139.20 GB ❘ Total: 240.00 GB
    ```

---

## 🛠️ Ringkasan Matriks Standardisasi Threshold (Checkmk)

| Parameter | OK (0) | Warning (1) | Critical (2) | Keterangan |
| :--- | :--- | :--- | :--- | :--- |
| **Suhu CPU** | $\le 75^\circ	ext{C}$ | $> 75^\circ	ext{C}$ | $> 85^\circ	ext{C}$ | Pemantauan Inti Sensor Hardware |
| **Kipas Prosesor** | $> 1600	ext{ RPM}$ / 0 (Fanless) | $< 1600	ext{ RPM}$ | Kombinasi Suhu Tinggi | Perlindungan Thermal Aktif |
| **Kesehatan Baterai** | $\ge 60\%$ | $\le 40\%$ | $\le 20\%$ | Auto-detect Laptop vs PC Desktop |
| **Kesehatan SSD/NVMe**| $> 90\%$ | $\le 90\%$ | $\le 80\%$ | Unified NVMe & SATA SSD Heuristik |
| **Penggunaan Storage**| $< 85\%$ | $\ge 85\%$ | $\ge 95\%$ | Partisi Aktif Fisik (Non-Virtual) |
| **Penggunaan RAM** | $< 85\%$ | $\ge 85\%$ | $\ge 95\%$ | RAM Fisik Real-time (/proc/meminfo) |
| **Hasil Uji RAM (`memtester`)**| Passed | - | Failed | Pengujian Sabtu 11:00 AM (Asinkron) |

---

## 🔧 Pemeliharaan & Kustomisasi Script

Jika Anda ingin melakukan penyesuaian atau perbaikan logika pada script monitoring di kemudian hari:
1. Anda **tidak perlu** mengonfigurasi ulang komputer client satu per satu.
2. Cukup lakukan perubahan pada berkas script yang ada di dalam repositori GitHub ini dan lakukan *commit/push*.
3. Pada komputer client yang sudah aktif, jalankan kembali perintah *one-liner bootstrap* di atas untuk memperbarui script lokal mereka ke versi terbaru secara otomatis.
