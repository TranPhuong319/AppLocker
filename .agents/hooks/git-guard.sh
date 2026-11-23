#!/bin/bash
set -euo pipefail

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | /usr/bin/jq -r '.toolCall.args.CommandLine // empty' 2>/dev/null || true)

if [ -z "$CMD" ]; then
  printf '{"decision":"ask"}\n'
  exit 0
fi

# Block unsolicited git state mutations per AGENTS.md
if printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+((-[Cc][[:space:]]+[^[:space:]]+[[:space:]]+)*)(commit|push|reset[[:space:]]+--hard|rebase|merge|checkout[[:space:]]+--|restore|clean[[:space:]]+-[a-zA-Z]*f|tag|branch[[:space:]]+-[dD])([[:space:]]|$)'; then
  /usr/bin/jq -n '{
    decision: "force_ask",
    reason: "Blocked automatic git state modification (git-guard hook). Explicit user approval is required per AGENTS.md."
  }'
  exit 0
fi

printf '{"decision":"ask"}\n'
