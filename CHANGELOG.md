# Changelog

All notable changes to dev-framework are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Claude Code support — the framework now ships for two hosts from one tree.** Same
  constitution, same specialists, same skills, same hook scripts, same `.dev-framework.yml`;
  only the manifests and the hook-event wiring differ per host.
  - `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (plugin source `"./"`),
    installable with `claude plugin marketplace add` / `claude plugin install`.
  - `hooks/hooks.claude.json` maps the engine onto Claude Code's events —
    `SessionStart` (on `startup`/`resume`/`clear`/`compact`/`fork`), `PreToolUse` and
    `PostToolUse` (matching `Write`/`Edit`/`MultiEdit`/`NotebookEdit`), and `Stop` for the
    completion gate.
  - Hook verdicts now carry the `hookSpecificOutput.hookEventName` discriminator Claude Code
    requires, alongside the top-level fields Copilot CLI reads, so one code path serves both.
  - Host awareness in `common.sh` (`df_host`, `df_host_label`, `df_host_bin`, `df_agent_ref`,
    `df_skill_ref`) and a host-aware session banner that names the specialists and skills the
    way *that* host expects them to be invoked (`dev-framework:pattern-guardian` under Claude
    Code, bare names under Copilot CLI).
  - `df_tool_file` reads an edit target from `path`, `file_path`, or `notebook_path`, so the
    protected-path guardrail and the format/lint pass cover both hosts' tool schemas.
  - Specialist agents are now locked to investigation-only via `disallowedTools` where the
    host enforces it, instead of only being asked to behave in the prompt.
- **`df` is host-aware**: `df claude` / `df copilot` (combinable with a profile in either
  order), a `host:` config key, `$DF_HOST`, and `df status` now reporting the resolved host
  and which CLIs are installed.
- **`tests/validate-claude-schema.sh`** — optional `claude plugin validate --strict` run
  against a staged copy of the repo, which is the only way to get Claude Code's own validator
  to check `hooks/hooks.claude.json` (it otherwise reads hooks only from the default
  `hooks/hooks.json` path). Skips cleanly when `claude` isn't installed.
- **`install.sh` / `uninstall.sh` cover both hosts** — with no argument they act on every CLI
  found on `PATH`; `./install.sh claude` or `./install.sh copilot` targets just one.
- **`.github/PULL_REQUEST_TEMPLATE.md`** — contributor checklist (tests, validation, dormant-safe, docs).
- **`AGENTS.md`** (root) — instructions for agents/contributors working on the framework
  itself: build/test/validate commands, repo map, must-follow conventions, hard-won gotchas,
  and the release process.
- **Dogfooding** — a committed root `.dev-framework.yml` so the project holds its own changes
  to the same bar it ships (the completion gate runs the test suite + manifest validator).
- **`examples/todo-service/`** — a worked example with a `WALKTHROUGH.md` showing how a
  project defines its conventions (`.dev-framework.yml` + `STYLE.md` + `AGENTS.md`) and how
  the framework keeps an agent on the rails through a real change.
- **`CONFIGURATION.md`** — full `.dev-framework.yml` reference: grammar, every key with
  type/default, substitution tokens, glob syntax, and worked examples.
- **Broad language support** for auto-detection: tests (RSpec/Rake, Gradle/Maven,
  `dotnet test`, `mix test`, PHPUnit, sbt, `swift test`, dart/flutter, deno, make/just),
  type-check (mypy, pyright, flow), format and lint across ~20 ecosystems — each gated on
  the tool being installed.
- **Project task-runner preference**: `make`/`just` targets, npm scripts, and **pre-commit**
  (`.pre-commit-config.yaml`) are used when present.
- **Per-language config overrides** via `format.<ext>` / `lint.<ext>` keys, plus a
  `precommit: auto|off` toggle.
- `df status` now shows the resolved formatter/linter for each file type in the repo;
  `df init` reports detected file types.

### Changed
- **`hooks/hooks.json` is now `hooks/hooks.copilot.json`.** Claude Code auto-discovers the
  default `hooks/hooks.json` path, so neither host's config sits there any more — each
  manifest points at its own `hooks/hooks.<host>.json`. No user-visible change; `plugin.json`
  was updated to match.
- **Agent frontmatter dropped `tools: ["*"]`** in favor of omitting `tools` (identical
  meaning — all tools — on both hosts) plus an explicit `disallowedTools`. A YAML list is read
  by Claude Code as a literal tool name, which would have left the specialists with no tools.
- The constitution, skills, and agent prompts are now host-neutral; host-specific detail
  (component naming, built-in reviewers, event names) is rendered into the session banner.
- `validate-manifests.py` validates both ecosystems, checks that every hook command points at
  a script that exists, rejects a YAML-list `tools`/`disallowedTools`, and fails when the four
  manifest versions disagree.
- The test suite grew from 48 to 117 assertions, covering host detection, Claude Code's hook
  dialect end to end, hook-config parity between the two wirings, and `df`'s host resolution
  and launch behavior against stub CLIs.

## [0.1.0] - 2026-06-29

Initial release.

### Added
- **Plugin packaging** for the GitHub Copilot CLI (`plugin.json` +
  `.github/plugin/marketplace.json`), installable via the official
  `copilot plugin marketplace add` / `copilot plugin install` flow.
- **Constitution** (`rules/*.md`): quality bar, match-existing-patterns, testing
  discipline, and a delegation working-loop — injected into context at `sessionStart`
  only when the framework is active.
- **Specialist agents**: `pattern-guardian` (anti-drift), `style-enforcer`,
  `test-grounder` — investigation-only reviewers.
- **Continuous hooks**: `sessionStart` (active banner + repo tooling + constitution),
  `preToolUse` (protected-paths guardrail), `postToolUse` (format + lint feedback per
  edited file), `agentStop` (type-check + test completion gate).
- **Skills**: `peer-review`, `ground-in-tests`, `match-patterns`.
- **Intensity profiles**: `off` / `advisory` / `standard` / `strict`, set per-session
  (`DEV_FRAMEWORK=`) or per-repo (`profile:` in `.dev-framework.yml`).
- **`df` CLI**: `init`, `status`, `version`, profile launchers, and copilot passthrough.
- **Smarter gate**: skip-unchanged, scoped tests (`gate_scope: changed` + `test_changed`),
  time budget (`gate_timeout`), and a `gate_max_blocks` stand-down.
- **Per-project config** (`.dev-framework.yml`) with auto-detection for common stacks.
- **Test suite** (`tests/run.sh`), **manifest validator**, and **CI**.
