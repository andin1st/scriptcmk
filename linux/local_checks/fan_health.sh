#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: FAN & Temperature Health (Version 3 - Highly Robust)
# ==============================================================================

# Ambil data mentah dari sensors
SENSORS_OUT=$(sensors 2>/dev/null)

# 1. Parsing Suhu CPU Secara Robust
# Kami mencari sensor CPUTIN, k10temp, coretemp, atau sensors dasar lainnya.
# Kami memotong tanda kurung '(' terlebih dahulu untuk memastikan batas kritis/high tidak ikut terbaca.
cputin_line=$(echo "$SENSORS_OUT" | grep -i "CPUTIN:")
k10temp_block=$(echo "$SENSORS_OUT" | grep -A 5 -i "k10temp")
k10temp_line=$(echo "$k10temp_block" | grep -i "temp1:")
intel_line=$(echo "$SENSORS_OUT" | grep -i -E "Core 0|Package id" | head -n1)

cpu_temp=""
if [ ! -z "$cputin_line" ]; then
    # Ambil bagian setelah titik dua dan sebelum tanda kurung
    clean_line=$(echo "$cputin_line" | cut -d':' -f2 | cut -d'(' -f1)
    cpu_temp=$(echo "$clean_line" | grep -o -E '[0-9]+(\.[0-9]+)?' | head -n1)
elif [ ! -z "$k10temp_line" ]; then
    clean_line=$(echo "$k10temp_line" | cut -d':' -f2 | cut -d'(' -f1)
    cpu_temp=$(echo "$clean_line" | grep -o -E '[0-9]+(\.[0-9]+)?' | head -n1)
elif [ ! -z "$intel_line" ]; then
    clean_line=$(echo "$intel_line" | cut -d':' -f2 | cut -d'(' -f1)
    cpu_temp=$(echo "$clean_line" | grep -o -E '[0-9]+(\.[0-9]+)?' | head -n1)
else
    # Fallback: Cari temp1 dari adapter non-GPU (ambil baris temp1 pertama yang bukan dari radeon/amdgpu/nvidia/nouveau)
    # Karena adapter name ada di baris atas, kita lakukan loop per baris untuk mendeteksi adapter saat ini
    current_adapter=""
    while read -r line; do
        if [ -z "$line" ]; then
            continue
        fi
        # Deteksi adapter baru
        if [[ ! "$line" =~ ":" ]] && [[ "$line" =~ "adapter" || "$line" =~ "pci" || "$line" =~ "isa" ]]; then
            current_adapter="$line"
        fi
        # Jika menemukan temp1 pada adapter non-GPU
        if [[ "$line" =~ "temp1:" ]] && [[ ! "$current_adapter" =~ "radeon" && ! "$current_adapter" =~ "amdgpu" && ! "$current_adapter" =~ "nouveau" && ! "$current_adapter" =~ "nvidia" ]]; then
            clean_line=$(echo "$line" | cut -d':' -f2 | cut -d'(' -f1)
            val=$(echo "$clean_line" | grep -o -E '[0-9]+(\.[0-9]+)?' | head -n1)
            if [ ! -z "$val" ]; then
                cpu_temp=$val
                break
            fi
        fi
    done < <(echo "$SENSORS_OUT")
fi

# Jika masih kosong, ambil baris temp1 pertama sebagai absolute fallback
if [ -z "$cpu_temp" ]; then
    temp_line=$(echo "$SENSORS_OUT" | grep -i "temp1" | head -n1)
    clean_line=$(echo "$temp_line" | cut -d':' -f2 | cut -d'(' -f1)
    cpu_temp=$(echo "$clean_line" | grep -o -E '[0-9]+(\.[0-9]+)?' | head -n1)
fi

# Konversi ke integer bulat untuk komparasi matematika
cpu_temp_int=$(printf "%.0f" "$cpu_temp" 2>/dev/null || echo "0")


# 2. Parsing Kecepatan Kipas (FAN Speed) Secara Robust
# Pada komputer dengan beberapa port kipas (seperti fan1, fan2, fan3, dll.), port kosong akan bernilai 0 RPM.
# Kami memotong bagian sebelum titik dua (agar angka label port seperti fan2 tidak terbaca sebagai RPM)
# dan memotong tanda kurung '(' (agar nilai min=0 RPM dalam tanda kurung tidak terbaca).
# Kami mengambil nilai RPM maksimum di antara semua sensor kipas yang aktif untuk menemukan kipas pendingin CPU sesungguhnya.
max_fan=0
while read -r fan_line; do
    [ -z "$fan_line" ] && continue
    # Potong setelah titik dua dan sebelum tanda kurung
    fan_clean=$(echo "$fan_line" | cut -d':' -f2 | cut -d'(' -f1)
    speed=$(echo "$fan_clean" | grep -o -E '[0-9]+' | head -n1)
    if [ ! -z "$speed" ] && [ "$speed" -gt "$max_fan" ]; then
        max_fan=$speed
    fi
done < <(echo "$SENSORS_OUT" | grep -i "fan")


# 3. Evaluasi Kondisi Berdasarkan Aturan
# - temp > 85 dan fan_speed < 1600 -> CRITICAL (Status 2)
# - temp > 65 dan fan_speed < 1000 -> WARNING (Status 1)
# - temp < 65 dan fan_speed >= 0   -> OK (Status 0)
status=0
status_txt="OK"
remark="FAN Condition Good"

if [ "$cpu_temp_int" -gt 85 ] && [ "$max_fan" -lt 1600 ]; then
    status=2
    status_txt="Critical"
    remark="Please check thermal pasta cooling system"
elif [ "$cpu_temp_int" -gt 65 ] && [ "$max_fan" -lt 1000 ]; then
    status=1
    status_txt="Warning"
    remark="Please check thermal pasta cooling system"
else
    status=0
    status_txt="OK"
    remark="FAN Condition Good"
fi

# 4. Output Akhir Sesuai Format yang Diminta
echo "$status \"FAN_Health\" - Status : $status_txt | FAN Speed : ${max_fan}rpm | Remark: $remark"
