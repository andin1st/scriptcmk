#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: Battery Health (Autodetect via UPower / Sysfs Fallback)
# ==============================================================================

# 1. Cek apakah perintah 'upower' tersedia di sistem client
if command -v upower >/dev/null 2>&1; then
    # Cari path device battery secara dinamis (mengatasi perbedaan BAT0, BAT1, dll)
    BAT_PATH=$(upower -e | grep -i 'battery' | head -n1)

    if [ -z "$BAT_PATH" ]; then
        # Jika upower aktif tapi tidak mendeteksi baterai sama sekali -> PC/Desktop
        echo "0 \"Battery_Health\" - Device is PC/Desktop, there is no battery."
        exit 0
    fi

    # Ambil info detail dari UPower
    INFO=$(upower -i "$BAT_PATH")

    # Ekstrak status baterai (charging, discharging, dll) dan rapikan huruf kapitalnya
    status_raw=$(echo "$INFO" | grep -i "state:" | awk '{print $2}')
    case "$status_raw" in
        "charging")        BAT_STATUS="Charging" ;;
        "discharging")     BAT_STATUS="Discharging" ;;
        "fully-charged")   BAT_STATUS="Fully Charged" ;;
        "pending-charge")  BAT_STATUS="Pending Charge" ;;
        *)                 BAT_STATUS="${status_raw:-Unknown}" ;;
    esac

    # Ekstrak tingkat baterai saat ini (Battery Level)
    BAT_LEVEL=$(echo "$INFO" | grep -i "percentage:" | awk '{print $2}' | tr -d '%')

    # Ekstrak Design Capacity (Wh) dan Current Capacity (Wh)
    # Gunakan tr ',' '.' untuk menangani OS dengan standar desimal koma
    design_raw=$(echo "$INFO" | grep -i "energy-full-design:" | awk '{print $2}' | tr ',' '.')
    current_raw=$(echo "$INFO" | grep -i "energy-full:" | awk '{print $2}' | tr ',' '.')

    design_wh=$(printf "%.0f" "$design_raw" 2>/dev/null || echo "0")
    current_wh=$(printf "%.0f" "$current_raw" 2>/dev/null || echo "0")

    # Ekstrak persentase kesehatan baterai (Capacity / Health) dari UPower
    health_raw=$(echo "$INFO" | grep -i "capacity:" | awk '{print $2}' | tr -d '%' | tr ',' '.')
    health=$(printf "%.0f" "$health_raw" 2>/dev/null || echo "0")

else
    # 2. FALLBACK: Jika 'upower' tidak terinstall (misal pada server minimal CLI), gunakan sysfs /sys/class/power_supply/
    BAT_DIR=""
    for dir in /sys/class/power_supply/*; do
        if [ -f "$dir/type" ] && [ "$(cat "$dir/type")" = "Battery" ]; then
            BAT_DIR="$dir"
            break
        fi
    done

    if [ -z "$BAT_DIR" ]; then
        echo "0 \"Battery_Health\" - Device is PC/Desktop, there is no battery."
        exit 0
    fi

    # Ekstrak status dan level dasar
    status_raw=$(cat "$BAT_DIR/status" 2>/dev/null || echo "Unknown")
    case "$status_raw" in
        "Charging")    BAT_STATUS="Charging" ;;
        "Discharging") BAT_STATUS="Discharging" ;;
        *)             BAT_STATUS="$status_raw" ;;
    esac
    BAT_LEVEL=$(cat "$BAT_DIR/capacity" 2>/dev/null || echo "0")

    design_wh="0"
    current_wh="0"
    health="0"

    if [ -f "$BAT_DIR/energy_full_design" ] && [ -f "$BAT_DIR/energy_full" ]; then
        energy_design=$(cat "$BAT_DIR/energy_full_design")
        energy_full=$(cat "$BAT_DIR/energy_full")
        if [ "$energy_design" -gt 0 ]; then
            design_wh=$(printf "%.0f" "$(awk "BEGIN {print $energy_design/1000000}")")
            current_wh=$(printf "%.0f" "$(awk "BEGIN {print $energy_full/1000000}")")
            health=$(awk "BEGIN {print int(($energy_full/$energy_design)*100)}")
        fi
    fi
fi

# 3. Tentukan status alert Checkmk berdasarkan Battery Health
# OK = 0 (Health >= 70%), WARN = 1 (Health 40-69%), CRIT = 2 (Health < 40%)
status=0
if [ "$health" -ne 0 ] 2>/dev/null; then
    if [ "$health" -lt 40 ]; then
        status=2
    elif [ "$health" -lt 70 ]; then
        status=1
    fi
fi

# 4. Output dalam format kustom yang Anda minta
echo "$status \"Battery_Health\" - Status Battery : $BAT_STATUS | Design Capacity : ${design_wh}w/h | Current Capacity : ${current_wh}w/h | Health : ${health}% | Battery Level : ${BAT_LEVEL}%"
