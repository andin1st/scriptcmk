#!/usr/bin/env python3
import os
import sys
import re
import subprocess

def get_disks():
    disks = []
    try:
        for d in os.listdir('/sys/class/block/'):
            if re.match(r'^sd[a-z]$', d):
                disks.append(d)
            elif re.match(r'^nvme[0-9]+n[0-9]+$', d):
                disks.append(d)
    except Exception:
        pass
    return sorted(disks)

def run_smartctl(device):
    try:
        res = subprocess.run(['smartctl', '-a', f'/dev/{device}'], capture_output=True, text=True, errors='ignore')
        return res.stdout
    except Exception as e:
        return ""

def parse_smart_data(stdout, device):
    if not stdout:
        return None

    # Common fields
    model = "Unknown"
    capacity_gb = "0.00"
    capacity_bytes = 0
    temp = 0
    status_str = "UNKNOWN"
    poh = 0
    is_hdd = False
    
    # Check rotation rate to determine if it is HDD
    rotation_rate_match = re.search(r'Rotation Rate:\s*(.*)', stdout, re.IGNORECASE)
    if rotation_rate_match:
        rot_val = rotation_rate_match.group(1).strip()
        if "Solid State" not in rot_val and rot_val != "0" and "rpm" in rot_val.lower():
            is_hdd = True

    # Parse Model
    model_match = re.search(r'Device Model:\s*(.*)', stdout, re.IGNORECASE)
    if not model_match:
        model_match = re.search(r'Model Number:\s*(.*)', stdout, re.IGNORECASE)
    if model_match:
        model = model_match.group(1).strip()

    # Parse Capacity
    cap_match = re.search(r'User Capacity:\s*([\d,]+)\s*bytes\s*\[(.*?)\]', stdout, re.IGNORECASE)
    if not cap_match:
        cap_match = re.search(r'User Capacity:\s*([\d\s.]+)\s*(GB|TB)', stdout, re.IGNORECASE)
    if cap_match:
        if len(cap_match.groups()) >= 2 and cap_match.group(1).replace(',', '').strip().isdigit():
            bytes_str = cap_match.group(1).replace(',', '').strip()
            capacity_bytes = int(bytes_str)
            capacity_gb = f"{capacity_bytes / (1024**3):.2f}"
        else:
            capacity_gb = cap_match.group(1).strip() + " " + cap_match.group(2).strip()

    # Parse SMART Status
    status_match = re.search(r'SMART overall-health self-assessment test result:\s*(\w+)', stdout, re.IGNORECASE)
    if not status_match:
        status_match = re.search(r'SMART Health Status:\s*(\w+)', stdout, re.IGNORECASE)
    if status_match:
        status_str = status_match.group(1).strip()

    # Parse Temperature
    temp_match = re.search(r'Temperature:\s*(\d+)\s*C', stdout, re.IGNORECASE)
    if not temp_match:
        temp_table_match = re.search(r'194\s+Temperature_Celsius\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)', stdout, re.IGNORECASE)
        if temp_table_match:
            temp = int(temp_table_match.group(1))
        else:
            temp_gen = re.search(r'(Airflow_Temperature_Cel|Temperature_Internal).*?\s(\d+)\s*(?:\(|$)', stdout, re.IGNORECASE)
            if temp_gen:
                temp = int(temp_gen.group(2))
    else:
        temp = int(temp_match.group(1))

    # Parse Power On Hours
    poh_match = re.search(r'Power On Hours:\s*([\d,]+)', stdout, re.IGNORECASE)
    if poh_match:
        poh = int(poh_match.group(1).replace(',', ''))
    else:
        poh_table_match = re.search(r'9\s+Power_On_Hours\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)', stdout, re.IGNORECASE)
        if poh_table_match:
            poh = int(poh_table_match.group(1))

    if is_hdd:
        reallocated = 0
        pending = 0
        
        realloc_match = re.search(r'5\s+Reallocated_Sector_Ct\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)', stdout, re.IGNORECASE)
        if realloc_match:
            reallocated = int(realloc_match.group(1))
            
        pending_match = re.search(r'197\s+Current_Pending_Sector_Ct\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)', stdout, re.IGNORECASE)
        if pending_match:
            pending = int(pending_match.group(1))

        chk_status = 0
        remark = "Disk Condition Good"
        if status_str.upper() != "PASSED" and status_str.upper() != "OK":
            chk_status = 2
            remark = "SMART Status Failed!"
        elif reallocated >= 50 or pending >= 10:
            chk_status = 2
            remark = "Critical bad sectors detected! Replace disk soon."
        elif reallocated > 0 or pending > 0:
            chk_status = 1
            remark = "Warning, some bad sectors detected. Keep monitor!"

        return {
            'is_hdd': True,
            'chk_status': chk_status,
            'model': model,
            'capacity_gb': capacity_gb,
            'status_str': status_str,
            'temp': temp,
            'reallocated': reallocated,
            'pending': pending,
            'poh': poh,
            'remark': remark
        }
    else:
        health = 100
        read_tb = 0.0
        written_tb = 0.0
        
        is_nvme = "Percentage Used" in stdout or "Data Units Written" in stdout
        
        if is_nvme:
            used_match = re.search(r'Percentage Used:\s*(\d+)%', stdout, re.IGNORECASE)
            if used_match:
                health = 100 - int(used_match.group(1))
                
            read_units_match = re.search(r'Data Units Read:\s*([\d,]+)\s+\[(.*?)\]', stdout, re.IGNORECASE)
            if read_units_match:
                unit_str = read_units_match.group(1).replace(',', '')
                read_tb = (int(unit_str) * 512000) / (10**12)
            else:
                bracket_match = re.search(r'Data Units Read:.*?\[(.*?)(?:TB|GB|MB)\]', stdout, re.IGNORECASE)
                if bracket_match:
                    dec_match = re.search(r'([\d.]+)', bracket_match.group(1))
                    if dec_match:
                        read_tb = float(dec_match.group(1))
                        
            write_units_match = re.search(r'Data Units Written:\s*([\d,]+)\s+\[(.*?)\]', stdout, re.IGNORECASE)
            if write_units_match:
                unit_str = write_units_match.group(1).replace(',', '')
                written_tb = (int(unit_str) * 512000) / (10**12)
            else:
                bracket_match = re.search(r'Data Units Written:.*?\[(.*?)(?:TB|GB|MB)\]', stdout, re.IGNORECASE)
                if bracket_match:
                    dec_match = re.search(r'([\d.]+)', bracket_match.group(1))
                    if dec_match:
                        written_tb = float(dec_match.group(1))
        else:
            health_match = re.search(r'231\s+(?:Remaining_Lifetime_Perc|SSD_Life_Left|SSD_Life_Left_Default|Unknown_SSD_Attribute)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)', stdout, re.IGNORECASE)
            if not health_match:
                health_match = re.search(r'233\s+(?:Media_Wearout_Indicator|Wearout_Actual)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)', stdout, re.IGNORECASE)
            if health_match:
                health = int(health_match.group(1))
            else:
                life_remain = re.search(r'Percent_Lifetime_Remain.*?\s(\d+)\s*(?:\(|$)', stdout, re.IGNORECASE)
                if life_remain:
                    health = int(life_remain.group(1))

            write_raw = 0
            read_raw = 0
            write_match = re.search(r'241\s+(?:Total_LBAs_Written|Lifetime_Writes_GiB|Host_Writes_32MiB|Host_Writes_GiB)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)', stdout, re.IGNORECASE)
            if write_match:
                write_raw = int(write_match.group(1))
            read_match = re.search(r'242\s+(?:Total_LBAs_Read|Lifetime_Reads_GiB|Host_Reads_32MiB|Host_Reads_GiB)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)', stdout, re.IGNORECASE)
            if read_match:
                read_raw = int(read_match.group(1))

            known_gb_brands = ['apacer', 'v-gen', 'pny', 'phison', 'smi', 'silicon motion', 'patriot', 'adata', 'kingmax', 'crucial', 'cs900']
            is_gb_scale = False
            for brand in known_gb_brands:
                if brand in model.lower():
                    is_gb_scale = True
                    break
            
            if not is_gb_scale and write_raw > 0:
                if poh > 100 and write_raw < 500000:
                    is_gb_scale = True
                try:
                    cap_val = float(capacity_gb.split()[0])
                    if write_raw > 10000 * cap_val:
                        is_gb_scale = False
                except Exception:
                    pass

            if is_gb_scale:
                written_tb = write_raw / 1000.0
                read_tb = read_raw / 1000.0
            else:
                written_tb = (write_raw * 512) / (10**12)
                read_tb = (read_raw * 512) / (10**12)

        write_day = 0.0
        if poh > 0:
            days = poh / 24.0
            if days > 0:
                write_day = (written_tb * 1000.0) / days

        est_life_str = ">10 Years"
        wear_rate = 100 - health
        if wear_rate > 0 and poh > 0:
            years_used = poh / 8760.0
            est_years = (years_used * health) / wear_rate
            if est_years < 10:
                est_life_str = f"{est_years:.2f} Years"

        chk_status = 0
        if health <= 80:
            chk_status = 2
        elif health <= 90:
            chk_status = 1

        if status_str.upper() != "PASSED" and status_str.upper() != "OK" and status_str.upper() != "UNKNOWN":
            chk_status = 2

        return {
            'is_hdd': False,
            'chk_status': chk_status,
            'model': model,
            'capacity_gb': capacity_gb,
            'status_str': status_str,
            'temp': temp,
            'health': health,
            'read_tb': read_tb,
            'written_tb': written_tb,
            'write_day': write_day,
            'est_life': est_life_str
        }

def main():
    disks = get_disks()
    if not disks:
        print('0 "Storage_Health" - No block devices detected.')
        sys.exit(0)

    if subprocess.run(['which', 'smartctl'], capture_output=True).returncode != 0:
        print('3 "Storage_Health" - Error: smartctl is not installed on this system.')
        sys.exit(0)

    for disk in disks:
        stdout = run_smartctl(disk)
        parsed = parse_smart_data(stdout, disk)
        
        if not parsed:
            print(f'1 "Storage_Health_{disk}" - Status : WARNING ❘ Model: {disk} ❘ Error: Could not parse SMART data.')
            continue

        if parsed['is_hdd']:
            print(f'{parsed["chk_status"]} "Storage_Health_{disk}" - Status : {"OK" if parsed["chk_status"]==0 else "WARNING" if parsed["chk_status"]==1 else "CRITICAL"} ❘ Model: {parsed["model"]} ({parsed["capacity_gb"]} GB) ❘ Status: {parsed["status_str"]} ❘ Temp: {parsed["temp"]}C ❘ Disk Type: HDD ❘ Reallocated Sectors: {parsed["reallocated"]} ❘ Pending Sectors: {parsed["pending"]} ❘ Power On Hours: {parsed["poh"]} Hrs ❘ Remark: {parsed["remark"]}')
        else:
            print(f'{parsed["chk_status"]} "Storage_Health_{disk}" - Status : {"OK" if parsed["chk_status"]==0 else "WARNING" if parsed["chk_status"]==1 else "CRITICAL"} ❘ Model: {parsed["model"]} ({parsed["capacity_gb"]} GB) ❘ Status: {parsed["status_str"]} ❘ Temp: {parsed["temp"]}C ❘ Health: {parsed["health"]}% ❘ Read: {parsed["read_tb"]:.1f} TB ❘ Written: {parsed["written_tb"]:.1f} TB ❘ Write/Day: {parsed["write_day"]:.2f} GB ❘ Est. Life: {parsed["est_life"]}')

if __name__ == '__main__':
    main()
