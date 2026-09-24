# Standardisasi Monitoring Checkmk (andin1st/scriptcmk)

Proyek ini bertujuan untuk membangun sistem monitoring aset perusahaan menggunakan **Checkmk** secara terpusat, otomatis, dan seragam. Semua berkas konfigurasi, skrip instalasi (*installer*), dan skrip pemantauan (*local checks*) dikelola secara terpusat melalui repositori GitHub resmi: ****.

---

## 📂 Struktur Repositori GitHub



---

## 🚀 Panduan Deployment Cepat (One-Liner Bootstrap)

### **A. Pemasangan Server Checkmk (Docker + Dockge + Checkmk Community Edition)**

Gunakan perintah satu baris (*one-liner*) berikut pada server Linux (Ubuntu/Debian/RHEL/Fedora) untuk memasang Docker Engine, Dockge Stack Manager (Port 5001), dan **Checkmk Community Edition Server** (Port 8080 & 8000) secara otomatis dengan fitur *auto-start* saat sistem dinyalakan:



---

### **B. Pemasangan Agen Client Linux (Debian, Ubuntu, Fedora, RHEL, Rocky, Alma)**

#### **1. Mode Interaktif (Manual & Interaktif)**
Perintah ini akan menanyakan IP Server, Site ID, dan versi agen secara interaktif:


#### **2. Mode Instan / Silent (Deployment Massal)**
Gunakan parameter CLI untuk instalasi otomatis tanpa interaksi keyboard:


---

### **C. Pemasangan Agen Client Windows**

#### **1. Mode Interaktif (3 Inputan Ringkas: IP Server:Port, Site ID, Versi)**
Jalankan melalui **PowerShell (Administrator)**:


#### **2. Mode Non-Interaktif / Fast CLI Arguments**


---

### **D. Pendaftaran Sertifikat Keamanan Agen (mTLS Registration)**

Setiap agen client perlu didaftarkan satu kali ke server Checkmk via port TLS  untuk mengamankan komunikasi data monitoring:

* **Linux Host**:
  
* **Windows Host (PowerShell Administrator)**:
  

---

## 📊 Detail 10 Skrip Pemantauan Lokal (Linux & Windows)

Seluruh output local check menggunakan placeholder data kinerja () serta pembatas visual Unicode Light Vertical Bar (****) untuk menjamin keakuratan parsing data Checkmk dan menghindari kegagalan status (*Invalid data*).

### **1.  / **
Mendeteksi distribusi OS dan kernel/versi OS yang digunakan host serta lisensi dan aplikasi office terpasang.

### **2.  / **
Menampilkan informasi CPU yang bersih (bebas simbol dagang kotor) serta performa load real-time dan sensor temperatur hardware.

### **3.  / **
Pemantauan penyimpanan terpadu yang mendukung NVMe, SATA SSD (kalkulasi otomatis TBW/LBA), dan SATA HDD (Reallocated/Pending Sectors).

### **4.  / **
Memantau kecepatan kipas pendingin (*fan speed*) dengan membandingkannya terhadap suhu CPU saat ini.

### **5.  / **
Melacak statistik statistik jaringan real-time (IP Address, Total RX/TX, serta Throughput Rate B/s, KB/s, MB/s).

### **6.  / **
Mendeteksi tingkat kesehatan baterai laptop (*State of Health*) secara presisi berbasis rasio kapasitas riil vs desain pabrik, serta mengenali PC/Desktop tanpa baterai.

### **7.  / **
Membaca log pengujian memori dinamis asinkron (alokasi 20% Free RAM) yang dijalankan terjadwal via Cron/Task Scheduler setiap Sabtu pukul 11:00 AM.

### **8.  / **
Memantau persentase penggunaan memori fisik (RAM) real-time (Used, Free, Total).

### **9.  / **
Mendeteksi ID aplikasi bantuan jarak jauh (AnyDesk & RustDesk) untuk inventaris IT.

### **10.  / **
Memantau persentase kapasitas partisi penyimpanan fisik yang terpasang (*mounted*) dan mengabaikan partisi virtual.

---

## 📋 Matriks Standardisasi Batas Parameter (Threshold)

Berikut adalah tabel acuan ambang batas parameter untuk penentuan status kesehatan aset pada dashboard Checkmk perusahaan:

| Parameter Monitoring | OK (Status: 0) | WARNING (Status: 1) | CRITICAL (Status: 2) | Keterangan / Sensor |
| :--- | :--- | :--- | :--- | :--- |
| **Suhu CPU** |  |  s.d  |  | ACPI / CPUTIN / Coretemp |
| **Kipas (FAN) CPU** |  atau  (Fanless/PC) |  (Saat suhu tinggi) |  (Suhu ) | sensors (lm-sensors / CIM) |
| **Kesehatan Baterai** |  |  |  | UPower / sysfs / WMI |
| **Kesehatan SSD (SATA/NVMe)**|  |  |  | Remaining Life / TBW Wearout |
| **Kesehatan HDD (SATA)** | Bad Sector = 0 | Reallocated/Pending  | SMART  / Reallocated  | Reallocated & Pending Count |
| **RAM Usage** |  |  s.d  |  | MemAvailable / Physical RAM |
| **RAM Health** | Passed | - | Failed | Pengujian  / stress test |
| **Storage Usage** |  |  s.d  |  | Disk Mount Physical |
| **Aplikasi Remote** | Terdeteksi ID | - | Tidak Terpasang | Config / CLI Extraction |
