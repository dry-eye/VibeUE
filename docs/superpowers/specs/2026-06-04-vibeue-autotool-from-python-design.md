# VibeUE Auto-Tool from Python — Design (self-improve v2)

**Date:** 2026-06-04
**Status:** Approved (design); ready for implementation planning
**Author:** brainstorming session (user: layter000)
**Extends:** `2026-06-03-vibeue-self-improve-design.md`

## 1. Purpose & Scope

Extend the self-improve pipeline's trigger from *"no способу взагалі"* to
*"довелось писати reusable raw Python"*, and add an **autonomous tail** that turns
recurring Python escape-hatch usage into a first-class MCP tool:
**classify → log candidate → generate C++ → shadow-build → deferred gated swap.**

The motivation: today the pipeline fires only when **no** tool/skill/Python method
exists. But "I had to drop to raw `execute_python_code`" is a weaker-but-real
signal that a permanent tool may be warranted. That signal is currently lost. v2
captures it and, for simple cases, closes the loop autonomously.

### In scope (v1 of this extension)
- Per-call **intent classification** (reusable vs one-off) on every
  `execute_python_code` use during a VibeUE task.
- A **tool-candidate queue** holding live-verified Python recipes + signature sketch.
- **Autonomous C++ generation limited to *simple wrappers*** (single Python-API
  call surfaced as one MCP tool). Anything more complex is logged as a candidate
  for manual implementation — not auto-generated.
- **Shadow-build isolation**: generated code is built in a separate worktree; the
  live plugin binary is never touched by an unverified build.
- **Deferred gated swap**: a green shadow-build is staged and applied only at the
  **next session start**, never via a surprise mid-session editor restart.

### Out of scope (v1)
- Auto-generation of complex/multi-step tools (logged for manual work instead).
- In-session use of a freshly generated tool (physically impossible: build +
  editor restart barrier — see §3).
- Auto-build *in-place* and auto-rollback (rejected in favour of shadow isolation).
- CI-gated builds (considered, deferred to a later iteration).

## 2. Why "in parallel, use immediately" is impossible

A dedicated tool is a C++ method in `Source/VibeUE/Private/PythonAPI/` plus MCP-tool
registration. It becomes callable only after **plugin build + editor restart**.
Therefore a tool generated mid-task **cannot help the current task** — the raw
Python escape-hatch exists precisely because tools cannot materialise instantly.
The realistic shape of the idea is *not* "auto-build and use now", but "capture the
usage, generate offline, make it available next session".

## 3. Decisions (locked in brainstorming)

| # | Decision | Choice | Consequence |
|---|----------|--------|-------------|
| 1 | Scope | Full auto-cycle (gen → shadow-build → swap → use next session) | No per-step human approval on the simple-wrapper path |
| 2 | Build isolation | **Shadow-build + gated swap** | Live MCP is physically untouched until an isolated build is green |
| 3 | Trigger | **Intent classification** (reusable vs one-off) | Auto-cycle only for reusable calls; **default to logging-only when uncertain** |
| 4 | Swap/restart timing | **At next session start** | Zero interruptions; no surprise restart; no PIE/work loss |

## 4. Architecture — six components

| Unit | Responsibility | Depends on |
|------|----------------|------------|
| Intent classifier | Per `execute_python_code` call, decide reusable vs one-off; if reusable AND uncovered by tool/skill → emit a candidate | model judgement; existing detection gate (`manage_skills`, `discover_python_*`) |
| Candidate queue | Persist pending candidates (intent, live-verified recipe, C++ signature sketch, complexity class) | filesystem (fork) |
| Generator | For a **simple-wrapper** candidate, generate C++ service method + MCP-tool registration **in a shadow worktree** | C++ templates; fork worktree |
| Shadow-build gate | Build the plugin in the shadow worktree; parse accounting/`Result:`; green → stage binary + swap manifest, red → discard + log | `ProjectCompile`/`BuildPlugin`; `[ProjectCompileAccounting]` |
| Gated swap launcher | At next editor start, apply staged source + binary to live fork checkout, then launch | SessionStart hook or `.bat` launcher wrapper |
| Gap log | Record each outcome (auto-resolved / red-build / manual-deferred) | git (fork) |

### Data flow

```
[during task] execute_python_code ──► Intent classifier
                                          │ reusable & uncovered?
                                 ┌────────┴────────┐
                              no │                 │ yes
                            (drop)                 ▼
                                          Candidate queue  ◄── live-verified recipe (hard gate)
                                                  │ complexity?
                                  ┌───────────────┴───────────────┐
                          simple wrapper                      complex
                                  ▼                               ▼
                            Generator (shadow worktree)     log for manual impl
                                  ▼
                            Shadow-build gate ──red──► discard + gap-log (keep Python recipe)
                                  │ green
                                  ▼
                            stage binary + swap manifest
                                  ▼
                   ── next session start ──► Gated swap launcher ──► tool live this session
```

## 5. Intent classification — definition of "reusable simple wrapper"

A candidate is **auto-generated** only when **all** hold:
1. **Reusable:** the operation is parameterised and likely to recur, not a one-off
   probe/iteration/exploration (e.g. a quick `discover` follow-up, a debug print).
2. **Uncovered:** no existing skill (`manage_skills(list)`) and no convenient
   dedicated tool already does it.
3. **Simple wrapper:** the recipe is effectively **one Python-API call** (plus
   trivial arg marshalling / return shaping) that can be surfaced as a single MCP
   tool with a flat signature. No multi-step orchestration, no stateful sequences,
   no branching control flow.

If (1) or (2) is uncertain → **log-only** (err toward not generating). If (3) fails
→ record as a **manual candidate**, never auto-generate.

## 6. Shadow-build + gated swap

- The generator writes C++ into a **shadow git worktree** of the fork, *not* the
  live `Plugins/VibeUE` working tree.
- The shadow worktree is built with the project's compile path; success is judged
  **only** by `PROPAGATED_EXITCODE == 0` + `Result: Succeeded` (the established
  accounting rule). A disagreeing host exit code is ignored.
- **Green:** stage the built module binary + a `pending-swap` manifest (source
  patch ref + binary path + candidate id) into a queue dir.
- **Red:** discard the generated C++ entirely; the candidate **reverts to its
  live-verified Python recipe** (which still works); append a red-build record to
  the gap log. The live binary is never altered.
- At **next session start**, the launcher checks the queue; for each green entry it
  applies the source change to the live fork checkout, swaps the binary, then
  launches the editor. The new tool is live for that session.

**Safety invariants:**
- A bad generation can never reach the live binary (shadow isolation).
- A red build degrades gracefully to "Python recipe still available".
- No surprise editor restarts (swap only at a natural session boundary).
- The **hard live-verification gate is preserved**: a recipe becomes a candidate
  only after it ran live in the editor and produced the observed result.

## 7. Error handling

- **Classifier false-positive** (logged a one-off as reusable): harmless — it sits
  in the candidate queue; the simple-wrapper gate and a human glance at the queue
  catch it before it ships. Bias is toward log-only, so over-generation is rare.
- **Classifier false-negative** (missed a reusable call): the call still worked via
  Python; the signal is simply lost this time — no regression vs today.
- **Generation produces non-compiling C++:** caught by the shadow-build gate →
  discarded → Python recipe retained → red-build logged.
- **Green build, but new tool misbehaves at runtime next session:** treated as a
  normal gap on the next run; the tool can be reverted in the fork.

## 8. Relationship to v1 autonomy gate (explicit reversal)

The v1 design (`§6` of the 2026-06-03 spec) states: *C++ service-method / MCP-tool
changes require an explicit human "go" before editing.* This extension **reverses
that for the simple-wrapper auto-cycle path**, replacing the *human-approval* gate
with a **shadow-build-green + deferred-swap** gate.

| Path | Gate (v1) | Gate (v2) |
|------|-----------|-----------|
| Skill doc | Autonomous | Autonomous (unchanged) |
| C++ — complex | Explicit "go" | Explicit "go" (unchanged; logged as manual candidate) |
| C++ — **simple wrapper** | Explicit "go" | **Autonomous**, gated by green shadow-build + next-session swap |

The project memory `project_vibeue_self_improve_pipeline.md` must be updated to
record this carve-out so the two specs do not contradict.

## 9. Artifact locations (in the fork)

- **Candidate queue:** `docs/self-improve/tool-candidates/` (one file per candidate;
  schema TBD in the plan: intent, recipe, signature sketch, complexity class, state).
- **Pending-swap queue:** a staging dir (path decided in the plan) holding green
  binaries + swap manifests.
- **Generated C++:** `Source/VibeUE/Private/PythonAPI/` (via shadow worktree).
- **Gap log:** `docs/self-improve/gap-log.md` — extended with auto-cycle outcome
  records (`GAP-<YYYYMMDD>-<n>`, resolution sha in a separate commit, as today).

## 10. Open implementation tasks (for the plan)

- Define the candidate-record schema and the pending-swap manifest schema.
- Specify the simple-wrapper detection heuristic concretely (what counts as "one
  API call + trivial marshalling") and the classifier prompt/checklist.
- Decide the shadow-worktree + build invocation mechanics and the green/red parse.
- Design the gated-swap launcher (SessionStart hook vs `.bat` wrapper) and the
  binary/source apply step.
- Extend the gap-log format for auto-cycle outcomes.
- Update `vibeue-self-improve` skill phases (DETECT…LOG) to add CLASSIFY, QUEUE,
  GENERATE(shadow), and SWAP, and to encode the simple-wrapper-only v1 limit.
- Update project memory to record the §8 carve-out.
- Dry-run end-to-end on one synthetic simple-wrapper candidate.
