# `.dev-framework.yml` configuration reference

`.dev-framework.yml` lives at the root of a repository. Its presence **activates** the
framework for Copilot sessions in that repo, and its keys configure behavior. Commit it to
share identical enforcement with your whole team. Every key is optional — blank or absent
values fall back to auto-detection or a profile default.

Generate a starter file with `df init`, or copy
[`.dev-framework.example.yml`](.dev-framework.example.yml).

---

## Grammar

The file is parsed as **simple flat `key: value` lines** — not full YAML. The rules:

- **One setting per line**, in the form `key: value`. Only the **first** colon separates
  the key from the value, so values may contain colons (`test: sh -c 'a:b'`).
- **Comments** start with `#`. A `#` anywhere on a line begins a comment, so **values
  cannot contain `#`**.
- **Blank means "unset"** → the framework auto-detects (commands) or uses the profile
  default (toggles).
- **Whitespace** around the key and value is trimmed.
- **Quoting:** if a value is wrapped in a matching pair of single or double quotes, that
  outer pair is stripped (use it to preserve leading/trailing spaces). Quotes *inside* a
  value are kept verbatim — e.g. `test: sh -c 'pytest -q'` works as written.
- **Keys are matched exactly** (case-sensitive). If a key appears twice, the first wins.
- **No nesting / no lists.** Structure is expressed with flat keys (e.g. `gate_scope`) and,
  for per-language settings, **dotted keys** (e.g. `format.py`).

```yaml
# a comment
profile: strict                # inline comment (everything after # is ignored)
test: sh -c 'pytest -q'        # value with a colon and quotes — fine
format.py: ruff format {file}  # dotted per-language key
```

### Substitution tokens

Some command values are templated before they run:

| Token | Expands to | Used in |
|-------|-----------|---------|
| `{file}` | the edited file (quoted). If omitted from a `format`/`lint` command, the path is appended automatically. | `format`, `lint`, `format.<ext>`, `lint.<ext>` |
| `{files}` | space-separated list of changed files | `test_changed` |

### Glob syntax (for `protect` and `exclude`)

Space-separated patterns. `*` matches within a path segment, `**` spans directories, `?`
matches one character. Each pattern is tested against the path as written, its basename,
and its repo-relative form. Example: `**/migrations/** *.min.js vendor/**`.

### Booleans

`true` / `yes` / `on` / `1` are true; anything else is false (case-insensitive).

---

## Activation & profile

A session is active when the **profile** resolves to something other than `off`. Resolution
order (first match wins):

1. The `DEV_FRAMEWORK` environment variable, if it names a profile
   (`off`/`advisory`/`standard`/`strict`; `1`/`on`/`true` → `standard`).
2. The `profile:` key in `.dev-framework.yml`.
3. If the file exists but sets no profile → `standard`.
4. Otherwise → `off` (dormant).

So `DEV_FRAMEWORK=strict copilot` (or `df strict`) overrides the committed profile for one
session, and `DEV_FRAMEWORK=off` / `df off` forces a dormant session.

| Profile | Edit feedback | Completion gate | Protected paths |
|---------|---------------|-----------------|-----------------|
| `off` | — | — | — |
| `advisory` | format + lint | runs, **never blocks** | warn |
| `standard` | format + lint | **blocks** on type-check/test failure | deny |
| `strict` | format + lint | also blocks on **lint of changed files** | deny |

Profiles set the *defaults* for the toggles below; any key you set explicitly overrides the
profile default.

---

## Key reference

### Commands

| Key | Default | Description |
|-----|---------|-------------|
| `test` | auto-detect | Test command run by the completion gate. |
| `typecheck` | auto-detect | Type-check command run by the completion gate. |
| `format` | auto per file | Global formatter; `{file}` is substituted (else appended). |
| `lint` | auto per file | Global linter; `{file}` is substituted (else appended). |
| `format.<ext>` | — | Per-language formatter override for files ending `.ext` (e.g. `format.py`). Wins over `format` and auto-detect. |
| `lint.<ext>` | — | Per-language linter override (e.g. `lint.go`). Wins over `lint` and auto-detect. |
| `test_changed` | — | Command for `gate_scope: changed`; `{files}` is substituted. Falls back to `test` if unset. |
| `precommit` | `auto` | `auto` uses `.pre-commit-config.yaml` (when `pre-commit` is installed) for per-file format+lint; `off` ignores it. |

Resolution for an edited file: `format.<ext>` / `lint.<ext>` → `format` / `lint` →
pre-commit (if active) → built-in auto-detection by extension. Auto-detection only ever runs
tools that are actually installed. See the README "Language support" section for coverage.

### Live (per-edit) enforcement

| Key | Default | Description |
|-----|---------|-------------|
| `format_on_edit` | `true` | Auto-format each file the agent writes (`postToolUse`). |
| `lint_on_edit` | `true` | Lint each edited file and feed violations back. |
| `exclude` | — | Globs to skip for format/lint (e.g. `**/migrations/** **/*.min.js`). |

### Completion gate (`agentStop`)

| Key | Default | Description |
|-----|---------|-------------|
| `gate_run_typecheck` | `true` | Run `typecheck` at the gate. |
| `gate_run_tests` | `true` | Run `test` at the gate. |
| `gate_block_on_failure` | profile (`false` advisory, else `true`) | Block completion while checks are red. |
| `gate_skip_unchanged` | `true` | Skip the gate entirely if the session changed no files. |
| `gate_scope` | `all` | `all` runs `test`; `changed` runs `test_changed` with the changed files. |
| `gate_lint_changed` | profile (`true` strict, else `false`) | Also lint each changed file at the gate (failures block). |
| `gate_timeout` | — | Seconds per gate command (requires the `timeout` tool). |
| `gate_max_blocks` | `3` | After N blocks in a session, the gate stands down (loudly) to avoid trapping you. |

### Protected paths (`preToolUse`)

| Key | Default | Description |
|-----|---------|-------------|
| `protect_off` | `false` | `true` disables path protection entirely. |
| `protect_mode` | profile (`warn` advisory, else `deny`) | `deny` blocks the edit; `warn` allows it with a warning. |
| `protect` | sensible defaults | Space-separated globs to protect. Defaults cover lockfiles, `.env*`, `**/vendor/**`, `**/node_modules/**`, `**/dist/**`, `**/build/**`, `**/generated/**`, `**/*.generated.*`, `**/*.min.js`, `.git/**`. |

### Misc

| Key | Default | Description |
|-----|---------|-------------|
| `style_guide` | auto-discover | Path (relative to repo root) to a style guide the agent should follow. If blank, common locations (`STYLE.md`, `CONTRIBUTING.md`, …) are auto-discovered. |

---

## Examples

**Strict Node/TypeScript service**

```yaml
profile: strict
test: npm test
typecheck: tsc --noEmit
# format/lint auto-detected (prettier/eslint)
```

**Advisory Python project (coach, never block)**

```yaml
profile: advisory
test: pytest -q
format.py: ruff format {file}
lint.py: ruff check {file}
```

**Polyglot monorepo using pre-commit, scoped tests**

```yaml
profile: standard
precommit: auto                       # pre-commit handles per-file format+lint
gate_scope: changed
test_changed: ./scripts/test-changed.sh {files}
exclude: **/generated/** **/*.pb.go
```

**Loosen protection for a repo that hand-maintains a lockfile**

```yaml
profile: standard
protect: .env .env.* **/node_modules/**   # narrower than the defaults
# or: protect_off: true
```

Run `df status` in the repo to see exactly how your settings resolve, including the
formatter/linter chosen for each file type present.
