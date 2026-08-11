#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: CPU Information (Terpisah)
# ==============================================================================

# 1. Ambil Model CPU dan rapikan tampilannya (menghapus logo dagang seperti (R), (TM), @ speed)
cpu_model_raw=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
# Pembersihan teks agar lebih rapi (misal: "Intel(R) Core(TM) i3-13100 CPU" -> "Intel Core i3 13100")
cpu_model=$(echo "$cpu_model_raw" | sed -E 's/\((R)\)//g; s/\((TM)\)//g; s/ CPU//g; s/ @.*//g; s/ +/ /g')
[ -z "$cpu_model" ] && cpu_model="Generic CPU"

# 2. Ambil Clock Speed Maksimal (dalam GHz)
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq ]; then
    max_khz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)
    clock_speed=$(awk "BEGIN {printf \"%.1fGhz\", $max_khz/1000000}")
else
    # Fallback dari /proc/cpuinfo (MHz)
    mhz=$(grep -m1 "cpu MHz" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
    if [ ! -z "$mhz" ]; then
        clock_speed=$(awk "BEGIN {printf \"%.1fGhz\", $mhz/1000}")
    else
        clock_speed="N/A"
    fi
fi

# 3. Hitung Core Fisik dan Core Logis (Thread)
physical_cores=$(grep -m1 "cpu cores" /proc/cpuinfo | cut -d: -f2 | tr -d ' ')
logical_threads=$(nproc)
[ -z "$physical_cores" ] && physical_cores=$logical_threads

# 4. Ambil CPU Load Saat Ini (Menggunakan kalkulasi delta /proc/stat untuk akurasi terbaik)
read -r cpu a b c d e f g _ < /proc/stat
prevactive=$((a + b + c + f + g))
prevtotal=$((a + b + c + d + e + f + g))
sleep 0.5
read -r cpu a b c d e f g _ < /proc/stat
active=$((a + b + c + f + g))
total=$((a + b + c + d + e + f + g))

cpu_load=0
if [ $((total - prevtotal)) -gt 0 ]; then
    cpu_load=$(( 100 * (active - prevactive) / (total - prevtotal) ))
fi

# 5. Ambil Suhu CPU
temp="N/A"
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp)
    temp=$((temp_raw / 1000))
elif command -v sensors >/dev/null 2>&1; then
    # Jika zone0 absen, cari via lm-sensors
    temp=$(sensors | grep -i -E "Core 0|Package id|temp1" | head -n1 | awk '{print $2}' | tr -d '+°C' | cut -d. -f1)
fi

# 6. Evaluasi Status Alert Berdasarkan Standar Checkmk (Suhu CPU <= 75 OK, > 85 Critical)
status=0
if [ "$temp" != "N/A" ] 2>/dev/null; then
    if [ "$temp" -gt 85 ]; then
        status=2 # CRITICAL
    elif [ "$temp" -gt 75 ]; then
        status=1 # WARNING
    fi
fi

# Evaluasi tambahan berdasarkan CPU Load (Warning > 85%, Critical > 95%)
if [ "$cpu_load" -gt 95 ] && [ "$status" -lt 2 ]; then
    status=2
elif [ "$cpu_load" -gt 85 ] && [ "$status" -lt 1 ]; then
    status=1
fi

# 7. Output Checkmk dengan format kustom yang Anda minta
# Struktur: <status> <service_name> <perf_data> <status_text>
echo "$status \"CPU_Info\" - Spesifikasi : $cpu_model | Clock Speed : $clock_speed | Core/Thread : ${physical_cores}/${logical_threads} | CPU Load : ${cpu_load}% | CPU Temperature: ${temp} Celcius"
