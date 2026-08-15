@echo off
setlocal
title Build All Neura Upgrades
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BUILD_ALL_NEURA_UPGRADES.ps1"
if errorlevel 1 (
  echo.
  echo [X] The build stopped. Read the error above.
) else (
  echo.
  echo [OK] All available Neura upgrades were built.
)
pause
endlocal
