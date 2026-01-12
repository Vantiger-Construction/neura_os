@echo off
setlocal
set "PROJECT_DIR=%NEURA_PROJECT_DIR%"
if "%PROJECT_DIR%"=="" set "PROJECT_DIR=%~dp0..\..\Neura_Companion"

echo Neura Companion — Android one-click build
echo ProjectDir: %PROJECT_DIR%

flutter --version >nul 2>&1
if errorlevel 1 (
  echo flutter not found on PATH
  exit /b 1
)

pushd "%PROJECT_DIR%"
flutter clean
flutter pub get
flutter analyze

echo Building Android release APK...
flutter build apk --release

echo Done. Check: build\app\outputs\flutter-apk\
popd
endlocal
