#!/usr/bin/env bash
# =====================================================================
# Local Check Checkmk: Daily Battery Health Monitor
# Scheduled to run once a day at 16:00
# =====================================================================
CACHE_DIR="/var/lib/check_mk_agent/cache"
mkdir -p "$CACHE_DIR" 2>/dev/null
CACHE_FILE="$CACHE_DIR/cache_battery_health.txt"

# Get current hour and today's 16:00 epoch
CURRENT_HOUR=$(date +%H)
TODAY_16=$(date -d "16:00:00" +%s 2>/dev/null)

if [ -z "$TODAY_16" ]; then
    TODAY_16=$(date +%s -d "16:00:00" 2>/dev/null)
fi

if [ "$CURRENT_HOUR" -lt 16 ]; then
    LAST_16=$(date -d "yesterday 16:00:00" +%s 2>/dev/null)
else
    LAST_16=$TODAY_16
fi

if [ -z "$LAST_16" ]; then
    LAST_16=$(( TODAY_16 - 86400 ))
fi

need_update() {
    local file=$1
    local threshold=$2
    if [ ! -f "$file" ]; then
        return 0
    fi
    local file_ts
    file_ts=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    if [ "$file_ts" -lt "$threshold" ]; then
        return 0
    fi
    return 1
}

if need_update "$CACHE_FILE" "$LAST_16"; then
    > "$CACHE_FILE"
    
    # Deteksi Baterai menggunakan UPower terlebih dahulu
    has_battery=false
    bat_path=""
    
    if command -v upower >/dev/null 2>&1; then
        bat_path=$(upower -e 2>/dev/null | grep -i "battery" | head -n 1)
        if [ -n "$bat_path" ]; then
            has_battery=true
        fi
    fi
    
    # Jika ada baterai via UPower
    if [ "$has_battery" = true ]; then
        bat_info=$(upower -i "$bat_path" 2>/dev/null)
        state=$(echo "$bat_info" | grep -i "state" | cut -d':' -f2 | xargs)
        health_str=$(echo "$bat_info" | grep -i "capacity" | grep -o -E '[0-9.]+%?' | tr -d '%')
        cycle=$(echo "$bat_info" | grep -i "history-charge" -A5 2>/dev/null | grep -i "cycle" | grep -o -E '[0-9]+' | head -n1)
        [ -z "$cycle" ] && cycle=$(echo "$bat_info" | grep -i "cycle" | grep -o -E '[0-9]+' | head -n1)
        [ -z "$cycle" ] && cycle="0"
        
        # Validasi Health
        if [[ "$health_str" =~ ^[0-9.]+$ ]]; then
            health=$(awk "BEGIN {print int($health_str)}")
        else
            health=100
        fi
    else
        # Fallback ke Sysfs jika UPower tidak mendeteksi baterai
        sys_bat_dir=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n 1)
        if [ -n "$sys_bat_dir" ]; then
            has_battery=true
            state=$(cat "$sys_bat_dir/status" 2>/dev/null | tr 'A-Z' 'a-z')
            cycle=$(cat "$sys_bat_dir/cycle_count" 2>/dev/null || echo "0")
            
            # Hitung kesehatan berbasis energy atau charge
            ef_design=$(cat "$sys_bat_dir/energy_full_design" 2>/dev/null || cat "$sys_bat_dir/charge_full_design" 2>/dev/null)
            ef_now=$(cat "$sys_bat_dir/energy_full" 2>/dev/null || cat "$sys_bat_dir/charge_full" 2>/dev/null)
            
            if [ -n "$ef_design" ] && [ -n "$ef_now" ] && [ "$ef_design" -gt 0 ] 2>/dev/null; then
                health=$(awk "BEGIN {print int(($ef_now / $ef_design) * 100)}")
            else
                health=100
            fi
        fi
    fi
    
    # Output hasil sesuai tipe perangkat
    if [ "$has_battery" = true ]; then
        [ -z "$state" ] && state="unknown"
        
        # Evaluasi Threshold
        # OK >= 60%, WARNING <= 40%, CRITICAL <= 20%
        status=0
        status_txt="OK"
        if [ "$health" -le 20 ]; then
            status=2
            status_txt="Critical"
        elif [ "$health" -le 40 ]; then
            status=1
            status_txt="Warning"
        fi
        
        echo "$status \"Health_Battery\" - Status : $status_txt ❘ Health: ${health}% ❘ Cycle: $cycle ❘ State: $state" >> "$CACHE_FILE"
    else
        # Jika PC Desktop / Tidak ada baterai
        echo "0 \"Health_Battery\" - Status : OK ❘ Device is PC/Desktop, there is no battery." >> "$CACHE_FILE"
    fi
fi

cat "$CACHE_FILE" 2>/dev/null
