# Reusable CI pipeline (`ci.yml`)

`.github/workflows/ci.yml` is a reusable pipeline for JavaScript and TypeScript
repositories. A repository keeps its own triggers, release jobs and
product-specific checks, and calls this workflow for the common stages.

## What runs when

| Event | Mode | Stages |
| --- | --- | --- |
| Draft pull request | `draft` | plan, lint |
| Pull request whose files all match `light-paths` | `light` | plan, lint |
| Ready pull request, merge queue | `pr` | plan, lint + typecheck, tests (`affected-test-command`), build |
| Push to the branch | `seed` | plan, dependency cache refresh |
| Schedule, with a commit in the last `nightly-window-hours` | `full` | plan, lint + typecheck, tests (`test-command`), build |
| Schedule, nothing new | `skip` | plan |
| Manual run | `full` | as the schedule |

The stages are a chain: a red stage skips the stages after it, and a
`cancel on failure` job cancels the rest of the caller's run (its own product
jobs included). Every job has a timeout (`job-timeout-minutes`, default 20).
The calling job's result (`needs.<job>.result`) is the pipeline's result, so a
small gate job can keep an existing required check name:

```yaml
  verify:
    needs: pipeline
    if: always()
    runs-on: ubuntu-24.04
    steps:
      - run: test "$RESULT" = success
        env:
          RESULT: ${{ needs.pipeline.result }}
```

## Tools

- **Install:** Bun (`installer: auto`, the default) with a fallback to the
  lockfile's package manager (pnpm or npm) when `bun install` fails. Use
  `installer: native` when Bun installs a tree the repository cannot use.
  Pull requests only restore the dependency cache; pushes to the branch save it.
- **Lint:** oxlint, pinned (`oxlint-version`), with GitHub annotations.
  Add a `.oxlintrc.json` or `oxlint-args` for project rules.
- **Format:** Biome, pinned (`biome-version`), formatter only. With
  `format-scope: added` (the default), files a pull request adds must be
  formatted and files it modifies only get a warning, so an unformatted
  codebase can adopt the check without a repository-wide reformat. The check
  needs a `biome.json` at the repository root.
- **Typecheck, tests, build:** the repository's own commands.

## Per-test time budget (Vitest)

The test stage exports `CI_TEST_PROFILE` (`pr` on pull requests, `full`
otherwise). A Vitest config can use it to keep pull requests fast:

```ts
import { configDefaults, defineConfig } from 'vitest/config'

const pr = process.env.CI_TEST_PROFILE === 'pr'

export default defineConfig({
  test: {
    // Report tests slower than 2 s; fail a pull-request test after 10 s.
    slowTestThreshold: 2_000,
    testTimeout: pr ? 10_000 : 30_000,
    // Long tests live in *.slow.test.* files and run on the schedule only.
    exclude: [...configDefaults.exclude, ...(pr ? ['**/*.slow.test.*'] : [])],
  },
})
```

The same flags work on the command line:
`vitest run --slowTestThreshold=2000 --testTimeout=10000 --exclude='**/*.slow.test.*'`.

## Caller example

```yaml
name: CI
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
  push:
    branches: [main]
  schedule:
    - cron: '30 3 * * *'
  workflow_dispatch:
permissions: {}
concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
jobs:
  pipeline:
    uses: AgentsKit-io/.github/.github/workflows/ci.yml@<full commit SHA>
    permissions:
      contents: read
      actions: write # lets the pipeline cancel the run when a stage fails
    with:
      typecheck-command: pnpm typecheck
      affected-test-command: pnpm vitest run --changed "$BASE_REF"
      test-command: pnpm test
      build-command: pnpm build
      light-paths: |
        *.md
        docs/*
```

Every job runs on `ubuntu-24.04` (GitHub-hosted) unless the caller passes
`runs-on`, which takes JSON: a label (`'"ubuntu-24.04"'`) or a list. Public
repositories should stay on GitHub-hosted runners: they accept pull requests
from forks.

A product job that should only run on ready pull requests and full runs can
read the pipeline's mode:

```yaml
  e2e:
    needs: pipeline
    if: contains(fromJSON('["pr","full"]'), needs.pipeline.outputs.mode)
```

Uploads from caller jobs should set `retention-days` (for example 7, or 3 for
build output).
