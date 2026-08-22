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
│       ├── battery_health.sh            # 1. Monitoring kesehatan baterai laptop
│       ├── cpu_info.sh                  # 2. Detail spesifikasi, clock, load & suhu CPU
│       ├── cpu_os_info.sh               # 3. Skrip gabungan legacy CPU & OS
│       ├── disk_nvme_health.sh          # 4. Kesehatan SSD NVMe/SATA & HDD (Unified)
│       ├── fan_health.sh                # 5. Monitoring kec. kipas vs suhu CPU
│       ├── onlyoffice_info.sh           # 6. Deteksi status & versi Onlyoffice (Terpisah)
│       ├── OS_info.sh                   # 7. Informasi distro OS & kernel Linux
│       ├── ram_health.sh                # 8. Log reader pengujian RAM memtester
│       ├── ram_usage.sh                 # 9. Kapasitas & persentase penggunaan RAM
│       ├── remote_apps.sh               # 10. Deteksi ID Remote (AnyDesk & RustDesk)
│       └── storage_usage.sh             # 11. Kapasitas partisi penyimpanan aktif
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

## 📋 Detail 11 Skrip Monitoring Linux (`linux/local_checks/`)

Seluruh skrip monitoring menggunakan standar pemisahan visual **Unicode Light Vertical Bar (`❘` - U+2758)** agar laporan visual tampil sangat rapi di dashboard Checkmk dan kebal terhadap kegagalan *parsing* data kinerja (*performance data*).

### **1. battery_health.sh**
*   **Fungsi**: Mendeteksi kesehatan baterai menggunakan subsistem `UPower` D-Bus. Jika dipasang pada PC Desktop, skrip secara cerdas melaporkan kondisi normal tanpa baterai.
*   **Standardisasi Threshold**:
    *   **OK (0)**: Kesehatan \(\ge 60\%\)
    *   **Warning (1)**: Kesehatan \(\le 40\%\)
    *   **Critical (2)**: Kesehatan \(\le 20\%\)
*   **Format Output**:
    ```text
    0 "Battery_Health" - Status : OK ❘ Health: 94% ❘ Cycle: 45 ❘ State: fully-charged
    ```

### **2. cpu_info.sh**
*   **Fungsi**: Menampilkan detail spesifikasi prosesor real-time yang bersih dari logo dagang (`(R)`, `(TM)`, dll.), clock speed dinamis dalam GHz, rasio Core/Thread fisik, beban utilitas, serta sensor suhu hardware terarah (`CPUTIN`/`k10temp`).
*   **Standardisasi Threshold**:
    *   **OK (0)**: Suhu CPU \(\le 75^\circ\text{C}\)
    *   **Warning (1)**: Suhu CPU \(> 75^\circ\text{C}\)
    *   **Critical (2)**: Suhu CPU \(> 85^\circ\text{C}\) (Status kritis dipicu jika kipas bermasalah)
*   **Format Output**:
    ```text
    0 "CPU_Info" - Spesifikasi : Intel Core i3 13100 | Clock Speed : 3.4Ghz | Core/Thread : 4/8 | CPU Load : 12% | CPU Temperature: 48 Celcius
    ```

### **3. cpu_os_info.sh**
*   **Fungsi**: Skrip legacy terpadu yang menampilkan spesifikasi ringkas performa prosesor beriringan dengan detail sistem operasi host.
*   **Format Output**:
    ```text
    0 "CPU_OS_Info" - OS: Ubuntu 24.04 LTS ❘ CPU: AMD Ryzen 5 5600X ❘ Load: 8% ❘ Temp: 42C
    ```

### **4. disk_nvme_health.sh (Unified)**
*   **Fungsi**: Skrip berbasis Python terpadu untuk mendeteksi SSD NVMe, SSD SATA, dan SATA HDD secara otomatis. Dilengkapi dengan **Algoritma Heuristik Mandiri** untuk konversi LBA ke TBW pada SSD SATA kelas konsumen (seperti Apacer CS900) agar nilai baca/tulis tidak bernilai `0.0 TB`. Skrip ini juga beralih otomatis ke mode pelacakan bad sector khusus HDD.
*   **Standardisasi Threshold (SSD/NVMe Health)**:
    *   **OK (0)**: Kesehatan \(> 90\%\)
    *   **Warning (1)**: Kesehatan \(\le 90\%\)
    *   **Critical (2)**: Kesehatan \(\le 80\%\)
*   **Format Output (SSD NVMe / SATA SSD)**:
    ```text
    0 "Storage_Health_sda" - Status : OK ❘ Model: CS900 SSD 120GB (111.79 GB) ❘ Status: PASSED ❘ Temp: 34C ❘ Health: 100% ❘ Read: 6.5 TB ❘ Written: 5.4 TB ❘ Write/Day: 108.64 GB ❘ Est. Life: >10 Years
    ```
*   **Format Output (SATA HDD - Deteksi Bad Sector & Power On Hours)**:
    ```text
    0 "Storage_Health_sdb" - Status : OK ❘ Model: ST1000LM035-1RK172 1TB (931.51 GB) ❘ Status: PASSED ❘ Temp: 31C ❘ Disk Type: HDD ❘ Reallocated Sectors: 0 ❘ Pending Sectors: 0 ❘ Power On Hours: 12345 Hrs ❘ Remark: Disk Condition Good
    ```

### **5. fan_health.sh**
*   **Fungsi**: Membandingkan kecepatan putaran kipas pendingin (*fan speed*) secara dinamis dengan tingkat suhu prosesor untuk mengantisipasi kegagalan sistem pendingin aktif.
*   **Standardisasi Threshold**:
    *   **Critical (2)**: Suhu CPU \(> 85^\circ\text{C}\) dengan kipas \(< 1600\text{ RPM}\).
    *   **Warning (1)**: Suhu CPU \(> 65^\circ\text{C}\) dengan kipas \(< 1000\text{ RPM}\).
    *   **OK (0)**: Suhu CPU \(< 65^\circ\text{C}\) dengan kipas \(\ge 0\text{ RPM}\) (mendukung mode fanless/dingin).
*   **Format Output**:
    ```text
    0 "FAN_Health" - Status : OK | FAN Speed : 2319rpm | Remark: FAN Condition Good
    ```

### **6. onlyoffice_info.sh (Terpisah)**
*   **Fungsi**: Skrip mandiri khusus untuk mendeteksi status dan versi aplikasi Onlyoffice yang terinstal di komputer host. Mendukung pencarian dari paket lokal (`dpkg`, `rpm`), `flatpak`, dan `snap` (dengan perbaikan pencarian filter kustom).
*   **Format Output (Terpasang)**:
    ```text
    0 "Onlyoffice_Status" - Status : OK ❘ Version: Onlyoffice v7.2
    ```
*   **Format Output (Tidak Terpasang)**:
    ```text
    0 "Onlyoffice_Status" - Status : OK ❘ Onlyoffice tidak terpasang
    ```

### **7. OS_info.sh**
*   **Fungsi**: Menyediakan informasi detail mengenai distribusi sistem operasi Linux yang aktif beserta versi modul kernel yang digunakan.
*   **Format Output**:
    ```text
    0 "OS_Detail" - OS: Ubuntu 24.04.1 LTS, Kernel: 6.8.0-40-generic
    ```

### **8. ram_health.sh**
*   **Fungsi**: Membaca file log lokal hasil pengujian modul memori RAM asinkron oleh utilitas `memtester` yang dipicu secara berkala setiap hari Sabtu pukul 11:00 AM via Cron Job, serta secara dinamis mendeteksi konfigurasi slot fisik RAM motherboard (`dmidecode`) untuk melacak slot terisi/kosong guna mempermudah peningkatan (*upgrade*) RAM.
*   **Standardisasi Threshold**:
    *   **OK (0)**: Log pengujian RAM bernilai `Passed`
    *   **Critical (2)**: Log pengujian RAM bernilai `Failed` (mengindikasikan bad sector fisik pada keping RAM)
*   **Format Output**:
    ```text
    0 "RAM_Health" - Status : OK ❘ Result: Passed ❘ Tested Size: 1024M ❘ Last Test: 2026-08-15 11:00 ❘ Used Slots: 1/2 (1 Empty) ❘ Active Modules: [8GB] ❘ Log: memtester passed successfully.
    ```

### **9. ram_usage.sh**
*   **Fungsi**: Menampilkan kapasitas RAM terpasang, ruang bebas, sisa ruang kosong, dan persentase penggunaan RAM fisik real-time berbasis data `/proc/meminfo`.
*   **Standardisasi Threshold**:
    *   **OK (0)**: Utilisasi RAM \(< 85\%\)
    *   **Warning (1)**: Utilisasi RAM \(\ge 85\%\)
    *   **Critical (2)**: Utilisasi RAM \(\ge 95\%\)
*   **Format Output**:
    ```text
    0 "RAM_Usage" - Status : OK ❘ Used: 45% ❘ Used Space: 3.60 GB ❘ Free: 4.40 GB ❘ Total: 8.00 GB
    ```

### **10. remote_apps.sh**
*   **Fungsi**: Memindai ID unik untuk software remote support AnyDesk dan RustDesk yang aktif pada komputer client guna mempercepat kendali kendali tim helpdesk IT.
*   **Format Output**:
    ```text
    0 "Remote_Apps" - Status : OK ❘ AnyDesk ID: 123456789 ❘ RustDesk ID: 987654321
    ```

### **11. storage_usage.sh**
*   **Fungsi**: Memantau tingkat penggunaan kapasitas pada partisi aktif dan secara otomatis mengabaikan tipe sistem berkas virtual/semu (*pseudofilesystem*). Skrip ini adaptif sehingga aman digunakan pada host fisik, VPS (LXC), maupun dalam kontainer Docker.
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

## 📝 Kontribusi & Penyelarasan
Pembaruan kode skrip *local checks* harus senantiasa diselaraskan dengan tabel standar operasional prosedur yang berlaku demi menjaga tingkat akurasi alarm sistem monitoring pusat.
