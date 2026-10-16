Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Counts the fix attempts already made on the branch.

.DESCRIPTION
    Every fix commit carries a trailer such as "Agent-Fix-Attempt: 2". The count is the
    number of commits between the base and HEAD that have the trailer, so the limit lives
    in git history: it survives reruns and cannot be reset by relabelling the PR.

.EXAMPLE
    Get-FixAttempt -RepoPath . -BaseRef origin/main -Trailer 'Agent-Fix-Attempt'
#>
function Get-FixAttempt {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [string] $RepoPath,
        [Parameter(Mandatory)] [string] $BaseRef,
        [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z][A-Za-z0-9-]*$')] [string] $Trailer
    )
    $result = Invoke-Git -RepoPath $RepoPath -Arguments @(
        'log', ('--format=%(trailers:key=' + $Trailer + ',valueonly)--end-of-commit--'), "$BaseRef..HEAD"
    )
    if ($result.ExitCode -ne 0) {
        throw "git log failed: $($result.Output -join ' ')"
    }
    # One record per commit, ended by a printable marker (git output loses control characters); a record with a value is a fix commit.
    $records = (($result.Output -join "`n") -split '--end-of-commit--') | Where-Object { $_.Trim() }
    @($records).Count
}
