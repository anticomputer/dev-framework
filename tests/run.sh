#!/usr/bin/env bash
# dev-framework test suite. Self-contained: creates throwaway projects, exercises the
# hooks and helpers with stub commands, and asserts outcomes. Requires bash, python3,
# git. Does NOT require copilot, claude, codex, or any formatter/linter — the hooks are tested
# by feeding them the same JSON event payloads each CLI sends. Run: tests/run.sh
set -uo pipefail

FW="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="$FW/hooks/lib/common.sh"
DF_TALLY="$(mktemp)"; export DF_TALLY

# Host detection reads the ambient environment, so scrub the vars a real session would
# set before each case; every test then declares the host it is exercising.
unset CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA CLAUDECODE
unset COPILOT_PLUGIN_ROOT COPILOT_PROJECT_DIR COPILOT_PLUGIN_DATA PLUGIN_ROOT PLUGIN_DATA DF_HOST CODEX_HOME

ok()   { echo P >> "$DF_TALLY"; printf '  ok   %s\n' "$1"; }
bad()  { echo F >> "$DF_TALLY"; printf '  FAIL %s\n' "$1"; }
assert_eq()       { [ "${2:-}" = "${3:-}" ] && ok "$1" || { bad "$1"; printf '         expected=[%s] actual=[%s]\n' "${2:-}" "${3:-}"; }; }
assert_contains() { case "${3:-}" in *"${2:-}"*) ok "$1" ;; *) bad "$1"; printf '         missing [%s] in: %s\n' "${2:-}" "${3:0:160}" ;; esac; }
assert_empty()    { [ -z "${2:-}" ] && ok "$1" || { bad "$1"; printf '         expected empty, got: %s\n' "${2:0:120}"; }; }
newproj() { mktemp -d; }
jget()  { python3 -c "import json,sys;print(json.load(sys.stdin).get('$1',''))" 2>/dev/null; }
# jgetp a.b.c — read a nested key out of a hook's JSON verdict.
jgetp() { python3 -c "
import json,sys
cur=json.load(sys.stdin)
for p in '$1'.split('.'):
    cur = cur.get(p) if isinstance(cur, dict) else None
print('' if cur is None else cur)" 2>/dev/null; }

echo "# host detection"
(
  PROJ="$(newproj)"; cd "$PROJ" || exit 1; . "$COMMON"
  export COPILOT_PROJECT_DIR="$PROJ"
  assert_eq "copilot when PLUGIN_ROOT set" copilot "$(PLUGIN_ROOT=/x df_host)"
  assert_eq "claude when CLAUDE_PLUGIN_ROOT set" claude "$(CLAUDE_PLUGIN_ROOT=/x df_host)"
  # A Claude hook process sets both plugin roots' cousins; the Claude one must win.
  assert_eq "claude plugin root beats copilot project dir" claude \
    "$(CLAUDE_PLUGIN_ROOT=/x PLUGIN_ROOT=/y df_host)"
  assert_eq "DF_HOST overrides env" claude "$(DF_HOST=claude PLUGIN_ROOT=/x df_host)"
  assert_eq "DF_HOST copilot overrides env" copilot "$(DF_HOST=copilot CLAUDE_PLUGIN_ROOT=/x df_host)"
  assert_eq "claude-code alias" claude "$(DF_HOST=claude-code df_host)"
  assert_eq "codex explicit host" codex "$(DF_HOST=codex df_host)"
  assert_eq "codex alias" codex "$(DF_HOST=openai-codex df_host)"
  assert_eq "host labels" "Claude Code claude" "$(DF_HOST=claude bash -c ". \"$COMMON\"; printf '%s %s' \"\$(df_host_label)\" \"\$(df_host_bin)\"")"
  assert_eq "copilot label" "Copilot CLI copilot" "$(DF_HOST=copilot bash -c ". \"$COMMON\"; printf '%s %s' \"\$(df_host_label)\" \"\$(df_host_bin)\"")"
  assert_eq "codex label" "Codex CLI codex" "$(DF_HOST=codex bash -c ". \"$COMMON\"; printf '%s %s' \"\$(df_host_label)\" \"\$(df_host_bin)\"")"
  # Claude Code and Codex namespace plugin components; Copilot CLI does not.
  assert_eq "claude namespaces agents" "dev-framework:pattern-guardian" "$(DF_HOST=claude df_agent_ref pattern-guardian)"
  assert_eq "copilot bare agents" "pattern-guardian" "$(DF_HOST=copilot df_agent_ref pattern-guardian)"
  assert_eq "claude namespaces skills" "dev-framework:peer-review" "$(DF_HOST=claude df_skill_ref peer-review)"
  assert_eq "codex agent role" "dev_framework_pattern_guardian" "$(DF_HOST=codex df_agent_ref pattern-guardian)"
  assert_eq "codex skill identity" "dev-framework:peer-review" "$(DF_HOST=codex df_skill_ref peer-review)"
  assert_eq "codex plugin data" "$PROJ/codex-data" "$(DF_HOST=codex PLUGIN_DATA="$PROJ/codex-data" df_data_dir)"
  DF_STDIN='{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: src/a.py\n*** Move to: src/b.py\n*** Add File: src/c.py\n*** Delete File: src/d.py\n*** End Patch"}}'; export DF_STDIN
  assert_eq "codex patch targets" $'src/a.py\nsrc/b.py\nsrc/c.py\nsrc/d.py' "$(df_tool_files)"
  assert_eq "first patch target remains compatible" "src/a.py" "$(df_tool_file)"
)

echo "# Claude Code project root + data dir"
(
  PROJ="$(newproj)"; . "$COMMON"
  unset COPILOT_PROJECT_DIR COPILOT_PLUGIN_DATA
  export CLAUDE_PROJECT_DIR="$PROJ"
  assert_eq "CLAUDE_PROJECT_DIR is the root" "$PROJ" "$(df_project_root)"
  assert_eq "config path under claude root" "$PROJ/.dev-framework.yml" "$(df_config_file)"
  DATA="$(newproj)/nested"; export CLAUDE_PLUGIN_DATA="$DATA"
  assert_eq "CLAUDE_PLUGIN_DATA honored" "$DATA" "$(df_data_dir)"
  [ -d "$DATA" ] && ok "data dir created on demand" || bad "data dir created on demand"
  unset CLAUDE_PLUGIN_DATA
  TMPDIR="$(newproj)" ; export TMPDIR
  assert_eq "falls back to a namespaced tmp dir" "$TMPDIR/dev-framework" "$(df_data_dir)"
)

echo "# Claude Code hook dialect (PreToolUse / PostToolUse / Stop / SessionStart)"
(
  PROJ="$(newproj)"; DATA="$(newproj)"
  export CLAUDE_PLUGIN_ROOT="$FW" CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_DATA="$DATA"
  unset PLUGIN_ROOT COPILOT_PROJECT_DIR COPILOT_PLUGIN_DATA
  export DEV_FRAMEWORK=standard

  # PreToolUse: Claude Code reads the decision out of hookSpecificOutput and needs the
  # hookEventName discriminator, and its Write/Edit tools use `file_path`, not `path`.
  out="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"yarn.lock"}}' \
    | bash "$FW/hooks/lib/pre-tool-use.sh")"
  assert_eq "claude denies via hookSpecificOutput" deny "$(printf '%s' "$out" | jgetp hookSpecificOutput.permissionDecision)"
  assert_eq "claude deny carries hookEventName" PreToolUse "$(printf '%s' "$out" | jgetp hookSpecificOutput.hookEventName)"
  assert_contains "claude deny explains why" "protected path" "$(printf '%s' "$out" | jgetp hookSpecificOutput.permissionDecisionReason)"
  out="$(printf '{"hook_event_name":"PreToolUse","tool_name":"NotebookEdit","tool_input":{"notebook_path":"pnpm-lock.yaml"}}' \
    | bash "$FW/hooks/lib/pre-tool-use.sh")"
  assert_eq "notebook_path is understood" deny "$(printf '%s' "$out" | jgetp hookSpecificOutput.permissionDecision)"
  out="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"src/app.ts"}}' \
    | bash "$FW/hooks/lib/pre-tool-use.sh")"
  assert_empty "claude allows normal files" "$out"

  # PostToolUse: feedback rides in hookSpecificOutput.additionalContext.
  printf "format:\nlint: sh -c 'echo LINTBAD; exit 1'\n" > "$PROJ/.dev-framework.yml"
  echo x > "$PROJ/foo.py"
  out="$(printf '{"hook_event_name":"PostToolUse","session_id":"cc1","tool_name":"Edit","tool_input":{"file_path":"foo.py"}}' \
    | bash "$FW/hooks/lib/post-tool-use.sh")"
  assert_contains "claude gets lint feedback" "LINTBAD" "$(printf '%s' "$out" | jgetp hookSpecificOutput.additionalContext)"
  assert_eq "post-edit carries hookEventName" PostToolUse "$(printf '%s' "$out" | jgetp hookSpecificOutput.hookEventName)"
  [ -f "$DATA/edits-cc1.flag" ] && ok "edit marker in claude data dir" || bad "edit marker in claude data dir"

  # Stop: the completion gate blocks with decision/reason.
  cd "$PROJ" || exit 1; git init -q; git -c user.email=t@t -c user.name=t commit -qm init --allow-empty
  printf "typecheck:\ntest: sh -c 'echo TFAIL; exit 1'\n" > "$PROJ/.dev-framework.yml"
  out="$(printf '{"hook_event_name":"Stop","session_id":"cc1"}' | bash "$FW/hooks/lib/stop-gate.sh")"
  assert_eq "claude gate blocks" block "$(printf '%s' "$out" | jget decision)"
  assert_eq "claude block carries hookEventName" Stop "$(printf '%s' "$out" | jgetp hookSpecificOutput.hookEventName)"
  assert_contains "claude block shows the failure" "TFAIL" "$(printf '%s' "$out" | jget reason)"
  printf "typecheck:\ntest: sh -c 'exit 0'\n" > "$PROJ/.dev-framework.yml"; : > "$DATA/edits-cc1.flag"
  out="$(printf '{"hook_event_name":"Stop","session_id":"cc1"}' | bash "$FW/hooks/lib/stop-gate.sh")"
  assert_empty "claude gate passes when green" "$out"

  # SessionStart: banner must name the host and the namespaced component names.
  rm -f "$PROJ/.dev-framework.yml"; export DEV_FRAMEWORK=strict
  out="$(printf '{"hook_event_name":"SessionStart","source":"startup"}' \
    | bash "$FW/hooks/lib/session-start.sh")"
  assert_eq "session start carries hookEventName" SessionStart "$(printf '%s' "$out" | jgetp hookSpecificOutput.hookEventName)"
  ctx="$(printf '%s' "$out" | jgetp hookSpecificOutput.additionalContext)"
  assert_contains "banner names the host" "host: Claude Code" "$ctx"
  assert_contains "banner namespaces agents" "dev-framework:pattern-guardian" "$ctx"
  assert_contains "banner names the Task tool" "subagent_type" "$ctx"
  assert_contains "constitution still injected" "DEV-FRAMEWORK CONSTITUTION" "$ctx"
  unset DEV_FRAMEWORK
  assert_empty "dormant claude session injects nothing" \
    "$(printf '{"hook_event_name":"SessionStart","source":"startup"}' | bash "$FW/hooks/lib/session-start.sh")"
)

echo "# Copilot banner stays Copilot-flavored"
(
  PROJ="$(newproj)"; export PLUGIN_ROOT="$FW" COPILOT_PROJECT_DIR="$PROJ" COPILOT_PLUGIN_DATA="$(mktemp -d)"
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA
  export DEV_FRAMEWORK=standard
  ctx="$(printf '{"hook_event_name":"sessionStart"}' | bash "$FW/hooks/lib/session-start.sh" | jget additionalContext)"
  assert_contains "banner names Copilot" "host: Copilot CLI" "$ctx"
  assert_contains "copilot agents are bare" "pattern-guardian, style-enforcer, and test-grounder agents" "$ctx"
  assert_contains "copilot built-ins mentioned" "rubber-duck" "$ctx"
  case "$ctx" in *dev-framework:pattern-guardian*) bad "copilot banner must not namespace" ;; *) ok "copilot banner must not namespace" ;; esac
  # The event name is echoed back in the host's own casing.
  out="$(printf '{"hook_event_name":"preToolUse","tool_input":{"path":"yarn.lock"}}' | bash "$FW/hooks/lib/pre-tool-use.sh")"
  assert_eq "copilot event casing echoed" preToolUse "$(printf '%s' "$out" | jgetp hookSpecificOutput.hookEventName)"
  assert_eq "copilot top-level deny kept" deny "$(printf '%s' "$out" | jget permissionDecision)"
)

echo "# Codex CLI hook dialect (PreToolUse / PostToolUse / Stop / SessionStart)"
(
  PROJ="$(newproj)"; DATA="$(newproj)"; CODEX_HOME="$(newproj)"; export CODEX_HOME
  export DF_HOST=codex PLUGIN_ROOT="$FW" PLUGIN_DATA="$DATA" DEV_FRAMEWORK=standard
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA CLAUDECODE
  unset COPILOT_PLUGIN_ROOT COPILOT_PROJECT_DIR COPILOT_PLUGIN_DATA
  cd "$PROJ" || exit 1
  out="$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: src/app.py\n*** Add File: yarn.lock\n*** End Patch"}}' | bash "$FW/hooks/lib/pre-tool-use.sh")"
  assert_eq "codex denies protected secondary target" deny "$(printf '%s' "$out" | jgetp hookSpecificOutput.permissionDecision)"
  assert_eq "codex deny carries hookEventName" PreToolUse "$(printf '%s' "$out" | jgetp hookSpecificOutput.hookEventName)"
  mkdir -p src
  echo x > src/a.py; echo y > src/b.py
  printf "%s\n" "format:" "lint: sh -c 'echo LINTBAD:\$1; exit 1' sh" > .dev-framework.yml
  out="$(printf '%s' '{"hook_event_name":"PostToolUse","session_id":"cx1","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: src/a.py\n*** Update File: src/b.py\n*** Delete File: src/gone.py\n*** End Patch"}}' | bash "$FW/hooks/lib/post-tool-use.sh")"
  ctx="$(printf '%s' "$out" | jgetp hookSpecificOutput.additionalContext)"
  assert_contains "codex lints first patch target" "src/a.py" "$ctx"
  assert_contains "codex lints second patch target" "src/b.py" "$ctx"
  [ -f "$DATA/edits-cx1.flag" ] && ok "codex edit marker in plugin data" || bad "codex edit marker in plugin data"
  git init -q; git -c user.email=t@t -c user.name=t commit -qm init --allow-empty
  printf "typecheck:\ntest: sh -c 'echo CFAIL; exit 1'\n" > .dev-framework.yml
  out="$(printf '%s' '{"hook_event_name":"Stop","session_id":"cx1"}' | bash "$FW/hooks/lib/stop-gate.sh")"
  assert_eq "codex gate blocks" block "$(printf '%s' "$out" | jget decision)"
  assert_contains "codex gate returns failure" CFAIL "$(printf '%s' "$out" | jget reason)"
  rm -f .dev-framework.yml; export DEV_FRAMEWORK=strict
  out="$(printf '%s' '{"hook_event_name":"SessionStart","source":"startup"}' | bash "$FW/hooks/lib/session-start.sh")"
  ctx="$(printf '%s' "$out" | jgetp hookSpecificOutput.additionalContext)"
  assert_contains "codex banner names host" "host: Codex CLI" "$ctx"
  assert_contains "codex banner uses skill syntax" '$dev-framework:peer-review' "$ctx"
  assert_contains "codex banner has built-in fallback" 'built-in `explorer` or `default`' "$ctx"
  mkdir -p "$CODEX_HOME/agents"
  touch "$CODEX_HOME/agents/dev-framework-pattern-guardian.toml" "$CODEX_HOME/agents/dev-framework-style-enforcer.toml" "$CODEX_HOME/agents/dev-framework-test-grounder.toml"
  ctx="$(printf '%s' '{"hook_event_name":"SessionStart","source":"startup"}' | bash "$FW/hooks/lib/session-start.sh" | jgetp hookSpecificOutput.additionalContext)"
  assert_contains "codex banner names installed agent" dev_framework_pattern_guardian "$ctx"
  unset DEV_FRAMEWORK
  assert_empty "dormant codex session injects nothing" "$(printf '%s' '{"hook_event_name":"SessionStart","source":"startup"}' | bash "$FW/hooks/lib/session-start.sh")"
)

echo "# hook manifests: all hosts, same engine"
(
  out="$(python3 - "$FW" <<'PY'
import json, os, re, sys
fw = sys.argv[1]
cop = json.load(open(os.path.join(fw, "hooks/hooks.copilot.json")))["hooks"]
cla = json.load(open(os.path.join(fw, "hooks/hooks.claude.json")))["hooks"]
cod = json.load(open(os.path.join(fw, "hooks/hooks.codex.json")))["hooks"]
def scripts(cmds):
    return {m.group(1) for c in cmds for m in re.finditer(r"hooks/lib/([a-z-]+\.sh)", c)}
cop_cmds = [e.get("bash", "") for entries in cop.values() for e in entries]
cla_cmds = [h.get("command", "") for groups in cla.values() for g in groups for h in g["hooks"]]
cod_cmds = [h.get("command", "") for groups in cod.values() for g in groups for h in g["hooks"]]
print("copilot_events=" + ",".join(sorted(cop)))
print("claude_events=" + ",".join(sorted(cla)))
print("codex_events=" + ",".join(sorted(cod)))
print("same_scripts=" + str(scripts(cop_cmds) == scripts(cla_cmds) == scripts(cod_cmds)).lower())
print("claude_uses_plugin_root=" + str(all("${CLAUDE_PLUGIN_ROOT}" in c for c in cla_cmds)).lower())
print("copilot_uses_plugin_root=" + str(all("$PLUGIN_ROOT" in c for c in cop_cmds)).lower())
print("codex_uses_plugin_root=" + str(all("$PLUGIN_ROOT" in c for c in cod_cmds)).lower())
print("codex_sets_host=" + str(all("DF_HOST=codex" in c for c in cod_cmds)).lower())
PY
)"
  eval "$out"
  assert_eq "copilot events are camelCase" "agentStop,postToolUse,preToolUse,sessionStart" "$copilot_events"
  assert_eq "claude events are PascalCase" "PostToolUse,PreToolUse,SessionStart,Stop" "$claude_events"
  assert_eq "codex events are PascalCase" "PostToolUse,PreToolUse,SessionStart,Stop" "$codex_events"
  assert_eq "all hosts drive the same scripts" true "$same_scripts"
  assert_eq "claude uses CLAUDE_PLUGIN_ROOT" true "$claude_uses_plugin_root"
  assert_eq "copilot uses PLUGIN_ROOT" true "$copilot_uses_plugin_root"
  assert_eq "codex uses PLUGIN_ROOT" true "$codex_uses_plugin_root"
  assert_eq "codex commands force host" true "$codex_sets_host"
  [ -f "$FW/hooks/hooks.json" ] && bad "no ambiguous hooks/hooks.json" || ok "no ambiguous hooks/hooks.json"
  [ -f "$FW/.claude-plugin/plugin.json" ] && ok "claude manifest present" || bad "claude manifest present"
  [ -f "$FW/.claude-plugin/marketplace.json" ] && ok "claude marketplace present" || bad "claude marketplace present"
  [ -f "$FW/.codex-plugin/plugin.json" ] && ok "codex manifest present" || bad "codex manifest present"
  [ -f "$FW/.agents/plugins/marketplace.json" ] && ok "codex marketplace present" || bad "codex marketplace present"
  [ -f "$FW/hooks/hooks.codex.json" ] && ok "codex hook manifest present" || bad "codex hook manifest present"
  [ -f "$FW/codex-agents/dev-framework-pattern-guardian.toml" ] && ok "codex pattern agent present" || bad "codex pattern agent present"
  [ -f "$FW/codex-agents/dev-framework-style-enforcer.toml" ] && ok "codex style agent present" || bad "codex style agent present"
  [ -f "$FW/codex-agents/dev-framework-test-grounder.toml" ] && ok "codex test agent present" || bad "codex test agent present"
)

echo "# three-host manifest validation"
(
  out="$(python3 "$FW/.github/scripts/validate-manifests.py" 2>&1)"; rc=$?
  assert_eq "manifest validator passes" 0 "$rc"
  assert_contains "validator reports codex" "Copilot CLI + Claude Code + Codex CLI" "$out"
)

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

echo "# df CLI: host selection + launch"
(
  PROJ="$(newproj)"; cd "$PROJ" || exit 1; git init -q
  unset DEV_FRAMEWORK COPILOT_PROJECT_DIR DF_HOST
  # Stub all three CLIs so we can observe exactly what `df` would exec.
  bindir="$(mktemp -d)"
  for h in claude copilot codex; do
    printf '#!/bin/sh\necho "LAUNCH host=%s profile=$DEV_FRAMEWORK args=$*"\n' "$h" > "$bindir/$h"
    chmod +x "$bindir/$h"
  done
  export PATH="$bindir:$PATH"

  assert_contains "df status reports the host" "host             : Claude Code" "$("$FW/bin/df" claude status)"
  assert_contains "df status copilot host" "host             : Copilot CLI" "$("$FW/bin/df" copilot status)"
  assert_contains "df status codex host" "host             : Codex CLI" "$("$FW/bin/df" codex status)"
  assert_contains "DF_HOST steers status" "host             : Claude Code" "$(DF_HOST=claude "$FW/bin/df" status)"
  assert_contains "--host= steers status" "host             : Claude Code" "$("$FW/bin/df" --host=claude status)"
  assert_contains "--host= accepts aliases" "host             : Claude Code" "$("$FW/bin/df" --host=cc status)"
  assert_contains "--host= accepts codex alias" "host             : Codex CLI" "$("$FW/bin/df" --host=openai-codex status)"
  assert_eq "--host space form" "LAUNCH host=claude profile=standard args=" "$("$FW/bin/df" --host claude)"
  assert_contains "status lists installed CLIs" "CLIs installed   : copilot claude codex" "$("$FW/bin/df" status)"

  # Host and profile in either order, and the profile reaches the CLI as DEV_FRAMEWORK.
  assert_eq "host then profile" "LAUNCH host=claude profile=strict args=--resume" "$("$FW/bin/df" claude strict --resume)"
  assert_eq "profile then host" "LAUNCH host=claude profile=strict args=" "$("$FW/bin/df" strict claude)"
  assert_eq "codex host and profile" "LAUNCH host=codex profile=strict args=--search" "$("$FW/bin/df" codex strict --search)"
  assert_eq "copilot is the default when both exist" "LAUNCH host=copilot profile=standard args=" "$("$FW/bin/df")"
  assert_eq "unknown args pass through" "LAUNCH host=copilot profile=standard args=--foo bar" "$("$FW/bin/df" --foo bar)"
  assert_eq "df off launches dormant" "LAUNCH host=copilot profile=off args=" "$("$FW/bin/df" off)"

  # A repo can pin its host; an explicit word and DF_HOST still win.
  printf 'profile: advisory\nhost: claude\n' > "$PROJ/.dev-framework.yml"
  assert_eq "repo host: claude honored" "LAUNCH host=claude profile= args=" "$("$FW/bin/df")"
  assert_eq "word beats repo host" "LAUNCH host=copilot profile= args=" "$("$FW/bin/df" copilot)"
  assert_eq "DF_HOST beats repo host" "LAUNCH host=copilot profile= args=" "$(DF_HOST=copilot "$FW/bin/df")"
  assert_contains "repo host shows in status" "host             : Claude Code" "$("$FW/bin/df" status)"
  printf 'profile: advisory\nhost: codex\n' > "$PROJ/.dev-framework.yml"
  assert_eq "repo host: codex honored" "LAUNCH host=codex profile= args=" "$("$FW/bin/df")"
  rm -f "$PROJ/.dev-framework.yml"

  claude_codex="$(mktemp -d)"; cp "$bindir/claude" "$bindir/codex" "$claude_codex/"
  assert_eq "claude precedes codex by default" "LAUNCH host=claude profile=standard args=" "$(PATH="$claude_codex:/usr/bin:/bin" "$FW/bin/df")"
  onlycodex="$(mktemp -d)"; cp "$bindir/codex" "$onlycodex/codex"
  assert_eq "codex is default when alone" "LAUNCH host=codex profile=standard args=" "$(PATH="$onlycodex:/usr/bin:/bin" "$FW/bin/df")"

  # A missing host binary must fail loudly and point at the one that is installed.
  onlyclaude="$(mktemp -d)"; cp "$bindir/claude" "$onlyclaude/claude"
  out="$(PATH="$onlyclaude:/usr/bin:/bin" DF_HOST=copilot "$FW/bin/df" 2>&1)"; rc=$?
  assert_eq "missing host exits 127" 127 "$rc"
  assert_contains "missing host names it" "'copilot' not found on PATH" "$out"
  assert_contains "missing host suggests the other" "try: df claude" "$out"
  out="$(PATH="$onlyclaude:/usr/bin:/bin" DF_HOST=codex "$FW/bin/df" 2>&1)"; rc=$?
  assert_eq "missing codex exits 127" 127 "$rc"
  assert_contains "missing codex names it" "'codex' not found on PATH" "$out"
  assert_contains "missing codex suggests installed host" "try: df claude" "$out"

  assert_eq "unknown host rejected" 2 "$( "$FW/bin/df" --host=emacs >/dev/null 2>&1; echo $?)"
  help="$("$FW/bin/df" help)"
  assert_contains "help documents claude" "df claude" "$help"
  assert_contains "help documents copilot" "df copilot" "$help"
  assert_contains "help documents codex" "df codex" "$help"
  assert_contains "help documents precedence" "Host precedence" "$help"
)

echo "# Codex CLI install and uninstall ownership"
(
  bindir="$(mktemp -d)"; CODEX_HOME="$(mktemp -d)"; export CODEX_HOME
cat > "$bindir/codex" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$CODEX_HOME/codex.log"
[ "${CODEX_STUB_FAIL:-0}" = 0 ]
SH
  chmod +x "$bindir/codex"
  PATH="$bindir:/usr/bin:/bin" "$FW/install.sh" codex > "$CODEX_HOME/install.out" 2>&1; rc=$?
  assert_eq "codex install succeeds" 0 "$rc"
  log="$(cat "$CODEX_HOME/codex.log" 2>/dev/null)"
  assert_contains "codex registers marketplace" "plugin marketplace add $FW" "$log"
  assert_contains "codex installs plugin" "plugin add dev-framework@dev-framework" "$log"
  [ -f "$CODEX_HOME/agents/dev-framework-pattern-guardian.toml" ] && ok "codex installs pattern agent" || bad "codex installs pattern agent"
  [ -f "$CODEX_HOME/agents/dev-framework-style-enforcer.toml" ] && ok "codex installs style agent" || bad "codex installs style agent"
  [ -f "$CODEX_HOME/agents/dev-framework-test-grounder.toml" ] && ok "codex installs test agent" || bad "codex installs test agent"
  PATH="$bindir:/usr/bin:/bin" "$FW/install.sh" codex >/dev/null 2>&1; rc=$?
  assert_eq "identical codex agent install is idempotent" 0 "$rc"

  CONFLICT_HOME="$(mktemp -d)"; mkdir -p "$CONFLICT_HOME/agents"
  echo user > "$CONFLICT_HOME/agents/dev-framework-pattern-guardian.toml"
  CODEX_HOME="$CONFLICT_HOME" PATH="$bindir:/usr/bin:/bin" "$FW/install.sh" codex > "$CONFLICT_HOME/install.out" 2>&1; rc=$?
  assert_eq "codex agent conflict aborts install" 1 "$rc"
  assert_empty "codex conflict precedes plugin mutation" "$(cat "$CONFLICT_HOME/codex.log" 2>/dev/null)"
  assert_contains "codex conflict names destination" "dev-framework-pattern-guardian.toml" "$(cat "$CONFLICT_HOME/install.out")"

  FAIL_HOME="$(mktemp -d)"
  CODEX_STUB_FAIL=1 CODEX_HOME="$FAIL_HOME" PATH="$bindir:/usr/bin:/bin" "$FW/install.sh" codex > "$FAIL_HOME/install.out" 2>&1; rc=$?
  assert_eq "codex plugin failure exits one" 1 "$rc"
  assert_contains "codex plugin failure is distinguished from missing binary" "Codex CLI installation failed" "$(cat "$FAIL_HOME/install.out")"

  echo modified > "$CODEX_HOME/agents/dev-framework-style-enforcer.toml"
  PATH="$bindir:/usr/bin:/bin" "$FW/uninstall.sh" codex > "$CODEX_HOME/uninstall.out" 2>&1; rc=$?
  assert_eq "codex uninstall succeeds" 0 "$rc"
  log="$(cat "$CODEX_HOME/codex.log")"
  assert_contains "codex removes plugin" "plugin remove dev-framework" "$log"
  [ ! -e "$CODEX_HOME/agents/dev-framework-pattern-guardian.toml" ] && ok "codex removes unchanged pattern agent" || bad "codex removes unchanged pattern agent"
  [ -f "$CODEX_HOME/agents/dev-framework-style-enforcer.toml" ] && ok "codex preserves modified style agent" || bad "codex preserves modified style agent"
  [ ! -e "$CODEX_HOME/agents/dev-framework-test-grounder.toml" ] && ok "codex removes unchanged test agent" || bad "codex removes unchanged test agent"
  assert_contains "codex uninstall warns about modified agent" "preserving modified agent" "$(cat "$CODEX_HOME/uninstall.out")"
)

echo
PASS=$(grep -c '^P$' "$DF_TALLY"); PASS=${PASS:-0}
FAIL=$(grep -c '^F$' "$DF_TALLY"); FAIL=${FAIL:-0}
rm -f "$DF_TALLY"
echo "================  $PASS passed, $FAIL failed  ================"
[ "$FAIL" -eq 0 ]
