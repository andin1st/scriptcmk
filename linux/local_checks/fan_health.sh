#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: FAN Health (Fixed Parser & Dynamic Detection - v2)
# ==============================================================================

# 1. Mendeteksi Suhu CPU (Menggunakan sensors atau fallback sysfs)
temp=""
if command -v sensors >/dev/null 2>&1; then
    temp_line=$(sensors 2>/dev/null | grep -i -E "Core 0|Package id|temp1|CPU" | head -n1)
    if [ -n "$temp_line" ]; then
        temp=$(echo "$temp_line" | grep -o -E '[0-9]+(\.[0-9]+)?' | head -n1 | cut -d. -f1)
    fi
fi

if [ -z "$temp" ] && [ -d /sys/class/thermal ]; then
    for zone in /sys/class/thermal/thermal_zone*; do
        if [ -f "$zone/temp" ] && [ -f "$zone/type" ]; then
            type=$(cat "$zone/type" 2>/dev/null)
            if echo "$type" | grep -q -i -E "cpu|x86_pkg_temp|acpitz"; then
                temp_raw=$(cat "$zone/temp" 2>/dev/null)
                if [ -n "$temp_raw" ] && [ "$temp_raw" -gt 0 ] 2>/dev/null; then
                    temp=$(( temp_raw / 1000 ))
                    break
                fi
            fi
        fi
    done
fi

if [ -z "$temp" ] || ! [[ "$temp" =~ ^[0-9]+$ ]]; then
    temp=45 # Default safe temperature fallback
fi

# 2. Mendeteksi Kecepatan Kipas (FAN Speed)
# BUG FIX: Mencari angka yang berpasangan langsung dengan kata 'RPM/rpm' 
# Hal ini mencegah kecacatan parser yang salah mencocokkan angka indeks fan (seperti '0' pada 'fan0')
fan_speed=""
if command -v sensors >/dev/null 2>&1; then
    # Cari baris yang mengandung kata 'fan' dan 'rpm'
    fan_line=$(sensors 2>/dev/null | grep -i "fan" | grep -i "rpm" | head -n1)
    if [ -n "$fan_line" ]; then
        # Ambil angka pertama yang berdekatan dengan RPM (menggunakan regex biner yang ketat)
        fan_speed=$(echo "$fan_line" | grep -o -E '[0-9]+\s*[rR][pP][mM]' | head -n1 | grep -o -E '[0-9]+')
    fi
fi

# Jika masih kosong, default ke 0 (misalnya pada VM, PC tanpa sensor, atau driver belum dimuat)
if [ -z "$fan_speed" ] || ! [[ "$fan_speed" =~ ^[0-9]+$ ]]; then
    fan_speed=0
fi

# 3. Logika Evaluasi Status Berdasarkan Aturan Kustom:
# - temp > 85 dan fan < 1600 -> CRITICAL
# - temp > 65 dan fan < 1000 -> WARNING
# - temp < 65 dan fan >= 0   -> OK
status_code=0
status_txt="OK"
remark="FAN Condition Good"

if [ "$temp" -gt 85 ] && [ "$fan_speed" -lt 1600 ]; then
    status_code=2
    status_txt="Critical"
    remark="Please check thermal pasta cooling system"
elif [ "$temp" -gt 65 ] && [ "$fan_speed" -lt 1000 ]; then
    status_code=1
    status_txt="Warning"
    remark="Please check thermal pasta cooling system"
else
    status_code=0
    status_txt="OK"
    remark="FAN Condition Good"
fi

# Tambahan informasi troubleshooting jika kipas terbaca 0rpm di sistem fisik
if [ "$fan_speed" -eq 0 ] && [ "$temp" -gt 65 ]; then
    remark="Please check thermal pasta cooling system OR run 'sudo sensors-detect' to load driver modules"
fi

# 4. Output dalam format kustom yang diminta:
# Format: Status : OK/Warning/Critical | FAN Speed : 1000rpm | Remark: FAN Condition Good/ Please check thermal pasta cooling system
echo "$status_code \"FAN_Health\" - Status : $status_txt | FAN Speed : ${fan_speed}rpm | Remark: $remark"
