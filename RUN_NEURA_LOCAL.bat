@echo off
setlocal EnableExtensions
title Neura Local Build

set "ROOT=%~dp0"
cd /d "%ROOT%"

echo ======================================
echo        NEURA LOCAL BUILD
echo ======================================
echo Root: %CD%
echo.

where powershell >nul 2>&1 || (
  echo [X] PowerShell was not found.
  pause
  exit /b 1
)

where flutter >nul 2>&1 || (
  echo [X] Flutter was not found in PATH.
  echo Install Flutter and Visual Studio Desktop development with C++.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\Neura-FastCheck.ps1" -Root "%ROOT%" -BuildWindows
set "STATUS=%ERRORLEVEL%"

if not "%STATUS%"=="0" (
  echo.
  echo [X] Neura did not pass the local build checks.
  pause
  exit /b %STATUS%
)

echo.
echo [OK] Neura local build completed.
echo Output:
echo   %ROOT%build\windows\x64\runner\Release
start "" "%ROOT%build\windows\x64\runner\Release"
pause
exit /b 0
