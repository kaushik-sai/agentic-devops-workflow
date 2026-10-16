Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Builds the branch name for a ticket: <prefix><KEY>-<slug>, for example agent/DEVOPS-42-add-health-endpoint.

.DESCRIPTION
    The slug is the summary in lower case, ASCII letters and digits only, words joined
    by hyphens and cut at a word boundary within policy.branch.maxSlugLength.
    The same ticket always gets the same name, so a rerun finds the branch it made before.

.EXAMPLE
    New-AgentBranchName -IssueKey 'DEVOPS-42' -Summary 'Add a /health endpoint' -Policy (Get-AgentPolicy)
#>
function New-AgentBranchName {
    # Builds a string only; nothing is created, so there is nothing for -WhatIf to skip.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidatePattern('(?-i)^[A-Z][A-Z0-9]{1,9}-[1-9][0-9]{0,6}\z')] [string] $IssueKey,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Summary,
        [Parameter(Mandatory)] [pscustomobject] $Policy
    )
    # Drop accents first (e acute becomes e), then anything that is not a letter or digit.
    $normalized = $Summary.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    $words = @(($normalized.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim() -split '\s+' | Where-Object { $_ })
    $slug = ''
    foreach ($word in $words) {
        $candidate = if ($slug) { "$slug-$word" } else { $word }
        if ($candidate.Length -gt $Policy.branch.maxSlugLength) { break }
        $slug = $candidate
    }
    # One very long first word: cut it rather than leave the slug empty.
    if (-not $slug -and $words.Count -gt 0) {
        $slug = $words[0].Substring(0, [Math]::Min($words[0].Length, $Policy.branch.maxSlugLength))
    }
    if ($slug) { "$($Policy.branch.prefix)$IssueKey-$slug" } else { "$($Policy.branch.prefix)$IssueKey" }
}
