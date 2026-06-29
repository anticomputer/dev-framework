#!/usr/bin/env bash
# agentStop hook: the completion gate. When active (standard/strict), run the repo's
# type-check + tests (and, in strict, lint on changed files) before the agent may finish;
# block on failure and feed the output back. In advisory profile it reports without
# blocking. Skips entirely when the session changed no files. No-op when off.
set -uo pipefail
. "$(dirname "$0")/common.sh"

df_active || exit 0
df_read_stdin

root="$(df_project_root)"
session="$(df_json_get session_id)"; [ -n "$session" ] || session="default"
data="$(df_data_dir)"
counter="$data/gate-$(df_session_safe "$session").count"
max="$(df_opt gate_max_blocks)"
gate_timeout="$(df_cfg gate_timeout '')"

# Skip the gate when nothing was edited this session (only when we can reliably tell).
if df_truthy "$(df_opt gate_skip_unchanged)" && [ -w "$data" ] && [ ! -f "$(df_edit_marker "$session")" ]; then
  exit 0
fi

run_cmd() { # label, command  -> prints a failure block on non-zero, nothing on success
  local label="$1" cmd="$2" out rc
  [ -n "$cmd" ] || return 0
  if [ -n "$gate_timeout" ] && command -v timeout >/dev/null 2>&1; then
    cmd="timeout $gate_timeout sh -c $(printf '%q' "$cmd")"
  fi
  out="$( ( cd "$root" && eval "$cmd" ) 2>&1 )"; rc=$?
  [ $rc -ne 0 ] && printf '### %s failed: `%s` (exit %d)\n%s\n\n' "$label" "$2" "$rc" "$(printf '%s' "$out" | tail -c 3000)"
}

failures=""

# --- type-check ------------------------------------------------------------
if df_truthy "$(df_opt gate_run_typecheck)"; then
  failures="${failures}$(run_cmd 'Type-check' "$(df_cfg typecheck "$(df_detect_typecheck)")")"
fi

# --- tests (optionally scoped to changed files) ----------------------------
if df_truthy "$(df_opt gate_run_tests)"; then
  tcmd=""
  if [ "$(df_opt gate_scope)" = "changed" ]; then
    changed="$(df_changed_files | tr '\n' ' ')"
    tchanged="$(df_cfg test_changed '')"
    if [ -n "$tchanged" ] && [ -n "${changed// /}" ]; then
      tcmd="$(df_apply_files "$tchanged" "$changed")"
    fi
  fi
  [ -n "$tcmd" ] || tcmd="$(df_cfg test "$(df_detect_test)")"
  failures="${failures}$(run_cmd 'Tests' "$tcmd")"
fi

# --- lint on changed files (strict / opt-in) -------------------------------
if df_truthy "$(df_opt gate_lint_changed)"; then
  while IFS= read -r cf; do
    [ -n "$cf" ] || continue
    [ -f "$root/$cf" ] || continue
    lc="$(df_lang_cmd lint "$cf")"
    [ -n "$lc" ] || continue
    failures="${failures}$(run_cmd "Lint $cf" "$(df_apply_file "$lc" "$root/$cf")")"
  done <<EOF
$(df_changed_files)
EOF
fi

# --- verdict ---------------------------------------------------------------
if [ -z "$failures" ]; then
  rm -f "$counter" 2>/dev/null || true
  df_clear_edit "$session"
  exit 0
fi

if ! df_truthy "$(df_opt gate_block_on_failure)"; then
  df_emit_context "dev-framework completion gate (advisory — not blocking) saw failures:

$failures
Per the testing-discipline rule, do not claim success while these are red."
  exit 0
fi

count=0; [ -f "$counter" ] && count="$(cat "$counter" 2>/dev/null || echo 0)"
case "$count" in ''|*[!0-9]*) count=0 ;; esac

if [ "$count" -ge "$max" ]; then
  rm -f "$counter" 2>/dev/null || true
  df_emit_context "dev-framework completion gate has blocked $max times and is standing
down to avoid trapping you. The checks are STILL failing:

$failures
Do not claim the work is complete. Tell the user plainly what remains red and why."
  exit 0
fi

echo $((count + 1)) > "$counter" 2>/dev/null || true
df_emit_block "dev-framework completion gate — you cannot finish yet. The repo's checks are failing:

$failures
Fix the underlying cause and continue. Do NOT disable, skip, or weaken these checks to
get past the gate. If a failure is pre-existing and unrelated to your work, prove it
(show it fails on a clean tree) and report it to the user. (Block $((count + 1))/${max} this session.)"
exit 0
