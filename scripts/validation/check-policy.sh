#!/usr/bin/env bash
# Verifies that the controls living in .claude/settings.json are actually present, and that the
# .claude/ adapter layer contains no rules of its own. POSIX counterpart of check-policy.ps1.
#
# 1. Permission controls. Immutable-archive, secret-file, and key-material protection moved out of
#    a hook into deny rules because the harness enforces those with zero process startup. A control
#    that moves out of a tested hook must not become an untested one.
#
# 2. Adapter discipline. .claude/ is an adapter, not a home for rules -- the load-bearing constraint
#    recorded in the project decision log. Without this
#    check that constraint is documentation only.
#
# Exit 0 when both hold, 1 otherwise.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$REPO_ROOT/scripts/lib/blueprint-manifest.json"

[ -f "$MANIFEST" ] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }

# Capability, not presence: on Windows/Git Bash a Microsoft Store python3 stub sits on PATH and
# cannot run anything, so probe with a real parse -- and try python before giving up. Probed only
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

jq_or_py() {   # jq_or_py <jq-filter> <python-expression-over-d>
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1" "$MANIFEST"
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c "
import json,sys
d = json.load(open(sys.argv[1]))
$2
" "$MANIFEST" | tr -d '\r'
  else
    echo "check-policy.sh requires jq or a working python3/python." >&2
    exit 1
  fi
}

SETTINGS_REL="$(jq_or_py '.policy.settingsFile' 'print(d["policy"]["settingsFile"])')"

# jq_or_py runs inside a command substitution, so its `exit 1` ends that subshell only. This check
# fails closed either way, but it would blame a missing settings file for an unreadable manifest.
# Name the real cause: a wrong diagnosis costs more than the failure it reports.
if [ -z "$SETTINGS_REL" ]; then
  echo "Cannot read blueprint manifest. Install jq or python3." >&2
  echo "  manifest : $MANIFEST" >&2
  echo "  jq       : $(command -v jq || echo MISSING)" >&2
  echo "  python3  : $(command -v python3 || echo MISSING)" >&2
  exit 1
fi

SETTINGS="$REPO_ROOT/$SETTINGS_REL"

failures=()
ok=0

# --- 1. Permission and hook controls ----------------------------------------------------------

if [ ! -f "$SETTINGS" ]; then
  failures+=("Settings file not found: $SETTINGS_REL")
else
  settings_has() {   # settings_has <permissions-key> <rule>
    if command -v jq >/dev/null 2>&1; then
      jq -e --arg k "$1" --arg r "$2" '(.permissions[$k] // []) | index($r) != null' "$SETTINGS" >/dev/null 2>&1
    else
      [ -n "$JSON_PY" ] || return 1
      "$JSON_PY" -c '
import json,sys
s = json.load(open(sys.argv[1]))
sys.exit(0 if sys.argv[3] in s.get("permissions", {}).get(sys.argv[2], []) else 1)
' "$SETTINGS" "$1" "$2" >/dev/null 2>&1
    fi
  }

  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    if settings_has deny "$rule"; then ok=$((ok + 1)); else failures+=("Missing deny rule: $rule"); fi
  done < <(jq_or_py '.policy.requiredDeny[]' 'print("\n".join(d["policy"]["requiredDeny"]))')

  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    if settings_has ask "$rule"; then ok=$((ok + 1)); else failures+=("Missing ask rule: $rule"); fi
  done < <(jq_or_py '.policy.requiredAsk[]' 'print("\n".join(d["policy"]["requiredAsk"]))')

  while IFS= read -r event; do
    [ -z "$event" ] && continue
    if grep -q "\"$event\"" "$SETTINGS"; then ok=$((ok + 1)); else failures+=("Missing hook event: $event"); fi
  done < <(jq_or_py '.policy.requiredHooks[]' 'print("\n".join(d["policy"]["requiredHooks"]))')

  # An event being declared is not the same as a guard being wired: a settings file can list
  # PreToolUse and reference nothing. Assert each hook script by name.
  while IFS= read -r script; do
    [ -z "$script" ] && continue
    if grep -q -- "$script" "$SETTINGS"; then
      ok=$((ok + 1))
    else
      failures+=("Hook script not wired in $SETTINGS_REL: $script")
    fi
  done < <(jq_or_py '.policy.requiredHookScripts[]?' 'print("\n".join(d["policy"].get("requiredHookScripts", [])))')
fi

# --- 1b. Thin entrypoints ----------------------------------------------------------------------
# CLAUDE.md and AGENTS.md are the only files an agent is guaranteed to read, which makes them the
# most tempting place to restate a rule "for salience" and the least visible place for that copy to
# drift. It already happened once, undetected for two versions.

EP_MAX="$(jq_or_py '.policy.entrypoints.maxLines // empty' 'print(d["policy"].get("entrypoints", {}).get("maxLines", ""))')"
EP_REF="$(jq_or_py '.policy.entrypoints.mustReference // empty' 'print(d["policy"].get("entrypoints", {}).get("mustReference", ""))')"

if [ -n "$EP_MAX" ] && [ -n "$EP_REF" ]; then
  mapfile -t EP_FILES    < <(jq_or_py '.policy.entrypoints.files[]?' 'print("\n".join(d["policy"]["entrypoints"]["files"]))')
  mapfile -t EP_HEADINGS < <(jq_or_py '.policy.entrypoints.forbiddenHeadings[]?' 'print("\n".join(d["policy"]["entrypoints"]["forbiddenHeadings"]))')
  mapfile -t EP_PATTERNS < <(jq_or_py '.policy.entrypoints.forbiddenPatterns[]?' 'print("\n".join(d["policy"]["entrypoints"]["forbiddenPatterns"]))')

  for name in ${EP_FILES[@]+"${EP_FILES[@]}"}; do
    file="$REPO_ROOT/$name"
    if [ ! -f "$file" ]; then
      failures+=("Entrypoint not found: $name")
      continue
    fi

    count="$(grep -c '' "$file" 2>/dev/null || echo 0)"
    if [ "$count" -gt "$EP_MAX" ]; then
      failures+=("Entrypoint too long: $name has $count lines, limit $EP_MAX. Move the content into .ai/ and link to it.")
    else
      ok=$((ok + 1))
    fi

    if grep -qF -- "$EP_REF" "$file"; then
      ok=$((ok + 1))
    else
      failures+=("Entrypoint does not reference $EP_REF: $name")
    fi

    for heading in ${EP_HEADINGS[@]+"${EP_HEADINGS[@]}"}; do
      if grep -qxF -- "$heading" "$file"; then
        failures+=("Entrypoint carries a rules section: $name has '$heading'. That subject is owned by .ai/contract/ or .ai/rules/.")
      fi
    done
    ok=$((ok + 1))

    for pattern in ${EP_PATTERNS[@]+"${EP_PATTERNS[@]}"}; do
      hits="$(grep -cE -- "$pattern" "$file" 2>/dev/null || true)"
      if [ "${hits:-0}" -gt 0 ]; then
        failures+=("Entrypoint restates contract rules: $name matches /$pattern/ on $hits line(s). Link to .ai/contract/core.md instead of copying it.")
      fi
    done
    ok=$((ok + 1))
  done
fi

# --- 2. Adapter discipline ---------------------------------------------------------------------

REFERENCE="$(jq_or_py '.policy.adapter.mustReference' 'print(d["policy"]["adapter"]["mustReference"])')"
EXEMPT="$(jq_or_py '.policy.adapter.exempt | join(" ")' 'print(" ".join(d["policy"]["adapter"]["exempt"]))')"

while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  if [ ! -d "$REPO_ROOT/$dir" ]; then
    failures+=("Adapter directory not found: $dir")
    continue
  fi
  while IFS= read -r -d '' file; do
    rel="${file#"$REPO_ROOT"/}"
    case " $EXEMPT " in *" $rel "*) continue ;; esac
    if grep -qF -- "$REFERENCE" "$file"; then
      ok=$((ok + 1))
    else
      failures+=("Adapter file does not reference '$REFERENCE' (a rule may have been written here instead of in .ai/): $rel")
    fi
  done < <(find "$REPO_ROOT/$dir" -type f -name '*.md' -print0)
done < <(jq_or_py '.policy.adapter.directories[]' 'print("\n".join(d["policy"]["adapter"]["directories"]))')

# --- 3. Adapter thinness ------------------------------------------------------------------------
#
# Referencing .ai/ is necessary but not sufficient. An adapter can cite its source and restate it
# in different words -- which is what happened before v1.2.0, at up to 2.1x the size of the file
# it pointed at, with zero literal duplicate lines so no diff could show it.

# Rules are grouped per surface: a role adapter needs only a pointer, while a slash command
# legitimately carries the concrete invocations for two shells. One limit for both would be wrong.
# Each group is emitted as: name <TAB> maxLines <TAB> dirs(space) <TAB> headings(newline-escaped)

thin_groups="$(
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.policy.adapter.thin // []) | .[] | [.name, (.maxLines|tostring), (.directories|join(" ")), (.forbiddenHeadings|join("|"))] | @tsv' "$MANIFEST"
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c '
import json,sys
for g in json.load(open(sys.argv[1]))["policy"]["adapter"].get("thin", []):
    print("\t".join([g["name"], str(g["maxLines"]), " ".join(g["directories"]), "|".join(g["forbiddenHeadings"])]))
' "$MANIFEST" 2>/dev/null | tr -d '\r'
  fi
)"

while IFS=$'\t' read -r gname gmax gdirs gheads; do
  [ -z "$gname" ] && continue
  for dir in $gdirs; do
    [ -d "$REPO_ROOT/$dir" ] || continue
    while IFS= read -r -d '' file; do
      rel="${file#"$REPO_ROOT"/}"
      case " $EXEMPT " in *" $rel "*) continue ;; esac

      lines="$(grep -c '' "$file" 2>/dev/null || echo 0)"
      if [ "$lines" -gt "$gmax" ]; then
        failures+=("Adapter is too long ($lines lines, limit $gmax for $gname) -- move the content to .ai/ and point at it: $rel")
      else
        ok=$((ok + 1))
      fi

      old_ifs="$IFS"; IFS='|'
      for heading in $gheads; do
        [ -z "$heading" ] && continue
        if grep -qxF -- "$heading" "$file"; then
          failures+=("Adapter carries an operational section '$heading' -- that belongs in .ai/, not here: $rel")
        fi
      done
      IFS="$old_ifs"
    done < <(find "$REPO_ROOT/$dir" -type f -name '*.md' -print0)
  done
done <<< "$thin_groups"

# --- 3b. Source/adapter pairing -----------------------------------------------------------------
#
# An adapter with no source in .ai/ is a second knowledge source by definition. A source with no
# adapter is a role Claude Code cannot dispatch. Both directions are failures.

pairs="$(
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.policy.adapter.pairing // []) | .[] | [.name, .source, .adapter, (.exempt|join(" "))] | @tsv' "$MANIFEST"
  elif [ -n "$JSON_PY" ]; then
    "$JSON_PY" -c '
import json,sys
for p in json.load(open(sys.argv[1]))["policy"]["adapter"].get("pairing", []):
    print("\t".join([p["name"], p["source"], p["adapter"], " ".join(p.get("exempt", []))]))
' "$MANIFEST" 2>/dev/null | tr -d '\r'
  fi
)"

while IFS=$'\t' read -r pname psrc padp pexempt; do
  [ -z "$pname" ] && continue
  [ -d "$REPO_ROOT/$psrc" ] || continue
  [ -d "$REPO_ROOT/$padp" ] || continue

  list_names() {
    find "$REPO_ROOT/$1" -maxdepth 1 -type f -name '*.md' -printf '%f\n' 2>/dev/null | sort
  }

  for n in $(list_names "$psrc"); do
    case " $pexempt " in *" $n "*) continue ;; esac
    if [ -f "$REPO_ROOT/$padp/$n" ]; then
      ok=$((ok + 1))
    else
      failures+=("Role has no Claude adapter, so it cannot be dispatched: $psrc/$n has no $padp/$n")
    fi
  done

  for n in $(list_names "$padp"); do
    case " $pexempt " in *" $n "*) continue ;; esac
    if [ ! -f "$REPO_ROOT/$psrc/$n" ]; then
      failures+=("Adapter has no source, which makes it a second knowledge source: $padp/$n has no $psrc/$n")
    fi
  done
done <<< "$pairs"

# --- 4. Source-of-truth discipline --------------------------------------------------------------
#
# docs/ owns project facts; .ai/context/ summarizes and links. Deliberately dumb: it checks that
# the pointer is present and that a known-duplicated heading has not come back.

SOT_REF="$(jq_or_py '.sourceOfTruth.summaries.mustReference // empty' 'print(d.get("sourceOfTruth",{}).get("summaries",{}).get("mustReference",""))')"

if [ -n "$SOT_REF" ]; then
  mapfile -t SOT_FILES < <(jq_or_py '.sourceOfTruth.summaries.files[]?' 'print("\n".join(d.get("sourceOfTruth",{}).get("summaries",{}).get("files",[])))')
  mapfile -t SOT_HEADS < <(jq_or_py '.sourceOfTruth.summaries.forbiddenHeadings[]?' 'print("\n".join(d.get("sourceOfTruth",{}).get("summaries",{}).get("forbiddenHeadings",[])))')

  for rel in ${SOT_FILES[@]+"${SOT_FILES[@]}"}; do
    [ -z "$rel" ] && continue
    file="$REPO_ROOT/$rel"
    if [ ! -f "$file" ]; then
      failures+=("Context summary is missing: $rel")
      continue
    fi

    if grep -qF -- "$SOT_REF" "$file"; then
      ok=$((ok + 1))
    else
      failures+=("Context summary does not point at '$SOT_REF' -- it may have become a source of truth instead of a summary: $rel")
    fi

    for heading in ${SOT_HEADS[@]+"${SOT_HEADS[@]}"}; do
      [ -z "$heading" ] && continue
      if grep -qE "^#{1,6}[[:space:]]+${heading}[[:space:]]*$" "$file"; then
        failures+=("Context summary carries a section '$heading' that docs/ owns -- summarize and link instead: $rel")
      fi
    done
  done
fi

# --- 4b. Profile integrity ----------------------------------------------------------------------
#
# A profile that names a role which does not exist is a lie. A profile that never points at docs/
# has started to become a source of truth instead of a selector. Roles are read from frontmatter.

PROF_DIR="$(jq_or_py '.sourceOfTruth.profiles.directory // empty' 'print(d.get("sourceOfTruth",{}).get("profiles",{}).get("directory",""))')"

if [ -n "$PROF_DIR" ] && [ -d "$REPO_ROOT/$PROF_DIR" ]; then
  ROLE_DIR="$(jq_or_py '.sourceOfTruth.profiles.roleDirectory' 'print(d["sourceOfTruth"]["profiles"]["roleDirectory"])')"
  PROF_REF="$(jq_or_py '.sourceOfTruth.profiles.mustReference' 'print(d["sourceOfTruth"]["profiles"]["mustReference"])')"
  PROF_EXEMPT="$(jq_or_py '.sourceOfTruth.profiles.exempt | join(" ")' 'print(" ".join(d["sourceOfTruth"]["profiles"]["exempt"]))')"
  PROF_KEYS="$(jq_or_py '.sourceOfTruth.profiles.roleKeys | join(" ")' 'print(" ".join(d["sourceOfTruth"]["profiles"]["roleKeys"]))')"

  known_roles=" $(find "$REPO_ROOT/$ROLE_DIR" -maxdepth 1 -type f -name '*.md' -printf '%f\n' 2>/dev/null \
                  | grep -v '^README\.md$' | sed 's/\.md$//' | tr '\n' ' ') "

  while IFS= read -r -d '' file; do
    base="$(basename "$file")"
    case " $PROF_EXEMPT " in *" $base "*) continue ;; esac
    rel="${file#"$REPO_ROOT"/}"

    if grep -qF -- "$PROF_REF" "$file"; then
      ok=$((ok + 1))
    else
      failures+=("Profile never points at '$PROF_REF' -- it may be becoming a source of truth instead of a selector: $rel")
    fi

    named=0
    for key in $PROF_KEYS; do
      line="$(grep -m1 -E "^[[:space:]]*${key}[[:space:]]*:" "$file" 2>/dev/null || true)"
      [ -z "$line" ] && continue
      roles="$(printf '%s' "$line" | sed -e 's/.*\[//' -e 's/\].*//' -e 's/,/ /g')"
      for role in $roles; do
        [ -z "$role" ] && continue
        named=$((named + 1))
        case "$known_roles" in
          *" $role "*) ok=$((ok + 1)) ;;
          *) failures+=("Profile names a role that does not exist in $ROLE_DIR/: '$role' in $rel") ;;
        esac
      done
    done
    [ "$named" -eq 0 ] && failures+=("Profile declares no roles in frontmatter ($PROF_KEYS): $rel")
  done < <(find "$REPO_ROOT/$PROF_DIR" -maxdepth 1 -type f -name '*.md' -print0)
fi

# --- 5. Open-questions register -----------------------------------------------------------------
#
# An operational file may mention an assumption or an open question, but it must send the reader
# to the single register in the same file.

OQ_REGISTER="$(jq_or_py '.sourceOfTruth.openQuestions.register // empty' 'print(d.get("sourceOfTruth",{}).get("openQuestions",{}).get("register",""))')"

if [ -n "$OQ_REGISTER" ]; then
  OQ_MARKERS="$(jq_or_py '.sourceOfTruth.openQuestions.markers | join("|")' 'print("|".join(d["sourceOfTruth"]["openQuestions"]["markers"]))')"
  OQ_EXEMPT="$(jq_or_py '.sourceOfTruth.openQuestions.exempt | join(" ")' 'print(" ".join(d["sourceOfTruth"]["openQuestions"]["exempt"]))')"
  mapfile -t OQ_DIRS < <(jq_or_py '.sourceOfTruth.openQuestions.scanDirectories[]?' 'print("\n".join(d["sourceOfTruth"]["openQuestions"]["scanDirectories"]))')

  for dir in ${OQ_DIRS[@]+"${OQ_DIRS[@]}"}; do
    [ -z "$dir" ] && continue
    [ -d "$REPO_ROOT/$dir" ] || continue
    while IFS= read -r -d '' file; do
      rel="${file#"$REPO_ROOT"/}"
      case " $OQ_EXEMPT " in *" $rel "*) continue ;; esac

      grep -qiE -- "$OQ_MARKERS" "$file" || continue

      if grep -qF -- "$OQ_REGISTER" "$file"; then
        ok=$((ok + 1))
      else
        failures+=("File records an assumption or open question but never points at $OQ_REGISTER: $rel")
      fi
    done < <(find "$REPO_ROOT/$dir" -type f -name '*.md' -print0)
  done
fi

# --- 6. Source-only classification ---------------------------------------------------------------
#
# A source-only path is release tooling: carried by this repository, never copied into a project.
# It lives inside a portable directory because the discovery gate permits writes nowhere else, so
# nothing about its location says "do not distribute" -- only this declaration does. Verify the
# declaration is not contradicted elsewhere in the manifest, and that it points at something real.
# A classification that names a path nobody created protects an empty space.

SO_ROLE=''
[ -f "$REPO_ROOT/blueprint.version" ] &&
  SO_ROLE="$(grep -m1 '"role"' "$REPO_ROOT/blueprint.version" | sed 's/.*: *"//; s/".*//')"
mapfile -t SRC_ONLY < <(jq_or_py '.distribution.sourceOnly[]?' 'print("\n".join(d.get("distribution",{}).get("sourceOnly",[])))')
mapfile -t SO_PORTFILES < <(jq_or_py '.distribution.portableFiles[]?' 'print("\n".join(d.get("distribution",{}).get("portableFiles",[])))')
mapfile -t SO_SEEDFILES < <(jq_or_py '.distribution.seedFiles[]?' 'print("\n".join(d.get("distribution",{}).get("seedFiles",[])))')

for so in ${SRC_ONLY[@]+"${SRC_ONLY[@]}"}; do
  [ -z "$so" ] && continue
  so_bad=0
  # The assertion is role-dependent, and getting that wrong broke every adopter of v1.15.0+:
  # a source-only path exists HERE and must be ABSENT there, so requiring existence everywhere
  # reported the classification working as if it had failed. Both directions are now checked,
  # which makes the adopted side a leak detector rather than a false alarm.
  if [ "$SO_ROLE" = 'source' ]; then
    [ -e "$REPO_ROOT/$so" ] || { failures+=("Source-only path does not exist: $so"); so_bad=1; }
  else
    [ -e "$REPO_ROOT/$so" ] && { failures+=("Source-only path reached this project: $so"); so_bad=1; }
  fi
  for p in ${SO_PORTFILES[@]+"${SO_PORTFILES[@]}"}; do
    case "$p" in "$so"|"$so"/*) failures+=("Source-only path is also a portable file: $p"); so_bad=1 ;; esac
  done
  for p in ${SO_SEEDFILES[@]+"${SO_SEEDFILES[@]}"}; do
    case "$p" in "$so"|"$so"/*) failures+=("Source-only path is also a seed file: $p"); so_bad=1 ;; esac
  done
  [ "$so_bad" -eq 0 ] && ok=$((ok + 1))
done

# --- Report ------------------------------------------------------------------------------------

if [ "${#failures[@]}" -gt 0 ]; then
  printf 'Policy check FAILED  (%s ok, %s failed)\n\n' "$ok" "${#failures[@]}"
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  echo ''
  echo 'A missing deny rule means a control that used to be enforced no longer is.'
  echo 'An adapter file with no .ai/ reference means the single-source-of-truth design has'
  echo 'started to drift -- write the rule in .ai/ and point to it from here.'
  exit 1
fi

printf 'Policy check passed  (%s control(s) verified: permissions, hooks, adapter discipline, source-of-truth summaries, open-questions register, source-only classification)\n' "$ok"
exit 0
