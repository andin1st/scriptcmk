#!/bin/bash

# Cari folder baterai (biasanya BAT0 atau BAT1)
BAT_PATH=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n 1)

if [ -n "$BAT_PATH" ]; then
    # Ambil data persentase dan status pengisian
    capacity=$(cat "$BAT_PATH/capacity")
    status=$(cat "$BAT_PATH/status")
    
    # Tentukan status alert (0 = OK, 1 = Warning, 2 = Critical)
    state=0
    if [ "$capacity" -le 15 ]; then 
        state=2
    elif [ "$capacity" -le 30 ]; then 
        state=1
    fi
    
    # Output untuk Checkmk
    echo "$state Laptop_Battery capacity=$capacity OK - Status: $status, Kapasitas: $capacity%"
fi
