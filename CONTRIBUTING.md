# Contributing to dev-framework

Thanks for helping improve the framework. It's small, shell-based, and self-testing —
contributions should keep it that way.

The framework ships for **three hosts**—GitHub Copilot CLI, Claude Code, and Codex CLI—from
one tree: shared engine, three manifests, three hook wirings. Every change has to work on all.

## Layout

| Path | What it is |
|------|-----------|
| `plugin.json` | Copilot CLI manifest (declares `agents`, `skills`, `hooks`). |
| `.github/plugin/marketplace.json` | Copilot CLI marketplace entry so it installs by name. |
| `.claude-plugin/plugin.json` | Claude Code manifest (`agents/`/`skills/` auto-discovered). |
| `.claude-plugin/marketplace.json` | Claude Code marketplace entry (`source: "./"`). |
| `.codex-plugin/plugin.json` | Codex CLI manifest (declares shared `skills/` and Codex hooks). |
| `.agents/plugins/marketplace.json` | Codex CLI local/repository marketplace entry. |
| `hooks/hooks.copilot.json` | Copilot CLI event wiring (camelCase events, `bash` key). |
| `hooks/hooks.claude.json` | Claude Code event wiring (PascalCase events, nested `hooks`). |
| `hooks/hooks.codex.json` | Codex CLI event wiring (PascalCase events, nested `hooks`). |
| `hooks/lib/*.sh` | The continuous-enforcement engine — shared by all hosts. |
| `rules/*.md` | The constitution. Injected into context at session start when active. |
| `agents/*.agent.md` | Specialist subagents (frontmatter `name`, `description`, `disallowedTools`). |
| `codex-agents/*.toml` | Installer-managed read-only Codex specialist definitions. |
| `skills/<name>/SKILL.md` | Invokable workflows (frontmatter `name`, `description`). |
| `bin/df` | The `df` CLI (host + profile launcher). |
| `tests/run.sh` | Self-contained test suite. |
| `.github/scripts/validate-manifests.py` | Manifest/schema validator for all hosts. |

## Develop & test locally

```bash
# Run the full test suite (needs bash, python3, git — no host CLI required):
bash tests/run.sh

# Validate the manifests for all hosts against the documented schemas:
python3 .github/scripts/validate-manifests.py

# Optional, if you have Claude Code — checks the live Claude Code schema
# (skips cleanly when `claude` isn't installed):
bash tests/validate-claude-schema.sh
bash tests/validate-codex-schema.sh

# Syntax-check the shell:
for f in bin/df install.sh uninstall.sh hooks/lib/*.sh tests/*.sh; do bash -n "$f"; done

# Install your working copy into every CLI you have and iterate:
./install.sh                 # registers this dir as a marketplace and installs
# ...make changes...
copilot plugin update dev-framework   # or update/reinstall through the selected host
```

CI (`.github/workflows/ci.yml`) runs syntax, ShellCheck, JSON, static manifest validation,
and the deterministic suite. The live host validators remain local optional checks.

## Conventions

- **Hooks must no-op when dormant.** Every hook script starts with `df_active || exit 0`.
  Nothing the framework does may change behavior unless a session has opted in.
- **Respect profiles.** Read behavior via `df_opt <key>` (config value, else profile
  default) rather than hard-coding. Advisory must never block.
- **Shared logic lives in `hooks/lib/common.sh`.** Reuse the helpers (`df_cfg`, `df_opt`,
  `df_host`, `df_tool_files`, `df_match_globs`, `df_emit_context`, `df_emit_block`,
  `df_emit_deny`, …) — don't re-implement. The `df_emit_*` helpers speak all supported
  output dialects; hand-rolled JSON will silently fail on at least one host.
- **All hosts or none.** Branch on `df_host` when behavior genuinely must differ, and wire
  new hook events into `hooks/hooks.copilot.json`, `hooks/hooks.claude.json`, and
  `hooks/hooks.codex.json`.
- **Every behavior change needs a test** in `tests/run.sh` (dogfooding our own testing
  discipline). Use stub commands (`sh -c '...'`) so tests don't depend on real tools, and
  cover all affected hosts when the change touches hook I/O.
- **Keep config flat.** `.dev-framework.yml` is parsed as simple `key: value` lines, not
  full YAML. Document new keys in `.dev-framework.example.yml` and `df init`.

## Adding a component

- **Agent:** add `agents/<name>.agent.md` with `name`/`description` frontmatter (plus
  `disallowedTools` as a **comma-separated string** — a YAML list breaks Claude Code) and a
  strong "investigation only, never edit" body. Add the read-only Codex translation under
  `codex-agents/`. Reviewers must not modify code.
- **Skill:** add `skills/<name>/SKILL.md` (frontmatter `name`, `description`) and list it in
  `plugin.json` `skills`. Claude Code discovers `skills/` automatically.
- **Hook:** add a script under `hooks/lib/`, set `DF_EVENT` at the top of it, and wire it into
  all three configs under the right event: Copilot's camelCase event and the PascalCase
  Claude/Codex events. Add the event to every validator name set.
- **Rule:** add `rules/NN-topic.md`; it's injected automatically (numbered for order). Keep
  the prose host-neutral — put host-specific detail in the session-start banner.

Then add tests and run `bash tests/run.sh` + the validator before opening a PR.
