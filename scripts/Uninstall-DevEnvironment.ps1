#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstall WSL development environment for fresh testing.
.DESCRIPTION
    Removes everything installed by Bootstrap-DevEnvironment.ps1:
    1. Tailscale
    2. Windows OpenSSH Server
    3. SSH authorized_keys
    4. WSL distributions
    5. WSL feature (last)
.PARAMETER KeepTailscale
    Don't uninstall Tailscale
.PARAMETER KeepSSH
    Don't uninstall Windows OpenSSH Server
.PARAMETER KeepWSL
    Don't uninstall WSL (only remove distributions)
.PARAMETER Force
    Skip confirmation prompts
.EXAMPLE
    .\Uninstall-DevEnvironment.ps1
.EXAMPLE
    .\Uninstall-DevEnvironment.ps1 -Force
.NOTES
    Run as Administrator. Restart required after WSL removal.
#>

[CmdletBinding()]
param(
    [switch]$KeepTailscale,
    [switch]$KeepSSH,
    [switch]$KeepWSL,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Red
    Write-Host "  $Message" -ForegroundColor Red
    Write-Host "===========================================================" -ForegroundColor Red
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

# Confirmation
if (-not $Force) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host "              WARNING: DESTRUCTIVE OPERATION                    " -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "This will PERMANENTLY remove:" -ForegroundColor Yellow
    if (-not $KeepTailscale) { Write-Host "  - Tailscale VPN" -ForegroundColor Gray }
    if (-not $KeepSSH) { Write-Host "  - Windows OpenSSH Server" -ForegroundColor Gray }
    Write-Host "  - SSH authorized_keys" -ForegroundColor Gray
    Write-Host "  - ALL WSL distributions and their data" -ForegroundColor Gray
    if (-not $KeepWSL) { Write-Host "  - WSL feature entirely" -ForegroundColor Gray }
    Write-Host ""

    $confirm = Read-Host "Type 'YES' to confirm"
    if ($confirm -ne 'YES') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

# ============================================================================
# STEP 1: Uninstall Tailscale
# ============================================================================

if (-not $KeepTailscale) {
    Write-Step "Step 1/5: Uninstalling Tailscale"

    # Stop Tailscale
    $tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($tailscale) {
        Write-Info "Logging out of Tailscale..."
        & tailscale logout 2>$null

        # Uninstall via winget
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            Write-Info "Uninstalling via winget..."
            winget uninstall --id Tailscale.Tailscale --silent 2>$null
        }

        # Also try via Programs
        $tailscaleApp = Get-Package -Name "*Tailscale*" -ErrorAction SilentlyContinue
        if ($tailscaleApp) {
            Write-Info "Uninstalling Tailscale package..."
            $tailscaleApp | Uninstall-Package -Force 2>$null
        }

        # Remove via MSI if still present
        $msiProduct = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Tailscale*" }
        if ($msiProduct) {
            Write-Info "Uninstalling via MSI..."
            $msiProduct.Uninstall() | Out-Null
        }

        Write-Success "Tailscale uninstalled"
    } else {
        Write-Info "Tailscale not installed"
    }

    # Remove Tailscale data
    $tailscaleData = "$env:LocalAppData\Tailscale"
    if (Test-Path $tailscaleData) {
        Remove-Item -Path $tailscaleData -Recurse -Force -ErrorAction SilentlyContinue
        Write-Info "Removed Tailscale data"
    }
} else {
    Write-Step "Step 1/5: Keeping Tailscale"
}

# ============================================================================
# STEP 2: Uninstall Windows OpenSSH Server
# ============================================================================

if (-not $KeepSSH) {
    Write-Step "Step 2/5: Uninstalling Windows OpenSSH Server"

    # Stop and disable service
    $sshService = Get-Service sshd -ErrorAction SilentlyContinue
    if ($sshService) {
        Write-Info "Stopping SSH service..."
        Stop-Service sshd -Force -ErrorAction SilentlyContinue
        Set-Service -Name sshd -StartupType Disabled -ErrorAction SilentlyContinue
    }

    # Remove OpenSSH Server capability
    $sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
    if ($sshCapability.State -eq 'Installed') {
        Write-Info "Removing OpenSSH Server..."
        Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        Write-Success "OpenSSH Server removed"
    } else {
        Write-Info "OpenSSH Server not installed"
    }

    # Remove firewall rule
    $firewallRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    if ($firewallRule) {
        Write-Info "Removing firewall rule..."
        Remove-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
    }

    # Remove SSH config
    $sshConfig = "$env:ProgramData\ssh"
    if (Test-Path $sshConfig) {
        Write-Info "Removing SSH config directory..."
        Remove-Item -Path $sshConfig -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Step "Step 2/5: Keeping Windows OpenSSH Server"
}

# ============================================================================
# STEP 3: Remove SSH Keys/Authorized Keys
# ============================================================================

Write-Step "Step 3/5: Removing SSH Keys"

$sshDir = "$env:USERPROFILE\.ssh"
if (Test-Path $sshDir) {
    # Only remove authorized_keys, keep user's own keys
    $authorizedKeys = "$sshDir\authorized_keys"
    if (Test-Path $authorizedKeys) {
        Remove-Item $authorizedKeys -Force
        Write-Success "Removed authorized_keys"
    }

    # Ask about removing all SSH keys
    if (-not $Force) {
        $removeAllKeys = Read-Host "Remove ALL SSH keys in $sshDir? (y/n)"
        if ($removeAllKeys -eq 'y') {
            Remove-Item -Path $sshDir -Recurse -Force
            Write-Success "Removed all SSH keys"
        } else {
            Write-Info "Kept SSH keys"
        }
    }
} else {
    Write-Info "No SSH directory found"
}

# ============================================================================
# STEP 4: Uninstall WSL Distributions
# ============================================================================

Write-Step "Step 4/5: Uninstalling WSL Distributions"

$wsl = Get-Command wsl -ErrorAction SilentlyContinue
if ($wsl) {
    # Get all distributions
    $distros = wsl --list --quiet 2>$null | Where-Object { $_ -and $_ -notmatch '^\s*$' }

    if ($distros) {
        foreach ($distro in $distros) {
            $distro = $distro.Trim()
            if ($distro) {
                Write-Info "Unregistering $distro..."
                wsl --unregister $distro 2>$null
                Write-Success "Removed $distro"
            }
        }
    } else {
        Write-Info "No WSL distributions found"
    }

    # Shutdown WSL
    Write-Info "Shutting down WSL..."
    wsl --shutdown 2>$null

    # Remove WSL data directories
    Write-Info "Removing WSL data directories..."

    # Remove Ubuntu packages from LocalAppData
    $wslPackages = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "*Ubuntu*" -ErrorAction SilentlyContinue
    foreach ($pkg in $wslPackages) {
        Write-Info "Removing $($pkg.Name)..."
        Remove-Item -Path $pkg.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Remove CanonicalGroup packages
    $canonicalPkgs = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "*CanonicalGroup*" -ErrorAction SilentlyContinue
    foreach ($pkg in $canonicalPkgs) {
        Write-Info "Removing $($pkg.Name)..."
        Remove-Item -Path $pkg.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Remove lxss directory (older WSL)
    if (Test-Path "$env:LOCALAPPDATA\lxss") {
        Write-Info "Removing lxss directory..."
        Remove-Item -Path "$env:LOCALAPPDATA\lxss" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Remove .wslconfig
    if (Test-Path "$env:USERPROFILE\.wslconfig") {
        Remove-Item "$env:USERPROFILE\.wslconfig" -Force -ErrorAction SilentlyContinue
        Write-Info "Removed .wslconfig"
    }

    Write-Success "WSL data directories removed"
} else {
    Write-Info "WSL not installed"
}

# ============================================================================
# STEP 5: Uninstall WSL Feature (Last)
# ============================================================================

if (-not $KeepWSL) {
    Write-Step "Step 5/5: Uninstalling WSL Feature"

    # Disable WSL features
    Write-Info "Disabling Windows Subsystem for Linux..."
    Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart -ErrorAction SilentlyContinue | Out-Null

    Write-Info "Disabling Virtual Machine Platform..."
    Disable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart -ErrorAction SilentlyContinue | Out-Null

    # Remove WSL update package
    $wslUpdate = Get-Package -Name "*Windows Subsystem for Linux*" -ErrorAction SilentlyContinue
    if ($wslUpdate) {
        Write-Info "Removing WSL update package..."
        $wslUpdate | Uninstall-Package -Force -ErrorAction SilentlyContinue
    }

    # Uninstall WSL via winget
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "Removing WSL via winget..."
        winget uninstall --id Microsoft.WSL --silent 2>$null
    }

    Write-Success "WSL features disabled"
} else {
    Write-Step "Step 5/5: Keeping WSL Feature"
}

# ============================================================================
# Summary
# ============================================================================

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "                    UNINSTALL COMPLETE                          " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Removed:" -ForegroundColor Yellow
if (-not $KeepTailscale) { Write-Host "  [OK] Tailscale" -ForegroundColor Green }
if (-not $KeepSSH) { Write-Host "  [OK] Windows OpenSSH Server" -ForegroundColor Green }
Write-Host "  [OK] SSH authorized_keys" -ForegroundColor Green
Write-Host "  [OK] WSL distributions" -ForegroundColor Green
if (-not $KeepWSL) { Write-Host "  [OK] WSL feature" -ForegroundColor Green }

Write-Host ""
Write-Host ">> RESTART REQUIRED to complete WSL removal" -ForegroundColor Yellow
Write-Host ""

$restart = Read-Host "Restart now? (y/n)"
if ($restart -eq 'y') {
    Restart-Computer -Force
}
