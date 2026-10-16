BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'AgentFlow.TestHelpers.ps1')
    Import-AgentFlowModule
}

AfterAll {
    Remove-Module AgentFlow -ErrorAction SilentlyContinue
}

Describe 'Send-JiraComment' {
    BeforeEach {
        Mock -ModuleName AgentFlow Invoke-JiraApi { }
    }

    It 'POSTs to the comment path of the issue' {
        Send-JiraComment -IssueKey 'DEVOPS-42' -Text 'Hello'
        Should -Invoke -ModuleName AgentFlow Invoke-JiraApi -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Path -ceq '/rest/api/3/issue/DEVOPS-42/comment'
        }
    }

    It 'sends an ADF document with one paragraph holding the text' {
        Send-JiraComment -IssueKey 'DEVOPS-42' -Text 'Draft PR opened.'
        Should -Invoke -ModuleName AgentFlow Invoke-JiraApi -Times 1 -Exactly -ParameterFilter {
            $Body.body.type -eq 'doc' -and $Body.body.version -eq 1 -and
            $Body.body.content[0].type -eq 'paragraph' -and
            @($Body.body.content[0].content).Count -eq 1 -and
            $Body.body.content[0].content[0].text -ceq 'Draft PR opened.'
        }
    }

    It 'adds the link as a text node with a link mark' {
        Send-JiraComment -IssueKey 'DEVOPS-42' -Text 'PR:' -LinkUrl 'https://github.com/o/r/pull/7'
        Should -Invoke -ModuleName AgentFlow Invoke-JiraApi -Times 1 -Exactly -ParameterFilter {
            $nodes = @($Body.body.content[0].content)
            $nodes.Count -eq 3 -and
            $nodes[2].text -ceq 'https://github.com/o/r/pull/7' -and
            $nodes[2].marks[0].type -eq 'link' -and
            $nodes[2].marks[0].attrs.href -ceq 'https://github.com/o/r/pull/7'
        }
    }

    It 'masks token-like text before sending' {
        Send-JiraComment -IssueKey 'DEVOPS-42' -Text ('failed with ' + (Get-FakeGitHubToken))
        Should -Invoke -ModuleName AgentFlow Invoke-JiraApi -Times 1 -Exactly -ParameterFilter {
            $Body.body.content[0].content[0].text -ceq 'failed with [redacted]'
        }
    }

    It 'makes no call with -WhatIf' {
        Send-JiraComment -IssueKey 'DEVOPS-42' -Text 'Hello' -WhatIf
        Should -Invoke -ModuleName AgentFlow Invoke-JiraApi -Times 0 -Exactly
    }

    It 'rejects <Key> as an issue key' -ForEach @(
        @{ Key = 'devops-1' }
        @{ Key = 'DEVOPS-1/../x' }
        @{ Key = 'DEVOPS-0' }
        @{ Key = "DEVOPS-1`n" }
    ) {
        { Send-JiraComment -IssueKey $Key -Text 'x' } | Should -Throw
        Should -Invoke -ModuleName AgentFlow Invoke-JiraApi -Times 0 -Exactly
    }

    It 'rejects a link that is not https' {
        { Send-JiraComment -IssueKey 'DEVOPS-1' -Text 'x' -LinkUrl 'http://example.com' } | Should -Throw
        { Send-JiraComment -IssueKey 'DEVOPS-1' -Text 'x' -LinkUrl 'javascript:alert(1)' } | Should -Throw
    }
}
