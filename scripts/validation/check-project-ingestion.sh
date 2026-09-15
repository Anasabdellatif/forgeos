#!/usr/bin/env bash
# Reports whether this project has turned its governing documents into compact product
# intelligence -- or, with no governing documents, prepared its discovery records. POSIX
# counterpart of check-project-ingestion.ps1. M-25 Project Ingestion Layer, slice 1.
#
# Informational by design, and never a failure: a project that adopted before this layer existed
# has no maps yet, and that is a finding to report, not a reason to fail validation. Gating is
# slice 3, once the layer is proven on adopters. Always exits 0.
#
# Cheap by construction: it checks directory and file PRESENCE only. It never opens a governing
# document, never reads a PDF, and never scans content -- the maps exist precisely so that nobody,
# human or agent, rereads a whole specification to answer one question. The procedure that fills
# the maps is .ai/workflows/ingest-project.md.
#
# Usage: check-project-ingestion.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRODUCT_REL='.ai/product'
PRODUCT_DIR="$REPO_ROOT/$PRODUCT_REL"

row() { printf '  %-13s %s\n' "$1" "$2"; }

role='unknown'
if [ -f "$REPO_ROOT/blueprint.version" ]; then
  r="$(grep -m1 '"role"' "$REPO_ROOT/blueprint.version" | sed 's/.*: *"//; s/".*//')"
  [ -n "$r" ] && role="$r"
fi

echo 'Project ingestion'
row 'role' "$role"

if [ "$role" = 'source' ]; then
  row 'mode' 'NOT_APPLICABLE'
  echo 'Project ingestion N/A  (source role -- the blueprint has no product of its own to ingest; adopting projects are checked)'
  exit 0
fi

# Governing document directories, as a first guess. Each entry is one logical place in up to two
# common spellings; the first that exists is reported, so a case-insensitive filesystem answers once
# and both shells print the same name. A directory counts only when it holds at least one file, and
# find stops at the first file it sees -- the contents are never read.
governing=''
for cand_pair in 'docs/Client:docs/client' 'docs/Developer:docs/developer' 'docs/data:docs/Data' \
                 'docs/specifications:' 'docs/specs:'; do
  for cand in "${cand_pair%%:*}" "${cand_pair#*:}"; do
    [ -n "$cand" ] || continue
    if [ -d "$REPO_ROOT/$cand" ] && [ -n "$(find "$REPO_ROOT/$cand" -type f -print -quit 2>/dev/null)" ]; then
      governing="${governing:+$governing, }$cand"
      break
    fi
  done
done

# A map counts only when it is non-empty: an empty file is a placeholder, not a map.
intel_n=0; intel_missing=''
for name in authority-map source-index project-concept module-map requirement-matrix \
            implementation-roadmap open-decisions; do
  if [ -s "$PRODUCT_DIR/$name.md" ]; then
    intel_n=$((intel_n + 1))
  else
    intel_missing="${intel_missing:+$intel_missing, }$PRODUCT_REL/$name.md"
  fi
done

disc_n=0; disc_missing=''
for name in project-brief stakeholders module-map-draft questions assumptions phase-roadmap; do
  if [ -s "$PRODUCT_DIR/$name.md" ]; then
    disc_n=$((disc_n + 1))
  else
    disc_missing="${disc_missing:+$disc_missing, }$PRODUCT_REL/$name.md"
  fi
done

# The authority map is the declaration: a project that has written one says its governing documents
# exist, wherever they live -- the directory list above is only the first guess.
mode='PROJECT_DISCOVERY_REQUIRED'
governing_text='none found'
if [ -n "$governing" ]; then
  mode='PROJECT_WITH_GOVERNING_DOCS'
  governing_text="$governing"
elif [ -s "$PRODUCT_DIR/authority-map.md" ]; then
  mode='PROJECT_WITH_GOVERNING_DOCS'
  governing_text="declared in $PRODUCT_REL/authority-map.md"
fi

row 'mode' "$mode"
row 'governing' "$governing_text"
row 'intelligence' "$intel_n of 7 in $PRODUCT_REL"
row 'discovery' "$disc_n of 6 in $PRODUCT_REL"

if [ "$mode" = 'PROJECT_WITH_GOVERNING_DOCS' ]; then
  if [ "$intel_n" -eq 7 ]; then
    echo 'Project ingestion OK  (governing documents found; the product intelligence layer is complete, 7 of 7 maps)'
  else
    row 'missing' "$intel_missing"
    echo "Project ingestion NOTE  (governing documents found; $intel_n of 7 product intelligence maps -- run .ai/workflows/ingest-project.md before implementation)"
  fi
else
  if [ "$disc_n" -eq 6 ]; then
    echo 'Project ingestion OK  (no governing documents found; the discovery layer is complete, 6 of 6 records)'
  else
    row 'missing' "$disc_missing"
    echo "Project ingestion NOTE  (no governing documents found; $disc_n of 6 discovery records -- run .ai/workflows/ingest-project.md in discovery mode before implementation)"
  fi
fi

exit 0
