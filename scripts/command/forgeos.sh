#!/usr/bin/env bash
# The local ForgeOS command surface. POSIX counterpart of forgeos.ps1.
#
# A WRAPPER FOR THE PROJECT, AN ENGINE FOR ITSELF. `status` and `next` describe the PROJECT, so they
# route to project-status and add nothing: the reading, the schema and the safety flags all belong to
# that one command, and a second place that read the same files would be a second answer waiting to
# disagree. `doctor` and `version` describe the INSTALLATION, so they are implemented here -- neither
# duplicates the engine, and neither could route to a command that may itself be the missing piece.
#
# READ-ONLY EXCEPT ON TWO EXPLICIT PATHS. Every command here reads and nothing more, with two
# exceptions: `adopt --apply` and `update --apply`, which delegate to sync-blueprint's own writing
# path. Dry run is the default for both -- neither writes unasked -- and --force is never passed, so
# a file the project customized is skipped and reported rather than overwritten.
#
# adopt brings ForgeOS into a project that does not have it; update refreshes one that does, and
# refuses a target that has never adopted. Nothing here touches the network: the source is always
# this checkout, so there is no channel, no fetch and no version discovery.
#
# Usage: forgeos.sh <status|next|doctor|version|adopt|update> [--json]
# Exit 0 reported; 1 usage error or could not run; 2 is reserved by the house convention for a gate
# refusal and no command here can produce one.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
STATUS="$HERE/project-status.sh"

# One escaper for every JSON string this file emits. Two would eventually disagree.
jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\010\013-\037'; }
jstr() { printf '"%s"' "$(jesc "$1")"; }
jnul() { if [ -z "$1" ]; then printf 'null'; else jstr "$1"; fi; }

usage() {
  cat <<'USAGEEOF'
forgeos -- the local ForgeOS command surface

Usage:
  forgeos status  [--json]   where this project is, read from its own files
  forgeos next    [--json]   what the next safe thing to do is
  forgeos doctor  [--json]   whether this ForgeOS installation can run
  forgeos version [--json]   which ForgeOS this is, and where it sits
  forgeos adopt  --target <path> [--apply] [--json]
                             bring the portable blueprint into a project for the first time.
                             DRY RUN unless --apply is given.
  forgeos update --target <path> [--apply] [--json]
                             refresh a project that has ALREADY adopted. Refuses one that has not.
                             DRY RUN unless --apply is given.

Every command reads. The two exceptions are `adopt --apply` and `update --apply`, which delegate to
sync-blueprint to write; on their own both are dry runs. None authorizes code, opens a governance
window, reaches the network, or passes --force.

Exit codes: 0 reported - 1 usage error or could not run - 2 refused by a gate (never from here).
USAGEEOF
}

CMD="${1:-}"
JSON=0; APPLY=0; TARGET=''
shift 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --apply) APPLY=1 ;;
    --target) shift; TARGET="${1:-}" ;;
    --target=*) TARGET="${1#--target=}" ;;
    *) echo "Unknown option: $1" >&2; echo '' >&2; usage >&2; exit 1 ;;
  esac
  shift
done

# A writing flag accepted by a reading command is a bad surprise waiting to happen, so the options
# are checked against the command rather than merely parsed. Only adopt and update take --apply or
# --target; every other command refuses them outright.
if [ "$CMD" != 'adopt' ] && [ "$CMD" != 'update' ]; then
  if [ "$APPLY" -eq 1 ]; then
    echo "--apply is only valid for 'forgeos adopt' and 'forgeos update'." >&2; echo '' >&2; usage >&2; exit 1
  fi
  if [ -n "$TARGET" ]; then
    echo "--target is only valid for 'forgeos adopt' and 'forgeos update'." >&2; echo '' >&2; usage >&2; exit 1
  fi
fi

case "$CMD" in
  status|next)
    [ -f "$STATUS" ] || {
      echo "Cannot run: project-status.sh is missing from $HERE" >&2
      echo 'Run "forgeos doctor" for the full picture.' >&2
      exit 1
    }
    args=()
    [ "$JSON" -eq 1 ] && args+=('--json')
    [ "$CMD" = 'next' ] && args+=('--section' 'next')
    bash "$STATUS" ${args[@]+"${args[@]}"}
    exit $?
    ;;
  doctor|version|adopt|update) ;;
  -h|--help|help) usage; exit 0 ;;
  '') echo 'No command given.' >&2; echo '' >&2; usage >&2; exit 1 ;;
  *) echo "Unknown command: $CMD" >&2; echo '' >&2; usage >&2; exit 1 ;;
esac

# --- version ---------------------------------------------------------------------------------------
# Which ForgeOS this is, and where this checkout sits relative to the last tag. Like doctor, it
# describes the INSTALLATION rather than the project, which is why it is implemented here instead of
# routed: a version command that could not answer because the engine was missing would be a poor
# version command, and the doctor fixture proves that case is real.
#
# Every value is read from a local file or from local git metadata. Nothing here reaches the network.
if [ "$CMD" = 'version' ]; then
  v_missing=''
  v_note_missing() { v_missing="${v_missing:+$v_missing
}$1"; }

  v_version='unknown'; v_role='unknown'; v_source='missing'
  if [ -r "$REPO_ROOT/blueprint.version" ]; then
    v_source='blueprint.version'
    vv="$(grep -m1 '"version"' "$REPO_ROOT/blueprint.version" | sed 's/.*: *"//; s/".*//')"
    vr="$(grep -m1 '"role"'    "$REPO_ROOT/blueprint.version" | sed 's/.*: *"//; s/".*//')"
    [ -n "$vv" ] && v_version="$vv"
    [ -n "$vr" ] && v_role="$vr"
  else
    v_note_missing 'blueprint.version'
  fi

  # git, read-only. A shallow clone is treated as no answer for the DISTANCE: `git rev-list` there
  # counts only the fetched commits, so the number would be a floor rather than a fact.
  v_commit='unknown'; v_tag=''; v_distance='null'
  if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    c="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"
    [ -n "$c" ] && v_commit="$c"
    t="$(git -C "$REPO_ROOT" tag --sort=-v:refname 2>/dev/null | head -1)"
    [ -n "$t" ] && v_tag="$t"
    if [ -n "$v_tag" ] && [ "$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = 'false' ]; then
      d="$(git -C "$REPO_ROOT" rev-list --count "$v_tag..HEAD" 2>/dev/null)"
      case "$d" in
        ''|*[!0-9]*) ;;
        *) v_distance="$d" ;;
      esac
    fi
  else
    v_note_missing 'git metadata'
  fi

  # A GitHub Release is a REMOTE fact and no local file records one, so this command says it does not
  # know rather than guessing from the latest tag. The two are related but not the same: a tag can
  # exist with no release behind it, and reporting one as the other is how a version command starts
  # claiming something nobody published.
  v_release_known='false'; v_release=''
  v_note_missing 'GitHub release (remote; this command reads only local files)'

  if [ "$JSON" -eq 1 ]; then
    ms=''
    if [ -n "$v_missing" ]; then
      while IFS= read -r m; do
        [ -z "$m" ] && continue
        [ -n "$ms" ] && ms="$ms, "
        ms="$ms$(jstr "$m")"
      done <<< "$v_missing"
    fi
    cat <<VERJSONEOF
{
  "schema": "forgeos.version/1",
  "version": $(jstr "$v_version"),
  "role": $(jstr "$v_role"),
  "commit": $(jstr "$v_commit"),
  "latestTag": $(jnul "$v_tag"),
  "distanceFromLatestTag": $v_distance,
  "releaseKnown": $v_release_known,
  "releaseVersion": $(jnul "$v_release"),
  "source": $(jstr "$v_source"),
  "missingSources": [$ms],
  "safety": {
    "canModifyFiles": false,
    "canAuthorizeCode": false,
    "canOpenGovernanceWindow": false
  }
}
VERJSONEOF
    exit 0
  fi

  vnz() { if [ -z "$1" ] || [ "$1" = 'null' ]; then printf 'unknown'; else printf '%s' "$1"; fi; }
  echo ''
  echo 'ForgeOS version'
  echo ''
  printf '  %-22s %s\n' 'version' "$(vnz "$v_version")"
  printf '  %-22s %s\n' 'role' "$(vnz "$v_role")"
  printf '  %-22s %s\n' 'commit' "$(vnz "$v_commit")"
  printf '  %-22s %s\n' 'latest tag' "$(vnz "$v_tag")"
  printf '  %-22s %s\n' 'commits since that tag' "$(vnz "$v_distance")"
  printf '  %-22s %s\n' 'release' 'unknown -- remote fact, not read here'
  printf '  %-22s %s\n' 'source' "$v_source"
  if [ -n "$v_missing" ]; then
    echo ''
    echo '  not read -- reported, not guessed:'
    while IFS= read -r m; do [ -n "$m" ] && printf '    - %s\n' "$m"; done <<< "$v_missing"
  fi
  echo ''
  echo '  This command reads. It writes nothing, authorizes nothing, and opens no governance window.'
  echo ''
  exit 0
fi

# --- adopt -------------------------------------------------------------------------------------
# Syncs the portable blueprint into another project by DELEGATING to sync-blueprint. It re-implements
# none of that engine: fifteen versions of proven behaviour and the cases that pin them live there,
# and a second copy of the copy rules would be a second answer waiting to disagree.
#
# Dry run is the default, because sync-blueprint's default already is -- "WITHOUT --apply THIS ONLY
# REPORTS" is its own header. This command adds no writing path; it chooses between two that exist.
#
# --force is never passed and never exposed. It is the flag that overwrites a file the project
# customized, and a wrapper that quietly offered it would undo the guarantee the engine exists for.
#
# `update` is the same delegation with one precondition in front of it. adopt brings ForgeOS into a
# project that does not have it; update refreshes one that does. They share this block on purpose:
# two copies of the same delegation would eventually disagree about --force or about a counter.
if [ "$CMD" = 'adopt' ] || [ "$CMD" = 'update' ]; then
  SYNC="$REPO_ROOT/scripts/blueprint/sync-blueprint.sh"
  a_missing=''
  a_note_missing() { a_missing="${a_missing:+$a_missing
}$1"; }

  if [ -z "$TARGET" ]; then
    echo "$CMD needs --target <path>: the project to sync the blueprint into." >&2
    echo '' >&2
    usage >&2
    exit 1
  fi

  # What separates update from adopt, and the reason it is a command rather than an alias: update
  # refreshes a project that has ALREADY adopted, so it refuses one that has not. It fails closed --
  # syncing into a project that never adopted is an adoption, and calling it an update would hide a
  # first-time seeding behind a word that promises only a refresh.
  a_from_version=''
  if [ "$CMD" = 'update' ]; then
    tgt_bp="$TARGET/blueprint.version"
    if [ ! -r "$tgt_bp" ]; then
      echo "Nothing to update: $TARGET has no blueprint.version, so it has never adopted ForgeOS." >&2
      echo "Adopt it first:  forgeos adopt --target \"$TARGET\"" >&2
      exit 1
    fi
    tgt_role="$(grep -m1 '"role"' "$tgt_bp" | sed 's/.*: *"//; s/".*//')"
    if [ "$tgt_role" != 'adopted' ]; then
      echo "Refusing to update: $TARGET reports role '${tgt_role:-unknown}', not 'adopted'." >&2
      echo 'update refreshes a project that adopted ForgeOS; this target is not one.' >&2
      exit 1
    fi
    a_from_version="$(grep -m1 '"version"' "$tgt_bp" | sed 's/.*: *"//; s/".*//')"
  fi
  if [ ! -f "$SYNC" ]; then
    echo "Cannot run: scripts/blueprint/sync-blueprint.sh is missing from $REPO_ROOT" >&2
    echo 'Run "forgeos doctor" for the full picture.' >&2
    exit 1
  fi

  nzv() { if [ -z "$1" ]; then printf 'unknown'; else printf '%s' "$1"; fi; }
  a_mode='dry-run'
  [ "$APPLY" -eq 1 ] && a_mode='apply'

  # The version this checkout would bring. Read from the file, never assumed.
  a_to_version='unknown'
  if [ -r "$REPO_ROOT/blueprint.version" ]; then
    tv="$(grep -m1 '"version"' "$REPO_ROOT/blueprint.version" | sed 's/.*: *"//; s/".*//')"
    [ -n "$tv" ] && a_to_version="$tv"
  fi

  # The delegation itself. Exactly the engine's own two routes, and nothing else on the command line.
  sync_args=('--source' "$REPO_ROOT" '--target' "$TARGET")
  [ "$APPLY" -eq 1 ] && sync_args+=('--apply')
  sync_out="$(bash "$SYNC" "${sync_args[@]}" 2>&1)"
  sync_code=$?

  # The engine's counters are printed with fixed labels from array lengths, so they can be read back
  # without re-deriving anything. A label that is absent yields null -- never a zero, because "the
  # engine did not print this" and "the engine printed zero" are different facts. A self-test case
  # pins these labels, so a change to the engine's report fails loudly instead of quietly nulling.
  a_count() {   # a_count <label>
    local n
    n="$(printf '%s\n' "$sync_out" | sed -n "s/^  $1  *\([0-9][0-9]*\).*/\1/p" | head -1)"
    if [ -z "$n" ]; then printf 'null'; else printf '%s' "$n"; fi
  }
  a_new="$(a_count 'new')"
  a_updated="$(a_count 'updated')"
  a_unchanged="$(a_count 'unchanged')"
  a_preexisting="$(a_count 'pre-existing')"
  a_localmods="$(a_count 'locally modified')"
  a_removed="$(a_count 'removed in source')"
  a_owned="$(a_count 'project-owned')"
  a_seed_files="$(a_count 'seeded')"
  a_seed_dirs="$(printf '%s\n' "$sync_out" | sed -n 's/^  seeded  *[0-9][0-9]* file(s), \([0-9][0-9]*\) directory(ies).*/\1/p' | head -1)"
  [ -z "$a_seed_dirs" ] && a_seed_dirs='null'
  [ "$a_new" = 'null' ] && a_note_missing 'the counter table sync-blueprint prints (its labels may have changed)'

  # planned is what a dry run would write: new files plus updated ones plus first-time seeds.
  a_planned='null'
  if [ "$a_new" != 'null' ] && [ "$a_updated" != 'null' ]; then
    a_planned=$((a_new + a_updated))
    [ "$a_seed_files" != 'null' ] && a_planned=$((a_planned + a_seed_files))
  fi

  a_written='null'
  if [ "$APPLY" -eq 1 ]; then
    w="$(printf '%s\n' "$sync_out" | sed -n 's/^Applied\. \([0-9][0-9]*\) file(s) written.*/\1/p' | head -1)"
    [ -n "$w" ] && a_written="$w"
  fi

  # Warnings are read from the engine's own counters, never invented. Each names something a person
  # would want to know before applying.
  a_warnings=''
  a_warn() { a_warnings="${a_warnings:+$a_warnings
}$1"; }
  [ "$a_localmods" != 'null' ] && [ "${a_localmods:-0}" -gt 0 ] &&
    a_warn "$a_localmods file(s) were customized in the target and are skipped, not overwritten"
  [ "$a_preexisting" != 'null' ] && [ "${a_preexisting:-0}" -gt 0 ] &&
    a_warn "$a_preexisting file(s) already exist in the target and were never placed by sync; they are skipped"
  [ "$a_removed" != 'null' ] && [ "${a_removed:-0}" -gt 0 ] &&
    a_warn "$a_removed file(s) are gone from the source; sync deletes nothing, so remove them by hand if that is intended"
  printf '%s\n' "$sync_out" | grep -q 'not a git repository yet' &&
    a_warn 'the target is not a git repository yet, so its validation suite cannot scan a tracked tree until it is'
  [ "$sync_code" -ne 0 ] && a_warn "sync-blueprint exited $sync_code; nothing above should be trusted as a completed plan"

  if [ "$JSON" -eq 1 ]; then
    ms=''
    if [ -n "$a_missing" ]; then
      while IFS= read -r m; do
        [ -z "$m" ] && continue
        [ -n "$ms" ] && ms="$ms, "
        ms="$ms$(jstr "$m")"
      done <<< "$a_missing"
    fi
    ws=''
    if [ -n "$a_warnings" ]; then
      while IFS= read -r w2; do
        [ -z "$w2" ] && continue
        [ -n "$ws" ] && ws="$ws, "
        ws="$ws$(jstr "$w2")"
      done <<< "$a_warnings"
    fi
    # canModifyFiles is TRUE in apply mode. It is the one writing path in this file, and a flag that
    # said false while files were being written would be the exact lie these flags exist to prevent.
    a_can_write='false'
    [ "$APPLY" -eq 1 ] && a_can_write='true'
    cat <<ADOPTJSONEOF
{
  "schema": $(jstr "forgeos.$CMD/1"),
  "mode": $(jstr "$a_mode"),
  "fromVersion": $(jnul "$a_from_version"),
  "toVersion": $(jstr "$a_to_version"),
  "wouldWrite": $a_can_write,
  "delegatesTo": "scripts/blueprint/sync-blueprint.sh",
  "forcePassed": false,
  "source": $(jstr "$REPO_ROOT"),
  "target": $(jstr "$TARGET"),
  "plannedFileCount": $a_planned,
  "filesWritten": $a_written,
  "counters": {
    "new": $a_new,
    "updated": $a_updated,
    "unchanged": $a_unchanged,
    "preExisting": $a_preexisting,
    "locallyModified": $a_localmods,
    "removedInSource": $a_removed,
    "projectOwned": $a_owned,
    "seededFiles": $a_seed_files,
    "seededDirectories": $a_seed_dirs
  },
  "exitCode": $sync_code,
  "warnings": [$ws],
  "missingSources": [$ms],
  "safety": {
    "canModifyFiles": $a_can_write,
    "canAuthorizeCode": false,
    "canOpenGovernanceWindow": false
  }
}
ADOPTJSONEOF
    exit "$sync_code"
  fi

  # The engine's own report is the report. Reprinting it in this command's words would be a second
  # description of the same plan, and the two would drift.
  printf '%s\n' "$sync_out"
  echo ''
  if [ "$APPLY" -eq 1 ]; then
    echo '  Applied through sync-blueprint. --force was not passed, so any file this project had'
    echo '  customized was left alone rather than overwritten.'
  else
    echo '  This was a DRY RUN. Nothing was written.'
    echo '  To apply it:'
    # QUOTED, and that is not cosmetic. A target path containing a space -- which is ordinary on
    # Windows and on any Desktop folder -- came back as `--target /a/b/host machinery --apply`,
    # and copying that line verbatim failed with "Unknown option: machinery". A suggested command
    # that cannot be pasted is worse than none: it teaches the reader to distrust the output.
    printf '    bash scripts/command/forgeos.sh %s --target "%s" --apply\n' "$CMD" "$TARGET"
  fi
  if [ "$CMD" = 'update' ]; then
    printf '  %-22s %s -> %s\n' 'version' "$(nzv "$a_from_version")" "$a_to_version"
  fi
  echo ''
  exit "$sync_code"
fi

# --- doctor ---------------------------------------------------------------------------------------
# Whether this installation can run, and when it cannot, which prerequisite failed and what to do
# about it. A missing tool is REPORTED, never hidden and never silently worked around: a doctor that
# hides a missing dependency is how a first run fails with a stack trace instead of a sentence.
#
# Rows are ok / missing / unknown. "unknown" is for a question this command cannot answer without
# doing something it must not do -- there is no network call and no write anywhere in here.
rows=''
ready=1
add_row() {   # add_row <name> <state> <detail> <required 0|1>
  rows="${rows}${rows:+
}$1|$2|$3|$4"
  [ "$4" = '1' ] && [ "$2" != 'ok' ] && ready=0
  return 0
}

# 1. the shell itself
add_row 'shell' 'ok' "bash ${BASH_VERSION:-unknown}" 1

# 2. and 3. the engine and the gates this surface depends on
if [ -f "$STATUS" ]; then
  add_row 'project-status' 'ok' 'scripts/command/project-status.sh' 1
else
  add_row 'project-status' 'missing' 'expected scripts/command/project-status.sh -- re-sync the blueprint' 1
fi
if [ -f "$REPO_ROOT/scripts/validation/check-all.sh" ]; then
  add_row 'validation' 'ok' 'scripts/validation/check-all.sh' 1
else
  add_row 'validation' 'missing' 'expected scripts/validation/check-all.sh -- re-sync the blueprint' 1
fi

# 4. and 5. the two files that tell this installation what it is
if [ -r "$REPO_ROOT/blueprint.version" ]; then
  dv="$(grep -m1 '"version"' "$REPO_ROOT/blueprint.version" | sed 's/.*: *"//; s/".*//')"
  dr="$(grep -m1 '"role"'    "$REPO_ROOT/blueprint.version" | sed 's/.*: *"//; s/".*//')"
  add_row 'blueprint.version' 'ok' "version ${dv:-unknown}, role ${dr:-unknown}" 1
else
  add_row 'blueprint.version' 'missing' 'expected blueprint.version at the repository root' 1
fi
if [ -r "$REPO_ROOT/scripts/lib/blueprint-manifest.json" ]; then
  add_row 'manifest' 'ok' 'scripts/lib/blueprint-manifest.json' 1
else
  add_row 'manifest' 'missing' 'expected scripts/lib/blueprint-manifest.json -- re-sync the blueprint' 1
fi

# 6. the JSON reader, chosen by CAPABILITY rather than by name. Git Bash ships a Microsoft Store
# stub called python3 that sits on PATH, satisfies `command -v`, and cannot run anything -- so the
# probe is a real parse, the same rule check-links already follows. Optional: every command here
# works without one, and only a caller piping --json into a parser needs it.
json_reader='none'
if command -v jq >/dev/null 2>&1; then
  json_reader='jq'
else
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && printf '{}' | "$c" -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
      json_reader="$c"; break
    fi
  done
fi
if [ "$json_reader" = 'none' ]; then
  add_row 'json reader' 'missing' 'no jq and no working python -- optional, needed only to parse --json output here' 0
else
  add_row 'json reader' 'ok' "$json_reader" 0
fi

# 7. git. Optional for reporting, but without it the status command reports its own git fields as
# missing rather than failing, so this is a warning and not a stop.
if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  add_row 'git' 'ok' "$(git --version 2>/dev/null | head -1)" 0
elif command -v git >/dev/null 2>&1; then
  add_row 'git' 'missing' 'git is installed but this is not a repository -- branch, commit and ages report unknown' 0
else
  add_row 'git' 'missing' 'git not on PATH -- branch, commit and slice ages report unknown' 0
fi

# 8. hook wiring. The hooks are the safety net; a settings file that does not reference them means
# the net is not attached, which is worth saying out loud even though nothing here depends on it.
SETTINGS="$REPO_ROOT/.claude/settings.json"
if [ -r "$SETTINGS" ]; then
  hooked="$(grep -c 'scripts/hooks' "$SETTINGS")"
  if [ "${hooked:-0}" -gt 0 ]; then
    add_row 'hook wiring' 'ok' ".claude/settings.json references scripts/hooks (${hooked} time(s))" 0
  else
    add_row 'hook wiring' 'missing' '.claude/settings.json does not reference scripts/hooks -- the guards are not wired' 0
  fi
else
  add_row 'hook wiring' 'unknown' '.claude/settings.json not readable here' 0
fi

# 9. line-ending policy. Its absence is what lets a .ps1 and a .sh disagree across platforms.
if [ -r "$REPO_ROOT/.gitattributes" ]; then
  eol="$(grep -c 'eol=' "$REPO_ROOT/.gitattributes")"
  add_row 'line endings' 'ok' ".gitattributes pins ${eol:-0} rule(s)" 0
else
  add_row 'line endings' 'missing' 'no .gitattributes -- line endings would follow whatever the platform does' 0
fi

verdict='ready'
[ "$ready" -eq 1 ] || verdict='not ready'

if [ "$JSON" -eq 1 ]; then
  printf '{\n'
  printf '  "schema": "forgeos.doctor/1",\n'
  printf '  "generatedFrom": "local installation only",\n'
  printf '  "ready": %s,\n' "$([ "$ready" -eq 1 ] && printf 'true' || printf 'false')"
  printf '  "checks": [\n'
  first=1
  while IFS='|' read -r n s d r; do
    [ -z "$n" ] && continue
    [ "$first" -eq 1 ] || printf ',\n'
    first=0
    printf '    { "name": %s, "state": %s, "required": %s, "detail": %s }' \
      "$(jstr "$n")" "$(jstr "$s")" "$([ "$r" = '1' ] && printf 'true' || printf 'false')" "$(jstr "$d")"
  done <<< "$rows"
  printf '\n  ],\n'
  printf '  "safety": {\n'
  printf '    "canModifyFiles": false,\n'
  printf '    "canAuthorizeCode": false,\n'
  printf '    "canOpenGovernanceWindow": false\n'
  printf '  }\n'
  printf '}\n'
  exit 0
fi

echo ''
echo "ForgeOS doctor  [$verdict]"
echo ''
while IFS='|' read -r n s d r; do
  [ -z "$n" ] && continue
  req='optional'
  [ "$r" = '1' ] && req='required'
  printf '  %-18s %-8s %-9s %s\n' "$n" "$s" "$req" "$d"
done <<< "$rows"
echo ''
if [ "$ready" -eq 1 ]; then
  echo '  Every required prerequisite is present. Optional rows marked missing are safe to ignore'
  echo '  unless you need what they provide.'
else
  echo '  A required prerequisite is missing. Each row above names what it expected and what to do.'
fi
echo ''
echo '  This command reads. It writes nothing, authorizes nothing, and opens no governance window.'
echo ''
exit 0
