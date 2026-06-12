@echo off
if defined GRAPEROOT_PRO_HOME (
    set "_GRP=%GRAPEROOT_PRO_HOME%"
) else (
    set "_GRP=%USERPROFILE%\.graperoot-pro"
)
"%_GRP%\venv\Scripts\python.exe" "%_GRP%\launch.py" %*
