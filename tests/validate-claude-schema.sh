#!/usr/bin/env bash
# Validate the Claude Code side of the plugin against Claude Code's OWN schema, using the
# `claude plugin validate` CLI. Skips cleanly (exit 0) when `claude` isn't installed, so it
# is safe to run anywhere.
#
# Why the staging dance: `claude plugin validate` only reads hooks from the DEFAULT path
# (hooks/hooks.json). It ignores the path declared in the manifest's `hooks` field, so
# validating this repo in place silently skips our hook config. We therefore validate a
# throwaway copy in which hooks/hooks.claude.json is staged as hooks/hooks.json. Shipping
# that file at the default path for real is not an option — see AGENTS.md.
#
# It also validates a marketplace.json in preference to a plugin.json when both are present,
# so the copy drops the marketplace manifest and it is validated in a second pass.
set -uo pipefail

FW="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v claude >/dev/null 2>&1; then
  echo "skip: 'claude' not on PATH — nothing to validate against."
  exit 0
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -r "$FW" "$STAGE/dev-framework"
PLUGIN="$STAGE/dev-framework"
rm -rf "$PLUGIN/.git"

rc=0

echo "==> marketplace manifest"
claude plugin validate "$PLUGIN" --strict || rc=1

echo "==> plugin manifest + agent/skill frontmatter + hooks"
mv "$PLUGIN/hooks/hooks.claude.json" "$PLUGIN/hooks/hooks.json"
python3 - "$PLUGIN/.claude-plugin/plugin.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
# The staged copy has the hooks config at the default path, so drop the explicit pointer.
data.pop("hooks", None)
json.dump(data, open(path, "w"), indent=2)
PY
rm -f "$PLUGIN/.claude-plugin/marketplace.json"
claude plugin validate "$PLUGIN" --strict || rc=1

[ "$rc" -eq 0 ] && echo "✅ Claude Code schema validation passed" \
                || echo "❌ Claude Code schema validation failed" >&2
exit "$rc"
