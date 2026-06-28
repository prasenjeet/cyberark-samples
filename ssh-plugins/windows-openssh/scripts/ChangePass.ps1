# =============================================================================
# ChangePass.ps1 — Windows local account password change via PowerShell
#
# Executed on the target Windows host over an SSH session as part of
# the CPM Change operation. Can also be run standalone for testing.
#
# Parameters:
#   -UserName    Local account to update
#   -NewPassword New password to set
#
# Exit codes:
#   0 — success
#   1 — parameter validation failure
#   2 — account not found
#   3 — password change failed
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$UserName,

    [Parameter(Mandatory = $true)]
    [string]$NewPassword
)

$ErrorActionPreference = 'Stop'

function Exit-WithCode {
    param([int]$Code, [string]$Message)
    if ($Code -eq 0) {
        Write-Output "SUCCESS: $Message"
    } else {
        Write-Error "ERROR: $Message"
    }
    exit $Code
}

# Validate input.
if ([string]::IsNullOrWhiteSpace($UserName)) {
    Exit-WithCode -Code 1 -Message "UserName parameter is required."
}
if ([string]::IsNullOrWhiteSpace($NewPassword)) {
    Exit-WithCode -Code 1 -Message "NewPassword parameter is required."
}
if ($NewPassword.Length -lt 14) {
    Exit-WithCode -Code 1 -Message "Password must be at least 14 characters."
}

# Verify the local account exists.
try {
    $account = Get-LocalUser -Name $UserName
} catch {
    Exit-WithCode -Code 2 -Message "Local user '$UserName' not found: $_"
}

# Unlock the account if locked.
if ($account.Enabled -eq $false) {
    Write-Output "INFO: Account '$UserName' is disabled. Enabling..."
    Enable-LocalUser -Name $UserName
}

# Change the password.
try {
    $securePass = ConvertTo-SecureString -String $NewPassword -AsPlainText -Force
    Set-LocalUser -Name $UserName -Password $securePass
    Exit-WithCode -Code 0 -Message "Password for '$UserName' changed successfully."
} catch {
    Exit-WithCode -Code 3 -Message "Failed to change password for '$UserName': $_"
}
