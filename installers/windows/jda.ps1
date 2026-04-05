# Jda Programming Language — PowerShell wrapper
# Runs jda commands via WSL2 (preferred) or Docker

$JdaHome = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$Version = Get-Content "$JdaHome\VERSION" -ErrorAction SilentlyContinue

function Show-Help {
    Write-Host @"
jda - The Jda Programming Language (Windows)

Usage: jda <command> [options]

  build [--include <lib>] <file.jda> [-o out]   Compile
  run   [--include <lib>] <file.jda>             Compile & run
  version                                        Show version
  help                                           This message

Jda on Windows runs via WSL2 (recommended) or Docker.
"@
}

$Command = if ($args.Count -gt 0) { $args[0] } else { "help" }
$RestArgs = if ($args.Count -gt 1) { $args[1..($args.Count-1)] } else { @() }

# Check WSL2
$HasWsl = $null -ne (Get-Command wsl -ErrorAction SilentlyContinue)
$HasDocker = $null -ne (Get-Command docker -ErrorAction SilentlyContinue)

if (-not $HasWsl -and -not $HasDocker) {
    Write-Host "Jda requires WSL2 or Docker on Windows." -ForegroundColor Red
    Write-Host ""
    Write-Host "Option 1 (recommended): Install WSL2"
    Write-Host "  wsl --install"
    Write-Host ""
    Write-Host "Option 2: Install Docker Desktop"
    Write-Host "  https://docs.docker.com/desktop/install/windows-install/"
    exit 1
}

switch ($Command) {
    "version" {
        Write-Host "jda $Version (windows$(if ($HasWsl) { '/wsl2' } else { '/docker' }))"
    }
    "help"    { Show-Help }
    "--help"  { Show-Help }
    "-h"      { Show-Help }
    "build" {
        if ($HasWsl) {
            $WslArgs = $RestArgs -join " "
            wsl bash -c "/mnt/c/jda/bin/jda1 build $WslArgs"
        } else {
            $DockerArgs = @("run", "--rm", "--platform", "linux/amd64",
                "--ulimit", "stack=524288000:524288000",
                "-v", "${pwd}:/w", "-v", "${JdaHome}:/h", "-w", "/w",
                "jda-build", "/h/bin/jda1", "build") + $RestArgs
            & docker @DockerArgs
        }
    }
    "run" {
        if ($HasWsl) {
            $WslArgs = $RestArgs -join " "
            wsl bash -c "/mnt/c/jda/bin/jda1 build $WslArgs -o /tmp/out && /tmp/out"
        } else {
            $DockerArgs = @("run", "--rm", "--platform", "linux/amd64",
                "--ulimit", "stack=524288000:524288000",
                "-v", "${pwd}:/w", "-v", "${JdaHome}:/h", "-w", "/w",
                "jda-build", "bash", "-c",
                "/h/bin/jda1 build $($RestArgs -join ' ') -o /tmp/out && /tmp/out")
            & docker @DockerArgs
        }
    }
    default {
        Write-Host "Unknown command: $Command. Run 'jda help'." -ForegroundColor Red
        exit 1
    }
}
