<#
.SYNOPSIS
    Installer script for Algorithmic Trading Challenges on VPS

.AUTHOR
    Sheridan Wendt

.DESCRIPTION
    Downloads and installs MT5, Ox Securities MT5, Orbtl, Experts and configs for each Challenge instance.
    Supports multiple Challenge installs, with cloning for MT5/Ox to avoid overwrites.
    Runs silent installs for first instances; clones for subsequent instances.
    Updates Experts in all users' MetaQuotes folders (both instance folders and roaming profiles).
    Launches each MT5 and Ox instance sequentially on the same desktop with delays.

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
            Log "Download failed on attempt $i $($_.Exception.Message)"
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

    # Get all user MetaQuotes Terminal folders under roaming profiles
    $terminalRoot = "C:\Users"
    $allTerminals = Get-ChildItem -Path $terminalRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $metaQuotes = Join-Path $_.FullName "AppData\Roaming\MetaQuotes\Terminal"
        if (Test-Path $metaQuotes) {
            Get-ChildItem -Path $metaQuotes -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $_.FullName
            }
        }
    } | Where-Object { $_ -ne $null }

    # Also find Experts folders inside each installed MT5 and Ox instance (for current machine)
    $instanceDirs = Get-ChildItem -Path "C:\Program Files" -Directory -ErrorAction SilentlyContinue | Where-Object { 
        $_.Name -like "MetaTrader 5*" -or $_.Name -like "Ox Securities MetaTrader 5*"
    } | Select-Object -ExpandProperty FullName

    $allExpertFolders = @()

    foreach ($terminal in $allTerminals) {
        $expertDir = Join-Path $terminal "MQL5\Experts"
        if (Test-Path $expertDir) {
            $allExpertFolders += $expertDir
        }
    }

    foreach ($instanceDir in $instanceDirs) {
        $expertDir = Join-Path $instanceDir "MQL5\Experts"
        if (Test-Path $expertDir) {
            $allExpertFolders += $expertDir
        }
    }

    $allExpertFolders = $allExpertFolders | Select-Object -Unique

    foreach ($expertDir in $allExpertFolders) {
        foreach ($expert in $experts) {
            try {
                $sourceFile = Join-Path $tempDir $expert.Name
                $destFile = Join-Path $expertDir $expert.Name
                Copy-Item -Path $sourceFile -Destination $destFile -Force
                Log "Updated expert $($expert.Name) at $expertDir"
            }
            catch {
                Log "Failed to update expert $($expert.Name) at $expertDir $($_.Exception.Message)"
            }
        }
    }
}

function Launch-Instances {
    param (
        [int]$TotalChallenges,
        [string]$BaseMT5Path = "C:\Program Files\MetaTrader 5",
        [string]$BaseOxPath = "C:\Program Files\Ox Securities MetaTrader 5"
    )

    function Get-MT5ExePath($instanceNum) {
        $path = if ($instanceNum -eq 1) { $BaseMT5Path } else { "$BaseMT5Path $instanceNum" }
        return Join-Path $path "terminal64.exe"
    }

    function Get-OxExePath($instanceNum) {
        $path = if ($instanceNum -eq 1) { $BaseOxPath } else { "$BaseOxPath $instanceNum" }
        return Join-Path $path "terminal64.exe"
    }

    Log "Launching first MT5 and Ox instances..."

    # Launch first MT5 and Ox instance, wait 30s
    if (Test-Path (Get-MT5ExePath 1)) {
        Start-Process -FilePath (Get-MT5ExePath 1) -ArgumentList "/portable"
        Log "Started MT5 instance 1"
    }
    else { Log "MT5 instance 1 executable not found." }

    if (Test-Path (Get-OxExePath 1)) {
        Start-Process -FilePath (Get-OxExePath 1) -ArgumentList "/portable"
        Log "Started Ox instance 1"
    }
    else { Log "Ox instance 1 executable not found." }

    Start-Sleep -Seconds 30

    # Launch remaining instances one by one with 30s delay each
    for ($i = 2; $i -le $TotalChallenges; $i++) {
        if (Test-Path (Get-MT5ExePath $i)) {
            Start-Process -FilePath (Get-MT5ExePath $i) -ArgumentList "/portable"
            Log "Started MT5 instance $i"
        }
        else { Log "MT5 instance $i executable not found." }

        if (Test-Path (Get-OxExePath $i)) {
            Start-Process -FilePath (Get-OxExePath $i) -ArgumentList "/portable"
            Log "Started Ox instance $i"
        }
        else { Log "Ox instance $i executable not found." }

        Start-Sleep -Seconds 30
    }
}

function Main {
    try {
        if ($TotalChallenges -eq 0) {
            $TotalChallenges = Read-Host "Enter total number of Challenges you want running on this VPS (e.g. 3)"
            $parsedValue = 0
            if (-not [int]::TryParse($TotalChallenges, [ref]$parsedValue)) {
                throw "Invalid number entered."
            }
            $TotalChallenges = $parsedValue
            if ($TotalChallenges -lt 1 -or $TotalChallenges -gt 10) {
                throw "Please enter a number between 1 and 10."
            }
        }

        Log "Starting installation for $TotalChallenges Challenges..."

        $downloadDir = Join-Path $env:TEMP "AlgorithmicTradingInstallers"
        if (-not (Test-Path $downloadDir)) { New-Item -ItemType Directory -Path $downloadDir | Out-Null }

        $mt5InstallerPath = Join-Path $downloadDir "mt5setup.exe"
        $oxInstallerPath = Join-Path $downloadDir "oxsecurities5setup.exe"

        $mt5InstallerUrl = "https://github.com/sheridanwendt/Algorithmic-Trading/raw/refs/heads/main/installers/mt5setup.exe"
        $oxInstallerUrl = "https://github.com/sheridanwendt/Algorithmic-Trading/raw/refs/heads/main/installers/oxsecurities5setup.exe"

        # Always redownload installers for latest
        Log "Downloading MT5 installer..."
        if (-not (Download-File -Url $mt5InstallerUrl -DestinationPath $mt5InstallerPath)) {
            throw "Failed to download MT5 installer."
        }
        if ((Get-Item $mt5InstallerPath).Length -lt 1MB) {
            throw "MT5 installer file size suspiciously small after download."
        }
        Log "✅ Successful Download of MT5 installer."

        Log "Downloading Ox installer..."
        if (-not (Download-File -Url $oxInstallerUrl -DestinationPath $oxInstallerPath)) {
            throw "Failed to download Ox installer."
        }
        if ((Get-Item $oxInstallerPath).Length -lt 1MB) {
            throw "Ox installer file size suspiciously small after download."
        }
        Log "✅ Successful Download of Ox installer."

        Log "Opening File Explorer to C:\Program Files"
        Start-Process "explorer.exe" -ArgumentList "C:\Program Files"

        for ($i = 1; $i -le $TotalChallenges; $i++) {
            Log "Processing Challenge $i..."
            Install-MT5Instance -ChallengeNum $i -InstallerPath $mt5InstallerPath
            Install-OxInstance -ChallengeNum $i -InstallerPath $oxInstallerPath
            # Orbtl and config downloads skipped as requested
        }

        Launch-Instances -TotalChallenges $TotalChallenges

        Update-Experts

        Log "Installation and setup complete."
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
