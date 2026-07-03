#Requires -Version 5.1
# =============================================================================
# PSMPlink-UnixSSH.ps1 — PSM Connector: SSH to Linux/Unix via plink.exe
#
# Launched by PSM to open an interactive SSH session to a Linux/Unix target.
# PSM supplies all parameters from the Vault account object; the user never
# sees the credential. The session is automatically recorded by PSM.
#
# Parameters supplied by PSM via PSMPlink-Connection.xml:
#   -Address   — target host IP or FQDN
#   -Port      — SSH port (default 22)
#   -UserName  — account username
#   -Password  — account password (SecureString form after PSM substitution)
#   -SessionId — PSM session ID for audit correlation
#   -KeyFile   — path to .ppk private key file (optional, for key auth)
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]  $Address,
    [Parameter(Mandatory)][string]  $UserName,
    [Parameter(Mandatory)][string]  $Password,
    [string] $Port      = "22",
    [string] $SessionId = "",
    [string] $KeyFile   = "",

    # Path to plink.exe — update if PuTTY is installed elsewhere.
    [string] $PlinkPath = "C:\Program Files\PuTTY\plink.exe"
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Validate plink.exe exists.
# ---------------------------------------------------------------------------
if (-not (Test-Path $PlinkPath)) {
    Write-Error "plink.exe not found at '$PlinkPath'. Install PuTTY or update `$PlinkPath."
    exit 1
}

# ---------------------------------------------------------------------------
# Build plink argument list.
# ---------------------------------------------------------------------------
$plinkArgs = @(
    '-ssh'
    '-l', $UserName
    '-P', $Port
    '-batch'                  # Non-interactive: fail on host-key prompts
    '-no-antispoof'           # Suppress the anti-spoofing prompt
)

if ($KeyFile -ne "") {
    # SSH key authentication — supply .ppk path instead of password.
    if (-not (Test-Path $KeyFile)) {
        Write-Error "Key file not found: $KeyFile"
        exit 1
    }
    $plinkArgs += '-i', $KeyFile
} else {
    # Password authentication — plink reads from PLINK_PASSWORD env var to
    # avoid the password appearing in the process argument list.
    $env:PLINK_PASSWORD = $Password
    $plinkArgs += '-pw', ($env:PLINK_PASSWORD)
}

$plinkArgs += $Address

# ---------------------------------------------------------------------------
# Write session banner to stdout (PSM records this as part of the session).
# ---------------------------------------------------------------------------
Write-Host "=========================================================="
Write-Host " CyberArk Privileged Session — Session ID: $SessionId"
Write-Host " Target : $UserName@${Address}:$Port"
Write-Host " Method : $(if ($KeyFile) { 'SSH Key' } else { 'Password' })"
Write-Host "=========================================================="
Write-Host ""

# ---------------------------------------------------------------------------
# Launch plink — this blocks until the user closes the session.
# PSM wraps this process and records all I/O.
# ---------------------------------------------------------------------------
try {
    $process = Start-Process -FilePath $PlinkPath `
                             -ArgumentList $plinkArgs `
                             -NoNewWindow `
                             -PassThru `
                             -Wait

    exit $process.ExitCode
} finally {
    # Clear the password from the environment immediately after use.
    Remove-Item Env:\PLINK_PASSWORD -ErrorAction SilentlyContinue
}
