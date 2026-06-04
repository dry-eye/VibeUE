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
    # NOTE: invoke as a child process (& script.ps1 ...), NOT dot-sourced — these exit calls would terminate a dot-sourcing caller.
    Write-Output "GREEN $CandidateId"
    exit 0
}

# RED: remove the bad source (tracked -> checkout HEAD; untracked -> delete), then rebuild prior good.
# git may be absent or the file untracked; the Remove-Item below is the real safety net for untracked files.
try { & git -C $PluginRoot checkout -- $GeneratedCpp 2>&1 | Out-Null } catch {}
$abs = Join-Path $PluginRoot $GeneratedCpp
if (Test-Path $abs) { Remove-Item $abs -Force }   # was untracked
$recovered = Invoke-EditorBuild
if (-not $recovered) {
    throw "RED $CandidateId AND prior-good rebuild FAILED — manual intervention needed."
}
Write-Output "RED $CandidateId"
exit 1