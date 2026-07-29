@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Neura finish-line prep

REM ============================================================
REM  neura_prep.bat -- deterministic finish-line prep
REM  ----------------------------------------------------------
REM  Root selection order:
REM    1. Path supplied on the command line
REM    2. NEURA_ROOT environment variable
REM    3. Project containing this batch file
REM    4. Project containing the current command-prompt folder
REM    5. Known Neura locations
REM    6. Automatic search below common Neura/repository folders
REM
REM  When several searched projects qualify, the tree containing
REM  the largest number of Dart files is selected.
REM
REM  Usage:
REM    neura_prep.bat
REM    neura_prep.bat "D:\path\to\neura_os"
REM ============================================================

set "ROOT="
set "ROOT_SOURCE="
set "BEST_DART_COUNT=-1"
set "STAMP="
set "STATUS=0"

REM ---- explicit command-line root always wins ----
if "%~1"=="" goto check_environment
call :accept_exact_root "%~f1" "command-line argument"
if defined ROOT goto haveroot

echo.
echo [X] The supplied path is not a Flutter project:
echo     "%~f1"
echo     No pubspec.yaml was found there.
set "STATUS=1"
goto finish

:check_environment
REM ---- optional permanent user setting ----
if not defined NEURA_ROOT goto check_batch_location
call :accept_exact_root "%NEURA_ROOT%" "NEURA_ROOT environment variable"
if defined ROOT goto haveroot
echo [!] Ignoring NEURA_ROOT because it has no pubspec.yaml:
echo     "%NEURA_ROOT%"

:check_batch_location
REM ---- walk upward from the batch file first ----
call :find_upwards "%~dp0" "batch-file location"
if defined ROOT goto haveroot

REM ---- then walk upward from the current command-prompt folder ----
call :find_upwards "%CD%" "current folder"
if defined ROOT goto haveroot

REM ---- score known exact project locations ----
call :score_root "D:\Vantiger1\neura_os" "known D: Neura location"
call :score_root "%USERPROFILE%\source\repos\Vantiger1\neura_os" "current user's source repository"
call :score_root "C:\Users\user1\source\repos\Vantiger1\neura_os" "known C: Neura repository"
call :score_root "D:\neura ver1.12" "known Neura installation location"
call :score_root "C:\NEURA_v2.0\Neura_Complete_v2" "known Neura v2 location"

REM ---- search likely parent folders for a Neura pubspec.yaml ----
call :discover_below "%~dp0"
call :discover_below "D:\Vantiger1"
call :discover_below "%USERPROFILE%\source\repos"
call :discover_below "C:\NEURA_v2.0"

if defined ROOT goto haveroot

echo.
echo [X] Could not locate the Neura Flutter project.
echo.
echo Try either:
echo   neura_prep.bat "D:\path\to\neura_os"
echo.
echo Or set a permanent root once, then run this file normally:
echo   setx NEURA_ROOT "D:\path\to\neura_os"
set "STATUS=1"
goto finish

:haveroot
if not exist "%ROOT%\pubspec.yaml" (
  echo [X] Internal root-selection error: no pubspec.yaml at "%ROOT%"
  set "STATUS=1"
  goto finish
)

REM cd /d changes both drive and directory. It also leaves an existing
REM command prompt at the Neura root when this batch file finishes.
cd /d "%ROOT%" 2>nul
if errorlevel 1 (
  echo [X] Could not enter the selected project directory:
  echo     "%ROOT%"
  set "STATUS=1"
  goto finish
)

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%i"
if not defined STAMP set "STAMP=unknown_time"

echo.
echo ==================== GATE 0: selected project ====================
echo   ROOT   = %ROOT%
echo   FOUND  = %ROOT_SOURCE%
call :treeinfo "%ROOT%"
echo.
echo All remaining commands will run from:
echo   %CD%
echo.
pause

where flutter >nul 2>&1
if errorlevel 1 (
  echo.
  echo [X] Flutter was not found in PATH.
  echo     Install Flutter or add its bin folder to PATH, then run again.
  set "STATUS=1"
  goto finish
)

echo.
echo ==================== GATE 1: flutter pub get ====================
call flutter pub get
if errorlevel 1 (
  echo.
  echo [X] flutter pub get failed. Fix the message above before continuing.
  set "STATUS=1"
  goto finish
)

echo.
echo ==================== PHASE 1: smart-quote / apostrophe fix ====================
if not exist "%ROOT%\fix_smart_quotes.ps1" (
  echo [!] fix_smart_quotes.ps1 not found in "%ROOT%" -- skipping fixer.
  goto analyze
)

echo --- dry run (shows changes, writes nothing) ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\fix_smart_quotes.ps1" -DryRun
if errorlevel 1 (
  echo [!] The fixer dry run returned an error. No fixer changes were applied.
  goto analyze
)

echo.
echo --- applying (backs up every changed file first) ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\fix_smart_quotes.ps1"
if errorlevel 1 echo [!] The fixer returned an error; analyze will still run.

:analyze
echo.
echo ==================== flutter analyze ====================
call flutter analyze > "%ROOT%\analyze_%STAMP%.txt" 2>&1
set "ANALYZE_EXIT=%ERRORLEVEL%"
type "%ROOT%\analyze_%STAMP%.txt"

echo.
echo ==================== SUMMARY ====================
findstr /i /c:"issues found" /c:"No issues found" "%ROOT%\analyze_%STAMP%.txt"
set "ERRCOUNT=0"
for /f %%c in ('powershell -NoProfile -Command "(Select-String -LiteralPath '%ROOT%\analyze_%STAMP%.txt' -Pattern '^\s*error\s+').Count"') do set "ERRCOUNT=%%c"
echo   Errors remaining : %ERRCOUNT%
echo   Analyzer exit    : %ANALYZE_EXIT%
echo   Log saved        : %ROOT%\analyze_%STAMP%.txt

echo.
echo ------------------------------------------------------------
echo NEXT (needs judgment -- not automatable by a batch file):
echo   1^) cd /d "%ROOT%"
echo   2^) claude
echo   3^) paste: Execute FINISH_LINE_RUN_BRIEF.md top to bottom.
echo.
echo The remaining analyzer errors should be used as the source of
echo truth. The ambiguous-lines CSV is only a cross-reference report.
echo ------------------------------------------------------------
goto finish

REM ============================================================
REM  Root discovery helpers
REM ============================================================

:accept_exact_root
if "%~1"=="" goto :eof
if not exist "%~1\pubspec.yaml" goto :eof
for %%R in ("%~1") do set "ROOT=%%~fR"
set "ROOT_SOURCE=%~2"
goto :eof

:find_upwards
set "PROBE=%~f1"
:find_upwards_loop
if exist "%PROBE%\pubspec.yaml" (
  set "ROOT=%PROBE%"
  set "ROOT_SOURCE=%~2 (walked upward)"
  goto :eof
)
for %%P in ("%PROBE%\..") do set "PARENT=%%~fP"
if /i "%PARENT%"=="%PROBE%" goto :eof
set "PROBE=%PARENT%"
goto find_upwards_loop

:score_root
if "%~1"=="" goto :eof
if not exist "%~1\pubspec.yaml" goto :eof
set "DART_COUNT=0"
for /f %%c in ('dir /s /b "%~1\lib\*.dart" 2^>nul ^| find /c /v ""') do set "DART_COUNT=%%c"
if %DART_COUNT% LEQ %BEST_DART_COUNT% goto :eof
for %%R in ("%~1") do set "ROOT=%%~fR"
set "ROOT_SOURCE=%~2"
set "BEST_DART_COUNT=%DART_COUNT%"
goto :eof

:discover_below
if "%~1"=="" goto :eof
if not exist "%~1\" goto :eof
for /f "delims=" %%F in ('where /r "%~1" pubspec.yaml 2^>nul') do call :score_if_neura "%%~dpF"
goto :eof

:score_if_neura
if not exist "%~1\pubspec.yaml" goto :eof
findstr /i /r /c:"^[ ]*name:[ ]*neura" "%~1\pubspec.yaml" >nul 2>&1
if errorlevel 1 goto :eof
call :score_root "%~1" "automatic Neura project search"
goto :eof

:treeinfo
if not exist "%~1\pubspec.yaml" goto :eof
set "TREE_DART_COUNT=0"
for /f %%c in ('dir /s /b "%~1\lib\*.dart" 2^>nul ^| find /c /v ""') do set "TREE_DART_COUNT=%%c"
set "PUBSPEC_TIME=unknown"
for %%F in ("%~1\pubspec.yaml") do set "PUBSPEC_TIME=%%~tF"
echo   pubspec modified : %PUBSPEC_TIME%
echo   Dart files       : %TREE_DART_COUNT%
goto :eof

:finish
echo.
if "%STATUS%"=="0" (
  echo Neura finish-line prep completed.
) else (
  echo Neura finish-line prep stopped with an error.
)
echo Current folder: %CD%
echo.
pause
endlocal & exit /b %STATUS%
