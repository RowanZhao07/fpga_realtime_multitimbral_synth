param([string]$VivadoBin, [string]$Python='python',
      [string]$GowinSimLib, [switch]$CheckTools, [string]$Only, [switch]$NoAnalysis)
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
    New-Item -ItemType Directory -Force (Join-Path $PSScriptRoot 'output') | Out-Null
    $sources=Get-ChildItem ../src/*.v | ForEach-Object FullName
    if(!(Test-Path $GowinSimLib)) { throw "Gowin GW5A simulation library not found: $GowinSimLib" }
    # Keep the vendor .v library in Verilog mode: XSim 2025.1 --sv silently
    # zero-initializes pROMX9.ram_MEM despite nonzero INIT_RAM parameters.
    & $xvlog $GowinSimLib
    if($LASTEXITCODE) { throw 'Gowin simulation library compilation failed' }
    $benches=Get-ChildItem tb*.sv | ForEach-Object FullName
    & $xvlog --sv @sources @benches
    if($LASTEXITCODE) { throw 'RTL/test compilation failed' }
    $tests=@('tb_octave_controls','tb_octave_audio','tb_i2c_recovery','tb_touch_debug','tb_sustain_envelope','tb_sustain_control','tb_sustain_audio','tb_waveform','tb_scope_link','tb_screen_feedback','tb_voice_feedback','tb_top_integration','tb_controls','tb_echo','tb_synthesis','tb_voice_quality','tb_timbre_profiles','tb_chord_audio','tb_i2s_audio','tb_touch_link','tb_pressure_link','tb_pressure_audio','tb_hc595','tb_key_lights','tb_lamp_diagnostics','tb_board_clock','tb_spectrum','tb_video','tb_visual_link','tb_serial_video','tb_latency','tb_uart_control','tb_uart_diagnostics','tb_uart_tx_notice','tb_score_upload','tb_remote_instrument','tb_tempo','tb_voice_allocator','tb_guide_timing','tb_dynamic_timbre','tb_guide_auto')
    if($Only){ $tests=$Only.Split(',') }
    foreach($test in $tests) {
        # Full-frame raster tests need no interactive HDL debugging. Keep all
        # testbench assertions while avoiding costly per-signal debug access.
        $elaborationOptions=@('--O3','--debug','off')
        & $xelab $test -s $test @elaborationOptions
        if($LASTEXITCODE) { throw "Elaboration failed: $test" }
        & $xsim $test -runall
        if($LASTEXITCODE -or !(Select-String xsim.log -Pattern 'ALL TESTS PASSED' -Quiet)) {
            throw "Simulation failed: $test"
        }
        Copy-Item xsim.log "$test.log" -Force
    }
    if(!$NoAnalysis){
    & $Python ../tools/analyze_octaves.py
    if($LASTEXITCODE) { throw 'Octave PCM pitch analysis failed' }
    & $Python ../tools/analyze_sustain.py
    if($LASTEXITCODE) { throw 'Sustain audio analysis failed' }
    & $Python ../tools/analyze_dynamic_timbre.py
    if($LASTEXITCODE) { throw 'Dynamic timbre analysis failed' }
    & $Python ../tools/analyze_audio.py
    if($LASTEXITCODE) { throw 'Audio analysis failed' }
    & $Python ../tools/analyze_chords.py
    if($LASTEXITCODE) { throw 'Chord analysis failed' }
    & $Python ../tools/analyze_visual.py
    if($LASTEXITCODE) { throw 'Visual analysis failed' }
    & $Python test_serial_control.py
    if($LASTEXITCODE) { throw 'Serial host-tool tests failed' }
    & $Python test_measure_latency.py
    if($LASTEXITCODE) { throw 'Analog measurement tool tests failed' }
    & $Python ../tools/preserve_sim_media.py
    if($LASTEXITCODE) { throw 'Simulation media preservation failed' }
    }
} finally { Pop-Location }
