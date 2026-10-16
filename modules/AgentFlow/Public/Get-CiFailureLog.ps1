Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Gets the log of the failed steps of a GitHub Actions run, with secrets masked and the size capped.

.DESCRIPTION
    Uses "gh run view <id> --log-failed" (needs GH_TOKEN with actions: read). The tail is
    kept because that is where the error usually is. GitHub already masks registered
    secrets; Protect-SecretText is a second pass for token-shaped strings it does not know.

.EXAMPLE
    Get-CiFailureLog -RunId 123456789 -Repository 'kaushik-sai/agentic-devops-workflow' -MaxBytes 60000
#>
function Get-CiFailureLog {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateRange(1, [long]::MaxValue)] [long] $RunId,
        [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')] [string] $Repository,
        [Parameter(Mandatory)] [int] $MaxBytes
    )
    $result = Invoke-Gh -Arguments @('run', 'view', "$RunId", '--repo', $Repository, '--log-failed')
    if ($result.ExitCode -ne 0) {
        throw "gh run view failed: $($result.Output -join ' ')"
    }
    $text = Protect-SecretText -Text ($result.Output -join "`n")
    $text = Format-UntrustedText -Text $text -MaxLength ([int]::MaxValue)
    if ($text.Length -gt $MaxBytes) {
        $text = "[earlier lines cut]`n" + $text.Substring($text.Length - $MaxBytes)
    }
    $text
}
