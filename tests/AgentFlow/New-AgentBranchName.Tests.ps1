BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'AgentFlow.TestHelpers.ps1')
    Import-AgentFlowModule
    $script:policy = Get-TestPolicy
}

AfterAll {
    Remove-Module AgentFlow -ErrorAction SilentlyContinue
}

Describe 'New-AgentBranchName' {
    It 'builds prefix + key + slug' {
        New-AgentBranchName -IssueKey 'DEVOPS-42' -Summary 'Add a /health endpoint' -Policy $policy |
            Should -BeExactly 'agent/DEVOPS-42-add-a-health-endpoint'
    }

    It 'is deterministic: the same ticket always gets the same name' {
        $first = New-AgentBranchName -IssueKey 'DEVOPS-42' -Summary 'Add a /health endpoint' -Policy $policy
        $second = New-AgentBranchName -IssueKey 'DEVOPS-42' -Summary 'Add a /health endpoint' -Policy $policy
        $second | Should -BeExactly $first
    }

    It 'turns <Summary> into the slug <Slug>' -ForEach @(
        @{ Summary = 'Fix: CRASH on Start-Up!!'; Slug = 'fix-crash-on-start-up' }
        @{ Summary = '  spaces   everywhere  '; Slug = 'spaces-everywhere' }
        @{ Summary = 'Crème brûlée ÀÉÎÕÜ'; Slug = 'creme-brulee-aeiou' }
        @{ Summary = 'path/../traversal; rm -rf'; Slug = 'path-traversal-rm-rf' }
        @{ Summary = 'v2.0 release'; Slug = 'v2-0-release' }
    ) {
        New-AgentBranchName -IssueKey 'DEVOPS-1' -Summary $Summary -Policy $policy |
            Should -BeExactly "agent/DEVOPS-1-$Slug"
    }

    It 'only produces ASCII letters, digits, hyphens and one slash' {
        $name = New-AgentBranchName -IssueKey 'DEVOPS-9' -Summary 'Ünïcode 日本語 "quotes" $(whoami) `tick`' -Policy $policy
        $name | Should -Match '^agent/DEVOPS-9(-[a-z0-9]+)*$'
    }

    It 'cuts the slug at a word boundary within the maximum length' {
        # 10 words of 5 letters: 'aaaaa-bbbbb-...'. 40 chars allow 6 words (6*5+5 = 35); a 7th would be 41.
        $summary = 'aaaaa bbbbb ccccc ddddd eeeee fffff ggggg hhhhh iiiii jjjjj'
        $name = New-AgentBranchName -IssueKey 'DEVOPS-3' -Summary $summary -Policy $policy
        $name | Should -BeExactly 'agent/DEVOPS-3-aaaaa-bbbbb-ccccc-ddddd-eeeee-fffff'
        $slug = $name -replace '^agent/DEVOPS-3-', ''
        $slug.Length | Should -BeLessOrEqual $policy.branch.maxSlugLength
    }

    It 'keeps a slug of exactly the maximum length' {
        $custom = Get-TestPolicy
        $custom.branch.maxSlugLength = 11
        New-AgentBranchName -IssueKey 'DEVOPS-3' -Summary 'hello world and more' -Policy $custom |
            Should -BeExactly 'agent/DEVOPS-3-hello-world'
    }

    It 'returns prefix + key when the summary is empty or has no usable characters' -ForEach @(
        @{ Summary = '' }
        @{ Summary = '   ' }
        @{ Summary = '!!! ??? ...' }
        @{ Summary = '日本語' }
    ) {
        New-AgentBranchName -IssueKey 'DEVOPS-5' -Summary $Summary -Policy $policy |
            Should -BeExactly 'agent/DEVOPS-5'
    }

    It 'cuts one huge first word instead of returning an empty slug' {
        $name = New-AgentBranchName -IssueKey 'DEVOPS-6' -Summary ('x' * 100) -Policy $policy
        $name | Should -BeExactly ('agent/DEVOPS-6-' + ('x' * $policy.branch.maxSlugLength))
    }

    It 'uses the prefix from the policy' {
        $custom = Get-TestPolicy
        $custom.branch.prefix = 'bot/'
        New-AgentBranchName -IssueKey 'DEVOPS-8' -Summary 'Hello' -Policy $custom | Should -BeExactly 'bot/DEVOPS-8-hello'
    }

    It 'rejects a malformed key' -ForEach @(
        @{ Key = 'devops-1' }
        @{ Key = 'DEVOPS-1/../x' }
        @{ Key = 'DEVOPS-0' }
        @{ Key = "DEVOPS-1`n" }
    ) {
        { New-AgentBranchName -IssueKey $Key -Summary 'x' -Policy $policy } | Should -Throw
    }
}
