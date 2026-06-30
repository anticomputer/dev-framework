# AGENTS.md — working on dev-framework itself

This repo **is** a GitHub Copilot CLI plugin that enforces engineering discipline on
Copilot sessions. When you work on it, you're improving that tool. It **dogfoods itself**:
a committed `.dev-framework.yml` activates the framework for sessions here, so the same
quality bar you ship applies to your own changes.

New to the project? Read [`README.md`](README.md) first (what it does and why), then
[`CONTRIBUTING.md`](CONTRIBUTING.md) (layout + dev loop) and
[`CONFIGURATION.md`](CONFIGURATION.md) (the `.dev-framework.yml` grammar).

## Build / test / validate

No build step. Everything is bash + a little Python. Before finishing any change, run:

```bash
bash tests/run.sh                          # the test suite (48+ assertions)
python3 .github/scripts/validate-manifests.py   # manifest/schema validation
for f in bin/df hooks/lib/*.sh tests/run.sh install.sh uninstall.sh; do bash -n "$f"; done
```

CI (`.github/workflows/ci.yml`) runs exactly these plus `shellcheck --severity=error`.
Requirements: `bash`, `python3`, `git` (no `copilot` needed for the suite — hooks are
tested by feeding them the same JSON event payloads the CLI sends).

To try a change in a real session: `./install.sh` (registers this dir as a marketplace and
installs via `copilot plugin install`), then `copilot plugin update dev-framework` to pick
up further edits. `./uninstall.sh` to remove.

## Repo map

| Path | What it is |
|------|-----------|
| `plugin.json` | Plugin manifest. Supported component fields: `agents`, `skills`, `commands`, `hooks`, `extensions`, `mcpServers`, `lspServers`. **There is no `rules` field.** |
| `.github/plugin/marketplace.json` | Marketplace entry (so `copilot plugin install name@marketplace` works). |
| `rules/*.md` | The constitution. **Injected at `sessionStart` (see `hooks/lib/session-start.sh`)**, not via a plugin field — that's how it stays dormant unless active. |
| `agents/*.agent.md` | Specialist subagents (frontmatter `name`, `description`, `tools`). Investigation-only — they must never edit code. |
| `hooks/hooks.json` + `hooks/lib/*.sh` | The enforcement engine. `common.sh` is the shared library. |
| `skills/<name>/SKILL.md` | Invokable workflows (frontmatter `name`, `description`). |
| `bin/df` | The `df` CLI (init/status/version/profile launchers). |
| `tests/run.sh` | Self-contained test suite. |
| `.github/scripts/validate-manifests.py` | Schema validator (also rejects a stray `rules` field). |
| `examples/todo-service/` | Worked example + `WALKTHROUGH.md`. |

## Conventions (must-follow)

1. **Hooks no-op when dormant.** Every hook script starts with `df_active || exit 0`.
   Nothing may change behavior unless a session opted in. Add a test asserting the dormant
   case stays silent.
2. **Be profile-aware.** Read behavior through `df_opt <key>` (config value → profile
   default), never hard-code. `advisory` must never block; `standard`/`strict` may.
3. **Reuse `common.sh`.** Shared helpers: `df_profile`/`df_active`/`df_opt`, `df_cfg`,
   `df_lang_cmd`, `df_match_globs`, `df_changed_files`, `df_emit_context`/`df_emit_block`/
   `df_emit_deny`, `df_read_stdin`/`df_json_get`. Don't re-implement these.
4. **Every behavior change ships with a test** in `tests/run.sh`. Use stub commands
   (`sh -c '...'`) so tests never depend on real tools being installed.
5. **Keep config flat.** `.dev-framework.yml` is parsed line-by-line (`df_cfg`), not real
   YAML. New keys must be documented in `CONFIGURATION.md` **and** `.dev-framework.example.yml`,
   and surfaced by `df init`/`df status` where relevant.
6. **Language detection is gated on tool availability** (`df_bin`/`command -v`). Never emit
   a command for a tool that isn't installed.

## Hard-won gotchas (don't relearn these)

- **The official docs are authoritative** — read them, don't reverse-engineer the binary:
  https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot and
  https://docs.github.com/en/copilot/reference/cli-plugin-reference.
- **Plugins can't contribute always-on instructions** (no `rules` field) — the constitution
  is injected by the `sessionStart` hook. Keep `rules/*.md` as the source it reads.
- **Skill frontmatter is just `name` + `description`** (+ optional `license`, `allowed-tools`).
  Other fields seen in third-party repos are *their* linter's convention, not the CLI's.
- **Hook event keys** (in `hooks.json`): `sessionStart`, `userPromptSubmitted`, `preToolUse`,
  `postToolUse`, `agentStop`, `sessionEnd`, … (note `userPromptSubmitted` and `agentStop`,
  not `userPromptSubmit`/`stop`). Plugin hooks live at `hooks/hooks.json`.
- **Hook payload** arrives as JSON on stdin (snake_case: `tool_name`, `tool_input`,
  `session_id`, `hook_event_name`, `cwd`); `matcher` is matched against canonical tool names
  (`Edit`/`Write`/`edit`/`create` are all covered by the existing regex).
- **Plugin hook scripts get `$PLUGIN_ROOT` and `$COPILOT_PROJECT_DIR`** injected — use them
  (that's why the framework needs nothing copied into target repos).
- **Bash/Python pitfalls already fixed** (keep them fixed): don't combine a stdin pipe with a
  `python3 -` heredoc (the heredoc wins — pass data via env, see `df_json_get`); only strip a
  *matching* surrounding quote pair in `df_cfg` (don't strip lone quotes from commands).
- **Install is marketplace-based**; direct repo/URL/local-path installs are deprecated.

## Releasing

Bump `version` in `plugin.json` **and** `.github/plugin/marketplace.json`, move the
`CHANGELOG.md` `[Unreleased]` section under a new version heading, commit, then
`git tag -a vX.Y.Z -m "..."` and push with `--tags`.

When creating commits, append:
`Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`
