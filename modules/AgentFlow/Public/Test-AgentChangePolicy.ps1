Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Checks the agent's changes against the policy: no protected paths, and a bounded size.

.DESCRIPTION
    Compares -BaseRef with HEAD (committed changes, as CI sees a PR) or, with -Staged,
    with the index (before the workflow commits). Fails when:
    - a changed path matches policy.changes.protectedPaths (workflows, CODEOWNERS,
      CLAUDE.md, the policy itself, key files), including renames away from them
    - more than policy.changes.maxFilesChanged files changed
    - more than policy.changes.maxLinesChanged lines were added plus removed

    Returns an object with Compliant, Violations, Files and Lines. With -ThrowOnViolation
    it throws AgentFlow.PolicyViolation instead, so a workflow step fails.

.EXAMPLE
    git add -A; Test-AgentChangePolicy -RepoPath . -BaseRef origin/main -Policy (Get-AgentPolicy) -Staged -ThrowOnViolation
#>
function Test-AgentChangePolicy {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $RepoPath,
        [Parameter(Mandatory)] [string] $BaseRef,
        [Parameter(Mandatory)] [pscustomobject] $Policy,
        [switch] $Staged,
        [switch] $ThrowOnViolation
    )
    # --no-renames lists a rename as delete + add, so moving a protected file is caught too.
    $diffArgs = @('diff', '--numstat', '--no-renames', '-z')
    $diffArgs += if ($Staged) { @('--cached', $BaseRef) } else { @("$BaseRef...HEAD") }
    $result = Invoke-Git -RepoPath $RepoPath -Arguments $diffArgs
    if ($result.ExitCode -ne 0) {
        throw "git diff failed: $($result.Output -join ' ')"
    }

    # -z output: "added<TAB>removed<TAB>path" records separated by NUL. Binary files show "-".
    $files = [System.Collections.Generic.List[string]]::new()
    $lines = 0
    foreach ($record in (($result.Output -join "`n") -split [char] 0)) {
        $record = $record.Trim("`n")
        if (-not $record) { continue }
        $parts = $record -split "`t", 3
        if ($parts.Count -lt 3) { continue }
        $files.Add($parts[2])
        foreach ($count in $parts[0], $parts[1]) {
            if ($count -match '^\d+$') { $lines += [int] $count }
        }
    }

    $violations = [System.Collections.Generic.List[string]]::new()
    $patterns = @($Policy.changes.protectedPaths | ForEach-Object { ConvertTo-PathRegex -Glob $_ })
    foreach ($file in $files) {
        foreach ($pattern in $patterns) {
            if ($file -match $pattern) {
                $violations.Add("Protected path changed: $file")
                break
            }
        }
    }
    if ($files.Count -gt $Policy.changes.maxFilesChanged) {
        $violations.Add("Too many files changed: $($files.Count) (limit $($Policy.changes.maxFilesChanged)).")
    }
    if ($lines -gt $Policy.changes.maxLinesChanged) {
        $violations.Add("Too many lines changed: $lines (limit $($Policy.changes.maxLinesChanged)).")
    }

    $report = [pscustomobject] @{
        Compliant  = ($violations.Count -eq 0)
        Violations = @($violations)
        Files      = @($files)
        Lines      = $lines
    }
    if ($ThrowOnViolation -and -not $report.Compliant) {
        $message = "Agent change policy: $($violations.Count) violation(s).`n" + ($violations -join "`n")
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new($message), 'AgentFlow.PolicyViolation',
            [System.Management.Automation.ErrorCategory]::PermissionDenied, $RepoPath)
        $PSCmdlet.ThrowTerminatingError($record)
    }
    $report
}
