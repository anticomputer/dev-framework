#!/usr/bin/env python3
"""Validate the dev-framework manifests for all three host CLIs against their documented
plugin schemas:

  Copilot CLI   plugin.json + .github/plugin/marketplace.json + hooks/hooks.copilot.json
                https://docs.github.com/copilot/reference/cli-plugin-reference
  Claude Code   .claude-plugin/plugin.json + .claude-plugin/marketplace.json
                + hooks/hooks.claude.json
                https://code.claude.com/docs/en/plugins-reference
  Codex CLI      .codex-plugin/plugin.json + .agents/plugins/marketplace.json
                + hooks/hooks.codex.json
                https://developers.openai.com/plugins/build/plugins

Checks the manifest fields, that component paths actually exist, that all version-bearing
manifests agree, and that referenced agents/skills/hooks are well-formed. Exits non-zero
on any error.
"""
import json
import os
import re
import sys
import tomllib

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
CODEX_EVENTS = {
    "SessionStart", "SessionEnd", "UserPromptSubmit", "Stop", "PreToolUse",
    "PermissionRequest", "PostToolUse", "SubagentStart", "SubagentStop",
    "PreCompact", "PostCompact",
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


def check_codex_plugin_json():
    data = load(".codex-plugin", "plugin.json")
    if data is None:
        return {}
    name = data.get("name", "")
    if not name or not KEBAB.match(name):
        err(f".codex-plugin/plugin.json: name must be kebab-case, got {name!r}")
    check_semver(".codex-plugin/plugin.json", data.get("version"))
    versions[".codex-plugin/plugin.json"] = data.get("version")
    for field in ("skills", "hooks", "mcpServers", "apps"):
        for p in as_paths(data.get(field)):
            if not p.startswith("./"):
                err(f".codex-plugin/plugin.json: {field} path must start with './', got {p!r}")
            elif not os.path.exists(os.path.join(ROOT, p)):
                err(f".codex-plugin/plugin.json: {field} path not found: {p}")
    for stray in ("skills", "hooks", "assets"):
        if os.path.isdir(os.path.join(ROOT, ".codex-plugin", stray)):
            err(f".codex-plugin/{stray}/: components must live at the plugin root, not inside .codex-plugin/")
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


def check_codex_agent_files():
    expected = {
        "dev-framework-pattern-guardian.toml": "dev_framework_pattern_guardian",
        "dev-framework-style-enforcer.toml": "dev_framework_style_enforcer",
        "dev-framework-test-grounder.toml": "dev_framework_test_grounder",
    }
    for filename, name in expected.items():
        path = os.path.join(ROOT, "codex-agents", filename)
        if not os.path.isfile(path):
            err(f"codex-agents/{filename}: file not found")
            continue
        try:
            with open(path, "rb") as handle:
                data = tomllib.load(handle)
        except (OSError, tomllib.TOMLDecodeError) as exc:
            err(f"codex-agents/{filename}: invalid TOML — {exc}")
            continue
        if data.get("name") != name:
            err(f"codex-agents/{filename}: name must be {name!r}, got {data.get('name')!r}")
        for field in ("description", "developer_instructions"):
            if not isinstance(data.get(field), str) or not data[field].strip():
                err(f"codex-agents/{filename}: {field} must be a non-empty string")
        if data.get("sandbox_mode") != "read-only":
            err(f"codex-agents/{filename}: sandbox_mode must be 'read-only'")
        for field in ("model", "model_reasoning_effort"):
            if field in data:
                err(f"codex-agents/{filename}: {field} must be inherited, not pinned")


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


def check_codex_hooks(plugin):
    for rel in as_paths(plugin.get("hooks", "hooks/hooks.json")):
        rel = rel[2:] if rel.startswith("./") else rel
        data = load(rel)
        if data is None:
            continue
        for event, groups in (data.get("hooks") or {}).items():
            if event not in CODEX_EVENTS:
                err(f"{rel}: unknown Codex CLI hook event '{event}'")
            if not isinstance(groups, list):
                err(f"{rel}: {event} must be an array of matcher groups")
                continue
            for group in groups:
                handlers = group.get("hooks")
                if not isinstance(handlers, list) or not handlers:
                    err(f"{rel}: {event} matcher group must contain a non-empty 'hooks' array")
                    continue
                for handler in handlers:
                    if handler.get("type") != "command":
                        err(f"{rel}: {event} handler type must be 'command', got {handler.get('type')!r}")
                    command = handler.get("command", "")
                    if not command:
                        err(f"{rel}: {event} handler missing 'command'")
                    if "DF_HOST=codex" not in command:
                        err(f"{rel}: {event} handler must set DF_HOST=codex")
                    if "$PLUGIN_ROOT" not in command:
                        err(f"{rel}: {event} handler must use $PLUGIN_ROOT")
                    check_hook_script(rel, event, command)


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


def check_codex_marketplace():
    data = load(".agents", "plugins", "marketplace.json")
    if data is None:
        return
    if not KEBAB.match(data.get("name", "")):
        err(f".agents/plugins/marketplace.json: name must be kebab-case, got {data.get('name')!r}")
    if not (data.get("interface") or {}).get("displayName"):
        err(".agents/plugins/marketplace.json: interface.displayName is required")
    plugins = data.get("plugins")
    if not isinstance(plugins, list) or not plugins:
        err(".agents/plugins/marketplace.json: plugins must be a non-empty array")
        return
    for plugin in plugins:
        if not KEBAB.match(plugin.get("name", "")):
            err(f".agents/plugins/marketplace.json: plugin name must be kebab-case, got {plugin.get('name')!r}")
        source = plugin.get("source")
        if not isinstance(source, dict) or source.get("source") != "local":
            err(f".agents/plugins/marketplace.json: plugin {plugin.get('name')!r} must use a local source object")
        else:
            path = source.get("path", "")
            if not isinstance(path, str) or not path.startswith("./"):
                err(f".agents/plugins/marketplace.json: local source path must start with './', got {path!r}")
            elif not os.path.isdir(os.path.join(ROOT, path)):
                err(f".agents/plugins/marketplace.json: source directory not found: {path}")
        policy = plugin.get("policy") or {}
        if policy.get("installation") not in {"AVAILABLE", "INSTALLED_BY_DEFAULT", "NOT_AVAILABLE"}:
            err(f".agents/plugins/marketplace.json: plugin {plugin.get('name')!r} has invalid installation policy")
        if not policy.get("authentication"):
            err(f".agents/plugins/marketplace.json: plugin {plugin.get('name')!r} missing authentication policy")
        if not plugin.get("category"):
            err(f".agents/plugins/marketplace.json: plugin {plugin.get('name')!r} missing category")


def check_versions_agree():
    """A release has to bump every version-bearing manifest, or the hosts drift apart."""
    distinct = {v for v in versions.values() if v is not None}
    if len(distinct) > 1:
        detail = ", ".join(f"{k}={v!r}" for k, v in sorted(versions.items()))
        err(f"version mismatch across manifests: {detail}")


def main():
    copilot = check_copilot_plugin_json()
    claude = check_claude_plugin_json()
    codex = check_codex_plugin_json()
    check_agent_files()
    check_skill_files()
    check_codex_agent_files()
    check_copilot_hooks(copilot)
    check_claude_hooks(claude)
    check_codex_hooks(codex)
    check_copilot_marketplace()
    check_claude_marketplace()
    check_codex_marketplace()
    check_versions_agree()
    if errors:
        for e in errors:
            print(f"❌ {e}")
        sys.exit(1)
    print("✅ manifests valid for all hosts (Copilot CLI + Claude Code + Codex CLI): "
          "plugin manifests, marketplaces, agents, skills, hooks")


if __name__ == "__main__":
    main()
