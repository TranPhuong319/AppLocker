#!/bin/bash
set -euo pipefail

INPUT=$(cat)
REASON=$(printf '%s' "$INPUT" | /usr/bin/jq -r '.terminationReason // empty' 2>/dev/null || true)
CONTINUATION=$(printf '%s' "$INPUT" | /usr/bin/jq -r '.continuationActive // false' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | /usr/bin/jq -r '.cwd // empty' 2>/dev/null || true)

# Only gate normal turn completions and prevent infinite continuation loops
if [ "$REASON" != "NO_TOOL_CALL" ] || [ "$CONTINUATION" = "true" ]; then
  printf '{"decision":"allow"}\n'
  exit 0
fi

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
  CWD="$(cd "$(dirname "$0")/../.." && pwd)"
fi

if ! command -v /usr/local/bin/swiftlint >/dev/null 2>&1; then
  printf '{"decision":"allow"}\n'
  exit 0
fi

# Collect existing modified/untracked .swift files relative to repo root
SWIFT_FILES=()
while IFS= read -r -d '' entry; do
  status="${entry:0:2}"
  path="${entry:3}"
  # Skip deletions
  if [[ "$status" == *D* ]]; then
    continue
  fi
  if [[ "$path" == *.swift ]] && [ -f "$CWD/$path" ]; then
    SWIFT_FILES+=("$path")
  fi
done < <(git -C "$CWD" status --porcelain -z -uall 2>/dev/null || true)

if [ "${#SWIFT_FILES[@]}" -eq 0 ]; then
  printf '{"decision":"allow"}\n'
  exit 0
fi

set +e
LINT_OUTPUT=$(cd "$CWD" && /usr/local/bin/swiftlint lint --strict --quiet --force-exclude "${SWIFT_FILES[@]}" 2>&1)
LINT_EXIT=$?
set -e

if [ "$LINT_EXIT" -ne 0 ]; then
  TRIMMED=$(printf '%s\n' "$LINT_OUTPUT" | head -n 30)
  REASON_MSG=$(printf 'SwiftLint (--strict) failed on modified Swift files:\n%s\n\nFix all warnings/errors before finishing.' "$TRIMMED")
  /usr/bin/jq -n --arg reason "$REASON_MSG" '{
    decision: "continue",
    reason: $reason
  }'
  exit 0
fi

printf '{"decision":"allow"}\n'
