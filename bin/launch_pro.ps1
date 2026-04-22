# GrapeRoot Pro — runtime launcher (Windows)
# Called by dgc-pro.cmd / dgc-pro.ps1 shims.

$ErrorActionPreference = "Stop"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {} }

$InstallDir  = if ($env:GRAPEROOT_PRO_HOME) { $env:GRAPEROOT_PRO_HOME } else { "$env:USERPROFILE\.graperoot-pro" }
$BinDir      = Join-Path $InstallDir "bin"
$VenvPy      = Join-Path $InstallDir "venv\Scripts\python.exe"
$LicenseFile = Join-Path $InstallDir "license.key"
$CacheFile   = Join-Path $InstallDir ".license_cache"

$R2       = if ($env:GRAPEROOT_PRO_R2)  { $env:GRAPEROOT_PRO_R2 }  else { "https://pub-pro-r2.graperoot.dev" }
$API      = if ($env:GRAPEROOT_PRO_API) { $env:GRAPEROOT_PRO_API } else { "https://api.graperoot.dev" }
$BaseUrl  = if ($env:GRAPEROOT_PRO_GH)  { $env:GRAPEROOT_PRO_GH }  else { "https://raw.githubusercontent.com/kunal12203/graperoot-pro-public/main" }

function Read-Key { if (Test-Path $LicenseFile) { (Get-Content $LicenseFile -Raw).Trim() } else { $null } }

function Verify-Online {
    $k = Read-Key
    if (-not $k) { return $null }
    try {
        return Invoke-RestMethod -Method POST -Uri "$API/v1/license/verify" `
            -ContentType "application/json" -TimeoutSec 10 `
            -Body (@{ license_key = $k; host = $env:COMPUTERNAME; os = "windows" } | ConvertTo-Json)
    } catch { return $null }
}

function Self-Update {
    $localVer = if (Test-Path "$BinDir\version.txt") { (Get-Content "$BinDir\version.txt" -Raw).Trim() } else { "0" }
    $remoteVer = $null
    foreach ($u in @("$R2/bin/version.txt", "$BaseUrl/bin/version.txt")) {
        try { $remoteVer = (Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 3).Content.Trim(); break } catch {}
    }
    if (-not $remoteVer -or $remoteVer -eq $localVer) { return }

    # Compare as version objects
    try {
        if ([version]$remoteVer -le [version]$localVer) { return }
    } catch { return }

    Write-Host "[update] GrapeRoot Pro $localVer → $remoteVer" -ForegroundColor Cyan
    $resp = Verify-Online
    if ($resp -and $resp.valid -and $resp.download_url) {
        $tmp = Join-Path $env:TEMP "grp-pro-update.tgz"
        try {
            Invoke-WebRequest $resp.download_url -OutFile $tmp -UseBasicParsing -TimeoutSec 60
            & tar -xzf $tmp -C $InstallDir --strip-components=1
            Remove-Item $tmp -ErrorAction SilentlyContinue
            foreach ($f in @("launch_pro.ps1","dgc-pro.cmd","dgc-pro.ps1","version.txt","changelog.txt")) {
                try { Invoke-WebRequest "$R2/bin/$f" -OutFile (Join-Path $BinDir "$f.new") -UseBasicParsing -TimeoutSec 15 } catch { continue }
                Move-Item (Join-Path $BinDir "$f.new") (Join-Path $BinDir $f) -Force
            }
            if (Test-Path "$BinDir\changelog.txt") {
                Get-Content "$BinDir\changelog.txt" -TotalCount 20 | ForEach-Object { Write-Host $_ }
            }
        } catch {
            Write-Host "[update] skipped: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

function Check-License {
    if (-not (Test-Path $LicenseFile)) {
        Write-Host "[error] GrapeRoot Pro: license missing. Re-run the installer." -ForegroundColor Red
        exit 1
    }
    $now = [int][double]::Parse((Get-Date -UFormat %s))
    if (Test-Path $CacheFile) {
        try {
            $c = Get-Content $CacheFile -Raw | ConvertFrom-Json
            if ($c.valid -and ($now - [int]$c.ts) -lt 86400) { return }
        } catch {}
    }
    $resp = Verify-Online
    if (-not $resp) {
        # Offline grace — allow if last-good cache is < 7d old
        if (Test-Path $CacheFile) {
            $c = Get-Content $CacheFile -Raw | ConvertFrom-Json
            if ($c.valid -and ($now - [int]$c.ts) -lt 604800) {
                Write-Host "[dgc-pro] license re-verify offline; running on 7-day grace" -ForegroundColor Yellow
                return
            }
        }
        Write-Host "[error] GrapeRoot Pro: license cannot be verified (offline > 7d). Reconnect and retry." -ForegroundColor Red
        exit 1
    }
    if (-not $resp.valid) {
        Write-Host "[error] GrapeRoot Pro: license rejected — $($resp.reason)" -ForegroundColor Red
        Write-Host "        Support: support@graperoot.dev"
        exit 1
    }
    $cache = @{ valid = $true; ts = $now; customer = $resp.customer; expires = $resp.expires; tier = $resp.tier }
    $cache | ConvertTo-Json | Set-Content $CacheFile -Encoding UTF8
}

Self-Update
Check-License

$Project = if ($args.Count -gt 0) { $args[0] } else { (Get-Location).Path }
$rest    = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

$env:GRAPEROOT_PRO_HOME = $InstallDir
& $VenvPy (Join-Path $InstallDir "launch.py") $Project @rest
exit $LASTEXITCODE
