#Requires -Version 5.1
# =============================================================================
# download-sshnet.ps1 — Download SSH.NET (Renci) from NuGet
#
# Run ONCE on the CPM server before deploying CPMRenci-Plugin.ps1.
# Pulls Renci.SshNet.dll from NuGet.org and places it in the plugin directory.
#
# Usage:
#   .\download-sshnet.ps1 [-OutputDir <path>] [-Version <version>]
# =============================================================================

[CmdletBinding()]
param(
    [string] $OutputDir = $PSScriptRoot,
    [string] $Version   = "2024.2.0"
)

$ErrorActionPreference = 'Stop'

$url   = "https://www.nuget.org/api/v2/package/SSH.NET/$Version"
$nupkg = Join-Path $env:TEMP "SSH.NET.$Version.nupkg"
$tmp   = Join-Path $env:TEMP "SSH.NET.$Version"

Write-Host "Downloading SSH.NET $Version ..."
Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing

Write-Host "Extracting ..."
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive -Path $nupkg -DestinationPath $tmp

# Find the best-match TFM.
$dllPath = $null
foreach ($tfm in @("net6.0", "net48", "net472", "net46", "net45", "net40", "netstandard2.1", "netstandard2.0")) {
    $candidate = Join-Path $tmp "lib\$tfm\Renci.SshNet.dll"
    if (Test-Path $candidate) { $dllPath = $candidate; break }
}

if (-not $dllPath) {
    Write-Error "Could not locate Renci.SshNet.dll in the NuGet package."
    exit 1
}

$dest = Join-Path $OutputDir "Renci.SshNet.dll"
Copy-Item $dllPath -Destination $dest -Force
Write-Host "Copied: Renci.SshNet.dll → $dest"

Remove-Item $nupkg -Force
Remove-Item $tmp   -Recurse -Force

Write-Host ""
Write-Host "Done. Renci.SshNet.dll is ready in: $OutputDir"
Write-Host "Next: copy CPMRenci-Plugin.ps1 and Renci.SshNet.dll to the CPM Plugins\UnixSSH\ directory."
