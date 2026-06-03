# VibeUE Self-Improvement Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a gap-driven, in-session self-improvement pipeline for the VibeUE MCP, packaged as a Claude Code skill that resolves missing-tool situations, verifies live in the editor, and persists results to a user-owned fork.

**Architecture:** The pipeline is a Markdown Claude Code skill (`vibeue-self-improve`) the agent invokes the moment it detects a true tool gap. It orchestrates existing VibeUE MCP tools (`manage_skills`, `discover_python_*`, `execute_python_code`, `read_logs`, `deep_research`). Knowledge it produces is persisted as VibeUE skill docs in a fork (`dry-eye/VibeUE`); deeper gaps escalate to approval-gated C++ service/MCP tools. A versioned gap-log records every outcome.

**Tech Stack:** Markdown skills (superpowers conventions), VibeUE MCP tools, git (`gh` CLI, authed as `dry-eye`), Unreal Engine 5.7 Python API, C++ (`Source/VibeUE/Private/PythonAPI/`) for the escalation tier.

**Two skill entities (do not conflate):**
- **Orchestration skill** `vibeue-self-improve` — the pipeline procedure. Lives at user-level `C:\Users\Dry Eye\.claude\skills\vibeue-self-improve\SKILL.md`. NOT part of the fork.
- **Knowledge skills** — the VibeUE MCP skill docs the pipeline *produces*. Live in the fork at `Content/Skills/<name>/`.

**Reference spec:** `docs/superpowers/specs/2026-06-03-vibeue-self-improve-design.md`

---

## File Structure

| File | Responsibility | Tier |
|------|----------------|------|
| `C:\Users\Dry Eye\.claude\skills\vibeue-self-improve\SKILL.md` | The pipeline procedure + gates + gap-record schema | Orchestration |
| `Plugins/VibeUE/docs/self-improve/gap-log.md` (fork) | Versioned log of every gap outcome | Data |
| `Plugins/VibeUE/docs/self-improve/README.md` (fork) | Explains the gap-log format + how the pipeline writes to the fork | Docs |
| `Plugins/VibeUE/Content/Skills/<name>/` (fork) | Knowledge skills produced at runtime by the pipeline | Output (runtime) |
| `Plugins/VibeUE/Source/VibeUE/Private/PythonAPI/` (fork) | C++ service methods added at runtime by the C++ tier | Output (runtime) |

Repo note: the local plugin repo (`Plugins/VibeUE`) currently has `origin = kevinpbuckley/VibeUE` (upstream). All pipeline writes go to the `fork` remote (`dry-eye/VibeUE`); never push to `origin`. Work happens on branch `feature/self-improve-pipeline` (already created; spec already committed there).

---

## Task 1: Create the fork and wire the `fork` remote

**Files:**
- Modify: git remotes of `M:/UnrealProjects/Game/Plugins/VibeUE`

- [ ] **Step 1: Verify gh auth (precondition)**

Run (PowerShell): `gh auth status`
Expected: `Logged in to github.com account dry-eye`. If not, the user runs `! gh auth login` in the session.

- [ ] **Step 2: Fork upstream to dry-eye and add the `fork` remote**

Run (Bash tool, from the plugin dir):
```bash
cd "M:/UnrealProjects/Game/Plugins/VibeUE"
gh repo fork kevinpbuckley/VibeUE --clone=false --remote=true --remote-name=fork
```
Expected: creates `dry-eye/VibeUE` (or reports it already exists) and adds a `fork` remote.

- [ ] **Step 3: Verify the remote points at the fork, not upstream**

Run: `git remote -v`
Expected: `fork  https://github.com/dry-eye/VibeUE.git` (fetch + push) present; `origin` still points at `kevinpbuckley/VibeUE`.

- [ ] **Step 4: Push the existing feature branch to the fork**

Run:
```bash
git push -u fork feature/self-improve-pipeline
```
Expected: branch appears on `dry-eye/VibeUE`; upstream tracking set to `fork/feature/self-improve-pipeline`.

- [ ] **Step 5: Confirm tracking**

Run: `git branch -vv`
Expected: `feature/self-improve-pipeline` tracks `fork/feature/self-improve-pipeline`.

(No commit — this task only changes git remotes/tracking.)

---

## Task 2: Define the gap-record format and seed the gap-log

**Files:**
- Create: `Plugins/VibeUE/docs/self-improve/README.md`
- Create: `Plugins/VibeUE/docs/self-improve/gap-log.md`

- [ ] **Step 1: Write the gap-log README (format definition)**

Create `docs/self-improve/README.md` with exactly:
```markdown
# VibeUE Self-Improvement — Gap Log

This directory is written by the `vibeue-self-improve` Claude Code skill. Every
time the agent hits a "no suitable tool" gap during a VibeUE task and runs the
pipeline, it appends a record to `gap-log.md`.

## Gap record format

Each record is one section appended to `gap-log.md`:

​```
## GAP-<YYYYMMDD>-<n>: <short title>
- **Date:** YYYY-MM-DD
- **Intent:** what the agent was trying to accomplish
- **Searched:** skills checked (manage_skills) + discover_python_* queries run
- **Why no tool:** why nothing existing fit the intent
- **Tier:** skill | cpp | unresolved
- **Artifact:** path to the skill/section or C++ method, or issue link
- **Verified:** the live-run evidence observed in the editor
- **Commit:** <sha> (on the fork)
​```

`<n>` is a per-day counter starting at 1.

## Rules
- Records are append-only; never rewrite history.
- A record is only added after the resolution is verified live (or marked
  `unresolved` with an issue link).
- All commits referenced here are on the `fork` remote (`dry-eye/VibeUE`).
```

- [ ] **Step 2: Seed gap-log.md with a header and a worked example**

Create `docs/self-improve/gap-log.md` with exactly:
```markdown
# VibeUE Gap Log

Append-only. Format defined in `README.md`.

---

<!-- Example record (template — not a real gap). Real records appended below. -->
## GAP-00000000-0: (example) set actor folder path
- **Date:** 0000-00-00
- **Intent:** Move a spawned actor into a named outliner folder.
- **Searched:** manage_skills(list) → level-actors skill loaded, no folder method; discover_python_function(ActorService, "folder") → none.
- **Why no tool:** Neither the skill nor ActorService exposed folder assignment.
- **Tier:** skill
- **Artifact:** Content/Skills/level-actors/SKILL.md (added "Outliner folders" gotcha)
- **Verified:** Ran recipe live; actor appeared under folder "Test" in the outliner.
- **Commit:** 0000000

---
```

- [ ] **Step 3: Commit on the feature branch**

Run:
```bash
cd "M:/UnrealProjects/Game/Plugins/VibeUE"
git add docs/self-improve/README.md docs/self-improve/gap-log.md
git commit -F - <<'EOF'
docs: seed self-improve gap-log and format

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```
Expected: commit succeeds; `git log --oneline -1` shows the subject.

- [ ] **Step 4: Push to fork**

Run: `git push fork feature/self-improve-pipeline`
Expected: push succeeds.

---

## Task 3: Author the `vibeue-self-improve` orchestration skill

**Files:**
- Create: `C:\Users\Dry Eye\.claude\skills\vibeue-self-improve\SKILL.md`

- [ ] **Step 1: Load skill-authoring conventions**

Invoke the Skill tool: `superpowers:writing-skills`. Follow its frontmatter and
structure rules while writing Step 2.

- [ ] **Step 2: Write SKILL.md with exactly this content**

Create `C:\Users\Dry Eye\.claude\skills\vibeue-self-improve\SKILL.md`:
````markdown
---
name: vibeue-self-improve
description: Use when working on a VibeUE / Unreal Editor task and you hit a wall because no suitable tool exists — manage_skills has no relevant skill AND discover_python_* exposes no method for the intent. Resolves the gap in-session (research, experiment live, verify), then persists it to the VibeUE fork as a skill doc (autonomous) or, with explicit approval, a C++ service method + MCP tool.
---

# VibeUE Self-Improvement Pipeline

Gap-driven. You invoke this the moment a real VibeUE task is blocked because no
tool fits. Resolve it now, in this session, then resume the original task.

Fork: all writes go to the `fork` remote (`dry-eye/VibeUE`) of
`M:/UnrealProjects/Game/Plugins/VibeUE`. Never push to `origin` (upstream).

## Detection gate — only proceed if ALL THREE hold
1. `manage_skills(action="list")` has no relevant skill, OR the loaded skill does
   not cover the need.
2. `discover_python_class` / `discover_python_function` / `discover_python_module`
   exposes no documented method for the intent.
3. The task genuinely requires it (not a convenience shortcut).

If any fails: there is no gap — use the existing tool/skill instead.

## Phases
1. **DETECT** — gate passes → draft a gap record (see schema below). Do not commit
   it yet.
2. **RESEARCH** — introspect the live API with `discover_python_*`. If that is
   insufficient, use `deep_research` on the relevant UE Python API.
3. **EXPERIMENT** — iterate `execute_python_code` in the live editor until a recipe
   produces the expected, observable result. Use `read_logs` to diagnose failures.
4. **VERIFY (hard gate)** — run the recipe once more, clean, and confirm the
   artifact/effect actually exists. No live proof → do NOT persist. Never write a
   "should work" recipe into a skill.
5. **TIER** — always try the skill tier first. Escalate to the C++ tier ONLY when:
   (a) impossible from Python alone, (b) the recipe is too fragile/clumsy to be
   reliable, or (c) it is a recurring, high-value operation deserving a first-class
   tool.
6. **PERSIST**
   - *Skill tier (autonomous):* in the fork, add/extend `Content/Skills/<name>/`
     (`SKILL.md` + section), update keywords/index, commit, push to `fork`.
   - *C++ tier (approval-gated):* draft the `Source/VibeUE/Private/PythonAPI/`
     service-method + MCP-tool change, then STOP and ask the user for an explicit
     "go". On approval: edit C++, build (`& 'M:\UnrealProjects\Game\Plugins\VibeUE\BuildPlugin.bat'`
     or `& 'M:\UnrealProjects\Game\ProjectCompile.bat'`), restart the editor,
     reconnect MCP, live-verify the NEW tool, commit, push to `fork`.
7. **RESUME** — return to the user's original task using the new tool/skill.
8. **LOG** — append the finished gap record to `docs/self-improve/gap-log.md` in the
   fork (with the commit sha), commit, push.

## Autonomy
| Tier | Action | Gate |
|------|--------|------|
| Skill | write/commit a verified skill doc to the fork | autonomous |
| C++ | edit service/MCP, build, restart editor, commit | explicit "go" required first |

## Error handling
If EXPERIMENT cannot reach a working recipe within a reasonable attempt budget
(~5–8 focused iterations): mark the gap `unresolved`, tell the user, and draft a
feature-request issue (upstream `kevinpbuckley/VibeUE` or the fork) per the
CLAUDE.md MCP-capability-gap rule — do not file silently. Resume the task with a
best-effort workaround or ask the user.

## Gap record schema (append to gap-log.md)
```
## GAP-<YYYYMMDD>-<n>: <short title>
- **Date:** YYYY-MM-DD
- **Intent:** <what you were trying to accomplish>
- **Searched:** <skills checked + discover_python_* queries run>
- **Why no tool:** <why nothing fit>
- **Tier:** skill | cpp | unresolved
- **Artifact:** <path to skill/section or C++ method, or issue link>
- **Verified:** <live-run evidence observed>
- **Commit:** <sha on the fork>
```
````

- [ ] **Step 3: Verify the skill is discoverable and well-formed**

Run (Grep tool): pattern `^name: vibeue-self-improve$` in
`C:\Users\Dry Eye\.claude\skills\vibeue-self-improve\SKILL.md`.
Expected: one match (valid frontmatter `name`).

Then confirm the required headings exist — Grep pattern
`^## (Detection gate|Phases|Autonomy|Error handling|Gap record schema)` in the same
file. Expected: 5 matches.

- [ ] **Step 4: Verify the skill loads via the Skill tool**

Invoke the Skill tool with `vibeue-self-improve`.
Expected: the SKILL.md content is returned (skill is registered and loadable).

(No git commit — this file lives in user `.claude`, outside the fork, per the
confirmed design default.)

---

## Task 4: Dry-run the pipeline end-to-end on one real small gap

This validates the loop and the hard verification gate against the live editor.
Requires the Unreal Editor open with VibeUE connected.

**Files:**
- Possibly create/modify (in fork): `Content/Skills/<name>/SKILL.md`
- Append (in fork): `docs/self-improve/gap-log.md`

- [ ] **Step 1: Pick a genuine small gap**

Choose a real, low-risk operation you suspect lacks a documented tool (e.g. an
ActorService/outliner detail, a niche asset property). Run the detection gate:
`manage_skills(action="list")` + a `discover_python_function` query. Confirm all
three detection conditions hold. If the tool already exists, pick another gap.

- [ ] **Step 2: Run RESEARCH + EXPERIMENT**

Use `discover_python_*` then iterate `execute_python_code` until the recipe
produces the expected observable result. Capture the exact working snippet.

- [ ] **Step 3: VERIFY (hard gate)**

Re-run the recipe clean via `execute_python_code` and confirm the artifact/effect
exists (read it back). Record the observed evidence verbatim — this is what goes in
the `Verified:` field.

- [ ] **Step 4: PERSIST (skill tier) + LOG**

In the fork, add the gotcha/section to the relevant `Content/Skills/<name>/` and
append the gap record to `docs/self-improve/gap-log.md`. Commit:
```bash
cd "M:/UnrealProjects/Game/Plugins/VibeUE"
git add Content/Skills docs/self-improve/gap-log.md
git commit -F - <<'EOF'
feat(skills): dry-run gap resolution — <short title>

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
git push fork feature/self-improve-pipeline
```
Expected: commit + push succeed. Put the resulting sha in the record's `Commit:`
field (amend the record if needed).

- [ ] **Step 5: Confirm the produced skill is loadable**

Run `manage_skills(action="load", skill_name="<name>")`.
Expected: the new section/gotcha is present in the returned content.

---

## Task 5: Finalize — open the fork PR / branch summary

**Files:** none (git/GitHub only)

- [ ] **Step 1: Push final state**

Run: `git push fork feature/self-improve-pipeline`
Expected: fork branch up to date.

- [ ] **Step 2: Summarize for the user**

Report: fork URL (`https://github.com/dry-eye/VibeUE`), branch, the skill path, the
gap-log path, and the dry-run result. Ask whether to open a PR on the fork (for the
user's own review) or leave as a branch. Do NOT open any PR against upstream
`kevinpbuckley/VibeUE`.

---

## Self-Review

**Spec coverage:**
- §1 scope (in-session, reactive, single-gap) → Task 3 SKILL.md phases. ✓
- §3 detection gate (3 conditions) → Task 3 SKILL.md "Detection gate" + Task 4 Step 1. ✓
- §4 phases (DETECT→LOG) → Task 3 SKILL.md "Phases"; exercised in Task 4. ✓
- §5 error handling (unresolved + issue draft) → Task 3 SKILL.md "Error handling". ✓
- §6 autonomy (skill auto / C++ gated) → Task 3 SKILL.md "Autonomy". ✓
- §7 verification (live run) → Task 3 phase 4 + Task 4 Step 3 (hard gate). ✓
- §8 artifact locations (gap-log, Content/Skills, PythonAPI) → Task 2 + File Structure. ✓
- §9.1 skill location (user .claude) → Task 3 file path + "no commit" note. ✓
- §9.2 tier rule → Task 3 SKILL.md TIER phase. ✓
- §9.3 fork prerequisite (create fork, second remote, never upstream) → Task 1. ✓
- §10 implementation tasks (fork, author skill, gap-log, dry-run) → Tasks 1–4. ✓

**Placeholder scan:** No TBD/TODO. Runtime-produced artifacts (`<name>`, the dry-run
gap) are intentionally chosen at execution time — that is the nature of a
gap-driven pipeline, not a plan placeholder. The example gap-log record uses
all-zero IDs deliberately to mark it as a non-real template.

**Type consistency:** Gap-record schema is identical in the spec, the gap-log
README (Task 2 Step 1), and SKILL.md (Task 3). Remote name `fork`, branch
`feature/self-improve-pipeline`, and fork `dry-eye/VibeUE` are used consistently.
