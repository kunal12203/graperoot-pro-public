$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$scriptDir\launch_pro.ps1" @args
exit $LASTEXITCODE
