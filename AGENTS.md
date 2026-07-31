# AGENTS.md — working on dev-framework itself

This repo **is** a plugin — shipped for **both GitHub Copilot CLI and Claude Code** — that
enforces engineering discipline on agent sessions. When you work on it, you're improving
that tool. It **dogfoods itself**: a committed `.dev-framework.yml` activates the framework
for sessions here (under either host), so the same quality bar you ship applies to your own
changes.

**Dual-host is the central design constraint.** One shared engine (`hooks/lib/*.sh`, `rules/`,
`agents/`, `skills/`) behind two manifests and two hook wirings. Any change must work on both
hosts, or explicitly branch on `df_host`.

New to the project? Read [`README.md`](README.md) first (what it does and why), then
[`CONTRIBUTING.md`](CONTRIBUTING.md) (layout + dev loop) and
[`CONFIGURATION.md`](CONFIGURATION.md) (the `.dev-framework.yml` grammar).

## Build / test / validate

No build step. Everything is bash + a little Python. Before finishing any change, run:

```bash
bash tests/run.sh                          # the test suite (115+ assertions, both hosts)
python3 .github/scripts/validate-manifests.py   # manifest/schema validation, both hosts
for f in bin/df hooks/lib/*.sh tests/*.sh install.sh uninstall.sh; do bash -n "$f"; done
```

CI (`.github/workflows/ci.yml`) runs exactly these plus `shellcheck --severity=error`.
Requirements: `bash`, `python3`, `git` (neither `copilot` nor `claude` is needed for the
suite — hooks are tested by feeding them the same JSON event payloads each CLI sends, and
`df`'s launcher is tested against stub binaries).

If you have Claude Code, also run the live schema check when you touch a manifest, an agent,
a skill, or the Claude hook wiring:

```bash
bash tests/validate-claude-schema.sh    # skips cleanly if `claude` isn't installed
```

It validates a staged copy of the repo with `claude plugin validate --strict`. Do **not** just
run `claude plugin validate .` here: that validates the marketplace manifest and stops, and
even when pointed at the plugin manifest it reads hooks only from the *default*
`hooks/hooks.json` path — it ignores the `hooks` field in the manifest, so our hook config is
silently skipped. The script stages `hooks/hooks.claude.json` at the default path to get it
actually checked. Neither check is in CI (the CLI isn't available there), which is why
`validate-manifests.py` independently enforces the event names and config shape.

To try a change in a real session: `./install.sh` (registers this dir as a marketplace and
installs into every CLI on your PATH), then `copilot plugin update dev-framework` /
`claude plugin update dev-framework` to pick up further edits. `./uninstall.sh` to remove.

## Repo map

| Path | What it is |
|------|-----------|
| `plugin.json` | **Copilot CLI** manifest. Supported component fields: `agents`, `skills`, `commands`, `hooks`, `extensions`, `mcpServers`, `lspServers`. **There is no `rules` field.** |
| `.github/plugin/marketplace.json` | **Copilot CLI** marketplace entry (so `copilot plugin install name@marketplace` works). |
| `.claude-plugin/plugin.json` | **Claude Code** manifest. Only `name` is required; `agents/` and `skills/` are auto-discovered, so it declares just metadata + the `hooks` path. Components must **never** live inside `.claude-plugin/`. |
| `.claude-plugin/marketplace.json` | **Claude Code** marketplace entry. Plugin `source` is `"./"` (the repo root); relative sources must start with `./`. |
| `hooks/hooks.copilot.json` | Copilot CLI event wiring: camelCase events, handlers flat under the event, `bash` key, `$PLUGIN_ROOT`. |
| `hooks/hooks.claude.json` | Claude Code event wiring: PascalCase events, handlers nested in a `hooks` array inside a matcher group, `command` key, `${CLAUDE_PLUGIN_ROOT}`. |
| `hooks/lib/*.sh` | The enforcement engine — **shared by both hosts**. `common.sh` is the shared library. |
| `rules/*.md` | The constitution. **Injected at session start (see `hooks/lib/session-start.sh`)**, not via a plugin field — neither host lets a plugin ship always-on instructions, and this is also how it stays dormant unless active. |
| `agents/*.agent.md` | Specialist subagents (frontmatter `name`, `description`, `disallowedTools`). Investigation-only — they must never edit code. |
| `skills/<name>/SKILL.md` | Invokable workflows (frontmatter `name`, `description`). |
| `bin/df` | The `df` CLI (init/status/version, host + profile launchers). Also on the Bash tool's `PATH` inside a Claude Code session. |
| `tests/run.sh` | Self-contained test suite, including a per-host hook-dialect section. |
| `tests/validate-claude-schema.sh` | Optional live `claude plugin validate --strict` check on a staged copy. |
| `.github/scripts/validate-manifests.py` | Schema validator for **both** ecosystems (also rejects a stray `rules` field and cross-checks manifest versions). |
| `examples/todo-service/` | Worked example + `WALKTHROUGH.md`. |

## Conventions (must-follow)

1. **Both hosts, or neither.** Every behavior change must work under Copilot CLI *and*
   Claude Code. Read the host with `df_host` (never sniff env vars yourself), name
   components with `df_agent_ref`/`df_skill_ref`, and read a tool's target path with
   `df_tool_file` (it covers `path`, `file_path`, and `notebook_path`). If you add a hook
   event, wire it in **both** `hooks/hooks.copilot.json` and `hooks/hooks.claude.json`
   using each one's schema, and add the event to both name sets in the validator.
2. **Hooks no-op when dormant.** Every hook script starts with `df_active || exit 0`.
   Nothing may change behavior unless a session opted in. Add a test asserting the dormant
   case stays silent — for both hosts.
3. **Be profile-aware.** Read behavior through `df_opt <key>` (config value → profile
   default), never hard-code. `advisory` must never block; `standard`/`strict` may.
4. **Reuse `common.sh`.** Shared helpers: `df_profile`/`df_active`/`df_opt`, `df_cfg`,
   `df_host`/`df_host_label`/`df_host_bin`/`df_agent_ref`/`df_skill_ref`, `df_lang_cmd`,
   `df_match_globs`, `df_changed_files`, `df_emit_context`/`df_emit_block`/`df_emit_deny`,
   `df_read_stdin`/`df_json_get`/`df_tool_file`/`df_hook_event`. Don't re-implement these.
   In particular, never hand-roll a hook verdict: the `df_emit_*` helpers emit the union of
   both hosts' output dialects, including the `hookEventName` discriminator Claude Code
   requires.
5. **Every behavior change ships with a test** in `tests/run.sh`. Use stub commands
   (`sh -c '...'`) so tests never depend on real tools being installed, and stub binaries
   for anything that launches a CLI. Tests must be deterministic no matter which CLI the
   contributor has installed or which one they're running the suite from — the suite
   scrubs every `CLAUDE_*`/`COPILOT_*`/`PLUGIN_ROOT`/`DF_HOST` variable up front, so each
   case declares the host it exercises.
6. **Keep config flat.** `.dev-framework.yml` is parsed line-by-line (`df_cfg`), not real
   YAML. New keys must be documented in `CONFIGURATION.md` **and** `.dev-framework.example.yml`,
   and surfaced by `df init`/`df status` where relevant.
7. **Language detection is gated on tool availability** (`df_bin`/`command -v`). Never emit
   a command for a tool that isn't installed.
8. **Keep the manifests in lockstep.** A release bumps `version` in all four manifests;
   the validator fails the build if they disagree.

## Hard-won gotchas (don't relearn these)

- **The official docs are authoritative** — read them, don't reverse-engineer the binaries:
  - Copilot CLI: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot
    and https://docs.github.com/en/copilot/reference/cli-plugin-reference
  - Claude Code: https://code.claude.com/docs/en/plugins-reference,
    https://code.claude.com/docs/en/hooks, https://code.claude.com/docs/en/plugin-marketplaces
- **Neither host lets a plugin contribute always-on instructions** (Copilot has no `rules`
  field; a `CLAUDE.md` at a plugin's root is explicitly *not* loaded) — the constitution is
  injected by the session-start hook. Keep `rules/*.md` as the source it reads.
- **Skill frontmatter is just `name` + `description`** (+ optional `license`, `allowed-tools`).
  Other fields seen in third-party repos are *their* linter's convention, not the CLI's.
- **Hook payloads are the same shape on both hosts** — JSON on stdin, snake_case
  (`tool_name`, `tool_input`, `session_id`, `hook_event_name`, `cwd`). The **outputs are
  not**: Copilot reads a top-level `permissionDecision`/`decision`, while Claude Code parses
  `hookSpecificOutput` as a union discriminated on `hookEventName` and **ignores a verdict
  that omits it**. `df_emit_*` emits both dialects at once; don't bypass it.
- **The two hook-config schemas differ in shape, not just event names.** Copilot: camelCase
  event → flat array of entries with a `bash` key. Claude Code: PascalCase event → array of
  *matcher groups*, each with a nested `hooks` array of handlers with a `command` key. Getting
  this wrong loads silently and never fires.
- **Event-name traps.** Copilot: `userPromptSubmitted` and `agentStop` (not
  `userPromptSubmit`/`stop`). Claude Code: `Stop` and `UserPromptSubmit` (not
  `agentStop`/`userPromptSubmitted`). The completion gate is `agentStop` on one and `Stop` on
  the other — hence one script wired twice.
- **There is deliberately no `hooks/hooks.json`.** Claude Code auto-discovers that exact path,
  so a Copilot-dialect file there would be loaded as Claude hooks and rejected; Copilot, by
  contrast, has **no** default hooks path and only reads the one its manifest names. So each
  host's manifest points at its own `hooks/hooks.<host>.json` and the default path stays empty.
  The cost is that `claude plugin validate` won't see our hook config (it only reads the
  default path) — `tests/validate-claude-schema.sh` stages a copy to get around that.
- **Claude Code's `.claude-plugin/` holds only `plugin.json`/`marketplace.json`** — every
  component directory (`agents/`, `skills/`, `hooks/`) must sit at the repo root. Component
  paths in the manifest must start with `./`; a marketplace `source` of `"."` is invalid
  (use `"./"`).
- **Agent frontmatter `tools`/`disallowedTools` must be a comma-separated string.** A YAML
  list (a `tools:` line followed by `- "*"`) is read by Claude Code as a literal tool name,
  which strands the agent. Omitting `tools` grants all tools on both hosts, so the specialists
  omit it and use `disallowedTools` to enforce investigation-only where the host supports it.
  The validator rejects the list form.
- **Tool names differ.** Copilot edits via `edit`/`create` with `tool_input.path`; Claude Code
  via `Write`/`Edit`/`MultiEdit` with `tool_input.file_path`, and `NotebookEdit` with
  `tool_input.notebook_path`. Use `df_tool_file`, and keep both matchers broad.
- **Plugin hook scripts get paths injected**: `$PLUGIN_ROOT`/`$COPILOT_PROJECT_DIR` (Copilot)
  or `$CLAUDE_PLUGIN_ROOT`/`$CLAUDE_PROJECT_DIR`/`$CLAUDE_PLUGIN_DATA` (Claude Code) — use
  them (that's why the framework needs nothing copied into target repos).
- **Bash/Python pitfalls already fixed** (keep them fixed): don't combine a stdin pipe with a
  `python3 -` heredoc (the heredoc wins — pass data via env, see `df_json_get`); only strip a
  *matching* surrounding quote pair in `df_cfg` (don't strip lone quotes from commands).
- **Install is marketplace-based on both hosts**; Copilot's direct repo/URL/local-path
  installs are deprecated. `claude plugin install` needs `--scope user` to stay
  non-interactive.
- **Claude Code puts a plugin's `bin/` on the Bash tool's `PATH`**, so `df` is callable from
  inside a session — keep `bin/df` self-contained and side-effect-free until it's told to
  launch something.

## Releasing

Bump `version` in **all four** manifests — `plugin.json`,
`.github/plugin/marketplace.json`, `.claude-plugin/plugin.json`, and
`.claude-plugin/marketplace.json` — move the `CHANGELOG.md` `[Unreleased]` section under a
new version heading, commit, then `git tag -a vX.Y.Z -m "..."` and push with `--tags`.
`validate-manifests.py` fails the build if the four versions disagree, so a half-finished
bump can't ship.

When creating commits, append:
`Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`
