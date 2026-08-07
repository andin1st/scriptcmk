# ==========================================
# 1. AMBIL STATUS CHARGER SAAT INI (Via WMI)
# ==========================================
$battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue

if (!$battery) {
    Write-Host "0 `"Battery_Status`" - OK: No battery detected on this device."
    exit
}

$currentCharge = [math]::Round(($battery | Measure-Object EstimatedChargeRemaining -Average).Average, 0)
$statusCode = $battery[0].BatteryStatus

$statusText = switch ($statusCode) {
    1 { "Discharging (On Battery)" }
    2 { "Charging (Plugged In)" }
    3 { "Fully Charged" }
    6 { "Charging" }
    9 { "Critical" }
    10 { "Charging, High" }
    11 { "Charging, Low" }
    default { "Status Code: $statusCode" }
}

# ==========================================
# 2. HITUNG KESEHATAN BATERAI (Via Powercfg XML)
# ==========================================
$designCap = 0
$fullCap = 0
$healthPct = "Unknown"

$xmlPath = "$env:TEMP\checkmk_battery.xml"

try {
    powercfg /batteryreport /xml /output $xmlPath 2>&1 | Out-Null
    
    if (Test-Path $xmlPath) {
        [xml]$xml = Get-Content $xmlPath -ErrorAction SilentlyContinue
        $batteries = $xml.BatteryReport.Batteries.Battery
        
        foreach ($bat in $batteries) {
            if ($bat.DesignCapacity -and $bat.FullChargeCapacity) {
                $designCap += [int]$bat.DesignCapacity
                $fullCap += [int]$bat.FullChargeCapacity
            }
        }
        
        if ($designCap -gt 0) {
            $healthPct = [math]::Round(($fullCap / $designCap) * 100, 1)
            if ($healthPct -gt 100) { $healthPct = 100 }
        }
        
        Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
    }
} catch {
    $healthPct = "Unknown"
}

# ==========================================
# 3. TENTUKAN STATUS CHECKMK & TIMESTAMP
# ==========================================
$exitCode = 0
$stateText = "OK"

if ($currentCharge -le 20) { $exitCode = 1; $stateText = "WARNING" }
if ($currentCharge -le 10) { $exitCode = 2; $stateText = "CRITICAL" }

if ($healthPct -ne "Unknown" -and $healthPct -le 60) {
    if ($exitCode -eq 0) { $exitCode = 1; $stateText = "WARNING" }
}

# Ambil waktu saat ini (Format: YYYY-MM-DD HH:mm:ss)
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# ==========================================
# 4. FORMAT OUTPUT KE CHECKMK
# ==========================================
if ($healthPct -ne "Unknown") {
    $perfData = "charge=$currentCharge;20;10;0;100 health=$healthPct;60;40;0;100"
    Write-Host "$exitCode `"Battery_Status`" $perfData $stateText - Current Level: $currentCharge% ($statusText) | Battery Health: $healthPct% ($fullCap mWh / $designCap mWh) | Last Checked: $timestamp"
} else {
    $perfData = "charge=$currentCharge;20;10;0;100"
    Write-Host "$exitCode `"Battery_Status`" $perfData $stateText - Current Level: $currentCharge% ($statusText) | Battery Health: Unknown | Last Checked: $timestamp"
}
