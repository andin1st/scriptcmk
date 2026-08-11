#!/usr/bin/env bash
# Local Check: RAM Health (Membaca log memtester dengan format kustom)

LOG_FILE="/var/log/checkmk_custom/memtester_health.log"

# 1. Jika file log belum terbentuk
if [ ! -f "$LOG_FILE" ]; then
    echo "3 \"RAM_Health\" - Status Memory: Unknown, log pengujian belum ditemukan | Sample Pengujian : 1GB | N/A"
    exit 0
fi

# 2. Ambil timestamp terakhir dari log (mengutamakan waktu selesai pengujian)
timestamp=$(grep "=== MEMTESTER END" "$LOG_FILE" | sed 's/=== MEMTESTER END: //')
if [ -z "$timestamp" ]; then
    # Jika belum selesai, ambil waktu mulai pengujian
    timestamp=$(grep "=== MEMTESTER START" "$LOG_FILE" | sed 's/=== MEMTESTER START: //')
fi
[ -z "$timestamp" ] && timestamp="N/A"

# 3. Deteksi ukuran sample secara dinamis dari log memtester (atau default ke 1GB)
sample_raw=$(grep -o -E "memtester [1]+[GM]" "$LOG_FILE" | head -n1 | awk '{print $2}')
if [ -z "$sample_raw" ]; then
    sample_size="1GB" # Fallback default
else
    # Jika di log tertulis 1024M, konversi tampilannya ke 1GB agar lebih rapi
    if [ "$sample_raw" = "1024M" ]; then
        sample_size="1GB"
    else
        sample_size="$sample_raw"
    fi
fi

# 4. Tentukan status Checkmk dan keluarkan format kustom Anda
if grep -q "STATUS: SUCCESS" "$LOG_FILE"; then
    # Status 0 = OK
    echo "0 \"RAM_Health\" - Status Memory: Ok, tidak ditemukan error saat pengecekan | Sample Pengujian : $sample_size | $timestamp"
elif grep -q "STATUS: FAILED" "$LOG_FILE"; then
    # Status 2 = CRITICAL
    echo "2 \"RAM_Health\" - Status Memory: Critical, ditemukan error kerusakan memory! | Sample Pengujian : $sample_size | $timestamp"
else
    # Status 1 = WARNING (Sedang berjalan / log belum lengkap)
    echo "1 \"RAM_Health\" - Status Memory: Warning, pengujian RAM sedang berlangsung | Sample Pengujian : $sample_size | $timestamp"
fi

