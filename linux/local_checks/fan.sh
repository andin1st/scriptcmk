#!/usr/bin/env bash
# ==========================================
# Pemantauan Kesehatan Kipas CPU (Linux)
# ==========================================

# 1. Pastikan lm-sensors terinstal
if ! command -v sensors &> /dev/null; then
    echo "3 \"CPU_Fan_Health\" - UNKNOWN: Aplikasi 'lm-sensors' tidak ditemukan."
    exit 0
fi

# 2. Ekstrak Suhu CPU Tertinggi (Format angka bulat)
# Mencari baris yang mengandung Core, Package, Tctl, atau temp, lalu mengambil angka suhunya
TEMP=$(sensors | grep -iE 'Core|Package|Tctl|CPU|temp' | grep -oE '\+[0-9]+' | tr -d '+' | sort -nr | head -n 1)

# 3. Ekstrak Kecepatan Fan RPM (Mengambil fan pertama yang terdeteksi)
# Mencari kata 'fan' dan mengekstrak angkanya sebelum tulisan RPM
FAN_RPM=$(sensors | grep -i 'fan' | grep -ioE '[0-9]+[[:space:]]*RPM' | grep -oE '[0-9]+' | head -n 1)

# Jika sensor tidak terbaca sama sekali
if [ -z "$TEMP" ] || [ -z "$FAN_RPM" ]; then
    echo "3 \"CPU_Fan_Health\" - UNKNOWN: Gagal membaca sensor Suhu atau Kipas. Pastikan motherboard mendukung pembacaan sensor."
    exit 0
fi

# 4. Logika Penentuan Status (Sesuai Indikator Anda)
exitCode=0
stateText="OK"
details="Kondisi normal."

if [ "$TEMP" -gt 85 ]; then
    if [ "$FAN_RPM" -lt 1600 ]; then
        # SUHU TINGGI + KIPAS LAMBAT = RUSAK
        exitCode=2
        stateText="CRITICAL"
        details="BAHAYA: Suhu overheat (${TEMP}C) tetapi kecepatan Fan tidak normal (${FAN_RPM} RPM). Kipas kemungkinan besar rusak/macet dan perlu diganti!"
    else
        # SUHU TINGGI + KIPAS KENCANG = KERJA BERAT (Bukan rusak fisik)
        exitCode=1
        stateText="WARNING"
        details="Suhu CPU cukup tinggi (${TEMP}C), tetapi Fan merespons dengan baik (${FAN_RPM} RPM)."
    fi
else
    # SUHU NORMAL (Kipas berputar lambat atau bahkan 0 RPM adalah hal wajar jika suhu di bawah 85C)
    details="Suhu aman (${TEMP}C) dan putaran Fan normal (${FAN_RPM} RPM)."
fi

# 5. Output ke Checkmk (Disertai Grafik)
# PerfData digabung dengan pipa (|) tanpa spasi: temp=45|fan=2200
perfData="temp=${TEMP};85;95|fan=${FAN_RPM}"

echo "$exitCode \"CPU_Fan_Health\" $perfData $stateText - $details"
