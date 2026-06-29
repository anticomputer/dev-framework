#!/usr/bin/env bash
# uninstall.sh — remove the dev-framework plugin registration. Leaves this directory
# (and your code) untouched. Run while no copilot session is active.
set -euo pipefail

COPILOT_HOME="${COPILOT_HOME:-$HOME/.copilot}"
CONFIG="$COPILOT_HOME/config.json"
SETTINGS="$COPILOT_HOME/settings.json"
NAME="dev-framework"
MARKETPLACE="dev-framework"
command -v python3 >/dev/null 2>&1 || { echo "uninstall: python3 is required." >&2; exit 1; }

ts="$(date +%Y%m%d%H%M%S)"
[ -f "$CONFIG" ] && cp "$CONFIG" "$CONFIG.bak.$ts"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak.$ts"

[ -f "$CONFIG" ] && python3 - "$CONFIG" "$NAME" "$MARKETPLACE" <<'PY'
import json, sys, os
path, name, market = sys.argv[1:4]
raw = open(path).read()
brace = raw.find('{'); header = raw[:brace] if brace > 0 else ""; body = raw[brace:] if brace >= 0 else "{}"
data = json.loads(body) if body.strip() else {}
data["installedPlugins"] = [p for p in data.get("installedPlugins", [])
                            if not (p.get("name") == name and p.get("marketplace") == market)]
open(path, "w").write(header + json.dumps(data, indent=2) + "\n")
print("  config.json: removed registry entry")
PY

[ -f "$SETTINGS" ] && python3 - "$SETTINGS" "$NAME" "$MARKETPLACE" <<'PY'
import json, sys, os
path, name, market = sys.argv[1:4]
data = json.load(open(path)) if os.path.exists(path) else {}
data.get("enabledPlugins", {}).pop(f"{name}@{market}", None)
open(path, "w").write(json.dumps(data, indent=2) + "\n")
print("  settings.json: disabled entry")
PY

echo "dev-framework uninstalled. Backups: .bak.$ts"
