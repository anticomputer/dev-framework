# Contributing to dev-framework

Thanks for helping improve the framework. It's small, shell-based, and self-testing —
contributions should keep it that way.

The framework ships for **two hosts**, GitHub Copilot CLI and Claude Code, from one tree:
shared engine, two manifests, two hook wirings. Every change has to work on both.

## Layout

| Path | What it is |
|------|-----------|
| `plugin.json` | Copilot CLI manifest (declares `agents`, `skills`, `hooks`). |
| `.github/plugin/marketplace.json` | Copilot CLI marketplace entry so it installs by name. |
| `.claude-plugin/plugin.json` | Claude Code manifest (`agents/`/`skills/` auto-discovered). |
| `.claude-plugin/marketplace.json` | Claude Code marketplace entry (`source: "./"`). |
| `hooks/hooks.copilot.json` | Copilot CLI event wiring (camelCase events, `bash` key). |
| `hooks/hooks.claude.json` | Claude Code event wiring (PascalCase events, nested `hooks`). |
| `hooks/lib/*.sh` | The continuous-enforcement engine — shared by both hosts. |
| `rules/*.md` | The constitution. Injected into context at session start when active. |
| `agents/*.agent.md` | Specialist subagents (frontmatter `name`, `description`, `disallowedTools`). |
| `skills/<name>/SKILL.md` | Invokable workflows (frontmatter `name`, `description`). |
| `bin/df` | The `df` CLI (host + profile launcher). |
| `tests/run.sh` | Self-contained test suite. |
| `.github/scripts/validate-manifests.py` | Manifest/schema validator for both hosts. |

## Develop & test locally

```bash
# Run the full test suite (needs bash, python3, git — no copilot or claude required):
bash tests/run.sh

# Validate the manifests for both hosts against the documented schemas:
python3 .github/scripts/validate-manifests.py

# Optional, if you have Claude Code — checks the live Claude Code schema
# (skips cleanly when `claude` isn't installed):
bash tests/validate-claude-schema.sh

# Syntax-check the shell:
for f in bin/df install.sh uninstall.sh hooks/lib/*.sh tests/*.sh; do bash -n "$f"; done

# Install your working copy into every CLI you have and iterate:
./install.sh                 # registers this dir as a marketplace and installs
# ...make changes...
copilot plugin update dev-framework   # and/or: claude plugin update dev-framework
```

CI (`.github/workflows/ci.yml`) runs all of the above on every push and PR.

## Conventions

- **Hooks must no-op when dormant.** Every hook script starts with `df_active || exit 0`.
  Nothing the framework does may change behavior unless a session has opted in.
- **Respect profiles.** Read behavior via `df_opt <key>` (config value, else profile
  default) rather than hard-coding. Advisory must never block.
- **Shared logic lives in `hooks/lib/common.sh`.** Reuse the helpers (`df_cfg`, `df_opt`,
  `df_host`, `df_tool_file`, `df_match_globs`, `df_emit_context`, `df_emit_block`,
  `df_emit_deny`, …) — don't re-implement. The `df_emit_*` helpers in particular speak both
  hosts' output dialects; hand-rolled JSON will silently not work on one of them.
- **Both hosts or neither.** Branch on `df_host` when behavior genuinely must differ, and
  wire new hook events into *both* `hooks/hooks.copilot.json` and `hooks/hooks.claude.json`.
- **Every behavior change needs a test** in `tests/run.sh` (dogfooding our own testing
  discipline). Use stub commands (`sh -c '...'`) so tests don't depend on real tools, and
  cover both hosts when the change touches hook I/O.
- **Keep config flat.** `.dev-framework.yml` is parsed as simple `key: value` lines, not
  full YAML. Document new keys in `.dev-framework.example.yml` and `df init`.

## Adding a component

- **Agent:** add `agents/<name>.agent.md` with `name`/`description` frontmatter (plus
  `disallowedTools` as a **comma-separated string** — a YAML list breaks Claude Code) and a
  strong "investigation only, never edit" body. Reviewers must not modify code.
- **Skill:** add `skills/<name>/SKILL.md` (frontmatter `name`, `description`) and list it in
  `plugin.json` `skills`. Claude Code discovers `skills/` automatically.
- **Hook:** add a script under `hooks/lib/`, set `DF_EVENT` at the top of it, and wire it into
  **both** configs under the right event: `hooks/hooks.copilot.json` (`sessionStart`,
  `preToolUse`, `postToolUse`, `agentStop`, …) and `hooks/hooks.claude.json` (`SessionStart`,
  `PreToolUse`, `PostToolUse`, `Stop`, …). Add the event to the validator's name sets.
- **Rule:** add `rules/NN-topic.md`; it's injected automatically (numbered for order). Keep
  the prose host-neutral — put host-specific detail in the session-start banner.

Then add tests and run `bash tests/run.sh` + the validator before opening a PR.
