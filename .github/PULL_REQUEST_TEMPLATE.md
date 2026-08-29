<!-- Thanks for contributing to dev-framework! Keep PRs small and focused. -->

## What & why

<!-- One or two sentences: what does this change and why? Link any issue. -->

## Checklist

- [ ] **Tests:** added/updated assertions in `tests/run.sh` for any behavior change
      (use `sh -c '...'` stubs so tests don't depend on installed tools).
- [ ] `bash tests/run.sh` passes locally.
- [ ] `python3 .github/scripts/validate-manifests.py` passes.
- [ ] `bash tests/validate-claude-schema.sh` passes (or skips — it needs Claude Code) when a
      manifest, agent, skill, or `hooks/hooks.claude.json` changed.
- [ ] `bash tests/validate-codex-schema.sh` passes (or skips—it needs Codex CLI) when Codex
      packaging, agents, skills, or hooks changed.
- [ ] `bash -n` clean for any changed shell scripts (and `shellcheck` if available).
- [ ] **Dormant-safe:** new/changed hooks start with `df_active || exit 0` and do nothing
      unless a session opts in.
- [ ] **Profile-aware:** behavior read via `df_opt` / profile defaults (advisory never
      blocks); no hard-coded gating.
- [ ] **Reused `hooks/lib/common.sh`** helpers rather than re-implementing them (including
      `df_emit_*` for hook verdicts—hand-rolled JSON breaks at least one host).
- [ ] **All hosts:** works under Copilot CLI, Claude Code, and Codex CLI. New hook events are
      wired into all three host manifests; host differences read via `df_host`.
- [ ] **Docs updated** when config/behavior changed: `CONFIGURATION.md`,
      `.dev-framework.example.yml`, `README.md`, and `df init`/`df status` as relevant.
- [ ] `CHANGELOG.md` `[Unreleased]` updated.
- [ ] **Release only:** `version` bumped in all five version-bearing files (`plugin.json`,
      `.github/plugin/marketplace.json`, `.claude-plugin/plugin.json`,
      `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json`).

<!-- See AGENTS.md and CONTRIBUTING.md for conventions and the hard-won gotchas. -->

## Notes for reviewers

<!-- Anything worth calling out: tradeoffs, follow-ups, things you're unsure about. -->
