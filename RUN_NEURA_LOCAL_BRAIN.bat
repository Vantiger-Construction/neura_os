@echo off
setlocal
set "ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\Build-Neura-LocalBrain.ps1" -Run
if errorlevel 1 pause
endlocal
