# Checkmk Client Monitoring Agent Script Suite

Sistem pemantauan agen kustom Checkmk berbasis skrip otomatis untuk melakukan pengawasan terstandarisasi pada seluruh host client Linux dan Windows. Seluruh konfigurasi dan skrip monitoring ini dikelola secara terpusat pada repositori GitHub resmi **`andin1st/scriptcmk`**.

---

## 📂 Struktur Repositori GitHub (`andin1st/scriptcmk`)

```text
andin1st/scriptcmk/
├── .gitignore
├── README.md
├── linux/
│   ├── install.sh                       # Skrip installer otomatis Linux Host (Multi-Distro, Default Site: cmk)
│   └── local_checks/
│       ├── battery_health.sh            # 1. Monitoring kesehatan baterai laptop (Pukul 16:00)
│       ├── cpu_info.sh                  # 2. Detail spesifikasi, clock, load & suhu CPU (Real-Time)
│       ├── disk_nvme_health.sh          # 3. Kesehatan SSD NVMe/SATA & HDD (Unified, Pukul 16:00)
│       ├── fan_health.sh                # 4. Monitoring kec. kipas vs suhu CPU (Real-Time)
│       ├── info_network.sh              # 5. Real-time network throughput, RX/TX rate, & IP info (Real-Time)
│       ├── info_OS_office.sh            # 6. Detail distro OS & versi Office terpasang (Pukul 16:00)
│       ├── ram_health.sh                # 7. Log reader pengujian RAM memtester (Sabtu 11:00)
│       ├── ram_usage.sh                 # 8. Kapasitas & persentase penggunaan RAM (Real-Time)
│       ├── remote_apps.sh               # 9. Deteksi ID Remote AnyDesk & RustDesk (Pukul 16:00)
│       └── storage_usage.sh             # 10. Kapasitas partisi penyimpanan aktif (Pukul 16:00)
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

#### **1. Mode Instan Standar (Otomatis)**
```bash
curl -sSfgL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install.sh | sudo bash
```

#### **2. Mode Skala Massal Non-Interaktif**
Sangat ideal digunakan bersama Ansible, Puppet, SSH Loop, atau skrip otomatisasi deployment Anda:
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
*   `-v` : Versi Agen Checkmk yang ingin dipasang (Default: `2.5.0p9-1`).
*   `-g` : Target repositori GitHub kustom Anda (Default: `andin1st/scriptcmk`).

---

## ⏱️ Strategi Optimasi Beban Kerja (Caching & Scheduling)

Demi menjaga performa CPU klien tetap optimal, suite ini memisahkan tugas pemantauan menjadi dua kategori:

1. **Skrip Real-Time (Eksekusi Instan)**:
   Dijalankan langsung setiap kali server melakukan *polling* (biasanya setiap 1 menit) karena metrik ini bersifat sangat dinamis.
   * *Skrip*: `cpu_info.sh`, `fan_health.sh`, `ram_usage.sh`, `info_network.sh`.

2. **Skrip Terjadwal (Daily Cache pukul 16:00)**:
   Metrik ini hanya berfluktuasi sedikit dalam sehari. Skrip ini menggunakan **Mesin Caching Mandiri Terjadwal** yang melakukan pemindaian perangkat keras fisik hanya **sekali dalam sehari setelah pukul 16:00**. Pada pemanggilan di luar jam tersebut, skrip langsung menyajikan data dari cache lokal (`/var/lib/check_mk_agent/cache/cache_*.txt`) dalam waktu kurang dari **1 milidetik** tanpa beban CPU sama sekali.
   * *Skrip*: `battery_health.sh`, `disk_nvme_health.sh`, `info_OS_office.sh`, `remote_apps.sh`, `storage_usage.sh`.

3. **Skrip Mingguan (Asinkron Sabtu pukul 11:00)**:
   Pengujian kerusakan fisik RAM (`memtester`) sangat membebani CPU. Pengujian dijalankan secara asinkron lewat Cron Job **setiap hari Sabtu pukul 11:00 AM**. Skrip pembaca status hanya membaca berkas log statis tersebut secara instan.
   * *Skrip*: `ram_health.sh`.

---

## 📋 Detail 10 Skrip Monitoring Linux (`linux/local_checks/`)

Seluruh skrip monitoring menggunakan standar pemisahan visual **Unicode Light Vertical Bar (`❘` - U+2758)** agar laporan visual tampil sangat rapi di dashboard Checkmk dan kebal terhadap kegagalan *parsing* data kinerja (*performance data*).

### **1. battery_health.sh**
*   **Fungsi**: Mendeteksi kesehatan baterai menggunakan subsistem `UPower` D-Bus (dengan fallback ke `sysfs`). Membaca kapasitas desain, kapasitas saat ini, tingkat keausan, dan level baterai. Pada PC Desktop, otomatis melaporkan kondisi normal tanpa baterai.
*   **Output (Laptop - Terdeteksi Baterai)**:
    ```text
    0 "Health_Battery" -  Status Battery : Fully Charged ❘ Design Capacity : 35w/h ❘ Current Capacity : 10w/h ❘ Health : 28% ❘ Battery Level : 100%
    ```
*   **Output (PC Desktop / Server CLI)**:
    ```text
    0 "Health_Battery" -  Status Battery : N/A ❘ Device is PC/Desktop, there is no battery.
    ```

### **2. cpu_info.sh**
*   **Fungsi**: Menampilkan detail spesifikasi prosesor real-time yang bersih dari logo dagang (`(R)`, `(TM)`, dll.), clock speed dinamis dalam GHz, rasio Core/Thread fisik, beban utilitas, serta sensor suhu hardware terarah (`CPUTIN`/`k10temp`).
*   **Output**:
    ```text
    0 "CPU_Info" - Spesifikasi : AMD Ryzen 5 5600H | Clock Speed : 3.3Ghz | Core/Thread : 6/12 | CPU Load : 15% | CPU Temperature: 46 Celcius
    ```

### **3. disk_nvme_health.sh**
*   **Fungsi**: Mendeteksi secara dinamis tipe disk (SATA SSD, NVMe SSD, dan SATA HDD) dan menyesuaikan template laporan. SSD SATA didukung **Algoritma Heuristik Mandiri** untuk konversi LBA ke TBW pada pengontrol non-standar (Apacer, V-Gen, dll.) agar nilai baca/tulis tidak terbaca `0.0 TB`. HDD SATA secara otomatis dipantau dari parameter bad sector (Reallocated/Pending) dan jam aktif kerja. Metrik `Est. Life` telah dihapus sepenuhnya demi menyederhanakan laporan.
*   **Output (SSD/NVMe)**:
    ```text
    0 "Storage Health (GEN01SM21AR1024ITNVME)" - Status : OK ❘ Type: NVME (1.00 TB) ❘ Status: PASSED ❘ Temp: 41C ❘ Health: 92% ❘ Read: 27.6 TB ❘ Written: 39.3 TB ❘ Write/Day: 153.40 GB
    ```
*   **Output (SATA HDD)**:
    ```text
    0 "Storage Health (ST1000LM035-1RK172)" - Status : OK ❘ Type: HDD (1.00 TB) ❘ Status: PASSED ❘ Temp: 31C ❘ Rotation Rate: 5400rpm | Realocated Sector: 0❘ Power On Hours: 12345 Hrs ❘ Remark: Disk Condition Good
    ```

### **4. fan_health.sh**
*   **Fungsi**: Membandingkan kecepatan putaran kipas pendingin (*fan speed*) secara dinamis dengan tingkat suhu prosesor untuk mengantisipasi kegagalan sistem pendingin aktif.
*   **Output**:
    ```text
    0 "FAN_Health" - Status : OK | FAN Speed : 2319rpm | Remark: FAN Condition Good
    ```

### **5. info_network.sh**
*   **Fungsi**: Melacak statistik performa jaringan secara real-time. Skrip mengukur volume akumulatif data terunduh/terunggah serta menghitung kecepatan transfer RX/TX Rate sesungguhnya per detik (B/s, KB/s, MB/s) pada setiap kartu jaringan (*interface*) yang sedang aktif.
*   **Output**:
    ```text
    0 "Info_Network_wlo1" in=122554432c|out=3586048c OK - IP Address: 192.168.43.33 | Total Download: 114.14 GB | Total Upload: 3.34 GB | RX Rate : 250.20 KB/s | TX Rate : 123.00 KB/s
    ```

### **6. info_OS_office.sh**
*   **Fungsi**: Menyajikan rincian nama sistem operasi distribusi Linux, versi kernel, serta melakukan pendeteksian terintegrasi terhadap seluruh aplikasi office terpasang (LibreOffice, WPS Office, Onlyoffice), baik dari paket lokal, Snap, maupun Flatpak user/system level. Output dilengkapi penanda waktu (*timestamped*) dan terproteksi dari bug output teks error `rpm`.
*   **Output**:
    ```text
    0 "Info_OS" - OK - OS: Fedora Linux 44 (Workstation Edition) | Kernel: 7.1.5-201.fc44.x86_64 | Arch: x86_64 ❘ Checked At: 2026-08-13 16:00:00
    0 "Info_Office" - OK - Product: LibreOffice 26.2.5.2 620(Build:2) + Onlyoffice v7.2.1 | Status: Native Linux Application ❘ Checked At: 2026-08-13 16:00:00
    ```

### **7. ram_health.sh**
*   **Fungsi**: Membaca file log lokal hasil pengujian modul memori RAM asinkron oleh utilitas `memtester` yang dipicu terjadwal oleh Cron Job setiap hari Sabtu pukul 11:00 AM.
*   **Output**:
    ```text
    0 "RAM_Health" - Status : OK ❘ Result: Passed ❘ Tested Size: 1024M ❘ Last Test: 2026-08-15 11:00 ❘ Log: memtester passed successfully.
    ```

### **8. ram_usage.sh**
*   **Fungsi**: Menampilkan kapasitas RAM terpasang, ruang bebas, sisa ruang kosong, dan persentase penggunaan RAM fisik real-time berbasis data `/proc/meminfo`.
*   **Output**:
    ```text
    0 "RAM_Usage" - Status : OK ❘ Used: 45% ❘ Used Space: 3.60 GB ❘ Free: 4.40 GB ❘ Total: 8.00 GB
    ```

### **9. remote_apps.sh**
*   **Fungsi**: Memindai ID unik untuk software remote support AnyDesk dan RustDesk yang aktif pada komputer client guna mempercepat kendali kendali tim helpdesk IT. (Logika pendeteksian Onlyoffice telah dihapus sepenuhnya dari berkas ini agar tidak terjadi redundansi karena sudah ditangani di `info_OS_office.sh`).
*   **Output**:
    ```text
    0 "Remote_Apps" - Status : OK ❘ AnyDesk ID: 123456789 ❘ RustDesk ID: 987654321
    ```

### **10. storage_usage.sh**
*   **Fungsi**: Memantau tingkat penggunaan kapasitas pada partisi aktif dan secara otomatis mengabaikan tipe sistem berkas virtual/semu (*pseudofilesystem*). Skrip ini adaptif sehingga aman digunakan pada host fisik, VPS (LXC), maupun dalam kontainer Docker.
*   **Output**:
    ```text
    0 "Storage_Usage_root" - Status : OK ❘ Partition: / ❘ Used: 42% ❘ Free: 139.20 GB ❘ Total: 240.00 GB
    ```

---

## 🛠️ Ringkasan Matriks Standardisasi Threshold (Checkmk)

| Parameter | OK (0) | Warning (1) | Critical (2) | Keterangan |
| :--- | :--- | :--- | :--- | :--- |
| **Suhu CPU** | \(\le 75^\circ\text{C}\) | \(> 75^\circ\text{C}\) | \(> 85^\circ\text{C}\) | Deteksi real-time |
| **Kipas Prosesor** | \(> 1600\text{ RPM}\) | \(< 1600\text{ RPM}\) | Kombinasi Suhu Tinggi | Deteksi real-time |
| **Kesehatan Baterai** | \(\ge 60\%\) | \(\le 40\%\) | \(\le 20\%\) | Caching harian (16:00) |
| **Kesehatan SSD/NVMe** | \(> 90\%\) | \(\le 90\%\) | \(\le 80\%\) | Caching harian (16:00) |
| **Penggunaan Storage** | \(< 85\%\) | \(\ge 85\%\) | \(\ge 95\%\) | Caching harian (16:00) |
| **Penggunaan RAM** | \(< 85\%\) | \(\ge 85\%\) | \(\ge 95\%\) | Deteksi real-time |
| **Hasil Uji RAM (`memtester`)** | Passed | - | Failed | Pengujian asinkron (Sabtu 11:00) |

---

## ⚙️ Aturan Pengembangan & Keamanan Pembatas (Unicode Light Pipe)

Demi menjaga kompatibilitas parser di sisi server Checkmk, semua skrip *local checks* kustom ini wajib mengikuti aturan teknis berikut:
* Karakter pipa standar (**`|`**) **HANYA** boleh digunakan di kolom data kinerja (*performance data* atau *perfdata*) di bagian awal baris sebelum pemisah spasi pertama.
* Seluruh tanda pembatas visual di dalam teks deskripsi status wajib menggunakan karakter *Unicode Light Vertical Bar* (**`❘` - U+2758**) agar parser Checkmk tidak mengalami galat `Invalid data`.
* Jika skrip tidak mengirimkan data kinerja (*perfdata*), karakter placeholder minus (**`-`**) wajib diletakkan di kolom ketiga sebelum penulisan teks status visual.

---

## 📝 Kontribusi & Penyelarasan
Pembaruan kode skrip *local checks* harus senantiasa diselaraskan dengan tabel standar operasional prosedur yang berlaku demi menjaga tingkat akurasi alarm sistem monitoring pusat.
