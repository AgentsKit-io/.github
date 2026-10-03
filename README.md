# .github
Shared reusable workflows and dependency-update presets for AgentsKit-io repositories
# AgentsKit shared GitHub configuration

This public repository provides reusable security checks and an organization
Renovate preset. Each calling repository keeps its own triggers, build matrix,
release workflow, and package-specific checks.

## Reusable security workflows

Each caller should pin a reusable workflow to a full commit SHA. The examples
below use the initial security-workflow revision
`518006fb10c42cefb345af3d451f6677742a09c9`; update that reference only after
reviewing a newer revision.

| Workflow | What it checks | Inputs |
| --- | --- | --- |
| `codeql.yml` | CodeQL static analysis and SARIF upload. Uses the selected language set, query suite, and build mode. | `languages` (required, comma-separated); `queries` (default `security-extended`); `build-mode` (default `autobuild`) |
| `scorecard.yml` | OpenSSF Scorecard and publishes its SARIF results. | None |
| `dependency-review.yml` | New or changed dependencies on pull requests. Does not write PR comments. | `fail-on-severity` (`critical` by default; use `high` to match stricter current callers); `deny-licenses`; `allow-licenses` (comma-separated SPDX values, both default empty) |
| `audit.yml` | npm or pnpm advisory audit in each supplied directory. Production-only mode omits development dependencies. | `package-manager` (`npm` or `pnpm`, required); `working-directories` (required JSON array); `audit-level` (default `high`); `production-only` (default `false`) |

The five-repository inventory informed these interfaces: CodeQL covers the
four repositories that currently run it; Scorecard and dependency review cover
those same four; package audit supports the npm root plus `apps/docs` shape and
the pnpm production audits used by the workspaces. Existing callers can retain
their severity and license policies through inputs. The central workflows do
not replace repository-specific CI, release, publishing, or build steps.

### Caller examples

CodeQL, matching the `javascript-typescript` repositories:

```yaml
name: CodeQL
on:
  push:
  pull_request:
  schedule:
    - cron: '23 5 * * 1'
permissions:
  contents: read
jobs:
  analyze:
    uses: AgentsKit-io/.github/.github/workflows/codeql.yml@518006fb10c42cefb345af3d451f6677742a09c9
    with:
      languages: javascript-typescript
      queries: security-extended
      build-mode: autobuild
    permissions:
      actions: read
      contents: read
      security-events: write
```

Scorecard:

```yaml
name: Scorecard
on:
  branch_protection_rule:
  schedule:
    - cron: '17 4 * * 1'
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  scorecard:
    uses: AgentsKit-io/.github/.github/workflows/scorecard.yml@518006fb10c42cefb345af3d451f6677742a09c9
    permissions:
      contents: read
      id-token: write
      security-events: write
```

Dependency review, preserving the GPL/AGPL deny list used by AgentsKit:

```yaml
name: Dependency Review
on:
  pull_request:
permissions:
  contents: read
jobs:
  review:
    uses: AgentsKit-io/.github/.github/workflows/dependency-review.yml@518006fb10c42cefb345af3d451f6677742a09c9
    with:
      fail-on-severity: high
      deny-licenses: GPL-2.0,GPL-3.0,AGPL-1.0,AGPL-3.0
    permissions:
      contents: read
      pull-requests: read
```

npm audit for Code Review's production dependencies in both package roots:

```yaml
name: Dependency Audit
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  audit:
    uses: AgentsKit-io/.github/.github/workflows/audit.yml@518006fb10c42cefb345af3d451f6677742a09c9
    with:
      package-manager: npm
      working-directories: '[".","apps/docs"]'
      audit-level: high
      production-only: true
    permissions:
      contents: read
```

For a pnpm workspace, use `package-manager: pnpm`, pass its lockfile root (or
each audited workspace directory) in `working-directories`, and set
`audit-level: critical` to preserve the current Chat and Playbook threshold.
Do not use `secrets: inherit`; these security workflows need no caller secrets.

### Pin updates

External actions are pinned to full commit SHAs. The adjacent version comments
record the upstream release represented by each SHA. When updating an action,
select the newest version already exercised in the five-repository inventory,
verify the release SHA against the upstream repository, update the comment,
and run the self-test. Callers pin this repository's reusable workflows to a
reviewed full commit SHA; Renovate can propose those pin updates for review.
The self-test runs on pushes and pull requests, invokes each reusable workflow
on this repository where applicable, and runs actionlint v1.7.12. The central
repository has no package manifests, so the audit call uses an empty directory
list and is intentionally skipped. Dependency review needs GitHub's dependency
graph, which is disabled here; that reusable workflow is validated by
actionlint and should be exercised by a caller repository with the graph
enabled. Scorecard runs on PRs and on pushes to the default branch because the
upstream action only accepts the default branch for push events.
