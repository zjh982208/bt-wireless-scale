@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"
title SD Scale - Build Release APK

where flutter >nul 2>nul
if errorlevel 1 (
    echo [ERROR] flutter not found in PATH.
    echo Please install Flutter and add it to PATH.
    pause
    exit /b 1
)

echo.
echo ===== Build release apk =====
echo.
flutter build apk --release --no-pub
if errorlevel 1 (
    echo.
    echo [ERROR] Build failed.
    pause
    exit /b 1
)

set "APK_PATH=build\app\outputs\flutter-apk\app-release.apk"
if not exist "%APK_PATH%" (
    echo.
    echo [ERROR] APK not found: %APK_PATH%
    pause
    exit /b 1
)

echo.
echo Build success:
echo %cd%\%APK_PATH%
echo.
pause
