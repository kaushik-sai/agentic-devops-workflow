# Runbook

Setup and day-to-day operation of the agent workflow. Design is in [DESIGN.md](DESIGN.md); the Jira rule is in [docs/JIRA_SETUP.md](docs/JIRA_SETUP.md).

Roles used here: **owner** (repository admin, CODEOWNERS), **reviewer** (reads and merges PRs), **Jira admin** (manages the project and automation).

Note: these steps are written from the workflow code. The setup has not yet been run end to end against live services (see [README.md](README.md), "Status").

## Setup

Do these in order. Stop after step 8 and test with a manual run before adding the Jira rule.

### 1. Create the GitHub App

GitHub, Settings, Developer settings, GitHub Apps, New GitHub App.

- Name: for example `agentic-devops-bot`.
- Homepage URL: the repository URL.
- Webhook: untick Active (no webhook).
- Repository permissions: Contents read and write, Pull requests read and write, Metadata read-only. Nothing else.
- Where can it be installed: only on this account.

Then:

1. Create the App, note the **App ID**.
2. Generate a private key (a `.pem` file downloads). Keep it only to paste into the secret in step 3, then delete the file.
3. Install the App on `kaushik-sai/agentic-devops-workflow` only (not all repositories).

### 2. Repository variables

Settings, Secrets and variables, Actions, Variables:

| Variable | Value | Required |
|---|---|---|
| `AGENT_APP_ID` | the App ID | yes |
| `JIRA_BASE_URL` | `https://<site>.atlassian.net` | yes |
| `JIRA_USER_EMAIL` | the Jira service account email | yes |
| `AGENT_ENABLED` | `true` to run, anything else stops all agent runs | yes |
| `AGENT_MODEL` | model name; default `claude-sonnet-5-5` | no |
| `ANTHROPIC_FEDERATION_RULE_ID` | OIDC federation rule ID | only for OIDC |
| `ANTHROPIC_ORGANIZATION_ID` | Anthropic organization ID | only for OIDC |

Leave `AGENT_ENABLED` unset until the end of the setup.

```bash
gh variable set AGENT_APP_ID --body 123456
gh variable set JIRA_BASE_URL --body https://your-site.atlassian.net
gh variable set JIRA_USER_EMAIL --body agent-bot@your-domain
```

### 3. Environments and secrets

Settings, Environments. Create three. For each, set **Deployment branches and tags** to **Selected branches**, and add only `main`. This stops a branch from reading the environment's secrets.

| Environment | Secret | Used by |
|---|---|---|
| `agent-intake` | `JIRA_API_TOKEN` | intake, notify, triage, escalate |
| `agent` | `ANTHROPIC_API_KEY` (or the two OIDC variables above) | implement, fix |
| `agent-publish` | `AGENT_APP_PRIVATE_KEY` (the whole `.pem` text) | publish |

```bash
gh secret set JIRA_API_TOKEN --env agent-intake
gh secret set ANTHROPIC_API_KEY --env agent
gh secret set AGENT_APP_PRIVATE_KEY --env agent-publish < app-private-key.pem
```

Optional: on the `agent` environment add **Required reviewers**. Every agent run then waits for a person to approve before the implement job starts.

Claude authentication: OIDC workload identity federation is preferred (no long-lived key; the job gets `id-token: write`). Set `ANTHROPIC_FEDERATION_RULE_ID` and `ANTHROPIC_ORGANIZATION_ID` and leave the API key secret out. Otherwise set `ANTHROPIC_API_KEY`.

### 4. Labels

```bash
gh label create agent        --color 2448d8 --description "Opened by the agent workflow"
gh label create needs-human  --color 8f5400 --description "The agent gave up; a person must take over"
gh label create dependencies --color 1d7a45 --description "Dependabot updates"
```

### 5. Ruleset on `main`

Settings, Rules, Rulesets, New branch ruleset. Target: default branch.

- Require a pull request before merging.
- Required approvals: 1. Require review from Code Owners. Dismiss stale approvals when new commits are pushed.
- Require status checks: `checks`, `workflow-security`, and `agent-policy`.
- Block force pushes. Restrict deletions.
- Leave the bypass list empty (or only the owner, if you must).

`agent-policy` only runs on agent PRs. If you require it for all PRs, other PRs will wait forever for a check that never reports. Either use a ruleset that targets only branches matching `agent/**` for that check, or accept that it is enforced for agent PRs by the `ci` workflow and by the publish job, and require only `checks` and `workflow-security` globally.

### 6. Ruleset for `agent/*` branches (where your plan allows it)

A second branch ruleset, target `agent/**`: restrict creations, and put the GitHub App on the bypass list. Then only the App can create agent branches, which closes the gap left by the dispatch PAT (it can write contents). Branch rulesets with bypass actors need a plan that supports them; on a free private repository this may not be available. If it is not, note that in your risk acceptance and rely on the `agent-policy` check, CODEOWNERS review and the PAT's narrow scope.

### 7. Jira

Follow [docs/JIRA_SETUP.md](docs/JIRA_SETUP.md): service account, `Ready for Agent` status, the PAT, the automation rule.

### 8. Test manually

1. Set `AGENT_ENABLED` to `true`.
2. Create a small `DEVOPS` ticket, label it `agent-ok`, move it to `Ready for Agent` (without the Jira rule, nothing runs yet).
3. Run `gh workflow run agent-ticket-to-pr.yml -f issue_key=DEVOPS-NN`.
4. Watch the run. Intake, implement and publish should pass; a draft PR appears; `ci` runs on it.
5. Turn on the Jira rule and repeat from Jira.

## Operations

### Read a run

Open the run in the Actions tab. The jobs are intake, implement, publish, notify. Each step has a name that says what it does. The artifacts `intake`, `patch` (and `fix-task`, `fix-patch` for fixes) stay 7 days; `patch/summary.md` is what the agent says it did. The PR body repeats that summary. Commits on the PR carry trailers `Jira:` and `Agent-Run:` with the run URL.

### Rerun a ticket

A rerun of the same ticket computes the same branch name. Publish pushes with a lease that requires the branch not to exist, so the rerun fails on purpose and does not overwrite earlier work. To rerun:

1. Close the old PR (or merge it).
2. Delete the branch: `gh api -X DELETE repos/kaushik-sai/agentic-devops-workflow/git/refs/heads/agent/DEVOPS-42-<slug>`.
3. Move the ticket out of and back into `Ready for Agent`, or run the workflow manually with the key.

### Stop everything

Set the repository variable `AGENT_ENABLED` to `false`:

```bash
gh variable set AGENT_ENABLED --body false
```

Intake and triage are skipped from the next event. Runs already in progress continue; cancel them in the Actions tab if needed. To also stop Jira from sending, disable the automation rule.

### A PR is labelled `needs-human`

The agent made 3 fix attempts and `ci` is still red. The PR and the Jira ticket have a comment. A person should:

1. Read the failing `ci` log and the three fix commits.
2. Fix the branch by hand (push to the branch; the agent will not touch it again because the attempt count is in git history), or close the PR and rewrite the ticket.
3. Note: further `ci` failures after your push still count the 3 earlier attempts, so the agent will not retry.

### Rotate secrets

| Secret | How |
|---|---|
| GitHub App private key | App settings, generate a new key, update `AGENT_APP_PRIVATE_KEY` in `agent-publish`, delete the old key in the App. |
| Jira API token | Create a new token for the service account, update `JIRA_API_TOKEN` in `agent-intake`, revoke the old one. |
| Dispatch PAT | Create a new fine-grained PAT, edit the Jira rule's header, delete the old PAT. |
| Anthropic API key | Create a new key, update `ANTHROPIC_API_KEY` in `agent`, revoke the old one. OIDC needs no rotation. |

### Update pinned versions

Dependabot opens a weekly PR for actions. Review it like any PR; the `ci` run must pass. For actionlint, change `ACTIONLINT_VERSION` and `ACTIONLINT_SHA256` together in `ci.yml` (take the hash from the release's checksums file). For zizmor, take the hashes from PyPI into `.github/zizmor-requirements.txt`. For Pester and PSScriptAnalyzer, change `Install-CheckTools.ps1` and `Invoke-Checks.ps1` together. All of these paths are protected; a person makes the change.

### Change the policy

Edit `modules/AgentFlow/policy.json` by hand in a normal PR (the agent cannot). Examples: add a project to `allowedProjects`, change `readyStatus`, change `maxAttempts`. Tests in `tests/AgentFlow` check the policy reader and the checks.

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| Jira rule shows 204 but no run | `AGENT_ENABLED` is not `true`, or workflow files are not on `main`. |
| Jira rule shows 401 or 404 | The PAT is expired, wrong or has no access to the repository. |
| Intake fails, ticket gets a comment | Status, label, type or project did not match; read the reasons in the comment. |
| Implement job waits | Required reviewers on `agent`: approve the run. |
| Publish fails on the policy step | The patch touched a protected path or exceeded 25 files or 800 lines. The patch artifact is kept; read it. |
| Publish fails on push | The branch already exists (see "Rerun a ticket"), or the App is not installed on the repository. |
| `ci` does not run on the PR | The PR was opened with `GITHUB_TOKEN` instead of the App token; check `AGENT_APP_ID` and the key. |
| Fix loop does not start | Branch head moved since the failed run, the PR is closed, or the branch is not `agent/<KEY>-...`. |
| Environment secret is empty | The run is not on `main` and the deployment branch policy blocked it. |

## Incident: the agent did something wrong

1. **Stop:** set `AGENT_ENABLED` to `false`, disable the Jira rule, cancel running workflows.
2. **Contain:** close the PR. If something was merged, revert it with a normal PR and release as usual. If a secret may have been exposed, rotate it (table above) before anything else.
3. **Find the cause:** the commit trailers `Jira:` and `Agent-Run:` lead to the ticket and the run. Read the ticket text (was there an injection attempt?), `summary.md`, the patch artifact, and the run log. Check who moved the ticket to `Ready for Agent` in Jira's history.
4. **Check the audit trail:** Actions run history, the App's commits (`<slug>[bot]`), the repository audit log, the Jira rule audit log.
5. **Fix the gap:** add the missing path to `protectedPaths`, add a test in `tests/AgentFlow`, tighten `CLAUDE.md` or the tool list. These are protected files, so a person makes the change in a reviewed PR.
6. **Resume:** set `AGENT_ENABLED` back to `true` and enable the rule. Write down what happened.
