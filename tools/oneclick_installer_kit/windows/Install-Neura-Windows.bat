@echo off
setlocal
REM One-click Windows build launcher (calls PowerShell)
powershell -ExecutionPolicy Bypass -File "%~dp0Install-Neura-Windows.ps1"
endlocal
