param([string]$VivadoBin, [string]$Python='python',
      [string]$GowinSimLib, [switch]$CheckTools)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../tools/toolchain.ps1')
$GowinSimLib = Resolve-GowinSimLib $GowinSimLib
$xvlog = Resolve-XSimTool $VivadoBin 'xvlog'
$xelab = Resolve-XSimTool $VivadoBin 'xelab'
$xsim = Resolve-XSimTool $VivadoBin 'xsim'
$pythonCommand = Get-Command $Python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (!$pythonCommand) { throw "Python not found: $Python" }
$Python = $pythonCommand.Source
if ($CheckTools) { Write-Output "XSim: $xsim`nGowin library: $GowinSimLib`nPython: $Python"; return }
Push-Location $PSScriptRoot
try {
    $sources=Get-ChildItem ../src/*.v | ForEach-Object FullName
    if(!(Test-Path $GowinSimLib)) { throw "Gowin GW5A simulation library not found: $GowinSimLib" }
    & $xvlog --sv $GowinSimLib @sources tb_controls.sv tb_echo.sv tb_synthesis.sv tb_touch_link.sv tb_board_clock.sv tb_spectrum.sv tb_video.sv tb_visual_link.sv tb_serial_video.sv tb_latency.sv tb_waveform.sv tb_screen_feedback.sv tb_listening_port.sv tb_scope_link.sv tb_top_integration.sv
    if($LASTEXITCODE) { throw 'RTL compilation failed' }
    foreach($test in @('tb_controls','tb_echo','tb_synthesis','tb_touch_link','tb_board_clock','tb_spectrum','tb_video','tb_visual_link','tb_serial_video','tb_latency','tb_waveform','tb_screen_feedback','tb_listening_port','tb_scope_link','tb_top_integration')) {
        & $xelab $test -s $test -debug typical
        if($LASTEXITCODE) { throw "Elaboration failed: $test" }
        & $xsim $test -runall
        if($LASTEXITCODE -or !(Select-String xsim.log -Pattern 'ALL TESTS PASSED' -Quiet)) {
            throw "Simulation failed: $test"
        }
        Copy-Item xsim.log "$test.log" -Force
    }
    & $Python ../tools/analyze_audio.py
    if($LASTEXITCODE) { throw 'Audio analysis failed' }
    & $Python ../tools/analyze_visual.py
    if($LASTEXITCODE) { throw 'Visual analysis failed' }
} finally { Pop-Location }
