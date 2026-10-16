Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Reads the agent policy (policy.json next to the module, or -Path).

.EXAMPLE
    $policy = Get-AgentPolicy
    $policy.fixLoop.maxAttempts
#>
function Get-AgentPolicy {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Path = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'policy.json')
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Policy file not found: $Path"
    }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}
