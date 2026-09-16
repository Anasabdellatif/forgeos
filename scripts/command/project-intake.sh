#!/usr/bin/env bash
# Project intake and forecast -- what kind of project this is, how ready it is, and which prompt
# family the next session belongs to. POSIX counterpart of project-intake.ps1. M-26 slice 1.
#
# READ-ONLY, AND CHEAP BY CONSTRUCTION. The report is built from names, sizes, and presence. It opens
# exactly three small files -- blueprint.version for the role, .ai/context/project.md for a TBD
# marker, .ai/context/governance.json for codeAuthorized -- and never a governing document: all it
# learns about a specification is that it exists and how large it is. The directory scan is bounded:
# depth 3, dependency, build, and tooling directories pruned, at most 5000 directories. It writes
# nothing, authorizes nothing, opens no governance window, and reaches no network.
#
# THE SIGNAL NAMES ARE DETECTION DATA, NOT REQUIREMENTS. The core names no language or framework a
# project must use; a project matching none of the names below is still classified, as discovery or
# reconstruction. Every figure is an estimate: the report names a token RISK and never claims a
# saving.
#
# Usage: project-intake.sh [--json]
# Exit 0 reported; 1 usage error.

set -uo pipefail
export LC_ALL=C
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    *) echo "Unknown option: $1" >&2; echo 'Usage: project-intake.sh [--json]' >&2; exit 1 ;;
  esac
  shift
done

jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\037'; }
jstr() { printf '"%s"' "$(jesc "$1")"; }
jbool() { if [ "$1" -eq 1 ]; then printf 'true'; else printf 'false'; fi; }
# A newline-separated list as a JSON array of at most $2 entries.
jarr() {
  local list="$1" cap="$2" n=0 x
  printf '['
  while IFS= read -r x; do
    [ -n "$x" ] || continue
    n=$((n + 1)); [ "$n" -le "$cap" ] || break
    [ "$n" -gt 1 ] && printf ','
    jstr "$x"
  done <<LISTEOF
$list
LISTEOF
  printf ']'
}
count() { if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | grep -c .; fi; }
add() { if [ -z "$1" ]; then printf '%s' "$2"; else printf '%s\n%s' "$1" "$2"; fi; }
sorted() { [ -n "$1" ] && printf '%s\n' "$1" | sort | grep -v '^$'; return 0; }
# The first $2 entries, comma-separated, and how many were left out. Lists are capped so the report
# stays short enough to paste into the next session.
shown() {
  local list="$1" cap="$2" total
  total="$(count "$list")"
  if [ "$total" -eq 0 ]; then printf 'none'; return 0; fi
  printf '%s\n' "$list" | awk -v c="$cap" 'NF && ++n <= c { printf "%s%s", (n > 1 ? ", " : ""), $0 }'
  [ "$total" -gt "$cap" ] && printf '  (+%d more)' $((total - cap))
  return 0
}
has_file_under() { [ -d "$1" ] && [ -n "$(find "$1" -type f -print -quit 2>/dev/null)" ]; }
row() { printf '  %-13s %s\n' "$1" "$2"; }
frow() { printf '  %-15s %-8s %s\n' "$1" "$2" "$3"; }

# --- evidence -------------------------------------------------------------------------------------
role='unknown'
if [ -f "$REPO_ROOT/blueprint.version" ]; then
  r="$(grep -m1 '"role"' "$REPO_ROOT/blueprint.version" | sed 's/.*: *"//; s/".*//')"
  [ -n "$r" ] && role="$r"
fi

# Governing document directories: one logical place in up to two spellings, the first that holds a
# file reported, so a case-insensitive filesystem answers once and both shells print the same name.
governing=''
for pair in 'docs/Client:docs/client' 'docs/Developer:docs/developer' 'docs/data:docs/Data' \
            'docs/specifications:' 'docs/specs:'; do
  for cand in "${pair%%:*}" "${pair#*:}"; do
    [ -n "$cand" ] || continue
    if has_file_under "$REPO_ROOT/$cand"; then governing="$(add "$governing" "$cand")"; break; fi
  done
done
gov_n="$(count "$governing")"
data_docs=0
printf '%s\n' "$governing" | grep -qi '^docs/data$' && data_docs=1

PRODUCT='.ai/product'
intel_n=0; intel_missing=''
for m in authority-map source-index project-concept module-map requirement-matrix implementation-roadmap open-decisions; do
  if [ -s "$REPO_ROOT/$PRODUCT/$m.md" ]; then intel_n=$((intel_n + 1)); else intel_missing="$(add "$intel_missing" "$m")"; fi
done
disc_n=0; disc_missing=''
for m in project-brief stakeholders module-map-draft questions assumptions phase-roadmap; do
  if [ -s "$REPO_ROOT/$PRODUCT/$m.md" ]; then disc_n=$((disc_n + 1)); else disc_missing="$(add "$disc_missing" "$m")"; fi
done
authority=0; [ -s "$REPO_ROOT/$PRODUCT/authority-map.md" ] && authority=1
module_map=0
if [ -s "$REPO_ROOT/$PRODUCT/module-map.md" ] || [ -s "$REPO_ROOT/$PRODUCT/module-map-draft.md" ]; then module_map=1; fi
G=0; if [ "$gov_n" -gt 0 ] || [ "$authority" -eq 1 ]; then G=1; fi

code=''
for f in package.json composer.json pyproject.toml requirements.txt go.mod Cargo.toml pom.xml build.gradle Gemfile mix.exs deno.json; do
  [ -f "$REPO_ROOT/$f" ] && code="$(add "$code" "$f")"
done
for d in src app apps lib packages server backend frontend api services; do
  [ -d "$REPO_ROOT/$d" ] && code="$(add "$code" "$d")"
done
code="$(sorted "$code")"; code_n="$(count "$code")"

web=''; web_cfg=0; pages=0; public=0
for e in "$REPO_ROOT"/*; do
  [ -f "$e" ] || continue
  b="${e##*/}"
  case "$b" in
    astro.config.*|next.config.*|nuxt.config.*|vite.config.*|svelte.config.*|gatsby-config.*|docusaurus.config.*|hugo.toml)
      web="$(add "$web" "$b")"; web_cfg=$((web_cfg + 1)) ;;
  esac
done
for d in pages src/pages; do
  if [ -d "$REPO_ROOT/$d" ]; then web="$(add "$web" "$d")"; pages=1; fi
done
if [ -d "$REPO_ROOT/public" ]; then web="$(add "$web" 'public')"; public=1; fi
web="$(sorted "$web")"; web_n="$(count "$web")"
W=0; if [ "$web_cfg" -gt 0 ] || { [ "$pages" -eq 1 ] && [ "$public" -eq 1 ]; }; then W=1; fi

# The one directory walk: depth 3, pruned, capped. Names only.
dirs="$(find "$REPO_ROOT" -mindepth 1 -maxdepth 3 -type d \( -name .git -o -name node_modules \
  -o -name vendor -o -name dist -o -name build -o -name .next -o -name .nuxt -o -name .venv \
  -o -name venv -o -name target -o -name .ai -o -name .claude -o -name .github -o -name docs \
  -o -name scripts -o -name templates \) -prune -o -type d -print 2>/dev/null \
  | head -n 5000 | cut -c$((${#REPO_ROOT} + 2))-)"
ent=''; ent_names=''; tests=0; migrations=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  b="${rel##*/}"; b="${b,,}"
  case "$b" in
    migrations|permissions|roles|tenants|workers|queues|jobs|audit|ledger|billing|invoices|payments|modules)
      ent="$(add "$ent" "$rel")"; ent_names="$(add "$ent_names" "$b")"
      [ "$b" = 'migrations' ] && migrations=1 ;;
    test|tests|__tests__|e2e) tests=1 ;;
  esac
done <<DIRSEOF
$dirs
DIRSEOF
ent="$(sorted "$ent")"
ent_n=0; [ -n "$ent_names" ] && ent_n="$(printf '%s\n' "$ent_names" | sort -u | grep -c .)"
E=0; [ "$ent_n" -ge 3 ] && E=1
has_code=0; if [ "$code_n" -gt 0 ] || [ "$W" -eq 1 ] || [ "$E" -eq 1 ]; then has_code=1; fi

ci=0
if has_file_under "$REPO_ROOT/.github/workflows" || [ -f "$REPO_ROOT/.gitlab-ci.yml" ] \
   || [ -f "$REPO_ROOT/azure-pipelines.yml" ] || [ -f "$REPO_ROOT/Jenkinsfile" ]; then ci=1; fi

pmd="$REPO_ROOT/.ai/context/project.md"
tbd=0; pmd_state='defined'
if [ ! -f "$pmd" ]; then tbd=1; pmd_state='absent'
elif grep -q 'TBD' "$pmd"; then tbd=1; pmd_state='TBD'; fi
gov_file=0; code_auth=0
if [ -f "$REPO_ROOT/.ai/context/governance.json" ]; then
  gov_file=1
  grep -Eq '"codeAuthorized"[[:space:]]*:[[:space:]]*true' "$REPO_ROOT/.ai/context/governance.json" && code_auth=1
fi
constraints=0; [ -f "$REPO_ROOT/.ai/context/constraints.md" ] && constraints=1
dec_n=0
if [ -d "$REPO_ROOT/.ai/memory/decisions" ]; then
  dec_n="$(find "$REPO_ROOT/.ai/memory/decisions" -mindepth 1 -maxdepth 1 -type f -name '*.md' ! -name README.md | grep -c .)"
fi

tok_bytes=0
for f in CLAUDE.md .ai/contract/core.md .ai/context/project.md .ai/context/constraints.md .ai/context/current-state.md; do
  [ -f "$REPO_ROOT/$f" ] && tok_bytes=$((tok_bytes + $(wc -c < "$REPO_ROOT/$f")))
done
tokens=$((tok_bytes / 4))
large=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  c="$(find "$REPO_ROOT/$d" -type f -size +200k -print 2>/dev/null | head -n 1000 | grep -c .)"
  large=$((large + c))
done <<GOVEOF
$governing
GOVEOF

# --- classification -------------------------------------------------------------------------------
if [ "$role" = 'source' ]; then mode='NOT_APPLICABLE'
elif [ "$G" -eq 1 ]; then mode='PROJECT_WITH_GOVERNING_DOCS'
elif [ "$has_code" -eq 1 ]; then
  if [ "$W" -eq 1 ] && [ "$E" -eq 0 ]; then mode='WEBSITE_PROJECT'
  elif [ "$E" -eq 1 ]; then mode='ENTERPRISE_SYSTEM'
  else mode='CODEBASE_RECONSTRUCTION_REQUIRED'; fi
else mode='PROJECT_DISCOVERY_REQUIRED'; fi

tags=''
if [ "$mode" != 'NOT_APPLICABLE' ]; then
  [ "$G" -eq 1 ] && tags="$(add "$tags" 'PROJECT_WITH_GOVERNING_DOCS')"
  { [ "$has_code" -eq 1 ] && [ "$G" -eq 0 ] && [ "$intel_n" -eq 0 ]; } && tags="$(add "$tags" 'CODEBASE_RECONSTRUCTION_REQUIRED')"
  [ "$W" -eq 1 ] && tags="$(add "$tags" 'WEBSITE_PROJECT')"
  [ "$E" -eq 1 ] && tags="$(add "$tags" 'ENTERPRISE_SYSTEM')"
  tags="$(printf '%s\n' "$tags" | grep -vx "$mode")"
fi

case "$mode" in
  NOT_APPLICABLE) support=2; evidence='blueprint.version' ;;
  PROJECT_WITH_GOVERNING_DOCS)
    support=$((gov_n + authority)); [ "$intel_n" -gt 0 ] && support=$((support + 1))
    evidence="$governing"; [ "$authority" -eq 1 ] && evidence="$(add "$evidence" "$PRODUCT/authority-map.md")" ;;
  WEBSITE_PROJECT) support="$web_n"; evidence="$web" ;;
  ENTERPRISE_SYSTEM) support=$((ent_n - 2)); evidence="$ent" ;;
  CODEBASE_RECONSTRUCTION_REQUIRED) support="$code_n"; evidence="$code" ;;
  *) support=$((1 + tbd)); evidence=''; [ -f "$pmd" ] && evidence='.ai/context/project.md' ;;
esac
if [ "$support" -ge 2 ]; then confidence='high'; elif [ "$support" -eq 1 ]; then confidence='medium'; else confidence='low'; fi
evidence_n="$(count "$evidence")"

# --- forecast -------------------------------------------------------------------------------------
yn() { if [ "$1" -eq 1 ]; then printf 'yes'; else printf 'no'; fi; }
if [ "$mode" = 'NOT_APPLICABLE' ]; then
  na='source blueprint: no product of its own'
  pt_s='n/a'; pt_r="$na"; ar_s='n/a'; ar_r="$na"; da_s='n/a'; da_r="$na"; go_s='n/a'; go_r="$na"; im_s='n/a'; im_r="$na"
else
  if [ "$G" -eq 1 ]; then
    if [ "$intel_n" -eq 7 ]; then pt_s='ready'; pt_r='governing documents mapped, 7 of 7'
    else pt_s='partial'; pt_r="governing documents present, $intel_n of 7 maps"; fi
  elif [ "$disc_n" -eq 6 ] && [ "$tbd" -eq 0 ]; then pt_s='ready'; pt_r='discovery records complete, 6 of 6'
  elif [ "$tbd" -eq 0 ] || [ "$disc_n" -gt 0 ]; then pt_s='partial'; pt_r="no governing documents, $disc_n of 6 discovery records"
  else pt_s='missing'; pt_r="no governing documents, project.md $pmd_state"; fi

  if [ "$module_map" -eq 1 ] && [ "$dec_n" -gt 0 ]; then ar_s='ready'; ar_r="module map and $dec_n decision record(s)"
  elif [ "$module_map" -eq 1 ] || [ "$dec_n" -gt 0 ]; then ar_s='partial'; ar_r="module map $(yn "$module_map"), $dec_n decision record(s)"
  else ar_s='missing'; ar_r='no module map, no decision record'; fi

  if [ "$data_docs" -eq 1 ] && [ "$migrations" -eq 1 ]; then da_s='ready'; da_r='data documents and migrations'
  elif [ "$data_docs" -eq 1 ]; then da_s='partial'; da_r='data documents, no migrations directory'
  elif [ "$migrations" -eq 1 ]; then da_s='partial'; da_r='migrations, no data documents'
  elif [ "$mode" = 'WEBSITE_PROJECT' ]; then da_s='n/a'; da_r='no data layer signalled'
  else da_s='missing'; da_r='no data documents, no migrations directory'; fi

  if [ "$gov_file" -eq 0 ]; then go_s='missing'; go_r='.ai/context/governance.json absent'
  elif [ "$tbd" -eq 1 ]; then go_s='partial'; go_r="gates present, project.md $pmd_state"
  elif [ "$constraints" -eq 0 ]; then go_s='partial'; go_r='gates present, constraints.md absent'
  else go_s='ready'; go_r='governance, constraints, and a defined project'; fi

  if [ "$tbd" -eq 1 ]; then im_s='blocked'; im_r="discovery gate: project.md $pmd_state"
  elif [ "$code_auth" -eq 0 ]; then im_s='blocked'; im_r='governance: codeAuthorized is not true'
  elif [ "$has_code" -eq 1 ] && [ "$ci" -eq 1 ] && [ "$tests" -eq 1 ]; then im_s='ready'; im_r='code, CI, and tests present'
  elif [ "$has_code" -eq 1 ]; then im_s='partial'; im_r="code present, CI $(yn "$ci"), tests $(yn "$tests")"
  else im_s='missing'; im_r='no application signal'; fi
fi

tk_l='low'
if [ "$tokens" -gt 5000 ] || { [ "$G" -eq 1 ] && [ "$intel_n" -eq 0 ] && [ "$large" -gt 0 ]; }; then tk_l='high'
elif [ "$tokens" -gt 4000 ] || { [ "$G" -eq 1 ] && [ "$intel_n" -lt 7 ]; } || [ "$large" -gt 0 ]; then tk_l='medium'; fi
tk_r="~$tokens always-loaded tokens (bytes/4), $large document(s) over 200 KB"
[ "$G" -eq 1 ] && [ "$intel_n" -lt 7 ] && tk_r="$tk_r, governing documents $intel_n of 7 mapped"

# --- next prompt family ---------------------------------------------------------------------------
if [ "$mode" = 'NOT_APPLICABLE' ]; then fam_key='none'; fam_label='none, the source blueprint has no product of its own'; fam_read=''
elif [ "$G" -eq 1 ] && [ "$intel_n" -lt 7 ]; then fam_key='extract-project-intelligence'; fam_label='extract project intelligence'; fam_read='.ai/workflows/ingest-project.md'
elif [ "$mode" = 'PROJECT_DISCOVERY_REQUIRED' ] && [ "$tbd" -eq 1 ]; then fam_key='run-discovery'; fam_label='run discovery'; fam_read='.ai/workflows/discovery.md'
elif [ "$mode" = 'CODEBASE_RECONSTRUCTION_REQUIRED' ]; then fam_key='reconstruct-from-codebase'; fam_label='reconstruct from codebase'; fam_read='.ai/skills/codebase-navigation.md'
elif [ "$mode" = 'WEBSITE_PROJECT' ]; then fam_key='website-path'; fam_label='website review/build/deploy path'; fam_read='.ai/contract/safety.md'
elif [ "$mode" = 'ENTERPRISE_SYSTEM' ]; then fam_key='enterprise-phasing'; fam_label='enterprise module/phasing path'; fam_read='.ai/contract/lifecycle.md'
elif [ "$im_s" = 'blocked' ]; then fam_key='blocked-owner-decision'; fam_label='blocked-owner-decision path'; fam_read='.ai/memory/open-questions.md'
else fam_key='safe-implementation'; fam_label='safe implementation path'; fam_read='.ai/workflows/start-task.md'; fi

if [ "$G" -eq 1 ]; then missing_maps="$intel_missing"; else missing_maps="$disc_missing"; fi

# --- output ---------------------------------------------------------------------------------------
if [ "$JSON" -eq 1 ]; then
  fr() { printf '{"status": %s, "reason": %s}' "$(jstr "$1")" "$(jstr "$2")"; }
  printf '{\n'
  printf '  "schema": "forgeos.project-intake/1",\n'
  printf '  "role": %s,\n' "$(jstr "$role")"
  printf '  "mode": %s,\n' "$(jstr "$mode")"
  printf '  "confidence": %s,\n' "$(jstr "$confidence")"
  printf '  "tags": %s,\n' "$(jarr "$tags" 5)"
  printf '  "evidence": {"total": %s, "paths": %s},\n' "$evidence_n" "$(jarr "$evidence" 5)"
  printf '  "governingDirectories": %s,\n' "$(jarr "$governing" 5)"
  printf '  "maps": {"directory": ".ai/product", "intelligence": {"present": %s, "total": 7, "missing": %s}, "discovery": {"present": %s, "total": 6, "missing": %s}},\n' \
    "$intel_n" "$(jarr "$intel_missing" 7)" "$disc_n" "$(jarr "$disc_missing" 6)"
  printf '  "signals": {"code": {"count": %s, "paths": %s}, "website": {"count": %s, "paths": %s}, "enterprise": {"count": %s, "paths": %s}, "ci": %s, "tests": %s},\n' \
    "$code_n" "$(jarr "$code" 5)" "$web_n" "$(jarr "$web" 5)" "$ent_n" "$(jarr "$ent" 5)" "$(jbool "$ci")" "$(jbool "$tests")"
  printf '  "forecast": {\n'
  printf '    "productTruth": %s,\n' "$(fr "$pt_s" "$pt_r")"
  printf '    "architecture": %s,\n' "$(fr "$ar_s" "$ar_r")"
  printf '    "data": %s,\n' "$(fr "$da_s" "$da_r")"
  printf '    "governance": %s,\n' "$(fr "$go_s" "$go_r")"
  printf '    "implementation": %s,\n' "$(fr "$im_s" "$im_r")"
  printf '    "tokenRisk": {"level": %s, "reason": %s, "alwaysLoadedTokens": %s, "largeDocuments": %s}\n' \
    "$(jstr "$tk_l")" "$(jstr "$tk_r")" "$tokens" "$large"
  printf '  },\n'
  if [ -n "$fam_read" ]; then read_json="$(jstr "$fam_read")"; else read_json='null'; fi
  printf '  "nextPromptFamily": {"key": %s, "label": %s, "readFirst": %s},\n' "$(jstr "$fam_key")" "$(jstr "$fam_label")" "$read_json"
  printf '  "safety": {"readOnly": true, "canModifyFiles": false, "canAuthorizeCode": false, "canOpenGovernanceWindow": false, "networkAccess": false}\n'
  printf '}\n'
  exit 0
fi

echo 'ForgeOS project intake  (read-only)'
row 'role' "$role"
row 'mode' "$mode  (confidence $confidence)"
row 'tags' "$(shown "$tags" 4)"
row 'evidence' "$(shown "$evidence" 3)"
row 'governing' "$(shown "$governing" 3)"
row 'maps' "intelligence $intel_n of 7, discovery $disc_n of 6"
if [ "$mode" != 'NOT_APPLICABLE' ] && [ -n "$missing_maps" ]; then
  row 'missing maps' "$(shown "$missing_maps" 3)  in .ai/product/"
fi
row 'code' "$code_n signal(s): $(shown "$code" 3)"
row 'website' "$web_n signal(s): $(shown "$web" 3)"
row 'enterprise' "$ent_n signal(s): $(shown "$ent" 3)"
echo 'Forecast'
frow 'product truth' "$pt_s" "$pt_r"
frow 'architecture' "$ar_s" "$ar_r"
frow 'data' "$da_s" "$da_r"
frow 'governance' "$go_s" "$go_r"
frow 'implementation' "$im_s" "$im_r"
frow 'token risk' "$tk_l" "$tk_r"
echo 'Next prompt family'
if [ -n "$fam_read" ]; then echo "  $fam_label  (read first: $fam_read)"; else echo "  $fam_label"; fi
echo 'Nothing was written, authorized, or opened. Token figures are estimates, not a claimed saving.'
exit 0
