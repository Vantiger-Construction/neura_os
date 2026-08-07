@echo off
setlocal
set "SCRIPT=%~dp0Build-Neura-GoogleDriveRebuild.ps1"

if not exist "%SCRIPT%" (
  echo [X] Missing build script: "%SCRIPT%"
  exit /b 2
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %ERRORLEVEL%
