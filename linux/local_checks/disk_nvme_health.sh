#!/usr/bin/env python3
import os
import subprocess
import re
import sys

def parse_capacity(smart_output):
    match = re.search(r'User Capacity:\s*([0-9,.\s]+)\s*bytes', smart_output, re.IGNORECASE)
    if match:
        bytes_str = match.group(1).replace(',', '').replace(' ', '').replace('.', '')
        try:
            total_bytes = int(bytes_str)
            gib = total_bytes / (1024**3)
            gb_nominal = total_bytes / (1000**3)
            if gb_nominal >= 900:
                nominal_str = f"{round(gb_nominal/1000)}TB"
            else:
                nominal_str = f"{round(gb_nominal)}GB"
            return f"{nominal_str} ({gib:.2f} GB)", total_bytes
        except:
            pass
    return "Unknown", 0

def parse_smart_line(line):
    line = line.strip()
    clean_line = re.sub(r'\(.*\)', '', line).strip()
    parts = clean_line.split()
    if len(parts) >= 4 and parts[0].isdigit():
        attr_id = int(parts[0])
        attr_name = parts[1]
        norm_val = 100
        if parts[3].isdigit():
            norm_val = int(parts[3])
        raw_val_str = parts[-1]
        num_match = re.search(r'([0-9]+)', raw_val_str)
        if num_match:
            raw_val = int(num_match.group(1))
        else:
            raw_val = 0
        return attr_id, attr_name, norm_val, raw_val
    return None

def get_sata_tb(model, cap_bytes, poh, attr_name, raw_val):
    attr_name_lower = attr_name.lower()
    if "32mib" in attr_name_lower:
        return (raw_val * 32 * 1024 * 1024) / 1e12
    elif "gib" in attr_name_lower or "gb" in attr_name_lower:
        return (raw_val * 1024 * 1024 * 1024) / 1e12
    
    cap_gb = cap_bytes / 1e9 if cap_bytes else 240.0
    known_gb_brands = ["apacer", "v-gen", "kingmax", "phison", "smi", "silicon motion", "patriot", "adata", "kingston"]
    is_known_gb_brand = any(brand in model.lower() for brand in known_gb_brands)
    
    if raw_val > 10000 * cap_gb:
        bytes_val = raw_val * 512
    elif is_known_gb_brand:
        bytes_val = raw_val * 1e9
    elif raw_val < 200000 and poh > 50:
        bytes_val = raw_val * 1e9
    else:
        bytes_val = raw_val * 512
        
    return bytes_val / 1e12

def process_device(device_name):
    device_path = f"/dev/{device_name}"
    try:
        res = subprocess.run(['smartctl', '-a', device_path], capture_output=True, text=True, timeout=5)
        smart_output = res.stdout
    except Exception as e:
        return f"3 \"Storage_Health_{device_name}\" - Error running smartctl: {str(e)}"
        
    if not smart_output or "smartctl" not in smart_output.lower():
        return f"3 \"Storage_Health_{device_name}\" - Error: No smartctl output."

    is_nvme = "NVMe" in smart_output or "nvme" in device_name
    
    model = "Unknown"
    if is_nvme:
        model_match = re.search(r'Model Number:\s*(.*)', smart_output, re.IGNORECASE)
    else:
        model_match = re.search(r'Device Model:\s*(.*)', smart_output, re.IGNORECASE)
        if not model_match:
            model_match = re.search(r'Device:\s*(.*)', smart_output, re.IGNORECASE)
            
    if model_match:
        model = model_match.group(1).strip()
        
    cap_str, cap_bytes = parse_capacity(smart_output)
    
    nominal_cap = cap_str.split()[0]
    if nominal_cap in model:
        gib_part = re.search(r'\(([^)]+)\)', cap_str)
        if gib_part:
            model_display = f"{model} ({gib_part.group(1)})"
        else:
            model_display = f"{model} ({cap_str})"
    else:
        model_display = f"{model} {cap_str}"

    status_match = re.search(r'SMART overall-health self-assessment test result:\s*([^\s\n]+)', smart_output, re.IGNORECASE)
    if not status_match:
        status_match = re.search(r'SMART Health Status:\s*([^\s\n]+)', smart_output, re.IGNORECASE)
    
    raw_status = "PASSED"
    if status_match:
        raw_status = status_match.group(1).strip().upper()
        if "OK" in raw_status or "PASSED" in raw_status:
            raw_status = "PASSED"
        else:
            raw_status = "FAILED"
            
    poh = 0
    temp = 0
    health = 100
    read_tb = 0.0
    written_tb = 0.0
    
    if is_nvme:
        poh_match = re.search(r'Power On Hours:\s*([0-9,]+)', smart_output, re.IGNORECASE)
        if poh_match:
            poh = int(poh_match.group(1).replace(',', ''))
            
        temp_match = re.search(r'Temperature:\s*([0-9]+)\s*Celsius', smart_output, re.IGNORECASE)
        if temp_match:
            temp = int(temp_match.group(1))
            
        used_match = re.search(r'Percentage Used:\s*([0-9]+)%', smart_output, re.IGNORECASE)
        if used_match:
            health = 100 - int(used_match.group(1))
            
        read_match = re.search(r'Data Units Read:\s*([0-9,]+)', smart_output, re.IGNORECASE)
        if read_match:
            read_units = int(read_match.group(1).replace(',', ''))
            read_tb = (read_units * 1000 * 512) / 1e12
            
        write_match = re.search(r'Data Units Written:\s*([0-9,]+)', smart_output, re.IGNORECASE)
        if write_match:
            write_units = int(write_match.group(1).replace(',', ''))
            written_tb = (write_units * 1000 * 512) / 1e12
    else:
        writes_raw = 0
        writes_name = ""
        reads_raw = 0
        reads_name = ""
        
        for line in smart_output.splitlines():
            parsed = parse_smart_line(line)
            if parsed:
                attr_id, attr_name, norm_val, raw_val = parsed
                if attr_id == 9:
                    poh = raw_val
                elif attr_id in [190, 194]:
                    temp = raw_val
                elif attr_id == 231:
                    health = raw_val
                elif attr_id == 233 and health == 100:
                    health = raw_val
                elif attr_id == 177 and health == 100:
                    health = norm_val
                elif attr_id in [241, 225]:
                    writes_raw = raw_val
                    writes_name = attr_name
                elif attr_id in [242, 226]:
                    reads_raw = raw_val
                    reads_name = attr_name
                    
        if writes_raw > 0 and writes_name:
            written_tb = get_sata_tb(model, cap_bytes, poh, writes_name, writes_raw)
        if reads_raw > 0 and reads_name:
            read_tb = get_sata_tb(model, cap_bytes, poh, reads_name, reads_raw)

    days_active = poh / 24.0
    written_gb = written_tb * 1000.0
    write_per_day = written_gb / days_active if days_active > 0.05 else 0.0
    
    wear_percentage = 100 - health
    years_active = poh / 8760.0
    if wear_percentage > 0:
        years_remaining = years_active * (health / wear_percentage)
        est_life_str = f"{years_remaining:.2f} Years"
    else:
        est_life_str = ">10 Years"
        
    chk_status = 0
    if raw_status == "FAILED":
        chk_status = 2
    elif health <= 80:
        chk_status = 2
    elif health <= 90:
        chk_status = 1
        
    status_text = "OK" if chk_status == 0 else ("WARNING" if chk_status == 1 else "CRITICAL")
    
    output_line = f"{chk_status} \"Storage_Health_{device_name}\" - Status : {status_text} ❘ Model: {model_display} ❘ Status: {raw_status} ❘ Temp: {temp}C ❘ Health: {health}% ❘ Read: {read_tb:.1f} TB ❘ Written: {written_tb:.1f} TB ❘ Write/Day: {write_per_day:.2f} GB ❘ Est. Life: {est_life_str}"
    return output_line

def main():
    devices = []
    try:
        for d in os.listdir('/sys/block'):
            if d.startswith('sd') or d.startswith('nvme'):
                devices.append(d)
    except Exception as e:
        print(f"3 \"Storage_Health\" - Error detecting devices: {str(e)}")
        sys.exit(0)
        
    if not devices:
        print("0 \"Storage_Health\" - No block devices detected.")
        sys.exit(0)
        
    for dev in sorted(devices):
        print(process_device(dev))

if __name__ == "__main__":
    main()
