# Run after build/simulation have finished. -WhatIf lists candidates only.
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param([string]$Python='python')
$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$releases=@('dist/instrument.fs','dist/instrument_touch_debug.fs','dist/instrument_ec11.fs' |
    ForEach-Object { Join-Path $repoRoot $_ } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if($releases.Count -eq 0) {
    throw 'Build a normal, touch-debug or EC11 release in dist before cleaning intermediates.'
}
$releaseHashes=@{}
foreach($release in $releases) {
    $releaseHashes[$release]=(Get-FileHash -LiteralPath $release -Algorithm SHA256).Hash
}

function Get-SafeItem([string]$Path) {
    $item=Get-Item -LiteralPath $Path -Force
    if(!$item.FullName.StartsWith($repoRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Outside repository: $Path"
    }
    # Reject junctions/symlinks in the target and every parent below the root.
    $node=$item
    while($node.FullName -ne $repoRoot) {
        if($node.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point: $($node.FullName)" }
        $node=Get-Item -LiteralPath (Split-Path -Parent $node.FullName) -Force
    }
    return $item
}

# Only named historical/generated directories; never assets, .local, source or .git.
$directories=@('tmp','backups','led_flow','xsim.dir','.Xil',
    'instrument/impl','instrument/sim/xsim.dir','instrument/sim/.Xil',
    'instrument/sim/output','instrument/tools/__pycache__','instrument/sim/__pycache__')
$candidates=@()
foreach($relative in $directories) {
    $path=Join-Path $repoRoot $relative
    if(Test-Path -LiteralPath $path) {
        $item=Get-SafeItem $path
        if(!$item.PSIsContainer) { throw "Expected directory: $path" }
        if(Get-ChildItem -LiteralPath $item.FullName -Recurse -Force |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
            throw "Nested reparse point: $path"
        }
        $candidates+=$item
    }
}
foreach($relative in @('.','instrument','instrument/sim')) {
    $folder=Join-Path $repoRoot $relative
    foreach($item in Get-ChildItem -LiteralPath $folder -File -Force) {
        if($item.Extension -in @('.log','.jou','.pb','.wdb','.csv','.ppm','.fs','.bin','.binx','.vg') -or
            $item.Name -eq 'dfx_runtime.txt' -or $item.Name -like '*.gprj.user') {
            $candidates+=Get-SafeItem $item.FullName
        }
    }
}
# Resolve and check every candidate before preserving or deleting its contents.
# A failed preservation step leaves all raw output intact.
if($PSCmdlet.ShouldProcess('Simulation images and audio','Preserve media before cleanup')) {
    & $Python (Join-Path $PSScriptRoot 'preserve_sim_media.py')
    if($LASTEXITCODE -ne 0) { throw 'Media preservation failed; cleanup cancelled.' }
}
foreach($item in $candidates) {
    if($PSCmdlet.ShouldProcess($item.FullName,'Delete historical/generated item')) {
        if($item.PSIsContainer) { Remove-Item -LiteralPath $item.FullName -Recurse -Force }
        else { Remove-Item -LiteralPath $item.FullName -Force }
    }
}
foreach($release in $releases) {
    if((Get-FileHash -LiteralPath $release -Algorithm SHA256).Hash -ne $releaseHashes[$release]) {
        throw "Release checksum changed during cleanup: $release"
    }
}
if(!$WhatIfPreference) {
    # Local verification archives and linked worktrees are outside cleanup's
    # scope. Do not traverse them or reject their retained reference bitstreams.
    $bitstreams=@(foreach($entry in Get-ChildItem -LiteralPath $repoRoot -Force) {
        if($entry.Name -in @('.git','.local')) { continue }
        if($entry.PSIsContainer) {
            Get-ChildItem -LiteralPath $entry.FullName -Recurse -File -Filter '*.fs'
        } elseif($entry.Extension -eq '.fs') { $entry }
    })
    if($bitstreams.Count -ne $releases.Count -or @($bitstreams | Where-Object { $_.FullName -notin $releases }).Count -ne 0) {
        throw 'Unexpected additional bitstreams remain; inspect them manually.'
    }
    Write-Output "Clean repository; releases retained: $($releases -join ', ')"
}
