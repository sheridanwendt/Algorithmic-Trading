@echo off
setlocal

REM Define temp path for the script
set SCRIPT_PATH=%TEMP%\bootstrap.ps1

REM Download bootstrap.ps1 from GitHub
powershell -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/sheridanwendt/Algorithmic-Trading/refs/heads/main/bootstrap.ps1' -OutFile '%SCRIPT_PATH%' -UseBasicParsing"

REM Run the script with parameters, keep window open after execution
powershell -NoExit -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -Challenges 1,2,3 -DebugMode

REM Pause so window stays open after script completes
pause

endlocal
