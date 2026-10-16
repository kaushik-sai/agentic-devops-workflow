<#
.SYNOPSIS
    Workflow step: commits the agent's staged changes and pushes them with the GitHub App token.

.DESCRIPTION
    Runs after Import-AgentPatch.ps1 staged the patch and the change policy passed. The commit
    is authored by the App's bot identity (looked up from APP_SLUG) and carries trailers that
    tie it to the ticket and the run. The token is passed to git as a one-off header, so it is
    never written to .git/config, and git hooks are switched off.

    -NewBranch: the branch must not exist on origin yet (a rerun of the same ticket fails
    instead of overwriting the earlier work). Otherwise the push is fast-forward only.

.EXAMPLE
    ./scripts/Publish-AgentBranch.ps1 -Branch agent/DEVOPS-42-x -Message 'DEVOPS-42: Add health endpoint' -Trailer 'Jira: DEVOPS-42' -NewBranch
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Branch,
    [Parameter(Mandatory)] [string] $Message,
    [string[]] $Trailer = @(),
    [switch] $NewBranch,
    [string] $RepoPath = '.'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($name in 'GH_APP_TOKEN', 'GH_TOKEN', 'APP_SLUG', 'GITHUB_REPOSITORY') {
    if (-not [Environment]::GetEnvironmentVariable($name)) { throw "Environment variable $name is not set." }
}
$safe = @('-C', $RepoPath, '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false')

# Commits show as the App's bot account: <id>+<slug>[bot]@users.noreply.github.com.
$botName = "$($env:APP_SLUG)[bot]"
$botId = & gh api "/users/$([uri]::EscapeDataString($botName))" --jq .id
if ($LASTEXITCODE -ne 0 -or $botId -notmatch '^\d+$') { throw "Could not look up the user ID of $botName." }
$botEmail = "$botId+$botName@users.noreply.github.com"

& git @safe diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Output '::error::The agent made no changes to commit.'
    exit 1
}

$commitArgs = $safe + @('-c', "user.name=$botName", '-c', "user.email=$botEmail", 'commit', '--quiet', '--no-verify', '-m', $Message)
foreach ($line in $Trailer) { $commitArgs += @('--trailer', $line) }
& git @commitArgs
if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }

# Basic auth header with the App installation token, scoped to this one command.
$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$env:GH_APP_TOKEN"))
$url = "https://github.com/$env:GITHUB_REPOSITORY"
$lease = if ($NewBranch) { "--force-with-lease=refs/heads/$($Branch):" } else { $null }
$pushArgs = $safe + @('-c', "http.https://github.com/.extraheader=AUTHORIZATION: basic $basic", 'push', '--quiet', '--no-verify')
if ($lease) { $pushArgs += $lease }
$pushArgs += @($url, "HEAD:refs/heads/$Branch")
& git @pushArgs
if ($LASTEXITCODE -ne 0) {
    Write-Output "::error::Push to $Branch was rejected (branch exists already, or it moved since checkout)."
    exit 1
}
Write-Output "Pushed $(git -C $RepoPath rev-parse HEAD) to $Branch."
