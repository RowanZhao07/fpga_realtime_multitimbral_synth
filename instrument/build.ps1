param([string]$GowinShell, [switch]$CheckTools, [switch]$Expression, [switch]$SynthesisOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'tools/toolchain.ps1')
$GowinShell = Resolve-GowinShell $GowinShell
if ($CheckTools) { Write-Output "Gowin shell: $GowinShell"; return }
$buildBase = 'instrument_expression'
$releaseBase = 'instrument_expression_ui_v2_3x'
# Never publish to the frozen instrument_expression_link_v1.fs baseline.
$previousSynthesisOnly = $env:INSTRUMENT_SYNTHESIS_ONLY
$env:INSTRUMENT_SYNTHESIS_ONLY = if($SynthesisOnly) { '1' } else { '0' }
Push-Location $PSScriptRoot
try {
    if(!(Test-Path $GowinShell)) { throw "Gowin shell not found: $GowinShell" }
    $buildStarted=Get-Date
    $inputFiles=@(Get-ChildItem src -File; Get-ChildItem config -File; Get-Item instrument_expression.gprj,build.tcl,build.ps1)
    $inputHashes=@($inputFiles | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{path=$_.FullName.Substring($PSScriptRoot.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
    & $GowinShell build.tcl 2>&1 | Tee-Object -FilePath build.log
    if($LASTEXITCODE -ne 0) { throw 'Gowin build failed' }
    if(Select-String build.log -Pattern '^ERROR\s' -Quiet) { throw 'Gowin reported errors' }
    foreach($inputHash in $inputHashes) {
        if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $inputHash.path)).Hash -ne $inputHash.sha256) {
            throw "Build input changed during compilation: $($inputHash.path). Rebuild before publishing."
        }
    }
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
    $releaseFile = [IO.Path]::GetFullPath((Join-Path $releaseDir "$releaseBase.fs"))
    $buildFile = (Resolve-Path -LiteralPath "impl/pnr/$buildBase.fs").Path
    foreach($path in @($releaseFile, $buildFile)) {
        if(!$path.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Build artifact outside repository: $path"
        }
    }
    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
    Move-Item -LiteralPath $buildFile -Destination $releaseFile -Force
    $releaseHash=Get-FileHash -LiteralPath $releaseFile -Algorithm SHA256
    $evidenceDir=Join-Path $repoRoot 'outputs/expression-ui-v2-3x'
    New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
    Copy-Item -LiteralPath "impl/pnr/$buildBase.tr","impl/pnr/$buildBase.rpt.txt","impl/pnr/$buildBase.pin.html",'build.log' -Destination $evidenceDir -Force
    [pscustomobject]@{
        profile='expression-ui-v2-3x';baseline='instrument_expression_link_v1.fs';display_gain=3;
        built_at_utc=$buildStarted.ToUniversalTime().ToString('o');
        bitstream="$releaseBase.fs";sha256=$releaseHash.Hash;bytes=(Get-Item -LiteralPath $releaseFile).Length;
        tool=$GowinShell;setup_violations=0;hold_violations=0;minimum_pulse_width_passed=$true;
        hardware_validated=$false;inputs=$inputHashes
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $releaseDir "$releaseBase.manifest.json") -Encoding utf8
    $releaseHash
 } finally { $env:INSTRUMENT_SYNTHESIS_ONLY = $previousSynthesisOnly; Pop-Location }
