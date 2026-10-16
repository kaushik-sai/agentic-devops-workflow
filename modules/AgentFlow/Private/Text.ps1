Set-StrictMode -Version Latest

# Removes control characters (keeps tab and newline), zero-width and bidi override characters,
# and caps the length.
# Ticket text and CI logs are untrusted input: this keeps them printable and bounded.
function Format-UntrustedText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [AllowNull()] [string] $Text,
        [Parameter(Mandatory)] [int] $MaxLength
    )
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $clean = ($Text -replace "`r`n", "`n") -replace '[\x00-\x08\x0B-\x1F\x7F\u200B-\u200F\u202A-\u202E\u2066-\u2069]', ''
    if ($clean.Length -gt $MaxLength) {
        $clean = $clean.Substring(0, $MaxLength) + "`n[truncated]"
    }
    $clean
}

# Masks values that look like credentials before text is shown to the agent or written to a log.
function Protect-SecretText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [AllowNull()] [string] $Text
    )
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $patterns = @(
        'gh[pousr]_[A-Za-z0-9]{20,}'              # GitHub tokens
        'github_pat_[A-Za-z0-9_]{20,}'            # GitHub fine-grained tokens
        'sk-ant-[A-Za-z0-9_\-]{20,}'              # Anthropic API keys
        'ATATT[A-Za-z0-9_\-=]{20,}'               # Atlassian API tokens
        'AKIA[0-9A-Z]{16}'                        # AWS access key IDs
        '(?i)(bearer|basic)\s+[A-Za-z0-9+/=._\-]{16,}'
        '-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----'
    )
    foreach ($pattern in $patterns) {
        $Text = [regex]::Replace($Text, $pattern, '[redacted]')
    }
    $Text
}

# Flattens a Jira Cloud description (Atlassian Document Format) to plain text.
# Paragraphs, headings and list items each end with a newline; marks and media are dropped.
function ConvertFrom-AdfText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [object] $Node
    )
    if ($null -eq $Node) { return '' }
    if ($Node -is [string]) { return $Node }
    $builder = [System.Text.StringBuilder]::new()
    $type = if ($Node.PSObject.Properties['type']) { $Node.type } else { '' }
    if ($type -eq 'text' -and $Node.PSObject.Properties['text']) {
        [void] $builder.Append($Node.text)
    }
    elseif ($type -eq 'hardBreak') {
        [void] $builder.Append("`n")
    }
    if ($Node.PSObject.Properties['content']) {
        $prefix = if ($type -eq 'listItem') { '- ' } else { '' }
        [void] $builder.Append($prefix)
        foreach ($child in @($Node.content)) {
            [void] $builder.Append((ConvertFrom-AdfText -Node $child))
        }
    }
    if ($type -in 'paragraph', 'heading', 'codeBlock', 'blockquote') {
        [void] $builder.Append("`n")
    }
    $builder.ToString()
}

# Turns a path glob from policy.json into a regex. ** crosses folders, * does not.
function ConvertTo-PathRegex {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Glob
    )
    $escaped = [regex]::Escape($Glob)
    $escaped = $escaped -replace '\\\*\\\*/', '(?:.*/)?'
    $escaped = $escaped -replace '\\\*\\\*', '.*'
    $escaped = $escaped -replace '\\\*', '[^/]*'
    $escaped = $escaped -replace '\\\?', '[^/]'
    '^' + $escaped + '$'
}
