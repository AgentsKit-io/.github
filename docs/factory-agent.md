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
(`agent`), `factory-actors` (`noxcode-factory[bot],EmersonBraun`) and `default-dispatcher` (`EmersonBraun`), below. Repository settings the flow expects: the label `agent:go`, auto-merge allowed, branches deleted on merge, and
(public repositories) workflow approval for first-time contributors.

## Pool do despachante (whose account pool pays the task)

Each person of the team has their own account pool, and a task runs on the pool of whoever dispatched it, never on
another one. The step "Pool do despachante" (`.github/scripts/dispatcher-pool.sh`, embedded in `agent.yml`) runs before
the agent:

1. The dispatcher. An `agent:go` issue: its `por:<login>` label, valid only if the last `labeled` event of that label in
   the issue timeline was made by one of `factory-actors` (the factory's GitHub App bot and the login of the current
   release); no `por:` label: `default-dispatcher` (the owner: everything dispatched before the labels was theirs). An
   "@claude" comment: the comment author.
2. The pool. The runner holds one file per person, `$HOME/.pools/<login in lower case>.env` with `POOL_BASE_URL` and
   `POOL_KEY` (written by the factory's `pool-sync`). The step reads it as data, masks the key and exports `POOL_KEY`
   and `POOL_BASE_URL` (a trailing `/v1` dropped); `ANTHROPIC_BASE_URL` of both agent runs (and the retry) is
   `POOL_BASE_URL`, with the runner's local `HTTP_PROXY` kept on self-hosted runners.
3. No pool: a `por:` label put by anyone else, two `por:` labels, an invalid login (`^[A-Za-z0-9-]{1,39}$`), an
   unreadable timeline, no file or a file without a usable key. The step comments "sem pool do despachante @<login>:
   <motivo>" on the issue and the agent does not run (the job ends green, the comment is the signal).

The pools are read on the runner, not passed as secrets: callers do not pass `secrets: inherit`, and the NoxCodeSolutions
repositories call this workflow across organizations, where per-person organization secrets would not reach it.

Transition: on a runner with no `$HOME/.pools/` at all, the owner's tasks keep the old `$HOME/.pool-key` and the pool at
`http://100.87.168.68:8317`; nobody else ever uses it. Hosted runners (`hosted: true`) only have the owner's pool, the
organization secret `FACTORY_POOL_KEY` (public AgentsKit-io repositories only); another dispatcher on a hosted runner
stops with the comment. The risk review (`risk-review.yml`) is the factory's work and runs on the owner's pool (input
`owner`).

Tests: `bash scripts/test-dispatcher-pool.sh` (fake `gh`, throwaway HOME; also checks that the copy embedded in
`agent.yml` is identical to the script). After changing the script, copy it into the step's heredoc (indented by ten
spaces).
