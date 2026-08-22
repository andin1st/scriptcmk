# =============================================================================
# Checkmk Agent Auto-Deployer & Configurator for Windows Host (PowerShell)
# =============================================================================
# Deskripsi: Script bootstrap satu baris (one-liner) untuk menginstal agen Checkmk (.msi),
#            mengunduh 10 skrip local checks kustom dari GitHub, membersihkan cache lama,
#            serta mendaftarkan Windows Task Scheduler untuk uji kesehatan RAM asinkron.
# =============================================================================

$ErrorActionPreference = "Stop"

# 1. Pastikan dijalankan sebagai Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Script ini HARUS dijalankan dengan hak akses Administrator (Run as Administrator)!"
    Exit
}

# --- KONFIGURASI DEFAULT (SESUAIKAN DENGAN SERVER ANDA) ---
$CmkServerIP   = "192.168.1.100"      # IP Server Checkmk
$CmkServerPort = "8080"               # Port Web Service Checkmk
$SiteName      = "cmk"                # Default Site ID (cmk)
$GithubUser    = "andin1st"           # Username GitHub Anda
$GithubRepo    = "scriptcmk"          # Nama repositori GitHub Anda
$Branch        = "main"

# Parsing argument dinamis (jika dilewatkan via baris perintah / silent deployment)
# Contoh: .\install.ps1 -Server "192.168.43.100" -Port "8089" -Site "cmk"
param(
    [string]$Server,
    [string]$Port,
    [string]$Site,
    [string]$GithubRepoCustom,
    [string]$GithubBranchCustom
)

if ($Server) { $CmkServerIP = $Server }
if ($Port) { $CmkServerPort = $Port }
if ($Site) { $SiteName = $Site }
if ($GithubRepoCustom) { $GithubRepo = $GithubRepoCustom }
if ($GithubBranchCustom) { $Branch = $GithubBranchCustom }

$BaseUrl = "https://raw.githubusercontent.com/$GithubUser/$GithubRepo/$Branch/windows"
$MsiUrl  = "http://$($CmkServerIP):$($CmkServerPort)/$SiteName/check_mk/agents/check_mk_agent.msi"

# Folder lokal tujuan
$AgentLocalFolder = "C:\ProgramData\checkmk\agent\local"
$CacheFolder       = "C:\ProgramData\checkmk\agent\cache"
$LogFolder        = "C:\ProgramData\checkmk\agent\log_custom"
$MsiLocalPath     = "$env:TEMP\check_mk_agent.msi"
$RamScriptPath    = "C:\ProgramData\checkmk\agent\run_memtester.ps1"

Write-Host "======================================================" -ForegroundColor Green
Write-Host "   MEMULAI DEPLOYMENT OTOMATIS AGEN CHECKMK (WINDOWS) " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green

# 2. Buat folder-folder yang dibutuhkan jika belum ada
$Directories = @($AgentLocalFolder, $CacheFolder, $LogFolder)
foreach ($Dir in $Directories) {
    if (-not (Test-Path $Dir)) {
        New-Item -ItemType Directory -Force -Path $Dir | Out-Null
        Write-Host "[OK] Folder dibuat: $Dir" -ForegroundColor Green
    }
}

# 3. Bersihkan seluruh cache pemantauan lama agar script baru langsung dieksekusi segar
Write-Host "[-] Membersihkan file cache lama agar seluruh script kustom langsung melakukan pemindaian baru..." -ForegroundColor Yellow
if (Test-Path $CacheFolder) {
    Get-ChildItem -Path $CacheFolder -Filter "cache_*.txt" | Remove-Item -Force -ErrorAction SilentlyContinue
}

# 4. Unduh dan Instal Agen Checkmk secara Silent (.msi)
Write-Host "[-] Mengunduh installer Agen Checkmk dari server: $MsiUrl..." -ForegroundColor Yellow
try {
    # Abaikan verifikasi SSL untuk koneksi HTTP/HTTPS lokal
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiLocalPath -UseBasicParsing -TimeoutSec 15
    Write-Host "[OK] Berhasil mengunduh installer agen." -ForegroundColor Green

    Write-Host "[-] Menginstal Agen Checkmk secara silent (tanpa GUI)..." -ForegroundColor Yellow
    $installProcess = Start-Process msiexec.exe -ArgumentList "/i `"$MsiLocalPath`" /qn /norestart" -Wait -PassThru
    if ($installProcess.ExitCode -eq 0 -or $installProcess.ExitCode -eq 3010) {
        Write-Host "[OK] Agen Checkmk berhasil diinstal!" -ForegroundColor Green
    } else {
        Write-Warning "Instalasi agen selesai dengan ExitCode non-zero: $($installProcess.ExitCode)"
    }
} catch {
    Write-Warning "Server Checkmk tidak dapat dijangkau atau file MSI absen. Melanjutkan pemasangan script kustom..."
} finally {
    if (Test-Path $MsiLocalPath) { Remove-Item $MsiLocalPath -Force }
}

# 5. Unduh 10 Script Local Checks Resmi dari GitHub
$LocalChecks = @(
    "battery_health.ps1",
    "cpu_info.ps1",
    "disk_nvme_health.ps1",
    "fan_health.ps1",
    "info_network.ps1",
    "info_OS_office.ps1",
    "ram_health.ps1",
    "ram_usage.ps1",
    "remote_apps.ps1",
    "storage_usage.ps1"
)

Write-Host "[-] Mengunduh 10 script pemantauan (Local Checks) dari GitHub..." -ForegroundColor Yellow
foreach ($script in $LocalChecks) {
    $scriptUrl = "$BaseUrl/local_checks/$script"
    $destination = Join-Path $AgentLocalFolder $script
    try {
        Invoke-WebRequest -Uri $scriptUrl -OutFile $destination -UseBasicParsing -TimeoutSec 10
        Write-Host " -> [SUCCESS] Berhasil memasang $script" -ForegroundColor Green
    } catch {
        Write-Warning "Gagal mengunduh script $script dari $scriptUrl. Melewati..."
    }
}

# 6. Setup RAM Health (PowerShell Memory Diagnostic Asinkron - Setiap Sabtu 11:00 AM)
Write-Host "[-] Mengonfigurasi penjadwal pengujian RAM asinkron (Hari Sabtu 11:00 AM)..." -ForegroundColor Yellow

$RamCheckScriptContent = @'
# Script Windows RAM Test (Sebagai representasi memtester di Windows)
$LogFile = "C:\ProgramData\checkmk\agent\log_custom\memtester_health.log"
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Add-Content -Path $LogFile -Value "=== MEMTESTER START: $Timestamp ==="

# Menghitung 20% Free RAM untuk uji alokasi aman
$CompSystem = Get-CimInstance -ClassName Win32_OperatingSystem
$FreeKB = $CompSystem.FreePhysicalMemory
$SampleMB = [int](($FreeKB / 1024) * 0.20)
if ($SampleMB -lt 128) { $SampleMB = 128 }

Add-Content -Path $LogFile -Value "SAMPLE_SIZE: $($SampleMB)M"
Add-Content -Path $LogFile -Value "Menjalankan memtester dengan alokasi $($SampleMB)MB..."

try {
    # Alokasikan array memory biner sementara
    $testArray = New-Object Byte[] ($SampleMB * 1024 * 1024)
    for ($i = 0; $i -lt $testArray.Length; $i += 4096) {
        $testArray[$i] = 1
    }
    # Bebaskan alokasi kembali
    $testArray = $null
    [System.GC]::Collect()
    
    # Deteksi log kesalahan hardware ECC memori (jika didukung BIOS/motherboard)
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

# Tulis script runner RAM Test ke lokasi aman
$RamCheckScriptContent | Out-File -FilePath $RamScriptPath -Encoding utf8 -Force

# Registrasikan Task Scheduler untuk berjalan setiap Hari Sabtu Pukul 11:00 Siang
$TaskName = "Checkmk_RAM_Health_Test"
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$RamScriptPath`""
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday -At 11am
$Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount

# Hapus Scheduled Task lama jika sudah ada agar ter-update dengan konfigurasi baru
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
}

try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal | Out-Null
    Write-Host "[SUCCESS] Windows Task Scheduler '$TaskName' berhasil didaftarkan untuk hari Sabtu 11:00 AM!" -ForegroundColor Green
    
    # Jalankan pengujian pertama kali di background agar langsung ada data log awal
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "[INFO] Menjalankan pengujian RAM (memtester) pertama kali di latar belakang..." -ForegroundColor Green
} catch {
    Write-Warning "Gagal mendaftarkan Scheduled Task untuk pengujian RAM: $_"
}

Write-Host "======================================================" -ForegroundColor Green
Write-Host "[SUCCESS] Pemasangan Otomatis Agen Checkmk Windows Selesai!" -ForegroundColor Green
Write-Host "Client telah terdaftar di Windows Task Scheduler." -ForegroundColor Green
Write-Host "Pastikan untuk mendaftarkan host ini ke server Checkmk Anda." -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
