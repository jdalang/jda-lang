@echo off
REM Jda Programming Language — Windows wrapper
REM Runs jda commands via WSL2 (preferred) or Docker

setlocal

set JDA_HOME=%~dp0..
set JDA_BIN=%JDA_HOME%\bin\jda1

REM Check for WSL2
where wsl >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    goto :wsl_mode
)

REM Check for Docker
where docker >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    goto :docker_mode
)

echo Jda requires WSL2 or Docker on Windows.
echo.
echo Option 1 (recommended): Install WSL2
echo   wsl --install
echo   Then run the Linux installer inside WSL.
echo.
echo Option 2: Install Docker Desktop
echo   https://docs.docker.com/desktop/install/windows-install/
exit /b 1

:wsl_mode
REM Convert Windows path to WSL path
set WSL_JDA_HOME=/mnt/%JDA_HOME:~0,1%/%JDA_HOME:~3%
set WSL_JDA_HOME=%WSL_JDA_HOME:\=/%

if "%1"=="version" (
    echo jda %VERSION% ^(windows/wsl2^)
    for /f %%i in ('type "%JDA_HOME%\VERSION"') do echo jda %%i ^(windows/wsl2^)
    exit /b 0
)

if "%1"=="build" (
    shift
    wsl bash -c "%WSL_JDA_HOME%/bin/jda1 build %*"
    exit /b %ERRORLEVEL%
)

if "%1"=="run" (
    shift
    wsl bash -c "%WSL_JDA_HOME%/bin/jda1 build %* -o /tmp/jda_out && /tmp/jda_out"
    exit /b %ERRORLEVEL%
)

if "%1"=="help" goto :show_help
if "%1"=="" goto :show_help
if "%1"=="--help" goto :show_help
if "%1"=="-h" goto :show_help

echo Unknown command: %1
echo Run: jda help
exit /b 1

:docker_mode
if "%1"=="version" (
    for /f %%i in ('type "%JDA_HOME%\VERSION"') do echo jda %%i ^(windows/docker^)
    exit /b 0
)

docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 ^
    -v "%cd%":/w -v "%JDA_HOME%":/h -w /w jda-build ^
    /h/bin/jda1 %*
exit /b %ERRORLEVEL%

:show_help
echo jda — The Jda Programming Language (Windows)
echo.
echo Usage: jda ^<command^> [options]
echo.
echo   build [--include ^<lib^>] ^<file.jda^> [-o out]   Compile
echo   run   [--include ^<lib^>] ^<file.jda^>             Compile ^& run
echo   version                                        Show version
echo   help                                           This message
echo.
echo Jda on Windows runs via WSL2 (recommended) or Docker.
exit /b 0
