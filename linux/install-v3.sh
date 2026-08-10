#!/usr/bin/env bash
# ==============================================================================
# Script Name    : install-v3.sh
# Description    : Automatic Checkmk Agent Deployer with Dynamic Server Config
# Language       : Bash
# Support OS     : Ubuntu/Debian
# ==============================================================================

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Script ini harus dijalankan sebagai root (gunakan sudo)."
    exit 1
fi

# Default values
SERVER_IP=""
SITE_ID="monitoring"
GITHUB_REPO="username/checkmk-agent-deploy"

# Function to display help
show_help() {
    echo "Penggunaan: sudo bash install-v3.sh [pilihan]"
    echo ""
    echo "Pilihan:"
    echo "  -s, --server IP      IP Address atau Hostname Server Checkmk (Wajib jika non-interaktif)"
    echo "  -d, --site SITE      Site ID dari Checkmk Server (Default: monitoring)"
    echo "  -g, --github REPO    Nama repositori GitHub Anda (Default: username/checkmk-agent-deploy)"
    echo "  -h, --help           Menampilkan bantuan ini"
    echo ""
    echo "Contoh penggunaan satu baris (Piped Curl):"
    echo "  curl -sSL https://raw.githubusercontent.com/.../install-v3.sh | sudo bash -s -- -s 192.168.1.100 -d monitoring"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--server)
            SERVER_IP="$2"
            shift 2
            ;;
        -d|--site)
            SITE_ID="$2"
            shift 2
            ;;
        -g|--github)
            GITHUB_REPO="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "[ERROR] Pilihan tidak dikenal: $1"
            show_help
            exit 1
            ;;
    esac
done

# If SERVER_IP is not provided, try to get it interactively
if [ -z "$SERVER_IP" ]; then
    # Check if we are running in an interactive terminal (TTY)
    if [ -t 0 ]; then
        echo "===================================================="
        echo "           KONFIGURASI SERVER CHECKMK               "
        echo "===================================================="
        read -p "Masukkan IP Address / Hostname Server Checkmk: " SERVER_IP
        read -p "Masukkan Site ID Checkmk [Default: $SITE_ID]: " TEMP_SITE
        if [ -n "$TEMP_SITE" ]; then
            SITE_ID="$TEMP_SITE"
        fi
        read -p "Masukkan Repositori GitHub [Default: $GITHUB_REPO]: " TEMP_REPO
        if [ -n "$TEMP_REPO" ]; then
            GITHUB_REPO="$TEMP_REPO"
        fi
        echo "===================================================="
    else
        # If running via piped curl (stdin is not TTY), read directly from /dev/tty
        # This prevents 'read' from consuming the script's own body from the pipe!
        if [ -c /dev/tty ]; then
            echo "====================================================" > /dev/tty
            echo "     KONFIGURASI SERVER CHECKMK (INTERAKTIF TTY)    " > /dev/tty
            echo "====================================================" > /dev/tty
            
            # Prompt to tty, read from tty
            echo -n "Masukkan IP Address / Hostname Server Checkmk: " > /dev/tty
            read -r SERVER_IP < /dev/tty
            
            echo -n "Masukkan Site ID Checkmk [Default: $SITE_ID]: " > /dev/tty
            read -r TEMP_SITE < /dev/tty
            if [ -n "$TEMP_SITE" ]; then
                SITE_ID="$TEMP_SITE"
            fi
            
            echo -n "Masukkan Repositori GitHub [Default: $GITHUB_REPO]: " > /dev/tty
            read -r TEMP_REPO < /dev/tty
            if [ -n "$TEMP_REPO" ]; then
                GITHUB_REPO="$TEMP_REPO"
            fi
            echo "====================================================" > /dev/tty
        else
            echo "[ERROR] IP address / hostname server checkmk wajib diisi!"
            echo "Gunakan opsi -s <IP> jika menjalankan script dalam mode non-interaktif."
            exit 1
        fi
    fi
fi

# Final validation to ensure server IP is not empty
if [ -z "$SERVER_IP" ]; then
    echo "[ERROR] IP address / hostname server checkmk wajib diisi!"
    exit 1
fi

echo "[INFO] Memulai instalasi agen Checkmk..."
echo "  - Server IP  : $SERVER_IP"
echo "  - Site ID    : $SITE_ID"
echo "  - GitHub Repo: $GITHUB_REPO"

# Update package list and install dependencies
echo "[INFO] Memasang dependensi sistem (smartmontools, memtester, lm-sensors, jq, bc)..."
apt-get update -y && apt-get install -y curl smartmontools memtester lm-sensors jq bc

# Download and install Checkmk Agent from server
echo "[INFO] Mengunduh Agen Checkmk dari Server ($SERVER_IP)..."
AGENT_URL="http://${SERVER_IP}/${SITE_ID}/check_mk/agents/check-mk-agent_all.deb"
curl -sSL -o /tmp/check-mk-agent_all.deb "$AGENT_URL"

if [ $? -ne 0 ] || [ ! -f /tmp/check-mk-agent_all.deb ] || [ ! -s /tmp/check-mk-agent_all.deb ]; then
    echo "[ERROR] Gagal mengunduh agen dari server. Periksa apakah server dan Site ID sudah benar dan aktif."
    exit 1
fi

echo "[INFO] Memasang paket Agen Checkmk..."
dpkg -i /tmp/check-mk-agent_all.deb || apt-get install -f -y

# Setup Local Checks
echo "[INFO] Menyiapkan folder local checks..."
LOCAL_DIR="/usr/lib/check_mk_agent/local"
mkdir -p "$LOCAL_DIR"

echo "[INFO] Mengunduh script kustom monitoring dari GitHub..."
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/main/linux/local_checks"

curl -sSL -o "${LOCAL_DIR}/cpu_os_info.sh" "${GITHUB_RAW}/cpu_os_info.sh"
curl -sSL -o "${LOCAL_DIR}/ram_health.sh" "${GITHUB_RAW}/ram_health.sh"
curl -sSL -o "${LOCAL_DIR}/disk_nvme_health.sh" "${GITHUB_RAW}/disk_nvme_health.sh"
curl -sSL -o "${LOCAL_DIR}/remote_apps.sh" "${GITHUB_RAW}/remote_apps.sh"

# Make all local check scripts executable
chmod +x ${LOCAL_DIR}/*.sh

# Setup Asynchronous Memtester (RAM Health)
echo "[INFO] Menyiapkan pengujian RAM asinkron (Memtester)..."
mkdir -p /var/log/checkmk_custom
mkdir -p /usr/local/bin

cat << 'EOF' > /usr/local/bin/run_memtester.sh
#!/usr/bin/env bash
# Script Pengujian RAM Berkala untuk Checkmk
LOG_FILE="/var/log/checkmk_custom/memtester_health.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "=== MEMTESTER START: $(date) ===" > "$LOG_FILE"
# Melakukan uji coba sampling RAM 128MB sebanyak 1 putaran
if memtester 128M 1 >> "$LOG_FILE" 2>&1; then
    echo "STATUS: SUCCESS" >> "$LOG_FILE"
else
    echo "STATUS: FAILED" >> "$LOG_FILE"
fi
echo "=== MEMTESTER END: $(date) ===" >> "$LOG_FILE"
EOF

chmod +x /usr/local/bin/run_memtester.sh

# Register Cron Job (Setiap tanggal 1 dan 15 pukul 02:00 pagi)
echo "[INFO] Mendaftarkan jadwal Cron Job untuk pengujian RAM..."
(crontab -l 2>/dev/null | grep -v "run_memtester.sh"; echo "0 2 1,15 * * /usr/local/bin/run_memtester.sh") | crontab -

# Run memtester for the first time in background to generate initial log
echo "[INFO] Menjalankan pengujian RAM pertama di latar belakang..."
/usr/local/bin/run_memtester.sh &

echo "[SUCCESS] Instalasi dan konfigurasi agen Checkmk selesai dijalankan!"
