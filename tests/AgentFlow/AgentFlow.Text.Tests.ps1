BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'AgentFlow.TestHelpers.ps1')
    Import-AgentFlowModule
}

AfterAll {
    Remove-Module AgentFlow -ErrorAction SilentlyContinue
}

Describe 'Format-UntrustedText' {
    It 'returns an empty string for null or empty input' -ForEach @(
        @{ Text = $null }
        @{ Text = '' }
    ) {
        InModuleScope AgentFlow -Parameters $_ {
            Format-UntrustedText -Text $Text -MaxLength 10 | Should -BeExactly ''
        }
    }

    It 'keeps tab and newline and normalises CRLF to LF' {
        InModuleScope AgentFlow {
            Format-UntrustedText -Text "a`tb`r`nc`nd" -MaxLength 100 | Should -BeExactly "a`tb`nc`nd"
        }
    }

    It 'removes control characters' {
        InModuleScope AgentFlow {
            $dirty = "a$([char] 0)b$([char] 7)c$([char] 0x1B)d$([char] 0x7F)e"
            Format-UntrustedText -Text $dirty -MaxLength 100 | Should -BeExactly 'abcde'
        }
    }

    It 'removes zero-width and bidirectional override characters' {
        InModuleScope AgentFlow {
            $dirty = "a$([char] 0x200B)b$([char] 0x202E)c$([char] 0x2066)d"
            Format-UntrustedText -Text $dirty -MaxLength 100 | Should -BeExactly 'abcd'
        }
    }

    It 'caps the length and marks the cut' {
        InModuleScope AgentFlow {
            Format-UntrustedText -Text ('x' * 20) -MaxLength 5 | Should -BeExactly "xxxxx`n[truncated]"
        }
    }

    It 'leaves text of exactly the maximum length alone' {
        InModuleScope AgentFlow {
            Format-UntrustedText -Text ('x' * 5) -MaxLength 5 | Should -BeExactly 'xxxxx'
        }
    }
}

Describe 'Protect-SecretText' {
    It 'masks <Name>' -ForEach @(
        @{ Name = 'a GitHub token'; Secret = ('gh' + 'p_' + ('A1' * 15)) }
        @{ Name = 'a GitHub OAuth token'; Secret = ('gh' + 'o_' + ('b2' * 15)) }
        @{ Name = 'a fine-grained GitHub token'; Secret = ('github' + '_pat_' + ('C3' * 15)) }
        @{ Name = 'an Anthropic key'; Secret = ('sk' + '-ant-' + ('d4' * 15)) }
        @{ Name = 'an Atlassian token'; Secret = ('AT' + 'ATT' + ('e5' * 15)) }
        @{ Name = 'an AWS access key id'; Secret = ('AK' + 'IA' + ('F6' * 8)) }
        @{ Name = 'a bearer header'; Secret = ('Bearer ' + ('g7' * 12)) }
        @{ Name = 'a basic auth header'; Secret = ('basic ' + ('h8' * 12)) }
        @{ Name = 'a private key block'; Secret = ("-----BEGIN RSA PRIVATE KEY-----`nMIIBOgIBAAJB`nabc`n-----END RSA PRIVATE KEY-----") }
    ) {
        InModuleScope AgentFlow -Parameters $_ {
            $result = Protect-SecretText -Text "before $Secret after"
            $result | Should -BeExactly 'before [redacted] after'
        }
    }

    It 'masks several secrets in one text' {
        InModuleScope AgentFlow {
            $a = 'gh' + 'p_' + ('A1' * 15)
            $b = 'AK' + 'IA' + ('F6' * 8)
            Protect-SecretText -Text "$a and $b" | Should -BeExactly '[redacted] and [redacted]'
        }
    }

    It 'leaves ordinary text alone' {
        InModuleScope AgentFlow {
            $text = "Error: ghp is short, Bearer x, sk-ant-short`nline 2"
            Protect-SecretText -Text $text | Should -BeExactly $text
        }
    }

    It 'returns an empty string for null or empty input' {
        InModuleScope AgentFlow {
            Protect-SecretText -Text $null | Should -BeExactly ''
            Protect-SecretText -Text '' | Should -BeExactly ''
        }
    }
}

Describe 'ConvertFrom-AdfText' {
    It 'returns an empty string for null' {
        InModuleScope AgentFlow {
            ConvertFrom-AdfText -Node $null | Should -BeExactly ''
        }
    }

    It 'returns a plain string as it is' {
        InModuleScope AgentFlow {
            ConvertFrom-AdfText -Node 'plain' | Should -BeExactly 'plain'
        }
    }

    It 'ends paragraphs and headings with a newline and prefixes list items' {
        $issue = Get-TestIssue
        InModuleScope AgentFlow -Parameters @{ Doc = $issue.fields.description } {
            $text = ConvertFrom-AdfText -Node $Doc
            $text | Should -BeExactly "Add health endpoint`nExpose GET /health returning 200 and the build version.`n- Return JSON`n- No auth required`n- Add a Pester test`n"
        }
    }

    It 'turns a hard break into a newline and drops marks' {
        $doc = '{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"a","marks":[{"type":"strong"}]},{"type":"hardBreak"},{"type":"text","text":"b"}]}]}' | ConvertFrom-Json
        InModuleScope AgentFlow -Parameters @{ Doc = $doc } {
            ConvertFrom-AdfText -Node $Doc | Should -BeExactly "a`nb`n"
        }
    }

    It 'ignores node types it does not know (media, mentions without text)' {
        $doc = '{"type":"doc","content":[{"type":"mediaSingle","content":[{"type":"media","attrs":{"id":"x"}}]},{"type":"paragraph","content":[{"type":"text","text":"after"}]}]}' | ConvertFrom-Json
        InModuleScope AgentFlow -Parameters @{ Doc = $doc } {
            ConvertFrom-AdfText -Node $Doc | Should -BeExactly "after`n"
        }
    }
}

Describe 'ConvertTo-PathRegex' {
    It 'anchors the pattern and escapes regex characters' {
        InModuleScope AgentFlow {
            $regex = ConvertTo-PathRegex -Glob 'a.b(c)+d'
            $regex | Should -BeLike '^*$'
            'a.b(c)+d' | Should -Match $regex
            'aXb(c)+d' | Should -Not -Match $regex
        }
    }

    It 'lets ** cross folders but * not' {
        InModuleScope AgentFlow {
            'x/y/z.txt' | Should -Match (ConvertTo-PathRegex -Glob 'x/**')
            'x/y/z.txt' | Should -Not -Match (ConvertTo-PathRegex -Glob 'x/*')
            'x/z.txt' | Should -Match (ConvertTo-PathRegex -Glob 'x/*')
        }
    }

    It 'treats **/ as zero or more folders' {
        InModuleScope AgentFlow {
            $regex = ConvertTo-PathRegex -Glob '**/f.txt'
            'f.txt' | Should -Match $regex
            'a/f.txt' | Should -Match $regex
            'a/b/f.txt' | Should -Match $regex
            'a/bf.txt' | Should -Not -Match $regex
        }
    }
}
