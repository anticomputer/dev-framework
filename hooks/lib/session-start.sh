#!/usr/bin/env bash
# sessionStart (Copilot CLI) / SessionStart (Claude Code and Codex CLI) hook: when active, inject a
# profile-aware ACTIVE banner with this repo's tooling and the working-loop directives.
# No-op when the profile is off.
set -uo pipefail
. "$(dirname "$0")/common.sh"
DF_EVENT=SessionStart

df_active || exit 0
df_read_stdin
profile="$(df_profile)"
root="$(df_project_root)"
fw_root="$(cd "$(dirname "$0")/../.." && pwd)"

test_cmd="$(df_cfg test "$(df_detect_test)")"
type_cmd="$(df_cfg typecheck "$(df_detect_typecheck)")"

fmt_note="auto-detected per file (prettier/ruff/black/gofmt/rustfmt where installed)"
[ -n "$(df_cfg format '')" ] && fmt_note="$(df_cfg format '')"
lint_note="auto-detected per file (eslint/ruff/flake8 where installed)"
[ -n "$(df_cfg lint '')" ] && lint_note="$(df_cfg lint '')"

# Describe the enforcement posture for this profile.
case "$profile" in
  advisory) posture="ADVISORY — you get formatting, lint, and review feedback inline, but nothing blocks. Treat the guidance as strong recommendations." ;;
  standard) posture="STANDARD — formatting/lint feedback is inline; the completion gate runs type-check + tests and BLOCKS finishing while they are red; protected paths cannot be edited." ;;
  strict)   posture="STRICT — as standard, plus lint on changed files must also pass at the gate; protected-path edits are denied. The bar is high." ;;
  *)        posture="active." ;;
esac

style_line=""
sg="$(df_cfg style_guide '')"
if [ -n "$sg" ] && [ -f "$root/$sg" ]; then
  style_line="- Project style guide: read \`$sg\` and follow it closely."
else
  for g in STYLE.md STYLEGUIDE.md docs/STYLE.md CONTRIBUTING.md; do
    [ -f "$root/$g" ] && { style_line="- Style reference found: \`$g\` (read it before writing)."; break; }
  done
fi

# Name specialists and skills the way this host expects them to be invoked.
guardian="$(df_agent_ref pattern-guardian)"
enforcer="$(df_agent_ref style-enforcer)"
grounder="$(df_agent_ref test-grounder)"
case "$(df_host)" in
claude)
  delegation="Delegate to them with the Task tool, passing the namespaced name as
\`subagent_type\`. The bundled skills are \`/$(df_skill_ref peer-review)\`,
\`/$(df_skill_ref ground-in-tests)\`, and \`/$(df_skill_ref match-patterns)\`. For a
general second opinion, spawn a plain subagent with a review brief."
  ;;
codex)
  peer="$(df_skill_ref peer-review)"
  tests="$(df_skill_ref ground-in-tests)"
  patterns="$(df_skill_ref match-patterns)"
  codex_agents="${CODEX_HOME:-}"
  [ -n "$codex_agents" ] || codex_agents="${HOME:-}/.codex"
  codex_agents="$codex_agents/agents"
  if [ -f "$codex_agents/dev-framework-pattern-guardian.toml" ] &&
     [ -f "$codex_agents/dev-framework-style-enforcer.toml" ] &&
     [ -f "$codex_agents/dev-framework-test-grounder.toml" ]; then
    delegation="Delegate reviews to \`$guardian\`, \`$enforcer\`, and \`$grounder\`. The bundled skills are
\`\$$peer\`, \`\$$tests\`, and \`\$$patterns\`."
  else
    delegation="Use a built-in \`explorer\` or \`default\` subagent with a focused review brief. The bundled skills are
\`\$$peer\`, \`\$$tests\`, and \`\$$patterns\`. The optional named dev-framework agents are installed by \`./install.sh codex\`."
  fi
  ;;
*)
  delegation="Delegate to them as subagents. The bundled skills are
\`$(df_skill_ref peer-review)\`, \`$(df_skill_ref ground-in-tests)\`, and
\`$(df_skill_ref match-patterns)\`. The built-in \`code-review\` and \`rubber-duck\`
agents are also available for a general second opinion."
  ;;
esac

banner="DEV-FRAMEWORK: ACTIVE (profile: ${profile}, host: $(df_host_label)).

${posture}

Work to the dev-framework discipline set out in the CONSTITUTION below: clear the
quality bar, match existing codebase patterns (do not re-invent helpers or add a second
way to do a thing), and ground every claim in tests you actually run. Use the
${guardian}, ${enforcer}, and ${grounder} agents as your default working loop.
${delegation}

This repo's verification tooling:
- Tests: ${test_cmd:-<none detected — set \`test:\` in .dev-framework.yml or run \`df init\`>}
- Type-check: ${type_cmd:-<none detected>}
- Format-on-edit: ${fmt_note}
- Lint-on-edit: ${lint_note}
${style_line}"

# Append the constitution (rules/*.md) so the discipline is in-context for this session.
# Plugins can't contribute always-on instructions, so we inject them here — which also
# means they only load when the framework is active.
constitution=""
if [ -d "$fw_root/rules" ]; then
  for rf in "$fw_root"/rules/*.md; do
    [ -f "$rf" ] || continue
    constitution="${constitution}

$(cat "$rf")"
  done
fi

if [ -n "$constitution" ]; then
  df_emit_context "$banner

============================ DEV-FRAMEWORK CONSTITUTION ============================
$constitution"
else
  df_emit_context "$banner"
fi
exit 0
