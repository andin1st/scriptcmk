#!/usr/bin/env bash
# Local Check: RAM Health (Membaca log memtester)

LOG_FILE="/var/log/checkmk_custom/memtester_health.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "3 \"RAM_Health\" - Pengujian RAM belum pernah dijalankan."
    exit 0
fi

# Cari status sukses/gagal di dalam log
if grep -q "STATUS: SUCCESS" "$LOG_FILE"; then
    last_run=$(grep "=== MEMTESTER END" "$LOG_FILE" | sed 's/=== MEMTESTER END: //')
    echo "0 \"RAM_Health\" - Pengujian RAM Sukses (Sehat). Terakhir dijalankan pada: $last_run"
elif grep -q "STATUS: FAILED" "$LOG_FILE"; then
    echo "2 \"RAM_Health\" - Pengujian RAM Menunjukkan Kerusakan (Hardware Error!). Periksa segera log di $LOG_FILE"
else
    echo "1 \"RAM_Health\" - Pengujian RAM sedang berlangsung atau log tidak lengkap."
fi
