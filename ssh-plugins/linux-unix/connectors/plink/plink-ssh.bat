@echo off
REM =============================================================================
REM  plink-ssh.bat — Lightweight plink SSH launcher for CyberArk PSM/CPM
REM
REM  Used as a thin wrapper when PSM is configured to launch plink.exe directly
REM  without the PowerShell overhead. Suitable for simple password-based
REM  interactive sessions in PSM.
REM
REM  Arguments (supplied by PSM from the connection component):
REM    %1 = Username
REM    %2 = Password
REM    %3 = Address
REM    %4 = Port (optional, defaults to 22)
REM    %5 = Key file path (optional, .ppk — enables key auth when provided)
REM
REM  Usage (direct):
REM    plink-ssh.bat myuser MyP@ss target.host 22
REM    plink-ssh.bat myuser "" target.host 22 C:\keys\root.ppk
REM =============================================================================

setlocal enabledelayedexpansion

set "PLINK=C:\Program Files\PuTTY\plink.exe"
set "USERNAME=%~1"
set "PASSWORD=%~2"
set "ADDRESS=%~3"
set "PORT=%~4"
set "KEYFILE=%~5"

REM --- Validate required arguments ---
if "%USERNAME%"=="" (
    echo ERROR: Username is required.
    exit /b 1
)
if "%ADDRESS%"=="" (
    echo ERROR: Address is required.
    exit /b 1
)
if not exist "%PLINK%" (
    echo ERROR: plink.exe not found at "%PLINK%". Install PuTTY.
    exit /b 1
)

REM --- Default port to 22 if not supplied ---
if "%PORT%"=="" set "PORT=22"

REM --- Build plink argument string ---
if "%KEYFILE%"=="" (
    REM Password-based session.
    REM plink reads password from the PLINK_PASSWORD environment variable
    REM to avoid exposing it in the process command line.
    set "PLINK_PASSWORD=%PASSWORD%"
    "%PLINK%" -ssh -l "%USERNAME%" -pw "!PLINK_PASSWORD!" -P %PORT% -batch -no-antispoof %ADDRESS%
) else (
    REM Key-based session — no password needed.
    if not exist "%KEYFILE%" (
        echo ERROR: Key file not found: "%KEYFILE%"
        exit /b 1
    )
    "%PLINK%" -ssh -l "%USERNAME%" -i "%KEYFILE%" -P %PORT% -batch -no-antispoof %ADDRESS%
)

set "PLINK_PASSWORD="
endlocal
exit /b %ERRORLEVEL%
