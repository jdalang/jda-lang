# Jda Programming Language — Windows Installer (PowerShell)
# =========================================================
#
# Usage (PowerShell, run as Administrator or normal user):
#   irm https://raw.githubusercontent.com/jdalang/jda-lang/main/install.ps1 | iex
#
# Or download and run:
#   .\install.ps1
#   .\install.ps1 -Uninstall
#   .\install.ps1 -InstallDir "C:\jda"
#
# Supports:
#   - Windows 10/11 with WSL2 (recommended — native speed)
#   - Windows 10/11 with Docker Desktop
#   - Windows with Git Bash / MSYS2
#
# Jda compiles to Linux x86-64 ELF binaries. On Windows, compilation
# runs inside WSL2 or Docker. Produced binaries run in WSL/Docker/Linux.

param(
    [string]$InstallDir = "$env:USERPROFILE\.jda",
    [string]$Version = "",
    [switch]$Uninstall,
    [switch]$NoPath
)

$ErrorActionPreference = "Stop"

$Repo = "jdalang/jda-lang"
$GitHubUrl = "https://github.com/$Repo"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Info  { Write-Host "  info  " -ForegroundColor Blue -NoNewline; Write-Host $args[0] }
function Write-Ok    { Write-Host "    ok  " -ForegroundColor Green -NoNewline; Write-Host $args[0] }
function Write-Warn  { Write-Host "  warn  " -ForegroundColor Yellow -NoNewline; Write-Host $args[0] }
function Write-Err   { Write-Host "  error " -ForegroundColor Red -NoNewline; Write-Host $args[0] }

function Test-Command($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

# ── Uninstall ────────────────────────────────────────────────────────────────

if ($Uninstall) {
    Write-Host ""
    Write-Host "Jda Programming Language — Uninstaller" -ForegroundColor White

    if (Test-Path $InstallDir) {
        Remove-Item -Recurse -Force $InstallDir
        Write-Ok "Removed $InstallDir"
    } else {
        Write-Warn "Nothing to remove at $InstallDir"
    }

    # Remove from PATH
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $BinDir = Join-Path $InstallDir "bin"
    if ($UserPath -like "*$BinDir*") {
        $NewPath = ($UserPath -split ";" | Where-Object { $_ -ne $BinDir }) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
        Write-Ok "Removed from PATH"
    }

    # Remove JDA_HOME
    if ([Environment]::GetEnvironmentVariable("JDA_HOME", "User")) {
        [Environment]::SetEnvironmentVariable("JDA_HOME", $null, "User")
        Write-Ok "Removed JDA_HOME"
    }

    Write-Ok "Jda uninstalled"
    exit 0
}

# ── Main ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Jda Programming Language — Windows Installer" -ForegroundColor Cyan
Write-Host ""

# ── Detect Method ────────────────────────────────────────────────────────────

$Method = "none"
$WslDistro = ""

# Check WSL2
if (Test-Command "wsl") {
    try {
        $WslOutput = wsl --list --quiet 2>&1 | Out-String
        if ($WslOutput -match "\w") {
            $Method = "wsl"
            $WslDistro = ($WslOutput -split "`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim()
            # Remove null characters from WSL output
            $WslDistro = $WslDistro -replace "`0", ""
            Write-Info "WSL2 detected (distro: $WslDistro)"
        }
    } catch {
        # WSL not functional
    }
}

# Check Docker Desktop
if ($Method -eq "none" -and (Test-Command "docker")) {
    try {
        docker info 2>&1 | Out-Null
        $Method = "docker"
        Write-Info "Docker Desktop detected"
    } catch {
        Write-Warn "Docker found but not running"
    }
}

if ($Method -eq "none") {
    Write-Err "Jda requires WSL2 or Docker Desktop on Windows."
    Write-Host ""
    Write-Host "  Option 1 (recommended): Install WSL2" -ForegroundColor Yellow
    Write-Host "    wsl --install"
    Write-Host ""
    Write-Host "  Option 2: Install Docker Desktop" -ForegroundColor Yellow
    Write-Host "    https://docs.docker.com/desktop/install/windows-install/"
    Write-Host ""
    exit 1
}

# ── Create Directories ──────────────────────────────────────────────────────

$BinDir = Join-Path $InstallDir "bin"
$StdlibDir = Join-Path $InstallDir "stdlib"
$ToolsDir = Join-Path $InstallDir "tools"
$DockerDir = Join-Path $InstallDir "docker"

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
New-Item -ItemType Directory -Force -Path $StdlibDir | Out-Null
New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
New-Item -ItemType Directory -Force -Path $DockerDir | Out-Null

# ── Download ─────────────────────────────────────────────────────────────────

$TmpDir = Join-Path $env:TEMP "jda-install-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

try {
    # Clone or download
    if (Test-Command "git") {
        Write-Info "Cloning repository..."
        $CloneRef = if ($Version) { "v$Version" } else { "main" }
        git clone --depth 1 --branch $CloneRef "$GitHubUrl.git" "$TmpDir\jda" 2>&1 | Out-Null
        if (-not (Test-Path "$TmpDir\jda")) {
            git clone --depth 1 "$GitHubUrl.git" "$TmpDir\jda" 2>&1 | Out-Null
        }
        $Src = "$TmpDir\jda"
    } else {
        Write-Info "Downloading source..."
        $ZipUrl = "$GitHubUrl/archive/refs/heads/main.zip"
        Invoke-WebRequest -Uri $ZipUrl -OutFile "$TmpDir\jda.zip" -UseBasicParsing
        Expand-Archive -Path "$TmpDir\jda.zip" -DestinationPath $TmpDir
        $Src = Get-ChildItem -Path $TmpDir -Directory -Filter "jda-lang*" | Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not (Test-Path $Src)) {
        Write-Err "Failed to download Jda source"
        exit 1
    }

    # Read version
    if (-not $Version -and (Test-Path "$Src\VERSION")) {
        $Version = (Get-Content "$Src\VERSION" -Raw).Trim()
    }
    if (-not $Version) { $Version = "dev" }
    Write-Ok "Source ready (v$Version)"

    # ── Copy Files ───────────────────────────────────────────────────────────

    # Compiler binary
    $Jda1Src = "$Src\bootstrap\stage1\jda1"
    if (-not (Test-Path $Jda1Src)) { $Jda1Src = "$Src\bootstrap\stage0\jda1" }
    if (Test-Path $Jda1Src) {
        Copy-Item $Jda1Src "$BinDir\jda1" -Force
        Write-Ok "Compiler binary installed"
    }

    # Bootstrap binary
    $BootSrc = "$Src\bootstrap\bin\jda1-bootstrap"
    if (Test-Path $BootSrc) {
        Copy-Item $BootSrc "$BinDir\jda1-bootstrap" -Force
    }

    # Stdlib
    $StdlibSrc = "$Src\stdlib"
    if (Test-Path $StdlibSrc) {
        Get-ChildItem "$StdlibSrc\*.jda" | ForEach-Object { Copy-Item $_.FullName $StdlibDir -Force }
        $PkgCount = (Get-ChildItem "$StdlibDir\*.jda" | Measure-Object).Count
        Write-Ok "Standard library ($PkgCount packages)"
    }

    # Tools
    $ToolsSrc = "$Src\tools"
    if (Test-Path $ToolsSrc) {
        Get-ChildItem "$ToolsSrc\*" -File | ForEach-Object { Copy-Item $_.FullName $ToolsDir -Force }
    }

    # Dockerfile
    $DockerSrc = "$Src\docker\Dockerfile"
    if (Test-Path $DockerSrc) { Copy-Item $DockerSrc $DockerDir -Force }

    # Version
    $Version | Out-File -FilePath "$InstallDir\VERSION" -NoNewline -Encoding ascii

    Write-Ok "Files installed to $InstallDir"

} finally {
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}

# ── Create Wrapper Scripts ───────────────────────────────────────────────────

# PowerShell wrapper: jda.ps1
$Ps1Wrapper = Join-Path $BinDir "jda.ps1"

if ($Method -eq "wsl") {
    @"
# jda.ps1 - Jda compiler wrapper (WSL2 mode)
param([Parameter(ValueFromRemainingArguments=`$true)]`$Args_)

`$JdaHome = `$env:JDA_HOME
if (-not `$JdaHome) { `$JdaHome = "`$env:USERPROFILE\.jda" }

# Convert Windows path to WSL path
function ToWslPath(`$p) {
    `$p = `$p -replace '\\', '/'
    if (`$p -match '^([A-Za-z]):(.*)') {
        return "/mnt/`$(`$Matches[1].ToLower())`$(`$Matches[2])"
    }
    return `$p
}

`$WslJdaHome = ToWslPath `$JdaHome
`$WslJda1 = "`$WslJdaHome/bin/jda1"

switch (`$Args_[0]) {
    "build" {
        `$rest = `$Args_[1..(`$Args_.Length-1)]
        `$wslArgs = @()
        for (`$i = 0; `$i -lt `$rest.Length; `$i++) {
            `$a = `$rest[`$i]
            if (`$a -eq "--include" -or `$a -eq "-o") {
                `$wslArgs += `$a
                `$i++
                `$wslArgs += (ToWslPath (Resolve-Path `$rest[`$i] -ErrorAction SilentlyContinue || `$rest[`$i]))
            } elseif (`$a -match '\.jda$') {
                `$wslArgs += (ToWslPath (Resolve-Path `$a))
            } else {
                `$wslArgs += `$a
            }
        }
        wsl `$WslJda1 build @wslArgs
    }
    "run" {
        `$rest = `$Args_[1..(`$Args_.Length-1)]
        `$wslArgs = @()
        `$srcFile = ""
        for (`$i = 0; `$i -lt `$rest.Length; `$i++) {
            `$a = `$rest[`$i]
            if (`$a -eq "--include") {
                `$wslArgs += `$a
                `$i++
                `$wslArgs += (ToWslPath (Resolve-Path `$rest[`$i]))
            } elseif (`$a -match '\.jda$') {
                `$srcFile = ToWslPath (Resolve-Path `$a)
                `$wslArgs += `$srcFile
            } else {
                `$wslArgs += `$a
            }
        }
        wsl bash -c "`$WslJda1 build `$(`$wslArgs -join ' ') -o /tmp/jda_out 2>&1 && /tmp/jda_out"
    }
    "version" {
        `$ver = Get-Content "`$JdaHome\VERSION" -ErrorAction SilentlyContinue
        Write-Host "jda `$ver (wsl)"
    }
    { `$_ -eq "help" -or `$_ -eq `$null -or `$_ -eq "" } {
        Write-Host "jda - The Jda Programming Language (WSL2 mode)"
        Write-Host ""
        Write-Host "  jda build <file.jda> [-o out]   Compile"
        Write-Host "  jda run <file.jda>              Compile & run"
        Write-Host "  jda version                     Show version"
        Write-Host "  jda help                        This message"
        Write-Host ""
        Write-Host "Runs via WSL2. Binaries are Linux x86-64 ELF."
    }
    default {
        Write-Host "Unknown command: `$(`$Args_[0]). Run 'jda help'." -ForegroundColor Red
        exit 1
    }
}
"@ | Out-File -FilePath $Ps1Wrapper -Encoding ascii

} elseif ($Method -eq "docker") {
    @"
# jda.ps1 - Jda compiler wrapper (Docker mode)
param([Parameter(ValueFromRemainingArguments=`$true)]`$Args_)

`$JdaHome = `$env:JDA_HOME
if (-not `$JdaHome) { `$JdaHome = "`$env:USERPROFILE\.jda" }
`$Image = "jda-build"

# Ensure Docker image
function Ensure-Image {
    `$exists = docker image inspect `$Image 2>&1 | Out-Null; `$LASTEXITCODE -eq 0
    if (-not `$exists) {
        Write-Host "Building Jda Docker image (one-time)..."
        `$df = Join-Path `$JdaHome "docker\Dockerfile"
        if (Test-Path `$df) {
            docker build --platform=linux/amd64 -t `$Image -f `$df `$JdaHome
        } else {
            "FROM ubuntu:22.04`nRUN apt-get update && apt-get install -y nasm binutils make xxd file python3 && rm -rf /var/lib/apt/lists/*`nWORKDIR /jda" | docker build --platform=linux/amd64 -t `$Image -
        }
    }
}

switch (`$Args_[0]) {
    "build" {
        Ensure-Image
        `$rest = `$Args_[1..(`$Args_.Length-1)]
        `$src = ""; `$out = ""; `$inc = ""
        for (`$i = 0; `$i -lt `$rest.Length; `$i++) {
            switch (`$rest[`$i]) {
                "--include" { `$i++; `$inc = "--include /w/`$(`$rest[`$i])" }
                "-o"        { `$i++; `$out = `$rest[`$i] }
                default     { `$src = `$rest[`$i] }
            }
        }
        `$dir = (Resolve-Path (Split-Path `$src)).Path
        `$fn = Split-Path `$src -Leaf
        `$oname = if (`$out) { `$out } else { `$fn -replace '\.jda$','' }
        docker run --rm --platform=linux/amd64 --ulimit stack=524288000:524288000 ``
            -v "`${JdaHome}:/h" -v "`${dir}:/w" -w /w `$Image ``
            bash -c "/h/bin/jda1 build `$inc /w/`$fn -o /w/`$oname 2>&1"
    }
    "run" {
        Ensure-Image
        `$rest = `$Args_[1..(`$Args_.Length-1)]
        `$src = ""; `$inc = ""
        for (`$i = 0; `$i -lt `$rest.Length; `$i++) {
            switch (`$rest[`$i]) {
                "--include" { `$i++; `$inc = "--include /w/`$(`$rest[`$i])" }
                default     { `$src = `$rest[`$i] }
            }
        }
        `$dir = (Resolve-Path (Split-Path `$src)).Path
        `$fn = Split-Path `$src -Leaf
        docker run --rm --platform=linux/amd64 --ulimit stack=524288000:524288000 ``
            -v "`${JdaHome}:/h" -v "`${dir}:/w" -w /w `$Image ``
            bash -c "/h/bin/jda1 build `$inc /w/`$fn -o /tmp/out 2>&1 && /tmp/out"
    }
    "version" {
        `$ver = Get-Content "`$JdaHome\VERSION" -ErrorAction SilentlyContinue
        Write-Host "jda `$ver (docker)"
    }
    { `$_ -eq "help" -or `$_ -eq `$null -or `$_ -eq "" } {
        Write-Host "jda - The Jda Programming Language (Docker mode)"
        Write-Host ""
        Write-Host "  jda build <file.jda> [-o out]   Compile (via Docker)"
        Write-Host "  jda run <file.jda>              Compile & run (via Docker)"
        Write-Host "  jda version                     Show version"
        Write-Host "  jda help                        This message"
    }
    default {
        Write-Host "Unknown command: `$(`$Args_[0]). Run 'jda help'." -ForegroundColor Red
        exit 1
    }
}
"@ | Out-File -FilePath $Ps1Wrapper -Encoding ascii
}

Write-Ok "PowerShell wrapper created ($Method)"

# CMD batch wrapper: jda.cmd
$CmdWrapper = Join-Path $BinDir "jda.cmd"
@"
@echo off
REM jda.cmd - Jda compiler wrapper for Windows CMD
powershell -ExecutionPolicy Bypass -File "%~dp0jda.ps1" %*
"@ | Out-File -FilePath $CmdWrapper -Encoding ascii
Write-Ok "CMD wrapper created (jda.cmd)"

# ── PATH Setup ───────────────────────────────────────────────────────────────

if (-not $NoPath) {
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($UserPath -notlike "*$BinDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$BinDir;$UserPath", "User")
        Write-Ok "Added to PATH: $BinDir"
    } else {
        Write-Info "Already in PATH"
    }

    # Set JDA_HOME
    [Environment]::SetEnvironmentVariable("JDA_HOME", $InstallDir, "User")
}

# ── Docker Image Setup ──────────────────────────────────────────────────────

if ($Method -eq "docker") {
    Write-Info "Checking Docker image..."
    $imageExists = docker image inspect jda-build 2>&1 | Out-Null; $LASTEXITCODE -eq 0
    if (-not $imageExists) {
        Write-Info "Building Docker image 'jda-build' (one-time)..."
        $df = Join-Path $DockerDir "Dockerfile"
        if (Test-Path $df) {
            docker build --platform=linux/amd64 -t jda-build -f $df $InstallDir 2>&1 | Out-Null
        }
        Write-Ok "Docker image built"
    } else {
        Write-Ok "Docker image exists"
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Jda v$Version installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "  Location:  $InstallDir"
Write-Host "  Method:    $Method"
Write-Host "  Wrapper:   $BinDir\jda.cmd"
Write-Host ""
Write-Host "  Quick start (open a new terminal):"
Write-Host "    jda version" -ForegroundColor White
Write-Host "    jda run hello.jda" -ForegroundColor White
Write-Host "    jda build hello.jda -o hello" -ForegroundColor White
Write-Host ""

if ($Method -eq "wsl") {
    Write-Host "  Note: Compiled binaries are Linux ELF executables." -ForegroundColor Yellow
    Write-Host "  Run them with: wsl ./hello" -ForegroundColor Yellow
    Write-Host ""
}
