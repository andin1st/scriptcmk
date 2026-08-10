#!/usr/bin/env bash
# ==============================================================================
# Script Installer Otomatis Agen Checkmk v2 (Dynamic Server Input)
# Ditujukan untuk Client: Ubuntu / Debian
# ==============================================================================

set -e

# --- Default Configuration ---
CMK_SERVER=""
CMK_SITE=""
GITHUB_REPO="username/checkmk-agent-deploy" # Ganti dengan username/nama-repo Anda
GITHUB_BRANCH="main"

# ==============================================================================
# 1. PARSING ARGUMEN BARIS PERINTAH (CLI ARGUMENTS)
# ==============================================================================

show_help() {
    echo "Penggunaan: sudo bash install-v2.sh [opsi]"
    echo ""
    echo "Opsi:"
    echo "  -s, --server <IP/Host>   IP Address atau Hostname server Checkmk"
    echo "  -d, --site <Site_ID>     Site ID Checkmk (default: monitoring)"
    echo "  -g, --github <Repo>      Repositori GitHub (contoh: user/repo)"
    echo "  -b, --branch <Branch>    Branch GitHub (default: main)"
    echo "  -h, --help               Menampilkan panduan bantuan ini"
    echo ""
    echo "Contoh One-Liner (piping):"
    echo "  curl -sSL https://raw.githubusercontent.com/.../install-v2.sh | sudo bash -s -- -s 192.168.1.100 -d monitoring"
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--server) CMK_SERVER="$2"; shift ;;
        -d|--site)   CMK_SITE="$2"; shift ;;
        -g|--github) GITHUB_REPO="$2"; shift ;;
        -b|--branch) GITHUB_BRANCH="$2"; shift ;;
        -h|--help)   show_help; exit 0 ;;
        *) echo "Opsi tidak dikenal: $1"; show_help; exit 1 ;;
    esac
    shift
done

# ==============================================================================
# 2. VALIDASI PRE-REQUISITE & AKSES ROOT
# ==============================================================================

# Pastikan script dijalankan sebagai root/sudo
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Harap jalankan script ini sebagai root atau menggunakan sudo!"
    exit 1
fi

# Deteksi OS (Memastikan keluarga Debian/Ubuntu)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" && ! "$ID_LIKE" =~ "debian" ]]; then
        echo "[WARNING] Sistem operasi terdeteksi sebagai $NAME. Script ini dioptimalkan untuk Ubuntu/Debian."
        read -p "Apakah Anda ingin tetap melanjutkan? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    fi
else
    echo "[ERROR] Tidak dapat mendeteksi sistem operasi. Menghentikan instalasi."
    exit 1
fi

# ==============================================================================
# 3. INPUT INTERAKTIF (JIKA PARAMETER KOSONG)
# ==============================================================================

if [ -z "$CMK_SERVER" ]; then
    echo "--- Konfigurasi Server Checkmk ---"
    read -p "Masukkan IP Address atau Hostname Server Checkmk: " CMK_SERVER
fi

# Validasi IP/Hostname server tidak boleh kosong
while [ -z "$CMK_SERVER" ]; do
    echo "[ERROR] IP Address / Hostname Server Checkmk wajib diisi!"
    read -p "Masukkan IP Address atau Hostname Server Checkmk: " CMK_SERVER
done

if [ -z "$CMK_SITE" ]; then
    read -p "Masukkan Site ID Checkmk [Default: monitoring]: " CMK_SITE
    CMK_SITE=${CMK_SITE:-monitoring}
fi

echo ""
echo "=================================================="
echo "      KONFIGURASI DEPLOYMENT AGEN CHECKMK v2"
echo "=================================================="
echo "Server Checkmk : $CMK_SERVER"
echo "Site ID        : $CMK_SITE"
echo "GitHub Repo    : $GITHUB_REPO ($GITHUB_BRANCH)"
echo "=================================================="
echo ""

# ==============================================================================
# 4. INSTALASI DEPENDENSI LOKAL
# ==============================================================================
echo "[1/5] Memperbarui paket & menginstal dependensi..."
apt-get update -qq
apt-get install -y -qq curl smartmontools memtester lm-sensors jq bc wget >/dev/null

# ==============================================================================
# 5. DOWNLOAD & INSTALASI AGEN CHECKMK DARI SERVER DYNAMIC
# ==============================================================================
echo "[2/5] Mengunduh agen Checkmk dari server..."
AGENT_URL="http://${CMK_SERVER}/${CMK_SITE}/check_mk/agents/check-mk-agent_all.deb"
TEMP_DEB="/tmp/check-mk-agent_all.deb"

# Mengunduh paket .deb agen
if curl -sSfL "$AGENT_URL" -o "$TEMP_DEB"; then
    echo "[OK] Berhasil mengunduh agen dari server."
elif wget -qO "$TEMP_DEB" "$AGENT_URL"; then
    echo "[OK] Berhasil mengunduh agen dari server (via wget)."
else
    echo "[ERROR] Gagal mengunduh agen dari $AGENT_URL"
    echo "Pastikan server Checkmk Anda menyala, IP/Site benar, dan dapat diakses dari client ini."
    exit 1
fi

echo "Menginstal agen Checkmk..."
dpkg -i "$TEMP_DEB" || apt-get install -f -y -qq
rm -f "$TEMP_DEB"

# ==============================================================================
# 6. DOWNLOAD SCRIPTS LOCAL CHECKS DARI GITHUB
# ==============================================================================
echo "[3/5] Mengunduh script pemantauan kustom (Local Checks) dari GitHub..."
LOCAL_DIR="/usr/lib/check_mk_agent/local"
mkdir -p "$LOCAL_DIR"

# List script monitoring kustom yang akan diambil
scripts=("cpu_os_info.sh" "ram_health.sh" "disk_nvme_health.sh" "remote_apps.sh")

for script in "${scripts[@]}"; do
    GITHUB_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/linux/local_checks/${script}"
    echo "  -> Mengunduh $script..."
    
    if curl -sSfL "$GITHUB_URL" -o "${LOCAL_DIR}/${script}"; then
        chmod +x "${LOCAL_DIR}/${script}"
        echo "     [OK] $script terpasang."
    else
        echo "     [WARNING] Gagal mengunduh $script dari GitHub (URL: $GITHUB_URL)."
        echo "     Pastikan file tersebut ada di repositori Anda."
    fi
done

# ==============================================================================
# 7. KONFIGURASI PENGUJIAN RAM ASINKRON (MEMTESTER)
# ==============================================================================
echo "[4/5] Mengonfigurasi penjadwalan pengujian RAM Health (Memtester)..."
LOG_DIR="/var/log/checkmk_custom"
mkdir -p "$LOG_DIR"

# Buat script pembantu run_memtester.sh
cat << 'EOF' > /usr/local/bin/run_memtester.sh
#!/usr/bin/env bash
# Script Eksekusi Memtester Asinkron (2 Mingguan)

LOG_FILE="/var/log/checkmk_custom/memtester_health.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "=== MEMTESTER START: $(date) ===" > "$LOG_FILE"

# Hitung RAM bebas dan ambil 50% untuk ditest
free_ram=$(free -m | awk '/^Mem:/{print $4}')
test_ram=$(( free_ram / 2 ))

# Pastikan ukuran pengetesan aman (minimal 32MB)
if [ $test_ram -lt 32 ]; then
    test_ram=32
fi

echo "Memulai pengujian memtester dengan alokasi ${test_ram}M..." >> "$LOG_FILE"

# Jalankan memtester sebanyak 1 pass/loop
if memtester "${test_ram}M" 1 >> "$LOG_FILE" 2>&1; then
    echo "STATUS: SUCCESS" >> "$LOG_FILE"
else
    echo "STATUS: FAILED" >> "$LOG_FILE"
fi

echo "=== MEMTESTER END: $(date) ===" >> "$LOG_FILE"
EOF

chmod +x /usr/local/bin/run_memtester.sh

# Pasang di Cron Job (Berjalan tanggal 1 dan 15 setiap pukul 02:00 pagi)
CRON_JOB="0 2 1,15 * * /usr/local/bin/run_memtester.sh"
(crontab -l 2>/dev/null | grep -v "run_memtester.sh" ; echo "$CRON_JOB") | crontab -
echo "[OK] Cron Job didaftarkan (berjalan 2 minggu sekali)."

# Jalankan pertama kali di background agar langsung menghasilkan data log awal
echo "Menjalankan uji RAM inisial di latar belakang..."
/usr/local/bin/run_memtester.sh >/dev/null 2>&1 &

# ==============================================================================
# 8. VERIFIKASI AKHIR
# ==============================================================================
echo "[5/5] Memverifikasi status layanan agen..."
if systemctl is-active --quiet check-mk-agent.socket || systemctl is-active --quiet check-mk-agent; then
    echo "[OK] Layanan agen Checkmk aktif."
else
    echo "[WARNING] Layanan agen Checkmk tidak aktif. Mencoba menyalakan..."
    systemctl enable --now check-mk-agent.socket || true
fi

echo ""
echo "=================================================="
echo "   DEPLOMENT AGEN CHECKMK v2 SELESAI DENGAN SUKSES!"
echo "=================================================="
echo " Agen telah terinstal dan terhubung secara lokal."
echo " Silakan daftarkan host ini di Web GUI Server Anda:"
echo " http://${CMK_SERVER}:${CMK_SITE}/"
echo "=================================================="
echo ""
