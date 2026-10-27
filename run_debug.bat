@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"
title SD Scale - Flutter Debug Run

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
echo ===== 1) Start adb server =====
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
    echo Please check USB cable / USB debug / authorization.
    echo.
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
echo ===== 2) Flutter run (hot reload ready) =====
echo Device: %DEVICE_ID%
echo Tips: press r for hot reload, press R for hot restart, press q to quit.
echo.

flutter run -d %DEVICE_ID% --debug --no-pub

echo.
echo Flutter run ended.
pause
