#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: Storage Usage (Robust Multi-Platform - v2)
# ==============================================================================

# Atur PATH agar skrip dapat menemukan binary df, grep, awk, sed, dll.
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Ambil data kapasitas penyimpanan menggunakan df -PT (POSIX Portability & Type)
# Bendera -P memastikan baris output TIDAK dipotong/dibagi menjadi dua baris 
# meskipun nama perangkat (device name) sangat panjang.
df_output=$(df -PT 2>/dev/null)

# Fallback otomatis jika df -PT gagal
if [ -z "$df_output" ]; then
    df_output=$(df -T 2>/dev/null)
fi

if [ -z "$df_output" ]; then
    df_output=$(df 2>/dev/null)
fi

# Proses baris demi baris, lewati baris header (tail -n +2)
echo "$df_output" | tail -n +2 | while read -r fs type total used avail pct mount; do
    # Lewati jika baris kosong
    [ -z "$fs" ] && continue

    # 1. Kecualikan sistem berkas virtual/semu yang tidak mewakili penyimpanan fisik
    case "$type" in
        tmpfs|devtmpfs|devfs|sysfs|proc|udev|cgroup|squashfs|configfs|debugfs|pstore|bpf|autofs|securityfs|hugetlbfs|mqueue|devpts|fusectl|nsfs)
            continue
            ;;
    esac

    # 2. Tangani kasus 'overlay' (Docker/LXC writable layer):
    # HANYA monitor overlay jika dipasang di root '/' (artinya kita berada di dalam container).
    # Jika dipasang di sub-folder host (seperti /var/lib/docker/overlay2/...), lewati agar tidak redundan.
    if [ "$type" = "overlay" ] && [ "$mount" != "/" ]; then
        continue
    fi

    # 3. Kecualikan direktori sistem virtual dan internal kontainer untuk mencegah duplikasi pemantauan
    case "$mount" in
        /proc*|/sys*|/dev*|/run*|/var/lib/docker*|/var/lib/kubelet*|/snap*)
            continue
            ;;
    esac

    # 4. Hilangkan tanda persen '%' pada data penggunaan
    used_pct=$(echo "$pct" | tr -d '%')
    
    # Validasi apakah nilai persen adalah angka bulat positif
    if ! [[ "$used_pct" =~ ^[0-9]+$ ]]; then
        continue
    fi

    # 5. Konversi block biner (1024-byte blocks) ke satuan GB dengan 2 desimal
    # 1024 * 1024 = 1048576 untuk konversi langsung ke GB
    total_gb=$(awk "BEGIN {printf \"%.2f\", $total / 1048576}")
    used_gb=$(awk "BEGIN {printf \"%.2f\", $used / 1048576}")
    free_gb=$(awk "BEGIN {printf \"%.2f\", $avail / 1048576}")

    # 6. Bersihkan nama mount point agar aman digunakan sebagai Service Name di Checkmk (Slashes dilarang)
    mount_clean=$(echo "$mount" | sed 's|/$|root|' | sed 's|^/||' | sed 's|/|_|g')
    if [ -z "$mount_clean" ]; then
        mount_clean="root"
    fi
    service_name="SSD Usage - ${mount_clean}"

    # 7. Evaluasi Kode Status Checkmk berdasarkan Standar Proyek:
    # OK (0): Usage < 85%
    # WARNING (1): Usage >= 85% dan < 95%
    # CRITICAL (2): Usage >= 95%
    status=0
    if [ "$used_pct" -ge 95 ]; then
        status=2
    elif [ "$used_pct" -ge 85 ]; then
        status=1
    fi

    # Label visual status untuk Checkmk
    status_label="OK"
    if [ "$status" -eq 1 ]; then
        status_label="Warning"
    elif [ "$status" -eq 2 ]; then
        status_label="Critical"
    fi

    # 8. Output dengan format kustom menggunakan pemisah Unicode Light Vertical Bar (❘)
    # serta placeholder '-' untuk kolom perfdata kosong agar Checkmk tidak mengalami error 'Invalid data'
    echo "$status \"$service_name\" - Status : $status_label ❘ Partition: $mount ❘ Used: ${used_pct}% ❘ Free: ${free_gb} GB ❘ Total: ${total_gb} GB"
done
