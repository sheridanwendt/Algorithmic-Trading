param (
    [Parameter(Mandatory=$true)]
    [string[]]$Challenges
)

$repoBase = "https://raw.githubusercontent.com/sheridanwendt/Algorithmic-Trading/main"
$versionsFile = "$repoBase/versions.json"
$maxRetries = 3
$retryDelay = 2

Write-Host "=== Algorithmic Trading Challenge Installer (Hardened Core) ===" -ForegroundColor Cyan

# --- RELAUNCH ON FAILURE ---
$scriptPath = $MyInvocation.MyCommand.Definition
if ($env:INSTALLER_RETRY -ne "1") {
    trap {
        Write-Warning "Script failed. Attempting auto-relaunch..."
        $env:INSTALLER_RETRY = "1"
        & powershell -ExecutionPolicy Bypass -File $scriptPath -Challenges $Challenges
        exit
    }
}

# --- REQUIRE ADMIN ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltinRole] "Administrator")) {
    Write-Error "Please run this script as Administrator."
    exit 1
}

# --- DOWNLOAD WITH RETRY & CHECKSUM ---
function Download-File($url, $destination, $expectedHash) {
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing
            if (Test-Checksum $destination $expectedHash) {
                Write-Host "Downloaded & verified: $url"
                return $true
            } else {
                Write-Warning "Checksum mismatch for $destination (Attempt $i)"
                Remove-Item $destination -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warning "Download failed for $url (Attempt $i)"
        }
        Start-Sleep -Seconds ($retryDelay * $i)
    }
    Write-Error "Failed to download $url after $maxRetries attempts."
    return $false
}

# --- CHECKSUM TEST ---
function Test-Checksum($filePath, $expectedHash) {
    if (-not (Test-Path $filePath)) { return $false }
    $actualHash = (Get-FileHash -Algorithm SHA256 $filePath).Hash.ToLower()
    return ($actualHash -eq $expectedHash.ToLower())
}

# --- PREREQUISITE CHECK ---
function Ensure-Prerequisite($name, $checkCommand, $downloadUrl, $expectedHash, $installerArgs) {
    if (-not (& $checkCommand)) {
        Write-Host "Installing prerequisite: $name..." -ForegroundColor Yellow
        $tempFile = "$env:TEMP\$name.exe"
        if (Download-File $downloadUrl $tempFile $expectedHash) {
            Start-Process -FilePath $tempFile -ArgumentList $installerArgs -Wait -NoNewWindow
        } else {
            Write-Error "Failed to install prerequisite: $name"
            exit 1
        }
    } else {
        Write-Host "$name already installed."
    }
}

# --- FETCH VERSIONS ---
try {
    $versions = Invoke-RestMethod -Uri $versionsFile -UseBasicParsing
} catch {
    Write-Error "Cannot fetch versions.json from repo"
    exit 1
}

# --- PREREQUISITES ---
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
            $sourceUrl = "$repoBase/experts/$fileName"
            $destFile = Join-Path $folder.FullName $fileName

            if (-not (Test-Checksum $destFile $hash)) {
                Write-Host "Updating Expert: $fileName in $($folder.FullName)"
                Download-File $sourceUrl $destFile $hash | Out-Null
            }
        }
    }
}

# --- INSTALL CHALLENGE ---
function Install-Challenge($num) {
    Write-Host "`n--- Installing Challenge $num ---" -ForegroundColor Green

    $mt5Path = "C:\Program Files\MetaTrader 5" + $(if ($num -gt 1) { " $num" } else { "" })
    $oxPath = "C:\Program Files\Ox Securities MetaTrader 5" + $(if ($num -gt 1) { " $num" } else { "" })
    $orbtlPath = "C:\Program Files\Orbtl"

    $apps = $versions.apps

    # MT5
    $mt5Exe = Join-Path $mt5Path "terminal64.exe"
    if (-not (Test-Checksum $mt5Exe $apps.mt5.sha256)) {
        if (Download-File $apps.mt5.url "$env:TEMP\mt5_$num.exe" $apps.mt5.sha256) {
            Start-Process "$env:TEMP\mt5_$num.exe" "/S /D=$mt5Path" -Wait
        } else {
            Write-Error "Failed to install MT5 for Challenge $num"
            exit 1
        }
    }

    # Ox
    $oxExe = Join-Path $oxPath "terminal64.exe"
    if (-not (Test-Checksum $oxExe $apps.ox.sha256)) {
        if (Download-File $apps.ox.url "$env:TEMP\ox_$num.exe" $apps.ox.sha256) {
            Start-Process "$env:TEMP\ox_$num.exe" "/S /D=$oxPath" -Wait
        } else {
            Write-Error "Failed to install Ox for Challenge $num"
            exit 1
        }
    }

    # Orbtl
    $orbtlExe = Join-Path $orbtlPath "orbtl.exe"
    if (-not (Test-Checksum $orbtlExe $apps.orbtl.sha256)) {
        if (Download-File $apps.orbtl.url "$env:TEMP\orbtl.exe" $apps.orbtl.sha256) {
            Start-Process "$env:TEMP\orbtl.exe" "/S /D=$orbtlPath" -Wait
        } else {
            Write-Error "Failed to install Orbtl"
            exit 1
        }
    }

    # Configs
    $configZip = "$env:TEMP\challenge${num}_config.zip"
    if (Download-File "$repoBase/configs/challenge${num}.zip" $configZip $versions.configs["challenge$num"].sha256) {
        Expand-Archive -Path $configZip -DestinationPath $mt5Path -Force
    } else {
        Write-Error "Failed to download config for Challenge $num"
        exit 1
    }
}

# --- MAIN ---
foreach ($challenge in $Challenges) {
    Install-Challenge $challenge
}

Update-Experts $versions.experts

Write-Host "`nAll Challenges installed/updated successfully!" -ForegroundColor Cyan