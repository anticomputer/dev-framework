#!/usr/bin/env python3
"""Validate the dev-framework manifests for both host CLIs against their documented
plugin schemas:

  Copilot CLI   plugin.json + .github/plugin/marketplace.json + hooks/hooks.copilot.json
                https://docs.github.com/copilot/reference/cli-plugin-reference
  Claude Code   .claude-plugin/plugin.json + .claude-plugin/marketplace.json
                + hooks/hooks.claude.json
                https://code.claude.com/docs/en/plugins-reference

Checks the manifest fields, that component paths actually exist, that the two ecosystems
agree on version, and that referenced agents/skills/hooks are well-formed. Exits non-zero
on any error.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KEBAB = re.compile(r"^[a-zA-Z0-9-]+$")
# Documented Copilot plugin.json component fields (NO `rules` — not a supported field).
COMPONENT_FIELDS = {"agents", "skills", "commands", "hooks", "extensions", "mcpServers", "lspServers"}
# Copilot CLI hook events (camelCase).
COPILOT_EVENTS = {
    "sessionStart", "sessionEnd", "userPromptSubmitted", "preToolUse", "preMcpToolCall",
    "postToolUse", "postToolUseFailure", "errorOccurred", "agentStop", "subagentStop",
    "subagentStart", "preCompact", "permissionRequest", "notification",
}
# Claude Code hook events (PascalCase) — the subset a plugin realistically ships.
CLAUDE_EVENTS = {
    "SessionStart", "Setup", "SessionEnd", "UserPromptSubmit", "UserPromptExpansion",
    "Stop", "StopFailure", "PreToolUse", "PermissionRequest", "PermissionDenied",
    "PostToolUse", "PostToolUseFailure", "PostToolBatch", "SubagentStart", "SubagentStop",
    "TaskCreated", "TaskCompleted", "TeammateIdle", "FileChanged", "CwdChanged",
    "ConfigChange", "InstructionsLoaded", "WorktreeCreate", "WorktreeRemove",
    "PreCompact", "PostCompact", "MessageDisplay", "Notification", "Elicitation",
    "ElicitationResult",
}
errors = []
versions = {}


def err(msg):
    errors.append(msg)


def as_paths(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [v for v in value if isinstance(v, str)]
    return []


def load(*parts):
    path = os.path.join(ROOT, *parts)
    if not os.path.isfile(path):
        err(f"{os.path.join(*parts)}: file not found")
        return None
    try:
        return json.load(open(path))
    except json.JSONDecodeError as exc:
        err(f"{os.path.join(*parts)}: invalid JSON — {exc}")
        return None


def check_semver(label, value):
    if value is not None and not re.match(r"^\d+\.\d+\.\d+", str(value)):
        err(f"{label}: version should be semver, got {value!r}")


def check_copilot_plugin_json():
    data = load("plugin.json")
    if data is None:
        return {}
    name = data.get("name", "")
    if not name or not KEBAB.match(name):
        err(f"plugin.json: name must be kebab-case, got {name!r}")
    check_semver("plugin.json", data.get("version"))
    versions["plugin.json"] = data.get("version")
    if "rules" in data:
        err("plugin.json: 'rules' is not a supported component field — deliver instructions another way")
    # Every declared component path must exist (agents/skills/hooks get deeper checks below).
    for field in COMPONENT_FIELDS:
        for p in as_paths(data.get(field)):
            if not os.path.exists(os.path.join(ROOT, p)):
                err(f"plugin.json: {field} path not found: {p}")
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
    for h in as_paths(data.get("hooks", "hooks/hooks.json")):
        if not os.path.isfile(os.path.join(ROOT, h)):
            err(f"plugin.json: hooks file not found: {h}")
    return data


def check_claude_plugin_json():
    data = load(".claude-plugin", "plugin.json")
    if data is None:
        return {}
    name = data.get("name", "")
    if not name or not KEBAB.match(name):
        err(f".claude-plugin/plugin.json: name must be kebab-case, got {name!r}")
    check_semver(".claude-plugin/plugin.json", data.get("version"))
    versions[".claude-plugin/plugin.json"] = data.get("version")
    if not isinstance(data.get("keywords", []), list):
        err(".claude-plugin/plugin.json: keywords must be an array")
    # Claude Code resolves component paths relative to the plugin root and requires "./".
    for field in ("commands", "agents", "skills", "hooks", "mcpServers", "lspServers", "outputStyles"):
        for p in as_paths(data.get(field)):
            if not p.startswith("./"):
                err(f".claude-plugin/plugin.json: {field} path must start with './', got {p!r}")
            elif not os.path.exists(os.path.join(ROOT, p)):
                err(f".claude-plugin/plugin.json: {field} path not found: {p}")
    # Components must live at the plugin root, never inside .claude-plugin/.
    for stray in ("agents", "skills", "commands", "hooks"):
        if os.path.isdir(os.path.join(ROOT, ".claude-plugin", stray)):
            err(f".claude-plugin/{stray}/: components must live at the plugin root, not inside .claude-plugin/")
    # Auto-discovered defaults still have to be well-formed if we rely on them.
    if "agents" not in data and not os.path.isdir(os.path.join(ROOT, "agents")):
        err(".claude-plugin/plugin.json: no 'agents' field and no default agents/ directory")
    if "skills" not in data and not os.path.isdir(os.path.join(ROOT, "skills")):
        err(".claude-plugin/plugin.json: no 'skills' field and no default skills/ directory")
    return data


def check_agent_files():
    adir = os.path.join(ROOT, "agents")
    for f in sorted(os.listdir(adir)):
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
        # Claude Code reads `tools`/`disallowedTools` as comma-separated strings; a YAML
        # list here silently becomes a literal tool name and strands the agent.
        for field in ("tools", "disallowedTools"):
            m2 = re.search(rf"^{field}\s*:(.*)$", fm, re.MULTILINE)
            if m2 and not m2.group(1).strip():
                err(f"agents/{f}: '{field}' must be a comma-separated string, not a YAML list")


def check_skill_files():
    sdir = os.path.join(ROOT, "skills")
    for sub in sorted(os.listdir(sdir)):
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


def check_copilot_hooks(plugin):
    for rel in as_paths(plugin.get("hooks", "hooks/hooks.json")):
        data = load(rel)
        if data is None:
            continue
        for event, entries in (data.get("hooks") or {}).items():
            if event not in COPILOT_EVENTS:
                err(f"{rel}: unknown Copilot hook event '{event}'")
            for e in entries:
                if not any(k in e for k in ("bash", "command", "powershell", "exec")):
                    err(f"{rel}: {event} entry missing a command (bash/command/exec)")
                check_hook_script(rel, event, e.get("bash") or e.get("command") or "")


def check_claude_hooks(plugin):
    for rel in as_paths(plugin.get("hooks", "hooks/hooks.json")):
        rel = rel[2:] if rel.startswith("./") else rel
        data = load(rel)
        if data is None:
            continue
        for event, groups in (data.get("hooks") or {}).items():
            if event not in CLAUDE_EVENTS:
                err(f"{rel}: unknown Claude Code hook event '{event}'")
            if not isinstance(groups, list):
                err(f"{rel}: {event} must be an array of matcher groups")
                continue
            for group in groups:
                # Claude Code nests the handlers one level deeper than Copilot does.
                handlers = group.get("hooks")
                if not isinstance(handlers, list) or not handlers:
                    err(f"{rel}: {event} matcher group must contain a non-empty 'hooks' array")
                    continue
                for h in handlers:
                    if h.get("type") != "command":
                        err(f"{rel}: {event} handler type must be 'command', got {h.get('type')!r}")
                    if not h.get("command"):
                        err(f"{rel}: {event} handler missing 'command'")
                    check_hook_script(rel, event, h.get("command", ""))
                    if "bash" in h:
                        err(f"{rel}: {event} handler uses Copilot's 'bash' key; Claude Code needs 'command'")


def check_hook_script(rel, event, command):
    """Every hook command must point at a script that exists in this repo."""
    for match in re.finditer(r"(?:\$\{?(?:CLAUDE_)?PLUGIN_ROOT\}?)/([^\"'\s]+)", command):
        script = match.group(1)
        if not os.path.isfile(os.path.join(ROOT, script)):
            err(f"{rel}: {event} references a missing script: {script}")


def check_copilot_marketplace():
    data = load(".github", "plugin", "marketplace.json")
    if data is None:
        return
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
        check_semver("marketplace.json", p.get("version"))
        versions["marketplace.json"] = p.get("version")


def check_claude_marketplace():
    data = load(".claude-plugin", "marketplace.json")
    if data is None:
        return
    if not KEBAB.match(data.get("name", "")):
        err(f".claude-plugin/marketplace.json: name must be kebab-case, got {data.get('name')!r}")
    if not (data.get("owner") or {}).get("name"):
        err(".claude-plugin/marketplace.json: owner.name is required")
    plugins = data.get("plugins")
    if not isinstance(plugins, list) or not plugins:
        err(".claude-plugin/marketplace.json: plugins must be a non-empty array")
        return
    for p in plugins:
        if not KEBAB.match(p.get("name", "")):
            err(f".claude-plugin/marketplace.json: plugin name must be kebab-case, got {p.get('name')!r}")
        source = p.get("source")
        if not source:
            err(f".claude-plugin/marketplace.json: plugin {p.get('name')!r} missing required 'source'")
        elif isinstance(source, str):
            # Relative plugin sources resolve against the marketplace root and must be "./"-prefixed.
            if not source.startswith("./"):
                err(f".claude-plugin/marketplace.json: relative source must start with './', got {source!r}")
            elif not os.path.isdir(os.path.join(ROOT, source)):
                err(f".claude-plugin/marketplace.json: source directory not found: {source}")
        check_semver(".claude-plugin/marketplace.json", p.get("version"))
        versions[".claude-plugin/marketplace.json"] = p.get("version")


def check_versions_agree():
    """A release has to bump every manifest, or the two hosts drift apart."""
    distinct = {v for v in versions.values() if v is not None}
    if len(distinct) > 1:
        detail = ", ".join(f"{k}={v!r}" for k, v in sorted(versions.items()))
        err(f"version mismatch across manifests: {detail}")


def main():
    copilot = check_copilot_plugin_json()
    claude = check_claude_plugin_json()
    check_agent_files()
    check_skill_files()
    check_copilot_hooks(copilot)
    check_claude_hooks(claude)
    check_copilot_marketplace()
    check_claude_marketplace()
    check_versions_agree()
    if errors:
        for e in errors:
            print(f"❌ {e}")
        sys.exit(1)
    print("✅ manifests valid for both hosts (Copilot CLI + Claude Code): "
          "plugin manifests, marketplaces, agents, skills, hooks")


if __name__ == "__main__":
    main()
