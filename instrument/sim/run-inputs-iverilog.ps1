param(
    [Parameter(Mandatory=$true)][string]$IcarusBin,
    [Parameter(Mandatory=$true)][string]$GowinSimLib,
    [string]$Only='tb_shared_ads1115,tb_shared_ads1115_rate,tb_joystick_controls,tb_pressure_expression,tb_joystick_core,tb_joystick_top,tb_pressure_link,tb_ec11_core,tb_guide_auto,tb_ec11_allocator,tb_screen_feedback,tb_builtin_score,tb_output_level'
)
$ErrorActionPreference='Stop'
$iverilog=Join-Path $IcarusBin 'iverilog.exe'
$vvp=Join-Path $IcarusBin 'vvp.exe'
foreach($tool in @($iverilog,$vvp,$GowinSimLib)){if(!(Test-Path -LiteralPath $tool)){throw "Missing: $tool"}}
$previousPath=$env:PATH
$env:PATH=$IcarusBin+';'+$env:PATH
Push-Location $PSScriptRoot
try {
    $out=Join-Path $PSScriptRoot 'output/icarus-inputs'
    New-Item -ItemType Directory -Force $out | Out-Null
    $sources=Get-ChildItem ../src/*.v | ForEach-Object {Join-Path '../src' $_.Name}
    foreach($test in $Only.Split(',')){
        $benches=@("$test.sv")
        if($test -eq 'tb_shared_ads1115_rate'){$benches=@('tb_shared_ads1115.sv')}
        if($test -eq 'tb_ec11_allocator'){$benches+='tb_voice_allocator.sv'}
        if($test -eq 'tb_engine_equivalence'){$benches+='reference/polyphonic_engine_reference.v'}
        $binary=Join-Path $out "$test.vvp"
        $compileLog=Join-Path $out "$test.compile.log"
        $simLog=Join-Path $out "$test.log"
        & $iverilog -g2012 -s $test -o $binary @sources @benches $GowinSimLib > $compileLog 2>&1
        if($LASTEXITCODE){Get-Content $compileLog -Tail 20;throw "Compile failed: $test"}
        & $vvp $binary > $simLog 2>&1
        if($LASTEXITCODE -or !(Select-String -LiteralPath $simLog -SimpleMatch 'ALL TESTS PASSED' -Quiet)){
            Get-Content $simLog -Tail 20;throw "Simulation failed: $test"
        }
        Write-Output "PASS $test"
    }
}finally {Pop-Location;$env:PATH=$previousPath}
