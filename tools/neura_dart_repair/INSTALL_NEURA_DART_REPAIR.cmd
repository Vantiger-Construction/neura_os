@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Install Neura Dart Repair
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Install-NeuraDartRepair.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo Installation failed with exit code %RC%.
pause
exit /b %RC%
