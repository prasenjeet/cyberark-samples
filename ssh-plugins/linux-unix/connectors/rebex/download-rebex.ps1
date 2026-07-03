#Requires -Version 5.1
# =============================================================================
# download-rebex.ps1 — Download Rebex SSH NuGet packages for the CPM plugin
#
# Run this ONCE on the CPM server before deploying CPMRebex-Plugin.ps1.
# Downloads Rebex.Ssh and its dependency Rebex.Common from NuGet.org and
# extracts the .NET 4.7.2 DLLs into the plugin directory.
#
# Usage:
#   .\download-rebex.ps1 [-OutputDir <path>] [-RebexVersion <version>]
# =============================================================================

[CmdletBinding()]
param(
    [string] $OutputDir    = $PSScriptRoot,
    [string] $RebexVersion = "2024.1.8631"
)

$ErrorActionPreference = 'Stop'
$NuGetBase = "https://www.nuget.org/api/v2/package"
$Packages  = @("Rebex.Common", "Rebex.Ssh")
$TfmPath   = "lib\net40"     # .NET 4.0 target compatible with .NET 4.7.2

Write-Host "Downloading Rebex SSH $RebexVersion to: $OutputDir"
Write-Host ""

foreach ($pkg in $Packages) {
    $url      = "$NuGetBase/$pkg/$RebexVersion"
    $nupkg    = Join-Path $env:TEMP "$pkg.$RebexVersion.nupkg"
    $expanded = Join-Path $env:TEMP "$pkg.$RebexVersion"

    Write-Host "  Downloading $pkg ..."
    Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing

    Write-Host "  Extracting ..."
    if (Test-Path $expanded) { Remove-Item $expanded -Recurse -Force }
    Expand-Archive -Path $nupkg -DestinationPath $expanded

    # Find the best matching .NET target framework folder.
    $libDir = $null
    foreach ($tfm in @("net472", "net46", "net45", "net40")) {
        $candidate = Join-Path $expanded "lib\$tfm"
        if (Test-Path $candidate) { $libDir = $candidate; break }
    }

    if (-not $libDir) {
        Write-Error "Could not find a .NET lib folder in $pkg."
        exit 1
    }

    Get-ChildItem $libDir -Filter "*.dll" | ForEach-Object {
        $dest = Join-Path $OutputDir $_.Name
        Copy-Item $_.FullName -Destination $dest -Force
        Write-Host "  Copied: $($_.Name) → $dest"
    }

    Remove-Item $nupkg    -Force
    Remove-Item $expanded -Recurse -Force
    Write-Host ""
}

Write-Host "Done. Rebex DLLs are ready in: $OutputDir"
Write-Host "Next: copy CPMRebex-Plugin.ps1 and the DLLs to the CPM Plugins\UnixSSH\ directory."
