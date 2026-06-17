@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

:: ============================================================
:: Anx Reader - One-click APK Build Script
:: Usage: build_apk.bat [--debug] [--split] [--arm64]
:: ============================================================

title Anx Reader APK Builder

set "PROJECT_DIR=%~dp0"
cd /d "%PROJECT_DIR%"

set BUILD_MODE=release
set BUILD_FLAGS=
set SPLIT=false

:: Parse arguments
:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="--debug" set BUILD_MODE=debug
if /i "%~1"=="--split" set SPLIT=true
if /i "%~1"=="--arm64" set BUILD_FLAGS=--target-platform android-arm64
shift
goto :parse_args
:args_done

:: ============================================================
:: Step 1: Check prerequisites
:: ============================================================
echo ==========================================
echo   Anx Reader APK Builder
echo ==========================================
echo.

:: Check Flutter
echo [Step 1/6] Checking Flutter SDK...
flutter --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter not found in PATH.
    echo.
    echo   Install Flutter 3.35.3:
    echo   1. Download: https://docs.flutter.dev/release/archive
    echo   2. Extract to C:\flutter
    echo   3. Add C:\flutter\bin to PATH
    echo.
    goto :fail
)

for /f "tokens=*" %%i in ('flutter --version 2^>^&1') do (
    echo   [OK] %%i
    goto :flutter_done
)
:flutter_done
echo.

:: Check Java
echo [Step 2/6] Checking Java...
java -version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Java not found in PATH.
    echo.
    echo   Install Java 17:
    echo   Download: https://www.azul.com/downloads/#zulu
    echo   Select: Zulu JDK 17, Windows, x64
    echo.
    goto :fail
)

for /f "tokens=3" %%i in ('java -version 2^>^&1 ^| findstr /i "version"') do (
    echo   [OK] Java %%i
    goto :java_done
)
:java_done
echo.

:: Check Android SDK
echo [Step 3/6] Checking Android SDK...
if defined ANDROID_HOME (
    echo   [OK] ANDROID_HOME=%ANDROID_HOME%
) else if defined ANDROID_SDK_ROOT (
    set "ANDROID_HOME=%ANDROID_SDK_ROOT%"
    echo   [OK] ANDROID_SDK_ROOT=%ANDROID_SDK_ROOT%
) else (
    if exist "%LOCALAPPDATA%\Android\Sdk" (
        set "ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk"
        echo   [OK] Found at default location: !ANDROID_HOME!
    ) else (
        echo [ERROR] Android SDK not found.
        echo.
        echo   Install Android Studio: https://developer.android.com/studio
        echo   Or set ANDROID_HOME environment variable.
        echo.
        goto :fail
    )
)
echo.

:: ============================================================
:: Step 2: Get dependencies
:: ============================================================
echo [Step 4/6] Running flutter pub get...
call flutter pub get
if errorlevel 1 (
    echo [ERROR] flutter pub get failed.
    goto :fail
)
echo   [OK] Dependencies resolved.
echo.

:: ============================================================
:: Step 3: Generate local.properties if missing
:: ============================================================
if not exist "android\local.properties" (
    echo [Step 5/6] Generating android/local.properties...
    for /f "tokens=*" %%i in ('where flutter 2^>nul') do set "FLUTTER_EXE=%%i"
    for %%i in ("!FLUTTER_EXE!\..\..") do set "FLUTTER_SDK=%%~fi"
    (
        echo sdk.dir=%ANDROID_HOME%
        echo flutter.sdk=!FLUTTER_SDK!
    ) > "android\local.properties"
    echo   [OK] local.properties created.
) else (
    echo [Step 5/6] local.properties already exists.
)
echo.

:: ============================================================
:: Step 4: Setup signing key
:: ============================================================
if "%BUILD_MODE%"=="debug" (
    echo [Step 6/6] Debug mode - skipping signing setup.
    goto :build
)

if exist "android\key.properties" (
    echo [Step 6/6] key.properties already exists.
    goto :build
)

echo [Step 6/6] Generating dummy keystore for testing...
echo   [WARN] This is a dummy keystore. For production, use your real keystore.

if not exist "android\dummy.keystore" (
    keytool -genkey -v -keystore "android\dummy.keystore" -alias dummykey -keyalg RSA -keysize 2048 -validity 10000 -storepass dummy123 -keypass dummy123 -dname "CN=Dummy,O=Dummy,C=US" >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Failed to generate keystore.
        echo   keytool is usually in: %JAVA_HOME%\bin\keytool.exe
        goto :fail
    )
    echo   [OK] Dummy keystore generated.
)

(
    echo keyAlias=dummykey
    echo keyPassword=dummy123
    echo storePassword=dummy123
    echo storeFile=dummy.keystore
) > "android\key.properties"
echo   [OK] key.properties created.
echo.

:: ============================================================
:: Step 5: Build APK
:: ============================================================
:build
echo ==========================================
echo   Building %BUILD_MODE% APK...
echo ==========================================
echo.

set "BUILD_CMD=flutter build apk --%BUILD_MODE%"

if "%SPLIT%"=="true" (
    set "BUILD_CMD=!BUILD_CMD! --split-per-abi"
    echo   Mode: Split APK per ABI
) else if defined BUILD_FLAGS (
    set "BUILD_CMD=!BUILD_CMD! %BUILD_FLAGS%"
    echo   Mode: arm64 only
) else (
    echo   Mode: Universal APK
)

echo   Command: !BUILD_CMD!
echo.

call !BUILD_CMD!
if errorlevel 1 (
    echo.
    echo [ERROR] Build failed!
    echo.
    echo   Common fixes:
    echo   - Run: flutter clean then flutter pub get
    echo   - Check: flutter doctor
    echo   - Ensure ANDROID_HOME is set correctly
    echo   - Ensure Java 17 is installed
    echo.
    goto :fail
)

:: ============================================================
:: Step 6: Show result
:: ============================================================
echo.
echo ==========================================
echo   Build succeeded!
echo ==========================================
echo.
echo   Output files:
echo.

if "%SPLIT%"=="true" (
    for %%f in ("build\app\outputs\flutter-apk\*release*.apk") do (
        echo   [OK] %%f
    )
) else (
    if "%BUILD_MODE%"=="debug" (
        echo   [OK] build\app\outputs\flutter-apk\app-debug.apk
    ) else (
        echo   [OK] build\app\outputs\flutter-apk\app-release.apk
    )
)

echo.
echo   To install on device:
echo   adb install ^<apk_path^>
echo.
goto :done

:fail
echo.
echo   Script stopped due to error.
echo.

:done
pause
