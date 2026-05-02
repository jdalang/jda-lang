@echo off
REM Jda Programming Language — Windows Batch Installer
REM ==================================================
REM
REM This is a lightweight fallback for systems without PowerShell.
REM For full features, use: powershell -ExecutionPolicy Bypass -File install.ps1
REM
REM Usage: install.bat

setlocal enabledelayedexpansion

echo.
echo  Jda Programming Language — Windows Installer
echo.

REM ── Check PowerShell ───────────────────────────────────────────────────────

where powershell >nul 2>&1
if %errorlevel% equ 0 (
    echo  Found PowerShell. Delegating to install.ps1...
    echo.

    REM Check if install.ps1 exists locally
    if exist "%~dp0install.ps1" (
        powershell -ExecutionPolicy Bypass -File "%~dp0install.ps1"
        goto :end
    )

    REM Download and run install.ps1
    echo  Downloading installer...
    powershell -ExecutionPolicy Bypass -Command ^
        "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/jdalang/jda-lang/main/install.ps1' -OutFile '%TEMP%\jda-install.ps1' -UseBasicParsing; & '%TEMP%\jda-install.ps1'"
    goto :end
)

REM ── No PowerShell — manual install ─────────────────────────────────────────

echo  PowerShell not found. Performing basic install...
echo.

set "INSTALL_DIR=%USERPROFILE%\.jda"
set "BIN_DIR=%INSTALL_DIR%\bin"

REM Check for WSL
where wsl >nul 2>&1
if %errorlevel% equ 0 (
    echo  WSL detected.
    echo.
    echo  Run the Unix installer inside WSL:
    echo    wsl curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh ^| sh
    echo.
    goto :end
)

REM Check for Docker
where docker >nul 2>&1
if %errorlevel% equ 0 (
    echo  Docker detected.
    echo.
) else (
    echo  ERROR: Jda requires WSL2 or Docker Desktop on Windows.
    echo.
    echo  Option 1 ^(recommended^): Install WSL2
    echo    wsl --install
    echo.
    echo  Option 2: Install Docker Desktop
    echo    https://docs.docker.com/desktop/install/windows-install/
    echo.
    goto :end
)

REM Check for git
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo  ERROR: git is required for installation.
    echo  Install from: https://git-scm.com/download/win
    goto :end
)

echo  Cloning Jda...
if exist "%TEMP%\jda-install-src" rd /s /q "%TEMP%\jda-install-src"
git clone --depth 1 https://github.com/jdalang/jda-lang.git "%TEMP%\jda-install-src" 2>nul

if not exist "%TEMP%\jda-install-src" (
    echo  ERROR: Failed to clone repository.
    goto :end
)

REM Create directories
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"
if not exist "%INSTALL_DIR%\stdlib" mkdir "%INSTALL_DIR%\stdlib"
if not exist "%INSTALL_DIR%\tools" mkdir "%INSTALL_DIR%\tools"
if not exist "%INSTALL_DIR%\docker" mkdir "%INSTALL_DIR%\docker"

REM Copy files
set "SRC=%TEMP%\jda-install-src"

if exist "%SRC%\bootstrap\stage1\jda1" (
    copy "%SRC%\bootstrap\stage1\jda1" "%BIN_DIR%\jda1" >nul
    echo    ok  Compiler binary installed
)

if exist "%SRC%\stdlib" (
    copy "%SRC%\stdlib\*.jda" "%INSTALL_DIR%\stdlib\" >nul 2>&1
    echo    ok  Standard library installed
)

if exist "%SRC%\docker\Dockerfile" (
    copy "%SRC%\docker\Dockerfile" "%INSTALL_DIR%\docker\" >nul
)

if exist "%SRC%\VERSION" (
    copy "%SRC%\VERSION" "%INSTALL_DIR%\" >nul
)

REM Create jda.cmd wrapper
echo @echo off > "%BIN_DIR%\jda.cmd"
echo REM jda.cmd - Jda compiler (Docker mode) >> "%BIN_DIR%\jda.cmd"
echo docker run --rm --platform=linux/amd64 --ulimit stack=524288000:524288000 -v "%INSTALL_DIR%":/h -v "%%cd%%":/w -w /w jda-build /h/bin/jda1 %%* >> "%BIN_DIR%\jda.cmd"
echo    ok  Created jda.cmd wrapper

REM Add to PATH
echo.
echo  To add Jda to PATH, run:
echo    setx PATH "%%PATH%%;%BIN_DIR%"
echo.

REM Cleanup
rd /s /q "%TEMP%\jda-install-src" 2>nul

REM Build Docker image
echo  Building Docker image...
docker build --platform=linux/amd64 -t jda-build -f "%INSTALL_DIR%\docker\Dockerfile" "%INSTALL_DIR%" >nul 2>&1
if %errorlevel% equ 0 (
    echo    ok  Docker image built
) else (
    echo  warn  Docker image build failed — build manually later
)

echo.
echo  Jda installed successfully!
echo.
echo    Location: %INSTALL_DIR%
echo    Wrapper:  %BIN_DIR%\jda.cmd
echo.
echo  Quick start:
echo    jda version
echo    jda build hello.jda -o hello
echo.

:end
endlocal
