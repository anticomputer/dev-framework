#!/usr/bin/env bash
# uninstall.sh — remove dev-framework from every agent CLI that has it, via each one's
# official plugin command.
#
#   ./uninstall.sh           remove from every detected CLI
#   ./uninstall.sh claude    remove from Claude Code only
#   ./uninstall.sh copilot   remove from Copilot CLI only
#
# Equivalent: copilot plugin uninstall dev-framework  /  claude plugin uninstall dev-framework
set -euo pipefail

want="${1:-all}"
case "$want" in all|claude|copilot) : ;; *) echo "uninstall: unknown host '$want' (all|claude|copilot)" >&2; exit 2 ;; esac

removed=""
for host in copilot claude; do
  case "$want" in all) : ;; "$host") : ;; *) continue ;; esac
  command -v "$host" >/dev/null 2>&1 || continue
  echo "==> $host: uninstalling dev-framework"
  "$host" plugin uninstall dev-framework && removed="$removed $host"
done

if [ -z "$removed" ]; then
  echo "uninstall: no supported CLI found on PATH (looked for 'copilot' and 'claude')." >&2
  exit 127
fi
echo "dev-framework uninstalled from:${removed}"
