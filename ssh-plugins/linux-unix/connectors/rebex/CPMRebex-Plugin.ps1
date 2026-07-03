#Requires -Version 5.1
# =============================================================================
# CPMRebex-Plugin.ps1 — CPM External Plugin: Linux/Unix via Rebex SSH
#
# Implements Verify, Change, and Reconcile for Linux/Unix accounts using the
# Rebex SSH .NET library. Key features over the plain Process.ini approach:
#
#   • Keyboard-interactive authentication (AIX/HP-UX/hardened sshd)
#   • SSH host-key fingerprint pinning
#   • Ed25519 / ECDSA / RSA key auth for reconcile accounts
#   • Detailed per-step error categorisation returned to CPM logs
#   • Automatic fallback: chpasswd → passwd --stdin → usermod -p
#
# CPM External Plugin environment variables (set by CPM before invocation):
#   CPM_OPERATION               — Verify | Change | Reconcile
#   CPM_ADDRESS                 — target host
#   CPM_PORT                    — SSH port
#   CPM_USERNAME                — managed account username
#   CPM_PASSWORD                — current password
#   CPM_NEWPASSWORD             — new generated password (Change/Reconcile)
#   CPM_EXTRAPASS1              — reconcile account credential
#   CPM_EXTRAPASS1NAME          — reconcile account username
#   CPM_EXTRAPASS1AUTHMETHOD    — Password | Key
#   CPM_HOSTKEY_FINGERPRINT     — expected SHA-256 fingerprint (optional pin)
#
# Exit codes:
#   0  — success
#   1  — retriable failure
#   2  — fatal / unrecoverable
# =============================================================================

[CmdletBinding()]
param(
    [string] $PluginDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Load Rebex assemblies.
# ---------------------------------------------------------------------------
$rebexCommon = Join-Path $PluginDir "Rebex.Common.dll"
$rebexSsh    = Join-Path $PluginDir "Rebex.Ssh.dll"

foreach ($dll in @($rebexCommon, $rebexSsh)) {
    if (-not (Test-Path $dll)) {
        Write-Error "FATAL: Rebex DLL not found: $dll. Run download-rebex.ps1 first."
        exit 2
    }
    Add-Type -Path $dll
}

# ---------------------------------------------------------------------------
# Read CPM environment variables.
# ---------------------------------------------------------------------------
$Operation         = $env:CPM_OPERATION              ?? "Verify"
$Address           = $env:CPM_ADDRESS                ?? ""
$Port              = [int]($env:CPM_PORT             ?? "22")
$UserName          = $env:CPM_USERNAME               ?? ""
$Password          = $env:CPM_PASSWORD               ?? ""
$NewPassword       = $env:CPM_NEWPASSWORD            ?? ""
$ReconUser         = $env:CPM_EXTRAPASS1NAME         ?? ""
$ReconCred         = $env:CPM_EXTRAPASS1             ?? ""
$ReconMethod       = $env:CPM_EXTRAPASS1AUTHMETHOD   ?? "Password"
$ExpectedFingerprint = $env:CPM_HOSTKEY_FINGERPRINT  ?? ""

# ---------------------------------------------------------------------------
# Helper: open a Rebex SSH session with optional host-key pinning.
# ---------------------------------------------------------------------------
function Open-RebexSession {
    param(
        [string] $TargetUser,
        [string] $Credential,
        [string] $AuthMethod = "Password"
    )

    $ssh = New-Object Rebex.Net.Ssh

    # Configure connection parameters.
    $ssh.Timeout = 30000   # 30 second socket timeout
    $ssh.Settings.SshParameters.EncryptionAlgorithms =
        [Rebex.Net.SshEncryptionAlgorithm]::AES256GCM,
        [Rebex.Net.SshEncryptionAlgorithm]::AES128GCM,
        [Rebex.Net.SshEncryptionAlgorithm]::AES256CTR

    # Optional host-key fingerprint pinning.
    if ($ExpectedFingerprint -ne "") {
        $ssh.add_ValidatingCertificate({
            param($sender, $e)
            $actual = $e.Certificate.Fingerprint
            if ($actual -ne $ExpectedFingerprint) {
                Write-Warning "CPM-REBEX: Host key mismatch! Expected=$ExpectedFingerprint Got=$actual"
                $e.Accept = $false
            } else {
                $e.Accept = $true
            }
        })
    } else {
        # Accept all host keys if no fingerprint pin is configured.
        $ssh.add_ValidatingCertificate({ param($s, $e) $e.Accept = $true })
    }

    $ssh.Connect($Address, $Port)

    switch ($AuthMethod) {
        "Key" {
            # Credential is the PEM private key content or a file path.
            $key = New-Object Rebex.Security.Cryptography.AsymmetricKeyParameter
            if (Test-Path $Credential) {
                $key = [Rebex.Security.Cryptography.AsymmetricKeyParameter]::LoadFromFile($Credential)
            } else {
                # Load from PEM string.
                $pemBytes = [System.Text.Encoding]::UTF8.GetBytes($Credential)
                $memStream = New-Object System.IO.MemoryStream(, $pemBytes)
                $key = [Rebex.Security.Cryptography.AsymmetricKeyParameter]::Load($memStream)
            }
            $ssh.Login($TargetUser, $key)
        }
        "KeyboardInteractive" {
            # Handle keyboard-interactive challenges (AIX/HP-UX style).
            $ssh.add_KeyboardInteractiveRequest({
                param($sender, $e)
                foreach ($prompt in $e.Prompts) {
                    # Respond to any password-style prompt with the credential.
                    if ($prompt.Prompt -match "[Pp]assword|[Pp]assphrase") {
                        $prompt.Response = $Credential
                    }
                }
            })
            $ssh.Login($TargetUser)
        }
        default {
            # Standard password authentication.
            $ssh.Login($TargetUser, $Credential)
        }
    }

    return $ssh
}

# ---------------------------------------------------------------------------
# Helper: run a shell command and return output.
# ---------------------------------------------------------------------------
function Invoke-RemoteCommand {
    param(
        [Rebex.Net.Ssh] $Session,
        [string]        $Command
    )

    $shell = $Session.OpenSession()
    try {
        $shell.StartExec($Command)
        $stdout = ""
        $stderr = ""
        $buf    = New-Object byte[] 4096

        while ($shell.State -ne [Rebex.Net.SshSessionState]::Closed) {
            $n = $shell.Receive($buf, 0, $buf.Length, [Rebex.Net.SshChannel]::Output)
            if ($n -gt 0) { $stdout += [System.Text.Encoding]::UTF8.GetString($buf, 0, $n) }
            $n = $shell.Receive($buf, 0, $buf.Length, [Rebex.Net.SshChannel]::ExtendedOutput)
            if ($n -gt 0) { $stderr += [System.Text.Encoding]::UTF8.GetString($buf, 0, $n) }
            Start-Sleep -Milliseconds 50
        }

        return [PSCustomObject]@{
            ExitCode = $shell.ExitCode
            Stdout   = $stdout
            Stderr   = $stderr
        }
    } finally {
        $shell.Close()
    }
}

# ---------------------------------------------------------------------------
# VERIFY
# ---------------------------------------------------------------------------
function Invoke-Verify {
    Write-Host "CPM-REBEX: Verify $UserName@${Address}:$Port"
    $ssh = $null
    try {
        $ssh = Open-RebexSession -TargetUser $UserName -Credential $Password
        $result = Invoke-RemoteCommand -Session $ssh -Command 'echo cyberark-verify-ok && id'

        if ($result.Stdout -match "cyberark-verify-ok") {
            Write-Host "CPM-REBEX: Verify SUCCEEDED. User info: $($result.Stdout.Trim())"
            return 0
        }
        Write-Error "CPM-REBEX: Verify FAILED — unexpected output: $($result.Stdout)"
        return 1
    } catch [Rebex.Net.SshException] {
        Write-Error "CPM-REBEX: SSH error during Verify: $($_.Exception.Message)"
        return 1
    } catch {
        Write-Error "CPM-REBEX: Unexpected error during Verify: $($_.Exception.Message)"
        return 2
    } finally {
        if ($ssh) { $ssh.Disconnect(); $ssh.Dispose() }
    }
}

# ---------------------------------------------------------------------------
# CHANGE
# ---------------------------------------------------------------------------
function Invoke-Change {
    Write-Host "CPM-REBEX: Change password for $UserName@${Address}:$Port"
    $ssh = $null
    try {
        $ssh = Open-RebexSession -TargetUser $UserName -Credential $Password

        # Try chpasswd first (non-interactive, honours PAM).
        $changeCmd = "echo '${UserName}:${NewPassword}' | sudo chpasswd 2>/dev/null && echo CHANGE_OK || " +
                     "sudo passwd --stdin '$UserName' <<< '$NewPassword' 2>/dev/null && echo CHANGE_OK || " +
                     "echo CHANGE_FAILED"

        $result = Invoke-RemoteCommand -Session $ssh -Command $changeCmd

        if ($result.Stdout -match "CHANGE_OK") {
            Write-Host "CPM-REBEX: Change SUCCEEDED for $UserName@$Address"
            return 0
        }
        Write-Error "CPM-REBEX: Change FAILED. Output=$($result.Stdout) Err=$($result.Stderr)"
        return 1
    } catch [Rebex.Net.SshException] {
        Write-Error "CPM-REBEX: SSH error during Change: $($_.Exception.Message)"
        return 1
    } catch {
        Write-Error "CPM-REBEX: Unexpected error during Change: $($_.Exception.Message)"
        return 2
    } finally {
        if ($ssh) { $ssh.Disconnect(); $ssh.Dispose() }
    }
}

# ---------------------------------------------------------------------------
# RECONCILE
# ---------------------------------------------------------------------------
function Invoke-Reconcile {
    Write-Host "CPM-REBEX: Reconcile $UserName@${Address}:$Port via $ReconUser [$ReconMethod]"
    $ssh = $null
    try {
        $ssh = Open-RebexSession -TargetUser $ReconUser -Credential $ReconCred -AuthMethod $ReconMethod

        $reconCmd = "sudo passwd -u '$UserName' 2>/dev/null; " +
                    "echo '${UserName}:${NewPassword}' | sudo chpasswd 2>/dev/null && echo RECON_OK || " +
                    "sudo passwd --stdin '$UserName' <<< '$NewPassword' 2>/dev/null && echo RECON_OK || " +
                    "HASH=\$(python3 -c \"import crypt; print(crypt.crypt('${NewPassword}', crypt.mksalt(crypt.METHOD_SHA512)))\" 2>/dev/null) && " +
                    "[ -n \"\$HASH\" ] && sudo usermod -p \"\$HASH\" '$UserName' && echo RECON_OK || echo RECON_FAILED"

        $result = Invoke-RemoteCommand -Session $ssh -Command $reconCmd

        if ($result.Stdout -match "RECON_OK") {
            Write-Host "CPM-REBEX: Reconcile SUCCEEDED for $UserName via $ReconUser"
            return 0
        }
        Write-Error "CPM-REBEX: Reconcile FAILED. Output=$($result.Stdout) Err=$($result.Stderr)"
        return 1
    } catch [Rebex.Net.SshException] {
        Write-Error "CPM-REBEX: SSH error during Reconcile: $($_.Exception.Message)"
        return 1
    } catch {
        Write-Error "CPM-REBEX: Unexpected error during Reconcile: $($_.Exception.Message)"
        return 2
    } finally {
        if ($ssh) { $ssh.Disconnect(); $ssh.Dispose() }
    }
}

# ---------------------------------------------------------------------------
# Dispatch.
# ---------------------------------------------------------------------------
$exitCode = switch ($Operation) {
    "Verify"    { Invoke-Verify }
    "Change"    { Invoke-Change }
    "Reconcile" { Invoke-Reconcile }
    default     { Write-Error "Unknown CPM operation: $Operation"; 2 }
}

exit $exitCode
