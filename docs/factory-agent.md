# The factory's agent

One workflow, `.github/workflows/agent.yml`, runs the factory's coding agent for every repository of AgentsKit-io and
NoxCodeSolutions. A repository opts in with a short caller, `.github/workflows/agent.yml`:

```yaml
name: agent
on:
  issues:
    types: [labeled]
  issue_comment:
    types: [created]
permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write
jobs:
  agent:
    if: >-
      (github.event_name == 'issues' && github.event.label.name == 'agent:go') ||
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude'))
    uses: AgentsKit-io/.github/.github/workflows/agent.yml@main
```

Flow: the PM validates a request (definition of ready) and labels the issue `agent:go`; the agent runs Claude Code on a
self-hosted runner labelled `agent` (cleaned before and after every job), pushes a branch, opens the PR (`Closes #N`) and
enables auto-merge; the required checks decide. Issues labelled `risco` wait for a human merge. "@claude" in a comment by a
member continues the work on the same issue or PR.

Inputs: `model` (default `sonnet`), `max-turns` (80), `install` (`auto` by lockfile, `none`, or a command), `runner-label`
(`agent`). Repository settings the flow expects: the label `agent:go`, auto-merge allowed, branches deleted on merge, and
(public repositories) workflow approval for first-time contributors.
