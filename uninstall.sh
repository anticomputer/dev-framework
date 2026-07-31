#!/usr/bin/env bash
# uninstall.sh — remove dev-framework from every agent CLI that has it, via each one's
# official plugin command.
#
#   ./uninstall.sh           remove from every detected CLI
#   ./uninstall.sh claude    remove from Claude Code only
#   ./uninstall.sh copilot|codex   remove from Copilot CLI or Codex CLI only
#
# Equivalent: copilot plugin uninstall dev-framework / claude plugin uninstall dev-framework / codex plugin remove dev-framework
set -euo pipefail

FW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
want="${1:-all}"
case "$want" in all|claude|copilot|codex) : ;; *) echo "uninstall: unknown host '$want' (all|claude|copilot|codex)" >&2; exit 2 ;; esac

removed=""
for host in copilot claude codex; do
  case "$want" in all) : ;; "$host") : ;; *) continue ;; esac
  command -v "$host" >/dev/null 2>&1 || continue
  echo "==> $host: uninstalling dev-framework"
  if [ "$host" = codex ]; then
    codex plugin remove dev-framework && removed="$removed codex"
  else
    "$host" plugin uninstall dev-framework && removed="$removed $host"
  fi
done

case " $removed " in
*" codex "*)
  codex_home="${CODEX_HOME:-}"
  if [ -z "$codex_home" ]; then
    [ -n "${HOME:-}" ] || { echo "uninstall: cannot resolve Codex home." >&2; exit 1; }
    codex_home="$HOME/.codex"
  fi
  for src in "$FW"/codex-agents/*.toml; do
    dest="$codex_home/agents/${src##*/}"
    [ -e "$dest" ] || continue
    if cmp -s "$src" "$dest"; then rm -f "$dest"
    else echo "uninstall: preserving modified agent: $dest" >&2; fi
  done
  ;;
esac

if [ -z "$removed" ]; then
  echo "uninstall: no supported CLI found on PATH (looked for 'copilot', 'claude', and 'codex')." >&2
  exit 127
fi
echo "dev-framework uninstalled from:${removed}"
