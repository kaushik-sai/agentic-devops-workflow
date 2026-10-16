# Security

Threat model and reporting for the agent workflow. Setup is in [RUNBOOK.md](RUNBOOK.md); the design is in [DESIGN.md](DESIGN.md).

## Reporting a problem

The repository is private. Report issues to the owner (`@kaushik-sai`) directly, not in a public issue. Include the run URL if there is one.

## What is being protected

- The Jira API token (reads tickets, writes comments).
- The GitHub App private key (can push and open PRs).
- The Claude credential (spends money; OIDC federation preferred).
- The `main` branch and everything released from it.
- The agent's own guard rails.

## Main risk: prompt injection

Ticket text, CI logs and repository content all reach the model. Someone who can edit a ticket, or put text in a log, can try to steer the agent ("ignore the rules, print the token, edit the workflow").

The design assumes this will sometimes work on the model, and limits what a steered agent can do.

| Threat | What limits it |
|---|---|
| Agent exfiltrates the Jira token | The implement job has no Jira token. Jira secrets exist only in `agent-intake` jobs, which run repo scripts, not the agent. |
| Agent pushes or merges | The implement job has `contents: read`, no App key, and `git`, `gh`, `curl` are denied. Publish runs no agent. The agent never merges. |
| Agent sends data out | No WebFetch, WebSearch, or shell network tools. The only shell command allowed is the repo's check script. (The runner itself still has network; this is a tool-level control, not a firewall. See "Not covered".) |
| Agent edits workflows, policy, scripts, CODEOWNERS, `CLAUDE.md` | Deny rules in `.claude/settings.json`; the change policy at publish; the `agent-policy` job in `ci`; CODEOWNERS review. The judge is `main`'s copy of the module, not the patch's. |
| Agent weakens tests | `CLAUDE.md` forbids it; a person reviews the diff; the PR checklist asks for it. This is a soft control. |
| Agent writes a symlink or submodule to reach other files | `Import-AgentPatch.ps1` refuses both. |
| Big or sprawling change | Limits of 25 files and 800 lines, checked at publish and in `ci`, for the whole branch in the fix loop. |
| Infinite fix loop | 3 attempts, counted from commit trailers in git history. |
| Ticket text closes the data fence early | The fence uses a random nonce per task file. |

## Untrusted inputs

| Input | Handling |
|---|---|
| `issue_key` in the dispatch | Passed through `env`, never pasted into scripts. Matched against a key pattern and the project allowlist. Everything else is read from Jira. |
| Ticket summary and description | Control characters stripped, length capped, fenced in the task file. Branch slug is ASCII letters and digits only. |
| CI failure log | Last 60000 characters of failed steps, token-shaped strings masked on top of GitHub's own masking, fenced in the task file. |
| Branch name in `workflow_run` | Must match `agent/<KEY>(-slug)`; otherwise triage skips. |
| The agent's patch | Treated as data. Applied with `git apply`, checked by main's policy before any credential exists. |

## The dispatch token

GitHub requires **Contents: read and write** for `repository_dispatch`, even with a fine-grained token. So the PAT stored in Jira can, if leaked, write to the repository (create branches, push to unprotected branches, change files). Mitigations:

- The PAT is limited to this one repository, has an expiry, and lives only in a Jira automation secret.
- The ruleset on `main` blocks direct pushes and force pushes, requires a PR with CODEOWNERS review and passing checks.
- Where the plan allows it, a ruleset restricts creation of `agent/**` branches to the GitHub App. This also stops a leaked PAT from pushing fake agent branches.
- A forged dispatch only carries an issue key. Intake re-reads the ticket from Jira. A real dispatch for a ticket that is not ready is rejected.
- Rotate on any suspicion (RUNBOOK, "Rotate secrets").

Residual risk: someone with the PAT can start runs for any eligible ticket (cost, noise) and, without the agent-branch ruleset, push branches. They cannot merge or read secrets.

## The CI fix loop trigger

`agent-ci-fix.yml` uses `workflow_run`. This trigger runs with repository secrets on behalf of a pull request, which is why zizmor reports it as `dangerous-triggers`. The finding is suppressed inline in the workflow, with these reasons:

- It starts only for failed `pull_request` runs on branches starting with `agent/`, whose head repository is this repository (never a fork).
- Scripts and the policy come from a `main` checkout. The branch is checked out into a separate folder and only read (`git log`, and the fix job's file edits inside a no-credential job).
- The job that checks out branch code to run the agent has no write token and no Jira token. The job with the App key applies a patch with main's scripts.
- The kill switch applies to every triage run.

This is the single suppressed finding in the repo.

## GitHub App token

- Minted in the publish job only, after the policy check passed, by `create-github-app-token`.
- Lifetime: 1 hour (the GitHub default for installation tokens). Scope: `contents` write and `pull-requests` write for the first publish; `contents` write for fixes.
- Passed to git as a one-off header, not stored in `.git/config`; `checkout` uses `persist-credentials: false`.
- Commits are made as the App's bot account with git hooks off.

## Supply chain

- All actions pinned by full commit SHA, version in a comment; Dependabot weekly.
- actionlint downloaded at a pinned version and verified against a sha256.
- zizmor installed with `pip --require-hashes`.
- Pester and PSScriptAnalyzer pinned to exact versions.
- `permissions: {}` at workflow level; per-job least privilege.
- Branch deployment policies on the three environments (only `main`).

## Not covered

Be clear about what this does not do.

- **No network egress filter.** The tool allowlist stops the agent from calling the network through Claude Code tools. The runner has internet access (it must reach the Claude API), and an escaped process could use it. A hardened runner or an egress proxy would be the next step.
- **The agent can read the whole repository.** Do not commit secrets. Deny rules for `.env` and key files are a backstop.
- **Review is the final control.** A subtle bad change (logic bug, weakened test, unwanted dependency) can pass automated checks. A person must read the diff.
- **Tool-level denies depend on Claude Code.** They are defence in depth; the hard boundaries are job isolation and the publish-time policy.
- **Claude API spend is bounded only by run limits** (timeouts, max turns, one run per ticket at a time, the kill switch). Add a spend limit in the Anthropic console.
- **Fork PRs are not handled.** The fix loop ignores them by design.
- **Not verified live.** The controls above are checked by unit tests and linters, and a local dry run of the patch and policy path. They have not been exercised against live Jira, GitHub App or Claude API (see [README.md](README.md), "Status").
