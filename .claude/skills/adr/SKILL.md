---
name: adr
description: Record an architecture decision directly, without the interactive deliberation that decision-needed provides. Use when user says "write an ADR", "record this decision", "document this choice".
---

Arguments: project name + decision title (e.g. "traffic-light-mgmt use leaflet for maps")

## Steps

1. Parse project name from $ARGUMENTS, then resolve its folder with the rule in
   AGENTS.md (§ Project path resolution). An ADR belongs to the project whose code
   the decision governs — a decision about one sub goes in that sub, not the main.
   Main-level `decisions/` is for choices that bind every sub.
2. Read existing ADR filenames only in that project's decisions/ to get next NNN.

3. **Supersession check — do this before writing, every time, unprompted.**
   Read the `## Key decisions` section of that project's `context.md`. You are opening it
   in step 5 anyway, so this costs nothing. Compare the new decision against those
   one-line summaries and ask yourself: does this *contradict* one of them, not merely
   sit near it?
   - Contradicts → stop and say so: "ADR-NNN says X; this says not-X. Supersede it?"
     Then run `/supersede`. Do not wait to be asked — the user is recording what they
     just decided, not auditing what they decided six weeks ago.
   - Extends or refines → carry on, no supersession.

   Filenames are not enough for this. `ADR-003-refresh-token-rotation` does not advertise
   that it is being reversed; the one-line summary next to it does. Never do this check
   by matching filenames.

   Duplicate ADR numbers in a folder are a strong signal this check was skipped in the
   past — flag them when you see them.
4. Create ADR-NNN-[slug].md in that folder

Template:
```
# ADR-NNN: [Title]
Date: YYYY-MM-DD
Status: Accepted

## Context
## Decision
## Consequences
## Alternatives considered
```

5. Update `## Key decisions` in that project's context.md:
   Add one line: `- [Title] — ADR-NNN (YYYY-MM-DD): [one sentence summary]`
   This is critical — context.md must stay current so project-status
   never needs to read raw ADR files, and it is what step 3 reads next time.

6. Do NOT re-read context.md in full to do step 5.
   Append only to the Key decisions section.

7. If the ADR changes the sub's `status:`, `summary:` or `blocker:` frontmatter,
   update those fields and then run `/rollup <main>`. The parent `_index.md` is
   generated — it does not notice changes on its own.

8. Last, apply the rules filed under `### /adr` in `AGENTS.local.md` § Local rules, if there are any.
