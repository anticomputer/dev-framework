#!/usr/bin/env bash
# install.sh — install dev-framework via the official Copilot CLI plugin marketplace
# flow (the future-proof path: direct repo/URL/local-path installs are deprecated).
#
# This registers THIS directory as a marketplace and installs the plugin from it. To
# install from GitHub on another machine instead, run:
#   copilot plugin marketplace add anticomputer/dev-framework
#   copilot plugin install dev-framework@dev-framework
set -euo pipefail

FW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v copilot >/dev/null 2>&1 || { echo "install: 'copilot' not found on PATH." >&2; exit 127; }

echo "Registering marketplace and installing dev-framework from $FW ..."
copilot plugin marketplace add "$FW"
copilot plugin install dev-framework@dev-framework

cat <<EOF

dev-framework installed (dormant by default — it changes nothing until you opt in).

Put the df CLI on your PATH:
  export PATH="$FW/bin:\$PATH"

Activate per session:
  df                  # launch copilot with the framework active (standard profile)
  df strict|advisory  # pick an intensity
  DEV_FRAMEWORK=1 copilot

Or per repo (shared with your team): commit a .dev-framework.yml (run \`df init\`).

Verify:    copilot plugin list   (then in a session: /agent, /skills list)
Update:    copilot plugin update dev-framework   (after pushing changes)
Uninstall: ./uninstall.sh
EOF
