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
