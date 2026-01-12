@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0Build-MSIX.ps1"
endlocal
