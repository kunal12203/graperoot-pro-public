@echo off
rem graperoot-pro — GrapeRoot Pro multi-platform launcher (Windows cmd shim)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch_pro.ps1" %*
exit /b %ERRORLEVEL%
