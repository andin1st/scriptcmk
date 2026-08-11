#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: FAN Health (Comparing Temperature & Fan Speed)
# ==============================================================================

# 1. Deteksi Suhu CPU (Menggunakan lm-sensors atau sysfs)
temp=""
if command -v sensors >/dev/null 2>&1; then
    # Cari baris suhu Core 0, Package id, atau temp1, lalu ekstrak angka integer-nya
    temp=$(sensors 2>/dev/null | grep -E -i "Core 0|Package id|temp1" | head -n1 | grep -o -E '[0-9]+(\.[0-9]+)?' | head -n1 | cut -d. -f1)
fi

# Fallback jika sensors gagal atau tidak menghasilkan data
if [ -z "$temp" ] && [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    temp=$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
fi

# Default fallback jika benar-benar tidak terdeteksi (asumsi suhu ruangan/normal)
[ -z "$temp" ] && temp=40

# 2. Deteksi Kecepatan Kipas (FAN Speed via lm-sensors)
fan=""
if command -v sensors >/dev/null 2>&1; then
    # Cari baris yang mengandung kata "fan" dan ambil angka RPM-nya
    fan=$(sensors 2>/dev/null | grep -i "fan" | head -n1 | grep -o -E '[0-9]+' | head -n1)
fi

# Default fallback jika tidak ada sensor fan terdeteksi (misal: PC Desktop tanpa sensor fan terintegrasi/VM/PC Fanless)
[ -z "$fan" ] && fan=0

# 3. Evaluasi Logika Perbandingan Berdasarkan Kriteria
# - Temp > 85°C dan Fan < 1600 RPM -> Status Critical (2)
# - Temp > 65°C dan Fan < 1000 RPM -> Status Warning (1)
# - Temp < 65°C dan Fan >= 0 RPM -> Status OK (0)
# - Selain itu (Suhu normal / Fan berputar kencang saat panas) -> Status OK (0)

status_code=0
status_text="OK"
remark="FAN Condition Good"

if [ "$temp" -gt 85 ] && [ "$fan" -lt 1600 ]; then
    status_code=2
    status_text="Critical"
    remark="Please check thermal pasta cooling system"
elif [ "$temp" -gt 65 ] && [ "$fan" -lt 1000 ]; then
    status_code=1
    status_text="Warning"
    remark="Please check thermal pasta cooling system"
else
    status_code=0
    status_text="OK"
    remark="FAN Condition Good"
fi

# 4. Output dalam format kustom yang Anda minta untuk Checkmk Local Check
echo "$status_code \"FAN_Health\" - Status : $status_text | FAN Speed : ${fan}rpm | Remark: $remark"
