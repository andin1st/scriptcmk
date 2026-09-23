#!/usr/bin/env bash
# =====================================================================
# Auto-Installer: Docker, Dockge, & Checkmk Community Edition Server Stack
# Multi-Distro (Ubuntu/Debian, RHEL/Fedora/CentOS)
# =====================================================================

set -e

# 1. Ensure script is run with sudo / root
if [ "$EUID" -ne 0 ]; then
    echo -e "\e[31m[ERROR] Script ini HARUS dijalankan sebagai root / sudo!\e[0m"
    exit 1
fi

echo -e "\e[36m=== Memulai Pemasangan Otomatis Docker Engine, Dockge, dan Checkmk Community Edition Server ===\e[0m"

# 2. Install Docker jika belum terpasang
if ! command -v docker &> /dev/null; then
    echo -e "\e[33m[-] Docker belum terdeteksi. Memulai instalasi Docker Engine...\e[0m"
    curl -fsSL https://get.docker.com | sh
    echo -e "\e[32m[OK] Docker Engine berhasil terinstal.\e[0m"
else
    echo -e "\e[32m[OK] Docker Engine sudah terpasang di sistem.\e[0m"
fi

# 3. Aktifkan dan jalankan Service Docker agar Otomatis Berjalan saat Booting (Systemd Auto-Start)
echo -e "\e[33m[-] Memastikan service Docker dikonfigurasi auto-start pada booting sistem...\e[0m"
systemctl enable docker
systemctl start docker
echo -e "\e[32m[OK] Service Docker diaktifkan (Auto-start: ENABLED).\e[0m"

# 4. Siapkan Struktur Direktori Dockge & Stacks
echo -e "\e[33m[-] Menyiapkan struktur direktori /opt/dockge dan /opt/dockge/stacks...\e[0m"
mkdir -p /opt/dockge/data
mkdir -p /opt/dockge/stacks/checkmk

# 5. Buat Konfigurasi Docker Compose untuk Dockge (/opt/dockge/compose.yaml)
echo -e "\e[33m[-] Membuat berkas Docker Compose untuk Dockge...\e[0m"
cat << 'EOF' > /opt/dockge/compose.yaml
version: "3.8"
services:
  dockge:
    image: louislam/dockge:1
    container_name: dockge
    restart: always
    ports:
      - "5001:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/dockge/data:/app/data
      - /opt/dockge/stacks:/opt/dockge/stacks
    environment:
      - DOCKGE_STACKS_DIR=/opt/dockge/stacks
EOF

# 6. Buat Konfigurasi Docker Compose untuk Checkmk Community Edition Server (/opt/dockge/stacks/checkmk/compose.yaml)
echo -e "\e[33m[-] Membuat berkas Docker Compose untuk Checkmk Community Edition Server...\e[0m"
cat << 'EOF' > /opt/dockge/stacks/checkmk/compose.yaml
version: "3.8"
services:
  checkmk:
    image: checkmk/check-mk-raw:2.5.0-latest
    container_name: checkmk-server
    restart: always
    ports:
      - "8080:5000"  # Web GUI Checkmk Community Edition
      - "8000:8000"  # Agent Controller TLS Registration
    environment:
      - CMK_PASSWORD=cmkadmin
      - CMK_SITE_ID=cmk
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - checkmk-data:/opt/omd/sites

volumes:
  checkmk-data:
    driver: local
EOF

# 7. Eksekusi Pemasangan Kontainer via Docker Compose
echo -e "\e[33m[-] Menjalankan kontainer Dockge (Port 5001)...\e[0m"
docker compose -f /opt/dockge/compose.yaml up -d

echo -e "\e[33m[-] Menjalankan kontainer Checkmk Community Edition Server (Port 8080 & 8000)...\e[0m"
docker compose -f /opt/dockge/stacks/checkmk/compose.yaml up -d

# 8. Dapatkan IP Server Lokal
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="<IP_SERVER_ANDA>"
fi

echo -e "\n\e[32m=====================================================================\e[0m"
echo -e "\e[32m  PROSES PEMASANGAN SELESAI & DOCKER AUTO-START AKTIF!\e[0m"
echo -e "\e[32m=====================================================================\e[0m"
echo -e "\e[36m1. Dockge Stack Manager:\e[0m"
echo -e "   URL      : http://${SERVER_IP}:5001"
echo -e "\e[36m2. Checkmk Community Edition Dashboard:\e[0m"
echo -e "   URL      : http://${SERVER_IP}:8080/cmk"
echo -e "   Username : cmkadmin"
echo -e "   Password : cmkadmin"
echo -e "\e[36m3. Checkmk Agent Registration Port:\e[0m"
echo -e "   Port TLS : ${SERVER_IP}:8000"
echo -e "\e[32m=====================================================================\e[0m\n"
