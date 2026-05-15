# Corterm Worker Installer for Windows
# Downloads and installs the latest worker binary for your platform.
#
# Usage: irm https://gateway.ct.rwecho.top/install.ps1 | iex

$ErrorActionPreference = "Stop"

$REPO = "monster-echo/CortexTerminal2"
$BIN_NAME = "corterm"
$INSTALL_DIR = if ($env:CORTERM_HOME) { $env:CORTERM_HOME } elseif ($env:CORTEX_TERMINAL_HOME) { $env:CORTEX_TERMINAL_HOME } else { "$env:USERPROFILE\.corterm" }
$DEFAULT_GATEWAY_URL = "https://gateway.ct.rwecho.top"
$GITHUB_PROXY = "https://proxy.0x2a.top"

# ---- Helpers ----
function Write-Info($msg)  { Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Fail($msg)  { Write-Host "  X $msg" -ForegroundColor Red; exit 1 }

# ---- Detect platform ----
function Detect-Platform {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if (-not $arch) {
        # Fallback for older PowerShell
        $arch = if ([Environment]::Is64BitProcess) { "X64" } else { "X86" }
    }

    switch ($arch.ToString()) {
        "X64"    { $ridArch = "x64" }
        "Arm64"  { $ridArch = "arm64" }
        "X86"    { $ridArch = "x86" }
        default  { Write-Fail "Unsupported architecture: $arch" }
    }

    $rid = "win-$ridArch"
    return $rid
}

# ---- Download latest release ----
function Download-Worker {
    param([string]$RID)

    $assetName = "corterm-${RID}.zip"
    $githubUrl = "https://github.com/${REPO}/releases/latest/download/${assetName}"
    $downloadUrl = "${GITHUB_PROXY}/${githubUrl}"

    Write-Info "Detected platform: $RID"
    Write-Info "Downloading $assetName ..."

    # Create install directory
    if (-not (Test-Path $INSTALL_DIR)) {
        New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
    }

    $tmpFile = Join-Path $env:TEMP $assetName

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpFile -UseBasicParsing
    } catch {
        Write-Fail "Failed to download worker binary. Check: $downloadUrl`nError: $_"
    }

    Write-Ok "Downloaded successfully"

    # Extract
    Write-Info "Extracting to $INSTALL_DIR ..."
    Expand-Archive -Path $tmpFile -DestinationPath $INSTALL_DIR -Force
    Remove-Item $tmpFile -Force

    Write-Ok "Installed to $INSTALL_DIR"
}

# ---- PATH check ----
function Add-ToPath {
    $pathParts = $env:PATH -split ";" | Where-Object { $_ -ne "" }
    $normalized = $pathParts | ForEach-Object { $_.TrimEnd("\").ToLower() }
    $target = $INSTALL_DIR.TrimEnd("\").ToLower()

    if ($normalized -notcontains $target) {
        Write-Info "Adding $INSTALL_DIR to user PATH ..."
        $currentUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($currentUserPath -notmatch [regex]::Escape($INSTALL_DIR)) {
            [Environment]::SetEnvironmentVariable("PATH", "$currentUserPath;$INSTALL_DIR", "User")
        }
        $env:PATH = "$env:PATH;$INSTALL_DIR"
        Write-Ok "Added to user PATH. Restart your terminal to apply."
    } else {
        Write-Info "$INSTALL_DIR is already in PATH."
    }
}

# ---- Install startup shortcut (auto-start) ----
function Install-Service {
    $exePath = Join-Path $INSTALL_DIR "$BIN_NAME.exe"

    if (-not (Test-Path $exePath)) {
        return
    }

    $startupFolder = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startupFolder "Corterm Worker.lnk"

    if (Test-Path $shortcutPath) {
        Write-Info "Startup shortcut already exists. Skipping."
        return
    }

    Write-Info "Creating startup shortcut ..."

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $exePath
    $shortcut.WorkingDirectory = $INSTALL_DIR
    $shortcut.WindowStyle = 7  # Minimized
    $shortcut.Description = "Corterm Worker auto-start"
    $shortcut.Save()

    Write-Ok "Startup shortcut created (auto-start on login)."
}

# ---- Start worker if already authenticated ----
function Start-IfAuthenticated {
    $authFile = Join-Path $INSTALL_DIR ".auth"
    if (-not (Test-Path $authFile)) {
        return $false
    }

    $exePath = Join-Path $INSTALL_DIR "$BIN_NAME.exe"
    if (-not (Test-Path $exePath)) {
        return $false
    }

    $proc = Get-Process -Name $BIN_NAME -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Ok "Worker is already running (PID $($proc.Id))"
        return $true
    }

    Start-Process -FilePath $exePath -WorkingDirectory $INSTALL_DIR -WindowStyle Hidden
    Write-Ok "Worker started"
    return $true
}

# ---- Main ----
Write-Host ""
Write-Host "  Corterm Worker Installer" -ForegroundColor White
Write-Host "  --------------------------------`n"

$rid = Detect-Platform
Download-Worker -RID $rid
Install-Service
Add-ToPath

Write-Host ""
if (Start-IfAuthenticated) {
    Write-Host "  Updated and running!" -ForegroundColor Green
} else {
    Write-Host "  Worker not yet authenticated." -ForegroundColor Cyan
    Write-Host "  Running '$BIN_NAME login' ...`n"
    $exePath = Join-Path $INSTALL_DIR "$BIN_NAME.exe"
    & $exePath login
    Start-IfAuthenticated | Out-Null
}
Write-Host ""
