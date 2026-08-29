#!/usr/bin/env bash
# preToolUse (Copilot CLI) / PreToolUse (Claude Code and Codex CLI) hook: guard protected paths.
# Before the agent edits/creates a file, check it against the `protect:` globs. In
# standard/strict the edit is DENIED; in advisory it is allowed with a warning.
# Disabled by `protect_off: true`. No-op when off.
set -uo pipefail
. "$(dirname "$0")/common.sh"
DF_EVENT=PreToolUse

df_active || exit 0
df_truthy "$(df_opt protect_off)" && exit 0
df_read_stdin

globs="$(df_opt protect)"
[ -n "$globs" ] || exit 0
protected=""
while IFS= read -r file; do
  [ -n "$file" ] || continue
  df_match_globs "$file" "$globs" || continue
  protected="${protected}${protected:+, }$file"
done <<EOF
$(df_tool_files)
EOF
[ -n "$protected" ] || exit 0

reason="dev-framework: \`$protected\` matches a protected path (lockfiles, secrets, vendored,
generated, or build output). These are not meant to be hand-edited.
If you genuinely need to change it, ask the user to confirm, or adjust \`protect:\` /
set \`protect_off: true\` in .dev-framework.yml. Regenerate lockfiles with the package
manager rather than editing them directly."

if [ "$(df_opt protect_mode)" = "warn" ]; then
  df_emit_context "$reason (advisory profile — allowed, but reconsider.)"
else
  df_emit_deny "$reason"
fi
exit 0
