#!/usr/bin/env bash
# install.sh — install dev-framework into every agent CLI you have, via each one's
# official plugin marketplace flow (the future-proof path: direct repo/URL/local-path
# installs are deprecated on Copilot CLI).
#
#   ./install.sh                 install into every detected CLI
#   ./install.sh claude          install into Claude Code only
#   ./install.sh copilot         install into Copilot CLI only
#
# This registers THIS directory as a marketplace and installs the plugin from it. To
# install from GitHub on another machine instead:
#   copilot plugin marketplace add anticomputer/dev-framework
#   copilot plugin install dev-framework@dev-framework
#   claude  plugin marketplace add anticomputer/dev-framework
#   claude  plugin install dev-framework@dev-framework --scope user
set -euo pipefail

FW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
want="${1:-all}"
case "$want" in all|claude|copilot) : ;; *) echo "install: unknown host '$want' (all|claude|copilot)" >&2; exit 2 ;; esac

installed=""

install_copilot() {
  command -v copilot >/dev/null 2>&1 || return 1
  echo "==> Copilot CLI: registering marketplace and installing from $FW"
  copilot plugin marketplace add "$FW"
  copilot plugin install dev-framework@dev-framework
  installed="$installed copilot"
}

install_claude() {
  command -v claude >/dev/null 2>&1 || return 1
  echo "==> Claude Code: registering marketplace and installing from $FW"
  claude plugin marketplace add "$FW"
  claude plugin install dev-framework@dev-framework --scope user
  installed="$installed claude"
}

case "$want" in
  all)     install_copilot || true; install_claude || true ;;
  copilot) install_copilot || { echo "install: 'copilot' not found on PATH." >&2; exit 127; } ;;
  claude)  install_claude  || { echo "install: 'claude' not found on PATH." >&2; exit 127; } ;;
esac

if [ -z "$installed" ]; then
  echo "install: no supported CLI found on PATH (looked for 'copilot' and 'claude')." >&2
  exit 127
fi

cat <<EOF

dev-framework installed for:${installed}
(dormant by default — it changes nothing until you opt in).

Put the df CLI on your PATH:
  export PATH="$FW/bin:\$PATH"

Activate per session:
  df                  # launch your default CLI with the framework active (standard)
  df claude strict    # pick a host and an intensity
  DEV_FRAMEWORK=1 copilot      /      DEV_FRAMEWORK=1 claude

Or per repo (shared with your team): commit a .dev-framework.yml (run \`df init\`).

Verify:
  copilot plugin list          (then in a session: /agent, /skills list)
  claude plugin list           (then in a session: /plugin, /agents)
Update:    copilot plugin update dev-framework   /   claude plugin update dev-framework
Uninstall: ./uninstall.sh
EOF
