#!/usr/bin/env bash
# =====================================================================
# Local Check Checkmk: Weekly RAM Health (Memtester Log Reader)
# Scheduled to update cache every Saturday at 11:00 AM
# =====================================================================
CACHE_DIR="/var/lib/check_mk_agent/cache"
mkdir -p "$CACHE_DIR" 2>/dev/null
CACHE_FILE="$CACHE_DIR/cache_ram_health.txt"

# Get current day of week (1=Mon, 6=Sat, 7=Sun) and hour
DOW=$(date +%u)
CURRENT_HOUR=$(date +%H)

# Calculate epoch for the most recent Saturday at 11:00 AM
if [ "$DOW" -eq 6 ]; then
    if [ "$CURRENT_HOUR" -lt 11 ]; then
        LAST_SAT_11=$(date -d "today - 7 days 11:00:00" +%s 2>/dev/null)
    else
        LAST_SAT_11=$(date -d "today 11:00:00" +%s 2>/dev/null)
    fi
elif [ "$DOW" -eq 7 ]; then
    LAST_SAT_11=$(date -d "today - 1 day 11:00:00" +%s 2>/dev/null)
else
    DAYS=$(( DOW + 1 ))
    LAST_SAT_11=$(date -d "today - $DAYS days 11:00:00" +%s 2>/dev/null)
fi

if [ -z "$LAST_SAT_11" ]; then
    # Fallback to 0 (always update cache if date command fails)
    LAST_SAT_11=0
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

if need_update "$CACHE_FILE" "$LAST_SAT_11"; then
    > "$CACHE_FILE"
    
    LOG_FILE="/var/log/checkmk_custom/memtester_health.log"
    
    if [ ! -f "$LOG_FILE" ]; then
        # If log file doesn't exist yet, assume OK state until scheduled run
        echo "0 \"Health_RAM\" - Status : OK ❘ Result: Passed ❘ Tested Size: N/A ❘ Last Test: No test run yet ❘ Log: Waiting for first scheduled memtester run on Saturday 11:00 AM." >> "$CACHE_FILE"
    else
        # Read test results from log file
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
        
        echo "$status_code \"Health_RAM\" - Status : $status_txt ❘ Result: $result_txt ❘ Tested Size: $sample_size ❘ Last Test: $formatted_time ❘ Log: $log_summary" >> "$CACHE_FILE"
    fi
fi

cat "$CACHE_FILE" 2>/dev/null
