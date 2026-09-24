# =====================================================================
# Local Check Checkmk: Daily Battery Health Monitor (Windows)
# Scheduled to run once a day at 16:00
# =====================================================================
$CacheDir = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force $CacheDir | Out-Null }
$CacheFile = Join-Path $CacheDir "cache_battery_health.txt"

# Get current hour and today's 16:00 threshold
$Now = Get-Date
$Today16 = Get-Date -Hour 16 -Minute 0 -Second 0
if ($Now -lt $Today16) {
    $Last16 = $Today16.AddDays(-1)
} else {
    $Last16 = $Today16
}

$NeedUpdate = $true
if (Test-Path $CacheFile) {
    $CacheMtime = (Get-Item $CacheFile).LastWriteTime
    if ($CacheMtime -ge $Last16) {
        $NeedUpdate = $false
    }
}

if ($NeedUpdate) {
    $DesignMwh = 0
    $FullMwh = 0
    $BatteryLevel = 0
    $State = "AC Power"
    $HasBattery = $false

    # --- 1. DETEKSI MULTI-LAYER UNTUK UJI KEREADAAN BATERAI ---
    # Layer A: Win32_Battery
    $CimBat = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    if ($CimBat) {
        $HasBattery = $true
        if ($CimBat.EstimatedChargeRemaining) { $BatteryLevel = $CimBat.EstimatedChargeRemaining }
        
        $StateVal = $CimBat.BatteryStatus
        if ($StateVal -eq 1) { $State = "Discharging" }
        elseif ($StateVal -eq 2) { $State = "Fully Charged" }
        elseif ($StateVal -eq 6) { $State = "Charging" }
        
        if ($CimBat.DesignCapacity -and $CimBat.DesignCapacity -gt 0) { $DesignMwh = $CimBat.DesignCapacity }
        if ($CimBat.FullChargeCapacity -and $CimBat.FullChargeCapacity -gt 0) { $FullMwh = $CimBat.FullChargeCapacity }
    }

    # Layer B: WMI root\wmi (ACPI Direct)
    $StaticData = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue
    if ($StaticData) {
        $HasBattery = $true
        if ($StaticData.DesignedCapacity -and $StaticData.DesignedCapacity -gt 0) {
            $DesignMwh = $StaticData.DesignedCapacity
        }
    }
    $FullData = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue
    if ($FullData -and $FullData.FullChargedCapacity -gt 0) {
        $FullMwh = $FullData.FullChargedCapacity
    }
    $StatusData = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue
    if ($StatusData -and $StatusData.RemainingCapacity) {
        if ($FullMwh -gt 0) {
            $BatteryLevel = [int](($StatusData.RemainingCapacity / $FullMwh) * 100)
        }
    }

    # Layer C: powercfg /batteryreport /xml
    $XmlPath = "$env:TEMP\battery_report.xml"
    try {
        $null = powercfg /batteryreport /xml /output $XmlPath 2>$null
        if (Test-Path $XmlPath) {
            [xml]$xml = Get-Content $XmlPath -ErrorAction SilentlyContinue
            $batNode = $xml.BatteryReport.Batteries.Battery | Select-Object -First 1
            if ($batNode) {
                $HasBattery = $true
                if ($batNode.DesignCapacity -and [int]$batNode.DesignCapacity -gt 0) { 
                    $DesignMwh = [int]$batNode.DesignCapacity 
                }
                if ($batNode.FullChargeCapacity -and [int]$batNode.FullChargeCapacity -gt 0) { 
                    $FullMwh = [int]$batNode.FullChargeCapacity 
                }
            }
            Remove-Item $XmlPath -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    # --- 2. PENENTUAN KELUARAN & KALKULASI SOH ---
    if ($HasBattery) {
        # Validasi logis agar Design Capacity tidak bernilai 0 jika Full Charge Capacity ada
        if ($DesignMwh -eq 0 -and $FullMwh -gt 0) { $DesignMwh = $FullMwh }
        
        # Hitung Health SOH
        if ($DesignMwh -gt 0) {
            $Health = [int](($FullMwh / $DesignMwh) * 100)
            if ($Health -gt 100) { $Health = 100 }
        } else {
            $Health = 100
        }

        $DesignWh = [Math]::Round($DesignMwh / 1000)
        $FullWh = [Math]::Round($FullMwh / 1000)

        # Thresholds: OK >= 60%, WARNING <= 40%, CRITICAL <= 20%
        $Status = 0
        $StatusTxt = "OK"
        if ($Health -le 20) {
            $Status = 2
            $StatusTxt = "Critical"
        } elseif ($Health -le 40) {
            $Status = 1
            $StatusTxt = "Warning"
        }

        # ASCII Delimiter (|) murni
        $Output = "$Status `"Health_Battery`" - Status Battery : $State | Design Capacity : $($DesignWh)w/h | Current Capacity : $($FullWh)w/h | Health : $($Health)% | Battery Level : $($BatteryLevel)%"
    } else {
        # PC Desktop / Virtual Machine / Tanpa Baterai
        $Output = "0 `"Health_Battery`" - Status Battery : N/A | Device is PC/Desktop, there is no battery."
    }

    # Simpan dengan ASCII murni
    $Output | Out-File -FilePath $CacheFile -Encoding ascii -Force
}

Get-Content $CacheFile -ErrorAction SilentlyContinue
