#!/usr/bin/env bash
# sessionStart hook: when active, inject a profile-aware ACTIVE banner with this repo's
# tooling and the working-loop directives. No-op when the profile is off.
set -uo pipefail
. "$(dirname "$0")/common.sh"

df_active || exit 0
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

banner="DEV-FRAMEWORK: ACTIVE (profile: ${profile}).

${posture}

Work to the dev-framework discipline set out in the CONSTITUTION below: clear the
quality bar, match existing codebase patterns (do not re-invent helpers or add a second
way to do a thing), and ground every claim in tests you actually run. Use the
pattern-guardian, style-enforcer, and test-grounder agents as your default working loop.

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
