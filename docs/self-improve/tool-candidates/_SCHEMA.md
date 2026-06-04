# Tool-Candidate & Pending-Build Schema

> **Revised 2026-06-04 (after Task 3):** the isolation model changed from
> shadow-build+swap to **in-place build + auto-rollback**. There is no pre-built
> binary to stage — the marker just points at the generated `.cpp` to build at the
> next editor-closed window. See spec §6.

## Candidate record — `CAND-<YYYYMMDD>-<n>.md`
One file per candidate. `<n>` = per-day counter from 1.

```yaml
id: CAND-20260604-1
date: 2026-06-04
intent: <one line — what reusable operation this is>
complexity: simple-wrapper | complex      # only simple-wrapper auto-generates
state: queued | generating | green | red | applied | manual | rejected
tool_name: <snake_case mcp tool name>      # e.g. set_world_killz
category: <ToolCategory, e.g. Level>
params:                                     # typed signature
  - { name: kill_z, type: float, required: true, desc: "Z height below which actors die" }
python_template: |                          # LIVE-VERIFIED body; {param} placeholders
  import unreal
  ws = unreal.VibeUEWorld.get_world_settings()
  ws.set_editor_property('kill_z', {kill_z})
  print('OK kill_z=' + str(ws.get_editor_property('kill_z')))
verified: <live-run evidence observed in editor>
resolution_commit: <sha on fork, filled at PERSIST>
```

## Pending-build marker — staged at `Game/Saved/SelfImprove/pending-build/<id>.json`
Written when a simple-wrapper `.cpp` is generated into the live tree; consumed by
`Apply-PendingBuild.ps1` at the next editor-closed window. Points at source to
build — there is NO pre-built binary (in-place build model, spec §6).
```json
{
  "id": "CAND-20260604-1",
  "tool_name": "set_world_killz",
  "generated_cpp": "Source/VibeUE/Private/Tools/Generated/SetWorldKillZTool.cpp",
  "build_target": "GameEditor",
  "build_config": "DebugGame",
  "state": "pending-build"
}
```

## Rules
- A candidate reaches `green`/`red` ONLY via a real in-place build (`Apply-PendingBuild.ps1` → `Build.bat <build_target> Win64 <build_config>`), judged by UBT `Result: Succeeded`.
- `complexity: complex` is never auto-generated — left `state: manual` for a human.
- When uncertain whether reusable, the classifier writes NOTHING (log-only bias).
- **Paths use `/` as separator throughout** (works in PowerShell, Python, and UBT on Windows).
- **`generated_cpp` is relative to the plugin root** (`M:/UnrealProjects/Game/Plugins/VibeUE`); it lives in the live tree, not a shadow copy.
- **`build_target` / `build_config` must match the live editor** (here `GameEditor` / `DebugGame`) so the rebuilt DLL loads. Confirmed live config in Task 3.
- **On red:** the applier runs `git checkout -- <generated_cpp>` (removing the bad source) and rebuilds the prior good state before launching the editor.
- **`state: manual`** = a `complex` candidate handed off for a human to implement outside the auto-cycle; terminal (the pipeline takes no further action on it).
