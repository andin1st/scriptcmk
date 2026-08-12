#!/usr/bin/env python3
# ==============================================================================
# Local Check Checkmk: Storage Health (SATA & NVMe Unified) - v4
# ==============================================================================
import os
import re
import subprocess
import sys

def check_smartctl():
    # Check if smartctl is installed
    try:
        subprocess.run(["smartctl", "--version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except FileNotFoundError:
        return False

def get_storage_devices():
    devices = []
    try:
        # Run smartctl --scan to discover devices
        res = subprocess.run(["smartctl", "--scan"], capture_output=True, text=True, check=True)
        for line in res.stdout.splitlines():
            parts = line.split()
            if parts and parts[0].startswith("/dev/"):
                devices.append(parts[0])
    except Exception:
        pass

    # Fallback to sysfs disk devices if smartctl scan fails or is empty
    if not devices:
        try:
            for dev in os.listdir("/dev/"):
                if re.match(r"^(sd[a-z]|nvme[0-9]+n[0-9]+)$", dev):
                    devices.append(f"/dev/{dev}")
        except Exception:
            pass

    return sorted(list(set(devices)))

def parse_smartctl(device):
    try:
        res = subprocess.run(["smartctl", "-a", device], capture_output=True, text=True)
        text = res.stdout
    except Exception as e:
        return f'3 "Storage_Health_{os.path.basename(device)}" - Status : UNKNOWN ❘ Error running smartctl: {str(e)}'

    if not text.strip():
        return f'3 "Storage_Health_{os.path.basename(device)}" - Status : UNKNOWN ❘ No output from smartctl'

    # Detect device type
    is_nvme = "Device Technology: NVMe" in text or "Model Number:" in text

    # 1. Extract Model Name
    model = "Unknown"
    model_match = re.search(r"Model Number:\s+(.+)", text)
    if not model_match:
        model_match = re.search(r"Device Model:\s+(.+)", text)
    if model_match:
        model = model_match.group(1).strip()

    # 2. Extract Capacity
    capacity_gb_str = "N/A"
    cap_match = re.search(r"(?:Namespace \d+ Size/Capacity:|User Capacity:)\s+([\d,]+)\s+bytes", text)
    if cap_match:
        capacity_bytes = int(cap_match.group(1).replace(",", ""))
        # Convert to GB binary format
        capacity_gb = round(capacity_bytes / (1024**3), 2)
        capacity_gb_str = f"{capacity_gb} GB"

    # 3. Extract Overall SMART Status
    status = "UNKNOWN"
    status_match = re.search(r"test result:\s+(\w+)", text, re.IGNORECASE)
    if status_match:
        status = status_match.group(1).strip().upper()

    # 4. Extract Temperature
    temp = "N/A"
    temp_match = re.search(r"Temperature:\s+(\d+)\s+Celsius", text, re.IGNORECASE)
    if temp_match:
        temp = f"{temp_match.group(1)}C"
    else:
        # Search for temperature attributes in SATA table (Attr 194 or 190)
        for line in text.splitlines():
            if "Temperature_Celsius" in line or "Airflow_Temperature_Cel" in line:
                parts = line.split()
                if len(parts) >= 10:
                    raw_val = parts[9]
                    m = re.match(r"\d+", raw_val)
                    if m:
                        temp = f"{m.group(0)}C"
                        break

    # 5. Extract Power On Hours
    poh = 0
    poh_match = re.search(r"Power On Hours:\s+([\d,]+)", text, re.IGNORECASE)
    if poh_match:
        poh = int(poh_match.group(1).replace(",", ""))
    else:
        for line in text.splitlines():
            if "Power_On_Hours" in line:
                parts = line.split()
                if len(parts) >= 10:
                    raw_val = parts[9].replace(",", "")
                    m = re.match(r"\d+", raw_val)
                    if m:
                        poh = int(m.group(0))
                        break

    # 6. Extract Health (Remaining Life)
    health = 100
    if is_nvme:
        pct_match = re.search(r"Percentage Used:\s+(\d+)%", text)
        if pct_match:
            health = 100 - int(pct_match.group(1))
    else:
        found_health = False
        for line in text.splitlines():
            parts = line.split()
            if len(parts) >= 10:
                attr_id = parts[0]
                attr_name = parts[1]
                # Normalized value is under VALUE column (typically index 3)
                if attr_id in ["231", "169", "173", "177"] or any(x in attr_name.lower() for x in ["ssd_life_left", "life_left", "wear_leveling_count", "remaining_lifetime_perc"]):
                    try:
                        health = int(parts[3])
                        found_health = True
                        break
                    except ValueError:
                        pass
        if not found_health:
            health = 100

    # 7. Extract Data Read & Written (TB)
    read_tb = 0.0
    write_tb = 0.0

    if is_nvme:
        read_match = re.search(r"Data Units Read:\s+[\d,]+\s+\[([\d.]+)\s+([KMGTP]B)\]", text)
        if read_match:
            val = float(read_match.group(1))
            unit = read_match.group(2)
            if unit == "TB": read_tb = val
            elif unit == "GB": read_tb = val / 1000.0
            elif unit == "PB": read_tb = val * 1000.0

        write_match = re.search(r"Data Units Written:\s+[\d,]+\s+\[([\d.]+)\s+([KMGTP]B)\]", text)
        if write_match:
            val = float(write_match.group(1))
            unit = write_match.group(2)
            if unit == "TB": write_tb = val
            elif unit == "GB": write_tb = val / 1000.0
            elif unit == "PB": write_tb = val * 1000.0
    else:
        # SATA attributes processing (LBAs Written / Read)
        for line in text.splitlines():
            parts = line.split()
            if len(parts) >= 10:
                attr_id = parts[0]
                attr_name = parts[1]
                raw_val = parts[9]

                m = re.match(r"\d+", raw_val)
                if m:
                    num_val = int(m.group(0))
                    # Handle Writes
                    if attr_id == "241" or "total_lbas_written" in attr_name.lower() or "host_writes_32mib" in attr_name.lower() or "host_writes_gib" in attr_name.lower() or "lifetime_writes_gib" in attr_name.lower():
                        if "32mib" in attr_name.lower():
                            bytes_written = num_val * 32 * 1024 * 1024
                        elif "gib" in attr_name.lower():
                            bytes_written = num_val * 1024 * 1024 * 1024
                        else:
                            # Standard LBAs (sectors) = 512 bytes
                            bytes_written = num_val * 512
                        write_tb = bytes_written / (10**12)  # Decimal Terabytes

                    # Handle Reads
                    elif attr_id == "242" or "total_lbas_read" in attr_name.lower() or "host_reads_32mib" in attr_name.lower() or "host_reads_gib" in attr_name.lower() or "lifetime_reads_gib" in attr_name.lower():
                        if "32mib" in attr_name.lower():
                            bytes_read = num_val * 32 * 1024 * 1024
                        elif "gib" in attr_name.lower():
                            bytes_read = num_val * 1024 * 1024 * 1024
                        else:
                            bytes_read = num_val * 512
                        read_tb = bytes_read / (10**12)

    # Round read/write TB values
    read_tb = round(read_tb, 1)
    write_tb = round(write_tb, 1)

    # 8. Calculate Write/Day (GB)
    write_day_gb_str = "0.00 GB"
    if poh > 0 and write_tb > 0:
        days = poh / 24.0
        if days > 0:
            write_day_gb = (write_tb * 1000.0) / days
            write_day_gb_str = f"{round(write_day_gb, 2)} GB"

    # 9. Calculate Est. Life (Years)
    est_life = ">10 Years"
    wear = 100 - health
    if wear > 0 and poh > 0:
        years_used = poh / 8760.0
        est_remaining_years = years_used * (100 - wear) / wear
        if est_remaining_years < 10:
            est_life = f"{round(est_remaining_years, 2)} Years"

    # 10. Checkmk Alert Status
    # Standard: OK if Health > 90 (status 0), WARN if Health <= 90 (status 1), CRIT if Health <= 80 (status 2)
    status_code = 0
    status_str = "OK"
    if health <= 80:
        status_code = 2
        status_str = "Critical"
    elif health <= 90:
        status_code = 1
        status_str = "Warning"

    dev_name = os.path.basename(device)
    return f'{status_code} "SSD Health {dev_name}" - Status : {status_str} ❘ Model: {model} ({capacity_gb_str}) ❘ Status: {status} ❘ Temp: {temp} ❘ Health: {health}% ❘ Read: {read_tb} TB ❘ Written: {write_tb} TB ❘ Write/Day: {write_day_gb_str} ❘ Est. Life: {est_life}'

def main():
    if not check_smartctl():
        print('3 "Storage_Health_System" - Status : UNKNOWN ❘ smartctl is not installed on this system.')
        sys.exit(0)

    devices = get_storage_devices()
    if not devices:
        print('3 "Storage_Health_System" - Status : UNKNOWN ❘ No block storage devices discovered.')
        sys.exit(0)

    for dev in devices:
        print(parse_smartctl(dev))

if __name__ == "__main__":
    main()
