BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'AgentFlow.TestHelpers.ps1')
    Import-AgentFlowModule
}

AfterAll {
    Remove-Module AgentFlow -ErrorAction SilentlyContinue
}

Describe 'Get-FixAttempt' {
    BeforeAll {
        $repo = Initialize-GitFixture
        Add-FixtureFile -RepoPath $repo -RelativePath 'README.md'
        Add-FixtureCommit -RepoPath $repo -Message 'Initial commit' | Out-Null
        git -C $repo checkout --quiet -b agent/DEVOPS-42-x
    }
    AfterAll { Remove-TempFolder -Path $repo }

    It 'returns 0 when the branch has no commits of its own' {
        Get-FixAttempt -RepoPath $repo -BaseRef main -Trailer 'Agent-Fix-Attempt' | Should -Be 0
    }

    It 'counts only the commits that carry the trailer' {
        Add-FixtureFile -RepoPath $repo -RelativePath 'src/a.ps1'
        Add-FixtureCommit -RepoPath $repo -Message 'Implement DEVOPS-42' | Out-Null
        Add-FixtureFile -RepoPath $repo -RelativePath 'src/b.ps1'
        Add-FixtureCommit -RepoPath $repo -Message 'Fix CI' -Trailer 'Agent-Fix-Attempt: 1' | Out-Null
        Add-FixtureFile -RepoPath $repo -RelativePath 'src/c.ps1'
        Add-FixtureCommit -RepoPath $repo -Message 'Fix CI again' -Trailer 'Agent-Fix-Attempt: 2' | Out-Null
        Get-FixAttempt -RepoPath $repo -BaseRef main -Trailer 'Agent-Fix-Attempt' | Should -Be 2
    }

    It 'ignores a different trailer key' {
        Get-FixAttempt -RepoPath $repo -BaseRef main -Trailer 'Other-Trailer' | Should -Be 0
    }

    It 'does not count the trailer text when it is only in the commit subject' {
        Add-FixtureCommit -RepoPath $repo -Message 'Agent-Fix-Attempt: 9' | Out-Null
        Get-FixAttempt -RepoPath $repo -BaseRef main -Trailer 'Agent-Fix-Attempt' | Should -Be 2
    }

    It 'returns an int' {
        (Get-FixAttempt -RepoPath $repo -BaseRef main -Trailer 'Agent-Fix-Attempt') | Should -BeOfType ([int])
    }

    It 'throws when the base ref does not exist' {
        { Get-FixAttempt -RepoPath $repo -BaseRef 'no-such-ref' -Trailer 'Agent-Fix-Attempt' } | Should -Throw -ExpectedMessage 'git log failed*'
    }

    It 'rejects a trailer name with unsafe characters' {
        { Get-FixAttempt -RepoPath $repo -BaseRef main -Trailer 'a,b' } | Should -Throw
    }
}
