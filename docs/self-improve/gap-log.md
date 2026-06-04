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

## GAP-20260603-1: read/set per-level World Settings (KillZ)
- **Date:** 2026-06-03
- **Intent:** Read and set `KillZ` on the current level's World Settings (`AWorldSettings`), restoring the original after verification.
- **Searched:** manage_skills(list) — no "world-settings" skill; only engine-settings / project-settings (UDeveloperSettings, project-wide) and level-actors (ActorService). manage_skills(suggest "world settings killz gravity") → engine-settings / project-settings, neither targets AWorldSettings. discover_python_function(unreal.GameplayStatics.get_world_settings) → NOT_FOUND; discover_python_function(unreal.ActorService.get_world_settings) → NOT_FOUND. discover_python_class(EngineSettingsService/ProjectSettingsService/ActorService, filter "world") → no world-settings method.
- **Why no tool:** World Settings is per-level state on the hidden `AWorldSettings` actor, not a UDeveloperSettings config object; the engine/project settings services edit project-wide `DefaultGravityZ`, not this level's `KillZ`/`GlobalGravityZ`. ActorService only exposes generic get/set_property keyed by actor name, and AWorldSettings has no outliner name.
- **Tier:** skill
- **Artifact:** Content/Skills/level-actors/SKILL.md (added "Per-Level World Settings (`AWorldSettings`: KillZ, gravity, etc.)" section)
- **Verified:** Live in UE 5.7.4 editor (map GASModular_Example). `world.get_world_settings()` returned the level's `LyraWorldSettings` (isinstance unreal.WorldSettings == True). ORIGINAL kill_z = -1048575.0; after set -54321.0; clean re-run with fresh world/ws lookup read back -54321.0; restored to -1048575.0 (confirmed via fresh lookup). Level NOT saved.
- **Commit:** 086162b

---

## GAP-00000000-0: (example) auto-generated simple-wrapper tool
- **Date:** 0000-00-00
- **Intent:** (example) Surface a reusable one-call Python op (set World Settings KillZ) as a first-class MCP tool.
- **Searched:** manage_skills(list) — no tool wraps it; discover_python_* — only the raw editor-property call.
- **Why no tool:** Recurring simple-wrapper op had no dedicated MCP tool; kept dropping to execute_python_code.
- **Tier:** cpp
- **Auto-cycle:** generated-green(set_world_killz)
- **Tool name:** set_world_killz
- **Artifact:** Source/VibeUE/Private/Tools/Generated/SetWorldKillZTool.cpp
- **Verified:** (example) Built in-place green at editor-closed window; tool called live, KillZ read back correctly.
- **Commit:** 0000000

---
