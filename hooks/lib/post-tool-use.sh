#!/usr/bin/env bash
# postToolUse hook: after the agent edits/creates a file, record that an edit happened
# (so the gate knows the session changed something), then auto-format and lint the file,
# feeding violations back. Respects `exclude:` globs. No-op when the profile is off.
set -uo pipefail
. "$(dirname "$0")/common.sh"

df_active || exit 0
df_read_stdin

file="$(df_json_get tool_input.path)"
[ -n "$file" ] || file="$(df_json_get tool_input.file_path)"
[ -n "$file" ] || exit 0

case "$file" in
  /*) : ;;
  *)  file="$(df_project_root)/$file" ;;
esac
[ -f "$file" ] || exit 0

# Record the edit for the completion gate's skip-unchanged check.
df_mark_edit "$(df_json_get session_id)"

# Honor exclude globs (skip framework tooling on these files).
exclude="$(df_cfg exclude '')"
if [ -n "$exclude" ] && df_match_globs "$file" "$exclude"; then
  exit 0
fi

feedback=""

if df_truthy "$(df_opt format_on_edit)"; then
  fmt_cmd="$(df_lang_cmd format "$file")"
  if [ -n "$fmt_cmd" ]; then
    full="$(df_apply_file "$fmt_cmd" "$file")"
    fmt_out="$( ( cd "$(df_project_root)" && eval "$full" ) 2>&1 )"; fmt_rc=$?
    [ $fmt_rc -ne 0 ] && feedback="${feedback}Formatter (\`$fmt_cmd\`) reported a problem with $file:
$(printf '%s' "$fmt_out" | head -c 1500)

"
  fi
fi

if df_truthy "$(df_opt lint_on_edit)"; then
  lint_cmd="$(df_lang_cmd lint "$file")"
  if [ -n "$lint_cmd" ]; then
    full="$(df_apply_file "$lint_cmd" "$file")"
    lint_out="$( ( cd "$(df_project_root)" && eval "$full" ) 2>&1 )"; lint_rc=$?
    [ $lint_rc -ne 0 ] && feedback="${feedback}Lint (\`$lint_cmd\`) found issues in $file you should fix:
$(printf '%s' "$lint_out" | head -c 2500)

"
  fi
fi

if [ -n "$feedback" ]; then
  df_emit_context "dev-framework — post-edit check on $file:

${feedback}Address these now while the context is fresh."
fi
exit 0
