#!/usr/bin/env bash
# ==============================================================================
# Local Check Checkmk: Storage Health (Unified NVMe & SATA SSD/HDD - v2)
# ==============================================================================

# Ensure smartctl is installed
if ! command -v smartctl >/dev/null 2>&1; then
    echo "3 \"Storage_Health\" - Error: smartctl is not installed on this system."
    exit 0
fi

# Function to parse a single disk
parse_disk() {
    local dev=$1
    local name=$(basename "$dev")
    
    # Run smartctl once and save output to scratch
    local tmp_out="/tmp/smartctl_${name}.out"
    smartctl -a "$dev" > "$tmp_out" 2>/dev/null
    local exit_status=$?
    
    # If smartctl fails completely to read the device
    if [ ! -s "$tmp_out" ]; then
        echo "3 \"Storage_Health_${name}\" - Error: Failed to query smartctl on $dev."
        return
    fi
    
    # Detect if NVMe or SATA
    local is_nvme=false
    if grep -q "Model Number:" "$tmp_out" || grep -q "Percentage Used:" "$tmp_out"; then
        is_nvme=true
    fi
    
    # 1. Model & Size
    local model=""
    local bytes_size=""
    local formatted_size=""
    
    if [ "$is_nvme" = true ]; then
        model=$(grep "Model Number:" "$tmp_out" | cut -d':' -f2- | xargs)
        bytes_size=$(grep "User Capacity:" "$tmp_out" | grep -o -E '[0-9,]+ bytes' | tr -d ',' | awk '{print $1}')
    else
        model=$(grep "Device Model:" "$tmp_out" | cut -d':' -f2- | xargs)
        bytes_size=$(grep "User Capacity:" "$tmp_out" | grep -o -E '[0-9,]+ bytes' | tr -d ',' | awk '{print $1}')
        # Fallback if Device Model not found (some HDDs use Model Family or Vendor)
        if [ -z "$model" ]; then
            model=$(grep "Model Family:" "$tmp_out" | cut -d':' -f2- | xargs)
        fi
        if [ -z "$model" ]; then
            model=$(grep "Vendor:" "$tmp_out" | cut -d':' -f2- | xargs)
        fi
    fi
    
    [ -z "$model" ] && model="Unknown Model"
    
    # Format size (GB / TB)
    if [ -n "$bytes_size" ]; then
        formatted_size=$(awk "BEGIN {printf \"%.2f GB\", $bytes_size / 1073741824}")
        
        # Deduce display capacity (e.g. 1TB, 512GB)
        local gb_rounded=$(awk "BEGIN {print int(($bytes_size / 1000000000) + 0.5)}")
        if [ "$gb_rounded" -ge 1000 ]; then
            local tb_val=$(awk "BEGIN {printf \"%.0f\", $gb_rounded / 1000}")
            display_capacity="${tb_val}TB"
        else
            display_capacity="${gb_rounded}GB"
        fi
    else
        formatted_size="Unknown Size"
        display_capacity=""
    fi
    
    # Deduplicate capacity in model name
    local display_model="$model"
    if [ -n "$display_capacity" ]; then
        if [[ "${model,,}" != *"${display_capacity,,}"* ]]; then
            display_model="$model $display_capacity"
        fi
    fi
    
    # 2. SMART Status
    local smart_status=$(grep "SMART overall-health self-assessment test result:" "$tmp_out" | cut -d':' -f2- | xargs)
    # Fallback for some SATA SMART structures
    if [ -z "$smart_status" ]; then
        smart_status=$(grep "SMART Health Status:" "$tmp_out" | cut -d':' -f2- | xargs)
    fi
    [ -z "$smart_status" ] && smart_status="PASSED" # Fallback default
    
    # 3. Core parameters: Temp, Health, Read, Written, Hours
    local temp="0"
    local health="100"
    local read_tb="0.0"
    local written_tb="0.0"
    local hours=0
    local is_ssd=true
    
    # Check if HDD (has non-zero rotation rate)
    if grep -i -q "Rotation Rate" "$tmp_out"; then
        if ! grep -i -q "Solid State Device" "$tmp_out"; then
            is_ssd=false
        fi
    fi
    
    if [ "$is_nvme" = true ]; then
        # Temperature
        temp=$(grep "Temperature:" "$tmp_out" | grep -o -E '[0-9]+' | head -n1)
        
        # Health (100 - Percentage Used)
        local used=$(grep "Percentage Used:" "$tmp_out" | grep -o -E '[0-9]+' | head -n1)
        if [ -n "$used" ]; then
            health=$((100 - used))
        fi
        
        # Reads and Writes
        local read_bracket=$(grep "Data Units Read:" "$tmp_out" | grep -o -E '\[.*\]' | tr -d '[]')
        local write_bracket=$(grep "Data Units Written:" "$tmp_out" | grep -o -E '\[.*\]' | tr -d '[]')
        
        if [ -n "$read_bracket" ]; then
            read_tb=$(echo "$read_bracket" | awk '{print $1}')
        fi
        if [ -n "$write_bracket" ]; then
            written_tb=$(echo "$write_bracket" | awk '{print $1}')
        fi
        
        # Power On Hours
        hours=$(grep "Power On Hours:" "$tmp_out" | tr -d ',' | grep -o -E '[0-9]+' | head -n1)
        
    else
        # SATA SSD/HDD parsing
        # Temperature: check ID 194 or 190
        temp=$(awk '$1 == 194 || $1 == 190 {print $10}' "$tmp_out" | head -n1 | grep -o -E '[0-9]+' | head -n1)
        [ -z "$temp" ] && temp="0"
        
        # Power On Hours: ID 9
        hours=$(awk '$1 == 9 {print $10}' "$tmp_out" | head -n1 | tr -d ',' | grep -o -E '[0-9]+' | head -n1)
        
        if [ "$is_ssd" = true ]; then
            # Health: check ID 231 (SSD Life Left), 233 (Media Wearout Indicator), or 202
            health=$(awk '$1 == 231 || $1 == 233 || $1 == 202 {print $10}' "$tmp_out" | head -n1 | grep -o -E '[0-9]+' | head -n1)
            [ -z "$health" ] && health="100"
            
            # Written/Read: check ID 241 and 242 (usually in LBAs, 1 LBA = 512 bytes)
            local raw_written_lba=$(awk '$1 == 241 {print $10}' "$tmp_out" | head -n1 | tr -d ',' | grep -o -E '[0-9]+' | head -n1)
            local raw_read_lba=$(awk '$1 == 242 {print $10}' "$tmp_out" | head -n1 | tr -d ',' | grep -o -E '[0-9]+' | head -n1)
            
            if [ -n "$raw_written_lba" ]; then
                written_tb=$(awk "BEGIN {printf \"%.1f\", ($raw_written_lba * 512) / 1000000000000}")
            fi
            if [ -n "$raw_read_lba" ]; then
                read_tb=$(awk "BEGIN {printf \"%.1f\", ($raw_read_lba * 512) / 1000000000000}")
            fi
        else
            health="N/A"
            read_tb="N/A"
            written_tb="N/A"
        fi
    fi
    
    [ -z "$hours" ] && hours=0
    [ -z "$temp" ] && temp="0"
    
    # 4. Write/Day (Total Written in GB / Days)
    local write_day="0.00"
    if [ "$is_ssd" = true ] && [ "$hours" -gt 0 ] && [ "$written_tb" != "N/A" ]; then
        local days=$(awk "BEGIN {print $hours / 24}")
        local written_gb=$(awk "BEGIN {print $written_tb * 1000}")
        write_day=$(awk "BEGIN {printf \"%.2f\", $written_gb / $days}")
    else
        write_day="N/A"
    fi
    
    # 5. Est. Life (Years)
    local est_life=">10"
    if [ "$is_ssd" = true ] && [ "$health" != "N/A" ]; then
        local used_pct=$((100 - health))
        if [ "$used_pct" -gt 0 ] && [ "$hours" -gt 0 ]; then
            local years_active=$(awk "BEGIN {print $hours / 8760}")
            local est_val=$(awk "BEGIN {printf \"%.2f\", $years_active * (100 - $used_pct) / $used_pct}")
            est_life="${est_val} Years"
        else
            est_life=">10 Years"
        fi
    else
        est_life="N/A"
    fi
    
    # Format health display
    local health_display="N/A"
    if [ "$health" != "N/A" ]; then
        health_display="${health}%"
    fi
    
    # Format Read/Write display
    local read_display="N/A"
    local write_display="N/A"
    if [ "$read_tb" != "N/A" ]; then read_display="${read_tb} TB"; fi
    if [ "$written_tb" != "N/A" ]; then write_display="${written_tb} TB"; fi
    
    # Format Write/Day display
    local write_day_display="N/A"
    if [ "$write_day" != "N/A" ]; then write_day_display="${write_day} GB"; fi
    
    # 6. Checkmk Status Evaluation
    local status="OK"
    local checkmk_status=0
    
    # If SMART overall health is failed
    if [[ "$smart_status" != "PASSED" && "$smart_status" != "passed" && "$smart_status" != "OK" && "$smart_status" != "ok" ]]; then
        status="CRITICAL"
        checkmk_status=2
    fi
    
    # Check SSD health threshold
    if [ "$health" != "N/A" ] && [ "$checkmk_status" -eq 0 ]; then
        if [ "$health" -le 80 ]; then
            status="CRITICAL"
            checkmk_status=2
        elif [ "$health" -le 90 ]; then
            status="WARNING"
            checkmk_status=1
        fi
    fi
    
    # Clean up temp file
    rm -f "$tmp_out"
    
    # Final clean output format requested:
    # Status : OK | Model: V-GEN01SM21AR1024ITNVME 1TB (953.87 GB) ❘ Status: PASSED ❘ Temp: 45C ❘ Health: 92% ❘ Read: 27.5 TB ❘ Written: 39.3 TB ❘ Write/Day: 153.55 GB ❘ Est. Life: 8.26 Years
    echo "$checkmk_status \"Storage_Health_${name}\" Status : $status | Model: $display_model ($formatted_size) ❘ Status: $smart_status ❘ Temp: ${temp}C ❘ Health: ${health_display} ❘ Read: ${read_display} ❘ Written: ${write_display} ❘ Write/Day: ${write_day_display} ❘ Est. Life: ${est_life}"
}

# Scan devices
# NVMe drives
for dev in /dev/nvme[0-9]; do
    if [ -b "$dev" ] || [ -c "$dev" ]; then
        parse_disk "$dev"
    fi
done

# SATA drives (sda to sdz)
for dev in /dev/sd[a-z]; do
    if [ -b "$dev" ]; then
        # Exclude partitions (only read the main drive)
        parse_disk "$dev"
    fi
done
