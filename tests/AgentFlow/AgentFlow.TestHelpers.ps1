Set-StrictMode -Version Latest

# Shared helpers for the AgentFlow tests. Not a test file itself
# (Pester only runs *.Tests.ps1); test files dot-source it in BeforeAll.

# Imports the module under test from the repo, fresh each time.
function Import-AgentFlowModule {
    [CmdletBinding()]
    param()
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'modules', 'AgentFlow'
    Import-Module $modulePath -Force
}

# Reads the real policy.json as an object. Tests change a copy to get small limits.
function Get-TestPolicy {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $path = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'modules', 'AgentFlow', 'policy.json'
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

# Reads the recorded Jira response for DEVOPS-42. A fresh object each call, so tests can edit it.
function Get-TestIssue {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $path = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures' -AdditionalChildPath 'jira-issue-DEVOPS-42.json'
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

# A ticket object shaped like the output of Get-AgentTicket.
function New-TestTicket {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string] $Summary = 'Add a /health endpoint',
        [string] $Description = 'Expose GET /health.'
    )
    if ($PSCmdlet.ShouldProcess('ticket', 'Create test object')) {
        [pscustomobject] @{
            Key = 'DEVOPS-42'; Project = 'DEVOPS'; Summary = $Summary; Description = $Description
            IssueType = 'Task'; Status = 'Ready for Agent'; Labels = @('agent-ok')
            Eligible = $true; Reasons = @()
        }
    }
}

# Builds a token-shaped string at run time, so no token-like literal sits in the source.
function Get-FakeGitHubToken {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    'ghp_' + ('a1B2c3D4' * 5)
}

# Creates an empty folder under the system temp folder and returns its path.
function Initialize-TempFolder {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()
    $path = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('agentflow-test-' + [guid]::NewGuid().ToString('N'))
    if ($PSCmdlet.ShouldProcess($path, 'Create temp folder')) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
    return $path
}

# Creates a throwaway Git repo with branch main and a local test identity,
# so tests never depend on (or change) the machine's git config.
function Initialize-GitFixture {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()
    $path = Initialize-TempFolder
    if ($PSCmdlet.ShouldProcess($path, 'git init')) {
        git -C $path init --quiet -b main
        git -C $path config user.name 'Test User'
        git -C $path config user.email 'test@example.com'
        git -C $path config commit.gpgsign false
    }
    return $path
}

# Writes a file (creating folders) inside the repo. Line endings are LF.
function Add-FixtureFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $RepoPath,
        [Parameter(Mandatory)] [string] $RelativePath,
        [string] $Content = "line`n"
    )
    $full = Join-Path -Path $RepoPath -ChildPath $RelativePath
    if ($PSCmdlet.ShouldProcess($full, 'Write fixture file')) {
        New-Item -ItemType Directory -Path (Split-Path -Path $full -Parent) -Force | Out-Null
        Set-Content -LiteralPath $full -Value $Content -NoNewline
    }
}

# Stages everything and commits. Each -Trailer becomes its own message paragraph, which git reads as a trailer.
# --allow-empty so a commit with only a trailer still works.
function Add-FixtureCommit {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $RepoPath,
        [Parameter(Mandatory)] [string] $Message,
        [string[]] $Trailer = @()
    )
    if ($PSCmdlet.ShouldProcess($RepoPath, 'git commit')) {
        git -C $RepoPath add -A
        $commitArgs = @('commit', '--quiet', '--allow-empty', '-m', $Message)
        foreach ($line in $Trailer) { $commitArgs += @('-m', $line) }
        git -C $RepoPath @commitArgs
    }
    return (git -C $RepoPath rev-parse HEAD)
}

# Deletes a temp folder. -Force because git marks object files read-only on Windows.
function Remove-TempFolder {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Path)
    if ((Test-Path -Path $Path) -and $PSCmdlet.ShouldProcess($Path, 'Delete temp folder')) {
        Remove-Item -Path $Path -Recurse -Force
    }
}
