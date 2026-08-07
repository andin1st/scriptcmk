$anydeskId = "Not Installed"
$rustdeskId = "Not Installed"

# ==========================================
# 1. CARI ID ANYDESK
# ==========================================
$adConfig = "C:\ProgramData\AnyDesk\system.conf"
if (Test-Path $adConfig -ErrorAction SilentlyContinue) {
    $adMatch = Select-String -Path $adConfig -Pattern "^ad\.anynet\.id=(\d+)"
    if ($adMatch) { 
        $anydeskId = $adMatch.Matches.Groups[1].Value 
    }
}

# ==========================================
# 2. CARI ID RUSTDESK (Metode CLI & Config)
# ==========================================
$cliId = $null
$rdExe = "C:\Program Files\RustDesk\rustdesk.exe"

if (Test-Path $rdExe -ErrorAction SilentlyContinue) {
    try {
        $cliOutput = & $rdExe --get-id 2>$null
        $cliId = $cliOutput -replace '\s',''
    } catch {}
}

if (![string]::IsNullOrEmpty($cliId) -and $cliId -match "^\d+$") {
    $rustdeskId = $cliId
} else {
    $tomlPaths = @(
        "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk.toml"
    )
    
    # Tambahkan parameter abaikan error di sini
    $userDirs = Get-ChildItem "C:\Users" -Directory -Force -ErrorAction SilentlyContinue
    foreach ($dir in $userDirs) {
        $tomlPaths += "$($dir.FullName)\AppData\Roaming\RustDesk\config\RustDesk.toml"
    }

    foreach ($path in $tomlPaths) {
        # Tambahkan parameter abaikan error di sini juga
        if (Test-Path $path -ErrorAction SilentlyContinue) {
            $idMatch = Select-String -Path $path -Pattern "^id\s*=\s*'([^']+)'"
            if ($idMatch) {
                $rustdeskId = $idMatch.Matches.Groups[1].Value
                break
            }
            
            $encMatch = Select-String -Path $path -Pattern "^enc_id\s*=\s*'([^']+)'"
            if ($encMatch) {
                $encString = $encMatch.Matches.Groups[1].Value
                $shortEnc = $encString.Substring(0, [math]::Min(10, $encString.Length))
                $rustdeskId = "(Encrypted) " + $shortEnc + "..."
                break
            }
        }
    }
}

# ==========================================
# 3. KIRIM OUTPUT KE CHECKMK
# ==========================================
Write-Host "0 `"Remote_Access_ID`" - OK: AnyDesk: $anydeskId | RustDesk: $rustdeskId"
