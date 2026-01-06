#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install Tailscale VPN on Windows.
.DESCRIPTION
    Downloads and installs Tailscale VPN client for Windows.
    Uses winget if available, otherwise downloads MSI directly.
.NOTES
    Run as Administrator in PowerShell.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host "=== Installing Tailscale VPN ===" -ForegroundColor Cyan

# Check if already installed
$tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
if ($tailscale) {
    Write-Host "Tailscale already installed: $($tailscale.Source)" -ForegroundColor Green
    $version = & tailscale version 2>$null | Select-Object -First 1
    Write-Host "Version: $version" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Run 'tailscale up' to connect" -ForegroundColor Cyan
    exit 0
}

# Try winget first
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    Write-Host "Installing via winget..." -ForegroundColor Yellow
    winget install --id Tailscale.Tailscale --accept-package-agreements --accept-source-agreements

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Tailscale installed successfully" -ForegroundColor Green
    } else {
        Write-Host "winget install failed, trying direct download..." -ForegroundColor Yellow
    }
}

# Verify installation or try direct download
$tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $tailscale) {
    Write-Host "Downloading Tailscale MSI..." -ForegroundColor Yellow

    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "386" }
    $msiUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest-$arch.msi"
    $msiPath = "$env:TEMP\tailscale-setup.msi"

    Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

    Write-Host "Installing Tailscale..." -ForegroundColor Yellow
    Start-Process msiexec.exe -ArgumentList "/i", $msiPath, "/quiet", "/norestart" -Wait

    Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
}

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# Verify
$tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
if ($tailscale) {
    Write-Host ""
    Write-Host "=== Tailscale installed successfully ===" -ForegroundColor Green
    $version = & tailscale version 2>$null | Select-Object -First 1
    Write-Host "Version: $version" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Run 'tailscale up' to authenticate" -ForegroundColor Cyan
    Write-Host "  2. Or use the Tailscale system tray icon" -ForegroundColor Cyan
} else {
    Write-Host "ERROR: Tailscale installation failed" -ForegroundColor Red
    Write-Host "Please install manually from: https://tailscale.com/download/windows" -ForegroundColor Yellow
    exit 1
}
