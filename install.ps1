# GrapeRoot Pro - one-time setup (Windows)
# Usage:
#   $env:GRAPEROOT_LICENSE_KEY = "GRP-XXXX-XXXX-XXXX"
#   irm https://graperoot.dev/pro/install.ps1 | iex

try {
    $ErrorActionPreference = "Stop"
    # Suppress Invoke-WebRequest progress bar - on PS 5.1 it makes IWR 40x slower
    $ProgressPreference = "SilentlyContinue"

    # TLS - PS 5.1 defaults to TLS 1.0 which many CDNs reject
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    }

    $R2          = if ($env:GRAPEROOT_PRO_R2)  { $env:GRAPEROOT_PRO_R2 }  else { "https://pub-pro-r2.graperoot.dev" }
    $API         = if ($env:GRAPEROOT_PRO_API) { $env:GRAPEROOT_PRO_API } else { "https://api.graperoot.dev" }
    $BASE_URL    = if ($env:GRAPEROOT_PRO_GH)  { $env:GRAPEROOT_PRO_GH }  else { "https://raw.githubusercontent.com/kunal12203/graperoot-pro-public/main" }
    $INSTALL_DIR = "$env:USERPROFILE\.graperoot-pro"
    $FREE_DIR    = "$env:USERPROFILE\.dual-graph"
    $LicenseKey  = $env:GRAPEROOT_LICENSE_KEY

    Write-Host ""
    Write-Host "+==============================================================+" -ForegroundColor Cyan
    Write-Host "|           GrapeRoot Pro - Installer  |  v1.0                 |" -ForegroundColor Cyan
    Write-Host "+==============================================================+" -ForegroundColor Cyan
    Write-Host ""

    if (-not $LicenseKey) {
        Write-Host "[error] License key required." -ForegroundColor Red
        Write-Host ""
        Write-Host "  Usage:"
        Write-Host "    `$env:GRAPEROOT_LICENSE_KEY = 'GRP-XXXX-XXXX-XXXX'"
        Write-Host "    irm https://graperoot.dev/pro/install.ps1 | iex"
        Write-Host ""
        Write-Host "  No license? Purchase at https://graperoot.dev/pro or email sales@graperoot.dev"
        exit 1
    }

    # -----------------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------------
    function Invoke-WebRequestWithRetry {
        param([string]$Uri, [string]$OutFile, [int]$MaxRetries = 4, [int]$TimeoutSec = 60)
        for ($i = 1; $i -le $MaxRetries; $i++) {
            try {
                Invoke-WebRequest $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec
                return
            } catch {
                if ($i -ge $MaxRetries) { throw "Download failed after $MaxRetries tries: $Uri - $($_.Exception.Message)" }
                Start-Sleep -Seconds ([Math]::Min(2 * $i, 8))
            }
        }
    }

    function Confirm-Install([string]$Prompt) {
        $a = Read-Host "$Prompt [Y/n]"
        return ($a -notmatch '^[Nn]')
    }

    # -----------------------------------------------------------------------
    # Prerequisites - Python 3.10+, Claude Code
    # -----------------------------------------------------------------------
    $pyCandidates = @("python3.13","python3.12","python3.11","python3.10","python3","python")
    $pythonCmd = $null
    foreach ($c in $pyCandidates) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) {
            $ok = & $cmd.Source -c "import sys; print('1' if sys.version_info >= (3,10) else '0')" 2>$null
            if ($ok -eq "1") { $pythonCmd = $cmd.Source; break }
        }
    }
    if (-not $pythonCmd) {
        Write-Host "[check] Python 3.10+ NOT installed." -ForegroundColor Yellow
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            if (Confirm-Install "[check] Install Python 3.11 via winget?") {
                winget install -e --id Python.Python.3.11 --accept-source-agreements --accept-package-agreements
                Write-Host "  Re-open PowerShell and run the installer again." -ForegroundColor Yellow
                exit 0
            }
        } else {
            Write-Host "  Install Python 3.11 from https://python.org, then re-run." -ForegroundColor Yellow
        }
        exit 1
    }
    Write-Host "[check] Python:       $(& $pythonCmd --version)"

    if (Get-Command rg -ErrorAction SilentlyContinue) {
        Write-Host "[check] ripgrep:      $(rg --version | Select-Object -First 1)"
    } else {
        Write-Host "[check] ripgrep:      NOT FOUND" -ForegroundColor Yellow
        if ((Get-Command winget -ErrorAction SilentlyContinue) -and (Confirm-Install "[check] Install ripgrep via winget?")) {
            winget install -e --id BurntSushi.ripgrep.MSVC --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        } elseif ((Get-Command scoop -ErrorAction SilentlyContinue) -and (Confirm-Install "[check] Install ripgrep via scoop?")) {
            scoop install ripgrep 2>&1 | Out-Null
        } elseif ((Get-Command choco -ErrorAction SilentlyContinue) -and (Confirm-Install "[check] Install ripgrep via Chocolatey?")) {
            choco install ripgrep -y 2>&1 | Out-Null
        } else {
            Write-Host "[warn] Install later via: winget install BurntSushi.ripgrep.MSVC   (needed for fallback_rg / graph_grep_all)" -ForegroundColor Yellow
        }
    }

    $nodeOk = $false
    if (Get-Command node -ErrorAction SilentlyContinue) {
        $nodeVer = (& node -v) 2>$null
        $nodeMajor = if ($nodeVer -match '^v(\d+)') { [int]$Matches[1] } else { 0 }
        if ($nodeMajor -ge 18) {
            Write-Host "[check] Node.js:      $nodeVer"
            $nodeOk = $true
        } else {
            Write-Host "[warn] Node $nodeVer is older than v18; Claude Code may fail. Upgrade recommended." -ForegroundColor Yellow
        }
    }
    if (-not $nodeOk) {
        Write-Host "[check] Node.js:      NOT FOUND" -ForegroundColor Yellow
        $installed = $false
        if ((Get-Command winget -ErrorAction SilentlyContinue) -and (Confirm-Install "[check] Install Node.js (LTS) via winget?")) {
            winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            $installed = $true
        } elseif ((Get-Command scoop -ErrorAction SilentlyContinue) -and (Confirm-Install "[check] Install Node.js via scoop?")) {
            scoop install nodejs-lts 2>&1 | Out-Null
            $installed = $true
        } elseif ((Get-Command choco -ErrorAction SilentlyContinue) -and (Confirm-Install "[check] Install Node.js via Chocolatey?")) {
            choco install nodejs-lts -y 2>&1 | Out-Null
            $installed = $true
        } else {
            Write-Host "[warn] Install Node.js 18+ from https://nodejs.org, then re-run for Claude Code install." -ForegroundColor Yellow
        }
        if ($installed) {
            # Refresh PATH so npm becomes available in this session
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        }
    }

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Host "[check] Claude Code:  installed"
    } elseif (Get-Command claude.cmd -ErrorAction SilentlyContinue) {
        Write-Host "[check] Claude Code:  installed (claude.cmd)"
    } else {
        Write-Host "[check] Claude Code:  NOT FOUND" -ForegroundColor Yellow
        if ((Get-Command npm -ErrorAction SilentlyContinue) -and (Confirm-Install "[check] Install Claude Code via npm?")) {
            npm install -g @anthropic-ai/claude-code
        } else {
            Write-Host "[warn] Install later:  npm install -g @anthropic-ai/claude-code   (needs Node 18+)" -ForegroundColor Yellow
        }
    }

    if (Test-Path $FREE_DIR) {
        Write-Host "[check] GrapeRoot Free detected at $FREE_DIR - Pro will install alongside (free install untouched)"
    }

    # -----------------------------------------------------------------------
    # License verify
    # -----------------------------------------------------------------------
    Write-Host "[verify] Validating license..."
    try {
        $verify = Invoke-RestMethod -Method POST -Uri "$API/v1/license/verify" `
            -ContentType "application/json" -TimeoutSec 15 `
            -Body (@{ license_key = $LicenseKey; host = $env:COMPUTERNAME; os = "windows" } | ConvertTo-Json)
    } catch {
        $errMsg = $_.Exception.Message
        $errBody = ""
        if ($_.Exception.Response) {
            try {
                $reader = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errBody = $reader.ReadToEnd()
                $reader.Close()
            } catch {}
        }
        Write-Host "[error] License server unreachable: $errMsg" -ForegroundColor Red
        if ($errBody) { Write-Host "        Server response: $errBody" -ForegroundColor Red }
        Write-Host "        URL tried: $API/v1/license/verify" -ForegroundColor Yellow
        Write-Host "        If on a corporate network, ask IT to whitelist *.graperoot.dev" -ForegroundColor Yellow
        Write-Host "        Support: support@graperoot.dev"
        exit 1
    }
    if (-not $verify.valid) {
        Write-Host "[error] License rejected: $($verify.reason)" -ForegroundColor Red
        Write-Host "        Support: support@graperoot.dev"
        exit 1
    }
    Write-Host "[verify] Valid  |  $($verify.customer)  |  expires: $($verify.expires)"

    # -----------------------------------------------------------------------
    # Install
    # -----------------------------------------------------------------------
    New-Item -ItemType Directory -Path "$INSTALL_DIR\bin" -Force | Out-Null

    Write-Host "[install] Downloading GrapeRoot Pro package..."
    $tmpTgz = Join-Path $env:TEMP "graperoot-pro.tar.gz"
    Invoke-WebRequestWithRetry -Uri $verify.download_url -OutFile $tmpTgz -TimeoutSec 120
    & tar -xzf $tmpTgz -C $INSTALL_DIR --strip-components=1
    if ($LASTEXITCODE -ne 0) { throw "tar extraction failed (Windows 10 1803+ required, or install Git Bash)" }
    Remove-Item $tmpTgz -ErrorAction SilentlyContinue

    Write-Host "[install] Downloading launcher..."
    foreach ($f in @("launch_pro.ps1","dgc-pro.cmd","dgc-pro.ps1","version.txt","changelog.txt")) {
        $dest = Join-Path "$INSTALL_DIR\bin" $f
        try { Invoke-WebRequestWithRetry -Uri "$R2/bin/$f" -OutFile $dest }
        catch { Invoke-WebRequestWithRetry -Uri "$BASE_URL/bin/$f" -OutFile $dest }
    }

    Write-Host "[install] Creating isolated Python venv..."
    & $pythonCmd -m venv "$INSTALL_DIR\venv" | Out-Null
    $venvPy = "$INSTALL_DIR\venv\Scripts\python.exe"
    & $venvPy -m pip install --quiet --upgrade pip
    & $venvPy -m pip install --quiet -r "$INSTALL_DIR\requirements.txt"

    # License persistence (owner-only ACL)
    $licenseFile = "$INSTALL_DIR\license.key"
    Set-Content -Path $licenseFile -Value $LicenseKey -NoNewline -Encoding ASCII
    $acl = Get-Acl $licenseFile
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name, "Read,Write", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl -Path $licenseFile -AclObject $acl

    # PATH - user scope
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $binDir   = "$INSTALL_DIR\bin"
    if ($userPath -notlike "*$binDir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$binDir;$userPath", "User")
        Write-Host "[install] Added $binDir to user PATH"
    }

    $ver = if (Test-Path "$INSTALL_DIR\bin\version.txt") { (Get-Content "$INSTALL_DIR\bin\version.txt" -Raw).Trim() } else { "1.0.8" }
    Write-Host ""
    Write-Host "+==============================================================+" -ForegroundColor Green
    Write-Host "|  Install complete.  GrapeRoot Pro v$ver" -ForegroundColor Green
    Write-Host "+==============================================================+" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Open a new PowerShell window (PATH refresh), then:"
    Write-Host "    dgc-pro C:\path\to\your\project" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Docs:    https://graperoot.dev/pro/docs"
    Write-Host "  Support: support@graperoot.dev"
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "[fatal] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "        Contact support@graperoot.dev with this message."
    exit 1
}
