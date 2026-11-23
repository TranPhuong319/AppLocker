#!/bin/bash
set -euo pipefail

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | /usr/bin/jq -r '.cwd // empty' 2>/dev/null || true)

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
  CWD="$(cd "$(dirname "$0")/../.." && pwd)"
fi

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || true)

case "$BRANCH" in
  main|master|release/*)
    MSG="Branch Guard: Active git branch is '${BRANCH}'. Exercise extra caution with behavioral changes and never commit/push without explicit user instruction."
    /usr/bin/jq -n --arg msg "$MSG" '{
      injectSteps: [
        {
          systemMessage: {
            systemMessage: $msg
          }
        }
      ]
    }'
    ;;
  *)
    printf '{}\n'
    ;;
esac
