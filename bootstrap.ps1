param (
    [Parameter(Mandatory=$true)]
    [string[]]$Challenges,

    [switch]$DebugMode
)

$repoBase = "https://raw.githubusercontent.com/sheridanwendt/Algorithmic-Trading/main"
$versionsUrl = "$repoBase/versions.json"
$coreScriptUrl = "$repoBase/installer_core.ps1"
$tempCore = "$env:TEMP\installer_core.ps1"

try {
    $versions = Invoke-RestMethod -Uri $versionsUrl -UseBasicParsing
} catch {
    Write-Error "Unable to fetch versions.json"
    exit 1
}

$coreHashRemote = $versions.installer.sha256
$coreHashLocal = if (Test-Path $tempCore) { (Get-FileHash -Algorithm SHA256 $tempCore).Hash.ToLower() } else { "" }

if ($coreHashRemote -ne $coreHashLocal) {
    Write-Host "Downloading latest installer_core.ps1..."
    Invoke-WebRequest -Uri $coreScriptUrl -OutFile $tempCore -UseBasicParsing
    if ((Get-FileHash -Algorithm SHA256 $tempCore).Hash.ToLower() -ne $coreHashRemote) {
        Write-Error "Downloaded installer core hash mismatch. Aborting."
        exit 1
    }
}

$arguments = @("-Challenges", $Challenges)
if ($DebugMode) {
    $arguments += "-DebugMode"
}

& powershell -ExecutionPolicy Bypass -File $tempCore @arguments
Read-Host "Press Enter to exit...
