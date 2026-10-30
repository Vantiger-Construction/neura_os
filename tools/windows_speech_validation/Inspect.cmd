@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-NeuraWindowsSpeech.ps1" %*
set "neura_speech_exit=%ERRORLEVEL%"
echo.
pause
exit /b %neura_speech_exit%
