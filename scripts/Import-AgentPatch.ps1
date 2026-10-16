<#
.SYNOPSIS
    Publish job step: applies the agent's patch and checks it against the change policy.

.DESCRIPTION
    Run this script from a checkout of main, so the module and policy that judge the patch
    are main's. The patch is applied to -RepoPath (main itself for a new ticket, or the PR
    branch for a fix) and staged. Then:
    - symlinks and submodules in the patch are refused
    - Test-AgentChangePolicy runs on the staged result against origin/main (protected paths,
      file and line limits), so a fix is judged on the whole branch, not only on its own diff

    -NewBranch creates -Branch from the current HEAD first.

.EXAMPLE
    ./scripts/Import-AgentPatch.ps1 -PatchPath "$env:RUNNER_TEMP/patch/agent.patch" -Branch agent/DEVOPS-42-x -NewBranch
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PatchPath,
    [string] $RepoPath = '.',
    [string] $Branch = '',
    [switch] $NewBranch
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'modules', 'AgentFlow') -Force
$policy = Get-AgentPolicy

if (-not (Test-Path -LiteralPath $PatchPath -PathType Leaf)) {
    throw "Patch not found: $PatchPath"
}
$safe = @('-C', $RepoPath, '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false')

if ($NewBranch) {
    if ($Branch -notmatch "^$([regex]::Escape($policy.branch.prefix))[A-Za-z0-9._/-]+$") {
        throw "Not an agent branch name: '$Branch'."
    }
    & git @safe switch --quiet --create $Branch
    if ($LASTEXITCODE -ne 0) { throw "Could not create branch $Branch." }
}

# git apply refuses paths into .git and outside the repository.
$patchFull = (Resolve-Path -LiteralPath $PatchPath).Path
& git @safe apply --index --whitespace=nowarn $patchFull
if ($LASTEXITCODE -ne 0) {
    Write-Output '::error::The agent patch does not apply cleanly.'
    exit 1
}

# Mode 120000 is a symlink, 160000 a submodule: neither is ever expected from the agent.
$summary = & git @safe diff --cached --summary origin/main
$special = @($summary | Where-Object { $_ -match 'mode 1[26]0000' })
if ($special.Count -gt 0) {
    $special | ForEach-Object { Write-Output "::error::Refused: $_" }
    exit 1
}

$report = Test-AgentChangePolicy -RepoPath $RepoPath -BaseRef origin/main -Policy $policy -Staged
Write-Output "Change policy: $($report.Files.Count) file(s), $($report.Lines) line(s) against main."
if (-not $report.Compliant) {
    $report.Violations | ForEach-Object { Write-Output "::error::$_" }
    exit 1
}
Write-Output 'Change policy: passed.'
