# Corterm Worker Installer for Windows
# Downloads and installs the latest worker binary for your platform.
#
# Usage: irm https://corterm.rwecho.top/install.ps1 | iex

$ErrorActionPreference = "Stop"

$REPO = "monster-echo/CortexTerminal2"
$BIN_NAME = "corterm"
$INSTALL_DIR = if ($env:CORTERM_HOME) { $env:CORTERM_HOME } elseif ($env:CORTEX_TERMINAL_HOME) { $env:CORTEX_TERMINAL_HOME } else { "$env:USERPROFILE\.corterm" }
$DEFAULT_GATEWAY_URL = "https://corterm.rwecho.top"
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

# ---- Install scheduled task (auto-start + crash recovery) ----
function Install-Service {
    $exePath = Join-Path $INSTALL_DIR "$BIN_NAME.exe"

    if (-not (Test-Path $exePath)) {
        return
    }

    $taskName = "Corterm Worker"

    # Remove old Startup shortcut if present
    $startupFolder = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startupFolder "Corterm Worker.lnk"
    if (Test-Path $shortcutPath) {
        Remove-Item $shortcutPath -Force
        Write-Info "Removed old startup shortcut."
    }

    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if ($existingTask) {
        # Update the action path in case install dir changed
        $existingAction = $existingTask.Actions | Select-Object -First 1
        if ($existingAction.Execute -ne $exePath) {
            Set-ScheduledTask -TaskName $taskName -Action (New-ScheduledTaskAction -Execute $exePath -WorkingDirectory $INSTALL_DIR) | Out-Null
            Write-Ok "Updated scheduled task path."
        } else {
            Write-Info "Scheduled task already configured. Skipping."
        }
        return
    }

    Write-Info "Creating scheduled task for auto-start and crash recovery ..."

    $action = New-ScheduledTaskAction -Execute $exePath -WorkingDirectory $INSTALL_DIR
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Seconds 5)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Corterm Worker auto-start with crash recovery" | Out-Null

    Write-Ok "Scheduled task created (auto-start on login, restart on crash)."
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
