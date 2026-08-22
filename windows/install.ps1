# install.ps1 - Script Installer Otomatis Agen Checkmk untuk Windows Client
# Dijalankan via PowerShell Administrator (One-Liner Bypass)

$ErrorActionPreference = "Stop"

# 1. Pastikan script berjalan sebagai Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Script ini HARUS dijalankan sebagai Administrator!"
    Exit
}

# 2. Konfigurasi Variabel (Silakan sesuaikan dengan URL repositori & server Anda)
$GithubUser = "username"
$GithubRepo = "checkmk-agent-deploy"
$Branch     = "main"
$CmkServer  = "http://your-checkmk-server:8080"
$SiteName   = "cmk"

$BaseUrl    = "https://raw.githubusercontent.com/$GithubUser/$GithubRepo/$Branch/windows"
$MsiUrl     = "$CmkServer/$SiteName/check_mk/agents/check_mk_agent.msi"

# Folder lokal tujuan
$AgentLocalFolder = "C:\ProgramData\checkmk\agent\local"
$LogFolder        = "C:\ProgramData\checkmk\agent\log_custom"
$MsiLocalPath     = "$env:TEMP\check_mk_agent.msi"
$RamScriptPath    = "C:\ProgramData\checkmk\agent\run_memtester.ps1"

Write-Host "=== Memulai Instalasi Otomatis Agen Checkmk di Windows ===" -ForegroundColor Cyan

# 3. Buat direktori yang dibutuhkan jika belum ada
if (-not (Test-Path $AgentLocalFolder)) {
    New-Item -ItemType Directory -Force -Path $AgentLocalFolder | Out-Null
    Write-Host "[OK] Folder local checks dibuat: $AgentLocalFolder" -ForegroundColor Green
}
if (-not (Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Force -Path $LogFolder | Out-Null
    Write-Host "[OK] Folder log custom dibuat: $LogFolder" -ForegroundColor Green
}

# 4. Unduh dan Instal Agen Checkmk secara Silent
Write-Host "[-] Mengunduh installer Agen Checkmk dari server..." -ForegroundColor Yellow
try {
    # Abaikan verifikasi SSL jika menggunakan self-signed certificate pada server Checkmk lokal
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiLocalPath -UseBasicParsing
    Write-Host "[OK] Berhasil mengunduh installer agen." -ForegroundColor Green

    Write-Host "[-] Menginstal Agen Checkmk secara silent (tanpa GUI)..." -ForegroundColor Yellow
    $installProcess = Start-Process msiexec.exe -ArgumentList "/i `"$MsiLocalPath`" /qn /norestart" -Wait -PassThru
    if ($installProcess.ExitCode -eq 0 -or $installProcess.ExitCode -eq 3010) {
        Write-Host "[OK] Agen Checkmk berhasil diinstal!" -ForegroundColor Green
    } else {
        Write-Warning "Instalasi agen selesai dengan ExitCode: $($installProcess.ExitCode)"
    }
} catch {
    Write-Error "Gagal mengunduh atau menginstal agen Checkmk: $_"
} finally {
    if (Test-Path $MsiLocalPath) { Remove-Item $MsiLocalPath -Force }
}

# 5. Unduh Script Local Checks dari GitHub
$LocalChecks = @(
    "os_cpu_health.ps1",
    "ram_health.ps1",
    "disk_nvme_health.ps1",
    "remote_apps.ps1",
    "ms_office_status.ps1"
)

Write-Host "[-] Mengunduh script Local Checks dari GitHub..." -ForegroundColor Yellow
foreach ($script in $LocalChecks) {
    $scriptUrl = "$BaseUrl/local_checks/$script"
    $destination = Join-Path $AgentLocalFolder $script
    try {
        Invoke-WebRequest -Uri $scriptUrl -OutFile $destination -UseBasicParsing
        Write-Host " -> [OK] Mengunduh $script" -ForegroundColor Green
    } catch {
        Write-Warning "Gagal mengunduh script: $script dari $scriptUrl. Melewati..."
    }
}

# 6. Setup RAM Health (Pengujian Memtester / Memory Diagnostik Asinkron - 2 Mingguan)
Write-Host "[-] Menyiapkan penjadwalan uji kesehatan RAM (2 mingguan)..." -ForegroundColor Yellow

# Script internal Windows untuk simulasi pengujian memtester asinkron
$RamCheckScriptContent = @'
# Script Windows RAM Test (Sebagai representasi memtester di Windows)
$LogFile = "C:\ProgramData\checkmk\agent\log_custom\memtester_health.log"
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Add-Content -Path $LogFile -Value "=== MEMTESTER START: $Timestamp ==="

# Menjalankan stress memory sederhana menggunakan alokasi objek .NET
# Mengalokasikan 256MB RAM sementara untuk memverifikasi fungsionalitas memori dasar
try {
    Write-Output "Mengalokasikan memori untuk testing..."
    $testArray = New-Object Byte[] (256 * 1024 * 1024) # 256MB
    for ($i = 0; $i -lt $testArray.Length; $i += 4096) {
        $testArray[$i] = 1
    }
    # Kosongkan memory kembali
    $testArray = $null
    [System.GC]::Collect()
    
    # Query logs hardware ECC memory jika didukung perangkat (WMI)
    $memoryErrors = Get-CimInstance -ClassName Win32_MemoryDevice | Where-Object { $_.ErrorCorrecting -eq $true -and $_.ErrorDescription -ne $null }
    
    if ($memoryErrors) {
        Add-Content -Path $LogFile -Value "STATUS: FAILED"
        Add-Content -Path $LogFile -Value "Error details: Terdeteksi kesalahan hardware pada modul RAM."
    } else {
        Add-Content -Path $LogFile -Value "STATUS: SUCCESS"
        Add-Content -Path $LogFile -Value "Memory allocation and system diagnostics passed."
    }
} catch {
    Add-Content -Path $LogFile -Value "STATUS: FAILED"
    Add-Content -Path $LogFile -Value "Error during diagnostic run: $_"
}

$EndTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $LogFile -Value "=== MEMTESTER END: $EndTimestamp ==="
'@

# Simpan script pengujian RAM asinkron ke sistem
$RamCheckScriptContent | Out-File -FilePath $RamScriptPath -Encoding utf8 -Force

# Registrasikan Task Scheduler untuk berjalan setiap 14 Hari sekali pukul 02:00 Pagi
$TaskName = "Checkmk_RAM_Health_Test"
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$RamScriptPath`""
# Jalankan setiap 2 minggu sekali (minggu pertama dan ketiga) pada hari Minggu jam 02.00
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -WeeksInterval 2 -At 2am
$Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount

# Hapus task lama jika sudah ada agar ter-update
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
}

try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal | Out-Null
    Write-Host "[OK] Windows Task Scheduler '$TaskName' berhasil didaftarkan!" -ForegroundColor Green
    
    # Jalankan tes pertama kali di background agar file log langsung terbuat
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "[OK] Menjalankan pengujian RAM inisial pertama kali..." -ForegroundColor Green
} catch {
    Write-Warning "Gagal mendaftarkan Scheduled Task untuk pengujian RAM: $_"
}

Write-Host "=== Proses Instalasi Selesai! Agen Anda Siap Digunakan ===" -ForegroundColor Green
Write-Host "Pastikan untuk melakukan registrasi sertifikat agen ke server Checkmk Anda menggunakan:"
Write-Host "cmk-agent-ctl register --hostname <NAMA_HOST> --server <SERVER_IP>:8000 --site $SiteName --user cmkadmin" -ForegroundColor Yellow
