@echo off
setlocal EnableExtensions
set "PROJECT_ROOT=%~1"
if not defined PROJECT_ROOT set "PROJECT_ROOT=%CD%"
set "TOOL=%~dp0..\tools\Neura-DartRepair.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TOOL%" -Root "%PROJECT_ROOT%" -RunAnalyzer -AutoFixStringLiterals
exit /b %ERRORLEVEL%
