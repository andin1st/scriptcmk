# ==========================================
# 1. DETEKSI LOKASI SMARTMONTOOLS (SCOOP)
# ==========================================
$smartctlPaths = Get-ChildItem -Path "C:\Users\*\scoop\apps\smartmontools\current\bin\smartctl.exe" -ErrorAction SilentlyContinue

if (-not $smartctlPaths) {
    $smartctlPaths = Get-ChildItem -Path "C:\ProgramData\scoop\apps\smartmontools\current\bin\smartctl.exe" -ErrorAction SilentlyContinue
}

if (-not $smartctlPaths) {
    Write-Host "1 `"SMART_Status`" - WARNING: smartmontools (Scoop) tidak ditemukan."
    exit
}

$smartctl = $smartctlPaths[0].FullName

# ==========================================
# 2. DETEKSI SEMUA DISK FISIK
# ==========================================
$disks = Get-PhysicalDisk -ErrorAction SilentlyContinue

if (!$disks) {
    Write-Host "3 `"SMART_Status`" - UNKNOWN: Tidak dapat mendeteksi Physical Disk."
    exit
}

# ==========================================
# 3. ANALISA SETIAP DISK DENGAN SMARTCTL
# ==========================================
foreach ($disk in $disks) {
    $id = $disk.DeviceId
    $name = $disk.FriendlyName
    $serviceName = "SMART_Disk_$id"
    
    $capacityGB = [math]::Round($disk.Size / 1GB, 2)
    
    $cmdOutput = & $smartctl -a "pd$id" 2>&1 | Out-String
    
    $exitCode = 3
    $stateText = "UNKNOWN"
    $details = ""

    # ---- DETEKSI KELULUSAN ----
    if ($cmdOutput -match "PASSED") {
        $exitCode = 0; $stateText = "OK"; $details = "Status: PASSED"
    } elseif ($cmdOutput -match "FAILED") {
        $exitCode = 2; $stateText = "CRITICAL"; $details = "Status: FAILED (Kerusakan Hardware)"
    } elseif ($cmdOutput -match "Unknown USB bridge" -or $disk.BusType -eq "USB") {
        continue 
    } else {
        if ($cmdOutput -match "SMART support is: Disabled" -or $cmdOutput -match "SMART support is: Unavailable") {
            Write-Host "0 `"$serviceName`" - OK - Model: $name | SMART dinonaktifkan."
            continue
        }
    }

    # ---- EKSTRAK SUHU ----
    $temp = "N/A"
    if ($cmdOutput -match 'Temperature:\s+(\d+)\s+Celsius') { $temp = $matches[1] } 
    elseif ($cmdOutput -match '194 Temperature_Celsius.+?-\s+(\d+)') { $temp = $matches[1] }
    elseif ($cmdOutput -match 'Current Drive Temperature:\s+(\d+)') { $temp = $matches[1] }

    # ---- EKSTRAK KESEHATAN (LIFETIME) & PERSENTASE AUS ----
    $healthPct = "N/A"
    $pctUsed = -1 # Variabel khusus untuk perhitungan matematika
    
    if ($cmdOutput -match 'Percentage Used:\s+(\d+)%') { 
        $pctUsed = [int]$matches[1]
        $healthPct = 100 - $pctUsed 
    } elseif ($cmdOutput -match 'Available Spare:\s+(\d+)%') { 
        $healthPct = $matches[1] 
    }

    # ---- EKSTRAK TOTAL READ, WRITE, & POWER ON HOURS ----
    $totalRead = "N/A"
    $totalWrite = "N/A"
    $writeGB = 0
    
    if ($cmdOutput -match 'Data Units Read:\s+[\d,]+\s+\[(.+?)\]') { $totalRead = $matches[1] }
    
    if ($cmdOutput -match 'Data Units Written:\s+[\d,]+\s+\[(.+?)\]') { 
        $totalWrite = $matches[1] 
        # Konversi string ke GB agar bisa dihitung
        if ($totalWrite -match '([\d\.]+)\s*TB') { 
            $writeGB = [double]$matches[1] * 1024 
        } elseif ($totalWrite -match '([\d\.]+)\s*GB') { 
            $writeGB = [double]$matches[1] 
        }
    }

    $powerOnHours = 0
    if ($cmdOutput -match 'Power On Hours:\s+([\d,]+)') {
        $powerOnHours = [int]($matches[1] -replace ',', '')
    }

    # ---- KALKULASI ESTIMASI UMUR (PREDICTIVE ANALYTICS) ----
    $analyticText = ""
    if ($writeGB -gt 0 -and $pctUsed -gt 0 -and $powerOnHours -gt 0) {
        # 1. Hitung Batas Total TBW 100% Aus (dalam GB)
        $totalTBW_GB = $writeGB / ($pctUsed / 100)
        
        # 2. Hitung Pemakaian Harian
        $daysOn = $powerOnHours / 24
        $dailyWriteGB = $writeGB / $daysOn
        
        # 3. Hitung Sisa Umur (Tahun)
        $remainingGB = $totalTBW_GB - $writeGB
        $remainingDays = $remainingGB / $dailyWriteGB
        $remainingYears = [math]::Round(($remainingDays / 365), 2)
        
        $analyticText = " | Write/Day: $([math]::Round($dailyWriteGB, 2)) GB | Est. Life: $remainingYears Years"
    } elseif ($pctUsed -eq 0 -and $writeGB -gt 0) {
        # Jika drive masih terlalu baru dan tingkat keausan belum 1%
        $analyticText = " | Write/Day: N/A | Est. Life: >10 Years (Keausan masih 0%)"
    }

    # ==========================================
    # 4. SUSUN GRAFIK & OUTPUT CHECKMK
    # ==========================================
    $perfMetrics = @()
    $infoText = "Model: $name ($capacityGB GB) | $details"

    if ($temp -ne "N/A") {
        $perfMetrics += "temp=$temp;55;65;0;100"
        $infoText += " | Temp: ${temp}C"
        if ([int]$temp -ge 55 -and $exitCode -eq 0) { $exitCode = 1; $stateText = "WARNING" }
        if ([int]$temp -ge 65) { $exitCode = 2; $stateText = "CRITICAL" }
    }

    if ($healthPct -ne "N/A") {
        $perfMetrics += "health=$healthPct;20;10;0;100"
        $infoText += " | Health: ${healthPct}%"
        if ([int]$healthPct -le 20 -and $exitCode -eq 0) { $exitCode = 1; $stateText = "WARNING" }
        if ([int]$healthPct -le 10) { $exitCode = 2; $stateText = "CRITICAL" }
    }

    if ($totalRead -ne "N/A" -and $totalWrite -ne "N/A") {
        $infoText += " | Read: $totalRead | Written: $totalWrite"
    }
    
    # Tambahkan hasil analitik jika ada
    $infoText += $analyticText

    $perfData = if ($perfMetrics.Count -gt 0) { $perfMetrics -join "|" } else { "-" }

    Write-Host "$exitCode `"$serviceName`" $perfData $stateText - $infoText"
}
