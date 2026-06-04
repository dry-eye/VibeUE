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
        if ($LASTEXITCODE -ne 0) { throw "git add failed for $($man.id) ($($man.generated_cpp)); marker kept at $($m.FullName)." }
        & git -C $PluginRoot commit -m "feat(self-improve): apply generated tool $($man.tool_name) [$($man.id)]"
        if ($LASTEXITCODE -ne 0) { throw "git commit failed for $($man.id); marker kept at $($m.FullName)." }
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
