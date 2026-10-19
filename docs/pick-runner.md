# Pick a CI runner

Private repositories can call `pick-runner.yml` to spend included GitHub Actions
minutes first, then use Depot. Public repositories never use Depot: Actions is
free there, so the picker returns GitHub-hosted runners for them (and runs on
one itself). The organization runs no Windows jobs in CI.

Decision order:

1. A nonempty `force_runner` wins, without billing calls.
2. A public repository (`github.event.repository.private == false`) gets
   `ubuntu-latest` (`ubuntu-24.04-arm` for `arm`; variants `4`/`8` warn and
   also get `ubuntu-latest`), without billing calls. Unknown visibility follows
   the private rules.
3. Variants `4` and `8` always use `depot-ubuntu-24.04-4` / `-8`:
   GitHub larger runners do not use included minutes.
4. Read the current UTC month's organization billing usage and all private repos.
   Count only private-repository Actions minutes: Linux ×1, Windows ×2, macOS ×10.
   Ignore storage and public repositories. Unknown minute SKUs count ×1 and warn.
5. If `included_minutes - used > min_remaining`, use `ubuntu-latest` (or
   `ubuntu-24.04-arm` for `arm`); otherwise use `depot-ubuntu-24.04` (or `-arm`).
   Missing token, API failures, or malformed responses warn and use Depot.

Defaults: `min_remaining: 100`, `included_minutes: 2000`, `variant: ''`,
`force_runner: ''`. The picker itself runs on Depot in private repositories and
on `ubuntu-latest` in public ones, with a three-minute timeout
and no `GITHUB_TOKEN` permissions. It logs used/remaining minutes, label, and
reason to the job log and step summary. It does not check out the caller.

## Prerequisites

- Install the Depot GitHub App on the organization with access to the callers.
- Set organization secret `ORG_BILLING_TOKEN`, available to private repositories.
  Use a token belonging to an organization **OWNER**:
  - Fine-grained PAT: resource owner `AgentsKit-io`, organization permission
    **Administration: read**, plus repository **Metadata: read** on all repos
    to enumerate private repositories. This fine-grained permission combination
    has **not been verified in a run yet**.
  - Or classic PAT with `read:org` + `repo`.
- Set `included_minutes` to the organization's plan allowance (default is the
  GitHub Free allowance of 2,000 minutes).

The [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#standard-github-hosted-runners-for--private-repositories)
was checked on 2026-10-16: it lists `ubuntu-24.04-arm` among standard private
repository runners using the account's included minutes, without a paid-plan
restriction. This is the standard runner, not a larger runner.

- Organization Actions policy must allow repositories to use actions and reusable
  workflows from `AgentsKit-io` (Settings → Actions → General).

Notes:

- Dependabot-triggered runs do not receive Actions secrets, so the picker has no
  token there: it warns and uses Depot. Add `ORG_BILLING_TOKEN` as a Dependabot
  secret too if those runs should use GitHub minutes.
- In private repositories the picker job runs on Depot (a few seconds per
  workflow run), because the GitHub quota may already be exhausted when it runs.
  Depot's runner group does not allow public repositories.

Depot usage caps (organization settings): GitHub Actions 60,000 minutes/month,
container builds 500, Depot CI 2,000. When a cap is reached, Depot jobs do not
start until the next billing period or until the cap is raised.

## Callers

```yaml
jobs:
  pick-runner:
    uses: AgentsKit-io/.github/.github/workflows/pick-runner.yml@main
    with:
      force_runner: ${{ vars.FORCE_RUNNER }}
    secrets:
      ORG_BILLING_TOKEN: ${{ secrets.ORG_BILLING_TOKEN }}

  build:
    needs: [pick-runner]          # append to an existing needs list, keep the others
    runs-on: ${{ needs.pick-runner.outputs.runner }}
```

Use one `pick-runner` job per workflow file, shared by every consuming job.
Each consumer must list `pick-runner` in its own `needs`, even if another
dependency already uses it. For an OS matrix, leave the matrix values untouched:

```yaml
runs-on: ${{ matrix.os == 'ubuntu-latest' && needs.pick-runner.outputs.runner || matrix.os }}
```

Set repository or organization variable `FORCE_RUNNER` to override selection,
for example `depot-ubuntu-24.04` or `ubuntu-latest`. Pass `variant: arm`, `4`, or
`8` through `with` when needed (quote numeric variants as strings).

## Local verification

Run `actionlint .github/workflows/*.yml` and
`python3 scripts/test-pick-runner.py --live` (omit `--live` for fixtures only).
The test extracts the actual inline workflow script, mocks only the `gh` response
boundary for fixtures, and uses the logged-in `gh` credential store for live
read-only snapshots. Raw API responses are temporary and removed on exit.
This does not execute a hosted Actions or Depot job; the self-test caller will
exercise that integration after publication.
