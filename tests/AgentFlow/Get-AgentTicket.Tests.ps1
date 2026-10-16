BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'AgentFlow.TestHelpers.ps1')
    Import-AgentFlowModule
}

AfterAll {
    Remove-Module AgentFlow -ErrorAction SilentlyContinue
}

Describe 'Get-AgentTicket: issue key' {
    BeforeAll {
        $script:policy = Get-TestPolicy
        Mock -ModuleName AgentFlow Invoke-JiraApi { }
    }

    It 'rejects the malformed key <Key>' -ForEach @(
        @{ Key = 'devops-1' }             # lower case
        @{ Key = 'DEVOPS-1/../x' }        # path characters would reach the URL
        @{ Key = 'DEVOPS-0' }             # zero is not a Jira number
        @{ Key = 'DEVOPS-01' }            # leading zero
        @{ Key = 'DEVOPS' }
        @{ Key = 'DEVOPS-1?x=1' }
        @{ Key = '1DEVOPS-1' }
        @{ Key = "DEVOPS-1`n" }
    ) {
        { Get-AgentTicket -IssueKey $Key -Policy $policy } | Should -Throw -ExpectedMessage 'Not a Jira issue key*'
        Should -Invoke -ModuleName AgentFlow Invoke-JiraApi -Times 0 -Exactly
    }
}

Describe 'Get-AgentTicket: project allow list' {
    BeforeAll {
        $script:policy = Get-TestPolicy
        Mock -ModuleName AgentFlow Invoke-JiraApi { }
    }

    It 'returns Eligible = $false without calling Jira for a project that is not allowed' {
        $ticket = Get-AgentTicket -IssueKey 'SECRET-7' -Policy $policy
        $ticket.Eligible | Should -BeFalse
        $ticket.Reasons | Should -HaveCount 1
        $ticket.Reasons[0] | Should -Match 'SECRET'
        Should -Invoke -ModuleName AgentFlow Invoke-JiraApi -Times 0 -Exactly
    }
}

Describe 'Get-AgentTicket: eligibility' {
    BeforeAll {
        $script:policy = Get-TestPolicy
        # Mock bodies run inside the module, so the issue is handed over as a closure.
        function Set-IssueResponse {
            [CmdletBinding(SupportsShouldProcess)]
            param([Parameter(Mandatory)] [pscustomobject] $Issue)
            if ($PSCmdlet.ShouldProcess('Invoke-JiraApi', 'Mock response')) {
                $response = $Issue
                Mock -ModuleName AgentFlow Invoke-JiraApi -MockWith { $response }.GetNewClosure()
            }
        }
    }

    It 'accepts the recorded DEVOPS-42 issue and asks Jira for the right path' {
        Set-IssueResponse -Issue (Get-TestIssue)
        $ticket = Get-AgentTicket -IssueKey 'DEVOPS-42' -Policy $policy
        $ticket.Eligible | Should -BeTrue
        $ticket.Reasons | Should -HaveCount 0
        $ticket.Key | Should -Be 'DEVOPS-42'
        $ticket.Project | Should -Be 'DEVOPS'
        $ticket.IssueType | Should -Be 'Task'
        $ticket.Status | Should -Be 'Ready for Agent'
        $ticket.Labels | Should -Contain 'agent-ok'
        $ticket.Summary | Should -Be 'Add a /health endpoint'
        Should -Invoke -ModuleName AgentFlow Invoke-JiraApi -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Path -like '/rest/api/3/issue/DEVOPS-42?fields=*'
        }
    }

    It 'flattens the ADF description to plain text' {
        Set-IssueResponse -Issue (Get-TestIssue)
        $ticket = Get-AgentTicket -IssueKey 'DEVOPS-42' -Policy $policy
        $expected = @(
            'Add health endpoint'
            'Expose GET /health returning 200 and the build version.'
            '- Return JSON'
            '- No auth required'
            '- Add a Pester test'
        ) -join "`n"
        $ticket.Description | Should -BeExactly $expected
    }

    It 'gives a reason when <Name>' -ForEach @(
        @{ Name = 'the status is wrong'; Edit = { param($i) $i.fields.status.name = 'In Progress' }; Reason = "Status is 'In Progress'*" }
        @{ Name = 'the label is missing'; Edit = { param($i) $i.fields.labels = @('backend') }; Reason = "Label 'agent-ok' is missing*" }
        @{ Name = 'the label differs only in case'; Edit = { param($i) $i.fields.labels = @('Agent-OK') }; Reason = "Label 'agent-ok' is missing*" }
        @{ Name = 'the issue type is not allowed'; Edit = { param($i) $i.fields.issuetype.name = 'Epic' }; Reason = "Issue type 'Epic' is not allowed*" }
        @{ Name = 'the summary is empty'; Edit = { param($i) $i.fields.summary = '  ' }; Reason = 'Summary is empty*' }
    ) {
        $issue = Get-TestIssue
        & $Edit $issue
        Set-IssueResponse -Issue $issue
        $ticket = Get-AgentTicket -IssueKey 'DEVOPS-42' -Policy $policy
        $ticket.Eligible | Should -BeFalse
        $ticket.Reasons | Should -HaveCount 1
        $ticket.Reasons[0] | Should -BeLike $Reason
    }

    It 'lists every reason when several rules fail' {
        $issue = Get-TestIssue
        $issue.fields.status.name = 'Done'
        $issue.fields.labels = @()
        $issue.fields.issuetype.name = 'Epic'
        Set-IssueResponse -Issue $issue
        $ticket = Get-AgentTicket -IssueKey 'DEVOPS-42' -Policy $policy
        $ticket.Eligible | Should -BeFalse
        $ticket.Reasons | Should -HaveCount 3
    }

    It 'removes control characters from the summary but keeps normal text' {
        $issue = Get-TestIssue
        $issue.fields.summary = "Fix`0 the`a login$([char] 0x1B)[31m page"
        Set-IssueResponse -Issue $issue
        $ticket = Get-AgentTicket -IssueKey 'DEVOPS-42' -Policy $policy
        $ticket.Summary | Should -BeExactly 'Fix the login[31m page'
    }

    It 'caps an over-long summary at the policy length' {
        $issue = Get-TestIssue
        $issue.fields.summary = 'a' * 500
        Set-IssueResponse -Issue $issue
        $ticket = Get-AgentTicket -IssueKey 'DEVOPS-42' -Policy $policy
        $ticket.Summary | Should -BeLike ('{0}*' -f ('a' * $policy.jira.maxSummaryLength))
        $ticket.Summary | Should -Not -BeLike ('{0}*' -f ('a' * ($policy.jira.maxSummaryLength + 1)))
        $ticket.Summary | Should -BeLike '*[[]truncated]'
    }

    It 'caps an over-long description at the policy length' {
        $smallPolicy = Get-TestPolicy
        $smallPolicy.jira.maxDescriptionLength = 30
        $issue = Get-TestIssue
        $issue.fields.description = $null
        $issue.fields.description = [pscustomobject] @{
            type = 'doc'; version = 1
            content = @([pscustomobject] @{ type = 'paragraph'; content = @([pscustomobject] @{ type = 'text'; text = 'x' * 100 }) })
        }
        Set-IssueResponse -Issue $issue
        $ticket = Get-AgentTicket -IssueKey 'DEVOPS-42' -Policy $smallPolicy
        $ticket.Description.Length | Should -BeLessThan 60
        $ticket.Description | Should -BeLike '*[[]truncated]'
    }

    It 'handles an issue with no description' {
        $issue = Get-TestIssue
        $issue.fields.description = $null
        Set-IssueResponse -Issue $issue
        $ticket = Get-AgentTicket -IssueKey 'DEVOPS-42' -Policy $policy
        $ticket.Description | Should -BeExactly ''
        $ticket.Eligible | Should -BeTrue
    }
}
