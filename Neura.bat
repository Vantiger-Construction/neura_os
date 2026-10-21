@echo off
setlocal
rem One-click Neura: builds the engine and app when needed, then starts Neura.
set "ROOT=%~dp0"
if not exist "%USERPROFILE%\Desktop\Neura.lnk" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\Install-NeuraShortcut.ps1" -Quiet
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\Start-Neura.ps1" %*
if errorlevel 1 pause
endlocal
