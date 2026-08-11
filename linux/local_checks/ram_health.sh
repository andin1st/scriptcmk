#!/usr/bin/env bash
# ==============================================================================
# Local Check: RAM Health (Membaca log memtester dengan format kustom - v2)
# ==============================================================================

LOG_FILE="/var/log/checkmk_custom/memtester_health.log"

# 1. Jika log belum terbentuk
if [ ! -f "$LOG_FILE" ]; then
    echo "3 \"RAM_Health\" - Status Memory: Unknown, log pengujian belum ditemukan | Sample Pengujian : N/A | N/A"
    exit 0
fi

# 2. Ambil timestamp terakhir dari log secara presisi
timestamp=$(grep "=== MEMTESTER END" "$LOG_FILE" | sed 's/=== MEMTESTER END: //')
if [ -z "$timestamp" ]; then
    # Fallback ke start time jika pengujian masih berjalan
    timestamp=$(grep "=== MEMTESTER START" "$LOG_FILE" | sed 's/=== MEMTESTER START: //')
fi
[ -z "$timestamp" ] && timestamp="N/A"

# 3. Baca SAMPLE_SIZE dari log dan konversi tampilannya secara dinamis
sample_raw=$(grep "SAMPLE_SIZE:" "$LOG_FILE" | cut -d' ' -f2)
sample_size="N/A"

if [ ! -z "$sample_raw" ]; then
    # Jika formatnya adalah angka diakhiri 'M' (misal: 2048M)
    if [[ "$sample_raw" =~ ^([1]+)M$ ]]; then
        mb_val="${BASH_REMATCH[1]}"
        # Jika nilai >= 1024 MB, konversi tampilannya ke GB agar lebih rapi
        if [ "$mb_val" -ge 1024 ]; then
            gb_val=$(( mb_val / 1024 ))
            rem=$(( (mb_val * 10 / 1024) % 10 ))
            if [ "$rem" -eq 0 ]; then
                sample_size="${gb_val}GB"
            else
                sample_size="${gb_val}.${rem}GB"
            fi
        else
            sample_size="${mb_val}MB"
        fi
    else
        sample_size="$sample_raw"
    fi
fi

# 4. Evaluasi status Checkmk dan keluarkan format kustom Anda
if grep -q "STATUS: SUCCESS" "$LOG_FILE"; then
    # Status 0 = OK (Sesuai format permintaan Anda)
    echo "0 \"RAM_Health\" - Status Memory: Ok, tidak ditemukan error saat pengecekan | Sample Pengujian : $sample_size | $timestamp"
elif grep -q "STATUS: FAILED" "$LOG_FILE"; then
    # Status 2 = CRITICAL
    echo "2 \"RAM_Health\" - Status Memory: Critical, ditemukan error kerusakan memory! | Sample Pengujian : $sample_size | $timestamp"
else
    # Status 1 = WARNING (Sedang berjalan / log belum lengkap)
    echo "1 \"RAM_Health\" - Status Memory: Warning, pengujian RAM sedang berlangsung | Sample Pengujian : $sample_size | $timestamp"
fi

