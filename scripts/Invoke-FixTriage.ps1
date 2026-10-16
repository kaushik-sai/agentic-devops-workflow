<#
.SYNOPSIS
    Workflow step: decides what to do after CI failed on an agent branch: fix, escalate or skip.

.DESCRIPTION
    - skip:     the branch has moved on since the failed run (a newer run will decide), or no open PR.
    - escalate: the branch already has policy.fixLoop.maxAttempts fix commits.
    - fix:      otherwise. Writes the masked, size-capped failure log for the fix job.

    Expects the branch checked out at the failed run's commit with origin/main fetched,
    and GH_TOKEN with contents: read, actions: read and pull-requests: read.
    Outputs (to $env:GITHUB_OUTPUT): action, attempt, max_attempts, pr_number, issue_key.

.EXAMPLE
    ./scripts/Invoke-FixTriage.ps1 -RunId 123 -Repository o/r -Branch agent/DEVOPS-42-x -HeadSha abc -LogPath "$env:RUNNER_TEMP/fix/failure.log"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [long] $RunId,
    [Parameter(Mandatory)] [string] $Repository,
    [Parameter(Mandatory)] [string] $Branch,
    [Parameter(Mandatory)] [ValidatePattern('^[0-9a-f]{40}$')] [string] $HeadSha,
    [Parameter(Mandatory)] [string] $LogPath,
    [string] $RepoPath = '.'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'modules', 'AgentFlow') -Force
$policy = Get-AgentPolicy

function Write-StepOutput {
    param([hashtable] $Values)
    foreach ($key in $Values.Keys) {
        Write-Output "$key=$($Values[$key])"
        if ($env:GITHUB_OUTPUT) { "$key=$($Values[$key])" | Add-Content -LiteralPath $env:GITHUB_OUTPUT }
    }
}

# The branch name is untrusted input: only agent branches with a ticket key are handled.
$prefix = [regex]::Escape($policy.branch.prefix)
if ($Branch -cnotmatch "^$prefix([A-Z][A-Z0-9]{1,9}-[1-9][0-9]{0,6})(-[a-z0-9-]+)?$") {
    Write-Output "Not an agent branch: $Branch"
    Write-StepOutput @{ action = 'skip' }
    exit 0
}
$issueKey = $Matches[1]

# A newer push means a newer CI run; let that run decide, so two fixes never race.
# Read through the API: the checkout keeps no git credentials.
$remoteSha = & gh api "repos/$Repository/git/ref/heads/$Branch" --jq '.object.sha' 2>$null
if ($LASTEXITCODE -ne 0) { $remoteSha = '' }
if ($remoteSha -ne $HeadSha) {
    Write-Output "Branch head is '$remoteSha', the failed run was for $HeadSha. Skipping."
    Write-StepOutput @{ action = 'skip' }
    exit 0
}

$prJson = & gh pr list --repo $Repository --head $Branch --state open --json number --limit 1
if ($LASTEXITCODE -ne 0) { throw 'gh pr list failed.' }
$pr = @($prJson | ConvertFrom-Json)
if ($pr.Count -eq 0) {
    Write-Output "No open PR for $Branch. Skipping."
    Write-StepOutput @{ action = 'skip' }
    exit 0
}

$attempts = Get-FixAttempt -RepoPath $RepoPath -BaseRef 'origin/main' -Trailer $policy.fixLoop.attemptTrailer
$max = [int] $policy.fixLoop.maxAttempts
$values = @{ attempt = $attempts + 1; max_attempts = $max; pr_number = $pr[0].number; issue_key = $issueKey }
if ($attempts -ge $max) {
    $values.action = 'escalate'
    Write-StepOutput $values
    exit 0
}

$log = Get-CiFailureLog -RunId $RunId -Repository $Repository -MaxBytes $policy.fixLoop.maxLogBytes
$folder = Split-Path -Path $LogPath -Parent
if ($folder) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
Set-Content -LiteralPath $LogPath -Value $log -Encoding utf8NoBOM
$values.action = 'fix'
Write-StepOutput $values
