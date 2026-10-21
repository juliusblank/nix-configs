---
name: explore
description: Goal-first tracking of private, exploration-heavy topics in this repo. Use when the user wants to start, continue, review or close an exploration ("/explore new|iterate|status|close <slug>"), or brings a new idea to research. Runs the interview, scrutiny and verdict, approach scoring, iteration with budget, and applies consequences. Files live in docs/explorations/.
argument-hint: "new <idea> | iterate <slug> | status [slug] | close <slug>"
---

# /explore — explorations

The rules are in `docs/SPEC.md` → **Explorations** (read it first; it wins over this file).
Files: `docs/explorations/<slug>.md` (copy `docs/explorations/_template.md`) and the
index `docs/explorations/README.md`.

## General rules

- **Interview, don't assume.** Ask a few focused questions at a time (max 3–4), propose
  answers where you can, and let the user correct them. Use their words for goals.
- **Questions over tasks.** Every iteration answers one question.
- **Evidence over opinion.** Mark what is verified, what is inferred, what is unknown.
  Never invent facts, paths, prices or features; cite sources (links) for web findings.
- **Stay in budget.** Track time / money per iteration; at the end of the budget, stop
  and run the end-of-budget review (below) instead of continuing.
- **Keep the file current.** Update the exploration file and the index (status, last
  update) at the end of every mode. Concise and precise; detail goes into linked notes.
- **Repo workflow applies** (`CLAUDE.md`): work on the exploration's branch
  `explore/<slug>` (the zse `explore` worktree), conventional commits
  (`docs(explore): …`), PR, never merge yourself, ask before changes outside
  `docs/explorations/` and the spec / roadmap lines the consequences touch.

## new <idea>

1. **Slug**: short kebab-case; check it is not taken in the index.
2. **Interview** (spec → Interview): purpose, goal, non-goals, context, constraints and
   risk tolerance, prior knowledge and research, references, budget, success criteria,
   open questions and assumptions. Skip what is clearly not applicable.
3. **Scrutiny**: search own docs first (`docs/`, `docs/explorations/`, roadmap), then the
   web. Answer: exists already? makes sense? knowledge level? greenfield or researched?
4. **Verdict** with a short rationale: **pursue · reuse · defer · discard** (defer and
   discard need a reason; defer needs a revisit trigger). Quick triage may end here:
   write a short file with status `deferred` / `discarded`, or point to what to reuse.
5. **Pursue** → sharpen goal, non-goals and definition of done with the user until the
   outcome is concrete enough to recognise "done" (avoid overshooting). Seed the
   approach backlog and open questions. Status `active`. Add a roadmap row if the user
   agrees.

## iterate <slug>

1. Read the file; show goal, open questions, backlog and the last iteration's result.
2. **Pick one question** with the user (the most uncertainty-removing one first).
3. **Brainstorm approaches** — as many as possible, including cheap and odd ones; add
   them to the backlog.
4. **Score** each 1–3 on: learning per effort (most important), value toward the goal,
   time to first signal, risk / reversibility, cost, fit. Select the top **2 (max 3)**.
5. Per selected approach: **success criteria** and **budget**. Write them down before
   executing.
6. **Execute** with the user; record results (facts, sources, numbers) as you go.
7. **Conclusions → consequences** — the checklist, every time:
   - goal and definition of done: still right? update;
   - open questions: mark answered ones done, add new ones;
   - backlog: drop or re-score approaches the answer affects;
   - spec / roadmap / other explorations / linked notes: apply the change (ask first
     for files outside `docs/explorations/`);
   - record each applied consequence in the iteration ("Consequences applied").
8. **Goal check**: reached → suggest `close`; no longer worth it → suggest `discard`;
   else name the next question.

### End-of-budget review

When an iteration's budget is used: stop and decide with the user — **answered**,
**continue** (new, explicit budget), or **drop** the approach (record why). Both
"answered" and "budget used, not answered" are valid iteration results.

## status [slug]

- No slug: print the index (slug, status, goal, last update) and flag stale ones.
- With slug: goal, status, current iteration and question, remaining budget, open
  questions (top 3), and the **next step**. If a budget is used up, start the
  end-of-budget review.

## close <slug>

Goal reached or discarded: write the **Summary** — outcome (against the definition of
done), key decisions, learnings, artifacts (files, PRs), follow-ups (as new explorations
or roadmap rows, if the user wants). Set status `done` or `discarded`, update the index
and the roadmap row.
