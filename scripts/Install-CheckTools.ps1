<#
.SYNOPSIS
    Installs the pinned Pester and PSScriptAnalyzer versions for the current user if they are missing.

.EXAMPLE
    ./scripts/Install-CheckTools.ps1
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Pinned versions; Invoke-Checks.ps1 imports exactly these.
$modules = [ordered] @{ 'Pester' = '5.9.1'; 'PSScriptAnalyzer' = '1.25.0' }
foreach ($name in $modules.Keys) {
    $version = $modules[$name]
    if (Get-Module -ListAvailable -Name $name | Where-Object { $_.Version -eq [version] $version }) {
        Write-Output "$name $version is installed."
        continue
    }
    Write-Output "Installing $name $version"
    Install-Module -Name $name -RequiredVersion $version -Scope CurrentUser -Force -SkipPublisherCheck -Repository PSGallery
}
