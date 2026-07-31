#!/usr/bin/env bash
# install.sh — install dev-framework into every agent CLI you have, via each one's
# official plugin marketplace flow (the future-proof path: direct repo/URL/local-path
# installs are deprecated on Copilot CLI).
#
#   ./install.sh                 install into every detected CLI
#   ./install.sh claude          install into Claude Code only
#   ./install.sh copilot|codex   install into Copilot CLI or Codex CLI only
#
# This registers THIS directory as a marketplace and installs the plugin from it. To
# install from GitHub on another machine instead:
#   copilot plugin marketplace add anticomputer/dev-framework && copilot plugin install dev-framework@dev-framework
#   claude plugin marketplace add anticomputer/dev-framework && claude plugin install dev-framework@dev-framework --scope user
#   codex plugin marketplace add anticomputer/dev-framework
#   codex plugin add dev-framework@dev-framework
set -euo pipefail

FW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
want="${1:-all}"
case "$want" in all|claude|copilot|codex) : ;; *) echo "install: unknown host '$want' (all|claude|copilot|codex)" >&2; exit 2 ;; esac

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

codex_agents_dir() {
  local home="${CODEX_HOME:-}"
  if [ -z "$home" ]; then
    [ -n "${HOME:-}" ] || return 1
    home="$HOME/.codex"
  fi
  printf '%s/agents' "$home"
}

preflight_codex_agents() {
  local dir src dest
  dir="$(codex_agents_dir)" || { echo "install: cannot resolve Codex home." >&2; return 1; }
  for src in "$FW"/codex-agents/*.toml; do
    dest="$dir/${src##*/}"
    if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
      echo "install: refusing to overwrite conflicting Codex agent: $dest" >&2
      return 1
    fi
  done
}

install_codex() {
  local dir src
  echo "==> Codex CLI: registering marketplace and installing from $FW"
  codex plugin marketplace add "$FW" || return 1
  codex plugin add dev-framework@dev-framework || return 1
  dir="$(codex_agents_dir)" || return 1
  mkdir -p "$dir" || return 1
  for src in "$FW"/codex-agents/*.toml; do cp "$src" "$dir/${src##*/}" || return 1; done
  installed="$installed codex"
}

if { [ "$want" = all ] || [ "$want" = codex ]; } && command -v codex >/dev/null 2>&1; then
  preflight_codex_agents || exit 1
fi

case "$want" in
  all)
    install_copilot || true
    install_claude || true
    if command -v codex >/dev/null 2>&1; then
      install_codex || { echo "install: Codex CLI installation failed." >&2; exit 1; }
    fi
    ;;
  copilot)
    install_copilot || { echo "install: 'copilot' not found on PATH." >&2; exit 127; }
    ;;
  claude)
    install_claude || { echo "install: 'claude' not found on PATH." >&2; exit 127; }
    ;;
  codex)
    command -v codex >/dev/null 2>&1 || { echo "install: 'codex' not found on PATH." >&2; exit 127; }
    install_codex || { echo "install: Codex CLI installation failed." >&2; exit 1; }
    ;;
esac

if [ -z "$installed" ]; then
  echo "install: no supported CLI found on PATH (looked for 'copilot', 'claude', and 'codex')." >&2
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
  DEV_FRAMEWORK=1 copilot  /  DEV_FRAMEWORK=1 claude  /  DEV_FRAMEWORK=1 codex

Or per repo (shared with your team): commit a .dev-framework.yml (run \`df init\`).

Verify:
  copilot plugin list          (then in a session: /agent, /skills list)
  claude plugin list           (then in a session: /plugin, /agents)
  codex plugin list            (then in a session: /plugins, /hooks)
Update:    copilot plugin update dev-framework / claude plugin update dev-framework
           codex plugin marketplace upgrade dev-framework && codex plugin add dev-framework@dev-framework
Uninstall: ./uninstall.sh
EOF
