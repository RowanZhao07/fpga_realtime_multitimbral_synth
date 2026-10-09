# FPGA 实时多音色电子乐器

Tang Mega 60K（GW5AT-60B）+ MPR121 + PCM5102 + HDMI 屏，纯 Verilog 实现。

- 已实现：八复音、四音色、ADSR、音量、颤音、延迟效果、波形/FFT 显示、按键练习指引。
- 已验证：基线十项仿真及布局布线通过（历史记录）；本轮验证状态见改进报告；实物整机和端到端延迟仍待测。
- 未实现：32 复音、压力感应、蓝牙、录音。暂不宣称达到 ≤10 ms 指标。
- 那个led_flow是验证板子work正常与否的工具，不在整个工程里面。

## 编译与使用

使用 Gowin V1.9.12.03，在仓库根目录执行：

```powershell
$env:GOWIN_HOME = Read-Host 'Gowin IDE 文件夹路径'
powershell -NoProfile -ExecutionPolicy Bypass -File .\instrument\build.ps1
```

用 Gowin Programmer 的 **SRAM Program** 下载 `instrument/impl/pnr/instrument.fs`，断电后需重新下载。

接线：J13 的 1→SCL、2→SDA、3→BCK、4→LRCK、5→DIN。MPR121 用 3.3V、ADD 接地；PCM5102 沿用 5V 供电，SCK 接地、FMT 低、XSMT 高，所有模块共地。核对模块标识，勿盲接焊盘。

K0～K7 演奏；C0 短按切换音色、长按切换延迟；C1/C2 调音量；C3 颤音。HDMI 输出固定 800×600，声音由 DAC 输出。波形使用独立过零触发采集，键盘显示按下、包络释音和目标音。

## 仿真

准备 XSim 和 Python（本轮使用 XSim 2018.3 验证），在同一终端执行：

```powershell
python -m pip install -r .\instrument\tools\requirements.txt
$env:VIVADO_BIN = Read-Host 'Vivado bin 文件夹路径'
powershell -NoProfile -ExecutionPolicy Bypass -File .\instrument\sim\run.ps1
```

源码在 `instrument/src/`，测试在 `instrument/sim/`，分析结果生成到 `instrument/sim/output/`。`led_flow/` 保留独立流水灯测试，打开其 `.gprj` 即可编译。

本轮改动说明见 [改进报告](docs/improvement_report.md)，听音算法预留接口见 [接口说明](docs/listening_interface.md)。贡献者与修改理由见 [CONTRIBUTORS](CONTRIBUTORS.md)。

频谱与波形显示灵感来自 [Music-Spectrum](https://github.com/aystmjz/Music-Spectrum)。
