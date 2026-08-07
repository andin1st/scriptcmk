# Local Check: Informasi OS & CPU (Windows)

# Detail OS & Lisensi
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$license = Get-CimInstance -ClassName SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.ApplicationID -eq "55c92734-d682-4d71-983e-d6ec3f16059f" } | Select-Object -First 1
$partialKey = if ($license) { $license.PartialProductKey } else { "Tidak Ditemukan" }

Write-Output "0 `"OS_Detail`" - OS: $($os.Caption) (v$($os.Version) $($os.OSArchitecture)), License_Key: ****-****-****-$partialKey"

# CPU Utilitas & Spesifikasi
$cpu = Get-CimInstance -ClassName Win32_Processor
$cpuUsage = (Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime

$status = 0
if ($cpuUsage -gt 85) { $status = 1 }
if ($cpuUsage -gt 95) { $status = 2 }

Write-Output "$status `"CPU_Usage`" usage=$cpuUsage%;85;95 CPU Utilitas: $cpuUsage%"
Write-Output "0 `"CPU_Model`" - Model: $($cpu.Name), Cores: $($cpu.NumberOfCores), Logical: $($cpu.NumberOfLogicalProcessors)"

# CPU Temperature (Memanfaatkan WMI ThermalZone jika didukung oleh ACPI motherboard)
try {
    $tempK = (Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue).CurrentTemperature
    if ($tempK) {
        $tempC = [math]::Round(($tempK / 10) - 273.15, 1)
        $tStatus = 0
        if ($tempC -gt 75) { $tStatus = 1 }
        if ($tempC -gt 85) { $tStatus = 2 }
        Write-Output "$tStatus `"CPU_Temperature`" temp=$tempC;75;85 Suhu CPU: $tempC C"
    } else {
        Write-Output "3 `"CPU_Temperature`" - Sensor ACPI ThermalZone tidak didukung perangkat keras ini."
    }
} catch {
    Write-Output "3 `"CPU_Temperature`" - Gagal membaca sensor suhu CPU."
}
