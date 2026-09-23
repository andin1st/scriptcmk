# Checkmk Client Monitoring Agent Script Suite & Server Stack

Sistem pemantauan terpusat berbasis **Checkmk Community Edition v2.5.0** dan rangkaian skrip pemantauan kustom (*local checks*) otomatis untuk pengawasan terstandarisasi pada seluruh host klien Linux dan Windows. Entire repository and deployment scripts are centralizes at **`andin1st/scriptcmk`**.

---

## 📂 Arsitektur & Struktur Repositori GitHub (`andin1st/scriptcmk`)

```text
andin1st/scriptcmk/
├── .gitignore
├── README.md
├── docker-compose-checkmk.yml           # Formasi Docker Compose Checkmk Community Edition v2.5.0
├── linux/
│   ├── install_server_stack.sh          # Auto-installer Server Stack (Docker + Dockge + Checkmk Community)
│   ├── install.sh                       # Skrip installer otomatis Linux Client Host (Multi-Distro, Smart Check)
│   └── local_checks/
│       ├── battery_health.sh            # 1. Health Baterai Laptop vs PC (Health_Battery)
│       ├── cpu_info.sh                  # 2. Detail CPU, Clock, Load & Suhu (CPU_Info)
│       ├── disk_nvme_health.sh          # 3. Kesehatan SSD/NVMe (Heuristik TBW) & HDD (SATA)
│       ├── fan_health.sh                # 4. Kecepatan Kipas vs Suhu CPU (FAN_Health)
│       ├── info_network.sh              # 5. Throughput Jaringan, Speed RX/TX & IP Address
│       ├── info_OS_office.sh            # 6. Informasi OS (Info_OS) & Detektor Office (Info_Office)
│       ├── ram_health.sh                # 7. Pengujian RAM memtester + Slot Fisik (Health_RAM)
│       ├── ram_usage.sh                 # 8. Penggunaan Kapasitas RAM Fisik (RAM_Usage)
│       ├── remote_apps.sh               # 9. ID Remote Desktop (AnyDesk & RustDesk)
│       └── storage_usage.sh             # 10. Utilisasi Partisi Penyimpanan Aktif
└── windows/
    ├── install.ps1                      # Skrip installer otomatis Windows Client Host (Smart Version Check)
    └── local_checks/
        ├── battery_health.ps1           # 1. Health Baterai Laptop Windows (Low-level WMI)
        ├── cpu_info.ps1                 # 2. Detail Spesifikasi, Clock, Load & Suhu CPU
        ├── disk_nvme_health.ps1         # 3. Health SSD/NVMe (Wearout %) & HDD Bad Sector
        ├── fan_health.ps1               # 4. Kecepatan Kipas Process (CIM/WMI Native)
        ├── info_network.ps1             # 5. Throughput Jaringan Real-Time & IP Windows
        ├── info_OS_office.ps1           # 6. Status Aktivasi Windows & Lisensi MS Office (ospp.vbs)
        ├── ram_health.ps1               # 7. Uji RAM Asinkron & Sensor Slot RAM Physical
        ├── ram_usage.ps1                # 8. Penggunaan Kapasitas RAM Fisik Windows
        ├── remote_apps.ps1              # 9. ID Remote AnyDesk & RustDesk Windows
        └── storage_usage.ps1            # 10. Utilisasi Partisi Drive Aktif (Volume)
```

---

## 🛠️ 1. Pemasangan Checkmk Community Edition Server & Stack Manager

Untuk memasang infrastruktur server pemantau terpusat (**Docker Engine**, **Dockge Stack Manager**, dan **Checkmk Community Edition Server v2.5.0**) pada server Linux Ubuntu/Debian/RHEL/Fedora Anda secara otomatis (dilengkapi fitur *auto-start systemd*):

```bash
curl -fsSL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install_server_stack.sh | sudo bash
```

### **Akses Dasbor Layanan Server:**
* **Dockge Stack Manager** : `http://<IP_SERVER>:5001`
* **Checkmk Community Edition GUI** : `http://<IP_SERVER>:8080/cmk` *(User: `cmkadmin` | Pass: `cmkadmin`)*
* **Checkmk Agent TLS Registration Port** : `<IP_SERVER>:8000`

---

## 🚀 2. Panduan Deployment Agen Klien (Fast Deployment)

### **A. Linux Client Host (Ubuntu, Debian, Fedora, RHEL, CentOS)**

Jalankan perintah satu baris (*one-liner*) berikut untuk mendeteksi versi, mengunduh agen, serta menyinkronkan 10 skrip *local checks*:

```bash
curl -sSfgL https://raw.githubusercontent.com/andin1st/scriptcmk/main/linux/install.sh | sudo bash -s -- \
  -s 192.168.43.100 \
  -d cmk \
  -v 2.5.0p9 \
  -g andin1st/scriptcmk
```

### **B. Windows Client Host (Windows 10, 11, Windows Server)**

Buka **PowerShell (Run as Administrator)** dan jalankan perintah *one-liner* berikut:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/andin1st/scriptcmk/main/windows/install.ps1'))
```

---

## 📋 3. Matriks Standardisasi Threshold & Parameter Status (Checkmk SOP)

Seluruh skrip *local checks* baik untuk Linux maupun Windows mengacu pada standar ambang batas peringatan (*alert thresholds*) resmi berikut:

| Nama Metrik / Parameter | OK (Status 0) | WARNING (Status 1) | CRITICAL (Status 2) | Keterangan Tambahan |
| :--- | :--- | :--- | :--- | :--- |
| **Suhu CPU** | $\le 75^\circ\text{C}$ | $> 75^\circ\text{C}$ | $> 85^\circ\text{C}$ | Sensor Inti Hardware Real-time |
| **Kipas Prosesor** | $> 1600\text{ RPM}$ / $0$ (Fanless) | $< 1600\text{ RPM}$ | Kombinasi Suhu High | Dukungan Passive Cooling Mode |
| **Kesehatan Baterai** | $\ge 60\%$ | $\le 40\%$ | $\le 20\%$ | Autodetect Laptop vs PC Desktop |
| **SSD / NVMe Health** | $> 90\%$ | $\le 90\%$ | $\le 80\%$ | Sisa Umur / Wearout % |
| **Penggunaan Storage**| $< 85\%$ | $\ge 85\%$ | $\ge 95\%$ | Partisi Aktif Fisik (Non-Virtual) |
| **Penggunaan RAM** | $< 85\%$ | $\ge 85\%$ | $\ge 95\%$ | RAM Fisik Real-time |
| **Hasil Uji RAM (`memtester`)**| Passed | - | Failed | Pengujian Asinkron Terjadwal |

---

## 🔒 4. Pendaftaran Sertifikat Keamanan Agen (mTLS Registration)

Setelah instalasi agen pada klien selesai, lakukan registrasi sertifikat digital satu kali (*one-time mTLS registration*) agar komunikasi agen ke Checkmk Server berjalan secara terenkripsi:

### **Pada Linux Client:**
```bash
sudo cmk-agent-ctl register --server 192.168.43.100:8000 --site cmk --user cmkadmin --host $(hostname)
```

### **Pada Windows Client (PowerShell Admin):**
```powershell
& "C:\Program Files (x86)\checkmk\service\cmk-agent-ctl.exe" register --hostname $env:COMPUTERNAME --server 192.168.43.100:8000 --site cmk --user cmkadmin
```

---

*Dokumentasi ini dikelola dan disinkronkan secara berkala mengikuti perkembangan infrastruktur monitoring Checkmk Community Edition v2.5.0.*
