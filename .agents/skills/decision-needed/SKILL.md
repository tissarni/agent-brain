---
name: decision-needed
description: Help think through a design decision and immediately write an ADR. Use when user says "I need to decide", "help me choose between", "which approach should I use".
---

Arguments: project name + decision topic (e.g. "traffic-light-mgmt auth strategy")

1. Parse project name and decision topic from $ARGUMENTS
2. Ask the user these three questions one at a time:
   a. What is the context forcing this decision?
   b. What are the options you're considering?
   c. What are the constraints (performance, security, maintainability)?

3. Help user reason through the options against their constraints
4. Once user has decided, confirm: "Should I record this as ADR-NNN?"

5. If confirmed:
   - Resolve the project folder with the rule in AGENTS.md (§ Project path resolution).
     The ADR goes where the code it governs lives: a sub-scoped decision in that sub,
     a decision binding every sub at the main level.
   - Read existing ADR filenames to get next NNN.
   - **Supersession check, unprompted.** Read `## Key decisions` in that project's
     `context.md` — you open it below anyway — and compare the new decision against those
     one-line summaries. If it *contradicts* one rather than extending it, say so and run
     `/supersede`. Never do this by filename: `ADR-003-refresh-token-rotation` does not
     advertise that it is being reversed, its summary line does.
     This matters more here than in `/adr`: an interview that ends "so we're going the
     other way" is a reversal by definition, and it is the moment the old ADR silently
     becomes wrong.
   - Create <project-folder>/decisions/ADR-NNN-[slug].md
   - Update that project's context.md `## Key decisions` to reference the new ADR
   - If the decision changes the sub's status/summary/blocker frontmatter,
     update it and run `/rollup <main>`

6. Last, apply the rules filed under `### /decision-needed` in `AGENTS.local.md` § Local rules, if there are any.

ADR template:
# ADR-NNN: [Title]
Date: YYYY-MM-DD
Status: Accepted

## Context
[What situation forced this decision]

## Decision
[What was decided, precisely]

## Consequences
[What this makes easier / harder]

## Alternatives considered
[What was rejected and why]
