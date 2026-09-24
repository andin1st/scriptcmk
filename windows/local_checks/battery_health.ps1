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
    # 1. Check if Battery exists on system
    $Battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    $HasBattery = $false
    if ($Battery) {
        $HasBattery = $true
    } else {
        $StaticData = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue
        if ($StaticData) { $HasBattery = $true }
    }

    if ($HasBattery) {
        # 2. Extract State & Battery Charge Level (%)
        $BatteryLevel = 0
        if ($Battery -and $Battery.EstimatedChargeRemaining) {
            $BatteryLevel = $Battery.EstimatedChargeRemaining
        } else {
            $StatusData = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue
            if ($StatusData -and $StatusData.RemainingCapacity) {
                $BatteryLevel = 100
            }
        }

        $State = "Unknown"
        if ($Battery -and $Battery.BatteryStatus) {
            $StateVal = $Battery.BatteryStatus
            if ($StateVal -eq 1) { $State = "Discharging" }
            elseif ($StateVal -eq 2) { $State = "Fully Charged" }
            elseif ($StateVal -eq 6) { $State = "Charging" }
            else { $State = "AC Power" }
        } else {
            $StatusData = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue
            if ($StatusData) {
                if ($StatusData.PowerOnline) { $State = "Fully Charged" } else { $State = "Discharging" }
            }
        }

        # 3. Extract Design Capacity & Full Charge Capacity (mWh)
        $DesignCapMWh = 0
        $FullCapMWh = 0

        # Primary Method: powercfg /batteryreport /xml
        $XmlPath = Join-Path $env:TEMP "cmk_battery_report.xml"
        try {
            $null = powercfg /batteryreport /xml /output "$XmlPath" 2>$null
            if (Test-Path $XmlPath) {
                [xml]$reportXml = Get-Content $XmlPath -ErrorAction SilentlyContinue
                $batNode = $reportXml.BatteryReport.Batteries.Battery | Select-Object -First 1
                if ($batNode) {
                    if ($batNode.DesignCapacity) { $DesignCapMWh = [long]$batNode.DesignCapacity }
                    if ($batNode.FullChargeCapacity) { $FullCapMWh = [long]$batNode.FullChargeCapacity }
                }
                Remove-Item $XmlPath -Force -ErrorAction SilentlyContinue
            }
        } catch {}

        # Fallback Method 1: powercfg /batteryreport /output HTML parse
        if ($DesignCapMWh -eq 0 -or $FullCapMWh -eq 0) {
            $HtmlPath = Join-Path $env:TEMP "cmk_battery_report.html"
            try {
                $null = powercfg /batteryreport /output "$HtmlPath" 2>$null
                if (Test-Path $HtmlPath) {
                    $htmlContent = Get-Content $HtmlPath -Raw -ErrorAction SilentlyContinue
                    if ($htmlContent -match 'DESIGN CAPACITY\s*</td>\s*<td[^>]*>\s*([0-9,]+)\s*mWh') {
                        $DesignCapMWh = [long]($Matches[1] -replace ',', '')
                    }
                    if ($htmlContent -match 'FULL CHARGE CAPACITY\s*</td>\s*<td[^>]*>\s*([0-9,]+)\s*mWh') {
                        $FullCapMWh = [long]($Matches[1] -replace ',', '')
                    }
                    Remove-Item $HtmlPath -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }

        # Fallback Method 2: CIM root\wmi (BatteryStaticData & BatteryFullChargedCapacity)
        if ($DesignCapMWh -eq 0 -or $FullCapMWh -eq 0) {
            $StaticData = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue
            if ($StaticData -and $StaticData.DesignedCapacity) {
                $DesignCapMWh = [long]$StaticData.DesignedCapacity
            }
            $FullData = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue
            if ($FullData -and $FullData.FullChargedCapacity) {
                $FullCapMWh = [long]$FullData.FullChargedCapacity
            }
        }

        # Fallback Method 3: Win32_Battery WMI
        if ($DesignCapMWh -eq 0 -or $FullCapMWh -eq 0) {
            if ($Battery) {
                if ($Battery.DesignCapacity) { $DesignCapMWh = [long]$Battery.DesignCapacity }
                if ($Battery.FullChargeCapacity) { $FullCapMWh = [long]$Battery.FullChargeCapacity }
            }
        }

        # 4. Compute Wh values & Health SOH (%)
        $DesignWh = [Math]::Round($DesignCapMWh / 1000)
        $FullWh = [Math]::Round($FullCapMWh / 1000)

        if ($DesignCapMWh -gt 0 -and $FullCapMWh -gt 0) {
            $Health = [Math]::Floor(($FullCapMWh / $DesignCapMWh) * 100)
            if ($Health -gt 100) { $Health = 100 }
        } elseif ($DesignWh -gt 0 -and $FullWh -gt 0) {
            $Health = [Math]::Floor(($FullWh / $DesignWh) * 100)
            if ($Health -gt 100) { $Health = 100 }
        } else {
            $Health = 0
        }

        # 5. Evaluate Thresholds: OK >= 60%, WARNING <= 40%, CRITICAL <= 20%
        $Status = 0
        $StatusTxt = "OK"
        if ($Health -le 20) {
            $Status = 2
            $StatusTxt = "Critical"
        } elseif ($Health -le 40) {
            $Status = 1
            $StatusTxt = "Warning"
        }

        $Output = "$Status `"Health_Battery`" - Status Battery : $State ❘ Design Capacity : $($DesignWh)w/h ❘ Current Capacity : $($FullWh)w/h ❘ Health : $($Health)% ❘ Battery Level : $($BatteryLevel)%"
    } else {
        # PC Desktop / No Battery
        $Output = "0 `"Health_Battery`" - Status Battery : N/A ❘ Device is PC/Desktop, there is no battery."
    }

    $Output | Out-File -FilePath $CacheFile -Encoding utf8 -Force
}

Get-Content $CacheFile -ErrorAction SilentlyContinue
