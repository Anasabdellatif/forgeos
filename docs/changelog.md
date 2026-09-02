# Changelog

**The changelog is `blueprint.version`.** It is not summarized here, and this page does not restate
it: two changelogs are one changelog and one lie, and the second one always rots.

## Where it lives, and why there

`blueprint.version` is a JSON file at the repository root carrying three things at once:

- the released version,
- a `changelog` object — one entry per version, keyed by version number,
- and, in an adopting project, a SHA-256 hash per synced file.

That last field is why the changelog lives inside it rather than beside it. The same file is the
identity a project records when it adopts, and the record the next sync compares against. Keeping
the version and its history in the file that adoption already reads means an adopted project can
answer *what do I carry, and what changed since* without fetching anything.

## Reading it

```bash
# The current version
grep -m1 '"version"' blueprint.version

# One entry
python3 -c "import json;d=json.load(open('blueprint.version'));print(d['changelog']['1.15.31'])"

# Every version, newest first
python3 -c "import json;d=json.load(open('blueprint.version'));[print(v) for v in sorted(d['changelog'], key=lambda s:[int(p) for p in s.split('.')], reverse=True)]"
```

Entries are prose, not bullet points, and they are written to answer one question: *what changed,
and what went wrong that made the change necessary.* Several will be field reports — a defect a
real adoption surfaced, the fix, and the permanent check that now guards it. The defects real
adoption has already found, anonymized, are in [`docs/field-reports.md`](field-reports.md).

## What a version number means here

A version is bumped when the **portable half** changes in a way adopting projects should take:
the contract, the rules, the hooks, the validation scripts, the templates, the manifest, the
workflow. Changes to this repository's own context, tasks, plans, or memory do not move it —
those never travel.

So a bump is a signal to adopters, not a release ceremony: re-run the sync from the newer source and
read the entry for what you are taking.

## Where the history starts

This public repository begins at `1.15.29`, launched as a clean, verified snapshot. The version
number is higher than the entry count because the engineering line that produced it is older than
its public home; development before the launch happened privately, and its history stays there.
From this release forward, every version an adopter can take is documented here, in the file that
adoption already reads.

## A rendered page

A generated page — derived from `blueprint.version`, never hand-maintained — is on the roadmap
(`docs/roadmap.md`). Until it exists, the commands above are the honest answer, and this page will
not pretend otherwise by carrying a copy that drifts.
