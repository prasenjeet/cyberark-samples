#Requires -Version 5.1
# =============================================================================
# CPMPlink-Plugin.ps1 — CPM External Plugin: Linux/Unix via plink.exe
#
# Implements the three CPM operations (Verify, Change, Reconcile) for
# Linux/Unix accounts using plink.exe as the SSH transport. Invoked by
# CPM as an External Plugin; parameters are supplied via environment
# variables set by the CPM engine from the Vault account object.
#
# CPM External Plugin environment variables (set by CPM before invocation):
#   CPM_OPERATION       — Verify | Change | Reconcile
#   CPM_ADDRESS         — target host
#   CPM_PORT            — SSH port
#   CPM_USERNAME        — managed account username
#   CPM_PASSWORD        — current password
#   CPM_NEWPASSWORD     — new generated password (Change/Reconcile only)
#   CPM_EXTRAPASS1      — reconcile account credential (password or .ppk path)
#   CPM_EXTRAPASS1NAME  — reconcile account username
#   CPM_EXTRAPASS1AUTHMETHOD — "Password" or "Key"
#
# Exit codes (parsed by CPM):
#   0  — operation succeeded
#   1  — operation failed (CPM retries per MaxNumberOfRetries)
#   2  — unrecoverable error (CPM does not retry)
# =============================================================================

[CmdletBinding()]
param(
    [string] $PlinkPath = "C:\Program Files\PuTTY\plink.exe"
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Read CPM-supplied parameters from environment variables.
# ---------------------------------------------------------------------------
$Operation   = $env:CPM_OPERATION       ?? "Verify"
$Address     = $env:CPM_ADDRESS         ?? ""
$Port        = $env:CPM_PORT            ?? "22"
$UserName    = $env:CPM_USERNAME        ?? ""
$Password    = $env:CPM_PASSWORD        ?? ""
$NewPassword = $env:CPM_NEWPASSWORD     ?? ""
$ReconUser   = $env:CPM_EXTRAPASS1NAME  ?? ""
$ReconCred   = $env:CPM_EXTRAPASS1      ?? ""
$ReconMethod = $env:CPM_EXTRAPASS1AUTHMETHOD ?? "Password"

if (-not (Test-Path $PlinkPath)) {
    Write-Error "FATAL: plink.exe not found at '$PlinkPath'."
    exit 2
}

# ---------------------------------------------------------------------------
# Helper: run a command on the target via plink and return stdout.
# ---------------------------------------------------------------------------
function Invoke-PlinkCommand {
    param(
        [string]   $TargetUser,
        [string]   $TargetCred,
        [string]   $AuthMethod = "Password",
        [string[]] $Commands
    )

    $tmpKey   = $null
    $tmpBatch = $null

    try {
        # Write commands to a temp batch file so plink executes them in sequence.
        $tmpBatch = [System.IO.Path]::GetTempFileName() + ".sh"
        $Commands | Set-Content -Path $tmpBatch -Encoding UTF8

        $plinkArgs = @('-ssh', '-P', $Port, '-batch', '-no-antispoof')

        if ($AuthMethod -eq "Key") {
            # TargetCred contains either a .ppk file path or PEM key content.
            if (Test-Path $TargetCred) {
                $plinkArgs += '-i', $TargetCred
            } else {
                # Write PEM content to a temp .ppk file (plink accepts OpenSSH PEM directly in v0.78+).
                $tmpKey = [System.IO.Path]::GetTempFileName() + ".ppk"
                [System.IO.File]::WriteAllText($tmpKey, $TargetCred)
                $plinkArgs += '-i', $tmpKey
            }
        } else {
            $env:PLINK_PASSWORD = $TargetCred
            $plinkArgs += '-pw', $TargetCred
        }

        $plinkArgs += '-l', $TargetUser
        $plinkArgs += $Address
        # Append the remote command (plink executes and exits, not a shell).
        $plinkArgs += "bash -s"

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = $PlinkPath
        $psi.Arguments              = ($plinkArgs -join ' ')
        $psi.RedirectStandardInput  = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true

        $proc = [System.Diagnostics.Process]::Start($psi)

        # Send the batch script via stdin.
        $scriptContent = [System.IO.File]::ReadAllText($tmpBatch)
        $proc.StandardInput.Write($scriptContent)
        $proc.StandardInput.Close()

        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        return [PSCustomObject]@{
            ExitCode = $proc.ExitCode
            Stdout   = $stdout
            Stderr   = $stderr
        }
    }
    finally {
        Remove-Item Env:\PLINK_PASSWORD -ErrorAction SilentlyContinue
        if ($tmpKey   -and (Test-Path $tmpKey))   { Remove-Item $tmpKey   -Force }
        if ($tmpBatch -and (Test-Path $tmpBatch)) { Remove-Item $tmpBatch -Force }
    }
}

# ---------------------------------------------------------------------------
# VERIFY — Confirm the stored credential authenticates successfully.
# ---------------------------------------------------------------------------
function Invoke-Verify {
    Write-Host "CPM-PLINK: Starting Verify for $UserName@${Address}:$Port"

    $result = Invoke-PlinkCommand `
        -TargetUser $UserName `
        -TargetCred $Password `
        -AuthMethod "Password" `
        -Commands @(
            'echo "cyberark-verify-ok"'
        )

    if ($result.ExitCode -eq 0 -and $result.Stdout -match "cyberark-verify-ok") {
        Write-Host "CPM-PLINK: Verify SUCCEEDED for $UserName@$Address"
        return 0
    }

    Write-Error "CPM-PLINK: Verify FAILED. Exit=$($result.ExitCode) Err=$($result.Stderr)"
    return 1
}

# ---------------------------------------------------------------------------
# CHANGE — Rotate the managed account password to $NewPassword.
# ---------------------------------------------------------------------------
function Invoke-Change {
    Write-Host "CPM-PLINK: Starting Change for $UserName@${Address}:$Port"

    $result = Invoke-PlinkCommand `
        -TargetUser $UserName `
        -TargetCred $Password `
        -AuthMethod "Password" `
        -Commands @(
            "echo '${UserName}:${NewPassword}' | sudo chpasswd 2>/dev/null && echo 'CHANGE_OK' && exit 0",
            "sudo passwd --stdin '$UserName' <<< '$NewPassword' 2>/dev/null && echo 'CHANGE_OK' && exit 0",
            "echo 'CHANGE_FAILED'; exit 1"
        )

    if ($result.ExitCode -eq 0 -and $result.Stdout -match "CHANGE_OK") {
        Write-Host "CPM-PLINK: Change SUCCEEDED for $UserName@$Address"
        return 0
    }

    Write-Error "CPM-PLINK: Change FAILED. Exit=$($result.ExitCode) Err=$($result.Stderr)"
    return 1
}

# ---------------------------------------------------------------------------
# RECONCILE — Use a privileged account to force-reset the managed password.
# Supports both password and SSH key auth for the reconcile account.
# ---------------------------------------------------------------------------
function Invoke-Reconcile {
    Write-Host "CPM-PLINK: Starting Reconcile for $UserName@${Address}:$Port"
    Write-Host "CPM-PLINK: Reconcile account=$ReconUser method=$ReconMethod"

    $result = Invoke-PlinkCommand `
        -TargetUser $ReconUser `
        -TargetCred $ReconCred `
        -AuthMethod $ReconMethod `
        -Commands @(
            "sudo passwd -u '$UserName' 2>/dev/null || true",
            "echo '${UserName}:${NewPassword}' | sudo chpasswd 2>/dev/null && echo 'RECON_OK' && exit 0",
            "sudo passwd --stdin '$UserName' <<< '$NewPassword' 2>/dev/null && echo 'RECON_OK' && exit 0",
            "HASH=\$(python3 -c \"import crypt; print(crypt.crypt('${NewPassword}', crypt.mksalt(crypt.METHOD_SHA512)))\" 2>/dev/null)",
            "[ -n \"\$HASH\" ] && sudo usermod -p \"\$HASH\" '$UserName' 2>/dev/null && echo 'RECON_OK' && exit 0",
            "echo 'RECON_FAILED'; exit 1"
        )

    if ($result.ExitCode -eq 0 -and $result.Stdout -match "RECON_OK") {
        Write-Host "CPM-PLINK: Reconcile SUCCEEDED using $ReconUser@$Address"
        return 0
    }

    Write-Error "CPM-PLINK: Reconcile FAILED. Exit=$($result.ExitCode) Err=$($result.Stderr)"
    return 1
}

# ---------------------------------------------------------------------------
# Dispatch to the requested operation.
# ---------------------------------------------------------------------------
$exitCode = switch ($Operation) {
    "Verify"    { Invoke-Verify }
    "Change"    { Invoke-Change }
    "Reconcile" { Invoke-Reconcile }
    default {
        Write-Error "CPM-PLINK: Unknown operation '$Operation'."
        2
    }
}

exit $exitCode
