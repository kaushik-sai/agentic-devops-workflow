BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'AgentFlow.TestHelpers.ps1')
    Import-AgentFlowModule

    # Makes Invoke-Gh return the given lines; the module-scope mock gets them as a closure.
    function Set-GhResponse {
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)] [string[]] $Output,
            [int] $ExitCode = 0
        )
        if ($PSCmdlet.ShouldProcess('Invoke-Gh', 'Mock response')) {
            $response = [pscustomobject] @{ ExitCode = $ExitCode; Output = $Output }
            Mock -ModuleName AgentFlow Invoke-Gh -MockWith { $response }.GetNewClosure()
        }
    }
}

AfterAll {
    Remove-Module AgentFlow -ErrorAction SilentlyContinue
}

Describe 'Get-CiFailureLog' {
    It 'returns the log unchanged when it fits' {
        Set-GhResponse -Output @('step 1', 'Error: test failed')
        Get-CiFailureLog -RunId 123 -Repository 'o/r' -MaxBytes 1000 | Should -BeExactly "step 1`nError: test failed"
    }

    It 'calls gh run view --log-failed for the run and repository' {
        Set-GhResponse -Output @('x')
        Get-CiFailureLog -RunId 987654321 -Repository 'kaushik-sai/agentic-devops-workflow' -MaxBytes 1000 | Out-Null
        Should -Invoke -ModuleName AgentFlow Invoke-Gh -Times 1 -Exactly -ParameterFilter {
            ($Arguments -join ' ') -eq 'run view 987654321 --repo kaushik-sai/agentic-devops-workflow --log-failed'
        }
    }

    It 'keeps the tail and marks the cut when the log is over MaxBytes' {
        $lines = 1..50 | ForEach-Object { "line-{0:D3}" -f $_ }
        Set-GhResponse -Output $lines
        $log = Get-CiFailureLog -RunId 1 -Repository 'o/r' -MaxBytes 30
        $log | Should -BeLike "[[]earlier lines cut]*"
        $log | Should -BeLike '*line-050'
        $log | Should -Not -BeLike '*line-001*'
        # Marker line plus exactly MaxBytes characters of tail.
        $log.Length | Should -Be ('[earlier lines cut]'.Length + 1 + 30)
    }

    It 'does not add the marker when the log is exactly MaxBytes' {
        Set-GhResponse -Output @('abcdefghij')
        Get-CiFailureLog -RunId 1 -Repository 'o/r' -MaxBytes 10 | Should -BeExactly 'abcdefghij'
    }

    It 'masks a GitHub token' {
        $token = Get-FakeGitHubToken
        Set-GhResponse -Output @("fatal: auth with $token failed")
        $log = Get-CiFailureLog -RunId 1 -Repository 'o/r' -MaxBytes 1000
        $log | Should -Not -Match 'ghp_'
        $log | Should -BeExactly 'fatal: auth with [redacted] failed'
    }

    It 'masks a token before cutting, so half a token cannot survive at the cut' {
        $token = Get-FakeGitHubToken
        Set-GhResponse -Output @("start $token end")
        # Cut inside where the token would have been: nothing of it may remain.
        $log = Get-CiFailureLog -RunId 1 -Repository 'o/r' -MaxBytes 12
        $log | Should -Not -Match 'a1B2c3D4'
    }

    It 'removes control characters from the log' {
        Set-GhResponse -Output @("ok$([char] 0x1B)[0m done")
        Get-CiFailureLog -RunId 1 -Repository 'o/r' -MaxBytes 1000 | Should -BeExactly 'ok[0m done'
    }

    It 'throws when gh exits non-zero' {
        Set-GhResponse -Output @('HTTP 404: Not Found') -ExitCode 1
        { Get-CiFailureLog -RunId 1 -Repository 'o/r' -MaxBytes 1000 } | Should -Throw -ExpectedMessage 'gh run view failed: HTTP 404*'
    }

    It 'rejects <Repository> as a repository' -ForEach @(
        @{ Repository = 'no-slash' }
        @{ Repository = 'o/r; rm -rf /' }
        @{ Repository = 'a/b/c' }
    ) {
        Set-GhResponse -Output @('x')
        { Get-CiFailureLog -RunId 1 -Repository $Repository -MaxBytes 1000 } | Should -Throw
        Should -Invoke -ModuleName AgentFlow Invoke-Gh -Times 0 -Exactly
    }

    It 'rejects a run id of zero' {
        { Get-CiFailureLog -RunId 0 -Repository 'o/r' -MaxBytes 1000 } | Should -Throw
    }
}
