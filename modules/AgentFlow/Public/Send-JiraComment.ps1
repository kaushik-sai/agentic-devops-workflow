Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Adds a plain-text comment to a Jira issue, with an optional link.

.EXAMPLE
    Send-JiraComment -IssueKey 'DEVOPS-42' -Text 'Draft PR opened by the agent.' -LinkUrl 'https://github.com/o/r/pull/7'
#>
function Send-JiraComment {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidatePattern('(?-i)^[A-Z][A-Z0-9]{1,9}-[1-9][0-9]{0,6}\z')] [string] $IssueKey,
        [Parameter(Mandatory)] [string] $Text,
        [ValidatePattern('^https://')] [string] $LinkUrl
    )
    $content = @(@{ type = 'text'; text = (Protect-SecretText -Text $Text) })
    if ($LinkUrl) {
        $content += @{ type = 'text'; text = ' ' }
        $content += @{ type = 'text'; text = $LinkUrl; marks = @(@{ type = 'link'; attrs = @{ href = $LinkUrl } }) }
    }
    # Jira Cloud v3 takes comments in Atlassian Document Format.
    $body = @{
        body = @{
            type    = 'doc'
            version = 1
            content = @(@{ type = 'paragraph'; content = $content })
        }
    }
    if ($PSCmdlet.ShouldProcess($IssueKey, 'Add Jira comment')) {
        Invoke-JiraApi -Method POST -Path "/rest/api/3/issue/$IssueKey/comment" -Body $body | Out-Null
    }
}
