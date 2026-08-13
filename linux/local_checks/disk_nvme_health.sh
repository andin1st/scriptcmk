#!/usr/bin/env python3
# ==============================================================================
# Local Check Checkmk: Storage Health (Unified SATA HDD, SATA SSD, and NVMe SSD)
# ==============================================================================

import subprocess
import re
import os
import sys

def check_smartctl_installed():
    """Check if smartctl is installed and accessible."""
    try:
        subprocess.run(["smartctl", "--version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        return True
    except (subprocess.SubprocessError, FileNotFoundError):
        return False

def scan_devices():
    """Scan for devices using smartctl --scan."""
    devices = []
    try:
        out = subprocess.check_output(["smartctl", "--scan"], text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            parts = line.split()
            if parts:
                dev_path = parts[0]
                dev_name = os.path.basename(dev_path)
                
                # Exclude loop, ram, and virtual block devices
                if any(x in dev_name for x in ["loop", "ram", "dm-", "md"]):
                    continue
                    
                # Extract type if specified (-d)
                dev_type = ""
                for i, part in enumerate(parts):
                    if part == '-d' and i + 1 < len(parts):
                        dev_type = parts[i+1]
                devices.append((dev_path, dev_name, dev_type))
    except Exception:
        pass
    return devices

def get_nvme_info(dev_path, dev_name):
    """Parse NVMe health metrics."""
    try:
        out = subprocess.check_output(["smartctl", "-a", dev_path], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return None
        
    model = "Unknown NVMe"
    capacity_str = "Unknown Capacity"
    temp = "N/A"
    health_pct = 100
    read_tb_str = "0.0 TB"
    written_tb_str = "0.0 TB"
    poh = 0
    status = "PASSED"
    
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("Model Number:"):
            model = line.split(":", 1)[1].strip()
        elif line.startswith("Total NVM Capacity:"):
            cap_parts = line.split(":", 1)[1].strip()
            # Extract e.g. [1.02 TB]
            m = re.search(r'\[(.*?)\]', cap_parts)
            if m:
                capacity_str = m.group(1)
        elif line.startswith("Temperature:"):
            m = re.search(r'(\d+)\s+Celsius', line)
            if m:
                temp = m.group(1)
        elif line.startswith("Percentage Used:"):
            m = re.search(r'(\d+)%', line)
            if m:
                used = int(m.group(1))
                health_pct = 100 - used
        elif line.startswith("Data Units Read:"):
            m = re.search(r'\[(.*?)\]', line)
            if m:
                read_tb_str = m.group(1)
        elif line.startswith("Data Units Written:"):
            m = re.search(r'\[(.*?)\]', line)
            if m:
                written_tb_str = m.group(1)
        elif line.startswith("Power On Hours:"):
            val = line.split(":", 1)[1].strip().replace(",", "").replace(".", "")
            m = re.search(r'(\d+)', val)
            if m:
                poh = int(m.group(1))
        elif "SMART overall-health self-assessment result:" in line:
            status = line.split(":", 1)[1].strip()

    # Calculate Write/Day and Est Life
    write_val_tb = 0.0
    m_w = re.match(r'([0-9.]+)\s*([A-Z]+)', written_tb_str)
    if m_w:
        val, unit = m_w.groups()
        val = float(val)
        if unit == 'TB':
            write_val_tb = val
        elif unit == 'GB':
            write_val_tb = val / 1024.0

    poh_days = poh / 24.0
    if poh_days > 0:
        write_day_gb = (write_val_tb * 1024.0) / poh_days
        write_day_str = f"{write_day_gb:.2f} GB"
    else:
        write_day_str = "0.00 GB"

    used_pct = 100 - health_pct
    if used_pct > 0:
        years_active = poh / 8760.0
        est_life_val = (years_active * (100.0 - used_pct)) / used_pct
        est_life = f"{est_life_val:.2f} Years"
    else:
        est_life = ">10 Years"

    # Status Code
    code = 0
    if health_pct <= 80:
        code = 2
    elif health_pct <= 90:
        code = 1

    desc = f"Status : OK ❘ Model: {model} ({capacity_str}) ❘ Status: {status} ❘ Temp: {temp}C ❘ Health: {health_pct}% ❘ Read: {read_tb_str} ❘ Written: {written_tb_str} ❘ Write/Day: {write_day_str} ❘ Est. Life: {est_life}"
    if code == 1:
        desc = desc.replace("Status : OK ❘", "Status : WARNING ❘")
    elif code == 2:
        desc = desc.replace("Status : OK ❘", "Status : CRITICAL ❘")

    return code, desc

def get_sata_info(dev_path, dev_name):
    """Parse SATA health metrics for HDD and SSD."""
    # 1. Run smartctl -i
    try:
        info_out = subprocess.check_output(["smartctl", "-i", dev_path], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return None
        
    model = "Unknown SATA"
    capacity_str = "Unknown Capacity"
    is_ssd = True  # Default to SSD if undetermined
    
    for line in info_out.splitlines():
        line = line.strip()
        if line.startswith("Device Model:") or line.startswith("Model Family:"):
            if "Device Model:" in line:
                model = line.split(":", 1)[1].strip()
            elif model == "Unknown SATA" and "Model Family:" in line:
                model = line.split(":", 1)[1].strip()
        elif line.startswith("User Capacity:"):
            cap_parts = line.split(":", 1)[1].strip()
            # e.g., "120,034,123,456 bytes [120 GB]"
            m = re.search(r'\[(.*?)\]', cap_parts)
            if m:
                capacity_str = m.group(1)
        elif "Rotation Rate:" in line:
            rot = line.split(":", 1)[1].strip().lower()
            if "solid state" in rot or "non-rotational" in rot:
                is_ssd = True
            elif "rpm" in rot or "spinning" in rot:
                is_ssd = False

    # 2. Run smartctl -H
    try:
        health_out = subprocess.check_output(["smartctl", "-H", dev_path], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        health_out = ""
        
    status = "PASSED"
    for line in health_out.splitlines():
        if "test result:" in line.lower() or "self-assessment result:" in line.lower():
            status = line.split(":", 1)[1].strip()

    # 3. Run smartctl -A to gather raw attributes
    try:
        attr_out = subprocess.check_output(["smartctl", "-A", dev_path], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        attr_out = ""
        
    attrs = {}
    for line in attr_out.splitlines():
        parts = line.split()
        if parts and parts[0].isdigit():
            attr_id = int(parts[0])
            name = parts[1]
            raw_val = parts[-1]
            attrs[attr_id] = (name, raw_val)

    # Common Attribute Extraction
    poh = 0
    if 9 in attrs:
        m = re.search(r'(\d+)', attrs[9][1])
        if m:
            poh = int(m.group(1))
            
    temp = "N/A"
    if 194 in attrs:
        m = re.search(r'(\d+)', attrs[194][1])
        if m:
            temp = m.group(1)
    elif 190 in attrs:
        m = re.search(r'(\d+)', attrs[190][1])
        if m:
            temp = m.group(1)

    if is_ssd:
        # ==========================================
        # SSD LOGIC (SATA SSD)
        # ==========================================
        health_pct = 100
        # Check SSD health/life attributes (ID 231, 233, or 169)
        if 231 in attrs:
            m = re.search(r'(\d+)', attrs[231][1])
            if m:
                health_pct = int(m.group(1))
        elif 233 in attrs:
            m = re.search(r'(\d+)', attrs[233][1])
            if m:
                health_pct = int(m.group(1))
        elif 169 in attrs: # Sometimes used for SandForce remaining life
            m = re.search(r'(\d+)', attrs[169][1])
            if m:
                health_pct = int(m.group(1))

        # Check raw bytes calculations
        write_raw = 0
        read_raw = 0
        write_name = ""
        read_name = ""
        
        if 241 in attrs:
            write_name = attrs[241][0]
            try:
                write_raw = int(re.search(r'(\d+)', attrs[241][1]).group(1))
            except Exception:
                pass
        if 242 in attrs:
            read_name = attrs[242][0]
            try:
                read_raw = int(re.search(r'(\d+)', attrs[242][1]).group(1))
            except Exception:
                pass

        def calculate_bytes(raw_val, attr_name, model_name):
            if raw_val <= 0:
                return 0.0
            
            attr_name_lower = attr_name.lower()
            model_lower = model_name.lower()
            
            # Check 1: Explicitly labeled blocks/units in name
            if "32mib" in attr_name_lower:
                return raw_val * 32.0 * 1024.0 * 1024.0
            elif "gb" in attr_name_lower:
                return raw_val * (10**9)
            elif "gib" in attr_name_lower:
                return raw_val * (2**30)
            elif "sectors" in attr_name_lower:
                return raw_val * 512.0
                
            # Check 2: LBA Named but behaves as GB / Sectors
            if "lba" in attr_name_lower:
                if "samsung" in model_lower:
                    # Samsung drives use real 512B sectors for ID 241
                    return raw_val * 512.0
                else:
                    # Non-Samsung (Apacer CS900, PNY, V-Gen, Phison, SMI, etc.)
                    # If raw value is very large, e.g. > 50 million, it's sectors.
                    # If it's small, it represents GB!
                    if raw_val > 50000000:
                        return raw_val * 512.0
                    else:
                        return raw_val * (10**9)
            
            # Check 3: Default to GB if small, sectors if huge
            if raw_val > 50000000:
                return raw_val * 512.0
            else:
                return raw_val * (10**9)

        write_val_bytes = calculate_bytes(write_raw, write_name, model)
        read_val_bytes = calculate_bytes(read_raw, read_name, model)
        
        read_tb_val = read_val_bytes / (10**12)
        written_tb_val = write_val_bytes / (10**12)
        
        read_tb_str = f"{read_tb_val:.1f} TB"
        written_tb_str = f"{written_tb_val:.1f} TB"
        
        # Power on days calculation
        poh_days = poh / 24.0
        if poh_days > 0:
            write_day_gb = (write_val_bytes / (10**9)) / poh_days
            write_day_str = f"{write_day_gb:.2f} GB"
        else:
            write_day_str = "0.00 GB"
            
        used_pct = 100 - health_pct
        if used_pct > 0:
            years_active = poh / 8760.0
            est_life_val = (years_active * (100.0 - used_pct)) / used_pct
            est_life = f"{est_life_val:.2f} Years"
        else:
            est_life = ">10 Years"
            
        code = 0
        if health_pct <= 80:
            code = 2
        elif health_pct <= 90:
            code = 1
            
        desc = f"Status : OK ❘ Model: {model} ({capacity_str}) ❘ Status: {status} ❘ Temp: {temp}C ❘ Health: {health_pct}% ❘ Read: {read_tb_str} ❘ Written: {written_tb_str} ❘ Write/Day: {write_day_str} ❘ Est. Life: {est_life}"
        if code == 1:
            desc = desc.replace("Status : OK ❘", "Status : WARNING ❘")
        elif code == 2:
            desc = desc.replace("Status : OK ❘", "Status : CRITICAL ❘")
            
        return code, desc

    else:
        # ==========================================
        # HDD LOGIC (SATA HDD)
        # ==========================================
        # Hard disks care about: Reallocated_Sector_Ct (5), Current_Pending_Sector_Ct (197), Offline_Uncorrectable (198)
        reallocated = 0
        if 5 in attrs:
            try:
                reallocated = int(re.search(r'(\d+)', attrs[5][1]).group(1))
            except Exception:
                pass
                
        pending = 0
        if 197 in attrs:
            try:
                pending = int(re.search(r'(\d+)', attrs[197][1]).group(1))
            except Exception:
                pass
                
        offline_uncorrectable = 0
        if 198 in attrs:
            try:
                offline_uncorrectable = int(re.search(r'(\d+)', attrs[198][1]).group(1))
            except Exception:
                pass
                
        # Determine status code and message based on bad sectors
        code = 0
        disk_remark = "Disk Condition Good"
        
        if status.upper() != "PASSED" or reallocated >= 50 or pending > 10 or offline_uncorrectable > 0:
            code = 2
            disk_remark = "Please check Harddisk, bad sectors detected!"
        elif reallocated > 0 or pending > 0:
            code = 1
            disk_remark = "Warning, some bad sectors detected. Keep monitor!"
            
        desc = f"Status : {'OK' if code == 0 else ('WARNING' if code == 1 else 'CRITICAL')} ❘ Model: {model} ({capacity_str}) ❘ Status: {status} ❘ Temp: {temp}C ❘ Disk Type: HDD ❘ Reallocated Sectors: {reallocated} ❘ Pending Sectors: {pending} ❘ Power On Hours: {poh} Hrs ❘ Remark: {disk_remark}"
        return code, desc

def main():
    if not check_smartctl_installed():
        print("3 \"Storage Health\" - Error: smartctl is not installed on this system.")
        sys.exit(0)
        
    devices = scan_devices()
    if not devices:
        print("0 \"Storage Health\" - No block devices detected.")
        sys.exit(0)
        
    for dev_path, dev_name, dev_type in devices:
        # Determine if NVMe or SATA
        if dev_type == "nvme" or "nvme" in dev_name:
            res = get_nvme_info(dev_path, dev_name)
        else:
            res = get_sata_info(dev_path, dev_name)
            
        if res:
            code, desc = res
            # Emit in Checkmk Local Check format
            print(f"{code} \"Storage Health {dev_name}\" - {desc}")

if __name__ == "__main__":
    main()
