#!/usr/bin/env bash
# Local Check: Informasi CPU & OS

# Detail OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "0 \"OS_Detail\" - OS: $PRETTY_NAME, Kernel: $(uname -r)"
else
    echo "1 \"OS_Detail\" - OS tidak terdeteksi sepenuhnya."
fi

# CPU Utilitas (Menggunakan Load Average 1 Menit)
load=$(cat /proc/loadavg | awk '{print $1}')
cores=$(nproc)
# Peringatan jika load melebihi jumlah core CPU
if (( $(echo "$load > $cores" | bc -l) )); then
    echo "1 \"CPU_Usage\" load=${load};${cores};$((cores*2)) CPU Load Tinggi: ${load}"
else
    echo "0 \"CPU_Usage\" load=${load};${cores};$((cores*2)) CPU Load Normal: ${load}"
fi

# CPU Detail
cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
echo "0 \"CPU_Model\" - Model: $cpu_model, Cores: $cores"

# CPU Temperature (lm-sensors)
if command -v sensors >/dev/null 2>&1; then
    temp=$(sensors | grep -i -E "Core 0|Package id|temp1" | head -n1 | awk '{print $2}' | tr -d '+°C')
    if [ ! -z "$temp" ]; then
        echo "0 \"CPU_Temperature\" temp=${temp};75;85 Suhu CPU saat ini: ${temp} C"
    else
        echo "3 \"CPU_Temperature\" - Sensor suhu tidak menghasilkan data."
    fi
else
    echo "3 \"CPU_Temperature\" - Alat 'sensors' tidak terinstall."
fi
