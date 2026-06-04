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
| `Scripts/SelfImprove/Build-PendingTool.ps1` (fork) | Build ONE pending candidate in place (`Build.bat <target> Win64 <config>`), parse `Result: Succeeded`; GREEN keep, RED `git checkout` the .cpp + rebuild prior good | create |
| `Scripts/SelfImprove/Apply-PendingBuild.ps1` (fork) | Session-start launcher: guard editor-closed → loop pending-build markers via Build-PendingTool → commit green → launch editor | create |
| `docs/self-improve/gap-log.md` (fork) | Extended with auto-cycle outcome fields | modify |
| `project_vibeue_self_improve_pipeline.md` (memory) | Record §8 approval-gate carve-out | modify |

> **Model revised 2026-06-04 (Task 3):** isolation switched from shadow-build+swap to
> **in-place build + auto-rollback** (see spec §6). No shadow worktree, no staged
> binary. The generated `.cpp` goes straight into the live tree; the build happens at
> the next editor-closed window; red rolls back via `git checkout`.

**Out-of-repo runtime paths** (gitignored, decided here so tasks agree):
- Generated tool sources: `Source/VibeUE/Private/Tools/Generated/` (in the live tree, tracked).
- Pending-build markers: `M:\UnrealProjects\Game\Saved\SelfImprove\pending-build\` (`Saved/` is gitignored).
- Build: `Build.bat GameEditor Win64 DebugGame "M:\UnrealProjects\Game\Game.uproject" -waitmutex` (target/config confirmed live in Task 3); success marker `Result: Succeeded`; capture stdout (no fixed log file).

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

## Task 4: `Build-PendingTool.ps1` — in-place build of one candidate + green/red + rollback

**Files:**
- Create: `Scripts/SelfImprove/Build-PendingTool.ps1`

Behavior (in-place model, spec §6): given a generated `.cpp` already present in the live tree, **with the editor closed**, rebuild the editor target in the live config and parse UBT `Result: Succeeded`. **GREEN** → the freshly built DLL is now live; print `GREEN`. **RED** → `git checkout`/remove the bad `.cpp`, **rebuild the prior good state** so the editor can still launch, print `RED`. This script does NOT commit (the launcher in Task 5 commits green sources).

> **Testability constraint (important):** a real build requires the editor CLOSED, but this MCP session runs *inside* the live editor. So the green/red build itself **cannot be exercised mid-session** — only the editor-running guard and script parse can be tested now. The real green/red/rollback verification is deferred to **Task 9** (manual, editor-closed). The script therefore exposes a `-BuildResultOverride` test seam used ONLY by tests to bypass the real build.

- [ ] **Step 1: Write the script**

Create `Scripts/SelfImprove/Build-PendingTool.ps1`:

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$GeneratedCpp,   # relative to plugin root, in the live tree
    [string]$CandidateId   = '',
    [string]$PluginRoot    = 'M:\UnrealProjects\Game\Plugins\VibeUE',
    [string]$ProjectFile   = 'M:\UnrealProjects\Game\Game.uproject',
    [string]$BuildTarget   = 'GameEditor',
    [string]$BuildConfig   = 'DebugGame',
    [string]$EnginePath    = 'M:\UnrealEngines\UE_5.7',
    [ValidateSet('', 'GREEN', 'RED')] [string]$BuildResultOverride = ''  # TEST SEAM ONLY
)
$ErrorActionPreference = 'Stop'
$BuildBat = Join-Path $EnginePath 'Engine\Build\BatchFiles\Build.bat'
$Marker   = 'Result: Succeeded'

function Invoke-EditorBuild {
    if ($BuildResultOverride) { return ($BuildResultOverride -eq 'GREEN') }  # test bypass
    $out = & $BuildBat $BuildTarget Win64 $BuildConfig "$ProjectFile" -waitmutex | Out-String
    return ($out -match [regex]::Escape($Marker))
}

# Guard: editor must be closed (it locks the DLL we are about to rebuild).
# Skipped under the test seam so the rollback logic can be exercised without a real build.
if (-not $BuildResultOverride -and (Get-Process -Name 'UnrealEditor*' -ErrorAction SilentlyContinue)) {
    throw 'UnrealEditor is running; close it before building (it locks the plugin DLL).'
}

if (Invoke-EditorBuild) {
    Write-Output "GREEN $CandidateId"
    exit 0
}

# RED: remove the bad source (tracked -> checkout HEAD; untracked -> delete), then rebuild prior good.
& git -C $PluginRoot checkout -- $GeneratedCpp 2>$null
$abs = Join-Path $PluginRoot $GeneratedCpp
if (Test-Path $abs) { Remove-Item $abs -Force }   # was untracked
$recovered = Invoke-EditorBuild
if (-not $recovered) {
    throw "RED $CandidateId AND prior-good rebuild FAILED — manual intervention needed."
}
Write-Output "RED $CandidateId"
exit 1
```

- [ ] **Step 2: Test the editor-running guard (real, testable now)**

The editor is currently running. Run (no override, so the guard fires):
```powershell
& 'M:\UnrealProjects\Game\Plugins\VibeUE\Scripts\SelfImprove\Build-PendingTool.ps1' -GeneratedCpp 'Source/VibeUE/Private/Tools/Generated/_x.cpp'
```
Expected: throws `UnrealEditor is running; close it before building (it locks the plugin DLL).` and does nothing else.

- [ ] **Step 3: Test the RED rollback file-logic with the test seam (no real build)**

Create an untracked dummy `Source/VibeUE/Private/Tools/Generated/_red.cpp` (a comment line). Run:
```powershell
& '...\Build-PendingTool.ps1' -GeneratedCpp 'Source/VibeUE/Private/Tools/Generated/_red.cpp' -BuildResultOverride RED
```
Expected: prints `RED `; the dummy file is removed (`Test-Path` → `$false`). (The seam makes both the initial and the recovery `Invoke-EditorBuild` return red→… note: with override RED the recovery build also returns red and the script will throw at the end — that is acceptable for this file-logic test; assert the file was removed BEFORE the throw. Alternatively run with the file untracked and confirm removal, ignoring the final throw.) Then test GREEN seam: create `_green.cpp`, run with `-BuildResultOverride GREEN`, expect `GREEN ` and the file left in place.

- [ ] **Step 4: Script-parse check + cleanup + commit**

Validate the script parses (catches syntax errors without running):
```powershell
$null = [System.Management.Automation.Language.Parser]::ParseFile('M:\UnrealProjects\Game\Plugins\VibeUE\Scripts\SelfImprove\Build-PendingTool.ps1', [ref]$null, [ref]$null)
```
Expected: no parse errors thrown. Remove any `_red.cpp`/`_green.cpp`/`_x.cpp` test files, then:
```powershell
cd 'M:\UnrealProjects\Game\Plugins\VibeUE'
git add Scripts/SelfImprove/Build-PendingTool.ps1
git commit -m "feat(self-improve): in-place build script with green/red gate + rollback"
```

---

## Task 5: `Apply-PendingBuild.ps1` — session-start launcher

**Files:**
- Create: `Scripts/SelfImprove/Apply-PendingBuild.ps1`

Behavior: at the next session start (editor closed), for each pending-build marker in the staging dir: call `Build-PendingTool.ps1` for its `generated_cpp`/`build_target`/`build_config`. **GREEN** → `git add`+commit the generated source, update the candidate state, remove the marker. **RED** → the source was already rolled back by Task 4; just remove the marker (the recipe stays as the Python fallback). Then the caller launches the editor. No markers → no-op.

> Same testability constraint as Task 4: the real build path can't run mid-session. The script takes a `-BuildScript` param (defaulting to `Build-PendingTool.ps1`) so tests can inject a fake builder that echoes GREEN/RED without an editor shutdown.
>
> **Why a CHILD PROCESS for the builder (load-bearing):** `Build-PendingTool.ps1` ends each path with `exit 0/1`. PowerShell's `& path.ps1` runs the script **in the current process**, so an `exit` there would terminate THIS launcher after the first candidate. We therefore invoke the builder via `powershell.exe -File` (a real child process) — `exit` then only ends the child, and we read its stdout + `$LASTEXITCODE`. (The code review that approved Task 4 assumed a child process; this makes that assumption true.)
>
> **Three-way result (from the Task 4 review):** GREEN → commit + clear marker; clean RED (`.cpp` rolled back, prior good rebuilt) → clear marker, keep Python recipe; **double-RED** (builder threw — prior-good rebuild also failed → neither GREEN nor RED in stdout) → **leave the marker** and stop loudly; the tree may be non-building and needs a human.

- [ ] **Step 1: Write the script**

Create `Scripts/SelfImprove/Apply-PendingBuild.ps1`:

```powershell
[CmdletBinding()]
param(
    [string]$PluginRoot  = 'M:\UnrealProjects\Game\Plugins\VibeUE',
    [string]$StageDir    = 'M:\UnrealProjects\Game\Saved\SelfImprove\pending-build',
    [string]$BuildScript = ''   # defaults to Build-PendingTool.ps1 next to this script
)
$ErrorActionPreference = 'Stop'
if (-not $BuildScript) { $BuildScript = Join-Path $PSScriptRoot 'Build-PendingTool.ps1' }
if (-not (Test-Path $StageDir)) { Write-Output 'no pending builds'; return }

$markers = Get-ChildItem "$StageDir\*.json" -ErrorAction SilentlyContinue
if (-not $markers) { Write-Output 'no pending builds'; return }

foreach ($m in $markers) {
    $man = Get-Content $m -Raw | ConvertFrom-Json
    # Run the builder in a CHILD process so its `exit` cannot terminate this launcher.
    # Capture STDOUT ONLY (no 2>&1): clean RED prints "RED ..." via Write-Output -> stdout;
    # a double-RED `throw` goes to the child's STDERR and never reaches $out, so it falls to
    # the else branch below. (Merging stderr would false-match the real "RED ... FAILED" throw.)
    # Not redirecting stderr also avoids the PS5.1 NativeCommandError-with-Stop pitfall.
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BuildScript `
        -GeneratedCpp $man.generated_cpp -CandidateId $man.id `
        -BuildTarget $man.build_target -BuildConfig $man.build_config | Out-String

    if ($out -match '(?m)^GREEN') {
        & git -C $PluginRoot add $man.generated_cpp
        & git -C $PluginRoot commit -m "feat(self-improve): apply generated tool $($man.tool_name) [$($man.id)]"
        Write-Output "APPLIED $($man.id)"
        Remove-Item $m -Force
    }
    elseif ($out -match '(?m)^RED') {
        # Build failed but the .cpp was rolled back and the prior good state rebuilt — tree is clean.
        Write-Output "ROLLED-BACK $($man.id)"
        Remove-Item $m -Force
    }
    else {
        # Double-RED: builder threw (prior-good rebuild also failed; its error went to stderr,
        # not $out). Tree may not compile. Keep the marker for inspection and stop loudly.
        Write-Warning "BUILD-BROKEN $($man.id): builder produced no GREEN/RED verdict on stdout."
        throw "Self-improve left the tree non-building for $($man.id); marker kept at $($m.FullName)."
    }
}
```

- [ ] **Step 2: Test no-marker no-op (real, testable now)**

Ensure `Saved/SelfImprove/pending-build/` is empty or absent, then run:
```powershell
& 'M:\UnrealProjects\Game\Plugins\VibeUE\Scripts\SelfImprove\Apply-PendingBuild.ps1'
```
Expected: prints `no pending builds`; no git activity.

- [ ] **Step 3: Test the three-way loop with fake builders (no real build)**

The launcher invokes the builder via `powershell.exe -File`, so the fake must be a `.ps1` that declares the same params and prints a verdict. Create three fakes and a staging dir:
```powershell
$d = 'M:\UnrealProjects\Game\Saved\SelfImprove'
New-Item -ItemType Directory -Force "$d\pending-build" | Out-Null
'param($GeneratedCpp,$CandidateId,$BuildTarget,$BuildConfig); Write-Output "GREEN $CandidateId"' | Set-Content "$d\_fakegreen.ps1" -Encoding utf8
'param($GeneratedCpp,$CandidateId,$BuildTarget,$BuildConfig); Write-Output "RED $CandidateId"'   | Set-Content "$d\_fakered.ps1"   -Encoding utf8
'param($GeneratedCpp,$CandidateId,$BuildTarget,$BuildConfig); throw "double-red"'                | Set-Content "$d\_fakebroken.ps1" -Encoding utf8
```

**GREEN sub-test** — generated_cpp points at a NEW throwaway file so the commit is real, then undo it:
```powershell
'// wire test' | Set-Content 'M:\UnrealProjects\Game\Plugins\VibeUE\Source\VibeUE\Private\Tools\Generated\_wire.cpp' -Encoding utf8
'{ "id":"WIRE-1","tool_name":"wire","generated_cpp":"Source/VibeUE/Private/Tools/Generated/_wire.cpp","build_target":"GameEditor","build_config":"DebugGame","state":"pending-build" }' | Set-Content "$d\pending-build\WIRE-1.json" -Encoding utf8
& '...\Apply-PendingBuild.ps1' -BuildScript "$d\_fakegreen.ps1"
```
Expected: prints `APPLIED WIRE-1`; marker `WIRE-1.json` removed; a commit added `_wire.cpp`. Cleanup: `git -C <plugin> reset --soft HEAD~1`, then `git -C <plugin> restore --staged Source/VibeUE/Private/Tools/Generated/_wire.cpp`, then delete `_wire.cpp`.

**RED sub-test** — re-stage `WIRE-1.json`, run with `_fakered.ps1`. Expected: prints `ROLLED-BACK WIRE-1`; marker removed; NO new commit (`git -C <plugin> log -1 --format=%s` unchanged).

**Double-RED sub-test** — re-stage `WIRE-1.json`, run with `_fakebroken.ps1`. Expected: the launcher **throws** `Self-improve left the tree non-building for WIRE-1…` and the marker `WIRE-1.json` is **NOT removed** (`Test-Path` → `$true`). Then delete the marker manually to clean up.

- [ ] **Step 4: Parse-check, cleanup, commit**

```powershell
$null = [System.Management.Automation.Language.Parser]::ParseFile('M:\UnrealProjects\Game\Plugins\VibeUE\Scripts\SelfImprove\Apply-PendingBuild.ps1', [ref]$null, [ref]$null)
Remove-Item 'M:\UnrealProjects\Game\Saved\SelfImprove\_fake*.ps1','M:\UnrealProjects\Game\Saved\SelfImprove\pending-build\*.json' -ErrorAction SilentlyContinue
Remove-Item 'M:\UnrealProjects\Game\Plugins\VibeUE\Source\VibeUE\Private\Tools\Generated\_wire.cpp' -ErrorAction SilentlyContinue
cd 'M:\UnrealProjects\Game\Plugins\VibeUE'
git status --short   # expect clean (no stray test files)
git add Scripts/SelfImprove/Apply-PendingBuild.ps1
git commit -m "feat(self-improve): session-start launcher (build pending, commit green)"
```

> **Hook wiring is deferred:** whether `Apply-PendingBuild.ps1` runs from a Claude Code SessionStart hook or the user's editor-launch `.bat` is decided when we wire it (Task 9 runs it manually first). It is safe to call unconditionally — it no-ops with `no pending builds`. The real green/red build is exercised end-to-end in Task 9 at an editor-closed window.

---

## Task 6: Add CLASSIFY / QUEUE / GENERATE / BUILD to the skill

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

- [ ] **Step 2: Add GENERATE + BUILD phases**

Append to the `## Phases` list:

```markdown
9. **GENERATE (simple-wrapper only, autonomous)** — fill
   `templates/simple-wrapper.cpp.tmpl` from the candidate into
   `Source/VibeUE/Private/Tools/Generated/<Name>Tool.cpp` (live tree), then write a
   pending-build marker to `Game/Saved/SelfImprove/pending-build/<id>.json`
   (schema: tool-candidates/_SCHEMA.md). The live MCP keeps running on the old
   binary; nothing is built mid-session.
10. **BUILD (next session start, editor closed)** —
    `Scripts/SelfImprove/Apply-PendingBuild.ps1` runs the in-place build for each
    pending marker via `Build-PendingTool.ps1`. GREEN → commit the `.cpp` to the
    fork, set candidate `state: applied`, the new tool is live this session. RED →
    the `.cpp` is auto-rolled-back (`git checkout`) and the prior good state rebuilt;
    set `state: red`, keep the Python recipe, append a red record to the gap log.
```

- [ ] **Step 3: Update the autonomy table for the carve-out**

Replace the `## Autonomy` table with:

```markdown
## Autonomy
| Tier | Action | Gate |
|------|--------|------|
| Skill | write/commit a verified skill doc to the fork | autonomous |
| C++ — simple wrapper | generate .cpp in live tree, in-place build at editor-closed window, auto-rollback on red | autonomous (gated by green build; no human gate) |
| C++ — complex | edit service/MCP, build, restart editor, commit | explicit "go" required first |
```

- [ ] **Step 4: Sync the snapshot and commit**

Copy the live skill over the fork snapshot so they are byte-identical, then:
```powershell
cd 'M:\UnrealProjects\Game\Plugins\VibeUE'
git add docs/self-improve/vibeue-self-improve.SKILL.md
git commit -m "feat(self-improve): skill v2 — classify, generate, in-place build at session start"
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
> Autonomy: skill-tier autonomous; **simple-wrapper C++ tools auto-generated, built in-place at the next editor-closed window with git-checkout auto-rollback on red (no human gate)**; complex C++ service-method changes remain approval-gated. See spec `2026-06-04-vibeue-autotool-from-python-design.md`.

- [ ] **Step 2: Verify** — re-reading the memory shows no contradiction with the v1 line; the carve-out is explicit. (Memory files are not committed to the fork; this is a local `.claude` write.)

---

## Task 9: End-to-end dry run on one real simple-wrapper candidate

**Files:** none new (exercises the whole pipeline).

- [ ] **Step 1: Pick a real candidate** — use a genuinely reusable one-API-call op not yet covered by a tool (e.g. the `set_world_killz` from the KillZ gap GAP-20260603-1). Write its `CAND-…` record per `_SCHEMA.md`.

- [ ] **Step 2: GENERATE** — fill the template into `Source/VibeUE/Private/Tools/Generated/SetWorldKillZTool.cpp` (live tree) and write the pending-build marker `Game/Saved/SelfImprove/pending-build/CAND-20260604-1.json` per `_SCHEMA.md`. This is where the Task 2 field-verified symbols meet a real compile.

- [ ] **Step 3: BUILD at an editor-closed window (the hard build gate)** — **close the editor** (this also ends the current MCP session), then run the launcher:
```powershell
& 'M:\UnrealProjects\Game\Plugins\VibeUE\Scripts\SelfImprove\Apply-PendingBuild.ps1'
```
Expected: it invokes `Build-PendingTool.ps1`, which runs `Build.bat GameEditor Win64 DebugGame "M:\UnrealProjects\Game\Game.uproject" -waitmutex`. GREEN → prints `APPLIED CAND-20260604-1` + a fork commit; the rebuilt DLL is the live binary. RED → prints `ROLLED-BACK CAND-20260604-1`, the `.cpp` is removed and the prior good state rebuilt; read the build stdout, fix the generated `.cpp` (or the template), regenerate, repeat.

- [ ] **Step 4: Launch the editor** — start the editor normally (its DLL is the freshly built one).

- [ ] **Step 5: Verify the new tool LIVE** — confirm the MCP exposes `set_world_killz`, call it (set a known KillZ), and observe the effect via an `execute_python_code` read-back of `kill_z`. **This live call is the hard gate** — no live proof, no LOG.

- [ ] **Step 6: LOG + finalise** — append the resolved gap record (with `Auto-cycle: generated-green(set_world_killz)` and the resolution sha in a separate commit), set the candidate `state: applied`. Push the branch to `fork` only when the user asks.

---

## Self-Review

**Spec coverage:** §4 components → Task 6 (classifier/queue refs), Task 1 (queue), Task 2+9 (generator), Task 4 (in-place build gate + rollback), Task 5 (session-start launcher), Task 7 (gap log). §5 simple-wrapper def → Task 6 Step 1. §6 in-place build + rollback invariants → Task 4 (green/red, editor-closed guard, rollback) + Task 5 (loop + commit green). §8 carve-out → Task 6 Step 3 + Task 8. §9 artifact locations → File Structure table. ✅ all covered.

**Model revised 2026-06-04 (Task 3 outcome):** shadow-build isolation was found unworkable in this tree (host-project in-place build; live editor is DebugGame). Switched to in-place build + `git checkout` auto-rollback at the editor-closed boundary. Spec §1/§3/§4/§6/§8/§9 and Tasks 4/5/6/8/9 updated accordingly.

**Testability constraint surfaced honestly:** the real build needs the editor closed, but this MCP session runs inside the live editor — so Tasks 4/5 can only test the guard, parse, and (via test seams) the rollback/loop logic mid-session; the real green/red build is exercised only in Task 9 at an editor-closed window. Stated in Tasks 4, 5, 9.

**Type/name consistency:** candidate id form `CAND-<YYYYMMDD>-<n>`; pending-build marker keys (`generated_cpp`, `build_target`, `build_config`, `tool_name`, `id`); script names (`Build-PendingTool.ps1`, `Apply-PendingBuild.ps1`) and params (`-GeneratedCpp`, `-CandidateId`, `-BuildTarget`, `-BuildConfig`, `-BuildResultOverride`, `-BuildScript`); staging path `Game/Saved/SelfImprove/pending-build/`; generated path `Source/VibeUE/Private/Tools/Generated/` — identical across Tasks 1, 4, 5, 6, 9. ✅
