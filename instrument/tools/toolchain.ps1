# Explicit parameters > environment variables > PATH. No machine-specific defaults.
function Resolve-ToolFile {
    param([string]$Value, [string]$Command, [string]$Hint)
    if ($Value) {
        if (!(Test-Path -LiteralPath $Value -PathType Leaf)) { throw "File not found: $Value. $Hint" }
        return (Resolve-Path -LiteralPath $Value).Path
    }
    $found = Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.Source }
    throw "Cannot locate $Command. $Hint"
}

function Resolve-GowinShell {
    param([string]$Value)
    if (!$Value) { $Value = $env:GOWIN_SHELL }
    if (!$Value -and $env:GOWIN_HOME) { $Value = Join-Path $env:GOWIN_HOME 'bin/gw_sh.exe' }
    Resolve-ToolFile $Value 'gw_sh.exe' 'Pass -GowinShell, set GOWIN_SHELL/GOWIN_HOME (the IDE directory), or add Gowin bin to PATH.'
}

function Resolve-GowinSimLib {
    param([string]$Value)
    if (!$Value) { $Value = $env:GOWIN_SIMLIB }
    if (!$Value) {
        $ideRoot = $env:GOWIN_HOME
        if (!$ideRoot) { $ideRoot = Split-Path (Split-Path (Resolve-GowinShell) -Parent) -Parent }
        $Value = Join-Path $ideRoot 'simlib/gw5a/prim_sim.v'
    }
    Resolve-ToolFile $Value '' 'Pass -GowinSimLib or set GOWIN_SIMLIB to the GW5A prim_sim.v file.'
}

function Resolve-XSimTool {
    param([string]$Bin, [string]$Name)
    if (!$Bin) { $Bin = $env:VIVADO_BIN }
    if (!$Bin -and $env:XILINX_VIVADO) { $Bin = Join-Path $env:XILINX_VIVADO 'bin' }
    $value = if ($Bin) { Join-Path $Bin "$Name.bat" } else { '' }
    Resolve-ToolFile $value "$Name.bat" 'Pass -VivadoBin, set VIVADO_BIN/XILINX_VIVADO, or add Vivado bin to PATH.'
}
