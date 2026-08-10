#!/usr/bin/env bash
# ==============================================================================
# Script Name    : install-v4.sh
# Description    : Automated Checkmk Agent Installer with Dynamic Version Support
# Compatibility  : Ubuntu / Debian (Targeted for Ubuntu 26 / Checkmk 2.5)
# ==============================================================================

# Exit immediately on unhandled errors
set -e

# --- Default Variables ---
DEFAULT_SITE="monitoring"
DEFAULT_GITHUB="username/checkmk-agent-deploy"
DEFAULT_VERSION="2.5.0p9-1"  # Default ke versi stabil 2.5 yang Anda miliki
GITHUB_REPO=""
SERVER_IP=""
SITE_ID=""
AGENT_VERSION=""

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "\e[1;31m[ERROR] Script ini harus dijalankan sebagai root (gunakan sudo)!\e[0m"
    exit 1
fi

# --- Help Menu ---
show_help() {
    echo "Penggunaan: sudo bash install-v4.sh [OPTIONS]"
    echo ""
    echo "Pilihan:"
    echo "  -s, --server IP/HOST     IP Address atau Hostname server Checkmk (Wajib)"
    echo "  -d, --site SITE_ID       Site ID Checkmk (Default: $DEFAULT_SITE)"
    echo "  -v, --version VERSION    Versi spesifik agen Checkmk (Default: $DEFAULT_VERSION)"
    echo "  -g, --github REPO        Repositori GitHub kustom (Format: 'user/repo')"
    echo "  -h, --help               Menampilkan bantuan ini"
    echo ""
    exit 0
}

# --- Parse Arguments ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--server) SERVER_IP="$2"; shift ;;
        -d|--site) SITE_ID="$2"; shift ;;
        -v|--version) AGENT_VERSION="$2"; shift ;;
        -g|--github) GITHUB_REPO="$2"; shift ;;
        -h|--help) show_help ;;
        *) echo "[WARNING] Parameter tidak dikenal: $1"; show_help ;;
    esac
    shift
done

# --- Interactive Prompts (Fallback) ---
# Jika dijalankan dari curl pipe, pastikan membaca dari /dev/tty agar tidak merusak eksekusi bash
if [ -z "$SERVER_IP" ]; then
    echo -e "\e[1;34m--- Konfigurasi Server Checkmk ---\e[0m"
    echo -n "Masukkan IP Address atau Hostname Server Checkmk: "
    read -r SERVER_IP < /dev/tty
fi

# Validasi akhir IP Server
if [ -z "$SERVER_IP" ]; then
    echo -e "\e[1;31m[ERROR] IP address / hostname server Checkmk wajib diisi!\e[0m"
    exit 1
fi

if [ -z "$SITE_ID" ]; then
    echo -n "Masukkan Site ID Checkmk [Default: $DEFAULT_SITE]: "
    read -r SITE_ID < /dev/tty
    SITE_ID="${SITE_ID:-$DEFAULT_SITE}"
fi

if [ -z "$AGENT_VERSION" ]; then
    echo -n "Masukkan Versi Agen Checkmk [Default: $DEFAULT_VERSION]: "
    read -r AGENT_VERSION < /dev/tty
    AGENT_VERSION="${AGENT_VERSION:-$DEFAULT_VERSION}"
fi

if [ -z "$GITHUB_REPO" ]; then
    GITHUB_REPO="$DEFAULT_GITHUB"
fi

echo -e "\e[1;32m"
echo "====================================================="
echo "  MEMULAI INSTALASI & KONFIGURASI AGEN CHECKMK"
echo "====================================================="
echo "Server IP    : $SERVER_IP"
echo "Site ID      : $SITE_ID"
echo "Agent Version: $AGENT_VERSION"
echo "GitHub Repo  : $GITHUB_REPO"
echo "====================================================="
echo -e "\e[0m"

# --- Step 1: Install Dependencies ---
echo -e "\e[1;34m[1/5] Memasang dependensi sistem (smartmontools, memtester, lm-sensors, jq)...\e[0m"
apt-get update -qq
apt-get install -y -qq curl smartmontools memtester lm-sensors jq bc < /dev/null

# --- Step 2: Download & Install Checkmk Agent Safely ---
echo -e "\e[1;34m[2/5] Mengunduh agen Checkmk dari server...\e[0m"

# URL Alternatif untuk menghindari error 404/download HTML
URL_VERSIONED="http://${SERVER_IP}/${SITE_ID}/check_mk/agents/check-mk-agent_${AGENT_VERSION}_all.deb"
URL_GENERIC="http://${SERVER_IP}/${SITE_ID}/check_mk/agents/check-mk-agent_all.deb"

DOWNLOAD_SUCCESS=false
TEMP_DEB="/tmp/check-mk-agent_all.deb"

# Hapus sisa file lama jika ada
rm -f "$TEMP_DEB"

# Percobaan 1: Mengunduh versi spesifik (Direkomendasikan)
echo "Mencoba mengunduh: $URL_VERSIONED"
if curl -sSf -o "$TEMP_DEB" "$URL_VERSIONED"; then
    DOWNLOAD_SUCCESS=true
else
    echo -e "\e[1;33m[WARN] Gagal mengunduh versi spesifik. Mencoba mengunduh file generic...\e[0m"
    # Percobaan 2: Mengunduh link generic
    echo "Mencoba mengunduh: $URL_GENERIC"
    if curl -sSf -o "$TEMP_DEB" "$URL_GENERIC"; then
        DOWNLOAD_SUCCESS=true
    fi
fi

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo -e "\e[1;31m[ERROR] Gagal mengunduh agen Checkmk dari server!\e[0m"
    echo "Silakan periksa:"
    echo "1. Apakah IP Server ($SERVER_IP) dan Site ID ($SITE_ID) sudah benar?"
    echo "2. Apakah Anda bisa mengakses URL berikut dari browser Anda:"
    echo "   - $URL_VERSIONED"
    echo "   - $URL_GENERIC"
    exit 1
fi

# Validasi format file deb (memastikan bukan HTML 404 tersembunyi)
if ! dpkg-deb -I "$TEMP_DEB" >/dev/null 2>&1; then
    echo -e "\e[1;31m[ERROR] Berkas yang diunduh bukan berkas Debian (.deb) yang valid!\e[0m"
    echo "Isi file yang diunduh kemungkinan besar adalah halaman error HTML 404 dari web server."
    echo "Harap pastikan versi '$AGENT_VERSION' terpasang dan tersedia di server Checkmk Anda."
    rm -f "$TEMP_DEB"
    exit 1
fi

echo "Menginstal paket agen Checkmk..."
dpkg -i "$TEMP_DEB" || apt-get install -f -y -qq

# Bersihkan berkas installer setelah selesai
rm -f "$TEMP_DEB"

# --- Step 3: Setup Local Checks dari GitHub ---
echo -e "\e[1;34m[3/5] Mengunduh script pemantauan kustom (Local Checks) dari GitHub...\e[0m"
LOCAL_DIR="/usr/lib/check_mk_agent/local"
mkdir -p "$LOCAL_DIR"

SCRIPTS=("cpu_os_info.sh" "ram_health.sh" "disk_nvme_health.sh" "remote_apps.sh")

for script in "${SCRIPTS[@]}"; do
    SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/linux/local_checks/${script}"
    echo "Mengunduh: $script..."
    if curl -sSf -o "${LOCAL_DIR}/${script}" "$SCRIPT_URL"; then
        chmod +x "${LOCAL_DIR}/${script}"
        echo -e "\e[1;32m  [OK] $script berhasil dipasang.\e[0m"
    else
        echo -e "\e[1;31m  [FAIL] Gagal mengunduh $script dari GitHub!\e[0m"
    fi
done

# --- Step 4: Setup Penjadwalan RAM Health (Memtester) ---
echo -e "\e[1;34m[4/5] Mengonfigurasi pengujian RAM asinkron (Cron Job 2 mingguan)...\e[0m"
LOG_DIR="/var/log/checkmk_custom"
mkdir -p "$LOG_DIR"

# Buat script eksekusi memtester asinkron
CRON_SCRIPT="/usr/local/bin/run_memtester.sh"
cat << 'EOF' > "$CRON_SCRIPT"
#!/usr/bin/env bash
# Menghitung alokasi RAM yang aman (sekitar 20% dari total RAM gratis atau max 2GB agar aman)
FREE_MEM_KB=$(grep MemFree /proc/meminfo | awk '{print $2}')
ALLOC_MB=$(( FREE_MEM_KB / 1024 / 5 ))
if [ "$ALLOC_MB" -gt 2048 ]; then ALLOC_MB=2048; fi
if [ "$ALLOC_MB" -lt 128 ]; then ALLOC_MB=128; fi

LOG_FILE="/var/log/checkmk_custom/memtester_health.log"
mkdir -p /var/log/checkmk_custom

echo "=== MEMTESTER START: $(date) ===" > "$LOG_FILE"
# Menjalankan memtester dengan 1 run sample
if memtester ${ALLOC_MB}M 1 >> "$LOG_FILE" 2>&1; then
    echo "STATUS: SUCCESS" >> "$LOG_FILE"
else
    echo "STATUS: FAILED" >> "$LOG_FILE"
fi
echo "=== MEMTESTER END: $(date) ===" >> "$LOG_FILE"
EOF

chmod +x "$CRON_SCRIPT"

# Daftarkan ke Cron (setiap tanggal 1 dan 15 pukul 02:00 pagi)
CRON_JOB="0 2 1,15 * * $CRON_SCRIPT"
(crontab -l 2>/dev/null | grep -Fv "$CRON_SCRIPT"; echo "$CRON_JOB") | crontab -

# Jalankan pengujian pertama kali di background agar langsung ada data log awal
echo "Menjalankan inisialisasi pengujian RAM pertama di latar belakang..."
nohup "$CRON_SCRIPT" >/dev/null 2>&1 &

# --- Step 5: Finalisasi ---
echo -e "\e[1;34m[5/5] Memverifikasi status agen...\e[0m"
if systemctl is-active --quiet check-mk-agent.socket; then
    echo -e "\e[1;32m  [OK] Socket Agen Checkmk aktif dan mendengarkan port 6556!\e[0m"
else
    # Mencoba restart socket jika belum aktif
    systemctl restart check-mk-agent.socket || true
fi

echo -e "\e[1;32m"
echo "====================================================="
echo "             PROSES INSTALASI SELESAI!"
echo "====================================================="
echo " Agen Checkmk berhasil dikonfigurasi."
echo " Pastikan Anda mendaftarkan host ini di server"
echo " Checkmk Anda dan lakukan 'Service Discovery'."
echo "====================================================="
echo -e "\e[0m"
