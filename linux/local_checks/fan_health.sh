#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: FAN Health (v4 - Fixed Temperature & Fan Speed Parsing)
# ==============================================================================

# 1. Dapatkan Suhu CPU secara akurat (Robust CPU Temperature Parser)
get_cpu_temp() {
    local temp=""
    
    if command -v sensors >/dev/null 2>&1; then
        local sensors_out=$(sensors 2>/dev/null)
        
        # A. Coba cari label sensor spesifik CPU: CPUTIN, Tdie, Tctl, Core 0
        local spec_line=$(echo "$sensors_out" | grep -i -E "CPUTIN|Tdie|Tctl|Core 0" | head -n1)
        if [ ! -z "$spec_line" ]; then
            local clean_line=$(echo "$spec_line" | cut -d':' -f2- | cut -d'(' -f1)
            temp=$(echo "$clean_line" | grep -o -E '[0-9.]+' | head -n1)
            if [ ! -z "$temp" ] && (( $(echo "$temp > 0" | bc -l) )); then
                echo "$temp"
                return
            fi
        fi
        
        # B. Cari k10temp (CPU AMD) secara spesifik
        local k10_line=$(echo "$sensors_out" | grep -A 5 -i "k10temp" | grep -i "temp1" | head -n1)
        if [ ! -z "$k10_line" ]; then
            local clean_line=$(echo "$k10_line" | cut -d':' -f2- | cut -d'(' -f1)
            temp=$(echo "$clean_line" | grep -o -E '[0-9.]+' | head -n1)
            if [ ! -z "$temp" ] && (( $(echo "$temp > 0" | bc -l) )); then
                echo "$temp"
                return
            fi
        fi

        # C. Cari coretemp (CPU Intel) secara spesifik
        local core_line=$(echo "$sensors_out" | grep -A 5 -i "coretemp" | grep -i -E "temp[0-9]+|Core [0-9]+" | head -n1)
        if [ ! -z "$core_line" ]; then
            local clean_line=$(echo "$core_line" | cut -d':' -f2- | cut -d'(' -f1)
            temp=$(echo "$clean_line" | grep -o -E '[0-9.]+' | head -n1)
            if [ ! -z "$temp" ] && (( $(echo "$temp > 0" | bc -l) )); then
                echo "$temp"
                return
            fi
        fi
        
        # D. Fallback umum: Cari "temp1" yang tidak di bawah GPU
        local in_gpu_block=0
        while read -r line; do
            if echo "$line" | grep -q -i -E "radeon|nvidia|amdgpu|nouveau"; then
                in_gpu_block=1
            elif [ "$in_gpu_block" -eq 1 ] && [ -z "$line" ]; then
                in_gpu_block=0
            elif [ "$in_gpu_block" -eq 0 ] && echo "$line" | grep -q -i -E "temp[0-9]+:|Core [0-9]+:"; then
                local clean_line=$(echo "$line" | cut -d':' -f2- | cut -d'(' -f1)
                temp=$(echo "$clean_line" | grep -o -E '[0-9.]+' | head -n1)
                if [ ! -z "$temp" ] && (( $(echo "$temp > 0" | bc -l) )); then
                    echo "$temp"
                    return
                fi
            fi
        done <<EOF
$sensors_out
EOF
    fi
    
    # E. Fallback terakhir ke sysfs jika sensors gagal
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        for tz in /sys/class/thermal/thermal_zone*/temp; do
            if [ -f "$tz" ]; then
                local t_raw=$(cat "$tz" 2>/dev/null || echo 0)
                local t=$((t_raw / 1000))
                if [ "$t" -gt 25 ] && [ "$t" -lt 105 ]; then
                    echo "$t"
                    return
                fi
            fi
        done
        local t_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
        echo "$((t_raw / 1000))"
        return
    fi
    
    echo "0"
}

temp_val=$(get_cpu_temp)
temp_int=$(printf "%.0f" "$temp_val" 2>/dev/null || echo "0")

# 2. Dapatkan Kecepatan Kipas Maksimum (Active Fan RPM)
fan_speed=0
if command -v sensors >/dev/null 2>&1; then
    # Cari baris fan, buang label sebelum titik dua (:) agar angka label fan seperti "fan1:" tidak ikut terbaca
    fan_lines=$(sensors 2>/dev/null | grep -i "fan" | cut -d':' -f2-)
    
    while read -r line; do
        # Buang bagian dalam kurung kurawal/siku/tanda kurung (seperti min, max, dll)
        line_clean=$(echo "$line" | cut -d'(' -f1)
        
        # Cari angka yang berpasangan dengan RPM/rpm
        speed_raw=$(echo "$line_clean" | grep -o -E '[0-9.]+\s*[rR][pP][mM]' | grep -o -E '[0-9.]+')
        if [ ! -z "$speed_raw" ]; then
            speed_int=$(printf "%.0f" "$speed_raw" 2>/dev/null || echo "0")
            if [ "$speed_int" -gt "$fan_speed" ]; then
                fan_speed="$speed_int"
            fi
        fi
    done <<EOF
$fan_lines
EOF
fi

# 3. Terapkan Aturan Pembandingan & Status Alert
status=0
status_txt="OK"
remark="FAN Condition Good"

if [ "$temp_int" -gt 85 ] && [ "$fan_speed" -lt 1600 ]; then
    status=2
    status_txt="Critical"
    remark="Please check thermal pasta cooling system"
elif [ "$temp_int" -gt 65 ] && [ "$fan_speed" -lt 1000 ]; then
    status=1
    status_txt="Warning"
    remark="Please check thermal pasta cooling system"
fi

# 4. Output dalam format kustom yang Anda minta
echo "$status \"FAN_Health\" - Status : $status_txt | FAN Speed : ${fan_speed}rpm | Remark: $remark"
