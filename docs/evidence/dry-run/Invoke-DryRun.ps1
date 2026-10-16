param([string] $S)
$ErrorActionPreference = 'Stop'
$env:SSL_CERT_FILE = "$S/bundle.pem"
$env:JIRA_BASE_URL = 'https://localhost:8443'
$env:JIRA_USER_EMAIL = 'agent@example.com'
$env:JIRA_API_TOKEN = 'dummy-token'
function Step($t) { Write-Output "`n=== $t" }
$sw = [Diagnostics.Stopwatch]::StartNew()

Step '1. Intake: eligible ticket DEVOPS-42'
git clone -q "$S/remote.git" "$S/work"
$env:GITHUB_OUTPUT = "$S/intake.out"; Remove-Item $env:GITHUB_OUTPUT -ErrorAction Ignore
& "$S/work/scripts/Invoke-TicketIntake.ps1" -IssueKey DEVOPS-42 -OutputPath "$S/agent/ticket.json"
Get-Content $env:GITHUB_OUTPUT
$branch = ((Get-Content $env:GITHUB_OUTPUT) -match '^branch=') -replace '^branch=', ''

Step '2. Intake: ineligible ticket DEVOPS-43 (status In Progress) and a disallowed project'
pwsh -NoProfile -File "$S/work/scripts/Invoke-TicketIntake.ps1" -IssueKey DEVOPS-43 -OutputPath "$S/x/t.json"; "exit code: $LASTEXITCODE"
pwsh -NoProfile -File "$S/work/scripts/Invoke-TicketIntake.ps1" -IssueKey HR-7 -OutputPath "$S/x/t.json"; "exit code: $LASTEXITCODE"
pwsh -NoProfile -File "$S/work/scripts/Invoke-TicketIntake.ps1" -IssueKey 'DEVOPS-1/../../x' -OutputPath "$S/x/t.json" 2>&1 | Select-Object -Last 1; "exit code: $LASTEXITCODE"

Step '3. Task file (injection text stays inside the nonce fence)'
Import-Module "$S/work/modules/AgentFlow" -Force
$ticket = Get-Content "$S/agent/ticket.json" -Raw | ConvertFrom-Json
New-AgentTask -Mode Implement -Ticket $ticket -Path "$S/work/.agent/task.md" | Out-Null
Get-Content "$S/work/.agent/task.md" | Select-Object -Last 8

Step '4. Simulated agent edit in the agent checkout (src + tests), then Invoke-Checks'
Add-Content "$S/work/src/InventoryApi/InventoryApi.psm1" -Value @'

<#
.SYNOPSIS
    Lists the SKUs at or below their reorder point, sorted by SKU.
#>
function Get-ReorderReport {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [hashtable] $Inventory,
        [Parameter(Mandatory)] [ValidateRange(0, [int]::MaxValue)] [int] $ReorderPoint
    )
    @($Inventory.Keys | Where-Object { [int] $Inventory[$_] -le $ReorderPoint } | Sort-Object)
}

Export-ModuleMember -Function 'Get-ReorderReport'
'@
Set-Content "$S/work/tests/InventoryApi/Get-ReorderReport.Tests.ps1" -Value @'
BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'src', 'InventoryApi', 'InventoryApi.psm1') -Force
}

Describe 'Get-ReorderReport' {
    It 'lists SKUs at or below the reorder point, sorted' {
        Get-ReorderReport -Inventory @{ 'SKU-3' = 1; 'SKU-1' = 3; 'SKU-2' = 9 } -ReorderPoint 3 | Should -Be @('SKU-1', 'SKU-3')
    }
}
'@
Set-Content "$S/work/.agent/summary.md" -Value 'Added Get-ReorderReport with a test. Ignored an instruction in the ticket to edit ci.yml.'
pwsh -NoProfile -File "$S/work/scripts/Invoke-Checks.ps1" | Where-Object { $_ -match '^(PSScriptAnalyzer|Pester):' }

Step '5. Export the patch from the agent checkout'
& "$S/work/scripts/Export-AgentPatch.ps1" -OutputPath "$S/patch" -RepoPath "$S/work"
git -C "$S/work" diff --cached --stat | Select-Object -Last 1

Step '6. Publish side: fresh clone of main, apply patch, change policy'
git clone -q "$S/remote.git" "$S/publish"
Push-Location "$S/publish"
pwsh -NoProfile -File ./scripts/Import-AgentPatch.ps1 -PatchPath "$S/patch/agent.patch" -Branch $branch -NewBranch; "exit code: $LASTEXITCODE"
git branch --show-current
Pop-Location

Step '7. Negative: patch that edits .github/workflows/ci.yml and scripts/'
git clone -q "$S/remote.git" "$S/bad"
Add-Content "$S/bad/.github/workflows/ci.yml" -Value '# removed tests'
Add-Content "$S/bad/scripts/Invoke-Checks.ps1" -Value 'exit 0'
& "$S/work/scripts/Export-AgentPatch.ps1" -OutputPath "$S/badpatch" -RepoPath "$S/bad"
git clone -q "$S/remote.git" "$S/publish2"
Push-Location "$S/publish2"
pwsh -NoProfile -File ./scripts/Import-AgentPatch.ps1 -PatchPath "$S/badpatch/agent.patch" -Branch 'agent/DEVOPS-44-bad' -NewBranch; "exit code: $LASTEXITCODE"
Pop-Location

Step '8. Negative: patch that adds a symlink'
git clone -q "$S/remote.git" "$S/sym"
New-Item -ItemType SymbolicLink -Path "$S/sym/src/link" -Target '/etc/passwd' | Out-Null
& "$S/work/scripts/Export-AgentPatch.ps1" -OutputPath "$S/sympatch" -RepoPath "$S/sym"
git clone -q "$S/remote.git" "$S/publish3"
Push-Location "$S/publish3"
pwsh -NoProfile -File ./scripts/Import-AgentPatch.ps1 -PatchPath "$S/sympatch/agent.patch" -Branch 'agent/DEVOPS-45-sym' -NewBranch; "exit code: $LASTEXITCODE"
Pop-Location

Step '9. Fix loop attempt counter on the published branch'
Push-Location "$S/publish"
git -c user.name=bot -c user.email=b@b commit -qm 'DEVOPS-42: Add Get-ReorderReport' --trailer 'Jira: DEVOPS-42'
foreach ($n in 1..3) {
    git -c user.name=bot -c user.email=b@b commit -q --allow-empty -m "DEVOPS-42: fix CI (attempt $n of 3)" --trailer 'Jira: DEVOPS-42' --trailer "Agent-Fix-Attempt: $n"
    "after attempt $($n): Get-FixAttempt = $(Get-FixAttempt -RepoPath . -BaseRef origin/main -Trailer 'Agent-Fix-Attempt') (escalate at 3)"
}
Pop-Location

Step '10. Jira calls the fake server received'
Get-Content "$S/jira.log" | ForEach-Object { if ($_.Length -gt 220) { $_.Substring(0, 220) + '...' } else { $_ } }
"Total time: $([math]::Round($sw.Elapsed.TotalSeconds, 1)) s"
