<#
.SYNOPSIS
    Agent job step: saves the agent's changes as a binary patch, plus its summary.

.DESCRIPTION
    Runs in the job where the agent worked, so it holds no write credential and its output is
    only data. Git hooks and fsmonitor are switched off for these commands, so nothing the agent
    wrote into the checkout can run here. The publish job decides whether the patch is allowed.

.EXAMPLE
    ./scripts/Export-AgentPatch.ps1 -OutputPath "$env:RUNNER_TEMP/patch"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $OutputPath,
    [string] $RepoPath = '.'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$safe = @('-C', $RepoPath, '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false')
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

# Everything except the agent's own working folder (.gitignore excludes it; the rm makes sure).
& git @safe add --all
if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
& git @safe rm -r --cached --quiet --ignore-unmatch -- .agent
if ($LASTEXITCODE -ne 0) { throw 'git rm --cached .agent failed.' }
$patch = Join-Path -Path $OutputPath -ChildPath 'agent.patch'
& git @safe diff --cached --binary --no-color --output=$patch
if ($LASTEXITCODE -ne 0) { throw 'git diff failed.' }

$summary = Join-Path -Path $RepoPath -ChildPath '.agent/summary.md'
if (Test-Path -LiteralPath $summary -PathType Leaf) {
    Copy-Item -LiteralPath $summary -Destination (Join-Path -Path $OutputPath -ChildPath 'summary.md')
}
$size = (Get-Item -LiteralPath $patch).Length
Write-Output "Patch: $size bytes."
if ($size -eq 0) {
    Write-Output '::error::The agent made no changes.'
    exit 1
}
