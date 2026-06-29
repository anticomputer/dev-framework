#!/usr/bin/env bash
# Shared helpers for dev-framework hooks and the `df` CLI. SOURCED, not run directly.
# Hook scripts receive $PLUGIN_ROOT and $COPILOT_PROJECT_DIR from the Copilot CLI.

# Default set of paths the preToolUse guardrail protects from edits.
DF_DEFAULT_PROTECT='*.lock package-lock.json pnpm-lock.yaml yarn.lock bun.lockb Cargo.lock poetry.lock Gemfile.lock composer.lock go.sum .env .env.* **/vendor/** **/node_modules/** **/dist/** **/build/** **/generated/** **/*.generated.* **/*.min.js .git/**'

# ---- locations ------------------------------------------------------------

df_project_root() {
  printf '%s' "${COPILOT_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
}

df_config_file() {
  printf '%s' "$(df_project_root)/.dev-framework.yml"
}

df_data_dir() {
  printf '%s' "${COPILOT_PLUGIN_DATA:-${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}}"
}

# ---- profiles & activation ------------------------------------------------
# Effective profile: off | advisory | standard | strict.
# Precedence: an explicit DEV_FRAMEWORK profile value wins; else `profile:` from
# .dev-framework.yml; else (config file present) standard; else off.
df_profile() {
  local v cp
  v="$(printf '%s' "${DEV_FRAMEWORK:-}" | tr '[:upper:]' '[:lower:]')"
  case "$v" in
    off|0|false|no)            echo off;      return ;;
    advisory|coach|nudge)      echo advisory; return ;;
    standard|on|1|true|yes)    echo standard; return ;;
    strict|block|enforce)      echo strict;   return ;;
  esac
  if [ -f "$(df_config_file)" ]; then
    cp="$(printf '%s' "$(df_cfg profile '')" | tr '[:upper:]' '[:lower:]')"
    case "$cp" in
      off)                  echo off ;;
      advisory|coach|nudge) echo advisory ;;
      strict|block|enforce) echo strict ;;
      *)                    echo standard ;;   # file present => active
    esac
    return
  fi
  # env set to some non-empty, unrecognized value => treat as active/standard
  [ -n "$v" ] && { echo standard; return; }
  echo off
}

df_active() { [ "$(df_profile)" != off ]; }

# Profile-derived default for a behavior key.
df_profile_default() {
  local p; p="$(df_profile)"
  case "$1" in
    gate_block_on_failure) [ "$p" = advisory ] && echo false || echo true ;;
    gate_run_tests)        echo true ;;
    gate_run_typecheck)    echo true ;;
    gate_lint_changed)     [ "$p" = strict ] && echo true || echo false ;;
    gate_skip_unchanged)   echo true ;;
    gate_scope)            echo all ;;
    gate_max_blocks)       echo 3 ;;
    protect_mode)          [ "$p" = advisory ] && echo warn || echo deny ;;
    protect_off)           echo false ;;
    protect)               printf '%s' "$DF_DEFAULT_PROTECT" ;;
    format_on_edit)        echo true ;;
    lint_on_edit)          echo true ;;
    *)                     echo "" ;;
  esac
}

# Resolve an option: explicit config value wins, else the profile default.
df_opt() {
  local key="$1" v
  v="$(df_cfg "$key" "__df_unset__")"
  if [ "$v" != "__df_unset__" ]; then printf '%s' "$v"; return; fi
  df_profile_default "$key"
}

# ---- config (flat `key: value` lines in .dev-framework.yml) ----------------
# df_cfg KEY [DEFAULT]   (DEFAULT returned when key is absent or empty)
df_cfg() {
  local key="$1" def="${2:-}" file
  file="$(df_config_file)"
  if [ -f "$file" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$file" "$key" "$def" <<'PY'
import sys
path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
val = None
try:
    with open(path) as fh:
        for line in fh:
            s = '' if line.lstrip().startswith('#') else line.split('#', 1)[0].rstrip()
            if not s.strip() or ':' not in s:
                continue
            k, _, v = s.partition(':')
            if k.strip() == key:
                v = v.strip()
                if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
                    v = v[1:-1]
                val = v
                break
except FileNotFoundError:
    pass
print(val if val not in (None, '') else default)
PY
  else
    printf '%s' "$def"
  fi
}

df_truthy() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# ---- glob matching --------------------------------------------------------
# df_match_globs PATH "glob1 glob2 ..."  -> 0 if PATH matches any glob.
# Matches against the path as given, its basename, and its repo-relative form;
# ** spans directory separators.
df_match_globs() {
  local path="$1" globs="$2" root
  root="$(df_project_root)"
  DF_MG_PATH="$path" DF_MG_ROOT="$root" DF_MG_GLOBS="$globs" python3 <<'PY'
import os, fnmatch, re, sys
path = os.environ["DF_MG_PATH"]; root = os.environ["DF_MG_ROOT"]
globs = os.environ["DF_MG_GLOBS"].split()
cands = {path, os.path.basename(path)}
ap = path if os.path.isabs(path) else os.path.join(root, path)
try:
    cands.add(os.path.relpath(ap, root))
except Exception:
    pass
def match(p, g):
    rx = re.escape(g)
    rx = rx.replace(r'\*\*/', '(.*/)?').replace(r'\*\*', '.*')
    rx = rx.replace(r'\*', '[^/]*').replace(r'\?', '[^/]')
    return re.fullmatch(rx, p) is not None or fnmatch.fnmatch(p, g)
sys.exit(0 if any(match(c, g) for c in cands for g in globs) else 1)
PY
}

# ---- git changed files ----------------------------------------------------
df_changed_files() {
  local root; root="$(df_project_root)"
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  {
    git -C "$root" diff --name-only
    git -C "$root" diff --name-only --staged
    git -C "$root" ls-files --others --exclude-standard
  } 2>/dev/null | sed '/^$/d' | sort -u
}

# ---- per-session edit marker (so the gate can skip unchanged sessions) -----
df_session_safe() { printf '%s' "${1:-default}" | tr -c 'A-Za-z0-9_.-' '_'; }
df_edit_marker()  { printf '%s/edits-%s.flag' "$(df_data_dir)" "$(df_session_safe "$1")"; }
df_mark_edit()    { : > "$(df_edit_marker "$1")" 2>/dev/null || true; }
df_clear_edit()   { rm -f "$(df_edit_marker "$1")" 2>/dev/null || true; }

# ---- tool discovery -------------------------------------------------------
df_bin() {
  local tool="$1" root local_bin
  root="$(df_project_root)"
  local_bin="$root/node_modules/.bin/$tool"
  if [ -x "$local_bin" ]; then printf '%s' "$local_bin"
  elif command -v "$tool" >/dev/null 2>&1; then printf '%s' "$tool"; fi
}

df_pkg_manager() {
  local root; root="$(df_project_root)"
  if [ -f "$root/pnpm-lock.yaml" ]; then printf 'pnpm'
  elif [ -f "$root/yarn.lock" ]; then printf 'yarn'
  elif [ -f "$root/package-lock.json" ] || [ -f "$root/package.json" ]; then printf 'npm'; fi
}

# ---- auto-detection -------------------------------------------------------
df_detect_test() {
  local root; root="$(df_project_root)"
  if [ -f "$root/package.json" ] && command -v python3 >/dev/null 2>&1; then
    local has_test pm
    has_test="$(python3 - "$root/package.json" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1])); s=(d.get('scripts') or {}).get('test','')
    print('yes' if s and 'no test specified' not in s else 'no')
except Exception:
    print('no')
PY
)"
    if [ "$has_test" = "yes" ]; then pm="$(df_pkg_manager)"; [ -n "$pm" ] && { printf '%s test' "$pm"; return; }; fi
  fi
  if { [ -f "$root/pyproject.toml" ] || [ -f "$root/pytest.ini" ] || [ -f "$root/setup.cfg" ] || [ -d "$root/tests" ]; } && command -v pytest >/dev/null 2>&1; then
    printf 'pytest -q'; return
  fi
  if [ -f "$root/go.mod" ] && command -v go >/dev/null 2>&1; then printf 'go test ./...'; return; fi
  if [ -f "$root/Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then printf 'cargo test'; return; fi
  if [ -f "$root/Makefile" ] && grep -qE '^test:' "$root/Makefile" 2>/dev/null && command -v make >/dev/null 2>&1; then
    printf 'make test'; return
  fi
}

df_detect_typecheck() {
  local root tsc; root="$(df_project_root)"
  if [ -f "$root/tsconfig.json" ]; then
    tsc="$(df_bin tsc)"; [ -n "$tsc" ] && { printf '%s --noEmit' "$tsc"; return; }
  fi
}

df_detect_format() {
  local f="$1" ext bin; ext="${f##*.}"
  case "$ext" in
    js|jsx|ts|tsx|mjs|cjs|json|css|scss|less|md|mdx|yaml|yml|html|vue)
      bin="$(df_bin prettier)"; [ -n "$bin" ] && printf '%s --write' "$bin" ;;
    py)
      bin="$(df_bin ruff)"; if [ -n "$bin" ]; then printf '%s format' "$bin";
      else bin="$(df_bin black)"; [ -n "$bin" ] && printf '%s' "$bin"; fi ;;
    go)  bin="$(df_bin gofmt)";   [ -n "$bin" ] && printf '%s -w' "$bin" ;;
    rs)  bin="$(df_bin rustfmt)"; [ -n "$bin" ] && printf '%s' "$bin" ;;
  esac
}

df_detect_lint() {
  local f="$1" ext bin; ext="${f##*.}"
  case "$ext" in
    js|jsx|ts|tsx|mjs|cjs)
      bin="$(df_bin eslint)"; [ -n "$bin" ] && printf '%s' "$bin" ;;
    py)
      bin="$(df_bin ruff)"; if [ -n "$bin" ]; then printf '%s check' "$bin";
      else bin="$(df_bin flake8)"; [ -n "$bin" ] && printf '%s' "$bin"; fi ;;
  esac
}

# ---- command assembly -----------------------------------------------------
# df_apply_file CMD FILE -> substitute {file} or append the quoted file path.
df_apply_file() {
  local cmd="$1" file="$2"
  if printf '%s' "$cmd" | grep -q '{file}'; then printf '%s' "${cmd//\{file\}/\"$file\"}"
  else printf '%s "%s"' "$cmd" "$file"; fi
}
# df_apply_files CMD "f1 f2 ..." -> substitute {files} (left as-is if absent).
df_apply_files() {
  local cmd="$1" files="$2"
  printf '%s' "${cmd//\{files\}/$files}"
}

# ---- output protocol ------------------------------------------------------
df_emit_context() {
  python3 - "$1" <<'PY'
import json,sys
ctx=sys.argv[1]
print(json.dumps({"hookSpecificOutput":{"additionalContext":ctx},"additionalContext":ctx}))
PY
}

df_emit_block() {
  python3 - "$1" <<'PY'
import json,sys
reason=sys.argv[1]
print(json.dumps({"decision":"block","reason":reason,"additionalContext":reason}))
PY
}

# Deny a tool action (preToolUse). REASON is shown to the agent.
df_emit_deny() {
  python3 - "$1" <<'PY'
import json,sys
reason=sys.argv[1]
print(json.dumps({"permissionDecision":"deny","permissionDecisionReason":reason,
                  "hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":reason}}))
PY
}

df_read_stdin() { DF_STDIN="$(cat 2>/dev/null || true)"; export DF_STDIN; }

# df_json_get DOTPATH  (reads from DF_STDIN) e.g. df_json_get tool_input.path
df_json_get() {
  [ -n "${DF_STDIN:-}" ] || return 0
  DF_JSON="$DF_STDIN" python3 - "$1" <<'PY'
import json, os, sys
try:
    data = json.loads(os.environ.get("DF_JSON", "") or "{}")
except Exception:
    sys.exit(0)
cur = data
for part in sys.argv[1].split('.'):
    if isinstance(cur, dict) and part in cur: cur = cur[part]
    else: cur = None; break
if cur is None: sys.exit(0)
print(cur if isinstance(cur, str) else json.dumps(cur))
PY
}
