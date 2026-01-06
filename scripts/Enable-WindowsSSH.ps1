#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enable Windows OpenSSH Server on port 22.
.DESCRIPTION
    Installs and configures Windows OpenSSH Server to run on port 22,
    complementing WSL SSH on port 222.
.NOTES
    Run as Administrator in PowerShell.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host "=== Enabling Windows OpenSSH Server (Port 22) ===" -ForegroundColor Cyan

# Check if already installed
$sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

if ($sshCapability.State -eq 'Installed') {
    Write-Host "OpenSSH Server already installed" -ForegroundColor Green
} else {
    Write-Host "Installing OpenSSH Server..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    Write-Host "OpenSSH Server installed" -ForegroundColor Green
}

# Configure and start the service
Write-Host "Configuring sshd service..." -ForegroundColor Yellow
Set-Service -Name sshd -StartupType 'Automatic'
Start-Service sshd

# Verify firewall rule exists
$firewallRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if (-not $firewallRule) {
    Write-Host "Adding firewall rule..." -ForegroundColor Yellow
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
}

# Setup SSH key authentication for current user
Write-Host "Configuring SSH key authentication..." -ForegroundColor Yellow

$sshDir = "$env:USERPROFILE\.ssh"
$authorizedKeys = "$sshDir\authorized_keys"

# Create .ssh directory if it doesn't exist
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    Write-Host "Created $sshDir" -ForegroundColor Gray
}

# Try to copy public key from WSL
$wslPubKey = $null
$wslDistros = @('Ubuntu', 'Ubuntu-24.04', 'Ubuntu-22.04')
foreach ($distro in $wslDistros) {
    $wslPath = "\\wsl$\$distro\home\$env:USERNAME\.ssh\id_ed25519.pub"
    if (Test-Path $wslPath) {
        $wslPubKey = Get-Content $wslPath -Raw
        Write-Host "Found WSL public key in $distro" -ForegroundColor Green
        break
    }
}

if ($wslPubKey) {
    # Add key if not already present
    $existingKeys = if (Test-Path $authorizedKeys) { Get-Content $authorizedKeys -Raw } else { "" }
    if ($existingKeys -notlike "*$($wslPubKey.Trim())*") {
        Add-Content -Path $authorizedKeys -Value $wslPubKey.Trim()
        Write-Host "Added WSL public key to authorized_keys" -ForegroundColor Green
    } else {
        Write-Host "WSL public key already in authorized_keys" -ForegroundColor Gray
    }
} else {
    Write-Host "No WSL public key found - you can add manually later" -ForegroundColor Yellow
    Write-Host "  Copy your public key to: $authorizedKeys" -ForegroundColor Gray
}

# For admin users, Windows uses administrators_authorized_keys instead
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin -and $wslPubKey) {
    $adminAuthKeys = "$env:ProgramData\ssh\administrators_authorized_keys"
    $existingAdminKeys = if (Test-Path $adminAuthKeys) { Get-Content $adminAuthKeys -Raw } else { "" }
    if ($existingAdminKeys -notlike "*$($wslPubKey.Trim())*") {
        Add-Content -Path $adminAuthKeys -Value $wslPubKey.Trim()
        # Fix permissions - must be owned by Administrators/SYSTEM only
        icacls $adminAuthKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
        Write-Host "Added key to administrators_authorized_keys" -ForegroundColor Green
    }
}

# Restart sshd to apply changes
Restart-Service sshd

# Verify
$service = Get-Service sshd
if ($service.Status -eq 'Running') {
    Write-Host "`n=== Windows SSH Server running on port 22 ===" -ForegroundColor Green
    Write-Host "Connect with: ssh $env:USERNAME@localhost" -ForegroundColor Cyan
    Write-Host "`nWSL SSH: port 222" -ForegroundColor Gray
    Write-Host "Windows SSH: port 22" -ForegroundColor Gray
} else {
    Write-Host "ERROR: sshd service not running" -ForegroundColor Red
    exit 1
}
