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
- **In-place build with auto-rollback** (see §6, revised 2026-06-04 after Task 3):
  at the next editor-closed window, the generated `.cpp` is added to the live tree
  and the editor target is rebuilt in the live config; **green** keeps it, **red**
  rolls the `.cpp` back via `git checkout` and rebuilds the prior good state.
- **Deferred to next session start**: generation may happen mid-task, but the build
  (and therefore the tool going live) waits for the editor-closed boundary — never a
  surprise mid-session editor restart.

### Out of scope (v1)
- Auto-generation of complex/multi-step tools (logged for manual work instead).
- In-session use of a freshly generated tool (physically impossible: a UE plugin's
  editor module cannot rebuild while the editor holds its DLL — see §2/§6).
- **Shadow-worktree isolation** (originally chosen, but Task 3 found the plugin
  cannot build in isolation in this tree — `BuildPlugin.bat` is a host-project
  in-place build; see §6).
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
| 1 | Scope | Full auto-cycle (gen → build → use next session) | No per-step human approval on the simple-wrapper path |
| 2 | Build isolation | **In-place build + auto-rollback** (revised 2026-06-04; was shadow-build) | Build happens in the live tree at an editor-closed window; red rolls back via `git checkout` + rebuild. Plugin can't build isolated here (Task 3) |
| 3 | Trigger | **Intent classification** (reusable vs one-off) | Auto-cycle only for reusable calls; **default to logging-only when uncertain** |
| 4 | Build/restart timing | **At next session start (editor closed)** | Zero interruptions; build+go-live collapse into the one window the editor is already down |

## 4. Architecture — six components

| Unit | Responsibility | Depends on |
|------|----------------|------------|
| Intent classifier | Per `execute_python_code` call, decide reusable vs one-off; if reusable AND uncovered by tool/skill → emit a candidate | model judgement; existing detection gate (`manage_skills`, `discover_python_*`) |
| Candidate queue | Persist pending candidates (intent, live-verified recipe, C++ signature sketch, complexity class) | filesystem (fork) |
| Generator | For a **simple-wrapper** candidate, write the C++ tool registration `.cpp` into the live tree (`Source/VibeUE/Private/Tools/Generated/`) | C++ template (`REGISTER_VIBEUE_TOOL`) |
| In-place build + rollback gate | At an editor-closed window, rebuild the editor target (live config) with the generated `.cpp` present; parse `Result: Succeeded`; **green** → keep + commit, **red** → `git checkout` the `.cpp` + rebuild prior good state + log | `Build.bat <Project>Editor Win64 <Config>` (UBT); `Result: Succeeded` |
| Session-start launcher | Ensure editor closed → run the build gate for each pending candidate → green commit / red rollback → launch editor | SessionStart hook or `.bat` launcher wrapper |
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
                   Generator → .cpp in live tree            log for manual impl
                                  │ (pending build marker)
                   ── next session start (editor closed) ──► In-place build gate
                                  │
                    ┌─────────────┴─────────────┐
                  red │                         │ green
                      ▼                         ▼
        git checkout .cpp + rebuild      keep .cpp + commit to fork
        prior good state; gap-log;              │
        keep Python recipe                      ▼
                      │                  launch editor ──► tool live this session
                      ▼
               launch editor (prior good binaries)
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

## 6. In-place build + auto-rollback (revised 2026-06-04 after Task 3)

**Why not shadow isolation (original plan):** Task 3 established that in this tree a
VibeUE build is a **host-project in-place build** — `BuildPlugin.bat` walks up to
`Game.uproject` and runs `Build.bat GameEditor` (UBT), writing the plugin DLL
in-place. A UE plugin's editor module cannot be compiled in isolation against a
bare engine without risk, and the live editor runs a specific config (**DebugGame**)
the build must match. `VibeUE.Build.cs` has **no project-module dependencies**, so a
standalone UAT `BuildPlugin` was theoretically possible, but it builds Development
against the bare engine — config-mismatched with the live DebugGame editor and not
worth the fragility. Since the build **and** the go-live both require the editor
closed anyway, isolation buys little. Chosen model: build in place, roll back on red.

- The generator writes the tool `.cpp` into the **live tree** at
  `Source/VibeUE/Private/Tools/Generated/` and records a *pending-build* marker for
  the candidate. The live MCP keeps running on the old binary until the next build.
- At the **next session start, with the editor closed**, the launcher rebuilds the
  editor target in the live config:
  `Build.bat <Project>Editor Win64 <Config> "<...>.uproject" -waitmutex`.
  Success is judged **only** by UBT `Result: Succeeded` (the `BuildPlugin.bat` banner
  is unreliable; the script captures stdout itself — there is no fixed log file).
- **Green:** keep the `.cpp`; the freshly built DLL is already the live binary;
  commit the source to the fork. Launch the editor — the new tool is live.
- **Red:** `git checkout -- <generated.cpp>` (and/or delete it) to remove the bad
  source, **rebuild the prior good state** so the editor can still launch, append a
  red-build record to the gap log, and **keep the candidate's live-verified Python
  recipe** as the working fallback. Launch the editor on the restored binary.

**Safety invariants:**
- The build runs only when the editor is closed — the live MCP is down during the
  one window its binary changes, so no half-swapped running editor.
- A red build is recovered by rolling the `.cpp` back and rebuilding the prior good
  state; the candidate degrades gracefully to "Python recipe still available".
- No surprise editor restarts (build happens at a natural editor-closed boundary).
- The **hard live-verification gate is preserved**: a recipe becomes a candidate
  only after it ran live in the editor and produced the observed result.
- **Residual risk (accepted):** unlike shadow isolation, a red build temporarily
  leaves the live tree non-building until rollback+rebuild completes. The launcher
  must always finish with a green editor target before launching.

## 7. Error handling

- **Classifier false-positive** (logged a one-off as reusable): harmless — it sits
  in the candidate queue; the simple-wrapper gate and a human glance at the queue
  catch it before it ships. Bias is toward log-only, so over-generation is rare.
- **Classifier false-negative** (missed a reusable call): the call still worked via
  Python; the signal is simply lost this time — no regression vs today.
- **Generation produces non-compiling C++:** caught by the in-place build gate
  (red) → `.cpp` rolled back via `git checkout` + prior good state rebuilt →
  Python recipe retained → red-build logged.
- **Green build, but new tool misbehaves at runtime next session:** treated as a
  normal gap on the next run; the tool can be reverted in the fork.

## 8. Relationship to v1 autonomy gate (explicit reversal)

The v1 design (`§6` of the 2026-06-03 spec) states: *C++ service-method / MCP-tool
changes require an explicit human "go" before editing.* This extension **reverses
that for the simple-wrapper auto-cycle path**, replacing the *human-approval* gate
with an **in-place-build-green + auto-rollback** gate at the editor-closed boundary.

| Path | Gate (v1) | Gate (v2) |
|------|-----------|-----------|
| Skill doc | Autonomous | Autonomous (unchanged) |
| C++ — complex | Explicit "go" | Explicit "go" (unchanged; logged as manual candidate) |
| C++ — **simple wrapper** | Explicit "go" | **Autonomous**, gated by green in-place build (red auto-rolls-back) at next session start |

The project memory `project_vibeue_self_improve_pipeline.md` must be updated to
record this carve-out so the two specs do not contradict.

## 9. Artifact locations (in the fork)

- **Candidate queue:** `docs/self-improve/tool-candidates/` (one file per candidate;
  schema in `_SCHEMA.md`: intent, recipe, signature sketch, complexity class, state).
- **Pending-build queue:** a gitignored staging dir (`Game/Saved/SelfImprove/pending-build/`)
  holding one marker per candidate awaiting the next editor-closed build — a pointer
  to the generated `.cpp`, not a pre-built binary.
- **Generated C++:** `Source/VibeUE/Private/Tools/Generated/` (in the live tree).
- **Gap log:** `docs/self-improve/gap-log.md` — extended with auto-cycle outcome
  records (`GAP-<YYYYMMDD>-<n>`, resolution sha in a separate commit, as today).

## 10. Open implementation tasks (for the plan)

- Define the candidate-record schema and the pending-swap manifest schema.
- Specify the simple-wrapper detection heuristic concretely (what counts as "one
  API call + trivial marshalling") and the classifier prompt/checklist.
- Decide the in-place build invocation (`Build.bat <Project>Editor Win64 <Config>`)
  and the `Result: Succeeded` parse; the rollback (`git checkout` + rebuild) path.
- Design the session-start launcher (SessionStart hook vs `.bat` wrapper) that runs
  the build gate with the editor closed and launches on green.
- Extend the gap-log format for auto-cycle outcomes.
- Update `vibeue-self-improve` skill phases (DETECT…LOG) to add CLASSIFY, QUEUE,
  GENERATE, and BUILD, and to encode the simple-wrapper-only v1 limit.
- Update project memory to record the §8 carve-out.
- Dry-run end-to-end on one synthetic simple-wrapper candidate.
