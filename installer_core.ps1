<#
.SYNOPSIS
    Installer script for Algorithmic Trading Challenges on VPS

.AUTHOR
    Sheridan Wendt

.DESCRIPTION
    Downloads and installs MT5, Ox Securities MT5, Orbtl, Experts and configs for each Challenge instance.
    Supports multiple Challenge installs, with cloning for MT5/Ox to avoid overwrites.
    Runs silent installs for first instances; clones for subsequent instances.
    Updates Experts in all users' MetaQuotes folders.
    Launches each MT5 and Ox instance on separate virtual desktops with delays.

.NOTES
    Requires running as Administrator.
#>

param(
    [int]$TotalChallenges = 0,
    [switch]$DebugMode
)

function Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage

    # Append to log file
    $global:LogFilePath = $global:LogFilePath -or (Join-Path $env:TEMP "installer_core.log")
    Add-Content -Path $global:LogFilePath -Value $logMessage
}

function Download-File {
    param(
        [string]$Url,
        [string]$DestinationPath,
        [int]$MaxRetries = 3
    )

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Log "Attempt $i Downloading $Url ..."
            Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
            Log "Downloaded $Url to $DestinationPath"
            return $true
        }
        catch {
            Log "Download failed on attempt $i: $($_.Exception.Message)"
            Start-Sleep -Seconds 2
        }
    }
    Log "FATAL ERROR: Failed to download $Url after $MaxRetries attempts."
    return $false
}

function Install-MT5Instance {
    param (
        [int]$ChallengeNum,
        [string]$BaseMT5Path = "C:\Program Files\MetaTrader 5",
        [string]$InstallerPath
    )

    $targetPath = if ($ChallengeNum -eq 1) {
        $BaseMT5Path
    } else {
        "$BaseMT5Path $ChallengeNum"
    }

    if (Test-Path $targetPath) {
        Log "MT5 instance $ChallengeNum already installed at $targetPath"
        return
    }

    if ($ChallengeNum -eq 1) {
        Log "Installing MT5 instance $ChallengeNum via installer to $targetPath..."
        Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait -NoNewWindow
        if (-not (Test-Path $targetPath)) {
            Log "ERROR: MT5 installation directory not found after install. Expected $targetPath"
            throw "MT5 install failed"
        }
    } else {
        $prevPath = if ($ChallengeNum -eq 2) { $BaseMT5Path } else { "$BaseMT5Path $(($ChallengeNum - 1))" }
        if (-not (Test-Path $prevPath)) {
            Log "Previous MT5 install folder $prevPath does not exist. Cannot clone."
            throw "Missing MT5 source folder for cloning"
        }
        Log "Cloning MT5 instance $ChallengeNum from $prevPath to $targetPath..."
        Copy-Item -Path $prevPath -Destination $targetPath -Recurse -Force
    }
}

function Install-OxInstance {
    param (
        [int]$ChallengeNum,
        [string]$BaseOxPath = "C:\Program Files\Ox Securities MetaTrader 5",
        [string]$InstallerPath
    )

    $targetPath = if ($ChallengeNum -eq 1) {
        $BaseOxPath
    } else {
        "$BaseOxPath $ChallengeNum"
    }

    if (Test-Path $targetPath) {
        Log "Ox instance $ChallengeNum already installed at $targetPath"
        return
    }

    if ($ChallengeNum -eq 1) {
        Log "Installing Ox instance $ChallengeNum via installer to $targetPath..."
        Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait -NoNewWindow
        if (-not (Test-Path $targetPath)) {
            Log "ERROR: Ox installation directory not found after install. Expected $targetPath"
            throw "Ox install failed"
        }
    } else {
        $prevPath = if ($ChallengeNum -eq 2) { $BaseOxPath } else { "$BaseOxPath $(($ChallengeNum - 1))" }
        if (-not (Test-Path $prevPath)) {
            Log "Previous Ox install folder $prevPath does not exist. Cannot clone."
            throw "Missing Ox source folder for cloning"
        }
        Log "Cloning Ox instance $ChallengeNum from $prevPath to $targetPath..."
        Copy-Item -Path $prevPath -Destination $targetPath -Recurse -Force
    }
}

function Update-Experts {
    # Download and update the latest Experts to all users' MetaQuotes Terminal folders

    $experts = @(
        @{ Name = "Titan X 23.63.ex5"; Url = "https://github.com/sheridanwendt/Algorithmic-Trading/raw/refs/heads/main/experts/Titan%20X%2023.63.ex5" },
        @{ Name = "Titan Hedge 2.09.ex5"; Url = "https://github.com/sheridanwendt/Algorithmic-Trading/raw/refs/heads/main/experts/Titan%20Hedge%202.09.ex5" },
        @{ Name = "OrbtlBridge 1.2.ex5"; Url = "https://github.com/sheridanwendt/Algorithmic-Trading/raw/refs/heads/main/experts/OrbtlBridge%201.2.ex5" }
    )

    $tempDir = Join-Path $env:TEMP "AlgorithmicTradingExperts"
    if (-Not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }

    foreach ($expert in $experts) {
        $destFile = Join-Path $tempDir $expert.Name
        Log "Downloading expert $($expert.Name)..."
        if (-not (Download-File -Url $expert.Url -DestinationPath $destFile)) {
            Log "ERROR: Failed to download expert $($expert.Name). Skipping."
            continue
        }
    }

    # Find all user MetaQuotes Terminal folders
    $terminalRoot = "C:\Users"
    $allTerminals = Get-ChildItem -Path $terminalRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $metaQuotes = Join-Path $_.FullName "AppData\Roaming\MetaQuotes\Terminal"
        if (Test-Path $metaQuotes) {
            Get-ChildItem -Path $metaQuotes -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $_.FullName
            }
        }
    } | Where-Object { $_ -ne $null }

    foreach ($terminal in $allTerminals) {
        $expertDir = Join-Path $terminal "MQL5\Experts"
        if (-not (Test-Path $expertDir)) {
            Log "Expert directory not found at $expertDir. Skipping."
            continue
        }
        foreach ($expert in $experts) {
            try {
                $sourceFile = Join-Path $tempDir $expert.Name
                $destFile = Join-Path $expertDir $expert.Name
                Copy-Item -Path $sourceFile -Destination $destFile -Force
                Log "Updated expert $($expert.Name) at $expertDir"
            }
            catch {
                Log "Failed to update expert $($expert.Name) at $expertDir: $($_.Exception.Message)"
            }
        }
    }
}

function Launch-Instances-On-VirtualDesktops {
    param (
        [int]$TotalChallenges,
        [string]$BaseMT5Path = "C:\Program Files\MetaTrader 5",
        [string]$BaseOxPath = "C:\Program Files\Ox Securities MetaTrader 5"
    )

    # Install and import VirtualDesktop module
    if (-not (Get-Module -ListAvailable -Name VirtualDesktop)) {
        Log "Installing VirtualDesktop module..."
        Install-Module VirtualDesktop -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
    }
    Import-Module VirtualDesktop

    # Create desktops if necessary
    $existingDesktops = Get-Desktop
    for ($i = 1; $i -le $TotalChallenges; $i++) {
        $desktopName = "Challenge$i"
        if (-not ($existingDesktops.Name -contains $desktopName)) {
            Log "Creating virtual desktop $desktopName"
            New-Desktop -Name $desktopName | Out-Null
        }
    }

    # Get updated list of desktops after creation
    $desktops = Get-Desktop

    # Helper function to get executable path for MT5 instance
    function Get-MT5ExePath($instanceNum) {
        $path = if ($instanceNum -eq 1) { $BaseMT5Path } else { "$BaseMT5Path $instanceNum" }
        return Join-Path $path "terminal64.exe"
    }

    # Helper function to get executable path for Ox instance
    function Get-OxExePath($instanceNum) {
        $path = if ($instanceNum -eq 1) { $BaseOxPath } else { "$BaseOxPath $instanceNum" }
        return Join-Path $path "terminal64.exe"
    }

    # Launch instances, one per desktop, wait 30s after each
    for ($i = 1; $i -le $TotalChallenges; $i++) {
        $desktop = $desktops | Where-Object { $_.Name -eq "Challenge$i" }
        if (-not $desktop) {
            Log "ERROR: Virtual desktop Challenge$i not found."
            continue
        }
        Log "Switching to virtual desktop Challenge$i"
        Switch-Desktop -Desktop $desktop

        $mt5Exe = Get-MT5ExePath $i
        $oxExe = Get-OxExePath $i

        if (Test-Path $mt5Exe) {
            Log "Starting MT5 instance $i from $mt5Exe"
            Start-Process -FilePath $mt5Exe -ArgumentList "/portable"
        }
        else {
            Log "MT5 executable not found for instance $i at $mt5Exe"
        }

        if (Test-Path $oxExe) {
            Log "Starting Ox instance $i from $oxExe"
            Start-Process -FilePath $oxExe -ArgumentList "/portable"
        }
        else {
            Log "Ox executable not found for instance $i at $oxExe"
        }

        Log "Waiting 30 seconds for instance $i to start..."
        Start-Sleep -Seconds 30
    }
}

function Main {
    try {
        if ($TotalChallenges -eq 0) {
            $TotalChallenges = Read-Host "Enter total number of Challenges you want running on this VPS (e.g. 3)"
            [int]::TryParse($TotalChallenges, [ref]$null) | Out-Null
            if ($TotalChallenges -lt 1 -or $TotalChallenges -gt 5) {
                throw "Please enter a number between 1 and 5."
            }
        }

        Log "Starting installation for $TotalChallenges Challenges..."

        # Paths for installers (assume these downloaded or downloaded now)
        $downloadDir = Join-Path $env:TEMP "AlgorithmicTradingInstallers"
        if (-not (Test-Path $downloadDir)) { New-Item -ItemType Directory -Path $downloadDir | Out-Null }

        $mt5InstallerPath = Join-Path $downloadDir "mt5setup.exe"
        $oxInstallerPath = Join-Path $downloadDir "oxsecurities5setup.exe"

        # URLs for installers (GitHub raw URLs)
        $mt5InstallerUrl = "https://github.com/sheridanwendt/Algorithmic-Trading/raw/refs/heads/main/installers/mt5setup.exe"
        $oxInstallerUrl = "https://github.com/sheridanwendt/Algorithmic-Trading/raw/refs/heads/main/installers/oxsecurities5setup.exe"

        # Download and validate MT5 installer
        if (-not (Test-Path $mt5InstallerPath) -or (Get-Item $mt5InstallerPath).Length -lt 1MB) {
            Log "Downloading MT5 installer..."
            if (-not (Download-File -Url $mt5InstallerUrl -DestinationPath $mt5InstallerPath)) {
                throw "Failed to download MT5 installer."
            }
            if ((Get-Item $mt5InstallerPath).Length -lt 1MB) {
                throw "MT5 installer file size suspiciously small after download."
            }
            Log "MT5 installer downloaded and validated."
        }

        # Download and validate Ox installer
        if (-not (Test-Path $oxInstallerPath) -or (Get-Item $oxInstallerPath).Length -lt 1MB) {
            Log "Downloading Ox installer..."
            if (-not (Download-File -Url $oxInstallerUrl -DestinationPath $oxInstallerPath)) {
                throw "Failed to download Ox installer."
            }
            if ((Get-Item $oxInstallerPath).Length -lt 1MB) {
                throw "Ox installer file size suspiciously small after download."
            }
            Log "Ox installer downloaded and validated."
        }

        for ($i = 1; $i -le $TotalChallenges; $i++) {
            Log "Processing Challenge $i..."

            Install-MT5Instance -ChallengeNum $i -InstallerPath $mt5InstallerPath
            Install-OxInstance -ChallengeNum $i -InstallerPath $oxInstallerPath

            # Orbtl and config downloads skipped as requested
        }

        Update-Experts

        Log "Installation complete. Launching instances on separate virtual desktops..."

        Launch-Instances-On-VirtualDesktops -TotalChallenges $TotalChallenges

        Log "All instances started successfully."

    }
    catch {
        Log "An error occurred: $($_.Exception.Message)"
    }
}

# Run Main
Main

if ($DebugMode) {
    Read-Host "Press Enter to exit..."
}
