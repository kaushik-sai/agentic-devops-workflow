<#
.SYNOPSIS
    Workflow step: checks a Jira ticket is eligible and writes ticket.json for the next job.

.DESCRIPTION
    Reads the issue back from Jira (the webhook payload only names it), applies the policy,
    and writes the ticket and its branch name. When the ticket is not eligible it comments
    the reasons on the Jira issue and exits 1, so the run stops before the agent starts.

    Outputs (to $env:GITHUB_OUTPUT when set): issue_key, branch.

.EXAMPLE
    ./scripts/Invoke-TicketIntake.ps1 -IssueKey DEVOPS-42 -OutputPath "$env:RUNNER_TEMP/ticket/ticket.json"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $IssueKey,
    [Parameter(Mandatory)] [string] $OutputPath,
    # Skip the Jira comment on rejection (local dry runs).
    [switch] $NoJiraComment
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'modules', 'AgentFlow') -Force
$policy = Get-AgentPolicy
$ticket = Get-AgentTicket -IssueKey $IssueKey -Policy $policy

if (-not $ticket.Eligible) {
    $reasons = $ticket.Reasons -join ' '
    Write-Output "::error::$IssueKey is not eligible for the agent. $reasons"
    # Only comment on projects the agent may touch; for others we never call Jira at all.
    if (-not $NoJiraComment -and $ticket.Project -cin @($policy.jira.allowedProjects)) {
        Send-JiraComment -IssueKey $IssueKey -Text "The agent did not start: $reasons"
    }
    exit 1
}

$branch = New-AgentBranchName -IssueKey $ticket.Key -Summary $ticket.Summary -Policy $policy
$ticket | Add-Member -NotePropertyName Branch -NotePropertyValue $branch
$folder = Split-Path -Path $OutputPath -Parent
if ($folder) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
$ticket | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM

Write-Output "$($ticket.Key) is eligible. Branch: $branch"
if ($env:GITHUB_OUTPUT) {
    "issue_key=$($ticket.Key)" | Add-Content -LiteralPath $env:GITHUB_OUTPUT
    "branch=$branch" | Add-Content -LiteralPath $env:GITHUB_OUTPUT
}
