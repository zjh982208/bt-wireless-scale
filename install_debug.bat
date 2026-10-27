@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"
title SD Scale - Build And Install Debug APK

where flutter >nul 2>nul
if errorlevel 1 (
    echo [ERROR] flutter not found in PATH.
    echo Please install Flutter and add it to PATH.
    pause
    exit /b 1
)

where adb >nul 2>nul
if errorlevel 1 (
    echo [ERROR] adb not found in PATH.
    echo Please install Android platform-tools and add it to PATH.
    pause
    exit /b 1
)

echo.
echo ===== 1) Build debug apk =====
flutter build apk --debug --no-pub
if errorlevel 1 (
    echo [ERROR] Build failed.
    pause
    exit /b 1
)

set "APK_PATH=build\app\outputs\flutter-apk\app-debug.apk"
if not exist "%APK_PATH%" (
    echo [ERROR] APK not found: %APK_PATH%
    pause
    exit /b 1
)

echo.
echo ===== 2) Detect phone =====
adb start-server >nul 2>nul
set "DEVICE_ID="
for /f "tokens=1,2" %%A in ('adb devices') do (
    if "%%B"=="device" (
        if not defined DEVICE_ID (
            set "DEVICE_ID=%%A"
        )
    )
)

if not defined DEVICE_ID (
    echo.
    echo [WARN] No online device detected.
    adb devices
    echo.
    set /p DEVICE_ID=Input device id manually:
)

if not defined DEVICE_ID (
    echo [ERROR] Device id is empty, exit.
    pause
    exit /b 1
)

echo.
echo ===== 3) Install apk =====
echo Device: %DEVICE_ID%
adb -s %DEVICE_ID% install -r "%APK_PATH%"
if errorlevel 1 (
    echo [ERROR] Install failed.
    pause
    exit /b 1
)

echo.
echo Install success.
pause
