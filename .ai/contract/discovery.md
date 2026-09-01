# Operating Contract — Discovery

The gate that stands in front of every other activity in an undefined project.

Load automatically when the discovery gate fires. Referenced by `.ai/contract/core.md` §0.

## 1. The Gate

**A project whose `.ai/context/` still carries blocking `TBD` markers is undefined. In an undefined
project the only permitted activity is discovery.**

Check on the first turn of any session:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validation/check-placeholders.ps1
bash scripts/validation/check-placeholders.sh
```

| Blocking markers | Mode |
| --- | --- |
| more than 0 | **Discovery.** Interview only. |
| 0 | Normal. The full lifecycle in `lifecycle.md` applies. |

While in discovery mode, these are forbidden regardless of what is asked:

- Writing, generating, or scaffolding any source file
- Creating directories outside those the discovery output defines
- Installing a dependency, initializing a framework, running a generator
- Choosing a technology, a pattern, or a data model without the user's decision
- Opening a task in `.ai/tasks/active/`

If the user asks for code while the project is undefined, say what is missing, ask the next
question, and continue the interview. **Do not compromise by writing "just a starting point".**
A starting point built on invented requirements is the most expensive artifact in software: it
looks like progress and it silently fixes decisions nobody made.

## 2. Why the Gate Exists

An agent given an empty directory and a one-line idea will produce a plausible project. Every gap
in the brief becomes an invented assumption, the assumptions become code, and the code becomes the
thing the user has to argue against for the rest of the project.

Discovery converts invention into questions. The cost is one session of asking. The alternative
cost is a rewrite.

## 3. The Six Phases

Run in order. **Do not start a phase until the previous one is confirmed by the user.** End every
phase with a written summary the user can correct before you move on.

### Phase 1 — The Idea → `docs/product/vision.md`

- What problem does this solve, and for whom, specifically?
- Who is the primary user? Who is explicitly *not* a user?
- What do they do today instead? Why is that not good enough?
- What is deliberately **out of scope** for v1?
- How will you know in six months whether this worked? Name a number.
- What already exists — brand, audience, content, an older version?

**Close phase 1 by classifying the project.** Pick a profile from `.ai/profiles/` and record it in
`.ai/context/project.md`. It decides which roles are mandatory and which gates must pass, so the
answer changes what phases 2 to 6 must press on. `none` is a valid answer for something genuinely
unusual — say so plainly, and note that no profile is then enforcing anything.

### Phase 2 — Requirements → `docs/product/requirements.md`

- Walk through the first five minutes of a new user, step by step.
- What is the single core loop the product repeats?
- What is the minimum that can ship and still be worth using?
- What must never happen? (data loss, double charge, exposure)
- Which parts are v1, which are v2, which are "maybe never"?
- What content, data, or integrations must exist on day one?

### Phase 3 — Technology → `.ai/context/stack.md` + a decision record

**Do not choose. Present and let the user choose.**

Offer two or three viable stacks. For each: mechanism, what it makes easy, what it makes hard,
hosting and cost implications, hiring and maintenance implications, and what it forecloses.
Weight the recommendation by the user's actual constraints, not by popularity.

Ask: existing team skills, hosting constraints, budget, language and locale needs, existing
systems to integrate with.

Record the outcome with `/adr` — including **why the alternatives lost**.

### Phase 4 — Brand and Interface → `docs/design/design-system.md`

- Does a brand exist? Colors, logo, typography, tone. If yes, collect the exact values.
- If not: what should it feel like? Name three adjectives, and one product you admire.
- Primary language and direction. **RTL is a structural decision, not a stylesheet.**
- Arabic typeface, and its Latin pairing.
- Light, dark, or both.
- Accessibility target — contrast, keyboard, screen reader.
- Density: compact and information-dense, or spacious and calm?

Record concrete values — hex codes, font names, spacing scale — not adjectives. An adjective is
not a design system.

### Phase 5 — Architecture → `docs/architecture/overview.md` + `docs/domains/domain-map.md`

Delegate to the `architect` subagent. It must produce:

- System boundaries and their responsibilities
- A **system diagram** in Mermaid (`.ai/rules/diagrams.md`)
- The domain model and its language — an **ER diagram** in Mermaid
- The critical flows — a **sequence diagram** for anything involving money, auth, or external systems
- Data ownership: who writes what, who reads what
- The directory structure that follows from the above, written to `.ai/context/scaffold.json`

Every structural choice traces to a requirement from Phase 2. A layer that no requirement demands
does not get built.

### Phase 6 — Constraints and Operations → `.ai/context/constraints.md`

- Hosting, region, data residency, legal or compliance obligations
- Availability target, expected load, performance budget
- Backup, retention, and recovery expectations
- Deployment cadence, approval gates, who can release
- Budget ceiling for infrastructure and third-party services
- Security obligations: payment data, personal data, minors, regulated content

## 4. Interview Rules

1. **Ask until the picture is complete, not until the user seems tired.** An unanswered question is
   a decision deferred to an agent, which means a decision made by guessing.
2. **One topic at a time.** A wall of twelve questions gets one answer.
3. **Never fill a gap with a plausible default.** If the user does not know, record the question in
   `.ai/memory/open-questions.md` with an owner and what it blocks, and continue. Unanswered is a
   valid, honest state; unanswered *and unrecorded* is not.
4. **Play back what you heard** at the end of each phase, in the user's own terms, and let them
   correct it.
5. **Separate what the user said from what you inferred.** Mark inferences explicitly and get them
   confirmed before they become facts.
6. **When the user says "you decide"** — present options with trade-offs and a recommendation, then
   get an explicit choice. Silence is not a choice.
7. **Write as you go.** Fill each document at the end of its phase, not at the end of discovery.
   A crashed session must not lose the interview.

## 5. Completion

Discovery is complete only when:

- [ ] `check-placeholders` reports **0 blocking** markers
- [ ] `docs/product/vision.md` and `requirements.md` describe a product a stranger could scope
- [ ] `.ai/context/stack.md` names exact technologies and versions, with a decision record
- [ ] `docs/design/design-system.md` carries concrete values, not adjectives
- [ ] `docs/architecture/overview.md` has a system diagram and named boundaries
- [ ] `docs/domains/domain-map.md` has the domain model and its vocabulary
- [ ] `.ai/context/constraints.md` states hosting, availability, budget, and compliance
- [ ] `.ai/context/scaffold.json` describes the directory structure
- [ ] Every open question and unverified assumption is in `.ai/memory/open-questions.md` with an
      owner — none are silently resolved

## 6. Handover to Build

On completion, and only then:

1. Run `scripts/ai/scaffold.ps1` / `.sh` to create the directory structure. It never overwrites.
2. Fill `.ai/context/structure.md` from what was created.
3. Generate the initial backlog into `.ai/tasks/inbox/` — each task with **observable** acceptance
   criteria, ordered so that each is shippable on its own.
4. Report the plan and get approval.
5. From here the normal lifecycle applies: `/start-task` → `/implement` → `/review` → `/finish-task`.

Re-running discovery later is legitimate: a pivot, a new domain, a major rewrite. Run
`/discovery --phase <n>` to revisit one phase without redoing all six.
