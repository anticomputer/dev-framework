#!/usr/bin/env bash
set -euo pipefail

FW="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v codex >/dev/null 2>&1; then
  echo "Codex CLI not installed — skipping live Codex plugin validation."
  exit 0
fi

stage="$(mktemp -d /tmp/dev-framework-codex-stage.XXXXXX)"
codex_home="$(mktemp -d /tmp/dev-framework-codex-home.XXXXXX)"
trap 'rm -rf -- "$stage" "$codex_home"' EXIT

run_codex() {
  if ! CODEX_HOME="$codex_home" codex "$@" 2>"$codex_home/stderr"; then
    cat "$codex_home/stderr" >&2
    return 1
  fi
}

mkdir -p "$stage/.codex-plugin" "$stage/.agents/plugins"
cp "$FW/.codex-plugin/plugin.json" "$stage/.codex-plugin/"
cp "$FW/.agents/plugins/marketplace.json" "$stage/.agents/plugins/"
cp -R "$FW/hooks" "$FW/skills" "$FW/codex-agents" "$stage/"

run_codex plugin marketplace add "$stage" >/dev/null
available="$(run_codex plugin list --available --json)"
python3 -c 'import json,sys; data=json.load(sys.stdin); assert any(p["pluginId"] == "dev-framework@dev-framework" for p in data["available"])' <<<"$available"
run_codex plugin add dev-framework@dev-framework --json >/dev/null
installed="$(run_codex plugin list --json)"
python3 -c 'import json,sys; data=json.load(sys.stdin); assert any(p["pluginId"] == "dev-framework@dev-framework" and p["enabled"] for p in data["installed"])' <<<"$installed"

echo "✅ Codex CLI plugin manifest, marketplace, hooks, and install flow are valid."
