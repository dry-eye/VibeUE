# VibeUE Auto-Tool from Python — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the `vibeue-self-improve` pipeline so that recurring raw-`execute_python_code` usage is classified, queued as a tool candidate, and — for *simple wrappers* only — autonomously turned into a first-class MCP tool that is built in an isolated shadow worktree and applied via a deferred gated swap at the next session start.

**Architecture:** A generated "simple wrapper" is a single `.cpp` using the existing `REGISTER_VIBEUE_TOOL(...)` macro whose lambda substitutes typed params into a *live-verified* Python template and runs it through `FPythonExecutionService::ExecuteCode`. Generation happens in a `git worktree` clone of the fork; the live plugin binary is never touched until an isolated `BuildPlugin` run is green. A green build is staged (binary + manifest) and applied by a launcher at the next editor start. No code logic is reimplemented in C++ — the verified Python body is the payload.

**Tech Stack:** Unreal Engine 5.7 C++ plugin (`REGISTER_VIBEUE_TOOL`, `FPythonExecutionService`), PowerShell 5.1 scripts, git (fork remote `dry-eye/VibeUE`), Markdown skill + gap-log.

---

## Decisions locked (from spec §3)

1. Full auto-cycle, no per-step human approval **on the simple-wrapper path only**.
2. Shadow-build + gated swap (live MCP untouched until isolated build green).
3. Trigger = intent classification (reusable vs one-off); **default to log-only when uncertain**.
4. Swap/restart at **next session start** (no surprise restart).
5. v1: auto-generate **simple wrappers only** (one Python-API call + trivial marshalling); complex → manual candidate.

## File Structure

| Path | Responsibility | New? |
|------|----------------|------|
| `~/.claude/skills/vibeue-self-improve/SKILL.md` | Live skill: add CLASSIFY / QUEUE / GENERATE(shadow) / SWAP phases + v1 limit | modify |
| `docs/self-improve/vibeue-self-improve.SKILL.md` (fork) | Versioned snapshot kept in sync | modify |
| `docs/self-improve/tool-candidates/_SCHEMA.md` (fork) | Candidate-record + swap-manifest schema | create |
| `docs/self-improve/tool-candidates/` (fork) | One file per pending candidate | create (dir) |
| `docs/self-improve/templates/simple-wrapper.cpp.tmpl` (fork) | Canonical generated-tool template | create |
| `Scripts/SelfImprove/Build-ShadowTool.ps1` (fork) | Make/refresh shadow worktree, write tool .cpp, run BuildPlugin, parse result, stage-or-discard | create |
| `Scripts/SelfImprove/Apply-PendingSwap.ps1` (fork) | At session start: apply staged binary+source to live checkout, clear queue | create |
| `docs/self-improve/gap-log.md` (fork) | Extended with auto-cycle outcome fields | modify |
| `project_vibeue_self_improve_pipeline.md` (memory) | Record §8 approval-gate carve-out | modify |

**Out-of-repo runtime paths** (gitignored / siblings, decided here so tasks agree):
- Shadow worktree: `M:\UnrealProjects\VibeUE-shadow` (sibling of `Game`, so the editor never scans it).
- Pending-swap staging: `M:\UnrealProjects\Game\Saved\SelfImprove\pending-swap\` (`Saved/` is gitignored).

---

## Task 1: Candidate-record + swap-manifest schema

**Files:**
- Create: `docs/self-improve/tool-candidates/_SCHEMA.md`
- Create (placeholder): `docs/self-improve/tool-candidates/.gitkeep`

- [ ] **Step 1: Write the schema doc**

Create `docs/self-improve/tool-candidates/_SCHEMA.md` with exactly:

````markdown
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
````

- [ ] **Step 2: Add the keep file and commit**

```powershell
New-Item -ItemType File 'M:\UnrealProjects\Game\Plugins\VibeUE\docs\self-improve\tool-candidates\.gitkeep'
cd 'M:\UnrealProjects\Game\Plugins\VibeUE'
git add docs/self-improve/tool-candidates/_SCHEMA.md docs/self-improve/tool-candidates/.gitkeep
git commit -m "feat(self-improve): candidate-record and swap-manifest schema"
```

- [ ] **Step 3: Verify** — `git show --stat HEAD` lists both files; `_SCHEMA.md` opens and the YAML block parses by eye (no tabs, valid keys).

---

## Task 2: Canonical simple-wrapper tool template

**Files:**
- Create: `docs/self-improve/templates/simple-wrapper.cpp.tmpl`

This is the exact shape the generator emits. It mirrors the verified pattern in `Source/VibeUE/Private/Tools/LogReaderToolsRegistration.cpp` (`REGISTER_VIBEUE_TOOL` + `TOOL_PARAMS` + lambda returning `FString`) and runs the candidate's Python via `FPythonExecutionService::ExecuteCode`.

- [ ] **Step 1: Write the template**

Create `docs/self-improve/templates/simple-wrapper.cpp.tmpl` with exactly:

```cpp
// Copyright Buckley Builds LLC 2026 All Rights Reserved.
// GENERATED by vibeue-self-improve (simple-wrapper). Candidate: {{CAND_ID}}
// Payload Python was live-verified before generation. Do not hand-edit; regenerate.

#include "Core/ToolRegistry.h"
#include "Tools/PythonExecutionService.h"
#include "Core/ServiceContext.h"
#include "Json.h"

// {{CAND_ID}}: {{INTENT}}
REGISTER_VIBEUE_TOOL({{TOOL_NAME}},
    "{{TOOL_DESCRIPTION}}",
    "{{TOOL_CATEGORY}}",
    TOOL_PARAMS(
        {{TOOL_PARAM_LINES}}   // e.g. TOOL_PARAM("kill_z", "Z height...", "number", true)
    ),
    {
        // 1. Marshal typed params into the verified Python template.
        FString Code = TEXT(R"PY({{PYTHON_TEMPLATE}})PY");
        {{PARAM_SUBSTITUTIONS}}  // e.g. Code = Code.Replace(TEXT("{kill_z}"), *Params.FindRef(TEXT("kill_z")));

        // 2. Run it through the live Python bridge.
        auto Ctx = MakeShared<FServiceContext>();
        VibeUE::FPythonExecutionService Py(Ctx);
        auto Result = Py.ExecuteCode(Code, EPythonFileExecutionScope::Private, 30000);

        // 3. Shape a JSON response.
        TSharedPtr<FJsonObject> Out = MakeShared<FJsonObject>();
        const bool bOk = Result.IsSuccess();
        Out->SetBoolField(TEXT("success"), bOk);
        Out->SetStringField(TEXT("output"), bOk ? Result.GetValue().Output : Result.GetError().Message);
        FString Json;
        TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&Json);
        FJsonSerializer::Serialize(Out.ToSharedRef(), Writer);
        return Json;
    }
);
```

- [ ] **Step 2: Hand-fill a smoke instance and confirm it matches the macro grammar**

By eye, substitute the `set_world_killz` example from `_SCHEMA.md` into the template. Confirm: one `TOOL_PARAM(...)` per param, the `R"PY(...)PY"` raw string holds the Python verbatim, every `{param}` has a matching `Code.Replace`. Do NOT compile yet (compilation is Task 4 via shadow build).

- [ ] **Step 3: Commit**

```powershell
cd 'M:\UnrealProjects\Game\Plugins\VibeUE'
git add docs/self-improve/templates/simple-wrapper.cpp.tmpl
git commit -m "feat(self-improve): canonical simple-wrapper tool template"
```

> ⚠️ **Field-verify during Task 4, not now:** the exact spelling of `Result.IsSuccess()/GetValue().Output/GetError().Message`, `EPythonFileExecutionScope::Private`, and the `REGISTER_VIBEUE_TOOL` arg order are taken from headers (`PythonExecutionService.h`, `ToolMacros.h`) and `LogReaderToolsRegistration.cpp`. The shadow build in Task 4 is the real check; fix the template there if the compiler disagrees.

---

## Task 3: Verify how `BuildPlugin.bat` builds (verify-first, no assumption)

The whole shadow-build idea hinges on building the plugin **in isolation**. We do not yet know whether `BuildPlugin.bat` is a standalone UAT `BuildPlugin` (compiles against the engine without the game) or needs the host project. This task establishes the ground truth before any script depends on it.

**Files:** none (investigation + notes into the plan's Task 4).

- [ ] **Step 1: Read the batch**

Read `Plugins/VibeUE/BuildPlugin.bat` (use the Read tool). Identify: does it call `RunUAT BuildPlugin -Plugin=... -Package=...` (standalone) or `Build.bat LyraEditor` (host-project)? Note the success marker it prints and the output binary location.

- [ ] **Step 2: Run it once against the live plugin, capture the signal**

```powershell
& 'M:\UnrealProjects\Game\Plugins\VibeUE\BuildPlugin.bat'
```
Record: the exact success string (e.g. `BUILD SUCCESSFUL` / `Result: Succeeded`) and the host exit code. This string is the green/red gate used in Task 4.

- [ ] **Step 3: Decide the shadow-build invocation and write it into Task 4**

- If **standalone UAT**: shadow build = run the same UAT `BuildPlugin` with `-Plugin=<shadow>/VibeUE.uplugin -Package=<temp>`. The worktree-only approach works.
- If **host-project**: a plugin can't build alone. Fallback: shadow build = copy the plugin into a *throwaway copy of the game project*, or build the live tree but to an alternate output and gate the binary swap. **If this fallback is needed, STOP and report** — it changes the isolation model in spec §6 and needs a design note + user nod before continuing.

- [ ] **Step 4: Record the finding** as a comment block at the top of `Build-ShadowTool.ps1` in Task 4 (build command + success marker).

---

## Task 4: `Build-ShadowTool.ps1` — shadow worktree, build, gate, stage

**Files:**
- Create: `Scripts/SelfImprove/Build-ShadowTool.ps1`

Behavior: given a candidate id + a generated `.cpp` path (in the live tree's `Source/VibeUE/Private/Tools/Generated/`), it (1) creates/refreshes a git worktree of the fork at the shadow root, (2) ensures the generated `.cpp` is present there, (3) runs the build command from Task 3, (4) parses the success marker, (5) green → stage binary + write swap manifest; red → delete the generated `.cpp` from the live tree and write a red record.

- [ ] **Step 1: Write the script**

Create `Scripts/SelfImprove/Build-ShadowTool.ps1`:

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$CandidateId,
    [Parameter(Mandatory)] [string]$GeneratedCpp,   # path RELATIVE to plugin root
    [string]$PluginRoot = 'M:\UnrealProjects\Game\Plugins\VibeUE',
    [string]$ShadowRoot = 'M:\UnrealProjects\VibeUE-shadow',
    [string]$StageDir   = 'M:\UnrealProjects\Game\Saved\SelfImprove\pending-swap'
)
$ErrorActionPreference = 'Stop'

# --- Build command + success marker: SET FROM TASK 3 FINDINGS ---
$SuccessMarker = 'Result: Succeeded'   # <-- replace with the exact string Task 3 recorded
function Invoke-ShadowBuild { param($Root)
    & "$Root\BuildPlugin.bat"          # <-- replace with the standalone UAT call if Task 3 said so
    return $LASTEXITCODE
}

# 1. Make/refresh the shadow worktree of the CURRENT branch.
$branch = (& git -C $PluginRoot rev-parse --abbrev-ref HEAD).Trim()
if (-not (Test-Path $ShadowRoot)) {
    & git -C $PluginRoot worktree add $ShadowRoot $branch
} else {
    & git -C $ShadowRoot checkout $branch
    & git -C $ShadowRoot reset --hard $branch
}

# 2. Copy the generated .cpp into the shadow tree (it lives in the live tree pre-build).
$src = Join-Path $PluginRoot $GeneratedCpp
$dst = Join-Path $ShadowRoot $GeneratedCpp
New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
Copy-Item $src $dst -Force

# 3. Build the shadow tree.
$exit = Invoke-ShadowBuild -Root $ShadowRoot
$log  = Get-Content "$ShadowRoot\Saved\Logs\BuildPlugin.log" -Raw -ErrorAction SilentlyContinue
$green = ($log -and $log.Contains($SuccessMarker))

# 4. Gate.
New-Item -ItemType Directory -Force $StageDir | Out-Null
if ($green) {
    $manifest = [pscustomobject]@{
        id = $CandidateId; tool_name = $CandidateId
        source_files = @($GeneratedCpp); binary_dir = 'Binaries\Win64'
        shadow_root = $ShadowRoot; build_result = 'Succeeded'
    }
    $manifest | ConvertTo-Json | Set-Content "$StageDir\$CandidateId.json" -Encoding utf8
    Write-Output "GREEN $CandidateId"
} else {
    Remove-Item $src -Force -ErrorAction SilentlyContinue   # revert live tree to Python-only
    Write-Output "RED $CandidateId (exit=$exit)"
}
```

- [ ] **Step 2: Test GREEN path against the unmodified plugin**

```powershell
& 'M:\...\Build-ShadowTool.ps1' -CandidateId TEST-GREEN -GeneratedCpp 'Source/VibeUE/Private/Tools/Generated/_noop.cpp'
```
First create `Generated/_noop.cpp` containing only a comment (compiles, registers nothing).
Expected: prints `GREEN TEST-GREEN`; a manifest `Saved/SelfImprove/pending-swap/TEST-GREEN.json` exists. Live MCP unaffected (we never swapped).

- [ ] **Step 3: Test RED path with a deliberately-broken .cpp**

Create `Generated/_broken.cpp` with `#error forced red`. Run the script with that file.
Expected: prints `RED TEST-GREEN (exit=...)`; no manifest written; `Generated/_broken.cpp` deleted from the live tree (verify `Test-Path` is `$false`). **Live MCP still up** — confirm by calling any `mcp__vibeue__manage_asset(action='help')`.

- [ ] **Step 4: Clean up test artifacts and commit the script**

```powershell
Remove-Item 'M:\UnrealProjects\Game\Saved\SelfImprove\pending-swap\TEST-GREEN.json' -ErrorAction SilentlyContinue
cd 'M:\UnrealProjects\Game\Plugins\VibeUE'
git add Scripts/SelfImprove/Build-ShadowTool.ps1
git commit -m "feat(self-improve): shadow-build script with green/red gate"
```

---

## Task 5: `Apply-PendingSwap.ps1` — deferred gated swap at session start

**Files:**
- Create: `Scripts/SelfImprove/Apply-PendingSwap.ps1`

Behavior: at the next editor start, for each manifest in the staging dir: copy the shadow-built binary over the live `Binaries/Win64`, ensure the generated source is committed to the live fork checkout, then remove the manifest. Editor must be **closed** when this runs (it replaces a loaded DLL).

- [ ] **Step 1: Write the script**

Create `Scripts/SelfImprove/Apply-PendingSwap.ps1`:

```powershell
[CmdletBinding()]
param(
    [string]$PluginRoot = 'M:\UnrealProjects\Game\Plugins\VibeUE',
    [string]$StageDir   = 'M:\UnrealProjects\Game\Saved\SelfImprove\pending-swap'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $StageDir)) { Write-Output 'no pending swaps'; return }

# Refuse to run while the editor holds the DLL.
if (Get-Process -Name 'UnrealEditor' -ErrorAction SilentlyContinue) {
    throw 'UnrealEditor is running; close it before applying a swap.'
}

foreach ($m in Get-ChildItem "$StageDir\*.json") {
    $man = Get-Content $m -Raw | ConvertFrom-Json
    # 1. Swap the built binary into the live plugin.
    Copy-Item "$($man.shadow_root)\$($man.binary_dir)\*" "$PluginRoot\$($man.binary_dir)\" -Recurse -Force
    # 2. Make sure the generated source is in the live tree + committed on the fork branch.
    foreach ($f in $man.source_files) {
        Copy-Item "$($man.shadow_root)\$f" "$PluginRoot\$f" -Force
        & git -C $PluginRoot add $f
    }
    & git -C $PluginRoot commit -m "feat(self-improve): apply generated tool $($man.tool_name) [$($man.id)]"
    # 3. Done — clear the manifest.
    Remove-Item $m -Force
    Write-Output "APPLIED $($man.id)"
}
```

- [ ] **Step 2: Test apply with the `_noop` GREEN manifest from Task 4**

Re-stage `TEST-GREEN.json` (re-run Task 4 Step 2). Ensure the editor is closed. Run:
```powershell
& 'M:\...\Apply-PendingSwap.ps1'
```
Expected: prints `APPLIED TEST-GREEN`; manifest removed; a commit exists on the fork branch adding `Generated/_noop.cpp`. (No real tool registered — `_noop` is empty — so nothing to call; success = clean apply + cleared queue.)

- [ ] **Step 3: Test the running-editor guard**

With the editor open, run the script. Expected: throws `UnrealEditor is running; close it before applying a swap.` and changes nothing.

- [ ] **Step 4: Commit**

```powershell
cd 'M:\UnrealProjects\Game\Plugins\VibeUE'
git add Scripts/SelfImprove/Apply-PendingSwap.ps1
git commit -m "feat(self-improve): deferred gated-swap applier"
```

> **Hook wiring is deferred:** whether `Apply-PendingSwap.ps1` is invoked by a Claude Code SessionStart hook or by the user's editor-launch `.bat` is decided when we wire it (Task 9 dry-run uses it manually first). The script is safe to call unconditionally — it no-ops with `no pending swaps`.

---

## Task 6: Add CLASSIFY / QUEUE / GENERATE / SWAP to the skill

**Files:**
- Modify: `~/.claude/skills/vibeue-self-improve/SKILL.md`
- Modify: `docs/self-improve/vibeue-self-improve.SKILL.md` (snapshot — keep identical)

- [ ] **Step 1: Insert a CLASSIFY rule after the Detection gate**

Add this block to the live skill, right after the `## Detection gate` section:

```markdown
## Classify every raw-Python use (v2)
Whenever you fall back to `execute_python_code` during a task, after it is
LIVE-VERIFIED, classify it:
- **one-off** (probe, debug print, exploration, single-asset fixup) → do nothing.
- **reusable** (parameterised, likely to recur) AND uncovered by any tool/skill:
  - **simple wrapper** (≈ one Python-API call + trivial marshalling, flat
    signature) → write a `CAND-…` record (schema: tool-candidates/_SCHEMA.md),
    `complexity: simple-wrapper`, `state: queued`.
  - **complex** (multi-step, stateful, branching) → write the record with
    `complexity: complex`, `state: manual`. Do NOT auto-generate.
- **When unsure if reusable → write nothing** (log-only bias).
```

- [ ] **Step 2: Add GENERATE + SWAP phases**

Append to the `## Phases` list:

```markdown
9. **GENERATE (simple-wrapper only, autonomous)** — fill
   `templates/simple-wrapper.cpp.tmpl` from the candidate into
   `Source/VibeUE/Private/Tools/Generated/<Name>Tool.cpp`. Run
   `Scripts/SelfImprove/Build-ShadowTool.ps1 -CandidateId <id> -GeneratedCpp <path>`.
   GREEN → set candidate `state: green`, manifest staged. RED → `state: red`,
   keep the Python recipe, append a red record to the gap log. The live MCP is
   never touched either way.
10. **SWAP (next session start)** — `Scripts/SelfImprove/Apply-PendingSwap.ps1`
    runs with the editor closed, swaps the binary, commits the source to the
    fork, clears the manifest. The new tool is live this session.
```

- [ ] **Step 3: Update the autonomy table for the carve-out**

Replace the `## Autonomy` table with:

```markdown
## Autonomy
| Tier | Action | Gate |
|------|--------|------|
| Skill | write/commit a verified skill doc to the fork | autonomous |
| C++ — simple wrapper | generate, shadow-build, deferred swap | autonomous (gated by green build + next-session swap) |
| C++ — complex | edit service/MCP, build, restart editor, commit | explicit "go" required first |
```

- [ ] **Step 4: Sync the snapshot and commit**

Copy the live skill over the fork snapshot so they are byte-identical, then:
```powershell
cd 'M:\UnrealProjects\Game\Plugins\VibeUE'
git add docs/self-improve/vibeue-self-improve.SKILL.md
git commit -m "feat(self-improve): skill v2 — classify, generate (shadow), deferred swap"
```

- [ ] **Step 5: Verify** — the live `SKILL.md` and the fork snapshot are identical (`git diff --no-index` between them reports no differences).

---

## Task 7: Extend the gap-log format for auto-cycle outcomes

**Files:**
- Modify: `docs/self-improve/gap-log.md`
- Modify: `docs/self-improve/README.md`

- [ ] **Step 1: Add the auto-cycle fields to the README format block**

In `README.md`, under the gap record format, add:
```text
- **Auto-cycle:** none | candidate(<id>) | generated-green(<tool>) | generated-red(<reason>)
- **Tool name:** <mcp tool name, if a wrapper was generated>
```

- [ ] **Step 2: Add an example auto-cycle record to gap-log.md**

Append one illustrative record (clearly marked `(example)`, date `0000-00-00`) showing `Tier: cpp`, `Auto-cycle: generated-green(set_world_killz)`.

- [ ] **Step 3: Commit**

```powershell
cd 'M:\UnrealProjects\Game\Plugins\VibeUE'
git add docs/self-improve/gap-log.md docs/self-improve/README.md
git commit -m "docs(self-improve): gap-log auto-cycle outcome fields"
```

---

## Task 8: Record the approval-gate carve-out in project memory

**Files:**
- Modify: `C:\Users\Dry Eye\.claude\projects\M--UnrealProjects-Game\memory\project_vibeue_self_improve_pipeline.md`
- Modify: `...\memory\MEMORY.md` (pointer line only if hook text changes)

- [ ] **Step 1: Amend the Autonomy bullet**

Change the memory's autonomy line from "C++ … are **approval-gated**" to record the v2 carve-out:
> Autonomy: skill-tier autonomous; **simple-wrapper C++ tools auto-generated via shadow-build + deferred next-session swap (no human gate)**; complex C++ service-method changes remain approval-gated. See spec `2026-06-04-vibeue-autotool-from-python-design.md`.

- [ ] **Step 2: Verify** — re-reading the memory shows no contradiction with the v1 line; the carve-out is explicit. (Memory files are not committed to the fork; this is a local `.claude` write.)

---

## Task 9: End-to-end dry run on one real simple-wrapper candidate

**Files:** none new (exercises the whole pipeline).

- [ ] **Step 1: Pick a real candidate** — use a genuinely reusable one-API-call op not yet covered by a tool (e.g. the `set_world_killz` from the KillZ gap GAP-20260603-1). Write its `CAND-…` record per `_SCHEMA.md`.

- [ ] **Step 2: GENERATE** — fill the template into `Source/VibeUE/Private/Tools/Generated/SetWorldKillZTool.cpp`. Fix any compile-shape issues the moment Task 4's build reports them (this is where the Task 2 ⚠️ field-verify resolves).

- [ ] **Step 3: Shadow-build** —
```powershell
& 'M:\...\Build-ShadowTool.ps1' -CandidateId CAND-20260604-1 -GeneratedCpp 'Source/VibeUE/Private/Tools/Generated/SetWorldKillZTool.cpp'
```
Expected: `GREEN CAND-20260604-1`; manifest staged. If RED, read the build log, fix the template/instance, repeat. Live MCP stays up throughout.

- [ ] **Step 4: SWAP** — close the editor, run `Apply-PendingSwap.ps1`, expect `APPLIED CAND-20260604-1` + a fork commit.

- [ ] **Step 5: Verify the new tool LIVE next session** — start the editor, confirm the MCP exposes the new tool, call it (set a known KillZ), and observe the effect via `read_pcg_graph`-style read or `execute_python_code` read-back. **This live call is the hard gate** — no live proof, no LOG.

- [ ] **Step 6: LOG + finalise** — append the resolved gap record (with `Auto-cycle: generated-green(set_world_killz)` and the resolution sha in a separate commit), set the candidate `state: applied`. Push the branch to `fork` only when the user asks.

---

## Self-Review

**Spec coverage:** §4 components → Task 6 (classifier/queue refs), Task 1 (queue), Task 2+9 (generator), Task 4 (shadow-build gate), Task 5 (swap launcher), Task 7 (gap log). §5 simple-wrapper def → Task 6 Step 1. §6 isolation invariants → Task 4 (green/red, live untouched) + Task 5 (editor-closed guard). §8 carve-out → Task 6 Step 3 + Task 8. §9 artifact locations → File Structure table. ✅ all covered.

**Open risk surfaced honestly:** Task 3 verifies the unproven `BuildPlugin.bat` isolation assumption before any script depends on it, with an explicit STOP-and-report fallback. Task 2 marks the C++-symbol details as field-verified at Task 4/9, not assumed.

**Type/name consistency:** candidate id form `CAND-<YYYYMMDD>-<n>`, manifest keys (`shadow_root`, `binary_dir`, `source_files`, `tool_name`), script param names (`-CandidateId`, `-GeneratedCpp`), staging path, and shadow root are identical across Tasks 1, 4, 5, 9. ✅
