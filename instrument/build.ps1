param([string]$GowinShell, [switch]$CheckTools, [switch]$TouchDebug, [switch]$Ec11, [switch]$Joystick, [switch]$SynthesisOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'tools/toolchain.ps1')
$GowinShell = Resolve-GowinShell $GowinShell
if ($CheckTools) { Write-Output "Gowin shell: $GowinShell"; return }
if(($TouchDebug -and $Ec11) -or ($Joystick -and ($TouchDebug -or $Ec11))) { throw 'Choose one build profile.' }
$buildBase = if($Joystick) { 'instrument_joystick' } elseif($Ec11) { 'instrument_ec11' } elseif($TouchDebug) { 'instrument_touch_debug' } else { 'instrument' }
$previousBuildProfile = $env:INSTRUMENT_BUILD_PROFILE
$previousSynthesisOnly = $env:INSTRUMENT_SYNTHESIS_ONLY
$env:INSTRUMENT_SYNTHESIS_ONLY = if($SynthesisOnly) { '1' } else { '0' }
$env:INSTRUMENT_BUILD_PROFILE = if($Joystick) { 'joystick' } elseif($Ec11) { 'ec11' } elseif($TouchDebug) { 'touch_debug' } else { 'normal' }
Push-Location $PSScriptRoot
try {
    if(!(Test-Path $GowinShell)) { throw "Gowin shell not found: $GowinShell" }
    $buildStarted=Get-Date
    & $GowinShell build.tcl 2>&1 | Tee-Object -FilePath build.log
    if($LASTEXITCODE -ne 0) { throw 'Gowin build failed' }
    if(Select-String build.log -Pattern '^ERROR\s' -Quiet) { throw 'Gowin reported errors' }
    if($SynthesisOnly) { Write-Output "Synthesis completed: $buildBase (no bitstream requested)"; return }
    if(!(Test-Path "impl/pnr/$buildBase.fs")) { throw 'Bitstream was not generated' }
    if((Get-Item "impl/pnr/$buildBase.fs").LastWriteTime -lt $buildStarted) { throw 'Bitstream is stale' }
    $timingReport=Get-Content "impl/pnr/$buildBase.tr" -Raw
    if($timingReport -notmatch '<Numbers of Setup Violated Endpoints>:0\s' -or
       $timingReport -notmatch '<Numbers of Hold Violated Endpoints>:0\s') {
        throw 'Timing verification failed; inspect setup/hold and recovery/removal paths before downloading'
    }
    # Gowin's endpoint totals do not include minimum clock pulse-width failures.
    $pulseTable=[regex]::Match($timingReport,'(?ms)^3\.2 Minimum Pulse Width Table\r?\n(.*?)^3\.3 Timing Report')
    if(!$pulseTable.Success -or $pulseTable.Value -notmatch '(?m)^\s+\d+\s+[-+]?\d+\.\d+\s') {
        throw 'Minimum pulse-width report missing; inspect timing before downloading'
    }
    if($pulseTable.Value -match '(?m)^\s+\d+\s+-\d+\.\d+\s') {
        throw 'Minimum clock pulse-width violation; inspect timing before downloading'
    }
    # Publish only a fresh, timing-checked build. Moving avoids two runnable copies.
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    $releaseDir = Join-Path $repoRoot 'dist'
    $releaseFile = [IO.Path]::GetFullPath((Join-Path $releaseDir "$buildBase.fs"))
    $buildFile = (Resolve-Path -LiteralPath "impl/pnr/$buildBase.fs").Path
    foreach($path in @($releaseFile, $buildFile)) {
        if(!$path.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Build artifact outside repository: $path"
        }
    }
    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
    Move-Item -LiteralPath $buildFile -Destination $releaseFile -Force
    Get-FileHash -LiteralPath $releaseFile -Algorithm SHA256
} finally { $env:INSTRUMENT_SYNTHESIS_ONLY = $previousSynthesisOnly; $env:INSTRUMENT_BUILD_PROFILE = $previousBuildProfile; Pop-Location }
