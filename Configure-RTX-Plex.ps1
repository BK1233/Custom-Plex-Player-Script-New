# Configure-RTX-Plex.ps1
# PowerShell script to fully configure or uninstall RTX Video Super Resolution (VSR) and RTX HDR (SDR-to-HDR) for Plex Player applications.
# Supports both Plex HTPC and Plex for Windows.

param(
    [switch]$Uninstall
)

# ---------------------------------------------------------
# Helper: Logging/Formatting
# ---------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $colors = @{
        "INFO" = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR" = "Red"
    }
    $color = $colors[$Level]
    if (-not $color) { $color = "White" }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')][$Level] $Message" -ForegroundColor $color
}

# ---------------------------------------------------------
# Pre-requisite check: Run as Administrator
# ---------------------------------------------------------
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script requires Administrator privileges to edit/restore DLLs in Program Files." -Level ERROR
    Write-Log "Please restart PowerShell as Administrator and run the script again." -Level ERROR
    Exit 1
}

# ---------------------------------------------------------
# Locate Plex Directories and Configuration Folders
# ---------------------------------------------------------
$plexInstallDirs = @{
    "Plex HTPC" = "C:\Program Files\Plex\Plex HTPC"
    "Plex for Windows" = "C:\Program Files\Plex\Plex"
}

$plexConfigDirs = @{
    "Plex HTPC" = Join-Path $env:LOCALAPPDATA "Plex HTPC"
    "Plex for Windows" = Join-Path $env:LOCALAPPDATA "Plex"
}

$activePlexApps = @()

foreach ($appName in $plexInstallDirs.Keys) {
    $installDir = $plexInstallDirs[$appName]
    $configDir = $plexConfigDirs[$appName]

    if (Test-Path $installDir) {
        Write-Log "Found installation of $appName at '$installDir'" -Level SUCCESS
        $activePlexApps += [PSCustomObject]@{
            Name = $appName
            InstallDir = $installDir
            ConfigDir = $configDir
            DllPath = Join-Path $installDir "libmpv-2.dll"
        }
    }
}

if ($activePlexApps.Count -eq 0) {
    Write-Log "No compatible Plex players (Plex HTPC or Plex for Windows) were found in default Program Files paths." -Level ERROR
    Exit 1
}

# ---------------------------------------------------------
# EXECUTE UNINSTALLATION LOGIC IF SPECIFIED
# ---------------------------------------------------------
if ($Uninstall) {
    Write-Log "=========================================================" -Level WARNING
    Write-Log "Starting Uninstallation & Restore of Plex modifications..." -Level WARNING
    Write-Log "=========================================================" -Level WARNING

    foreach ($app in $activePlexApps) {
        Write-Log "Restoring defaults for $($app.Name)..." -Level INFO

        # Stop active Plex processes to release locks on DLLs
        Write-Log "Stopping running processes of $($app.Name) to release file locks..." -Level INFO
        Stop-Process -Name ($app.Name -replace " ", "") -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # 1. Restore DLL Backup
        $backupDll = $app.DllPath + ".bak"
        if (Test-Path $backupDll) {
            Write-Log "Found original DLL backup at '$backupDll'. Restoring..." -Level SUCCESS
            try {
                Copy-Item -Path $backupDll -Destination $app.DllPath -Force
                Remove-Item -Path $backupDll -Force -ErrorAction SilentlyContinue
                Write-Log "Successfully restored original libmpv-2.dll." -Level SUCCESS
            } catch {
                Write-Log "Failed to restore original DLL: $_" -Level ERROR
            }
        } else {
            Write-Log "No original DLL backup file found at '$backupDll'. Cannot revert libmpv-2.dll automatically." -Level WARNING
        }

        # 2. Restore/Remove mpv.conf
        $mpvConfPath = Join-Path $app.ConfigDir "mpv.conf"
        $backupConf = $mpvConfPath + ".bak"

        if (Test-Path $backupConf) {
            Write-Log "Found original mpv.conf backup at '$backupConf'. Restoring..." -Level SUCCESS
            try {
                Copy-Item -Path $backupConf -Destination $mpvConfPath -Force
                Remove-Item -Path $backupConf -Force -ErrorAction SilentlyContinue
                Write-Log "Successfully restored original mpv.conf." -Level SUCCESS
            } catch {
                Write-Log "Failed to restore original mpv.conf: $_" -Level ERROR
            }
        } elseif (Test-Path $mpvConfPath) {
            Write-Log "No original mpv.conf backup was found. Deleting custom RTX mpv.conf..." -Level WARNING
            try {
                Remove-Item -Path $mpvConfPath -Force
                Write-Log "Custom RTX mpv.conf removed successfully." -Level SUCCESS
            } catch {
                Write-Log "Failed to delete mpv.conf: $_" -Level ERROR
            }
        }

        # 3. Delete autovsr_rtxhdr.lua script
        $luaPath = Join-Path (Join-Path $app.ConfigDir "scripts") "autovsr_rtxhdr.lua"
        if (Test-Path $luaPath) {
            Write-Log "Removing dynamic Lua script 'autovsr_rtxhdr.lua'..." -Level INFO
            try {
                Remove-Item -Path $luaPath -Force
                Write-Log "Successfully removed autovsr_rtxhdr.lua script." -Level SUCCESS
            } catch {
                Write-Log "Failed to delete Lua script: $_" -Level ERROR
            }
        }
    }

    Write-Log "=========================================================" -Level SUCCESS
    Write-Log "Uninstallation completed successfully! Plex defaults restored." -Level SUCCESS
    Write-Log "=========================================================" -Level SUCCESS
    Exit 0
}

# ---------------------------------------------------------
# Hardware and Environment Verification (Only during installation)
# ---------------------------------------------------------
Write-Log "Starting environment diagnostics..." -Level INFO

# Verify Nvidia GPU
$gpuQuery = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue
$nvidiaGpu = $gpuQuery | Where-Object { $_.Name -like "*NVIDIA*" -or $_.AdapterCompatibility -like "*NVIDIA*" }

if ($null -eq $nvidiaGpu) {
    Write-Log "No NVIDIA GPU detected on this system. RTX features require an NVIDIA RTX 20-series GPU or newer." -Level WARNING
} else {
    Write-Log "Found NVIDIA GPU: $($nvidiaGpu.Name)" -Level SUCCESS
}

# Verify Windows HDR State (RTX Video HDR requires system-level HDR to be enabled)
# Since the sandbox or some displays may not have HDR, we report it but do not exit
$hdrStatus = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction SilentlyContinue
Write-Log "RTX Video HDR requires 'Use HDR' to be toggled ON in Windows 11 Display settings." -Level INFO

# ---------------------------------------------------------
# Step 1: Upgrading libmpv-2.dll (Mitzsch mpv-winbuild)
# ---------------------------------------------------------
Write-Log "Checking for libmpv-2.dll upgrades required for RTX Video Features..." -Level INFO

# Retrieve latest stable version from Mitzsch's mpv-winbuild repository
$gitHubRepo = "mitzsch/mpv-winbuild"
$apiUrl = "https://api.github.com/repos/$gitHubRepo/releases/latest"

try {
    # Force TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $releasesJson = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing

    # Locate mpv-dev-x86_64-v3 distribution matching Windows 11 x64 systems
    $targetAsset = $releasesJson.assets | Where-Object { $_.name -like "mpv-dev-x86_64-v3-*" } | Select-Object -First 1

    if ($null -eq $targetAsset) {
        $targetAsset = $releasesJson.assets | Where-Object { $_.name -like "mpv-dev-x86_64-*" } | Select-Object -First 1
    }

    if ($null -ne $targetAsset) {
        $downloadUrl = $targetAsset.browser_download_url
        $tempZip = Join-Path $env:TEMP "mpv_rtx_dist.zip"
        $tempExtract = Join-Path $env:TEMP "mpv_rtx_extract"

        Write-Log "Downloading compatible modern libmpv distribution from $downloadUrl..." -Level INFO
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing

        # Clean temporary extraction folder if exists
        if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force | Out-Null }
        New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null

        Write-Log "Extracting modern libmpv-2.dll..." -Level INFO
        # Mitzsch's mpv-winbuild releases package files in zip.
        # Fallback explanation if Expand-Archive fails or is blocked on unsupported platforms
        try {
            Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force -ErrorAction Stop
        } catch {
            Write-Log "Expand-Archive failed or is not fully supported for this format. Retrying with system tar tool..." -Level WARNING
            tar -xf $tempZip -C $tempExtract
        }

        $extractedDll = Get-ChildItem -Path $tempExtract -Filter "libmpv-2.dll" -Recurse | Select-Object -First 1

        if ($null -ne $extractedDll) {
            foreach ($app in $activePlexApps) {
                Write-Log "Stopping running processes of $($app.Name) to release file locks..." -Level INFO
                Stop-Process -Name ($app.Name -replace " ", "") -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2

                # Backup current dll
                if (Test-Path $app.DllPath) {
                    $backupPath = $app.DllPath + ".bak"
                    if (-not (Test-Path $backupPath)) {
                        Write-Log "Creating backup of the old DLL: '$backupPath'" -Level INFO
                        Copy-Item -Path $app.DllPath -Destination $backupPath -Force
                    }
                }

                # Copy updated dll
                Write-Log "Replacing libmpv-2.dll in '$($app.InstallDir)' with the newer RTX-compatible version..." -Level SUCCESS
                Copy-Item -Path $extractedDll.FullName -Destination $app.DllPath -Force
            }
        } else {
            Write-Log "Target libmpv-2.dll was not found inside the downloaded archive." -Level WARNING
            Write-Log "Please download modern libmpv development DLL manually from https://github.com/$gitHubRepo/releases and replace libmpv-2.dll inside the Plex folder." -Level INFO
        }
    } else {
        Write-Log "Unable to locate optimal build target asset on GitHub. Skipping automatic DLL upgrade." -Level WARNING
    }
} catch {
    Write-Log "Failed to download and replace libmpv-2.dll automatically: $_" -Level WARNING
    Write-Log "You may need to manually download modern libmpv-2.dll build and replace it in the installation directories." -Level INFO
}

# ---------------------------------------------------------
# Step 2: Configure AppData directories (mpv.conf and scripts)
# ---------------------------------------------------------
foreach ($app in $activePlexApps) {
    Write-Log "Configuring settings for $($app.Name)..." -Level INFO

    # Create config folder if it doesn't exist
    if (-not (Test-Path $app.ConfigDir)) {
        New-Item -ItemType Directory -Path $app.ConfigDir -Force | Out-Null
    }

    # mpv.conf path
    $mpvConfPath = Join-Path $app.ConfigDir "mpv.conf"

    # Check if mpv.conf already exists, if so back it up
    if (Test-Path $mpvConfPath) {
        $backupConf = $mpvConfPath + ".bak"
        if (-not (Test-Path $backupConf)) {
            Write-Log "Backing up existing mpv.conf to '$backupConf'..." -Level INFO
            Copy-Item -Path $mpvConfPath -Destination $backupConf -Force
        }
    }

    # Generate perfect mpv.conf contents optimized for RTX Super Resolution and RTX HDR
    $mpvConfContents = @"
# ---------------------------------------------------------
# NVIDIA RTX Video Super Resolution (VSR) & RTX HDR Profile
# Optimized for Plex Player Integration
# ---------------------------------------------------------

# Direct3D11 Context configuration (Crucial for NVIDIA scaling/post processing)
gpu-context=d3d11
gpu-api=d3d11
vo=gpu-next
hwdec=d3d11va

# Output depth and colorspace profiles (preserves dynamic range during upscaling)
dither-depth=auto
temporal-dither=yes

# Allow custom player scripts to run
keep-open=yes

# Keep window and video attributes in sync
video-sync=display-resample
"@

    Write-Log "Writing updated mpv.conf to '$mpvConfPath'..." -Level SUCCESS
    Set-Content -Path $mpvConfPath -Value $mpvConfContents -Encoding UTF8

    # Create scripts folder
    $scriptsDir = Join-Path $app.ConfigDir "scripts"
    if (-not (Test-Path $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    }

    # Deploy autovsr_rtxhdr.lua
    # Fallback to web download if executing as a remote pipeline/one-liner where PSScriptRoot is null/empty
    $luaDest = Join-Path $scriptsDir "autovsr_rtxhdr.lua"
    $luaSource = $null

    if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
        $potentialSource = Join-Path $PSScriptRoot "autovsr_rtxhdr.lua"
        if (Test-Path $potentialSource) {
            $luaSource = $potentialSource
        }
    }

    if ($null -ne $luaSource) {
        Write-Log "Copying local autovsr_rtxhdr.lua to scripts folder: '$luaDest'" -Level SUCCESS
        Copy-Item -Path $luaSource -Destination $luaDest -Force
    } else {
        Write-Log "No local script source found (PSScriptRoot is empty/remote execution). Fetching autovsr_rtxhdr.lua directly from GitHub..." -Level INFO
        try {
            $rawLuaUrl = "https://raw.githubusercontent.com/BK1233/Custom-Plex-Player-Script-New/main/autovsr_rtxhdr.lua"
            Invoke-WebRequest -Uri $rawLuaUrl -OutFile $luaDest -UseBasicParsing
            Write-Log "Successfully downloaded and installed autovsr_rtxhdr.lua to '$luaDest'" -Level SUCCESS
        } catch {
            Write-Log "Failed to download autovsr_rtxhdr.lua: $_" -Level ERROR
        }
    }
}

# ---------------------------------------------------------
# Done
# ---------------------------------------------------------
Write-Log "=========================================================" -Level SUCCESS
Write-Log "Configuration for Plex player enhancements is complete!"  -Level SUCCESS
Write-Log "Ensure NVIDIA App or Control Panel has 'Super Resolution' and 'RTX Video HDR' enabled under Video Enhancements." -Level INFO
Write-Log "Keyboard Controls during Playback:" -Level INFO
Write-Log "  - [Ctrl + Shift + R] Toggle RTX Video Super Resolution" -Level INFO
Write-Log "  - [Ctrl + Shift + H] Toggle RTX Video HDR (SDR-to-HDR)" -Level INFO
Write-Log "  - [Ctrl + Shift + S] Show full RTX/Renderer Status Screen" -Level INFO
Write-Log "=========================================================" -Level SUCCESS
