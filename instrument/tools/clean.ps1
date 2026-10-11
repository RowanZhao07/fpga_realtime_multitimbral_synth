# Run after build/simulation have finished. -WhatIf lists candidates only.
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param([string]$Python='python')
$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$release=Join-Path $repoRoot 'dist/instrument.fs'
if(!(Test-Path -LiteralPath $release -PathType Leaf)) {
    throw 'Build dist/instrument.fs successfully before cleaning intermediates.'
}
$releaseHash=(Get-FileHash -LiteralPath $release -Algorithm SHA256).Hash

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
if((Get-FileHash -LiteralPath $release -Algorithm SHA256).Hash -ne $releaseHash) {
    throw 'Release checksum changed during cleanup.'
}
if(!$WhatIfPreference) {
    $bitstreams=@(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.fs' |
        Where-Object { !$_.FullName.StartsWith((Join-Path $repoRoot '.git')+[IO.Path]::DirectorySeparatorChar) })
    if($bitstreams.Count -ne 1 -or $bitstreams[0].FullName -ne $release) {
        throw 'Unexpected additional bitstreams remain; inspect them manually.'
    }
    Write-Output "Clean repository; one bitstream retained: $release"
}
