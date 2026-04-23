# Verify a fresh GrapeRoot Pro install on Windows. Used by the smoke test workflow.
$ErrorActionPreference = "Stop"
$proHome = Join-Path $env:USERPROFILE ".graperoot-pro"
$bin     = Join-Path $proHome "bin"

$expected = @(
    $proHome,
    (Join-Path $proHome "license.key"),
    (Join-Path $proHome "mcp_graph_server_v7.4.py"),
    (Join-Path $proHome "graph_builder.py"),
    (Join-Path $proHome "launch.py"),
    (Join-Path $proHome "venv\Scripts\python.exe"),
    (Join-Path $bin "dgc-pro.cmd"),
    (Join-Path $bin "launch_pro.ps1"),
    (Join-Path $bin "version.txt")
)
foreach ($p in $expected) {
    if (-not (Test-Path $p)) { Write-Host "FAIL: missing $p"; exit 1 }
}
Write-Host "[ok] all expected files present"

# Security regression guard: server must NOT bind 0.0.0.0
$serverContent = Get-Content (Join-Path $proHome "mcp_graph_server_v7.4.py") -Raw
if ($serverContent -match [regex]::Escape("0.0.0.0")) {
    Write-Host "FAIL: server binds to 0.0.0.0 - security regression"
    exit 1
}
Write-Host "[ok] server binds 127.0.0.1 only"

$version = (Get-Content (Join-Path $bin "version.txt") -Raw).Trim()
Write-Host "[ok] installed version: $version"

# Python venv + deps importable?
$py = Join-Path $proHome "venv\Scripts\python.exe"
$importsOut = & $py -c "import mcp, uvicorn, starlette, graperoot; print('imports ok')" 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: python imports failed: $importsOut"; exit 1 }
Write-Host "[ok] $importsOut"

# Launch.py runs cleanly via venv python
$launchPy = Join-Path $proHome "launch.py"
$launchVer = & $py $launchPy --version 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: launch.py --version errored: $launchVer"; exit 1 }
Write-Host "[ok] launch.py --version: $launchVer"

Write-Host ""
Write-Host "================================="
Write-Host " ALL WINDOWS CHECKS PASSED  ($version)"
Write-Host "================================="
