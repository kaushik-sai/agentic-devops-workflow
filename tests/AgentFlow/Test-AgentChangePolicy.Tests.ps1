BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'AgentFlow.TestHelpers.ps1')
    Import-AgentFlowModule
    $script:policy = Get-TestPolicy

    # Builds a repo whose main branch holds the protected files, then switches to a work branch.
    function New-PolicyRepo {
        [CmdletBinding(SupportsShouldProcess)]
        [OutputType([string])]
        param()
        $repo = Initialize-GitFixture
        if ($PSCmdlet.ShouldProcess($repo, 'Seed repo')) {
            Add-FixtureFile -RepoPath $repo -RelativePath 'src/app.ps1' -Content "one`ntwo`n"
            Add-FixtureFile -RepoPath $repo -RelativePath '.github/workflows/x.yml' -Content "on: push`n"
            Add-FixtureFile -RepoPath $repo -RelativePath 'CLAUDE.md' -Content "rules`n"
            Add-FixtureFile -RepoPath $repo -RelativePath 'modules/AgentFlow/policy.json' -Content "{}`n"
            Add-FixtureFile -RepoPath $repo -RelativePath 'a/b/.env' -Content "X=1`n"
            Add-FixtureCommit -RepoPath $repo -Message 'Initial commit' | Out-Null
            git -C $repo checkout --quiet -b agent/DEVOPS-42-x
        }
        $repo
    }
}

AfterAll {
    Remove-Module AgentFlow -ErrorAction SilentlyContinue
}

Describe 'Test-AgentChangePolicy: committed mode' {
    BeforeEach {
        $script:repo = New-PolicyRepo
    }
    AfterEach { Remove-TempFolder -Path $repo }

    It 'is compliant for changes under src' {
        Add-FixtureFile -RepoPath $repo -RelativePath 'src/new.ps1' -Content "a`nb`nc`n"
        Add-FixtureFile -RepoPath $repo -RelativePath 'tests/new.Tests.ps1' -Content "d`n"
        Add-FixtureCommit -RepoPath $repo -Message 'Work' | Out-Null
        $report = Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy
        $report.Compliant | Should -BeTrue
        $report.Violations | Should -HaveCount 0
        $report.Files | Should -HaveCount 2
        $report.Lines | Should -Be 4
    }

    It 'is compliant when nothing changed' {
        $report = Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy
        $report.Compliant | Should -BeTrue
        $report.Files | Should -HaveCount 0
        $report.Lines | Should -Be 0
    }

    It 'flags a change to <Path>' -ForEach @(
        @{ Path = '.github/workflows/x.yml' }
        @{ Path = 'CLAUDE.md' }
        @{ Path = 'modules/AgentFlow/policy.json' }
        @{ Path = 'a/b/.env' }
    ) {
        Add-FixtureFile -RepoPath $repo -RelativePath $Path -Content "changed`n"
        Add-FixtureCommit -RepoPath $repo -Message 'Touch protected' | Out-Null
        $report = Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy
        $report.Compliant | Should -BeFalse
        $report.Violations | Should -HaveCount 1
        $report.Violations[0] | Should -Be "Protected path changed: $Path"
    }

    It 'flags a new protected file such as <Path>' -ForEach @(
        @{ Path = '.claude/settings.json' }
        @{ Path = 'CODEOWNERS' }
        @{ Path = 'deploy/server.pem' }
        @{ Path = 'x/y/id.key' }
        @{ Path = '.env.local' }
        @{ Path = 'PSScriptAnalyzerSettings.psd1' }
    ) {
        Add-FixtureFile -RepoPath $repo -RelativePath $Path
        Add-FixtureCommit -RepoPath $repo -Message 'Add protected' | Out-Null
        (Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy).Compliant | Should -BeFalse
    }

    It 'flags moving a protected file away (a rename is a delete plus an add)' {
        git -C $repo mv .github/workflows/x.yml src/x.yml
        Add-FixtureCommit -RepoPath $repo -Message 'Move workflow' | Out-Null
        $report = Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy
        $report.Compliant | Should -BeFalse
        $report.Violations | Should -Contain 'Protected path changed: .github/workflows/x.yml'
    }

    It 'flags deleting a protected file' {
        git -C $repo rm --quiet CLAUDE.md
        Add-FixtureCommit -RepoPath $repo -Message 'Delete rules' | Out-Null
        (Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy).Violations | Should -Contain 'Protected path changed: CLAUDE.md'
    }

    It 'does not flag look-alike paths' {
        Add-FixtureFile -RepoPath $repo -RelativePath 'src/environment.ps1'
        Add-FixtureFile -RepoPath $repo -RelativePath 'docs/CLAUDE.md.txt'
        Add-FixtureFile -RepoPath $repo -RelativePath 'src/github/notes.md'
        Add-FixtureCommit -RepoPath $repo -Message 'Look-alikes' | Out-Null
        (Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy).Compliant | Should -BeTrue
    }

    It 'flags more files than the limit' {
        $small = Get-TestPolicy
        $small.changes.maxFilesChanged = 2
        foreach ($n in 1..3) { Add-FixtureFile -RepoPath $repo -RelativePath "src/f$n.ps1" }
        Add-FixtureCommit -RepoPath $repo -Message 'Three files' | Out-Null
        $report = Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $small
        $report.Compliant | Should -BeFalse
        $report.Violations | Should -HaveCount 1
        $report.Violations[0] | Should -Match 'Too many files changed: 3 \(limit 2\)'
    }

    It 'accepts exactly the file limit' {
        $small = Get-TestPolicy
        $small.changes.maxFilesChanged = 3
        foreach ($n in 1..3) { Add-FixtureFile -RepoPath $repo -RelativePath "src/f$n.ps1" }
        Add-FixtureCommit -RepoPath $repo -Message 'Three files' | Out-Null
        (Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $small).Compliant | Should -BeTrue
    }

    It 'flags more changed lines than the limit (added plus removed)' {
        $small = Get-TestPolicy
        $small.changes.maxLinesChanged = 5
        # 2 lines removed from app.ps1, 4 lines added = 6.
        Add-FixtureFile -RepoPath $repo -RelativePath 'src/app.ps1' -Content "w`nx`ny`nz`n"
        Add-FixtureCommit -RepoPath $repo -Message 'Rewrite' | Out-Null
        $report = Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $small
        $report.Lines | Should -Be 6
        $report.Compliant | Should -BeFalse
        $report.Violations[0] | Should -Match 'Too many lines changed: 6 \(limit 5\)'
    }

    It 'counts a binary file as a file but not as lines' {
        [System.IO.File]::WriteAllBytes((Join-Path -Path $repo -ChildPath 'src/blob.bin'), [byte[]] (0, 1, 2, 0, 255))
        Add-FixtureCommit -RepoPath $repo -Message 'Binary' | Out-Null
        $report = Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy
        $report.Files | Should -Contain 'src/blob.bin'
        $report.Lines | Should -Be 0
    }

    It 'reports every kind of violation together' {
        $small = Get-TestPolicy
        $small.changes.maxFilesChanged = 1
        $small.changes.maxLinesChanged = 1
        Add-FixtureFile -RepoPath $repo -RelativePath 'CLAUDE.md' -Content "a`nb`n"
        Add-FixtureFile -RepoPath $repo -RelativePath 'src/z.ps1' -Content "a`nb`n"
        Add-FixtureCommit -RepoPath $repo -Message 'Everything' | Out-Null
        (Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $small).Violations | Should -HaveCount 3
    }

    It 'throws when the base ref does not exist' {
        { Test-AgentChangePolicy -RepoPath $repo -BaseRef 'no-such-ref' -Policy $policy } | Should -Throw -ExpectedMessage 'git diff failed*'
    }
}

Describe 'Test-AgentChangePolicy: staged mode' {
    BeforeEach {
        $script:repo = New-PolicyRepo
    }
    AfterEach { Remove-TempFolder -Path $repo }

    It 'sees staged changes that committed mode does not' {
        Add-FixtureFile -RepoPath $repo -RelativePath 'CLAUDE.md' -Content "changed`n"
        git -C $repo add -A
        $staged = Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy -Staged
        $committed = Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy
        $staged.Compliant | Should -BeFalse
        $committed.Compliant | Should -BeTrue
    }

    It 'ignores unstaged changes' {
        Add-FixtureFile -RepoPath $repo -RelativePath 'CLAUDE.md' -Content "changed`n"
        (Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy -Staged).Compliant | Should -BeTrue
    }

    It 'sees a staged rename away from a protected file' {
        git -C $repo mv .github/workflows/x.yml src/x.yml
        $report = Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy -Staged
        $report.Violations | Should -Contain 'Protected path changed: .github/workflows/x.yml'
    }

    It 'is compliant for staged changes under src' {
        Add-FixtureFile -RepoPath $repo -RelativePath 'src/new.ps1'
        git -C $repo add -A
        $report = Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy -Staged
        $report.Compliant | Should -BeTrue
        $report.Files | Should -Be @('src/new.ps1')
    }
}

Describe 'Test-AgentChangePolicy: -ThrowOnViolation' {
    BeforeAll {
        $script:repo = New-PolicyRepo
        Add-FixtureFile -RepoPath $repo -RelativePath '.github/workflows/x.yml' -Content "evil`n"
        Add-FixtureCommit -RepoPath $repo -Message 'Touch workflow' | Out-Null
    }
    AfterAll { Remove-TempFolder -Path $repo }

    It 'throws AgentFlow.PolicyViolation naming the path' {
        { Test-AgentChangePolicy -RepoPath $repo -BaseRef main -Policy $policy -ThrowOnViolation } |
            Should -Throw -ErrorId 'AgentFlow.PolicyViolation*' -ExpectedMessage '*.github/workflows/x.yml*'
    }

    It 'does not throw when the changes are compliant' {
        $clean = New-PolicyRepo
        try {
            Add-FixtureFile -RepoPath $clean -RelativePath 'src/ok.ps1'
            Add-FixtureCommit -RepoPath $clean -Message 'Fine' | Out-Null
            { Test-AgentChangePolicy -RepoPath $clean -BaseRef main -Policy $policy -ThrowOnViolation } | Should -Not -Throw
        }
        finally { Remove-TempFolder -Path $clean }
    }
}

Describe 'ConvertTo-PathRegex (protected path globs)' {
    It 'matches <Path> against <Glob>: <Expected>' -ForEach @(
        @{ Glob = '.github/**'; Path = '.github/workflows/x.yml'; Expected = $true }
        @{ Glob = '.github/**'; Path = 'src/.github/x.yml'; Expected = $false }
        @{ Glob = '**/.env'; Path = '.env'; Expected = $true }
        @{ Glob = '**/.env'; Path = 'a/b/.env'; Expected = $true }
        @{ Glob = '**/.env'; Path = 'a/b/xenv'; Expected = $false }
        @{ Glob = '**/*.pem'; Path = 'k.pem'; Expected = $true }
        @{ Glob = '**/*.pem'; Path = 'a/k.pem'; Expected = $true }
        @{ Glob = '**/*.pem'; Path = 'a/k.pem.txt'; Expected = $false }
        @{ Glob = 'CLAUDE.md'; Path = 'CLAUDE.md'; Expected = $true }
        @{ Glob = 'CLAUDE.md'; Path = 'CLAUDEXmd'; Expected = $false }
        @{ Glob = '*.key'; Path = 'a.key'; Expected = $true }
        @{ Glob = '*.key'; Path = 'dir/a.key'; Expected = $false }
        @{ Glob = 'a?.txt'; Path = 'ab.txt'; Expected = $true }
        @{ Glob = 'a?.txt'; Path = 'a/.txt'; Expected = $false }
    ) {
        InModuleScope AgentFlow -Parameters $_ {
            ($Path -match (ConvertTo-PathRegex -Glob $Glob)) | Should -Be $Expected
        }
    }
}
