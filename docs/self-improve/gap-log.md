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

## GAP-20260606-1: author a Control Rig (FK + IK) for a skeletal mesh from Python
- **Date:** 2026-06-06
- **Intent:** Build an animator Control Rig (`ControlRigBlueprint`) for `SKM_KimodoSOMA` (77-bone humanoid) — FK on all bones + Two-Bone IK arms/legs with pole vectors + FK/IK switch + a master control hierarchy — to animate the character in Sequencer.
- **Searched:** manage_skills(list) — no control-rig skill (skeleton/animation-* only, none author a CR graph); discover_python_class(RigVMController / RigHierarchyController) — primitives exist (`add_unit_node`, `add_control`, `import_bones_from_skeletal_mesh`) but no high-level "generate biped rig"; reference `CR_UEFNMannyTatoolsRig` is a tool-generated content asset, the ThreepeatAnimTools C++ has no generator.
- **Why no tool:** No stock API generates a control rig; assembling one from RigVM primitives via raw `execute_python_code` is multi-step and full of crash/corruption traps (PerItem IK node access-violation, un-deletable CR assets, corrupt-CR editor-brick on load, control-offset stacking, value-contaminated global reads). Worth a verified, gotcha-laden skill doc.
- **Tier:** skill
- **Artifact:** Content/Skills/control-rig/SKILL.md (new)
- **Verified:** Live in UE 5.7 editor. Built `/KimodoTextToAnim/CR_KimodoSOMARig`: 76 controls, 139-node graph (BeginExecution → 61 FK Get/SetTransform pairs → 4 TwoBoneIKSimple). After `load_asset` reload: ALL 61 FK controls + 4 IK effectors verify on-bone (delta < 0.5); master controls global@z0 / root@z0 / body@z99.9; `compile_blueprint` clean; full execute chain confirmed. Offset recipe (`control offset = bone LOCAL transform`, fresh controls, parent-first) proven reload-stable on a 7-deep chain in an isolated test rig.
- **Commit:** e0110e9

---
