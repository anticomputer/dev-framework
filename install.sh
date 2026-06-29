#!/usr/bin/env bash
# install.sh — register the dev-framework as an installed Copilot CLI plugin.
#
# It points the plugin's cache_path directly at THIS directory (no copy/symlink), adds a
# registry entry to ~/.copilot/config.json, and enables it in settings.json. Because the
# framework is dormant unless a session opts in (DEV_FRAMEWORK=1 or a .dev-framework.yml
# in the repo), enabling it has no effect on ordinary `copilot` sessions.
#
# Run this while NO copilot session is active (the CLI rewrites config.json on exit).
# Re-runnable (idempotent). Use ./uninstall.sh to remove.
set -euo pipefail

FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPILOT_HOME="${COPILOT_HOME:-$HOME/.copilot}"
CONFIG="$COPILOT_HOME/config.json"
SETTINGS="$COPILOT_HOME/settings.json"
NAME="dev-framework"
MARKETPLACE="dev-framework"

[ -d "$COPILOT_HOME" ] || { echo "install: $COPILOT_HOME not found — is Copilot CLI installed?" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "install: python3 is required." >&2; exit 1; }

chmod +x "$FRAMEWORK_DIR/bin/df" 2>/dev/null || true

ts="$(date +%Y%m%d%H%M%S)"
[ -f "$CONFIG" ] && cp "$CONFIG" "$CONFIG.bak.$ts"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak.$ts"

# --- config.json: add/update the installedPlugins registry entry --------------
python3 - "$CONFIG" "$NAME" "$MARKETPLACE" "$FRAMEWORK_DIR" <<'PY'
import json, sys, datetime
path, name, market, cache = sys.argv[1:5]
raw = open(path).read() if __import__('os').path.exists(path) else "{}"
# Preserve a leading //-comment header, parse the JSON remainder.
brace = raw.find('{')
header = raw[:brace] if brace > 0 else ""
body = raw[brace:] if brace >= 0 else "{}"
data = json.loads(body) if body.strip() else {}
plugins = data.get("installedPlugins", [])
plugins = [p for p in plugins if not (p.get("name") == name and p.get("marketplace") == market)]
plugins.append({
    "name": name,
    "marketplace": market,
    "version": "0.1.0",
    "installed_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
    "enabled": True,
    "cache_path": cache,
})
data["installedPlugins"] = plugins
open(path, "w").write(header + json.dumps(data, indent=2) + "\n")
print(f"  config.json: registered {name}@{market} -> {cache}")
PY

# --- settings.json: enable the plugin ----------------------------------------
python3 - "$SETTINGS" "$NAME" "$MARKETPLACE" <<'PY'
import json, sys, os
path, name, market = sys.argv[1:4]
data = json.load(open(path)) if os.path.exists(path) else {}
ep = data.setdefault("enabledPlugins", {})
ep[f"{name}@{market}"] = True
open(path, "w").write(json.dumps(data, indent=2) + "\n")
print(f"  settings.json: enabled {name}@{market}")
PY

cat <<EOF

dev-framework installed (dormant by default).

Activate it for a session in either of these ways:
  1. Per session:   DEV_FRAMEWORK=1 copilot      (or use the wrapper: $FRAMEWORK_DIR/bin/df)
  2. Per repo:      copy .dev-framework.example.yml to a repo root as .dev-framework.yml

Tip: add the wrapper to your PATH:  export PATH="$FRAMEWORK_DIR/bin:\$PATH"   then run: df

Verify loading inside copilot with:  /env        (look for dev-framework rules/agents/skills/hooks)
Backups written with suffix .bak.$ts
EOF
