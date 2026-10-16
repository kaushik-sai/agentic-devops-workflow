Set-StrictMode -Version Latest

# The one place the module calls Jira Cloud's REST API.
# Credentials come from the environment, never from parameters, so they stay out of logs and history:
#   JIRA_BASE_URL    https://<site>.atlassian.net
#   JIRA_USER_EMAIL  the service account's email
#   JIRA_API_TOKEN   an API token for that account (a secret)
function Invoke-JiraApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('GET', 'POST')] [string] $Method,
        # Path below the site, starting with /rest/.
        [Parameter(Mandatory)] [ValidatePattern('^/rest/')] [string] $Path,
        [object] $Body
    )
    foreach ($name in 'JIRA_BASE_URL', 'JIRA_USER_EMAIL', 'JIRA_API_TOKEN') {
        if (-not [Environment]::GetEnvironmentVariable($name)) {
            throw "Environment variable $name is not set."
        }
    }
    $baseUrl = $env:JIRA_BASE_URL.TrimEnd('/')
    # Only HTTPS, so the token never travels in clear text.
    if ($baseUrl -notmatch '^https://') {
        throw 'JIRA_BASE_URL must start with https://.'
    }
    $pair = '{0}:{1}' -f $env:JIRA_USER_EMAIL, $env:JIRA_API_TOKEN
    $headers = @{
        Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        Accept        = 'application/json'
    }
    $request = @{
        Method      = $Method
        Uri         = $baseUrl + $Path
        Headers     = $headers
        TimeoutSec  = 30
        ErrorAction = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $request.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
        $request.ContentType = 'application/json'
    }
    Invoke-RestMethod @request
}
