# Changelog

All notable changes to dev-framework are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
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
