#Requires -Version 5.1
# =============================================================================
# CPMRenci-Plugin.ps1 — CPM External Plugin: Linux/Unix via SSH.NET (Renci)
#
# Implements Verify, Change, and Reconcile for Linux/Unix accounts using
# Renci.SshNet. Key differentiator: multi-key reconcile is native —
# PrivateKeyConnectionInfo accepts an array of keys and SSH.NET offers each
# to the server automatically, making cascading reconcile accounts trivial.
#
# CPM External Plugin environment variables:
#   CPM_OPERATION               — Verify | Change | Reconcile
#   CPM_ADDRESS                 — target host
#   CPM_PORT                    — SSH port
#   CPM_USERNAME                — managed account username
#   CPM_PASSWORD                — current password
#   CPM_NEWPASSWORD             — new generated password (Change/Reconcile)
#   CPM_EXTRAPASS1              — reconcile account 1 credential (PEM or path)
#   CPM_EXTRAPASS1NAME          — reconcile account 1 username
#   CPM_EXTRAPASS1AUTHMETHOD    — Password | Key
#   CPM_EXTRAPASS2              — reconcile account 2 credential (optional)
#   CPM_EXTRAPASS2NAME          — reconcile account 2 username (optional)
#   CPM_EXTRAPASS2AUTHMETHOD    — Password | Key (optional)
#   CPM_EXTRAPASS3              — reconcile account 3 credential (optional)
#   CPM_EXTRAPASS3NAME          — reconcile account 3 username (optional)
#   CPM_EXTRAPASS3AUTHMETHOD    — Password | Key (optional)
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
# Load Renci.SshNet assembly.
# ---------------------------------------------------------------------------
$sshNetDll = Join-Path $PluginDir "Renci.SshNet.dll"
if (-not (Test-Path $sshNetDll)) {
    Write-Error "FATAL: Renci.SshNet.dll not found at '$sshNetDll'. Run download-sshnet.ps1 first."
    exit 2
}
Add-Type -Path $sshNetDll

# ---------------------------------------------------------------------------
# Read CPM environment variables.
# ---------------------------------------------------------------------------
$Operation   = $env:CPM_OPERATION  ?? "Verify"
$Address     = $env:CPM_ADDRESS    ?? ""
$Port        = [int]($env:CPM_PORT ?? "22")
$UserName    = $env:CPM_USERNAME   ?? ""
$Password    = $env:CPM_PASSWORD   ?? ""
$NewPassword = $env:CPM_NEWPASSWORD ?? ""

# Reconcile account definitions (up to 3).
$ReconAccounts = @(
    [PSCustomObject]@{ User = $env:CPM_EXTRAPASS1NAME ?? ""; Cred = $env:CPM_EXTRAPASS1 ?? ""; Method = $env:CPM_EXTRAPASS1AUTHMETHOD ?? "Password" }
    [PSCustomObject]@{ User = $env:CPM_EXTRAPASS2NAME ?? ""; Cred = $env:CPM_EXTRAPASS2 ?? ""; Method = $env:CPM_EXTRAPASS2AUTHMETHOD ?? "Password" }
    [PSCustomObject]@{ User = $env:CPM_EXTRAPASS3NAME ?? ""; Cred = $env:CPM_EXTRAPASS3 ?? ""; Method = $env:CPM_EXTRAPASS3AUTHMETHOD ?? "Password" }
) | Where-Object { $_.User -ne "" }

# ---------------------------------------------------------------------------
# Helper: write a PEM key string to a secure temp file.
# Returns the file path; caller must delete it.
# ---------------------------------------------------------------------------
function Write-TempKey {
    param([string] $PemContent)
    $tmp = [System.IO.Path]::GetTempFileName()
    # Ensure only the current user can read this file.
    $acl = Get-Acl $tmp
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
        "FullControl", "Allow"
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $tmp -AclObject $acl
    [System.IO.File]::WriteAllText($tmp, $PemContent)
    return $tmp
}

# ---------------------------------------------------------------------------
# Helper: build a Renci ConnectionInfo object.
# ---------------------------------------------------------------------------
function New-SshConnectionInfo {
    param(
        [string] $TargetUser,
        [string] $Credential,
        [string] $AuthMethod = "Password"
    )

    $authMethods = [System.Collections.Generic.List[Renci.SshNet.AuthenticationMethod]]::new()

    if ($AuthMethod -eq "Key") {
        $tmpKeys = @()
        $keyFiles = @()

        # Credential may be a comma-separated list of PEM strings or file paths.
        $credEntries = $Credential -split "`n---`n"   # split on a custom delimiter if needed

        foreach ($entry in $credEntries) {
            $entry = $entry.Trim()
            if ([string]::IsNullOrEmpty($entry)) { continue }

            if ((Test-Path $entry -ErrorAction SilentlyContinue)) {
                $keyFiles += New-Object Renci.SshNet.PrivateKeyFile($entry)
            } else {
                # PEM content — write to temp file.
                $tmpPath = Write-TempKey -PemContent $entry
                $tmpKeys += $tmpPath
                $keyFiles += New-Object Renci.SshNet.PrivateKeyFile($tmpPath)
            }
        }

        $authMethods.Add(
            (New-Object Renci.SshNet.PrivateKeyAuthenticationMethod($TargetUser, $keyFiles))
        )

        # Register cleanup of temp key files.
        $script:TempKeyFiles += $tmpKeys
    } else {
        $authMethods.Add(
            (New-Object Renci.SshNet.PasswordAuthenticationMethod($TargetUser, $Credential))
        )
    }

    return New-Object Renci.SshNet.ConnectionInfo(
        $Address, $Port, $TargetUser, $authMethods.ToArray()
    )
}

# Track temp key files for cleanup.
$script:TempKeyFiles = @()

# ---------------------------------------------------------------------------
# Helper: run a command over an SSH.NET SshClient and return result.
# ---------------------------------------------------------------------------
function Invoke-SshCommand {
    param(
        [Renci.SshNet.SshClient] $Client,
        [string]                 $Command
    )
    $cmd = $Client.CreateCommand($Command)
    $cmd.CommandTimeout = [TimeSpan]::FromSeconds(30)
    $stdout = $cmd.Execute()
    return [PSCustomObject]@{
        ExitCode = $cmd.ExitStatus
        Stdout   = $stdout
        Stderr   = $cmd.Error
    }
}

# ---------------------------------------------------------------------------
# VERIFY
# ---------------------------------------------------------------------------
function Invoke-Verify {
    Write-Host "CPM-RENCI: Verify $UserName@${Address}:$Port"
    $client = $null
    try {
        $connInfo = New-SshConnectionInfo -TargetUser $UserName -Credential $Password
        $client   = New-Object Renci.SshNet.SshClient($connInfo)
        $client.ConnectionInfo.Timeout = [TimeSpan]::FromSeconds(15)
        $client.Connect()

        $result = Invoke-SshCommand -Client $client -Command 'echo cyberark-verify-ok && id'

        if ($result.Stdout -match "cyberark-verify-ok") {
            Write-Host "CPM-RENCI: Verify SUCCEEDED. $($result.Stdout.Trim())"
            return 0
        }
        Write-Error "CPM-RENCI: Verify FAILED — unexpected output: $($result.Stdout)"
        return 1
    } catch [Renci.SshNet.Common.SshAuthenticationException] {
        Write-Error "CPM-RENCI: Authentication failed: $($_.Exception.Message)"
        return 1
    } catch {
        Write-Error "CPM-RENCI: Error during Verify: $($_.Exception.Message)"
        return 1
    } finally {
        if ($client -and $client.IsConnected) { $client.Disconnect() }
        $client?.Dispose()
    }
}

# ---------------------------------------------------------------------------
# CHANGE
# ---------------------------------------------------------------------------
function Invoke-Change {
    Write-Host "CPM-RENCI: Change password for $UserName@${Address}:$Port"
    $client = $null
    try {
        $connInfo = New-SshConnectionInfo -TargetUser $UserName -Credential $Password
        $client   = New-Object Renci.SshNet.SshClient($connInfo)
        $client.Connect()

        $changeCmd = @(
            "echo '${UserName}:${NewPassword}' | sudo chpasswd 2>/dev/null && echo CHANGE_OK",
            "|| sudo passwd --stdin '$UserName' <<< '$NewPassword' 2>/dev/null && echo CHANGE_OK",
            "|| echo CHANGE_FAILED"
        ) -join " "

        $result = Invoke-SshCommand -Client $client -Command $changeCmd

        if ($result.Stdout -match "CHANGE_OK") {
            Write-Host "CPM-RENCI: Change SUCCEEDED for $UserName"
            return 0
        }
        Write-Error "CPM-RENCI: Change FAILED. Stdout=$($result.Stdout) Stderr=$($result.Stderr)"
        return 1
    } catch [Renci.SshNet.Common.SshAuthenticationException] {
        Write-Error "CPM-RENCI: Auth failed during Change (password may already be wrong): $($_.Exception.Message)"
        return 1
    } catch {
        Write-Error "CPM-RENCI: Error during Change: $($_.Exception.Message)"
        return 1
    } finally {
        if ($client -and $client.IsConnected) { $client.Disconnect() }
        $client?.Dispose()
    }
}

# ---------------------------------------------------------------------------
# RECONCILE — multi-account, multi-key, SSH.NET native cascading.
#
# SSH.NET's PrivateKeyConnectionInfo accepts multiple PrivateKeyFile objects
# and offers each key to the server in turn. When multiple reconcile accounts
# are configured, we try each account in priority order 1→2→3.
# ---------------------------------------------------------------------------
function Invoke-Reconcile {
    Write-Host "CPM-RENCI: Reconcile $UserName@${Address}:$Port — trying $($ReconAccounts.Count) reconcile account(s)"

    $reconCmd = @(
        "sudo passwd -u '$UserName' 2>/dev/null;",
        "echo '${UserName}:${NewPassword}' | sudo chpasswd 2>/dev/null && echo RECON_OK",
        "|| sudo passwd --stdin '$UserName' <<< '$NewPassword' 2>/dev/null && echo RECON_OK",
        "|| HASH=\$(python3 -c \"import crypt; print(crypt.crypt('${NewPassword}', crypt.mksalt(crypt.METHOD_SHA512)))\" 2>/dev/null)",
        "&& [ -n \"\$HASH\" ] && sudo usermod -p \"\$HASH\" '$UserName' && echo RECON_OK",
        "|| echo RECON_FAILED"
    ) -join " "

    foreach ($acct in $ReconAccounts) {
        Write-Host "CPM-RENCI: Trying reconcile via $($acct.User) [$($acct.Method)]"
        $client = $null
        try {
            $connInfo = New-SshConnectionInfo `
                -TargetUser $acct.User `
                -Credential $acct.Cred `
                -AuthMethod $acct.Method
            $client = New-Object Renci.SshNet.SshClient($connInfo)
            $client.Connect()

            $result = Invoke-SshCommand -Client $client -Command $reconCmd

            if ($result.Stdout -match "RECON_OK") {
                Write-Host "CPM-RENCI: Reconcile SUCCEEDED via $($acct.User)"
                return 0
            }
            Write-Warning "CPM-RENCI: $($acct.User) connected but reconcile command failed — trying next account."
        } catch [Renci.SshNet.Common.SshAuthenticationException] {
            Write-Warning "CPM-RENCI: Auth failed for $($acct.User) — trying next account."
        } catch {
            Write-Warning "CPM-RENCI: Error with $($acct.User): $($_.Exception.Message) — trying next."
        } finally {
            if ($client -and $client.IsConnected) { $client.Disconnect() }
            $client?.Dispose()
        }
    }

    Write-Error "CPM-RENCI: All $($ReconAccounts.Count) reconcile account(s) exhausted — Reconcile FAILED."
    return 1
}

# ---------------------------------------------------------------------------
# Dispatch, then clean up any temp key files.
# ---------------------------------------------------------------------------
try {
    $exitCode = switch ($Operation) {
        "Verify"    { Invoke-Verify }
        "Change"    { Invoke-Change }
        "Reconcile" { Invoke-Reconcile }
        default     { Write-Error "Unknown operation: $Operation"; 2 }
    }
} finally {
    foreach ($f in $script:TempKeyFiles) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}

exit $exitCode
