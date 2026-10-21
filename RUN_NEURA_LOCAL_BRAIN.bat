@echo off
setlocal
rem The engine (neura_api) is started by the Neura app with a per-session
rem credential; it cannot run on its own. This now runs the one-click launcher.
set "ROOT=%~dp0"
call "%ROOT%Neura.bat" %*
endlocal
