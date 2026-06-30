<!-- Thanks for contributing to dev-framework! Keep PRs small and focused. -->

## What & why

<!-- One or two sentences: what does this change and why? Link any issue. -->

## Checklist

- [ ] **Tests:** added/updated assertions in `tests/run.sh` for any behavior change
      (use `sh -c '...'` stubs so tests don't depend on installed tools).
- [ ] `bash tests/run.sh` passes locally.
- [ ] `python3 .github/scripts/validate-manifests.py` passes.
- [ ] `bash -n` clean for any changed shell scripts (and `shellcheck` if available).
- [ ] **Dormant-safe:** new/changed hooks start with `df_active || exit 0` and do nothing
      unless a session opts in.
- [ ] **Profile-aware:** behavior read via `df_opt` / profile defaults (advisory never
      blocks); no hard-coded gating.
- [ ] **Reused `hooks/lib/common.sh`** helpers rather than re-implementing them.
- [ ] **Docs updated** when config/behavior changed: `CONFIGURATION.md`,
      `.dev-framework.example.yml`, `README.md`, and `df init`/`df status` as relevant.
- [ ] `CHANGELOG.md` `[Unreleased]` updated.

<!-- See AGENTS.md and CONTRIBUTING.md for conventions and the hard-won gotchas. -->

## Notes for reviewers

<!-- Anything worth calling out: tradeoffs, follow-ups, things you're unsure about. -->
