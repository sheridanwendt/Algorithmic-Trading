param (
    [Parameter(Mandatory=$true)]
    [string[]]$Challenges,

    [switch]$DebugMode
)

$logFile = "$env:TEMP\challenge_install.log"

function Log-Write {
    param ([string]$msg)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$timestamp] $msg"
    Add-Content -Path $logFile -Value $entry
    if ($DebugMode) { Write-Host $entry }
}

# Wrapper to run commands with error capture
function Run-WithLogging([scriptblock]$scriptblock, [string]$context) {
    try {
        & $scriptblock
        Log-Write "SUCCESS: $context"
    } catch {
        Log-Write "ERROR: $context - $_"
        throw $_
    }
}

# Trap for unexpected errors
trap {
    Log-Write "FATAL ERROR: $_"
    Write-Host "An error occurred. Please check the log file at $logFile" -ForegroundColor Red
    # Prevent console from closing automatically
    if ($Host.Name -eq 'ConsoleHost') { Read-Host "Press Enter to exit..." }
    exit 1
}

Log-Write "Starting install process..."

# Require admin check
Run-WithLogging {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
        [Security.Principal.WindowsBuiltinRole] "Administrator")) {
        throw "Script must be run as Administrator."
    }
} "Admin rights verification"

# --- DOWNLOAD WITH RETRY & CHECKSUM ---
function Download-File($url, $destination, $expectedHash) {
    $maxRetries = 3
    $retryDelay = 2
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            Log-Write "Downloading $url to $destination (Attempt $i)"
            Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing -ErrorAction Stop
            if ((Get-FileHash -Algorithm SHA256 $destination).Hash.ToLower() -eq $expectedHash.ToLower()) {
                Log-Write "Checksum verified for $destination"
                return $true
            } else {
                Log-Write "Checksum mismatch for $destination"
                Remove-Item $destination -ErrorAction SilentlyContinue
            }
        } catch {
            Log-Write "Download error: $_"
        }
        Start-Sleep -Seconds ( $retryDelay * $i )
    }
    throw "Failed to download $url after $maxRetries attempts."
}

# --- PREREQUISITE CHECK ---
function Ensure-Prerequisite($name, $checkCommand, $downloadUrl, $expectedHash, $installerArgs) {
    Run-WithLogging {
        if (-not (& $checkCommand)) {
            Log-Write "Installing prerequisite: $name..."
            $tempFile = "$env:TEMP\$name.exe"
            if (Download-File $downloadUrl $tempFile $expectedHash) {
                Start-Process -FilePath $tempFile -ArgumentList $installerArgs -Wait -NoNewWindow
            } else {
                throw "Failed to install prerequisite: $name"
            }
        } else {
            Log-Write "$name already installed."
        }
    } "Prerequisite check/install: $name"
}

# --- FETCH VERSIONS ---
try {
    $versionsFile = "https://raw.githubusercontent.com/sheridanwendt/Algorithmic-Trading/main/versions.json"
    $versions = Invoke-RestMethod -Uri $versionsFile -UseBasicParsing
    Log-Write "Fetched versions.json"
} catch {
    Log-Write "Cannot fetch versions.json from repo: $_"
    throw $_
}

# Check and install prerequisites
Ensure-Prerequisite "VC++_x64" {
    Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64 -ErrorAction SilentlyContinue
} $versions.prereqs.vc.url $versions.prereqs.vc.sha256 "/install /quiet /norestart"

Ensure-Prerequisite ".NET_Desktop_Runtime" {
    Get-Command "dotnet" -ErrorAction SilentlyContinue
} $versions.prereqs.dotnet.url $versions.prereqs.dotnet.sha256 "/install /quiet /norestart"

# --- UPDATE EXPERTS ---
function Update-Experts($experts) {
    $expertFolders = Get-ChildItem "C:\Users\*\AppData\Roaming\MetaQuotes\Terminal\*\MQL5\Experts" -Directory -ErrorAction SilentlyContinue
    foreach ($folder in $expertFolders) {
        foreach ($expertName in $experts.Keys) {
            $ver = $experts[$expertName].version
            $hash = $experts[$expertName].sha256
            $fileName = "$expertName $ver.ex5"
            $sourceUrl = "https://raw.githubusercontent.com/sheridanwendt/Algorithmic-Trading/main/experts/$fileName"
            $destFile = Join-Path $folder.FullName $fileName

            if (-not (Test-Path $destFile) -or (Get-FileHash -Algorithm SHA256 $destFile).Hash.ToLower() -ne $hash.ToLower()) {
                Log-Write "Updating Expert: $fileName in $($folder.FullName)"
                Download-File $sourceUrl $destFile $hash | Out-Null
            }
        }
    }
}

# --- INSTALL CHALLENGE ---
function Install-Challenge($num) {
    Log-Write "`n--- Installing Challenge $num ---"

    $mt5Path = "C:\Program Files\MetaTrader 5" + $(if ($num -gt 1) { " $num" } else { "" })
    $oxPath = "C:\Program Files\Ox Securities MetaTrader 5" + $(if ($num -gt 1) { " $num" } else { "" })
    $orbtlPath = "C:\Program Files\Orbtl"

    $apps = $versions.apps

    # MT5
    $mt5Exe = Join-Path $mt5Path "terminal64.exe"
    if (-not (Test-Path $mt5Exe) -or (Get-FileHash -Algorithm SHA256 $mt5Exe).Hash.ToLower() -ne $apps.mt5.sha256.ToLower()) {
        if (Download-File $apps.mt5.url "$env:TEMP\mt5_$num.exe" $apps.mt5.sha256) {
            Start-Process "$env:TEMP\mt5_$num.exe" "/S /D=$mt5Path" -Wait
        } else {
            throw "Failed to install MT5 for Challenge $num"
        }
    } else {
        Log-Write "MT5 already installed and verified for Challenge $num"
    }

    # Ox
    $oxExe = Join-Path $oxPath "terminal64.exe"
    if (-not (Test-Path $oxExe) -or (Get-FileHash -Algorithm SHA256 $oxExe).Hash.ToLower() -ne $apps.ox.sha256.ToLower()) {
        if (Download-File $apps.ox.url "$env:TEMP\ox_$num.exe" $apps.ox.sha256) {
            Start-Process "$env:TEMP\ox_$num.exe" "/S /D=$oxPath" -Wait
        } else {
            throw "Failed to install Ox for Challenge $num"
        }
    } else {
        Log-Write "Ox already installed and verified for Challenge $num"
    }

    # Orbtl
    $orbtlExe = Join-Path $orbtlPath "orbtl.exe"
    if (-not (Test-Path $orbtlExe) -or (Get-FileHash -Algorithm SHA256 $orbtlExe).Hash.ToLower() -ne $apps.orbtl.sha256.ToLower()) {
        if (Download-File $apps.orbtl.url "$env:TEMP\orbtl.exe" $apps.orbtl.sha256) {
            Start-Process "$env:TEMP\orbtl.exe" "/S /D=$orbtlPath" -Wait
        } else {
            throw "Failed to install Orbtl"
        }
    } else {
        Log-Write "Orbtl already installed and verified"
    }

    # Configs
    $configZip = "$env:TEMP\challenge${num}_config.zip"
    if (Download-File "$repoBase/configs/challenge${num}.zip" $configZip $versions.configs["challenge$num"].sha256) {
        Expand-Archive -Path $configZip -DestinationPath $mt5Path -Force
        Log-Write "Extracted config for Challenge $num"
    } else {
        throw "Failed to download config for Challenge $num"
    }
}

# --- MAIN ---
foreach ($challenge in $Challenges) {
    Install-Challenge $challenge
}

Update-Experts $versions.experts

Log-Write "`nAll Challenges installed/updated successfully!"
Write-Host "`nInstallation complete! Log file at: $logFile" -ForegroundColor Green

# Keep console open after completion if run interactively
if ($Host.Name -eq 'ConsoleHost') { Read-Host "Press Enter to exit..." }
