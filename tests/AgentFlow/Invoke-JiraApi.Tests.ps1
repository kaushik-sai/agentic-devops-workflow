BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'AgentFlow.TestHelpers.ps1')
    Import-AgentFlowModule
}

AfterAll {
    Remove-Module AgentFlow -ErrorAction SilentlyContinue
}

# Invoke-JiraApi is private, so these tests run inside the module. The values are made up.
Describe 'Invoke-JiraApi' {
    BeforeEach {
        # Save and replace the three variables; AfterEach puts the originals back.
        $saved = @{}
        foreach ($name in 'JIRA_BASE_URL', 'JIRA_USER_EMAIL', 'JIRA_API_TOKEN') {
            $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        }
        $env:JIRA_BASE_URL = 'https://example.atlassian.net/'
        $env:JIRA_USER_EMAIL = 'bot@example.com'
        $env:JIRA_API_TOKEN = 'not-a-real-token'
        Mock -ModuleName AgentFlow Invoke-RestMethod { 'ok' }
    }
    AfterEach {
        foreach ($name in $saved.Keys) {
            [Environment]::SetEnvironmentVariable($name, $saved[$name])
        }
    }

    It 'throws when <Name> is not set' -ForEach @(
        @{ Name = 'JIRA_BASE_URL' }
        @{ Name = 'JIRA_USER_EMAIL' }
        @{ Name = 'JIRA_API_TOKEN' }
    ) {
        [Environment]::SetEnvironmentVariable($Name, $null)
        InModuleScope AgentFlow -Parameters @{ Name = $Name } {
            { Invoke-JiraApi -Method GET -Path '/rest/api/3/myself' } | Should -Throw "Environment variable $Name is not set."
        }
        Should -Invoke -ModuleName AgentFlow Invoke-RestMethod -Times 0 -Exactly
    }

    It 'throws when the base URL is http://' {
        $env:JIRA_BASE_URL = 'http://example.atlassian.net'
        InModuleScope AgentFlow {
            { Invoke-JiraApi -Method GET -Path '/rest/api/3/myself' } | Should -Throw '*must start with https://*'
        }
        Should -Invoke -ModuleName AgentFlow Invoke-RestMethod -Times 0 -Exactly
    }

    It 'rejects a path that does not start with /rest/' {
        InModuleScope AgentFlow {
            { Invoke-JiraApi -Method GET -Path '/other' } | Should -Throw
        }
    }

    It 'rejects a method other than GET or POST' {
        InModuleScope AgentFlow {
            { Invoke-JiraApi -Method DELETE -Path '/rest/api/3/issue/X-1' } | Should -Throw
        }
    }

    It 'joins the base URL (without trailing slash) and the path, with a Basic header' {
        InModuleScope AgentFlow {
            Invoke-JiraApi -Method GET -Path '/rest/api/3/myself' | Should -Be 'ok'
        }
        $expectedAuth = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('bot@example.com:not-a-real-token'))
        Should -Invoke -ModuleName AgentFlow Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -ceq 'https://example.atlassian.net/rest/api/3/myself' -and
            $Method -eq 'GET' -and
            $Headers.Authorization -ceq 'Basic Ym90QGV4YW1wbGUuY29tOm5vdC1hLXJlYWwtdG9rZW4=' -and
            -not $Body
        }
        $expectedAuth | Should -Be 'Basic Ym90QGV4YW1wbGUuY29tOm5vdC1hLXJlYWwtdG9rZW4='
    }

    It 'sends the body as compressed JSON with a JSON content type' {
        InModuleScope AgentFlow {
            Invoke-JiraApi -Method POST -Path '/rest/api/3/issue/DEVOPS-1/comment' -Body @{ a = 1 } | Out-Null
        }
        Should -Invoke -ModuleName AgentFlow Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Body -ceq '{"a":1}' -and $ContentType -eq 'application/json'
        }
    }
}
