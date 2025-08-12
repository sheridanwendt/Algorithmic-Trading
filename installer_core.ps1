param (
    [Parameter(Mandatory=$true)]
    [string[]]$Challenges,

    [switch]$Verbose
)

$logFile = "$env:TEMP\challenge_install.log"

function Log-Write {
    param ([string]$msg)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$timestamp] $msg"
    Add-Content -Path $logFile -Value $entry
    if ($Verbose) { Write-Host $entry }
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

# Example: wrapping the Download-File call
function Download-File($url, $destination, $expectedHash) {
    for ($i = 1; $i -le 3; $i++) {
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
        Start-Sleep -Seconds (2 * $i)
    }
    throw "Failed to download $url after 3 attempts."
}

# Continue wrapping other critical sections with Run-WithLogging ...

# At the very end:
Log-Write "Installation completed successfully for Challenges: $($Challenges -join ', ')"
Write-Host "Installation complete! Log file at: $logFile" -ForegroundColor Green

# Keep console open after completion
if ($Host.Name -eq 'ConsoleHost') { Read-Host "Press Enter to exit..." }
