# Tool-Candidate & Swap-Manifest Schema

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

## Swap manifest — staged at `Saved/SelfImprove/pending-swap/<id>.json`
```json
{
  "id": "CAND-20260604-1",
  "tool_name": "set_world_killz",
  "source_files": ["Source/VibeUE/Private/Tools/Generated/SetWorldKillZTool.cpp"],
  "binary_dir": "Binaries/Win64",
  "shadow_root": "M:/UnrealProjects/VibeUE-shadow",
  "build_result": "Succeeded",
  "built_at_marker": "<value passed in by caller; scripts never call Date.now>"
}
```

## Rules
- A candidate reaches `green`/`red` ONLY via `Build-ShadowTool.ps1` (real BuildPlugin run).
- `complexity: complex` is never auto-generated — left `state: manual` for a human.
- When uncertain whether reusable, the classifier writes NOTHING (log-only bias).
- **Paths use `/` as separator throughout** (works in PowerShell, Python, and UBT on Windows).
- **`binary_dir` is relative to BOTH roots:** the build output is at `<shadow_root>/<binary_dir>` and the applier copies it to `<plugin_root>/<binary_dir>` (same relative subpath under each). `source_files` entries are likewise relative to each root.
- **`built_at_marker` is set by `Build-ShadowTool.ps1`, not authored by hand** — there is no timestamp field in the YAML record (scripts never call Date.now).
- **`state: manual`** = a `complex` candidate handed off for a human to implement outside the auto-cycle; terminal (the pipeline takes no further action on it).
