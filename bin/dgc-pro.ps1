# dgc-pro — GrapeRoot Pro launcher (Windows PowerShell shim)
$installDir = if ($env:GRAPEROOT_PRO_HOME) { $env:GRAPEROOT_PRO_HOME } else { Join-Path $env:USERPROFILE ".graperoot-pro" }
& "$installDir\venv\Scripts\python.exe" "$installDir\launch.py" @args
exit $LASTEXITCODE
