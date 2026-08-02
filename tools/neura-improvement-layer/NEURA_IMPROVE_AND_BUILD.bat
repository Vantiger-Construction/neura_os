@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Invoke-NeuraImprovement.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" echo Neura improvement/build finished with exit code %EXITCODE%.
exit /b %EXITCODE%
