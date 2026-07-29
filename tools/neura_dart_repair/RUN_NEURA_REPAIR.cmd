@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Neura Dart Repair
set "ROOT=%~1"
if not defined ROOT set "ROOT=%CD%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Neura-DartRepair.ps1" -Root "%ROOT%" -RunAnalyzer -AutoFixStringLiterals
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo Repair completed with remaining analyzer issues. See .neura_repair\reports in the project.
if "%RC%"=="0" echo Repair and analyzer checks completed successfully.
pause
exit /b %RC%
