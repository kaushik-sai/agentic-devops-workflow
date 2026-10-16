@{
    RootModule        = 'AgentFlow.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b7f6f0a2-3a51-4f55-9f0e-2f6a1c7d4e10'
    Author            = 'Kaushik Sai'
    Description       = 'Guard rails for an agentic Jira-to-PR workflow: ticket validation, branch names, task files, change policy and the CI fix loop.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'Get-AgentPolicy'
        'Get-AgentTicket'
        'New-AgentBranchName'
        'New-AgentTask'
        'Get-FixAttempt'
        'Test-AgentChangePolicy'
        'Get-CiFailureLog'
        'Send-JiraComment'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
