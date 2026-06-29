# Contributing to dev-framework

Thanks for helping improve the framework. It's small, shell-based, and self-testing —
contributions should keep it that way.

## Layout

| Path | What it is |
|------|-----------|
| `plugin.json` | Plugin manifest (declares `agents`, `skills`, `hooks`). |
| `.github/plugin/marketplace.json` | Marketplace entry so it installs by name. |
| `rules/*.md` | The constitution. Injected into context at `sessionStart` when active. |
| `agents/*.agent.md` | Specialist subagents (frontmatter `name`, `description`, `tools`). |
| `hooks/hooks.json` + `hooks/lib/*.sh` | The continuous-enforcement engine. |
| `skills/<name>/SKILL.md` | Invokable workflows (frontmatter `name`, `description`). |
| `bin/df` | The `df` CLI. |
| `tests/run.sh` | Self-contained test suite. |
| `.github/scripts/validate-manifests.py` | Manifest/schema validator. |

## Develop & test locally

```bash
# Run the full test suite (needs bash, python3, git — no copilot required):
bash tests/run.sh

# Validate the manifests against the documented schema:
python3 .github/scripts/validate-manifests.py

# Syntax-check the shell:
for f in bin/df install.sh uninstall.sh hooks/lib/*.sh tests/run.sh; do bash -n "$f"; done

# Install your working copy into Copilot CLI and iterate:
./install.sh                 # registers this dir as a marketplace and installs
# ...make changes...
copilot plugin update dev-framework   # or re-run ./install.sh to pick up changes
```

CI (`.github/workflows/ci.yml`) runs all of the above on every push and PR.

## Conventions

- **Hooks must no-op when dormant.** Every hook script starts with `df_active || exit 0`.
  Nothing the framework does may change behavior unless a session has opted in.
- **Respect profiles.** Read behavior via `df_opt <key>` (config value, else profile
  default) rather than hard-coding. Advisory must never block.
- **Shared logic lives in `hooks/lib/common.sh`.** Reuse the helpers (`df_cfg`, `df_opt`,
  `df_match_globs`, `df_emit_context`, `df_emit_block`, `df_emit_deny`, …) — don't
  re-implement.
- **Every behavior change needs a test** in `tests/run.sh` (dogfooding our own testing
  discipline). Use stub commands (`sh -c '...'`) so tests don't depend on real tools.
- **Keep config flat.** `.dev-framework.yml` is parsed as simple `key: value` lines, not
  full YAML. Document new keys in `.dev-framework.example.yml` and `df init`.

## Adding a component

- **Agent:** add `agents/<name>.agent.md` with `name`/`description`/`tools` frontmatter and
  a strong "investigation only, never edit" body. Reviewers must not modify code.
- **Skill:** add `skills/<name>/SKILL.md` (frontmatter `name`, `description`) and list it in
  `plugin.json` `skills`.
- **Hook:** add a script under `hooks/lib/` and wire it into `hooks/hooks.json` under the
  correct event (`sessionStart`, `preToolUse`, `postToolUse`, `agentStop`, …).
- **Rule:** add `rules/NN-topic.md`; it's injected automatically (numbered for order).

Then add tests and run `bash tests/run.sh` + the validator before opening a PR.
