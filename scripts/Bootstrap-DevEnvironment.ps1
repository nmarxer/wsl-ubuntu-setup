#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Complete WSL2 development environment bootstrap for fresh Windows PC.
.DESCRIPTION
    Single script to set up everything:
    1. Install WSL2 with Ubuntu
    2. Run WSL setup script (shell, languages, tools)
    3. Configure Windows SSH on port 22
    4. Install Tailscale on Windows
    5. Optionally install Tailscale on WSL
.PARAMETER WslDistro
    Ubuntu distro to install (default: Ubuntu-24.04)
.PARAMETER SkipWslInstall
    Skip WSL installation if already installed
.PARAMETER SkipWindowsSSH
    Skip Windows OpenSSH Server setup
.PARAMETER SkipTailscale
    Skip Tailscale installation
.PARAMETER UserFullName
    Git author name for WSL setup
.PARAMETER UserEmail
    Git/SSH email for WSL setup
.PARAMETER UserGithub
    GitHub username for WSL setup
.EXAMPLE
    .\Bootstrap-DevEnvironment.ps1
.EXAMPLE
    .\Bootstrap-DevEnvironment.ps1 -UserFullName "John Doe" -UserEmail "john@example.com"
.NOTES
    Run as Administrator in PowerShell.
    Requires internet connection.
    May require restarts during installation.
#>

[CmdletBinding()]
param(
    [string]$WslDistro = "Ubuntu-24.04",
    [switch]$SkipWslInstall,
    [switch]$SkipWindowsSSH,
    [switch]$SkipTailscale,
    [string]$UserFullName = "",
    [string]$UserEmail = "",
    [string]$UserGithub = ""
)

$ErrorActionPreference = 'Stop'
$RepoUrl = "https://raw.githubusercontent.com/nmarxer/wsl-ubuntu-setup/main"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "===========================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "-> $Message" -ForegroundColor Gray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

# ============================================================================
# STEP 1: WSL2 Installation
# ============================================================================

if (-not $SkipWslInstall) {
    Write-Step "Step 1/5: Installing WSL2 with $WslDistro"

    # Check if WSL is installed
    $wslInstalled = Get-Command wsl -ErrorAction SilentlyContinue

    if (-not $wslInstalled) {
        Write-Info "Installing WSL..."
        wsl --install --no-launch
        Write-Warn "WSL installed. A RESTART may be required."
        Write-Warn "After restart, run this script again with -SkipWslInstall"

        $restart = Read-Host "Restart now? (y/n)"
        if ($restart -eq 'y') {
            Restart-Computer -Force
        }
        exit 0
    }

    # Check if distro is installed
    $distros = wsl --list --quiet 2>$null
    if ($distros -notcontains $WslDistro -and $distros -notcontains $WslDistro.Replace("-", "")) {
        Write-Info "Installing $WslDistro..."
        wsl --install -d $WslDistro --no-launch
        Write-Success "$WslDistro installed"

        Write-Info "Launching $WslDistro for initial setup..."
        Write-Warn "Complete the Ubuntu username/password setup, then type 'exit'"
        wsl -d $WslDistro
    } else {
        Write-Success "WSL with Ubuntu already installed"
    }
} else {
    Write-Step "Step 1/5: Skipping WSL installation"
}

# ============================================================================
# STEP 2: Run WSL Setup Script
# ============================================================================

Write-Step "Step 2/5: Running WSL Ubuntu Setup Script"

# Build environment variables for WSL
$envVars = ""
if ($UserFullName) { $envVars += "USER_FULLNAME='$UserFullName' " }
if ($UserEmail) { $envVars += "USER_EMAIL='$UserEmail' " }
if ($UserGithub) { $envVars += "USER_GITHUB='$UserGithub' " }

$wslCommand = @"
cd ~ && \
curl -fsSL $RepoUrl/wsl_ubuntu_setup.sh -o wsl_ubuntu_setup.sh && \
chmod +x wsl_ubuntu_setup.sh && \
$envVars ./wsl_ubuntu_setup.sh --full
"@

Write-Info "Downloading and running WSL setup script..."
Write-Info "This will take 30-60 minutes..."
Write-Host ""

# Run in WSL
wsl -d $WslDistro.Replace("-24.04", "") -- bash -c $wslCommand

if ($LASTEXITCODE -eq 0) {
    Write-Success "WSL setup completed"
} else {
    Write-Warn "WSL setup may have had issues. Check the output above."
}

# ============================================================================
# STEP 3: Windows OpenSSH Server (Port 22)
# ============================================================================

if (-not $SkipWindowsSSH) {
    Write-Step "Step 3/5: Configuring Windows SSH Server (Port 22)"

    # Install OpenSSH Server
    $sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
    if ($sshCapability.State -ne 'Installed') {
        Write-Info "Installing OpenSSH Server..."
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    }

    # Configure and start
    Write-Info "Configuring sshd service..."
    Set-Service -Name sshd -StartupType 'Automatic'
    Start-Service sshd

    # Firewall rule
    $firewallRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    if (-not $firewallRule) {
        Write-Info "Adding firewall rule..."
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    }

    # Setup SSH keys from WSL
    Write-Info "Configuring SSH key authentication..."
    $sshDir = "$env:USERPROFILE\.ssh"
    $authorizedKeys = "$sshDir\authorized_keys"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    # Try to find WSL public key
    $wslDistroName = $WslDistro.Replace("-24.04", "").Replace("-22.04", "")
    $wslUsers = @($env:USERNAME, $env:USERNAME.ToLower(), 'nmarxer')

    foreach ($wslUser in $wslUsers) {
        $wslPath = "\\wsl$\$wslDistroName\home\$wslUser\.ssh\id_ed25519.pub"
        if (Test-Path $wslPath) {
            $pubKey = Get-Content $wslPath -Raw
            $existingKeys = if (Test-Path $authorizedKeys) { Get-Content $authorizedKeys -Raw } else { "" }
            if ($existingKeys -notlike "*$($pubKey.Trim())*") {
                Add-Content -Path $authorizedKeys -Value $pubKey.Trim()
                Write-Success "Added WSL public key to authorized_keys"
            }
            break
        }
    }

    # Admin authorized_keys
    $adminAuthKeys = "$env:ProgramData\ssh\administrators_authorized_keys"
    if ((Test-Path $authorizedKeys) -and (Test-Path $adminAuthKeys -eq $false -or (Get-Content $adminAuthKeys -Raw) -eq "")) {
        Copy-Item $authorizedKeys $adminAuthKeys -Force
        icacls $adminAuthKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
    }

    Restart-Service sshd
    Write-Success "Windows SSH Server running on port 22"
} else {
    Write-Step "Step 3/5: Skipping Windows SSH setup"
}

# ============================================================================
# STEP 4: Windows Tailscale
# ============================================================================

if (-not $SkipTailscale) {
    Write-Step "Step 4/5: Installing Tailscale on Windows"

    $tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($tailscale) {
        Write-Success "Tailscale already installed"
    } else {
        # Try winget first
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            Write-Info "Installing via winget..."
            winget install --id Tailscale.Tailscale --accept-package-agreements --accept-source-agreements
        } else {
            Write-Info "Downloading Tailscale MSI..."
            $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "386" }
            $msiUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest-$arch.msi"
            $msiPath = "$env:TEMP\tailscale-setup.msi"
            Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
            Write-Info "Installing..."
            Start-Process msiexec.exe -ArgumentList "/i", $msiPath, "/quiet", "/norestart" -Wait
            Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
        }

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Success "Tailscale installed"
    }
} else {
    Write-Step "Step 4/5: Skipping Tailscale installation"
}

# ============================================================================
# STEP 5: Summary
# ============================================================================

Write-Step "Step 5/5: Setup Complete!"

Write-Host "================================================================" -ForegroundColor Green
Write-Host "                    INSTALLATION COMPLETE                       " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Port Configuration:" -ForegroundColor Yellow
Write-Host "  - Windows SSH: port 22" -ForegroundColor Gray
Write-Host "  - WSL SSH:     port 222" -ForegroundColor Gray
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Restart WSL:        wsl --shutdown" -ForegroundColor Cyan
Write-Host "  2. Authenticate Tailscale:" -ForegroundColor Cyan
Write-Host "     - Windows: tailscale up" -ForegroundColor Gray
Write-Host "     - WSL:     sudo tailscale up" -ForegroundColor Gray
Write-Host "  3. Auth GitHub CLI:    gh auth login (in WSL)" -ForegroundColor Cyan
Write-Host "  4. Auth GitLab CLI:    glab auth login (in WSL)" -ForegroundColor Cyan
Write-Host "  5. Install Nerd Font:  JetBrainsMono from nerdfonts.com" -ForegroundColor Cyan
Write-Host "  6. Set terminal font:  Windows Terminal -> Settings -> Ubuntu" -ForegroundColor Cyan
Write-Host ""

Write-Host "Test SSH connections:" -ForegroundColor Yellow
Write-Host "  - Windows: ssh $env:USERNAME@localhost" -ForegroundColor Gray
Write-Host "  - WSL:     ssh -p 222 <wsl-user>@localhost" -ForegroundColor Gray
Write-Host ""
