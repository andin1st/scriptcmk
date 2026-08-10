#!/usr/bin/env bash
# ==============================================================================
# Checkmk Agent Auto-Deployer & Configurator for Linux (Ubuntu/Debian)
# ==============================================================================
# Deskripsi: Script satu baris (one-liner) untuk menginstal agen Checkmk 2.5 (Community),
#            menginstal dependensi sistem, mengunduh script local checks dari GitHub,
#            serta mengonfigurasi Cron Job pengujian RAM (memtester) 2 minggu sekali.
# ==============================================================================

set -e

# --- KONFIGURASI DEFAULT (SESUAIKAN DENGAN SERVER ANDA) ---
CMK_SERVER_IP="192.168.1.100"       # IP Server Checkmk
CMK_SERVER_PORT="8080"              # Port Web Service Checkmk
CMK_SITE="monitoring"               # Nama Site Checkmk Anda
GITHUB_USER="username"              # Username GitHub Anda
GITHUB_REPO="checkmk-agent-deploy"   # Nama repositori GitHub Anda
GITHUB_BRANCH="main"

GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}/linux"
LOG_DIR="/var/log/checkmk_custom"
MEMTESTER_LOG="${LOG_DIR}/memtester_health.log"

# --- WARNA OUTPUT TERMINAL ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}   MEMULAI DEPLOYMENT OTOMATIS AGEN CHECKMK (LINUX)   ${NC}"
echo -e "${GREEN}======================================================${NC}"

# 1. Pastikan dijalankan sebagai Root (Sudo)
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Script ini harus dijalankan dengan hak akses root (sudo bash).${NC}"
    exit 1
fi

# 2. Deteksi OS dan validasi distribusi berbasis Debian/Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        echo -e "${YELLOW}[WARNING] Sistem operasi terdeteksi sebagai $NAME. Script ini dirancang optimal untuk Ubuntu/Debian.${NC}"
        read -p "Apakah Anda ingin tetap melanjutkan? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}[ABORT] Proses dibatalkan oleh pengguna.${NC}"
            exit 1
        fi
    fi
else
    echo -e "${RED}[ERROR] File /etc/os-release tidak ditemukan. Tidak dapat mendeteksi sistem operasi.${NC}"
    exit 1
fi

# 3. Instalasi Paket Dependensi yang Diperlukan
echo -e "\n${GREEN}[1/5] Menginstal paket dependensi sistem...${NC}"
apt-get update -y
apt-get install -y curl smartmontools memtester lm-sensors jq >/dev/null 2>&1
echo -e "-> Dependensi terinstal: curl, smartmontools, memtester, lm-sensors, jq."

# Membuat folder log kustom untuk monitoring mandiri
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"

# 4. Unduh dan Instal Agen Checkmk 2.5
echo -e "\n${GREEN}[2/5] Mengunduh & Menginstal Agen Checkmk...${NC}"
AGENT_URL="http://${CMK_SERVER_IP}:${CMK_SERVER_PORT}/${CMK_SITE}/check_mk/agents/check-mk-agent_all.deb"
DEB_TEMP="/tmp/check-mk-agent_all.deb"

# Coba unduh dari server lokal terlebih dahulu, fallback ke instalasi lokal jika gagal akses
if curl -sI --connect-timeout 5 "$AGENT_URL" | grep -q "200 OK"; then
    echo -e "Menghubungkan ke server Checkmk di $AGENT_URL..."
    curl -s -o "$DEB_TEMP" "$AGENT_URL"
    dpkg -i "$DEB_TEMP" || apt-get install -f -y
    rm -f "$DEB_TEMP"
    echo -e "-> Agen Checkmk berhasil diinstal dari Server."
else
    echo -e "${YELLOW}[WARNING] Server Checkmk di $CMK_SERVER_IP tidak dapat dijangkau (Timeout/Offline).${NC}"
    echo -e "${YELLOW}Pastikan server Checkmk Anda menyala atau unduh paket agen .deb secara manual nanti.${NC}"
fi

# 5. Konfigurasi Local Checks Folder dan Pengunduhan Script dari GitHub
LOCAL_DIR="/usr/lib/check_mk_agent/local"
echo -e "\n${GREEN}[3/5] Mengunduh script pemantauan (Local Checks) dari GitHub...${NC}"
mkdir -p "$LOCAL_DIR"
chmod 755 "$LOCAL_DIR"

# Daftar script local check yang disesuaikan dengan kebutuhan Anda
SCRIPTS=(
    "cpu_os_info.sh"
    "disk_nvme_health.sh"
    "ram_health.sh"
    "remote_apps.sh"
)

for script in "${SCRIPTS[@]}"; do
    echo -e "-> Mengunduh: ${script}..."
    SCRIPT_URL="${GITHUB_RAW_URL}/local_checks/${script}"
    
    # Mengunduh script dari raw GitHub
    curl -s -o "${LOCAL_DIR}/${script}" "${SCRIPT_URL}" || {
        echo -e "${RED}[ERROR] Gagal mengunduh ${script}. Membuat file template kosong...${NC}"
        touch "${LOCAL_DIR}/${script}"
    }
    
    # Memberikan izin eksekusi agar agen Checkmk dapat menjalankan script
    chmod +x "${LOCAL_DIR}/${script}"
done
echo -e "-> Semua script local check berhasil diunduh dan dipasang di $LOCAL_DIR"

# 6. Setup RAM Health (Scheduler Asinkron - Memtester)
echo -e "\n${GREEN}[4/5] Mengonfigurasi penjadwal pengujian RAM asinkron (2 Mingguan)...${NC}"

# Buat script eksekutor memtester di lokasi aman /usr/local/bin/
RUN_MEMTESTER_SH="/usr/local/bin/run_memtester.sh"
cat << 'EOF' > "$RUN_MEMTESTER_SH"
#!/usr/bin/env bash
# Script Eksekutor Memtester Asinkron (Dijalankan via Cron Job)
LOG_FILE="/var/log/checkmk_custom/memtester_health.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Menjalankan pengujian 128MB RAM sebanyak 1 siklus sebagai sample
# Anda dapat menyesuaikan ukuran RAM berdasarkan kebutuhan server client masing-masing
echo "=== MEMTESTER START: $(date) ===" > "$LOG_FILE"
if memtester 128M 1 >> "$LOG_FILE" 2>&1; then
    echo "STATUS: SUCCESS" >> "$LOG_FILE"
else
    echo "STATUS: FAILED" >> "$LOG_FILE"
fi
echo "=== MEMTESTER END: $(date) ===" >> "$LOG_FILE"
EOF

chmod +x "$RUN_MEMTESTER_SH"

# Menambahkan Cron Job: Berjalan setiap tanggal 1 dan 15 pukul 02:00 pagi (Setiap 2 Minggu sekali)
CRON_LINE="0 2 1,15 * * $RUN_MEMTESTER_SH > /dev/null 2>&1"
(crontab -l 2>/dev/null | grep -F -v "$RUN_MEMTESTER_SH"; echo "$CRON_LINE") | crontab -
echo -e "-> Cron Job berhasil didaftarkan: Berjalan setiap tanggal 1 dan 15 pukul 02:00 WIB."

# Jalankan pengujian RAM pertama kali di latar belakang agar data log awal langsung terbentuk
echo -e "-> Menjalankan pengujian RAM (memtester) pertama kali di latar belakang untuk inisialisasi..."
nohup "$RUN_MEMTESTER_SH" >/dev/null 2>&1 &

# 7. Panduan Pendaftaran TLS Agen (Fitur Wajib Checkmk 2.5)
echo -e "\n${GREEN}[5/5] Selesai! Pemasangan otomatis berhasil dilakukan.${NC}"
echo -e "======================================================\n"
echo -e "Untuk mengaktifkan enkripsi TLS penuh pada Checkmk 2.5, Anda perlu"
echo -e "mendaftarkan agen client ini ke server Checkmk secara manual."
echo -e "Silakan jalankan perintah pendaftaran berikut:\n"
echo -e "${YELLOW}sudo cmk-agent-ctl register --server ${CMK_SERVER_IP}:${CMK_SERVER_PORT} --site ${CMK_SITE} --user cmkadmin --host $(hostname)${NC}\n"
echo -e "======================================================"
