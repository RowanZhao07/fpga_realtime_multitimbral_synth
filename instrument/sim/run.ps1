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
    # Keep the vendor .v library in Verilog mode: XSim 2025.1 --sv silently
    # zero-initializes pROMX9.ram_MEM despite nonzero INIT_RAM parameters.
    & $xvlog $GowinSimLib
    if($LASTEXITCODE) { throw 'Gowin simulation library compilation failed' }
    & $xvlog --sv @sources tb_controls.sv tb_echo.sv tb_synthesis.sv tb_voice_quality.sv tb_touch_link.sv tb_pressure_link.sv tb_pressure_audio.sv tb_hc595.sv tb_board_clock.sv tb_spectrum.sv tb_video.sv tb_wallpaper.sv tb_visual_link.sv tb_serial_video.sv tb_latency.sv tb_uart_control.sv tb_uart_diagnostics.sv tb_uart_tx_notice.sv tb_score_upload.sv tb_remote_instrument.sv
    if($LASTEXITCODE) { throw 'RTL compilation failed' }
    & $xvlog --sv tb_lamp_diagnostics.sv tb_timbre_profiles.sv tb_i2s_audio.sv
    if($LASTEXITCODE) { throw 'Additional RTL test compilation failed' }
    foreach($test in @('tb_controls','tb_echo','tb_synthesis','tb_voice_quality','tb_timbre_profiles','tb_chord_audio','tb_i2s_audio','tb_touch_link','tb_pressure_link','tb_pressure_audio','tb_hc595','tb_key_lights','tb_lamp_diagnostics','tb_board_clock','tb_spectrum','tb_video','tb_wallpaper','tb_visual_link','tb_serial_video','tb_latency','tb_uart_control','tb_uart_diagnostics','tb_uart_tx_notice','tb_score_upload','tb_remote_instrument','tb_tempo')) {
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
    & $Python ../tools/analyze_chords.py
    if($LASTEXITCODE) { throw 'Chord analysis failed' }
    & $Python ../tools/analyze_visual.py
    if($LASTEXITCODE) { throw 'Visual analysis failed' }
    & $Python ../tools/analyze_wallpapers.py
    if($LASTEXITCODE) { throw 'Wallpaper pixel comparison failed' }
    & $Python test_serial_control.py
    if($LASTEXITCODE) { throw 'Serial host-tool tests failed' }
    & $Python ../tools/preserve_sim_media.py
    if($LASTEXITCODE) { throw 'Simulation media preservation failed' }
} finally { Pop-Location }
