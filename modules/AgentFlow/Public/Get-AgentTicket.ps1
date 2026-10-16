Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Fetches a Jira issue and decides whether the agent may work on it.

.DESCRIPTION
    The webhook payload only names the issue. Everything else (summary, description,
    status, labels) is read back from Jira here, so a forged or stale payload cannot
    change what the agent is asked to do.

    The issue is eligible when all of these hold:
    - the key looks like PROJECT-123 and the project is in policy.jira.allowedProjects
    - the status is policy.jira.readyStatus
    - it has the label policy.jira.requiredLabel
    - the issue type is in policy.jira.allowedIssueTypes

    Returns an object with Eligible and Reasons (why not). Summary and Description are
    cleaned of control characters and capped at the policy's lengths.

.EXAMPLE
    $ticket = Get-AgentTicket -IssueKey 'DEVOPS-42' -Policy (Get-AgentPolicy)
    if (-not $ticket.Eligible) { $ticket.Reasons }
#>
function Get-AgentTicket {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $IssueKey,
        [Parameter(Mandatory)] [pscustomobject] $Policy
    )
    # The key goes into a URL path, so it must match the Jira key format exactly.
    if ($IssueKey -cnotmatch '^[A-Z][A-Z0-9]{1,9}-[1-9][0-9]{0,6}\z') {
        throw "Not a Jira issue key: '$IssueKey'."
    }
    $project = $IssueKey.Split('-')[0]
    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($project -cnotin @($Policy.jira.allowedProjects)) {
        # Stop before calling Jira: the agent never reads projects it is not allowed to touch.
        $reasons.Add("Project $project is not in the allowed list.")
        return [pscustomobject] @{
            Key = $IssueKey; Project = $project; Summary = ''; Description = ''; IssueType = ''
            Status = ''; Labels = @(); Eligible = $false; Reasons = @($reasons)
        }
    }

    $issue = Invoke-JiraApi -Method GET -Path "/rest/api/3/issue/$($IssueKey)?fields=summary,description,status,labels,issuetype"
    $fields = $issue.fields
    $status = [string] $fields.status.name
    $labels = @($fields.labels | ForEach-Object { [string] $_ })
    $issueType = [string] $fields.issuetype.name

    if ($status -ne $Policy.jira.readyStatus) {
        $reasons.Add("Status is '$status', expected '$($Policy.jira.readyStatus)'.")
    }
    if ($Policy.jira.requiredLabel -cnotin $labels) {
        $reasons.Add("Label '$($Policy.jira.requiredLabel)' is missing.")
    }
    if ($issueType -notin @($Policy.jira.allowedIssueTypes)) {
        $reasons.Add("Issue type '$issueType' is not allowed.")
    }
    $summary = Format-UntrustedText -Text ([string] $fields.summary) -MaxLength $Policy.jira.maxSummaryLength
    if ([string]::IsNullOrWhiteSpace($summary)) {
        $reasons.Add('Summary is empty.')
    }
    $description = Format-UntrustedText -Text (ConvertFrom-AdfText -Node $fields.description) -MaxLength $Policy.jira.maxDescriptionLength

    [pscustomobject] @{
        Key         = $IssueKey
        Project     = $project
        Summary     = $summary
        Description = $description.Trim()
        IssueType   = $issueType
        Status      = $status
        Labels      = $labels
        Eligible    = ($reasons.Count -eq 0)
        Reasons     = @($reasons)
    }
}
