#!/usr/bin/env bash
# Shared JSON field extraction for blueprint hooks.
#
# Usage:  value="$(json_field "$payload" tool_input command)"
#
# Uses jq when available, then a python that actually works, then a best-effort grep fallback.
# Every path fails open (empty result) rather than blocking on a parse error:
# hooks are a safety net, not a security boundary.

# Capability, not presence: on Windows/Git Bash a Microsoft Store python3 stub sits on PATH and
# cannot run anything. The old presence test entered the python3 branch and returned its empty
# output, which made the grep fallback below dead code exactly where it was needed. Probed only
# when jq is absent, so the common path pays nothing.
JSON_PY=''
if ! command -v jq >/dev/null 2>&1; then
  for _py in python3 python; do
    if command -v "$_py" >/dev/null 2>&1 && "$_py" -c 'import json' >/dev/null 2>&1; then
      JSON_PY="$_py"
      break
    fi
  done
fi

json_field() {
  local payload="$1" parent="$2" key="$3"

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r --arg p "$parent" --arg k "$key" \
      '(.[$p][$k] // "")' 2>/dev/null
    return 0
  fi

  if [ -n "$JSON_PY" ]; then
    printf '%s' "$payload" | "$JSON_PY" -c '
import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get(sys.argv[1], {}).get(sys.argv[2], "") or "")
except Exception:
    print("")
' "$parent" "$key" 2>/dev/null | tr -d '\r'
    return 0
  fi

  # Fallback: extract "key": "value" with basic escape handling.
  printf '%s' "$payload" \
    | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"\(\\\\.\|[^\"\\\\]\)*\"" \
    | head -n 1 \
    | sed -e "s/^\"${key}\"[[:space:]]*:[[:space:]]*\"//" -e 's/"$//' \
    | sed -e 's/\\n/\n/g' -e 's/\\t/\t/g' -e 's/\\"/"/g' -e 's/\\\\/\\/g'
}
