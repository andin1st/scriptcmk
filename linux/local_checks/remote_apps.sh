#!/bin/bash

anydesk_id="Not Installed"
rustdesk_id="Not Installed"

# ==========================================
# 1. CARI ID ANYDESK
# ==========================================
if [ -f "/etc/anydesk/system.conf" ]; then
    ad_id=$(grep "^ad.anynet.id=" /etc/anydesk/system.conf | cut -d'=' -f2)
    if [ -n "$ad_id" ]; then
        anydesk_id="$ad_id"
    fi
fi

# ==========================================
# 2. CARI ID RUSTDESK (Dengan Prioritas Bertingkat)
# ==========================================
# Cek apakah RustDesk terinstal (Native atau Flatpak)
if command -v rustdesk >/dev/null 2>&1 || flatpak list | grep -q com.rustdesk.RustDesk; then
    
    rd_id=""
    active_user=$(who | awk '{print $1}' | head -n 1)
    
    # -----------------------------------------------------
    # PRIORITAS 1: Coba baca via CLI (--get-id)
    # -----------------------------------------------------
    if command -v rustdesk >/dev/null 2>&1; then
        # Instalasi Native
        if [ -n "$active_user" ] && [ "$active_user" != "root" ]; then
            rd_id=$(su - "$active_user" -c "rustdesk --get-id 2>/dev/null" | tr -d '[:space:]')
        else
            rd_id=$(rustdesk --get-id 2>/dev/null | tr -d '[:space:]')
        fi
    else
        # Instalasi Flatpak
        if [ -n "$active_user" ] && [ "$active_user" != "root" ]; then
            rd_id=$(su - "$active_user" -c "flatpak run com.rustdesk.RustDesk --get-id 2>/dev/null" | tr -d '[:space:]')
        else
            rd_id=$(flatpak run com.rustdesk.RustDesk --get-id 2>/dev/null | tr -d '[:space:]')
        fi
    fi

    # -----------------------------------------------------
    # PRIORITAS 2: Coba baca file rustdesk_id.txt
    # -----------------------------------------------------
    # (Jika hasil CLI kosong, gagal, atau error)
    if [[ -z "$rd_id" || "$rd_id" == *"error"* || "$rd_id" == *"Failed"* ]]; then
        DUMMY_FILE="/etc/rustdesk_id.txt"
        
        if [ -f "$DUMMY_FILE" ]; then
            rd_id=$(cat "$DUMMY_FILE" | tr -d '[:space:]')
        fi
    fi

    # -----------------------------------------------------
    # PRIORITAS 3: Gunakan Hostname
    # -----------------------------------------------------
    # (Jika file dummy juga tidak ada atau kosong)
    if [ -z "$rd_id" ]; then
        rd_id=$(hostname)
    fi

    # Terapkan hasil akhir ke variabel utama
    if [ -n "$rd_id" ]; then
        rustdesk_id="$rd_id"
    fi
fi

# ==========================================
# 3. KIRIM OUTPUT KE CHECKMK
# ==========================================
echo "0 \"Remote Support\" - OK: AnyDesk: $anydesk_id | RustDesk: $rustdesk_id"
