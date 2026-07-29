@echo off
setlocal EnableExtensions
set "PROJECT_ROOT=%~1"
if not defined PROJECT_ROOT set "PROJECT_ROOT=%CD%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\Invoke-NeuraBuild.ps1" -Root "%PROJECT_ROOT%" -BuildWindows -BuildApk
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
