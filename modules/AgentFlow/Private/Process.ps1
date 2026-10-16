Set-StrictMode -Version Latest

# The one place the module runs git. Returns the exit code and the output lines
# so callers decide what a failure means.
function Invoke-Git {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoPath,
        [Parameter(Mandatory)] [string[]] $Arguments
    )
    # -C runs git inside the repo without changing our current directory.
    $output = & git -C $RepoPath @Arguments 2>&1
    [pscustomobject] @{
        ExitCode = $LASTEXITCODE
        Output   = @($output | ForEach-Object { "$_" } | Where-Object { $_ -ne '' })
    }
}

# The one place the module runs the GitHub CLI. GH_TOKEN comes from the caller's environment.
function Invoke-Gh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Arguments
    )
    $output = & gh @Arguments 2>&1
    [pscustomobject] @{
        ExitCode = $LASTEXITCODE
        Output   = @($output | ForEach-Object { "$_" })
    }
}
