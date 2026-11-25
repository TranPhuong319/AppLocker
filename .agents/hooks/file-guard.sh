#!/bin/bash
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | /usr/bin/jq -r '.toolCall.name // empty' 2>/dev/null || true)
TARGET_PATH=$(printf '%s' "$INPUT" | /usr/bin/jq -r '.toolCall.args.Path // empty' 2>/dev/null || true)

if [ -z "$TARGET_PATH" ]; then
  printf '{"decision":"allow"}\n'
  exit 0
fi

resolve_path() {
  local raw="$1"
  local prefix="${raw%/}"
  local suffix=""
  while [ -n "$prefix" ] && [ ! -e "$prefix" ]; do
    local base
    base=$(basename "$prefix")
    suffix="${suffix:+$base/$suffix}"
    suffix="${suffix:-$base}"
    local parent
    parent=$(dirname "$prefix")
    [ "$parent" = "$prefix" ] && break
    prefix="$parent"
  done
  if [ -d "$prefix" ]; then
    local abs_dir
    abs_dir=$(cd "$prefix" 2>/dev/null && pwd -P) || abs_dir="$prefix"
    printf '%s\n' "${abs_dir%/}${suffix:+/$suffix}"
  elif [ -e "$prefix" ]; then
    local abs_dir
    abs_dir=$(cd "$(dirname "$prefix")" 2>/dev/null && pwd -P) || abs_dir="$(dirname "$prefix")"
    printf '%s/%s%s\n' "${abs_dir%/}" "$(basename "$prefix")" "${suffix:+/$suffix}"
  else
    printf '%s\n' "$raw"
  fi
}

RESOLVED_TARGET=$(resolve_path "$TARGET_PATH")

ALLOWED=false
while IFS= read -r root; do
  [ -z "$root" ] && continue
  RESOLVED_ROOT=$(resolve_path "$root")
  if [ "$RESOLVED_TARGET" = "$RESOLVED_ROOT" ] || [[ "$RESOLVED_TARGET" == "$RESOLVED_ROOT/"* ]]; then
    ALLOWED=true
    break
  fi
done < <(printf '%s' "$INPUT" | /usr/bin/jq -r '(.workspacePaths // [])[], (.artifactDirectoryPath // empty)' 2>/dev/null || true)

if [ "$ALLOWED" != "true" ]; then
  /usr/bin/jq -n --arg path "$TARGET_PATH" '{
    decision: "deny",
    reason: ("Blocked write outside active workspace or artifact directory (file-guard hook): " + $path)
  }'
  exit 0
fi

# Enforce <= 12,000-byte ceiling on .agents/AGENTS.md and .agents/rules/*.md
if [[ "$RESOLVED_TARGET" == *"/.agents/AGENTS.md" ]] || [[ "$RESOLVED_TARGET" == *"/.agents/rules/"*.md ]]; then
  MAX_BYTES=12000
  FINAL_BYTES=0

  if [ "$TOOL_NAME" = "write_file" ]; then
    IS_APPEND=$(printf '%s' "$INPUT" | /usr/bin/jq -r '.toolCall.args.Append // false' 2>/dev/null || true)
    CONTENT_BYTES=$(printf '%s' "$INPUT" | /usr/bin/jq -j '.toolCall.args.Content // ""' | LC_ALL=C wc -c | tr -d ' ')
    if [ "$IS_APPEND" = "true" ] && [ -f "$RESOLVED_TARGET" ]; then
      EXISTING_BYTES=$(LC_ALL=C wc -c < "$RESOLVED_TARGET" | tr -d ' ')
      FINAL_BYTES=$((EXISTING_BYTES + CONTENT_BYTES))
    else
      FINAL_BYTES=$CONTENT_BYTES
    fi
  elif [ "$TOOL_NAME" = "edit_file" ] && [ -f "$RESOLVED_TARGET" ]; then
    EXISTING_BYTES=$(LC_ALL=C wc -c < "$RESOLVED_TARGET" | tr -d ' ')
    TARGET_BYTES=$(printf '%s' "$INPUT" | /usr/bin/jq -j '.toolCall.args.Target // ""' | LC_ALL=C wc -c | tr -d ' ')
    REPL_BYTES=$(printf '%s' "$INPUT" | /usr/bin/jq -j '.toolCall.args.Replacement // ""' | LC_ALL=C wc -c | tr -d ' ')
    FINAL_BYTES=$((EXISTING_BYTES - TARGET_BYTES + REPL_BYTES))
  fi

  if [ "$FINAL_BYTES" -gt "$MAX_BYTES" ]; then
    /usr/bin/jq -n --arg path "$TARGET_PATH" --argjson bytes "$FINAL_BYTES" '{
      decision: "deny",
      reason: ("Blocked by file-guard hook: " + $path + " would be " + ($bytes | tostring) + " bytes (ceiling is 12,000 bytes).")
    }'
    exit 0
  fi
fi

printf '{"decision":"allow"}\n'
