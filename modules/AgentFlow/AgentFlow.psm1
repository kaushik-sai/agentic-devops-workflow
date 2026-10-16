Set-StrictMode -Version Latest

# Load private helpers first, then the public commands that use them.
# One function (or one small group of helpers) per file keeps each file easy to read.
$privateFiles = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1'
$publicFiles = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1'

foreach ($file in @($privateFiles) + @($publicFiles)) {
    . $file.FullName
}

# Keep in step with FunctionsToExport in AgentFlow.psd1.
Export-ModuleMember -Function @(
    'Get-AgentPolicy'
    'Get-AgentTicket'
    'New-AgentBranchName'
    'New-AgentTask'
    'Get-FixAttempt'
    'Test-AgentChangePolicy'
    'Get-CiFailureLog'
    'Send-JiraComment'
)
