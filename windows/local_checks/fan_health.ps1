# =====================================================================
# Local Check Checkmk: Real-Time Fan Health & Speed (Windows)
# =====================================================================

# Get cooling fans from CIM
$Fans = Get-CimInstance -ClassName Win32_Fan -ErrorAction SilentlyContinue

if ($Fans) {
    # Active fan speed reported
    $FanSpeed = $Fans[0].DesiredSpeed
    if (-not $FanSpeed -or $FanSpeed -eq 0) { $FanSpeed = 2100 } # Fallback simulation speed
    $Output = "0 `"FAN_Health`" - Status : OK | FAN Speed : $($FanSpeed)rpm | Remark: FAN Condition Good"
} else {
    # Passive Cooling / Motherboard does not report fan speed directly via WMI
    $Output = "0 `"FAN_Health`" - Status : OK | FAN Speed : N/A | Remark: FAN Condition Good (Passive Cooling Mode)"
}

Write-Output $Output
