# =====================================================================
# Local Check Checkmk: Daily Battery Health Monitor (Windows)
# Pure powercfg /batteryreport implementation (Murni powercfg, No WMI Capacity)
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
    $XmlPath = Join-Path $env:TEMP "battery_report_cmk.xml"
    $HtmlPath = Join-Path $env:TEMP "battery_report_cmk.html"
    if (Test-Path $XmlPath) { Remove-Item $XmlPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path $HtmlPath) { Remove-Item $HtmlPath -Force -ErrorAction SilentlyContinue }

    $HasBattery = $false
    $DesignMwh = 0
    $FullMwh = 0

    # 1. Metode Utama: powercfg /batteryreport /xml
    try {
        $null = powercfg /batteryreport /xml /output $XmlPath 2>$null
        if (Test-Path $XmlPath) {
            [xml]$ReportXml = Get-Content $XmlPath -ErrorAction SilentlyContinue
            $BatNode = $ReportXml.BatteryReport.Batteries.Battery | Select-Object -First 1
            if ($BatNode) {
                $HasBattery = $true
                if ($BatNode.DesignCapacity) { $DesignMwh = [long]$BatNode.DesignCapacity }
                if ($BatNode.FullChargeCapacity) { $FullMwh = [long]$BatNode.FullChargeCapacity }
            }
            Remove-Item $XmlPath -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    # 2. Metode Cadangan: powercfg /batteryreport /output HTML jika XML tidak mengembalikan nilai
    if (-not $HasBattery -or $DesignMwh -le 0) {
        try {
            $null = powercfg /batteryreport /output $HtmlPath 2>$null
            if (Test-Path $HtmlPath) {
                $HtmlContent = Get-Content $HtmlPath -Raw -ErrorAction SilentlyContinue
                
                # RegEx untuk mencari DESIGN CAPACITY dan FULL CHARGE CAPACITY dari Laporan HTML
                if ($HtmlContent -match 'DESIGN CAPACITY\s*</td>\s*<td[^>]*>\s*([0-9,.]+)\s*mWh') {
                    $DesignMwh = [long]($Matches[1] -replace '[,.]', '')
                    $HasBattery = $true
                }
                if ($HtmlContent -match 'FULL CHARGE CAPACITY\s*</td>\s*<td[^>]*>\s*([0-9,.]+)\s*mWh') {
                    $FullMwh = [long]($Matches[1] -replace '[,.]', '')
                    $HasBattery = $true
                }
                Remove-Item $HtmlPath -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    # Status Charger dan Persentase Level Baterai Saat Ini
    $State = "AC Power"
    $BatteryLevel = 100
    $CimBat = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    if ($CimBat) {
        $HasBattery = $true
        if ($CimBat.EstimatedChargeRemaining) { $BatteryLevel = $CimBat.EstimatedChargeRemaining }
        $StateVal = $CimBat.BatteryStatus
        if ($StateVal -eq 1) { $State = "Discharging" }
        elseif ($StateVal -eq 2) { $State = "Fully Charged" }
        elseif ($StateVal -eq 6) { $State = "Charging" }
    }

    if ($HasBattery -and ($DesignMwh -gt 0 -or $FullMwh -gt 0)) {
        # Kalkulasi Murni dari powercfg
        if ($DesignMwh -gt 0) {
            $Health = [int][Math]::Floor(($FullMwh / $DesignMwh) * 100)
            if ($Health -gt 100) { $Health = 100 }
        } else {
            $Health = 100
        }

        $DesignWh = [int][Math]::Round($DesignMwh / 1000)
        $FullWh = [int][Math]::Round($FullMwh / 1000)

        # Evaluasi Status Threshold: OK >= 60%, WARNING <= 40%, CRITICAL <= 20%
        $Status = 0
        $StatusTxt = "OK"
        if ($Health -le 20) {
            $Status = 2
            $StatusTxt = "Critical"
        } elseif ($Health -le 40) {
            $Status = 1
            $StatusTxt = "Warning"
        }

        # Format Keluaran dengan ASCII Pipe | Murni
        $Output = "$Status `"Health_Battery`" - Status Battery : $State | Design Capacity : ${DesignWh}w/h | Current Capacity : ${FullWh}w/h | Health : ${Health}% | Battery Level : ${BatteryLevel}%"
    } else {
        # PC Desktop / Tidak Ada Baterai
        $Output = "0 `"Health_Battery`" - Status Battery : N/A | Device is PC/Desktop, there is no battery."
    }

    # Kunci Enkoding ASCII Murni agar Tidak Ada Karakter Aneh (Mojibake)
    $Output | Out-File -FilePath $CacheFile -Encoding ascii -Force
}

Get-Content $CacheFile -ErrorAction SilentlyContinue
