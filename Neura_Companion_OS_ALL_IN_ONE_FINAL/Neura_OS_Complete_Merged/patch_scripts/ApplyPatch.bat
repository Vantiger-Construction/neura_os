@echo off
setlocal enabledelayedexpansion

REM Apply Neura OS Patch v8
REM Usage: ApplyPatch.bat "C:\Path\To\Project"  (or parent containing neura_os)

set TARGET=%~1
if "%TARGET%"=="" (
  echo Usage: ApplyPatch.bat "C:\Path\To\Project"
  exit /b 1
)

set DEST=
if exist "%TARGET%\pubspec.yaml" (
  set DEST=%TARGET%
) else if exist "%TARGET%\neura_os\pubspec.yaml" (
  set DEST=%TARGET%\neura_os
) else (
  echo ERROR: Target must be a Flutter project root (pubspec.yaml) or a folder containing neura_os\pubspec.yaml
  echo Given: %TARGET%
  exit /b 2
)

echo Applying Neura OS Patch v8 into: %DEST%

xcopy /E /I /Y "neura_os" "%DEST%" >nul

echo.
echo Patch copied. Now run:
 echo   cd /d "%DEST%"
 echo   flutter pub get
 echo   flutter run
echo.
endlocal
