#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: Storage Usage (Multi-Partition Detection)
# OK: < 85% | Warning: >= 85% | Critical: >= 95%
# ==============================================================================

WARN=85
CRIT=95

# Get disk usage for local real filesystems (excluding pseudofilesystems)
df -T -P | grep -v -E "Type|tmpfs|devtmpfs|udev|shm|cgroup|sysfs|proc|dev" | while read -r line; do
    [ -z "$line" ] && continue
    
    filesystem=$(echo "$line" | awk '{print $1}')
    fstype=$(echo "$line" | awk '{print $2}')
    total_kb=$(echo "$line" | awk '{print $3}')
    used_kb=$(echo "$line" | awk '{print $4}')
    free_kb=$(echo "$line" | awk '{print $5}')
    pct_str=$(echo "$line" | awk '{print $6}')
    pct=${pct_str%\%} # Remove % sign
    mountpoint=$(echo "$line" | awk '{print $7}')
    
    # Clean mountpoint name for Checkmk service name (remove slashes, replace with underscore)
    svc_suffix=$(echo "$mountpoint" | sed 's|/|_|g')
    if [ "$svc_suffix" = "_" ] || [ -z "$svc_suffix" ]; then
        svc_suffix="_root"
    fi
    
    # Convert KB to GB for readability
    total_gb=$(awk "BEGIN {printf \"%.2f\", $total_kb/1024/1024}")
    free_gb=$(awk "BEGIN {printf \"%.2f\", $free_kb/1024/1024}")
    
    # Determine status
    status=0
    status_txt="OK"
    if [ "$pct" -ge "$CRIT" ]; then
        status=2
        status_txt="Critical"
    elif [ "$pct" -ge "$WARN" ]; then
        status=1
        status_txt="Warning"
    fi
    
    # Output in clean Checkmk format using unicode vertical bar ❘
    echo "$status \"Storage Usage${svc_suffix}\" - Status : $status_txt ❘ Partition: $mountpoint ❘ Used: ${pct}% ❘ Free: ${free_gb} GB ❘ Total: ${total_gb} GB"
done
