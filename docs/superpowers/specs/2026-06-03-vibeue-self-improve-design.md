# VibeUE Self-Improvement Pipeline — Design

**Date:** 2026-06-03
**Status:** Approved (design); ready for implementation planning
**Author:** brainstorming session (user: layter000)

## 1. Purpose & Scope

A **gap-driven self-improvement pipeline** for the VibeUE MCP. It activates the
moment the agent, during a real Unreal task, hits a wall because **no suitable
tool exists** for what it needs. The pipeline resolves that gap **immediately, in
the same session**, proves the solution by **running it live in the editor**, and
**persists** the result into a **fork of VibeUE** that the user owns — as a skill
doc (autonomous) or as a C++ service method + MCP tool (gated on explicit
approval). The agent then resumes the original task with the now-existing tool.

### In scope (v1)
- In-session, reactive, single-gap resolution.
- Tiered persistence: skill doc first; C++ service/MCP tool when warranted.
- Hard live-verification gate before any persist.
- Autonomy split: skill writes autonomous; C++ changes require explicit "go".

### Out of scope (v1)
- Batch log-mining for gaps after the fact.
- Speculative auto-generation of whole new skills "just in case".
- The pipeline improving itself (meta loop).

## 2. Architecture

The pipeline is packaged as a **Claude Code skill** named `vibeue-self-improve`
(a Markdown procedure the agent invokes via the Skill tool). No new infrastructure
or MCP changes are required to run it. It orchestrates existing VibeUE MCP tools:

- `manage_skills` — discover/load/author skill docs.
- `discover_python_class` / `discover_python_function` / `discover_python_module` —
  introspect the live Unreal Python API surface.
- `execute_python_code` — experiment with and verify recipes in the live editor.
- `read_logs` — inspect editor/MCP errors during experimentation.
- `deep_research` — research UE Python APIs when introspection is insufficient.

### Component boundaries
| Unit | Responsibility | Depends on |
|------|----------------|------------|
| Detection gate | Decide a true tool gap exists | `manage_skills(list)`, `discover_python_*` |
| Research+Experiment loop | Reach a working Python recipe | `discover_python_*`, `deep_research`, `execute_python_code`, `read_logs` |
| Verification gate | Prove the recipe via a clean live run | `execute_python_code` |
| Tier decision | Choose skill vs C++ | recipe shape + reuse signal |
| Skill persistence | Write/commit skill doc to fork | filesystem + git (fork) |
| C++ persistence | Add service method + MCP tool, build, verify | C++ edit, `BuildPlugin`/`ProjectCompile`, editor restart, git (fork) |
| Gap log | Record outcomes (resolved + deferred) | git (fork) |

## 3. Detection Gate — what "no suitable tool" means

A gap is recorded **only when all three** hold:
1. `manage_skills(list)` has no relevant skill (or the loaded skill does not cover
   the need);
2. `discover_python_class/function/module` yields no documented method for the
   intent;
3. the task genuinely requires it (not a convenience shortcut).

This prevents premature triggering on tasks that are merely tedious.

## 4. Pipeline Phases

1. **DETECT** — gate (§3) passes → create a structured gap record (intent, what was
   searched, why nothing fit).
2. **RESEARCH** — introspect the live API via `discover_python_*`; if insufficient,
   `deep_research` the relevant UE Python API.
3. **EXPERIMENT** — iterate `execute_python_code` in the live editor until a recipe
   produces the expected, observable result.
4. **VERIFY (hard gate)** — clean re-run; confirm the artifact/effect exists. No
   proof → no persist. Never write "should work" recipes.
5. **TIER** — *always try the skill tier first.* Escalate to C++ only when:
   (a) the operation is impossible from Python alone, (b) the recipe is too
   fragile/clumsy to be reliable, or (c) it is a recurring, high-value operation
   that deserves a first-class tool.
6. **PERSIST**
   - *Skill (autonomous):* write `SKILL.md`/section in the fork, update keywords +
     index, commit to the fork.
   - *C++ (approval-gated):* draft the service-method + MCP-tool change → **pause,
     wait for explicit "go"** → edit C++, build (`BuildPlugin` / `ProjectCompile`),
     restart editor, reconnect MCP, live-verify the new tool, then commit to the
     fork.
7. **RESUME** — return to the user's original task using the new tool/skill.
8. **LOG** — append the outcome to the gap log in the fork.

## 5. Error Handling

If EXPERIMENT cannot reach a working recipe within a reasonable attempt budget:
- Record it as an **unresolved gap**.
- Notify the user, and per the CLAUDE.md MCP-capability-gap rule, draft a
  feature-request issue (upstream `kevinpbuckley/VibeUE`, or the fork) — do not
  file silently.
- Resume the original task with a best-effort workaround, or ask the user how to
  proceed.

No unverified recipe is ever written to a skill.

## 6. Autonomy & Approval

| Tier | Action | Gate |
|------|--------|------|
| Skill | Write/commit a verified skill doc to the fork | Autonomous |
| C++ | Edit service/MCP, build, restart editor, commit | Explicit "go" required before editing |

Rationale: knowledge writes are low-risk and reversible; C++ changes trigger a
recompile + editor restart + git history and must pause for human approval.

## 7. Verification Standard

A solution is "works" only after a **live run in the editor** via
`execute_python_code` that produces the expected observable result (asset created,
property set, etc.). For the C++ tier this extends to: successful build + live run
of the *new tool*. Automation tests are optional, not required, in v1.

## 8. Data & Artifact Locations (in the fork)

- **Gap log + resolution records:** `docs/self-improve/gap-log.md` (+ structured
  records) — versioned with the fork.
- **Skill docs:** `Content/Skills/<name>/` (existing `SKILL.md` + sections format).
- **C++ service methods:** `Source/VibeUE/Private/PythonAPI/`.

## 9. Confirmed Defaults

1. **Claude Code skill location:** user-level
   `C:\Users\Dry Eye\.claude\skills\vibeue-self-improve\` — not tied to one game
   project, since VibeUE is developed independently.
2. **Tier rule:** as stated in §4.5 (skill first; escalate to C++ only on the three
   conditions).
3. **Fork prerequisite:** the local plugin's `origin` is `kevinpbuckley/VibeUE`
   (upstream). The pipeline writes to a **fork the user owns**. Implementation must
   create that GitHub fork and add it as a second remote (e.g. `fork`); push only
   there, never to upstream.

## 10. Open Implementation Tasks (for the plan)

- Create the user's GitHub fork; add `fork` remote to the local plugin repo.
- Author the `vibeue-self-improve` Claude Code skill per superpowers:writing-skills
  conventions (procedure, gap-record schema, gate checklists).
- Define the structured gap-record format and seed `docs/self-improve/gap-log.md`.
- Dry-run the skill against one known/synthetic gap to validate the loop and the
  verification gate.
