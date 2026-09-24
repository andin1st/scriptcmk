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

    # --- METHOD 1: Query WMI Win32_Battery ---
    $CimBat = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    if ($CimBat) {
        $HasBattery = $true
        if ($CimBat.EstimatedChargeRemaining) { $BatteryLevel = [int]$CimBat.EstimatedChargeRemaining }
        
        $StateVal = $CimBat.BatteryStatus
        if ($StateVal -eq 1) { $State = "Discharging" }
        elseif ($StateVal -eq 2) { $State = "Fully Charged" }
        elseif ($StateVal -eq 6) { $State = "Charging" }
        else { $State = "AC Power" }
        
        if ($CimBat.DesignCapacity) { $DesignMwh = [long]$CimBat.DesignCapacity }
        if ($CimBat.FullChargeCapacity) { $FullMwh = [long]$CimBat.FullChargeCapacity }
    }

    # --- METHOD 2: Fallback WMI root\wmi (BatteryStaticData & BatteryFullChargedCapacity) ---
    if ($HasBattery -and ($DesignMwh -le 0 -or $FullMwh -le 0)) {
        $StaticData = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue
        if ($StaticData -and $StaticData.DesignedCapacity -gt 0) {
            $DesignMwh = [long]$StaticData.DesignedCapacity
        }
        $FullData = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue
        if ($FullData -and $FullData.FullChargedCapacity -gt 0) {
            $FullMwh = [long]$FullData.FullChargedCapacity
        }
    }

    # --- METHOD 3: Fallback powercfg /batteryreport /xml ---
    if ($HasBattery -and ($DesignMwh -le 0 -or $FullMwh -le 0)) {
        $XmlPath = "$env:TEMP\battery_report.xml"
        try {
            $null = powercfg /batteryreport /xml /output $XmlPath 2>$null
            if (Test-Path $XmlPath) {
                [xml]$xml = Get-Content $XmlPath -ErrorAction SilentlyContinue
                $batNode = $xml.BatteryReport.Batteries.Battery | Select-Object -First 1
                if ($batNode) {
                    if ($batNode.DesignCapacity -and [long]$batNode.DesignCapacity -gt 0) {
                        $DesignMwh = [long]$batNode.DesignCapacity
                    }
                    if ($batNode.FullChargeCapacity -and [long]$batNode.FullChargeCapacity -gt 0) {
                        $FullMwh = [long]$batNode.FullChargeCapacity
                    }
                }
                Remove-Item $XmlPath -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    # --- METHOD 4: Fallback powercfg /batteryreport (HTML parsing) ---
    if ($HasBattery -and ($DesignMwh -le 0 -or $FullMwh -le 0)) {
        $HtmlPath = "$env:TEMP\battery_report.html"
        try {
            $null = powercfg /batteryreport /output $HtmlPath 2>$null
            if (Test-Path $HtmlPath) {
                $htmlContent = Get-Content $HtmlPath -Raw -ErrorAction SilentlyContinue
                if ($htmlContent -match "DESIGN CAPACITY\s*</td>\s*<td[^>]*>\s*([\d\s,]+)\s*mWh") {
                    $DesignMwh = [long]($Matches[1] -replace '[\s,]', '')
                }
                if ($htmlContent -match "FULL CHARGE CAPACITY\s*</td>\s*<td[^>]*>\s*([\d\s,]+)\s*mWh") {
                    $FullMwh = [long]($Matches[1] -replace '[\s,]', '')
                }
                Remove-Item $HtmlPath -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    if ($HasBattery) {
        # Convert mWh to Wh
        $DesignWh = [Math]::Round($DesignMwh / 1000)
        $FullWh = [Math]::Round($FullMwh / 1000)

        # GUARD LOGIC: If DesignWh is 0 but FullWh is > 0 (e.g. 21 Wh), set DesignWh = FullWh
        if ($DesignWh -le 0 -and $FullWh -gt 0) {
            $DesignWh = $FullWh
            $DesignMwh = $FullMwh
        }
        if ($FullWh -le 0 -and $DesignWh -gt 0) {
            $FullWh = $DesignWh
            $FullMwh = $DesignMwh
        }

        # Calculate SOH Health %
        if ($DesignMwh -gt 0) {
            $Health = [int][Math]::Floor(($FullMwh / $DesignMwh) * 100)
            if ($Health -gt 100) { $Health = 100 }
        } else {
            $Health = 100
        }

        # Threshold Evaluation: OK >= 60%, WARNING <= 40%, CRITICAL <= 20%
        $Status = 0
        $StatusTxt = "OK"
        if ($Health -le 20) {
            $Status = 2
            $StatusTxt = "Critical"
        } elseif ($Health -le 40) {
            $Status = 1
            $StatusTxt = "Warning"
        }

        # Format output using ASCII pipe (|) ONLY
        $Output = "$Status `"Health_Battery`" - Status Battery : $State | Design Capacity : $($DesignWh)w/h | Current Capacity : $($FullWh)w/h | Health : $($Health)% | Battery Level : $($BatteryLevel)%"
    } else {
        $Output = "0 `"Health_Battery`" - Status Battery : N/A | Device is PC/Desktop, there is no battery."
    }

    # Force ASCII Encoding to eliminate BOM and Unicode byte corruption in CMD/Checkmk
    $Output | Out-File -FilePath $CacheFile -Encoding ascii -Force
}

Get-Content $CacheFile -ErrorAction SilentlyContinue
