#!/usr/bin/env bash
# ==========================================
# S.M.A.R.T Monitoring for Linux (Checkmk)
# Windows Parity Version (Predictive Analytics)
# ==========================================

# 1. CEK KETERSEDIAAN SMARTMONTOOLS
if ! command -v smartctl &> /dev/null; then
    echo "1 \"SMART_Status\" - WARNING: smartmontools tidak terinstal."
    exit 0
fi

# 2. DETEKSI DISK FISIK (Abaikan Loop, RAM disk, CD-ROM)
DISKS=$(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" && $1 !~ /^(loop|ram|sr|fd)/ {print $1}')

if [ -z "$DISKS" ]; then
    echo "3 \"SMART_Status\" - UNKNOWN: Tidak dapat mendeteksi Physical Disk."
    exit 0
fi

# 3. ANALISA SETIAP DISK
for disk in $DISKS; do
    dev="/dev/$disk"
    serviceName="SMART_Disk_${disk}"

    # Kapasitas Disk (GB)
    bytes=$(lsblk -b -d -n -o SIZE "$dev" 2>/dev/null)
    if [ -n "$bytes" ]; then
        capacityGB=$(awk "BEGIN {printf \"%.2f\", $bytes / 1073741824}")
    else
        capacityGB="UNKNOWN"
    fi

    cmdOutput=$(smartctl -a "$dev" 2>&1)

    # Filter USB atau non-SMART
    if echo "$cmdOutput" | grep -qi "Unknown USB bridge" || lsblk -d -n -o TRAN "$dev" | grep -qi "usb"; then
        continue
    fi

    if echo "$cmdOutput" | grep -Eqi "SMART support is: Disabled|SMART support is: Unavailable"; then
        model=$(echo "$cmdOutput" | grep -iE "^Device Model:|^Model Number:|^Model Name:" | head -n 1 | awk -F':' '{print $2}' | xargs)
        echo "0 \"$serviceName\" - OK - Model: ${model:-$disk} | SMART dinonaktifkan."
        continue
    fi

    # ---- DETEKSI KELULUSAN ----
    exitCode=3
    stateText="UNKNOWN"
    details=""

    if echo "$cmdOutput" | grep -iq "PASSED"; then
        exitCode=0; stateText="OK"; details="Status: PASSED"
    elif echo "$cmdOutput" | grep -iq "FAILED"; then
        exitCode=2; stateText="CRITICAL"; details="Status: FAILED (Kerusakan Hardware)"
    fi

    # Ekstrak Model
    model=$(echo "$cmdOutput" | grep -iE "^Device Model:|^Model Number:|^Model Name:" | head -n 1 | awk -F':' '{print $2}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$model" ] && model="$disk"

    # ---- EKSTRAK SUHU ----
    temp="N/A"
    if echo "$cmdOutput" | grep -qE "Temperature:[[:space:]]+[0-9]+[[:space:]]+Celsius"; then
        temp=$(echo "$cmdOutput" | grep -E "Temperature:[[:space:]]+[0-9]+[[:space:]]+Celsius" | awk '{print $2}')
    elif echo "$cmdOutput" | grep -qE "^194 Temperature_Celsius"; then
        temp=$(echo "$cmdOutput" | awk '/^194 Temperature_Celsius/ {print $10}')
    elif echo "$cmdOutput" | grep -qE "Current Drive Temperature:"; then
        temp=$(echo "$cmdOutput" | grep "Current Drive Temperature:" | awk '{print $4}')
    fi

    # ---- EKSTRAK KESEHATAN (LIFETIME) ----
    healthPct="N/A"
    pctUsed=-1
    if echo "$cmdOutput" | grep -qE "Percentage Used:"; then
        pctUsed=$(echo "$cmdOutput" | grep "Percentage Used:" | awk '{print $3}' | tr -d '%')
        healthPct=$((100 - pctUsed))
    elif echo "$cmdOutput" | grep -qE "Available Spare:"; then
        healthPct=$(echo "$cmdOutput" | grep "Available Spare:" | awk '{print $3}' | tr -d '%')
    fi

    # ---- EKSTRAK TOTAL READ / WRITE / POWER ON HOURS ----
    totalRead="N/A"
    totalWrite="N/A"
    writeGB=0
    powerOnHours=0

    # Menangkap pola "Data Units Read: 1234 [14.9 TB]"
    if read_line=$(echo "$cmdOutput" | grep -i "Data Units Read:"); then
        totalRead=$(echo "$read_line" | awk -F'[][]' '{print $2}')
    fi
    
    if write_line=$(echo "$cmdOutput" | grep -i "Data Units Written:"); then
        totalWrite=$(echo "$write_line" | awk -F'[][]' '{print $2}')
        # Konversi ke GB untuk kalkulasi matematika
        if echo "$totalWrite" | grep -iq "TB"; then
            val=$(echo "$totalWrite" | awk '{print $1}')
            writeGB=$(awk "BEGIN {print $val * 1024}")
        elif echo "$totalWrite" | grep -iq "GB"; then
            writeGB=$(echo "$totalWrite" | awk '{print $1}')
        fi
    fi

    if echo "$cmdOutput" | grep -qE "Power On Hours:"; then
        powerOnHours=$(echo "$cmdOutput" | grep "Power On Hours:" | awk '{print $4}' | tr -d ',')
    elif echo "$cmdOutput" | grep -qE "^[[:space:]]*9 Power_On_Hours"; then
        powerOnHours=$(echo "$cmdOutput" | awk '/^[[:space:]]*9 Power_On_Hours/ {print $10}')
    fi

    # ---- KALKULASI ESTIMASI UMUR (PREDICTIVE ANALYTICS) ----
    analyticText=""
    if [ "$pctUsed" -gt 0 ] && [ $(awk "BEGIN {print ($writeGB > 0) ? 1 : 0}") -eq 1 ] && [ "$powerOnHours" -gt 0 ]; then
        # Menggunakan AWK untuk perhitungan desimal (floating point)
        analyticText=$(awk -v writeGB="$writeGB" -v pctUsed="$pctUsed" -v poh="$powerOnHours" '
        BEGIN {
            totalTBW_GB = writeGB / (pctUsed / 100);
            daysOn = poh / 24;
            dailyWriteGB = writeGB / daysOn;
            remainingGB = totalTBW_GB - writeGB;
            remainingDays = (dailyWriteGB > 0) ? (remainingGB / dailyWriteGB) : 999999;
            remainingYears = remainingDays / 365;
            printf " | Write/Day: %.2f GB | Est. Life: %.2f Years", dailyWriteGB, remainingYears;
        }')
    elif [ "$pctUsed" -eq 0 ] && [ $(awk "BEGIN {print ($writeGB > 0) ? 1 : 0}") -eq 1 ]; then
        analyticText=" | Write/Day: N/A | Est. Life: >10 Years (Keausan masih 0%)"
    fi

    # ==========================================
    # 4. SUSUN GRAFIK & OUTPUT CHECKMK
    # ==========================================
    perfMetrics=""
    infoText="Model: $model ($capacityGB GB) | $details"

    if [ "$temp" != "N/A" ]; then
        perfMetrics="${perfMetrics}temp=$temp;55;65;0;100|"
        infoText="$infoText | Temp: ${temp}C"
        if [ "$temp" -ge 55 ] && [ "$exitCode" -eq 0 ]; then exitCode=1; stateText="WARNING"; fi
        if [ "$temp" -ge 65 ]; then exitCode=2; stateText="CRITICAL"; fi
    fi

    if [ "$healthPct" != "N/A" ]; then
        perfMetrics="${perfMetrics}health=$healthPct;20;10;0;100|"
        infoText="$infoText | Health: ${healthPct}%"
        if [ "$healthPct" -le 20 ] && [ "$exitCode" -eq 0 ]; then exitCode=1; stateText="WARNING"; fi
        if [ "$healthPct" -le 10 ]; then exitCode=2; stateText="CRITICAL"; fi
    fi

    if [ "$totalRead" != "N/A" ] && [ "$totalWrite" != "N/A" ]; then
        infoText="$infoText | Read: $totalRead | Written: $totalWrite"
    fi

    infoText="$infoText$analyticText"

    # Hapus karakter pipa (|) di akhir metrik jika ada
    perfMetrics=${perfMetrics%|}
    [ -z "$perfMetrics" ] && perfMetrics="-"

    echo "$exitCode \"$serviceName\" $perfMetrics $stateText - $infoText"
done
