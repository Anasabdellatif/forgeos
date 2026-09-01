#!/usr/bin/env bash
# Detects unexpected empty or whitespace-only source and documentation files.
# POSIX counterpart of check-empty-files.ps1.
#
# Exit 0 when nothing unexpected is found, 1 otherwise.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Extensions where a UTF-8 BOM is a defect rather than a cosmetic detail. Measured, not assumed:
#   .sh    -- a BOM before the shebang breaks execution outright, and `bash -n` passes it
#             silently, so the syntax gate cannot catch this class.
#   .json  -- python3 json.load raises "Unexpected UTF-8 BOM"; jq tolerates it, so a host
#             without jq fails while a host with it passes. That divergence broke check-all.sh.
#   .yml / .yaml -- precautionary; machine-parsed configuration.
# .md and .ps1 are deliberately excluded: a BOM there is harmless, and a check that fails on
# harmless input is a check that gets disabled.
BOM_SENSITIVE='\.(sh|json|ya?ml)$'
BOM_BYTES="$(printf '\xEF\xBB\xBF')"

empty=()
whitespace=()
withbom=()
scanned=0

while IFS= read -r -d '' file; do
  scanned=$((scanned + 1))
  rel="${file#"$REPO_ROOT"/}"
  if [ ! -s "$file" ]; then
    empty+=("$rel")
  elif [ "$(wc -c < "$file")" -le 512 ] && [ -z "$(tr -d '[:space:]' < "$file")" ]; then
    whitespace+=("$rel")
  fi

  # Read only the first three bytes. Never load or print the content.
  if printf '%s' "$rel" | grep -Eq -- "$BOM_SENSITIVE"; then
    if [ "$(LC_ALL=C head -c 3 "$file" 2>/dev/null)" = "$BOM_BYTES" ]; then
      withbom+=("$rel")
    fi
  fi
done < <(
  find "$REPO_ROOT" \
    \( -path '*/.git' -o -path '*/node_modules' -o -path '*/dist' -o -path '*/build' \
       -o -path '*/coverage' -o -path '*/.venv' -o -path '*/venv' -o -path '*/__pycache__' \
       -o -path '*/target' -o -path '*/.next' -o -path '*/.turbo' \) -prune -o \
    -type f \( -name '*.md' -o -name '*.ps1' -o -name '*.sh' -o -name '*.json' \
               -o -name '*.yml' -o -name '*.yaml' \) -print0
)

total=$(( ${#empty[@]} + ${#whitespace[@]} + ${#withbom[@]} ))

if [ "$total" -gt 0 ]; then
  if [ "${#empty[@]}" -gt 0 ]; then
    echo 'Empty files:'
    printf '  - %s\n' "${empty[@]}" | sort
  fi
  if [ "${#whitespace[@]}" -gt 0 ]; then
    echo 'Whitespace-only files:'
    printf '  - %s\n' "${whitespace[@]}" | sort
  fi
  if [ "${#withbom[@]}" -gt 0 ]; then
    echo 'Files starting with a UTF-8 BOM:'
    printf '  - %s\n' "${withbom[@]}" | sort
    echo ''
    echo 'A BOM before a shebang stops a shell script from running, and python3 refuses'
    echo 'to parse JSON that starts with one. Re-save each file as UTF-8 without BOM.'
  fi
  echo ''
  printf 'Empty-file check FAILED  (%s file(s))\n' "$total"
  echo 'A required file that exists but says nothing is worse than a missing one: it passes'
  echo 'the structure check while giving every future agent no information.'
  exit 1
fi

printf 'Empty-file check passed  (%s file(s) scanned, 0 empty, 0 with BOM)\n' "$scanned"
exit 0
