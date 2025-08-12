param (
    [Parameter(Mandatory=$true)]
    [string[]]$Challenges,

    [switch]$DebugMode
)

$repoBase = "https://raw.githubusercontent.com/sheridanwendt/Algorithmic-Trading/main"
$coreScriptUrl = "$repoBase/installer_core.ps1"
$tempCore = "$env:TEMP\installer_core.ps1"

Write-Host "Downloading latest installer_core.ps1..."
Invoke-WebRequest -Uri $coreScriptUrl -OutFile $tempCore -UseBasicParsing

# No checksum verification — proceed directly to run

$arguments = @("-Challenges", $Challenges)
if ($DebugMode) {
    $arguments += "-DebugMode"
}

Write-Host "Running installer_core.ps1..."
& powershell -ExecutionPolicy Bypass -File $tempCore @arguments
Read-Host "Press Enter to exit..."
