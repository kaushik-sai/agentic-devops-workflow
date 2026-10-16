<#
.SYNOPSIS
    The repository's checks: PSScriptAnalyzer (no errors or warnings) and Pester (all pass).

.DESCRIPTION
    One script for every caller: a developer before pushing, the agent before it hands back,
    and the ci workflow. Exits 1 when a check fails.
    Needs Pester 5.9.1 and PSScriptAnalyzer 1.25.0 (pinned; ci.yml installs them).

.EXAMPLE
    pwsh -NoProfile -File ./scripts/Invoke-Checks.ps1
#>
[CmdletBinding()]
param(
    # Where to write the NUnit result file; nothing is written when empty.
    [string] $TestResultPath = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Path $PSScriptRoot -Parent
$failed = $false

Import-Module PSScriptAnalyzer -RequiredVersion '1.25.0'
$findings = @(Invoke-ScriptAnalyzer -Path $root -Recurse -Settings (Join-Path -Path $root -ChildPath 'PSScriptAnalyzerSettings.psd1'))
$findings | Format-Table Severity, RuleName, ScriptName, Line, Message -AutoSize -Wrap | Out-String -Width 200 | Write-Output
$blocking = @($findings | Where-Object Severity -In 'Error', 'Warning', 'ParseError')
if ($blocking.Count -gt 0) {
    Write-Output "PSScriptAnalyzer: $($blocking.Count) error/warning finding(s)."
    $failed = $true
}
else {
    Write-Output 'PSScriptAnalyzer: no errors or warnings.'
}

Import-Module Pester -RequiredVersion '5.9.1'
$config = New-PesterConfiguration
$config.Run.Path = Join-Path -Path $root -ChildPath 'tests'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Normal'
if ($TestResultPath) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = $TestResultPath
}
$result = Invoke-Pester -Configuration $config
Write-Output "Pester: $($result.Result), $($result.PassedCount) passed, $($result.FailedCount) failed, $($result.SkippedCount) skipped."
if ($result.Result -ne 'Passed') { $failed = $true }

if ($failed) { exit 1 }
