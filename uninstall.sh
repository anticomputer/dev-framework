#!/usr/bin/env bash
# uninstall.sh — remove dev-framework via the official Copilot CLI plugin command.
# Equivalent: copilot plugin uninstall dev-framework
set -euo pipefail
command -v copilot >/dev/null 2>&1 || { echo "uninstall: 'copilot' not found on PATH." >&2; exit 127; }
copilot plugin uninstall dev-framework
echo "dev-framework uninstalled."
