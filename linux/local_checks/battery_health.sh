#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: Battery Health (Laptop vs PC/Desktop Autodetect)
# ==============================================================================

# 1. Cari folder baterai di /sys/class/power_supply/
BAT_DIR=""
for dir in /sys/class/power_supply/*; do
    if [ -f "$dir/type" ] && [ "$(cat "$dir/type")" = "Battery" ]; then
        BAT_DIR="$dir"
        break
    fi
done

# 2. Jika tidak ditemukan battery (Berarti PC / Desktop)
if [ -z "$BAT_DIR" ]; then
    # Status 0 = OK (Sebab wajar jika PC Desktop tidak memiliki baterai)
    echo "0 \"Battery_Health\" - Device is PC/Desktop, there is no battery."
    exit 0
fi

# 3. Jika ditemukan battery (Laptop)
BAT_STATUS=$(cat "$BAT_DIR/status" 2>/dev/null || echo "Unknown")
BAT_LEVEL=$(cat "$BAT_DIR/capacity" 2>/dev/null || echo "0")

design_wh="N/A"
current_wh="N/A"
health="N/A"

# Opsi A: Ambil data energi (Wh) - Umum ditemukan di laptop modern
if [ -f "$BAT_DIR/energy_full_design" ] && [ -f "$BAT_DIR/energy_full" ]; then
    energy_design=$(cat "$BAT_DIR/energy_full_design")
    energy_full=$(cat "$BAT_DIR/energy_full")
    
    if [ "$energy_design" -gt 0 ]; then
        # Konversi micro-Wh ke Wh (dibagi 1.000.000)
        design_val=$(awk "BEGIN {print $energy_design/1000000}")
        current_val=$(awk "BEGIN {print $energy_full/1000000}")
        
        # Format ke integer terdekat agar sesuai format Anda (misal 40w/h)
        design_wh=$(printf "%.0f" "$design_val")
        current_wh=$(printf "%.0f" "$current_val")
        
        # Hitung Persentase Kesehatan Baterai (Health)
        health=$(awk "BEGIN {print int(($energy_full/$energy_design)*100)}")
    fi

# Opsi B: Ambil data charge (Ah) jika tipe baterai menggunakan hitungan charge & voltage
elif [ -f "$BAT_DIR/charge_full_design" ] && [ -f "$BAT_DIR/charge_full" ]; then
    charge_design=$(cat "$BAT_DIR/charge_full_design")
    charge_full=$(cat "$BAT_DIR/charge_full")
    # Ambil voltage desain atau voltase saat ini, default ke 11.1V jika kosong
    voltage=$(cat "$BAT_DIR/voltage_min_design" 2>/dev/null || cat "$BAT_DIR/voltage_now" 2>/dev/null || echo 11100000)
    
    if [ "$charge_design" -gt 0 ]; then
        # Rumus Wh = (uAh * uV) / 10^12
        design_val=$(awk "BEGIN {print ($charge_design * $voltage)/1000000000000}")
        current_val=$(awk "BEGIN {print ($charge_full * $voltage)/1000000000000}")
        
        design_wh=$(printf "%.0f" "$design_val")
        current_wh=$(printf "%.0f" "$current_val")
        health=$(awk "BEGIN {print int(($charge_full/$charge_design)*100)}")
    fi
fi

# 4. Tentukan status alert Checkmk berdasarkan Battery Health (Kesehatan Baterai)
# OK = 0 (Health >= 70%), WARN = 1 (Health 40-69%), CRIT = 2 (Health < 40%)
status=0
if [ "$health" != "N/A" ]; then
    if [ "$health" -lt 40 ]; then
        status=2
    elif [ "$health" -lt 70 ]; then
        status=1
    fi
fi

# 5. Output dalam format kustom yang Anda minta
echo "$status \"Battery_Health\" - Status Battery : $BAT_STATUS | Design Capacity : ${design_wh}w/h | Current Capacity : ${current_wh}w/h | Health : ${health}% | Battery Level : ${BAT_LEVEL}%"
