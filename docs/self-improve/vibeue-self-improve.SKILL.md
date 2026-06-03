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
