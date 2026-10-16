# Decisions

Choices made while building the workflow, one line each. Design is in [../DESIGN.md](../DESIGN.md).

## Trigger and intake

| # | Question | Decision | Why |
|---|----------|----------|-----|
| 1 | How does Jira start a run | Jira Automation "Send web request" to the GitHub `dispatches` API, event type `jira-ticket-ready` | Works on Jira Cloud without an app; the rule is visible and editable by the Jira admin |
| 2 | What does the request carry | Only `issue_key` | The payload is a pointer; a forged or stale payload cannot change what the agent is asked to do |
| 3 | Where does the ticket content come from | Intake re-reads the ticket from Jira | Jira is the source of truth; status, label and text are checked at run time |
| 4 | What makes a ticket eligible | Project in the allowlist (`DEVOPS`), status `Ready for Agent`, label `agent-ok`, type Task, Bug or Story | Two human signals (status and label) plus a closed set of projects and types |
| 5 | Token for the dispatch call | Fine-grained PAT for this one repository, Contents read and write, stored as a Jira automation secret | `repository_dispatch` needs Contents write; this is the minimum GitHub accepts. Other mitigations are in SECURITY.md |
| 6 | Manual path | `workflow_dispatch` with `issue_key` | Retry after fixing why intake said no, and test without Jira. Same intake checks apply |
| 7 | Concurrency | One run per ticket (`agent-ticket-<key>`), queued, not cancelled | A second dispatch waits instead of racing or killing work in progress |
| 8 | Kill switch | Repository variable `AGENT_ENABLED` must be `true` | One setting stops all runs; unset by default so a fresh clone does nothing |
| 9 | How ticket text is passed to the agent | Task file with the text between `UNTRUSTED-*` markers that carry a random nonce; the prompt is fixed and only names the file | Ticket text cannot close the fence or rewrite the prompt |
| 10 | Rejected tickets | Comment the reasons on the Jira ticket and stop; no Jira call for projects outside the allowlist | The author learns why; the agent never reaches other projects |

## Agent run

| # | Question | Decision | Why |
|---|----------|----------|-----|
| 11 | Where the agent runs | Own job, environment `agent`, only the Claude credential, `contents: read` | A prompt-injected agent finds no Jira token and no write token |
| 12 | Which tools | Read, Edit, Write, Glob, Grep, and the single command `pwsh -NoProfile -File ./scripts/Invoke-Checks.ps1`; WebFetch, WebSearch, git, gh, curl denied | Enough to implement and test; no network, no git |
| 13 | How the agent's work leaves the job | A binary patch plus `summary.md` as an artifact | Data crosses the boundary, not a checkout; hooks and fsmonitor are off during export |
| 14 | Claude action | `anthropics/claude-code-action` pinned by commit SHA | Maintained integration; pin so an upstream change cannot alter the run |
| 15 | Claude authentication | OIDC workload identity federation preferred; `ANTHROPIC_API_KEY` as fallback | No long-lived key in GitHub with OIDC; fallback keeps the setup simple |
| 16 | Model and limits | `vars.AGENT_MODEL`, default `claude-sonnet-5-5`; `--max-turns` 40 (30 for fixes); 45 minute job timeout | Model is changeable without a PR; limits cap cost and runaway runs |
| 17 | Per-run approval | Optional required reviewers on the `agent` environment, not on by default | A team can choose a manual gate without changing code |

## Publishing

| # | Question | Decision | Why |
|---|----------|----------|-----|
| 18 | Who may push | A fresh `publish` job in environment `agent-publish`, holding the App private key; no agent runs in it | No job holds both the agent and a write credential |
| 19 | Which code judges the patch | `main`'s checkout: `Import-AgentPatch.ps1` and the AgentFlow module | A patch cannot edit the policy that checks it |
| 20 | Checks before any credential | `git apply --index`, refuse symlinks and submodules, then `Test-AgentChangePolicy` | Token is minted only after the patch passed |
| 21 | Why a GitHub App, not `GITHUB_TOKEN` | App installation token | Pushes made with `GITHUB_TOKEN` do not start other workflows, so `ci` would not run on the PR |
| 22 | App token scope | Short-lived (1 hour), `contents` and `pull-requests` write, minted after the policy check | Least privilege in time and in permission |
| 23 | Commit identity and trace | Commit as the App bot, hooks off, trailers `Jira:` and `Agent-Run:` | Anyone can tie a commit to a ticket and a run |
| 24 | Rerun of the same ticket | Branch name is deterministic; push uses `--force-with-lease=ref:` so it fails if the branch exists | A rerun cannot overwrite earlier work; delete the branch on purpose |
| 25 | PR state | Draft, label `agent`, review checklist in the body; the agent never merges | A person decides |
| 26 | Report back to Jira | `notify` job always comments, with the PR link or the run link | The ticket shows the outcome without opening GitHub |

## Fix loop

| # | Question | Decision | Why |
|---|----------|----------|-----|
| 27 | What starts a fix | `workflow_run` on `ci` completed, only if failed, event `pull_request`, branch `agent/*`, same repository | Narrow trigger; forks and human branches are excluded |
| 28 | Why `workflow_run` is acceptable | Scripts come from `main`; branch code never runs with a credential; zizmor finding suppressed inline with the reasons | The trigger is needed to see `ci` results; the risk is contained and written down |
| 29 | How attempts are counted | Commits with trailer `Agent-Fix-Attempt` in `origin/main..HEAD`; at 3, escalate | History cannot be reset by relabelling or reopening the PR |
| 30 | Escalation | Label `needs-human`, comment on the PR and on the Jira ticket | A person is told where they will look |
| 31 | Stale runs | Triage skips if the branch head is not the failed SHA | A newer push has a newer `ci` run; two fixes never race |
| 32 | Failure log given to the agent | `gh run view --log-failed`, token-shaped strings masked, last 60000 characters, fenced as untrusted | The error is usually at the end; logs can hold injected text and secrets |
| 33 | Policy for fixes | Checked on the whole branch against `main`, not on the single patch | Small fixes cannot add up to a big change |
| 34 | Fix push | Fast-forward only | If a person pushed meanwhile, the job fails instead of overwriting |

## Governance and supply chain

| # | Question | Decision | Why |
|---|----------|----------|-----|
| 35 | Protected paths | `.github/**`, `.claude/**`, `CLAUDE.md`, `CODEOWNERS`, `modules/AgentFlow/**`, `scripts/**`, `tests/AgentFlow/**`, `PSScriptAnalyzerSettings.psd1`, key and `.env` files | The agent must not change its own rules, tests of the rules, or secrets |
| 36 | Size limits | 25 files and 800 lines | Keeps reviews small; large tickets need a person |
| 37 | Where limits are enforced | `.claude/settings.json` deny rules, the publish-time policy, and the `agent-policy` job in `ci` | Three independent layers; the first is advisory, the other two run main's code |
| 38 | Review | CODEOWNERS review required by a ruleset; PRs are drafts | The agent's output is untrusted until read |
| 39 | Required status checks | `checks`, `workflow-security`, `agent-policy` (agent PRs) | Same checks for agent and human PRs |
| 40 | Workflow permissions | `permissions: {}` at the top, least privilege per job; checkout without persisted credentials | A leaked token has little power |
| 41 | Pinning | Actions by full SHA with version comment; Dependabot weekly; actionlint 1.7.12 sha256-verified; zizmor 1.31.1 with `--require-hashes`; Pester 5.9.1 and PSScriptAnalyzer 1.25.0 | Reproducible tools; updates are reviewed PRs |
| 42 | Environment protection | Three environments, each restricted to the `main` branch | A branch cannot read a secret by naming an environment |
| 43 | Language and tests | PowerShell with Pester and PSScriptAnalyzer; one `Invoke-Checks.ps1` for developers, agent and CI | Same toolchain as the owner's other repo; one command everyone trusts |
| 44 | Sample product code | `src/InventoryApi` (`Get-StockLevel`, `Test-ReorderNeeded`) | Gives tickets something real to change without a real product |
| 45 | Agent branch creation | Optional ruleset: only the App may create `agent/**`, where the plan allows it | Closes the gap that the dispatch PAT can write contents |
