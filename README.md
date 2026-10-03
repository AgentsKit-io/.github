# AgentsKit shared GitHub configuration

This public repository provides reusable security checks and an organization
Renovate preset. Each calling repository keeps its own triggers, build matrix,
release workflow, and package-specific checks.

## Renovate organization preset

Repositories opt in by adding a `renovate.json` file:

```json
{
  "extends": ["github>AgentsKit-io/.github"]
}
```

The preset schedules updates weekly, groups npm development patch/minor
updates and GitHub Actions, and groups production runtime patch/minor updates
for human review. It enables platform automerge only for development
patch/minor and GitHub Actions digest/patch/minor updates, so GitHub's required
checks must pass first. Major updates stay separate and never automerge.
GitHub Actions are pinned to commit digests with release comments. A three-day
minimum release age applies to npm updates. npm workspaces and pnpm workspaces
remain discovered from their package manifests and lockfiles; no manager or
workspace paths are hard-coded. The preset widens runtime dependency ranges
for library packages instead of pinning published runtime dependencies.

When migrating a repository from Dependabot, add `renovate.json` and remove
the version-update entries in `.github/dependabot.yml` in the **same PR**.
Keep Dependabot security alerts enabled; they are separate from Dependabot
version update configuration.
