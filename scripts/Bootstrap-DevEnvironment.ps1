#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Complete WSL2 development environment bootstrap for fresh Windows PC.
.DESCRIPTION
    Single script to set up everything:
    1. Install WSL2 with Ubuntu
    2. Run WSL setup script (shell, languages, tools)
    3. Configure Windows SSH on port 22
    4. Install Windows applications (Tailscale, Zed, Firefox, Spotify, Claude, PowerShell 7, Xpipe)
    5. Interactive SSH/GPG key setup and repository cloning
.PARAMETER WslDistro
    Ubuntu distro to install (default: Ubuntu)
.PARAMETER SkipWslInstall
    Skip WSL installation if already installed
.PARAMETER SkipWindowsSSH
    Skip Windows OpenSSH Server setup
.PARAMETER SkipWindowsApps
    Skip Windows application installations
.PARAMETER ResetCheckpoints
    Clear WSL installation checkpoints for a fresh install
.PARAMETER UserFullName
    Git author name for WSL setup
.PARAMETER UserGithub
    GitHub username for WSL setup
.PARAMETER UserGithubEmail
    GitHub email for WSL setup
.PARAMETER UserGitlab
    GitLab username for WSL setup (optional)
.PARAMETER UserGitlabEmail
    GitLab email for WSL setup (optional)
.PARAMETER GitlabServer
    GitLab server URL (optional, e.g., gitlab.company.com, defaults to gitlab.com)
.PARAMETER UseGitlabForGit
    Use GitLab email for git config instead of GitHub email
.EXAMPLE
    .\Bootstrap-DevEnvironment.ps1
.EXAMPLE
    .\Bootstrap-DevEnvironment.ps1 -UserFullName "John Doe" -UserGithub "johndoe" -UserGithubEmail "john@example.com"
.EXAMPLE
    .\Bootstrap-DevEnvironment.ps1 -UserFullName "John Doe" -UserGithub "johndoe" -UserGithubEmail "john@personal.com" -UserGitlab "jdoe" -UserGitlabEmail "john.doe@company.com" -GitlabServer "gitlab.company.com" -UseGitlabForGit
.NOTES
    Run as Administrator in PowerShell.
    Requires internet connection.
    May require restarts during installation.
#>

[CmdletBinding()]
param(
    [string]$WslDistro = "Ubuntu",
    [switch]$SkipWslInstall,
    [switch]$SkipWindowsSSH,
    [switch]$SkipWindowsApps,
    [switch]$ResetCheckpoints,
    [string]$UserFullName = "",
    [string]$UserGithub = "",
    [string]$UserGithubEmail = "",
    [string]$UserGitlab = "",
    [string]$UserGitlabEmail = "",
    [string]$GitlabServer = "",
    [switch]$UseGitlabForGit
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

function Install-WingetApp {
    param(
        [string]$AppId,
        [string]$AppName,
        [string]$ExtraArgs = ""
    )
    $installed = winget list --id $AppId 2>$null | Select-String $AppId
    if ($installed) {
        Write-Success "$AppName already installed"
        return $true
    }
    Write-Info "Installing $AppName..."
    $cmd = "winget install --id $AppId --accept-package-agreements --accept-source-agreements --silent $ExtraArgs"
    Invoke-Expression $cmd
    if ($LASTEXITCODE -eq 0) {
        Write-Success "$AppName installed"
        return $true
    } else {
        Write-Warn "Failed to install $AppName"
        return $false
    }
}

# ============================================================================
# PHASE 0: User Information Collection (3-Phase Prompts)
# ============================================================================

Write-Step "Phase 0: User Configuration"

Write-Host "================================================================" -ForegroundColor Yellow
Write-Host "       WSL Development Environment Setup                        " -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host ""

# --------------------------------------------------------------------------
# Phase 1: GitHub Configuration (Required)
# --------------------------------------------------------------------------
Write-Host "--- Phase 1/3: GitHub Configuration (Required) ---" -ForegroundColor Cyan
Write-Host ""

if (-not $UserFullName) {
    $UserFullName = Read-Host "Enter your full name (for Git commits)"
}
if (-not $UserGithub) {
    $UserGithub = Read-Host "Enter your GitHub username"
}
if (-not $UserGithubEmail) {
    $UserGithubEmail = Read-Host "Enter your GitHub email"
}

Write-Host ""

# --------------------------------------------------------------------------
# Phase 2: GitLab Decision
# --------------------------------------------------------------------------
Write-Host "--- Phase 2/3: GitLab Configuration (Optional) ---" -ForegroundColor Cyan
Write-Host ""

$configureGitlab = $false
if ($UserGitlab -or $UserGitlabEmail -or $GitlabServer) {
    # GitLab info provided via parameters
    $configureGitlab = $true
} else {
    $gitlabChoice = Read-Host "Do you want to configure GitLab? (y/n)"
    $configureGitlab = ($gitlabChoice -eq 'y')
}

# --------------------------------------------------------------------------
# Phase 3: GitLab Details (if opted in)
# --------------------------------------------------------------------------
if ($configureGitlab) {
    Write-Host ""
    Write-Host "--- Phase 3/3: GitLab Details ---" -ForegroundColor Cyan
    Write-Host ""

    if (-not $GitlabServer) {
        $gitlabServerResponse = Read-Host "Enter GitLab server URL (e.g., gitlab.company.com, or press Enter for gitlab.com)"
        if ($gitlabServerResponse) {
            $GitlabServer = $gitlabServerResponse
        } else {
            $GitlabServer = "gitlab.com"
        }
    }
    if (-not $UserGitlab) {
        $UserGitlab = Read-Host "Enter your GitLab username"
    }
    if (-not $UserGitlabEmail) {
        $UserGitlabEmail = Read-Host "Enter your GitLab email"
    }

    # Ask which email to use for git config
    if (-not $UseGitlabForGit) {
        Write-Host ""
        Write-Host "Which email should Git use for commits?" -ForegroundColor Yellow
        Write-Host "  1. GitHub email: $UserGithubEmail" -ForegroundColor Gray
        Write-Host "  2. GitLab email: $UserGitlabEmail" -ForegroundColor Gray
        $gitEmailChoice = Read-Host "Choose (1 or 2, default: 1)"
        if ($gitEmailChoice -eq '2') {
            $UseGitlabForGit = $true
        }
    }
}

# Determine which email to use for git config
$GitEmail = if ($UseGitlabForGit -and $UserGitlabEmail) { $UserGitlabEmail } else { $UserGithubEmail }

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Configuration Summary:" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Full Name:      $UserFullName" -ForegroundColor Gray
Write-Host ""
Write-Host "  GitHub:" -ForegroundColor Yellow
Write-Host "    Username:     $UserGithub" -ForegroundColor Gray
Write-Host "    Email:        $UserGithubEmail" -ForegroundColor Gray
if ($configureGitlab) {
    Write-Host ""
    Write-Host "  GitLab:" -ForegroundColor Yellow
    Write-Host "    Server:       $GitlabServer" -ForegroundColor Gray
    Write-Host "    Username:     $UserGitlab" -ForegroundColor Gray
    Write-Host "    Email:        $UserGitlabEmail" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  Git Configuration:" -ForegroundColor Yellow
Write-Host "    Email:        $GitEmail" -ForegroundColor Green
Write-Host ""

$confirm = Read-Host "Continue with this configuration? (y/n)"
if ($confirm -ne 'y') {
    Write-Warn "Setup cancelled. Run again with correct information."
    exit 0
}

Write-Success "Configuration confirmed"

# ============================================================================
# STEP 1: WSL2 Installation
# ============================================================================

if (-not $SkipWslInstall) {
    Write-Step "Step 1/6: Installing WSL2 with $WslDistro"

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

    $distros = wsl --list --quiet 2>$null
    $distroExists = $distros | Where-Object { $_ -match "Ubuntu" }
    if (-not $distroExists) {
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
    Write-Step "Step 1/6: Skipping WSL installation"
}

# ============================================================================
# STEP 2: Run WSL Setup Script
# ============================================================================

Write-Step "Step 2/6: Running WSL Ubuntu Setup Script"

$envVars = "DEBIAN_FRONTEND=noninteractive DOCKER_CHOICE=1 SKIP_SSH_VALIDATE=1 "
if ($UserFullName) { $envVars += "USER_FULLNAME='$UserFullName' " }
if ($GitEmail) { $envVars += "USER_EMAIL='$GitEmail' " }
if ($UserGithubEmail) { $envVars += "USER_GITHUB_EMAIL='$UserGithubEmail' " }
if ($UserGithub) { $envVars += "USER_GITHUB='$UserGithub' " }
if ($UserGitlab) { $envVars += "USER_GITLAB='$UserGitlab' " }
if ($UserGitlabEmail) { $envVars += "USER_GITLAB_EMAIL='$UserGitlabEmail' " }
if ($GitlabServer) { $envVars += "COMPANY_GITLAB='$GitlabServer' " }

# Reset checkpoints if requested (for fresh install)
if ($ResetCheckpoints) {
    Write-Info "Resetting WSL installation checkpoints..."
    wsl rm -f ~/.wsl_ubuntu_setup_logs/.checkpoint 2>$null
    Write-Success "Checkpoints cleared"
}

$wslCommand = "cd ~ && curl -fsSL $RepoUrl/wsl_ubuntu_setup.sh -o wsl_ubuntu_setup.sh && sed -i 's/\r`$//' wsl_ubuntu_setup.sh && chmod +x wsl_ubuntu_setup.sh && $envVars ./wsl_ubuntu_setup.sh --orchestrated"

Write-Info "Downloading and running WSL setup script..."
Write-Info "This will take 30-60 minutes..."
Write-Host ""

$wslDistroName = $WslDistro
if ($WslDistro -eq "Ubuntu") {
    $installedDistros = wsl --list --quiet 2>$null
    $ubuntuDistro = $installedDistros | Where-Object { $_ -match "^Ubuntu" } | Select-Object -First 1
    if ($ubuntuDistro) { $wslDistroName = $ubuntuDistro.Trim() }
}

wsl -d $wslDistroName -- bash -c $wslCommand

if ($LASTEXITCODE -eq 0) {
    Write-Success "WSL setup completed"
} else {
    Write-Warn "WSL setup may have had issues. Check the output above."
}

# ============================================================================
# STEP 3: Windows OpenSSH Server (Port 22)
# ============================================================================

if (-not $SkipWindowsSSH) {
    Write-Step "Step 3/6: Configuring Windows SSH Server (Port 22)"

    $sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
    if ($sshCapability.State -ne 'Installed') {
        Write-Info "Installing OpenSSH Server..."
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    }

    Write-Info "Configuring sshd service..."
    Set-Service -Name sshd -StartupType 'Automatic'
    Start-Service sshd

    $firewallRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    if (-not $firewallRule) {
        Write-Info "Adding firewall rule..."
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    }

    Write-Info "Configuring SSH key authentication..."
    $sshDir = "$env:USERPROFILE\.ssh"
    $authorizedKeys = "$sshDir\authorized_keys"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    $wslDistroNames = @('Ubuntu', 'Ubuntu-24.04', 'Ubuntu-22.04')
    $wslUsers = @($env:USERNAME, $env:USERNAME.ToLower(), 'nmarxer')
    $keyFound = $false

    foreach ($distro in $wslDistroNames) {
        if ($keyFound) { break }
        foreach ($wslUser in $wslUsers) {
            $wslPath = "\\wsl`$\$distro\home\$wslUser\.ssh\id_ed25519.pub"
            if (Test-Path $wslPath) {
                $pubKey = Get-Content $wslPath -Raw
                $existingKeys = if (Test-Path $authorizedKeys) { Get-Content $authorizedKeys -Raw } else { "" }
                if ($existingKeys -notlike "*$($pubKey.Trim())*") {
                    Add-Content -Path $authorizedKeys -Value $pubKey.Trim()
                    Write-Success "Added WSL public key to authorized_keys"
                }
                $keyFound = $true
                break
            }
        }
    }

    $adminAuthKeys = "$env:ProgramData\ssh\administrators_authorized_keys"
    if ((Test-Path $authorizedKeys) -and (Test-Path $adminAuthKeys -eq $false -or (Get-Content $adminAuthKeys -Raw) -eq "")) {
        Copy-Item $authorizedKeys $adminAuthKeys -Force
        icacls $adminAuthKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
    }

    Restart-Service sshd
    Write-Success "Windows SSH Server running on port 22"
} else {
    Write-Step "Step 3/6: Skipping Windows SSH setup"
}

# ============================================================================
# STEP 4: Windows Applications
# ============================================================================

if (-not $SkipWindowsApps) {
    Write-Step "Step 4/6: Installing Windows Applications"

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Warn "winget not found. Skipping Windows app installations."
        Write-Warn "Install App Installer from Microsoft Store to enable winget."
    } else {
        # Essential apps
        Install-WingetApp -AppId "Tailscale.Tailscale" -AppName "Tailscale VPN"
        Install-WingetApp -AppId "Microsoft.PowerShell" -AppName "PowerShell 7"

        # Nerd Font for terminal (required for Oh My Posh icons)
        Install-WingetApp -AppId "DEVCOM.JetBrainsMonoNerdFont" -AppName "JetBrainsMono Nerd Font"

        # Development tools
        Install-WingetApp -AppId "ZedIndustries.Zed" -AppName "Zed Editor"
        Install-WingetApp -AppId "xpipe-io.xpipe" -AppName "XPipe"
        Install-WingetApp -AppId "Anthropic.Claude" -AppName "Claude Desktop"

        # Browsers and media
        Install-WingetApp -AppId "Mozilla.Firefox" -AppName "Mozilla Firefox"

        # Spotify requires non-admin context - install separately
        $spotifyInstalled = winget list --id Spotify.Spotify 2>$null | Select-String "Spotify"
        if ($spotifyInstalled) {
            Write-Success "Spotify already installed"
        } else {
            Write-Info "Installing Spotify (requires non-admin - opening separate installer)..."
            # Download and run Spotify web installer which handles this properly
            $spotifyUrl = "https://download.scdn.co/SpotifySetup.exe"
            $spotifyPath = "$env:TEMP\SpotifySetup.exe"
            try {
                Invoke-WebRequest -Uri $spotifyUrl -OutFile $spotifyPath -UseBasicParsing
                Start-Process -FilePath $spotifyPath -Wait
                Write-Success "Spotify installer launched"
            } catch {
                Write-Warn "Spotify: Install manually from spotify.com/download"
            }
        }

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Success "Windows applications installed"
    }
} else {
    Write-Step "Step 4/6: Skipping Windows applications"
}

# ============================================================================
# STEP 5: Interactive SSH/GPG Key Setup
# ============================================================================

Write-Step "Step 5/6: SSH and GPG Key Configuration"

# Get WSL user - try multiple methods
$wslUser = $null

# Method 1: Check who owns /home directories
$homeUsers = wsl bash -c "ls /home 2>/dev/null" 2>$null
if ($homeUsers) {
    $wslUser = ($homeUsers -split '\s+' | Where-Object { $_ -ne '' } | Select-Object -First 1)
}

# Method 2: Fallback to Windows username lowercase
if (-not $wslUser) {
    $wslUser = $env:USERNAME.ToLower()
}

Write-Info "Detected WSL user: $wslUser"

# Get SSH public key - try multiple methods
$sshPubKey = $null

# Method 1: Direct UNC path access (works when WSL is running)
$uncPaths = @(
    "\\wsl$\Ubuntu\home\$wslUser\.ssh\id_ed25519.pub",
    "\\wsl$\Ubuntu-24.04\home\$wslUser\.ssh\id_ed25519.pub",
    "\\wsl.localhost\Ubuntu\home\$wslUser\.ssh\id_ed25519.pub"
)
foreach ($uncPath in $uncPaths) {
    if (Test-Path $uncPath) {
        $sshPubKey = (Get-Content $uncPath -Raw).Trim()
        Write-Info "SSH key found via UNC path"
        break
    }
}

# Method 2: WSL bash command with proper error suppression
if (-not $sshPubKey) {
    # Use bash -c with stderr suppression inside bash to avoid PowerShell error output
    $sshKeyOutput = $null
    try {
        $sshKeyOutput = wsl bash -c "cat /home/$wslUser/.ssh/id_ed25519.pub 2>/dev/null" 2>$null
    } catch {
        # Ignore errors
    }
    if ($sshKeyOutput -and $sshKeyOutput -like "ssh-*") {
        $sshPubKey = if ($sshKeyOutput -is [array]) { ($sshKeyOutput -join "").Trim() } else { $sshKeyOutput.ToString().Trim() }
        Write-Info "SSH key found via WSL bash"
    }
}

# Method 3: Try GitHub-specific key
if (-not $sshPubKey) {
    $sshKeyOutput = $null
    try {
        $sshKeyOutput = wsl bash -c "cat /home/$wslUser/.ssh/id_ed25519_github.pub 2>/dev/null" 2>$null
    } catch {
        # Ignore errors
    }
    if ($sshKeyOutput -and $sshKeyOutput -like "ssh-*") {
        $sshPubKey = if ($sshKeyOutput -is [array]) { ($sshKeyOutput -join "").Trim() } else { $sshKeyOutput.ToString().Trim() }
        Write-Info "SSH key found via wsl bash"
    }
}

# Get GPG key from WSL (run as the actual user)
$gpgPubKey = $null
$gpgKeyId = $null
try {
    $gpgKeyId = wsl bash -c "sudo -u $wslUser gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -E 'sec\s+' | head -1 | sed 's/.*\/\([A-F0-9]\+\).*/\1/'" 2>$null
} catch {
    # Ignore GPG errors
}
if ($gpgKeyId) {
    $gpgKeyId = $gpgKeyId.Trim()
    if ($gpgKeyId -match "^[A-F0-9]+$") {
        try {
            $gpgPubKey = wsl bash -c "sudo -u $wslUser gpg --armor --export $gpgKeyId 2>/dev/null" 2>$null
        } catch {
            # Ignore GPG export errors
        }
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host "            SSH AND GPG KEY CONFIGURATION                       " -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host ""

# Display SSH key
if ($sshPubKey) {
    Write-Host "SSH Public Key (add to GitHub/GitLab):" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host $sshPubKey.Trim() -ForegroundColor White
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Add this key to:" -ForegroundColor Yellow
    Write-Host "  - GitHub:  https://github.com/settings/ssh/new" -ForegroundColor Gray
    if ($GitlabServer) {
        Write-Host "  - GitLab:  https://$GitlabServer/-/user_settings/ssh_keys" -ForegroundColor Gray
    }
} else {
    Write-Warn "SSH key not found in WSL"
}

Write-Host ""

# Display GPG key
if ($gpgPubKey) {
    Write-Host "GPG Public Key (add to GitHub/GitLab for signed commits):" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host $gpgPubKey -ForegroundColor White
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Add this key to:" -ForegroundColor Yellow
    Write-Host "  - GitHub:  https://github.com/settings/gpg/new" -ForegroundColor Gray
    if ($GitlabServer) {
        Write-Host "  - GitLab:  https://$GitlabServer/-/user_settings/gpg_keys" -ForegroundColor Gray
    }
} else {
    Write-Info "GPG key not found (optional for signed commits)"
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Yellow

# Wait for user confirmation
$keysAdded = Read-Host "Have you added your SSH key to GitHub (and GitLab if applicable)? (y/n)"

if ($keysAdded -eq 'y') {
    Write-Info "Testing SSH connection to GitHub..."
    $sshTest = wsl ssh -T git@github.com -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 2>&1
    if ($sshTest -match "successfully authenticated|Hi ") {
        Write-Success "GitHub SSH authentication successful!"

        # Test GitLab if server provided
        if ($GitlabServer) {
            Write-Info "Testing SSH connection to GitLab..."
            $gitlabTest = wsl ssh -T "git@$GitlabServer" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 2>&1
            if ($gitlabTest -match "Welcome|successfully") {
                Write-Success "GitLab SSH authentication successful!"
            } else {
                Write-Warn "GitLab SSH test failed. You may need to add the key manually."
            }
        }

        # Clone configuration repositories
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Yellow
        Write-Host "            REPOSITORY CLONING                                  " -ForegroundColor Yellow
        Write-Host "================================================================" -ForegroundColor Yellow
        Write-Host ""

        $githubUser = if ($UserGithub) { $UserGithub } else { Read-Host "Enter your GitHub username" }

        # Clone .claude configuration
        Write-Info "Cloning Claude Code configuration (.claude)..."
        $cloneCmd = "cd ~ && if [ ! -d .claude ]; then git clone git@github.com:$githubUser/.claude.git .claude 2>/dev/null || echo 'CLONE_FAILED'; else echo 'EXISTS'; fi"
        $result = wsl bash -c $cloneCmd
        if ($result -eq "EXISTS") {
            Write-Success ".claude already exists"
        } elseif ($result -eq "CLONE_FAILED") {
            Write-Warn ".claude repository not found or clone failed"
        } else {
            Write-Success ".claude cloned successfully"
        }

        # Clone thoughts/notes repository
        Write-Info "Cloning thoughts/notes repository..."
        $cloneCmd = "cd ~/projects/personal && if [ ! -d thoughts ]; then git clone git@github.com:$githubUser/thoughts.git thoughts 2>/dev/null || echo 'CLONE_FAILED'; else echo 'EXISTS'; fi"
        $result = wsl bash -c $cloneCmd
        if ($result -eq "EXISTS") {
            Write-Success "thoughts already exists"
        } elseif ($result -eq "CLONE_FAILED") {
            Write-Warn "thoughts repository not found or clone failed"
        } else {
            Write-Success "thoughts cloned successfully"
        }

    } else {
        Write-Warn "GitHub SSH test failed. Please verify your SSH key was added correctly."
        Write-Host "Error: $sshTest" -ForegroundColor Red
    }
} else {
    Write-Warn "Skipping SSH verification. Remember to add your keys later!"
    Write-Host ""
    Write-Host "To add keys later:" -ForegroundColor Yellow
    Write-Host "  1. Copy the SSH key above" -ForegroundColor Gray
    Write-Host "  2. Go to https://github.com/settings/ssh/new" -ForegroundColor Gray
    Write-Host "  3. Paste and save" -ForegroundColor Gray
}

# ============================================================================
# STEP 6: Summary
# ============================================================================

Write-Step "Step 6/6: Setup Complete!"

Write-Host "================================================================" -ForegroundColor Green
Write-Host "                    INSTALLATION COMPLETE                       " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Port Configuration:" -ForegroundColor Yellow
Write-Host "  - Windows SSH: port 22" -ForegroundColor Gray
Write-Host "  - WSL SSH:     port 222" -ForegroundColor Gray
Write-Host ""

Write-Host "Installed Windows Apps:" -ForegroundColor Yellow
Write-Host "  - Tailscale VPN" -ForegroundColor Gray
Write-Host "  - PowerShell 7" -ForegroundColor Gray
Write-Host "  - JetBrainsMono Nerd Font" -ForegroundColor Gray
Write-Host "  - Zed Editor" -ForegroundColor Gray
Write-Host "  - XPipe" -ForegroundColor Gray
Write-Host "  - Claude Desktop" -ForegroundColor Gray
Write-Host "  - Mozilla Firefox" -ForegroundColor Gray
Write-Host "  - Spotify" -ForegroundColor Gray
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Restart WSL:        wsl --shutdown" -ForegroundColor Cyan
Write-Host "  2. Authenticate Tailscale:" -ForegroundColor Cyan
Write-Host "     - Windows: tailscale up" -ForegroundColor Gray
Write-Host "     - WSL:     sudo tailscale up" -ForegroundColor Gray
Write-Host "  3. Set terminal font:  Windows Terminal -> Settings -> Ubuntu -> JetBrainsMono Nerd Font" -ForegroundColor Cyan
Write-Host ""

Write-Host "Test SSH connections:" -ForegroundColor Yellow
Write-Host "  - Windows: ssh $env:USERNAME@localhost" -ForegroundColor Gray
Write-Host "  - WSL:     ssh -p 222 $wslUser@localhost" -ForegroundColor Gray
Write-Host ""
