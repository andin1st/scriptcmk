$anydeskId = "Not Installed"
$rustdeskId = "Not Installed"

# ==========================================
# 1. CARI ID ANYDESK
# ==========================================
$adConfig = "C:\ProgramData\AnyDesk\system.conf"
if (Test-Path $adConfig -ErrorAction SilentlyContinue) {
    $adMatch = Select-String -Path $adConfig -Pattern "^ad\.anynet\.id=(\d+)"
    if ($adMatch) { $anydeskId = $adMatch.Matches.Groups[1].Value }
}

# ==========================================
# 2. CARI ID RUSTDESK (Prioritas Bertingkat)
# ==========================================
$rdExe = "C:\Program Files\RustDesk\rustdesk.exe"

# Cek apakah aplikasi RustDesk ada
if (Test-Path $rdExe -ErrorAction SilentlyContinue) {
    
    $rdId = $null

    # -----------------------------------------------------
    # PRIORITAS 1: Coba baca via CLI (--get-id)
    # -----------------------------------------------------
    try {
        $cliOutput = cmd.exe /c "`"$rdExe`" --get-id" 2>$null
        $cleanId = $cliOutput -replace '\s',''
        
        # Validasi apakah hasilnya ada isinya dan bukan pesan error
        if (![string]::IsNullOrEmpty($cleanId) -and $cleanId -notmatch "error") {
            $rdId = $cleanId
        }
    } catch {}

    # -----------------------------------------------------
    # PRIORITAS 2: Coba baca file rustdesk_id.txt (Dummy File)
    # -----------------------------------------------------
    if ([string]::IsNullOrEmpty($rdId)) {
        $dummyFile = "C:\ProgramData\checkmk\agent\rustdesk_id.txt"
        
        if (Test-Path $dummyFile -ErrorAction SilentlyContinue) {
            $rdId = (Get-Content $dummyFile) -replace '\s',''
        }
    }

    # -----------------------------------------------------
    # PRIORITAS 3: Gunakan Hostname
    # -----------------------------------------------------
    if ([string]::IsNullOrEmpty($rdId)) {
        $rdId = $env:COMPUTERNAME
    }

    # Terapkan hasil akhir ke variabel utama
    if (![string]::IsNullOrEmpty($rdId)) {
        $rustdeskId = $rdId
    }
}

# ==========================================
# 3. KIRIM OUTPUT KE CHECKMK
# ==========================================
Write-Host "0 `"Remote_Access_ID`" - OK: AnyDesk: $anydeskId | RustDesk: $rustdeskId"
