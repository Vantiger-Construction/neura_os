@echo off
setlocal
rem One-click Neura: reconcile shortcuts, verify/build, then start Neura.
set "ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\Install-NeuraShortcut.ps1" -Quiet
if errorlevel 1 echo [Neura] Shortcut repair failed; continuing with startup.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\Start-Neura.ps1" %*
set "NEURA_EXIT=%ERRORLEVEL%"
if not "%NEURA_EXIT%"=="0" (
  echo [Neura] Startup failed with exit code %NEURA_EXIT%.
  pause
)
endlocal & exit /b %NEURA_EXIT%
