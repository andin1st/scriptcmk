#!/usr/bin/env bash
# ==============================================================================
# CHECKMK CLIENT DEPLOYMENT BOOTSTRAP SCRIPT (Linux - v5)
# ==============================================================================
# Deskripsi: Script otomatis untuk menginstal Checkmk Agent, mengonfigurasi
#            local checks, dan membuat cron job untuk pengujian RAM asinkron.
#            Mendukung parameter dinamis dan input interaktif aman dari pipa curl.
# ==============================================================================

set -e

# Warna untuk output terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}     Checkmk Client Automation Deployment (v5)       ${NC}"
echo -e "${BLUE}=====================================================${NC}"

# 1. Pastikan dijalankan sebagai root/sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Script ini harus dijalankan menggunakan sudo atau sebagai root!${NC}"
    exit 1
fi

# 2. Inisialisasi Nilai Default Parameter
SERVER_IP=""
SITE_ID="cmk"
AGENT_VERSION="2.5.0p9-1"
GITHUB_REPO="andin1st/scriptcmk"

# Fungsi Menampilkan Bantuan Penggunaan
show_help() {
    echo "Penggunaan: sudo bash install-v5.sh [OPSI]"
    echo ""
    echo "Opsi:"
    echo "  -s, --server IP_SERVER       IP Address atau Hostname Server Checkmk (Wajib)"
    echo "  -d, --site SITE_ID           Site ID Checkmk (Default: monitoring)"
    echo "  -v, --version VERSION        Versi Agen Checkmk (Default: 2.5.0p9-1)"
    echo "  -g, --github GITHUB_REPO     Repositori GitHub Anda (Default: username/checkmk-agent-deploy)"
    echo "  -h, --help                   Menampilkan bantuan ini"
    echo ""
}

# Parsing Argumen CLI
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
        -v|--version)
            AGENT_VERSION="$2"
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
            echo -e "${RED}[ERROR] Parameter tidak dikenal: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# 3. Input Interaktif jika parameter kosong (Aman dari pipa curl via /dev/tty)
if [ -z "$SERVER_IP" ]; then
    echo -e "${YELLOW}--- Konfigurasi Server Checkmk ---${NC}"
    echo -ne "${YELLOW}Masukkan IP Address atau Hostname Server Checkmk: ${NC}"
    read -r SERVER_IP < /dev/tty
    
    if [ -z "$SERVER_IP" ]; then
        echo -e "${RED}[ERROR] IP address / Hostname server Checkmk wajib diisi!${NC}"
        exit 1
    fi
fi

# Tanya jawab interaktif opsional jika dijalankan tanpa argumen sama sekali
if [ $# -eq 0 ] && [ -z "$1" ]; then
    echo -ne "${YELLOW}Masukkan Site ID Checkmk [Default: $SITE_ID]: ${NC}"
    read -r input_site < /dev/tty
    [ ! -z "$input_site" ] && SITE_ID="$input_site"

    echo -ne "${YELLOW}Masukkan Versi Agen Checkmk [Default: $AGENT_VERSION]: ${NC}"
    read -r input_ver < /dev/tty
    [ ! -z "$input_ver" ] && AGENT_VERSION="$input_ver"

    echo -ne "${YELLOW}Masukkan Repositori GitHub Anda [Default: $GITHUB_REPO]: ${NC}"
    read -r input_git < /dev/tty
    [ ! -z "$input_git" ] && GITHUB_REPO="$input_git"
fi

echo -e "\n${GREEN}[INFO] Menjalankan instalasi dengan parameter:${NC}"
echo -e "  - Server Checkmk: ${BLUE}$SERVER_IP${NC}"
echo -e "  - Site ID:        ${BLUE}$SITE_ID${NC}"
echo -e "  - Versi Agen:     ${BLUE}$AGENT_VERSION${NC}"
echo -e "  - Repositori Git: ${BLUE}$GITHUB_REPO${NC}"

# 4. Instalasi Dependensi Lokal
echo -e "\n${YELLOW}[1/6] Memperbarui paket dan memasang dependensi...${NC}"
apt-get update -qq
apt-get install -y -qq curl smartmontools memtester lm-sensors jq bc >/dev/null 2>&1

# 5. Unduh dan Instal Agen Checkmk dari Server Lokal secara Dinamis
echo -e "${YELLOW}[2/6] Mengunduh Agen Checkmk versi $AGENT_VERSION dari server...${NC}"
DOWNLOAD_URL="http://${SERVER_IP}/${SITE_ID}/check_mk/agents/check-mk-agent_${AGENT_VERSION}_all.deb"
DEB_PATH="/tmp/check-mk-agent_${AGENT_VERSION}_all.deb"

# Gunakan -f pada curl agar langsung gagal jika server mengembalikan 404
if curl -sSfgL -o "$DEB_PATH" "$DOWNLOAD_URL"; then
    echo -e "${GREEN}[OK] Berhasil mengunduh file agen .deb.${NC}"
else
    echo -e "${RED}[ERROR] Gagal mengunduh Agen Checkmk dari $DOWNLOAD_URL${NC}"
    echo -e "${RED}Silakan pastikan:${NC}"
    echo -e "  1. Server Checkmk Anda aktif dan dapat diakses dari client ini."
    echo -e "  2. Versi Agen '$AGENT_VERSION' terdaftar di server."
    echo -e "  3. Site ID '$SITE_ID' sudah benar."
    exit 1
fi

# Validasi Integritas File Debian
if ! dpkg-deb -I "$DEB_PATH" >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] File yang diunduh bukan merupakan arsip Debian (.deb) yang valid!${NC}"
    echo -e "${RED}Isi file yang diunduh kemungkinan besar adalah halaman error HTML 404 dari web server.${NC}"
    rm -f "$DEB_PATH"
    exit 1
fi

echo -e "${YELLOW}[3/6] Menginstal Agen Checkmk...${NC}"
dpkg -i "$DEB_PATH" || apt-get install -f -y -qq
rm -f "$DEB_PATH"

# 6. Setup Direktori Local Checks
echo -e "${YELLOW}[4/6] Menyiapkan direktori local checks...${NC}"
LOCAL_DIR="/usr/lib/check_mk_agent/local"
mkdir -p "$LOCAL_DIR"

# Daftar script local checks yang akan diunduh dari GitHub
SCRIPTS=("cpu_os_info.sh" "ram_health.sh" "disk_nvme_health.sh" "remote_apps.sh" "battery_health.sh")

for script in "${SCRIPTS[@]}"; do
    echo -e "  - Mengunduh script: $script"
    SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/linux/local_checks/${script}"
    
    # Gunakan -f agar curl tidak menulis file sampah 404 jika file tidak ada di Git
    if curl -sSfgL -o "${LOCAL_DIR}/${script}" "$SCRIPT_URL"; then
        chmod +x "${LOCAL_DIR}/${script}"
        echo -e "    ${GREEN}[OK] Berhasil diunduh dan dikonfigurasi.${NC}"
    else
        echo -e "    ${RED}[WARNING] Gagal mengunduh '$script' dari GitHub (404 Not Found).${NC}"
        echo -e "    Pastikan file tersebut ada di branch 'main' dalam folder 'linux/local_checks/' di repositori Anda."
    fi
done

# 7. Setup Script Memtester Asinkron dengan Output Ukuran RAM Dinamis (v5)
echo -e "${YELLOW}[5/6] Menyiapkan script runner memtester asinkron...${NC}"
RUNNER_PATH="/usr/local/bin/run_memtester.sh"
LOG_DIR="/var/log/checkmk_custom"
LOG_FILE="$LOG_DIR/memtester_health.log"

mkdir -p "$LOG_DIR"

# Buat berkas run_memtester.sh secara dinamis
cat << 'EOF' > "$RUNNER_PATH"
#!/usr/bin/env bash
# ==============================================================================
# Script Runner Memtester Asinkron (v5)
# Menghitung 20% dari Sisa RAM Bebas dan Mencatat Ukuran ke Log untuk Checkmk
# ==============================================================================

LOG_DIR="/var/log/checkmk_custom"
LOG_FILE="$LOG_DIR/memtester_health.log"
mkdir -p "$LOG_DIR"

echo "=== MEMTESTER START: $(date) ===" > "$LOG_FILE"

# 1. Hitung 20% dari Free RAM saat ini (dalam satuan Megabytes)
FREE_RAM=$(free -m | awk '/^Mem:/{print $4}')
SAMPLE_MB=$(( FREE_RAM * 20 / 100 ))

# 2. Atur batas minimal pengujian agar diagnostik bermakna (Default: 128MB)
if [ $SAMPLE_MB -lt 128 ]; then
    SAMPLE_MB=128
fi

# 3. Catat SAMPLE_SIZE ke dalam log agar dapat dibaca secara presisi oleh ram_health.sh
echo "SAMPLE_SIZE: ${SAMPLE_MB}M" >> "$LOG_FILE"
echo "Menjalankan memtester dengan sample ukuran ${SAMPLE_MB}MB..." >> "$LOG_FILE"

# 4. Jalankan memtester sebanyak 1 putaran (loop) agar tidak mengunci RAM terlalu lama
if memtester "${SAMPLE_MB}M" 1 >> "$LOG_FILE" 2>&1; then
    echo "STATUS: SUCCESS" >> "$LOG_FILE"
else
    echo "STATUS: FAILED" >> "$LOG_FILE"
fi

echo "=== MEMTESTER END: $(date) ===" >> "$LOG_FILE"
EOF

chmod +x "$RUNNER_PATH"

# 8. Konfigurasi Cron Job untuk Menjalankan Tes RAM Setiap 2 Minggu
echo -e "${YELLOW}[6/6] Mengonfigurasi Cron Job untuk pengujian RAM berkala...${NC}"
CRON_JOB="0 2 1,15 * * $RUNNER_PATH > /dev/null 2>&1"

# Hindari duplikasi cron job
(crontab -l 2>/dev/null | grep -Fv "$RUNNER_PATH"; echo "$CRON_JOB") | crontab -

# Jalankan pengujian RAM pertama kali di background agar langsung memproduksi log awal
echo -e "${GREEN}[INFO] Menjalankan inisialisasi awal pengujian RAM di latar belakang...${NC}"
nohup "$RUNNER_PATH" >/dev/null 2>&1 &

echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}      PROSES INSTALASI AUTOMATION SELESAI!            ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo -e "Pastikan Anda memeriksa status pemantauan di GUI Checkmk server."
echo -e "Log pengujian RAM awal dapat Anda pantau di: $LOG_FILE"
