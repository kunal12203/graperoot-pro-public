# dg-pro — GrapeRoot Pro launcher for OpenAI Codex (Windows PowerShell shim)
$installDir = if ($env:GRAPEROOT_PRO_HOME) { $env:GRAPEROOT_PRO_HOME } else { Join-Path $env:USERPROFILE ".graperoot-pro" }
$project = if ($args.Count -gt 0) { $args[0] } else { (Get-Location).Path }
$rest = if ($args.Count -gt 1) { $args[1..($args.Count-1)] } else { @() }
& "$installDir\venv\Scripts\python.exe" "$installDir\launch.py" $project --codex @rest
exit $LASTEXITCODE
