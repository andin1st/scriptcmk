# =====================================================================
# Local Check Checkmk: Daily Battery Health Monitor (Windows)
# Scheduled to run once a day at 16:00
# =====================================================================
$CacheDir = "$env:ProgramData\checkmk\agent\cache"
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Force $CacheDir | Out-Null }
$CacheFile = Join-Path $CacheDir "cache_battery_health.txt"

$Now = Get-Date
$Today16 = Get-Date -Hour 16 -Minute 0 -Second 0
if ($Now -lt $Today16) { $Last16 = $Today16.AddDays(-1) } else { $Last16 = $Today16 }

$NeedUpdate = $true
if (Test-Path $CacheFile) {
    if ((Get-Item $CacheFile).LastWriteTime -ge $Last16) { $NeedUpdate = $false }
}

if ($NeedUpdate) {
    $HasBattery = $false
    $DesignMwh = 0
    $FullMwh = 0
    $BatteryLevel = 0
    $State = "AC Power"

    # 1. Deteksi WMI Win32_Battery dasar
    $CimBat = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    if ($CimBat) {
        $HasBattery = $true
        $BatteryLevel = $CimBat.EstimatedChargeRemaining
        $StateVal = $CimBat.BatteryStatus
        if ($StateVal -eq 1) { $State = "Discharging" }
        elseif ($StateVal -eq 2) { $State = "Fully Charged" }
        elseif ($StateVal -eq 6) { $State = "Charging" }
        
        $DesignMwh = $CimBat.DesignCapacity
        $FullMwh = $CimBat.FullChargeCapacity
    }

    # 2. Ambil DesignedCapacity riil dari root\wmi (ACPI Direct)
    # Catatan: Win32_Battery sering menyamakan DesignCapacity = FullChargeCapacity (misal 21Wh).
    # root\wmi (BatteryStaticData) menyimpan kapasitas pabrik asli (misal 32Wh / 32000mWh).
    $StaticData = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue
    if ($StaticData) {
        $HasBattery = $true
        $RealDesign = ($StaticData | Select-Object -First 1).DesignedCapacity
        if ($RealDesign -and $RealDesign -gt 0) {
            $DesignMwh = $RealDesign
        }
    }

    $FullData = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue
    if ($FullData) {
        $RealFull = ($FullData | Select-Object -First 1).FullChargedCapacity
        if ($RealFull -and $RealFull -gt 0) {
            $FullMwh = $RealFull
        }
    }

    # 3. Fallback via powercfg /batteryreport /xml jika DesignMwh masih 0 atau sama persis dengan FullMwh
    if ($HasBattery -and ($DesignMwh -le 0 -or $DesignMwh -eq $FullMwh)) {
        $XmlPath = "$env:TEMP\battery_report.xml"
        try {
            $null = powercfg /batteryreport /xml /output $XmlPath 2>$null
            if (Test-Path $XmlPath) {
                [xml]$xml = Get-Content $XmlPath -ErrorAction SilentlyContinue
                $batNode = $xml.BatteryReport.Batteries.Battery | Select-Object -First 1
                if ($batNode) {
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
    }

    if ($HasBattery) {
        # Hitung Health SOH = (FullChargeCapacity / DesignCapacity) * 100
        if ($DesignMwh -gt 0) {
            $Health = [Math]::Floor(($FullMwh / $DesignMwh) * 100)
            if ($Health -gt 100) { $Health = 100 }
        } else {
            $Health = 100
        }

        $DesignWh = [Math]::Round($DesignMwh / 1000)
        $FullWh = [Math]::Round($FullMwh / 1000)

        # Evaluasi Threshold: OK >= 60%, WARNING <= 40%, CRITICAL <= 20%
        $Status = 0
        $StatusTxt = "OK"
        if ($Health -le 20) {
            $Status = 2
            $StatusTxt = "Critical"
        } elseif ($Health -le 40) {
            $Status = 1
            $StatusTxt = "Warning"
        }

        # Format output menggunakan karakter ASCII murni (|)
        $Output = "$Status `"Health_Battery`" - Status Battery : $State | Design Capacity : $($DesignWh)w/h | Current Capacity : $($FullWh)w/h | Health : $($Health)% | Battery Level : $($BatteryLevel)%"
    } else {
        $Output = "0 `"Health_Battery`" - Status Battery : N/A | Device is PC/Desktop, there is no battery."
    }

    # Simpan dengan enkoding ASCII murni agar tidak terdistorsi menjadi karakter aneh
    $Output | Out-File -FilePath $CacheFile -Encoding ascii -Force
}

Get-Content $CacheFile -ErrorAction SilentlyContinue
