#!/usr/bin/env bash
# =====================================================================
# Local Check Checkmk: Weekly RAM Health & Physical Slots Monitor
# Scheduled to run once a week on Saturday at 11:00 AM
# =====================================================================
CACHE_DIR="/var/lib/check_mk_agent/cache"
mkdir -p "$CACHE_DIR" 2>/dev/null
CACHE_FILE="$CACHE_DIR/cache_ram_health.txt"

# Get current Day Of Week (1=Monday, ..., 6=Saturday, 7=Sunday) and current Hour
DOW=$(date +%u)
HOUR=$(date +%H)

# Calculate the last Saturday 11:00 AM epoch threshold
case $DOW in
    7) days_ago=1 ;; # Sunday
    6) if [ "$HOUR" -ge 11 ]; then days_ago=0; else days_ago=7; fi ;;
    5) days_ago=6 ;; # Friday
    4) days_ago=5 ;; # Thursday
    3) days_ago=4 ;; # Wednesday
    2) days_ago=3 ;; # Tuesday
    1) days_ago=2 ;; # Monday
esac

LAST_SAT_11=$(date -d "today - $days_ago days 11:00:00" +%s 2>/dev/null)
if [ -z "$LAST_SAT_11" ]; then
    LAST_SAT_11=$(date +%s -d "today - $days_ago days 11:00:00" 2>/dev/null)
fi

need_update() {
    local file=$1
    local threshold=$2
    local log_file="/var/log/checkmk_custom/memtester_health.log"
    
    # Jika file cache belum ada, wajib update
    if [ ! -f "$file" ]; then
        return 0
    fi
    
    local file_ts log_ts=0
    file_ts=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    
    # Jika file log memtester lebih baru dari file cache (karena baru dipicu/selesai), wajib update
    if [ -f "$log_file" ]; then
        log_ts=$(stat -c %Y "$log_file" 2>/dev/null || echo 0)
    fi
    if [ "$log_ts" -gt "$file_ts" ]; then
        return 0
    fi
    
    # Jika file cache lebih tua dari ambang batas Sabtu 11:00 AM terdekat, wajib update
    if [ "$file_ts" -lt "$threshold" ]; then
        return 0
    fi
    return 1
}

if need_update "$CACHE_FILE" "$LAST_SAT_11"; then
    > "$CACHE_FILE"
    
    # -------------------------------------------------------------
    # 1. DETEKSI SLOT RAM FISIK (dmidecode)
    # -------------------------------------------------------------
    if command -v dmidecode >/dev/null 2>&1; then
        dmi_out=$(dmidecode -t 17 2>/dev/null)
        if [ -n "$dmi_out" ]; then
            sizes=$(echo "$dmi_out" | grep -i "Size:" | awk -F: '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            total_slots=0
            used_slots=0
            empty_slots=0
            active_modules=()
            
            while read -r size_val; do
                [ -z "$size_val" ] && continue
                total_slots=$((total_slots + 1))
                if [[ "$size_val" =~ "No Module Installed" ]] || [[ "$size_val" =~ "No Board Installed" ]] || [[ "$size_val" =~ "Unknown" ]]; then
                    empty_slots=$((empty_slots + 1))
                else
                    used_slots=$((used_slots + 1))
                    size_clean=$(echo "$size_val" | tr -d ' ')
                    active_modules+=("$size_clean")
                fi
            done <<< "$sizes"
            
            if [ "$total_slots" -gt 0 ]; then
                active_str=""
                for mod in "${active_modules[@]}"; do
                    if [ -z "$active_str" ]; then
                        active_str="$mod"
                    else
                        active_str="$active_str, $mod"
                    fi
                done
                [ -z "$active_str" ] && active_str="None"
                slot_info="Used Slots: ${used_slots}/${total_slots} (${empty_slots} Empty) ❘ Active Modules: [${active_str}]"
            else
                slot_info="Used Slots: N/A ❘ Active Modules: N/A"
            fi
        else
            slot_info="Used Slots: N/A ❘ Active Modules: N/A"
        fi
    else
        slot_info="Used Slots: N/A (dmidecode not installed) ❘ Active Modules: N/A"
    fi

    # -------------------------------------------------------------
    # 2. PEMBACAAN LOG MEMTESTER (Health Test)
    # -------------------------------------------------------------
    LOG_FILE="/var/log/checkmk_custom/memtester_health.log"
    
    if [ ! -f "$LOG_FILE" ]; then
        # Jika file log tidak ada, anggap status OK karena memtester belum berjalan/baru diinstall
        echo "0 \"RAM_Health\" - Status : OK ❘ Result: Passed ❘ Tested Size: N/A ❘ Last Test: No test run yet ❘ ${slot_info} ❘ Log: Waiting for first scheduled memtester run on Saturday 11:00 AM." >> "$CACHE_FILE"
    else
        # Baca status keberhasilan
        status_line=$(grep "STATUS:" "$LOG_FILE" | tail -n 1)
        sample_line=$(grep "SAMPLE_SIZE:" "$LOG_FILE" | tail -n 1)
        start_line=$(grep "=== MEMTESTER START:" "$LOG_FILE" | tail -n 1)
        
        sample_size=$(echo "$sample_line" | cut -d':' -f2 | xargs)
        [ -z "$sample_size" ] && sample_size="Unknown"
        
        test_time=$(echo "$start_line" | sed 's/=== MEMTESTER START: \(.*\) ===/\1/' | xargs)
        if [ -n "$test_time" ]; then
            formatted_time=$(date -d "$test_time" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$test_time")
        else
            formatted_time=$(date -r "$LOG_FILE" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown Date")
        fi
        
        status_code=0
        status_txt="OK"
        result_txt="Passed"
        log_summary="memtester passed successfully."
        
        if echo "$status_line" | grep -q "FAILED"; then
            status_code=2
            status_txt="Critical"
            result_txt="Failed"
            log_summary=$(grep -v "=== " "$LOG_FILE" | grep -v "STATUS:" | grep -v "SAMPLE_SIZE:" | tail -n 3 | tr '\n' ' ' | xargs)
            [ -z "$log_summary" ] && log_summary="Memory test failed during allocation or testing."
        fi
        
        echo "$status_code \"RAM_Health\" - Status : $status_txt ❘ Result: $result_txt ❘ Tested Size: $sample_size ❘ Last Test: $formatted_time ❘ ${slot_info} ❘ Log: $log_summary" >> "$CACHE_FILE"
    fi
fi

cat "$CACHE_FILE" 2>/dev/null
