# Jira setup

How to connect Jira Cloud to the workflow. Do the GitHub side first ([RUNBOOK.md](../RUNBOOK.md), "Setup"), because the rule needs a token for this repository.

Status: written from the workflow code and Jira Automation's documented behaviour. It has not been run against a live Jira site (see [README.md](../README.md), "Status"). Menu names can differ slightly between Jira versions.

## What Jira sends

One HTTP request when a ticket reaches "Ready for Agent" and carries the label `agent-ok`. It contains only the issue key. The workflow reads the rest from Jira itself, so the request is a pointer, not a source of truth.

## 1. Service account

1. Create a Jira user for the agent, for example `agent-bot@your-domain`. Use a real Atlassian account so it can have an API token.
2. Give it access to the `DEVOPS` project only, with the permissions Browse projects and Add comments. Nothing else: no edit, no transition, no admin.
3. Create an API token for it (Atlassian account settings, Security, API tokens).
4. Store the token as the secret `JIRA_API_TOKEN` in the GitHub environments `agent-intake` (see the runbook). Set the repository variables `JIRA_BASE_URL` (for example `https://your-site.atlassian.net`) and `JIRA_USER_EMAIL` (the service account's email).

The agent only reads tickets and adds comments. It never moves a ticket; a person does that.

## 2. Status and label

1. In the `DEVOPS` workflow, add a status named exactly `Ready for Agent`. The check compares the name, so spelling and case matter (`policy.json`, `jira.readyStatus`).
2. Make sure the label `agent-ok` can be added. Labels are free text in Jira; the check is on the exact string (`jira.requiredLabel`).
3. Allowed issue types are Task, Bug and Story. Other types are rejected at intake.

Who may move tickets into "Ready for Agent" and add `agent-ok` is who may start the agent. Restrict that in the project's workflow transition conditions or permissions.

## 3. GitHub token for the rule

GitHub's `repository_dispatch` endpoint accepts a fine-grained personal access token with **Contents: read and write** on the repository. That is the minimum GitHub requires for this call.

1. Create a fine-grained PAT. Resource owner: `kaushik-sai`. Repository access: only `agentic-devops-workflow`. Repository permission: Contents, read and write. Nothing else. Set an expiry.
2. Prefer a PAT owned by a machine user or a bot account, not a person who might leave.
3. Keep it only in the Jira rule's secret field (next section). Do not put it in GitHub.

This token can write contents to the repository, so treat it like a deploy key. Rulesets on `main` still stop it pushing there directly, but it could create branches. See [SECURITY.md](../SECURITY.md).

## 4. The automation rule

In the `DEVOPS` project: Project settings, Automation, Create rule.

1. **Trigger:** Work item transitioned (Issue transitioned). To status: `Ready for Agent`.
2. **Condition:** Issue fields condition. Labels contains `agent-ok`.
   Optional second condition: Issue type is one of Task, Bug, Story. Intake checks this again, so it is only to avoid pointless runs.
3. **Action:** Send web request.
   - Web request URL:
     ```
     https://api.github.com/repos/kaushik-sai/agentic-devops-workflow/dispatches
     ```
   - HTTP method: `POST`
   - Web request body: Custom data
   - Headers (add these four):

     | Header | Value |
     |---|---|
     | `Authorization` | `Bearer <the fine-grained PAT>` (mark the header as hidden / secret) |
     | `Accept` | `application/vnd.github+json` |
     | `X-GitHub-Api-Version` | `2022-11-28` |
     | `Content-Type` | `application/json` |

   - Custom data (body):
     ```json
     {
       "event_type": "jira-ticket-ready",
       "client_payload": {
         "issue_key": "{{issue.key}}"
       }
     }
     ```
   - Wait for response: leave off. GitHub answers `204 No Content` when the dispatch is accepted.
4. Name the rule `Agent: dispatch ready ticket`, turn it on.

Use Jira's hidden header option for `Authorization`, so the token is stored as a secret and not shown in the rule or its audit log.

## The exact request

Equivalent `curl`, to test the token from a terminal without Jira:

```bash
curl -sS -X POST \
  -H "Authorization: Bearer $GITHUB_PAT" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/json" \
  https://api.github.com/repos/kaushik-sai/agentic-devops-workflow/dispatches \
  -d '{"event_type":"jira-ticket-ready","client_payload":{"issue_key":"DEVOPS-42"}}'
```

Expected: HTTP 204 and no body. The `agent-ticket-to-pr` workflow then appears in the Actions tab with the event `repository_dispatch`.

## 5. Test it

1. Create a small ticket, for example `Add Get-ReorderReport that lists SKUs at or below their reorder point`, type Task, in project `DEVOPS`.
2. Add the label `agent-ok`.
3. Move it to `Ready for Agent`.
4. Check the rule's audit log in Jira (Automation, the rule, Audit log). A successful web request shows status 204.
5. Check Actions on GitHub. Intake should pass; the Jira ticket gets a comment with the PR link when the run ends.

If the audit log shows 401 or 404, the token is wrong, expired or has no access to the repository. If it shows 422, the body is not valid JSON (check the quotes around `{{issue.key}}`). If Jira shows 204 but nothing runs, `AGENT_ENABLED` is probably not `true`, or the workflow file is not on the default branch.

## Manual start without Jira

Run the workflow by hand with the key:

```bash
gh workflow run agent-ticket-to-pr.yml -f issue_key=DEVOPS-42
```

Intake still reads the ticket from Jira and applies all the same checks.

## Rotating the token

Create a new PAT, edit the rule's header with the new value, delete the old PAT. The next dispatch uses the new one. No GitHub setting changes.
