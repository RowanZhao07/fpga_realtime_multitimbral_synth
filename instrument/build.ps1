param([string]$GowinShell, [switch]$CheckTools)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'tools/toolchain.ps1')
$GowinShell = Resolve-GowinShell $GowinShell
if ($CheckTools) { Write-Output "Gowin shell: $GowinShell"; return }
Push-Location $PSScriptRoot
try {
    if(!(Test-Path $GowinShell)) { throw "Gowin shell not found: $GowinShell" }
    $buildStarted=Get-Date
    & $GowinShell build.tcl 2>&1 | Tee-Object -FilePath build.log
    if($LASTEXITCODE -ne 0) { throw 'Gowin build failed' }
    if(Select-String build.log -Pattern '^ERROR\s' -Quiet) { throw 'Gowin reported errors' }
    if(!(Test-Path 'impl/pnr/instrument.fs')) { throw 'Bitstream was not generated' }
    if((Get-Item 'impl/pnr/instrument.fs').LastWriteTime -lt $buildStarted) { throw 'Bitstream is stale' }
    $timingReport=Get-Content 'impl/pnr/instrument.tr' -Raw
    if($timingReport -notmatch '<Numbers of Setup Violated Endpoints>:0\s' -or
       $timingReport -notmatch '<Numbers of Hold Violated Endpoints>:0\s') {
        throw 'Timing verification failed; inspect setup/hold and recovery/removal paths before downloading'
    }
    Get-FileHash 'impl/pnr/instrument.fs' -Algorithm SHA256
} finally { Pop-Location }
