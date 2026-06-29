#!/usr/bin/env bash
# dev-framework test suite. Self-contained: creates throwaway projects, exercises the
# hooks and helpers with stub commands, and asserts outcomes. Requires bash, python3,
# git. Does NOT require copilot or any formatter/linter. Run: tests/run.sh
set -uo pipefail

FW="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="$FW/hooks/lib/common.sh"
DF_TALLY="$(mktemp)"; export DF_TALLY

ok()   { echo P >> "$DF_TALLY"; printf '  ok   %s\n' "$1"; }
bad()  { echo F >> "$DF_TALLY"; printf '  FAIL %s\n' "$1"; }
assert_eq()       { [ "${2:-}" = "${3:-}" ] && ok "$1" || { bad "$1"; printf '         expected=[%s] actual=[%s]\n' "${2:-}" "${3:-}"; }; }
assert_contains() { case "${3:-}" in *"${2:-}"*) ok "$1" ;; *) bad "$1"; printf '         missing [%s] in: %s\n' "${2:-}" "${3:0:160}" ;; esac; }
assert_empty()    { [ -z "${2:-}" ] && ok "$1" || { bad "$1"; printf '         expected empty, got: %s\n' "${2:0:120}"; }; }
newproj() { mktemp -d; }
jget()  { python3 -c "import json,sys;print(json.load(sys.stdin).get('$1',''))" 2>/dev/null; }

echo "# profile resolution"
(
  PROJ="$(newproj)"; export COPILOT_PROJECT_DIR="$PROJ"; cd "$PROJ"; . "$COMMON"
  unset DEV_FRAMEWORK;            assert_eq "off when nothing set" off "$(df_profile)"
  export DEV_FRAMEWORK=strict;    assert_eq "env strict" strict "$(df_profile)"
  export DEV_FRAMEWORK=1;         assert_eq "env 1 => standard" standard "$(df_profile)"
  export DEV_FRAMEWORK=off;       assert_eq "env off" off "$(df_profile)"
  unset DEV_FRAMEWORK; echo "profile: advisory" > "$PROJ/.dev-framework.yml"
  assert_eq "file advisory" advisory "$(df_profile)"
  export DEV_FRAMEWORK=strict;    assert_eq "env overrides file" strict "$(df_profile)"
)

echo "# profile-derived defaults"
(
  PROJ="$(newproj)"; export COPILOT_PROJECT_DIR="$PROJ"; cd "$PROJ"; . "$COMMON"
  export DEV_FRAMEWORK=advisory
  assert_eq "advisory no block" false "$(df_opt gate_block_on_failure)"
  assert_eq "advisory warn"     warn  "$(df_opt protect_mode)"
  export DEV_FRAMEWORK=standard
  assert_eq "standard blocks"   true  "$(df_opt gate_block_on_failure)"
  assert_eq "standard deny"     deny  "$(df_opt protect_mode)"
  export DEV_FRAMEWORK=strict
  assert_eq "strict lint-changed" true "$(df_opt gate_lint_changed)"
)

echo "# config parsing"
(
  PROJ="$(newproj)"; export COPILOT_PROJECT_DIR="$PROJ"; cd "$PROJ"; . "$COMMON"; export DEV_FRAMEWORK=standard
  printf "test: sh -c 'echo hi; exit 0'\ngate_block_on_failure: false   # comment\n" > "$PROJ/.dev-framework.yml"
  assert_eq "keeps embedded quotes" "sh -c 'echo hi; exit 0'" "$(df_cfg test NONE)"
  assert_eq "config overrides default" false "$(df_opt gate_block_on_failure)"
)

echo "# glob matching"
(
  PROJ="$(newproj)"; export COPILOT_PROJECT_DIR="$PROJ"; cd "$PROJ"; . "$COMMON"; export DEV_FRAMEWORK=standard
  df_match_globs "package-lock.json" "$DF_DEFAULT_PROTECT" && ok "lockfile matches" || bad "lockfile matches"
  df_match_globs "a/b/node_modules/x.js" "$DF_DEFAULT_PROTECT" && ok "nested node_modules" || bad "nested node_modules"
  df_match_globs "config/.env.prod" "$DF_DEFAULT_PROTECT" && ok ".env.prod matches" || bad ".env.prod matches"
  df_match_globs "src/app.ts" "$DF_DEFAULT_PROTECT" && bad "src not protected" || ok "src not protected"
)

echo "# preToolUse guardrail"
(
  PROJ="$(newproj)"; export PLUGIN_ROOT="$FW" COPILOT_PROJECT_DIR="$PROJ" COPILOT_PLUGIN_DATA="$(mktemp -d)"
  export DEV_FRAMEWORK=standard
  out="$(printf '{"tool_input":{"path":"yarn.lock"}}' | bash "$FW/hooks/lib/pre-tool-use.sh")"
  assert_eq "standard denies lockfile" deny "$(printf '%s' "$out" | jget permissionDecision)"
  export DEV_FRAMEWORK=advisory
  out="$(printf '{"tool_input":{"path":"yarn.lock"}}' | bash "$FW/hooks/lib/pre-tool-use.sh")"
  assert_empty "advisory does not deny" "$(printf '%s' "$out" | jget permissionDecision)"
  assert_contains "advisory warns" "protected path" "$(printf '%s' "$out" | jget additionalContext)"
  export DEV_FRAMEWORK=standard
  out="$(printf '{"tool_input":{"path":"src/main.py"}}' | bash "$FW/hooks/lib/pre-tool-use.sh")"
  assert_empty "normal file allowed" "$out"
)

echo "# postToolUse feedback + exclude + edit marker"
(
  PROJ="$(newproj)"; export PLUGIN_ROOT="$FW" COPILOT_PROJECT_DIR="$PROJ" COPILOT_PLUGIN_DATA="$(mktemp -d)"
  export DEV_FRAMEWORK=standard
  printf "format:\nlint: sh -c 'echo LINTBAD; exit 1'\n" > "$PROJ/.dev-framework.yml"
  echo x > "$PROJ/foo.py"
  out="$(printf '{"session_id":"s","tool_input":{"path":"foo.py"}}' | bash "$FW/hooks/lib/post-tool-use.sh")"
  assert_contains "lint failure fed back" "LINTBAD" "$(printf '%s' "$out" | jget additionalContext)"
  [ -f "$COPILOT_PLUGIN_DATA/edits-s.flag" ] && ok "edit marker written" || bad "edit marker written"
  printf "lint: sh -c 'echo NOPE; exit 1'\nexclude: foo.py\n" > "$PROJ/.dev-framework.yml"
  out="$(printf '{"session_id":"s","tool_input":{"path":"foo.py"}}' | bash "$FW/hooks/lib/post-tool-use.sh")"
  assert_empty "excluded file skipped" "$out"
)

echo "# agentStop completion gate"
(
  PROJ="$(newproj)"; export PLUGIN_ROOT="$FW" COPILOT_PROJECT_DIR="$PROJ" COPILOT_PLUGIN_DATA="$(mktemp -d)"
  cd "$PROJ"; git init -q; git -c user.email=t@t -c user.name=t commit -qm init --allow-empty
  export DEV_FRAMEWORK=standard
  printf "typecheck:\ntest: sh -c 'echo TFAIL; exit 1'\n" > "$PROJ/.dev-framework.yml"
  out="$(printf '{"session_id":"g1"}' | bash "$FW/hooks/lib/stop-gate.sh")"
  assert_empty "skips when unchanged" "$out"
  : > "$COPILOT_PLUGIN_DATA/edits-g1.flag"
  out="$(printf '{"session_id":"g1"}' | bash "$FW/hooks/lib/stop-gate.sh")"
  assert_eq "blocks on failing tests" block "$(printf '%s' "$out" | jget decision)"
  printf "typecheck:\ntest: sh -c 'exit 0'\n" > "$PROJ/.dev-framework.yml"; : > "$COPILOT_PLUGIN_DATA/edits-g1.flag"
  out="$(printf '{"session_id":"g1"}' | bash "$FW/hooks/lib/stop-gate.sh")"
  assert_empty "passes when green" "$out"
  export DEV_FRAMEWORK=advisory
  printf "typecheck:\ntest: sh -c 'echo X; exit 1'\n" > "$PROJ/.dev-framework.yml"; : > "$COPILOT_PLUGIN_DATA/edits-g1.flag"
  out="$(printf '{"session_id":"g1"}' | bash "$FW/hooks/lib/stop-gate.sh")"
  assert_empty "advisory never blocks" "$(printf '%s' "$out" | jget decision)"
)

echo "# sessionStart injects banner + constitution"
(
  PROJ="$(newproj)"; export PLUGIN_ROOT="$FW" COPILOT_PROJECT_DIR="$PROJ" COPILOT_PLUGIN_DATA="$(mktemp -d)"
  export DEV_FRAMEWORK=strict
  out="$(printf '{}' | bash "$FW/hooks/lib/session-start.sh" | jget additionalContext)"
  assert_contains "banner shows profile" "profile: strict" "$out"
  assert_contains "constitution injected" "DEV-FRAMEWORK CONSTITUTION" "$out"
  assert_contains "quality bar present" "Quality Bar" "$out"
  unset DEV_FRAMEWORK
  out="$(printf '{}' | bash "$FW/hooks/lib/session-start.sh")"
  assert_empty "dormant session injects nothing" "$out"
)

echo "# language configuration"
(
  PROJ="$(newproj)"; export COPILOT_PROJECT_DIR="$PROJ"; cd "$PROJ"; . "$COMMON"; export DEV_FRAMEWORK=standard
  # per-language override wins over generic + auto-detect
  printf 'format: GENERIC {file}\nformat.py: PYFMT {file}\nlint.go: GOLINT {file}\n' > "$PROJ/.dev-framework.yml"
  assert_eq "format.py override"   "PYFMT {file}"   "$(df_lang_cmd format x.py)"
  assert_eq "generic format for js" "GENERIC {file}" "$(df_lang_cmd format x.js)"
  assert_eq "lint.go override"     "GOLINT {file}"  "$(df_lang_cmd lint x.go)"
  # df_exts_present
  cd "$PROJ"; git init -q >/dev/null 2>&1; touch a.py b.js c.py; git add -A >/dev/null 2>&1
  exts="$(df_exts_present | tr '\n' ' ')"
  assert_contains "exts include py" "py" "$exts"
  assert_contains "exts include js" "js" "$exts"
  # task-runner preference: Makefile test target
  printf 'profile: standard\n' > "$PROJ/.dev-framework.yml"
  printf 'test:\n\t@echo hi\n' > "$PROJ/Makefile"
  if command -v make >/dev/null 2>&1; then assert_eq "prefers make test" "make test" "$(df_detect_test)"; else ok "make not installed (skip)"; fi
)

echo "# pre-commit integration"
(
  PROJ="$(newproj)"; export COPILOT_PROJECT_DIR="$PROJ"; cd "$PROJ"; . "$COMMON"; export DEV_FRAMEWORK=standard
  bindir="$(mktemp -d)"; printf '#!/bin/sh\nexit 0\n' > "$bindir/pre-commit"; chmod +x "$bindir/pre-commit"
  export PATH="$bindir:$PATH"
  printf 'repos: []\n' > "$PROJ/.pre-commit-config.yaml"
  printf 'profile: standard\n' > "$PROJ/.dev-framework.yml"
  df_precommit_active && ok "pre-commit active when present" || bad "pre-commit active when present"
  assert_contains "lint uses pre-commit" "run --files" "$(df_lang_cmd lint x.py)"
  assert_empty "format deferred to pre-commit" "$(df_lang_cmd format x.py)"
  printf 'profile: standard\nprecommit: off\n' > "$PROJ/.dev-framework.yml"
  df_precommit_active && bad "precommit off disables" || ok "precommit off disables"
)

echo "# df CLI: init + status"
(
  PROJ="$(newproj)"; cd "$PROJ"; git init -q
  printf '{"scripts":{"test":"jest"}}' > package.json
  unset DEV_FRAMEWORK COPILOT_PROJECT_DIR
  "$FW/bin/df" init --profile strict >/dev/null
  [ -f "$PROJ/.dev-framework.yml" ] && ok "df init writes config" || bad "df init writes config"
  assert_contains "init sets profile" "profile: strict" "$(cat "$PROJ/.dev-framework.yml")"
  assert_contains "init detects npm test" "test: npm test" "$(cat "$PROJ/.dev-framework.yml")"
  "$FW/bin/df" init >/dev/null 2>&1 && bad "init refuses clobber" || ok "init refuses clobber"
  assert_contains "status shows profile" "resolved profile : strict" "$("$FW/bin/df" status)"
  assert_contains "df version" "dev-framework" "$("$FW/bin/df" version)"
)

echo
PASS=$(grep -c '^P$' "$DF_TALLY"); PASS=${PASS:-0}
FAIL=$(grep -c '^F$' "$DF_TALLY"); FAIL=${FAIL:-0}
rm -f "$DF_TALLY"
echo "================  $PASS passed, $FAIL failed  ================"
[ "$FAIL" -eq 0 ]
