#!/usr/bin/env python3
"""Validate dev-framework plugin.json and marketplace.json against the documented
Copilot CLI plugin schema (https://docs.github.com/copilot/reference/cli-plugin-reference).

Checks the manifest fields, that component paths actually exist, and that referenced
agents/skills/hooks are well-formed. Exits non-zero on any error.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KEBAB = re.compile(r"^[a-zA-Z0-9-]+$")
# Documented plugin.json component fields (NO `rules` — not a supported field).
COMPONENT_FIELDS = {"agents", "skills", "commands", "hooks", "extensions", "mcpServers", "lspServers"}
errors = []


def err(msg):
    errors.append(msg)


def as_paths(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [v for v in value if isinstance(v, str)]
    return []


def check_plugin_json():
    path = os.path.join(ROOT, "plugin.json")
    data = json.load(open(path))
    name = data.get("name", "")
    if not name or not KEBAB.match(name):
        err(f"plugin.json: name must be kebab-case, got {name!r}")
    if "version" in data and not re.match(r"^\d+\.\d+\.\d+", str(data["version"])):
        err(f"plugin.json: version should be semver, got {data.get('version')!r}")
    if "rules" in data:
        err("plugin.json: 'rules' is not a supported component field — deliver instructions another way")
    # agents
    for d in as_paths(data.get("agents", "agents")):
        full = os.path.join(ROOT, d)
        if not os.path.isdir(full):
            err(f"plugin.json: agents path not found: {d}")
            continue
        if not any(f.endswith(".agent.md") for f in os.listdir(full)):
            err(f"plugin.json: no *.agent.md files in {d}")
    # skills
    for d in as_paths(data.get("skills", "skills")):
        full = os.path.join(ROOT, d)
        if not os.path.isfile(os.path.join(full, "SKILL.md")):
            err(f"plugin.json: skill dir missing SKILL.md: {d}")
    # hooks
    hooks = data.get("hooks")
    if isinstance(hooks, str):
        if not os.path.isfile(os.path.join(ROOT, hooks)):
            err(f"plugin.json: hooks file not found: {hooks}")
    return data


def check_agent_files():
    adir = os.path.join(ROOT, "agents")
    for f in os.listdir(adir):
        if not f.endswith(".agent.md"):
            continue
        text = open(os.path.join(adir, f)).read()
        m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
        if not m:
            err(f"agents/{f}: missing YAML frontmatter")
            continue
        fm = m.group(1)
        for field in ("name", "description"):
            if not re.search(rf"^{field}\s*:", fm, re.MULTILINE):
                err(f"agents/{f}: missing required frontmatter field '{field}'")


def check_skill_files():
    sdir = os.path.join(ROOT, "skills")
    for sub in os.listdir(sdir):
        skill = os.path.join(sdir, sub, "SKILL.md")
        if not os.path.isfile(skill):
            continue
        text = open(skill).read()
        m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
        if not m:
            err(f"skills/{sub}/SKILL.md: missing YAML frontmatter")
            continue
        fm = m.group(1)
        for field in ("name", "description"):
            if not re.search(rf"^{field}\s*:", fm, re.MULTILINE):
                err(f"skills/{sub}/SKILL.md: missing required frontmatter field '{field}'")


def check_hooks_json(plugin):
    hooks_path = plugin.get("hooks", "hooks.json")
    full = os.path.join(ROOT, hooks_path) if isinstance(hooks_path, str) else None
    if not full or not os.path.isfile(full):
        return
    data = json.load(open(full))
    valid_events = {
        "sessionStart", "sessionEnd", "userPromptSubmitted", "preToolUse", "preMcpToolCall",
        "postToolUse", "postToolUseFailure", "errorOccurred", "agentStop", "subagentStop",
        "subagentStart", "preCompact", "permissionRequest", "notification",
    }
    for event in (data.get("hooks") or {}):
        if event not in valid_events:
            err(f"{hooks_path}: unknown hook event '{event}'")
    for event, entries in (data.get("hooks") or {}).items():
        for e in entries:
            if not any(k in e for k in ("bash", "command", "powershell", "exec")):
                err(f"{hooks_path}: {event} entry missing a command (bash/command/exec)")


def check_marketplace_json():
    path = os.path.join(ROOT, ".github", "plugin", "marketplace.json")
    data = json.load(open(path))
    if not KEBAB.match(data.get("name", "")):
        err(f"marketplace.json: name must be kebab-case, got {data.get('name')!r}")
    if not (data.get("owner") or {}).get("name"):
        err("marketplace.json: owner.name is required")
    plugins = data.get("plugins")
    if not isinstance(plugins, list) or not plugins:
        err("marketplace.json: plugins must be a non-empty array")
        return
    for p in plugins:
        if not KEBAB.match(p.get("name", "")):
            err(f"marketplace.json: plugin name must be kebab-case, got {p.get('name')!r}")
        if not p.get("source"):
            err(f"marketplace.json: plugin {p.get('name')!r} missing required 'source'")


def main():
    plugin = check_plugin_json()
    check_agent_files()
    check_skill_files()
    check_hooks_json(plugin)
    check_marketplace_json()
    if errors:
        for e in errors:
            print(f"\u274c {e}")
        sys.exit(1)
    print("\u2705 manifests valid (plugin.json, marketplace.json, agents, skills, hooks)")


if __name__ == "__main__":
    main()
