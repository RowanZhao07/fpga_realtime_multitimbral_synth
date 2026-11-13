# EXPR M3 调度优化

M3 在 Tang Mega 60K NEO 上保持原有 32 声部、8 音色、48,828.125 Hz 采样率与演奏接口，缩短每帧合成的计算时间。引脚、时钟约束、传感器配置、波表数据和包络参数均沿用 M2。

## 下载与实板状态

[EXPR M3 8T Release](https://github.com/RowanZhao07/fpga_realtime_multitimbral_synth/releases/tag/expr-m3-20261113) 提供 M3 位流、构建 manifest、原始验证资料包及 `SHA256SUMS.txt`。验证资料包包含布局布线报告、17 项 RTL 日志、逐帧 CSV、八张界面预览，以及保留构建时字节内容的 56 个输入文件。

项目维护者于 **2026-11-13 确认新版已完成实板实测**。[实板状态记录](evidence/m3_hardware_status.json)单独保存该确认；本次发布没有新增逐项实板测量数据。下文量化结果仍分别来自 RTL 仿真与布局布线，既有示波器照片对应先前版本。

构建 manifest 和仿真摘要保留生成时的 `hardware_validated: false`，当前实板状态以上述独立记录为准。Git 按 LF 保存文本；[源码指纹](evidence/m3_source_fingerprints.json)同时记录构建时原始字节哈希与 LF 归一化哈希，以便核对 Release 输入和仓库源码。

## 调度变化

1. **成对搜索声部。** 奇偶两路分别比较候选槽，32 槽搜索由 32 拍缩短为 16 拍，再合并寄存的结果。仍按“首个空闲槽 → 最安静的释放槽 → 最老槽”分配；同包络取较小槽号，同年龄取较大槽号。遇到首对空闲槽立即结束搜索。
2. **跳过未分配槽。** 未占用槽只消耗一次扫描时钟。已占用但包络为零的槽继续按原规则处理，保留起音、相位和回收行为。
3. **重叠读取与插值。** 利用插值运算期间的 ROM 空档读取正弦参考点，每个已分配声部从 12 拍缩短为 11 拍，继续共享同一波表及插值运算通路。

## 同输入对照

使用本仓库提交 `72ef46a` 的合成器作为冻结参考。两版接收同一组输入，每 1024 个 50 MHz 时钟启动一帧。表中时钟数从采样使能被接收开始，计至 `valid`；不代表传感器至模拟输出的整机延迟。

| 场景 | M2 时钟数 | M3 时钟数 |
|---|---:|---:|
| 空闲帧 | 400 | 48 |
| 单声部持续发声 | 400 | 58 |
| 32 槽占用、无新起音 | 400 | 368 |
| 密集起音、满池抢占的测试最大值 | 829 | 589 |
| 对应最重帧预算余量 | 195 / 1024（19.04%） | 435 / 1024（42.48%） |

最重帧减少 240 时钟，即 28.95%；在 50 MHz 下为 4.8 μs 的计算时间。I²S 继续按固定采样节奏发送，这一节省主要增加调度余量。

调度成本也可从状态序列核算：无新起音时为 `48 + 10 × 已占用槽数`；每个新起音至多增加 16 拍搜索和 1 拍分配。32 槽全部占用、13 键同时重触发时为 `48 + 10 × 32 + 17 × 13 = 589` 拍，与回归峰值一致。

`tb_engine_equivalence` 对普通延音与表情演奏两种配置分别比较 13,496 帧，共 **26,992 帧**。覆盖八音色、四音区、13 键同时起音、32 声部满池、随机门控、正负弯音、颤音、延音强度边界、释放至精确静音及忙时复位。每帧检查 PCM、声部数、键位电平，并逐槽检查相位、频率、年龄、音色、包络、抢占尾音等状态。所有比较通过，每帧各产生一次有效输出，没有超时。

该对照针对测试中按采样帧给出的控制序列，不是对所有异步输入时刻的形式化等价证明。仿真生成的逐帧 CSV 另存于 `outputs/expression-m3-scheduler/regression/` 并随 Release 分发，摘要包含输入与 CSV 的 SHA256，见[对照摘要](evidence/m3_engine_equivalence.json)。

## 复现

```powershell
./instrument/sim/run.ps1 -VivadoBin '<Vivado>/bin' -GowinSimLib '<Gowin IDE>/simlib/gw5a/prim_sim.v' -NoAnalysis -Only 'tb_engine_equivalence,tb_voice_allocator,tb_expression_allocator,tb_eight_timbres'
python instrument/tools/analyze_engine_equivalence.py
./instrument/build.ps1 -GowinShell '<Gowin IDE>/bin/gw_sh.exe'
```

冻结参考只参与仿真，不加入 Gowin 综合工程。构建输出为 `dist/instrument_expression_m3_scheduler.fs` 及同名 manifest；屏幕版本为 `EXPR M3 8T`。M2 位流与[原发布证据](release_verification.md)单独保留。

## 布局布线

Gowin 1.9.12.03 对完整 `instrument_top` 重新综合和布局布线，器件仍为 `GW5AT-LV60PG484AC1/I0`；系统、像素与显示串行时钟仍为 50、40、200 MHz。

| 资源 | M2 | M3 | 器件容量 |
|---|---:|---:|---:|
| Logic | 36,017 | 36,546 | 59,904 |
| Register | 8,760 | 8,818 | 60,780 |
| BSRAM | 99 | 99 | 118 |
| DSP | 39 | 39 | 118 |

增加 529 个 Logic、58 个寄存器；BSRAM 与 DSP 数量不变。M3 Logic 占用为 61.01%，Register 为 14.51%。Setup / Hold 违规端点均为 0，系统域报告 Fmax 为 50.408 MHz。

| 时序检查 | M3 最小余量 ns |
|---|---:|
| Setup | 0.162 |
| Hold | 0.050 |
| Recovery | 0.175 |
| Removal | 0.589 |
| 最小脉宽 | 5.859 |

PR1014 提示 `ref_clk_d` 使用通用布线资源；M2 原始构建日志中也存在同一警告。本轮保持现有引脚和时钟约束，并保留警告记录，不把时序通过表述为零警告。完整工具报告保存在 `outputs/expression-m3-scheduler/`，[构建摘要](evidence/m3_build_summary.json)记录资源、时序、位流哈希与验证边界。

位流 SHA256：`5DF395F013DA8425ACF4D415A3C544D82C917CD5A42A715334E4B986EFD30FAD`，大小 20,706,987 bytes。56 个构建输入与当前源码的 SHA256 全部一致；M2 位流哈希仍为原交付值。

## 完整链路与验证边界

八相位数字响应回归仍为 **47.93～65.87 μs**，条件为 T0、节拍器关闭、控制状态入口至完整非零 I²S 样本，见[M3 原始数值](evidence/m3_latency_expression.csv)。更早完成计算没有改变固定的 I²S 发送节奏。

共 **17 项 RTL 回归、19 项 Python 单元测试通过**，另完成八音色 I²S 音频分析与动态谐波分析。逐项结果及日志哈希见[回归摘要](evidence/m3_regression.json)。

| 验证组 | 检查内容 |
|---|---|
| 引擎对照与分配 | 26,992 帧 PCM / 状态一致；密集起音、满池抢占、八音色及跨音区尾音 |
| 数字音频 | 164,211 个立体声 I²S 帧；八音色音高与区分、声道一致、释放静音 |
| 包络与输出 | 八音色 × 16 档延音、主音量、限幅、最大压力与满音量、动态谐波 |
| 表情与节拍器 | 实际 UART 命令、弯音、音效、节拍器静音与关闭旁路、8767 帧 I²S |
| 完整顶层 | 触摸 / ADC 总线模型、NACK / SCL 拉低 / 过流恢复、HDMI 状态、摇杆与显示通路 |
| 完整画面 | M3 版本字样、在线 / 离线画面、8 张壁纸、文字边界与无未知像素；已查看导出预览 |

可复现本轮集成检查：

```powershell
./instrument/sim/run.ps1 -VivadoBin '<Vivado>/bin' -GowinSimLib '<Gowin IDE>/simlib/gw5a/prim_sim.v' -NoAnalysis -Only 'tb_expression_core,tb_metronome_core,tb_expression_effects,tb_expression_latency,tb_i2s_audio,tb_dynamic_timbre,tb_variable_sustain,tb_output_level,tb_limit_activity,tb_full_scale_audio,tb_expression_touch_link,tb_expression_top,tb_expression_screen'
python instrument/tools/analyze_eight_timbres.py
python instrument/tools/analyze_dynamic_timbre.py
python -m unittest discover -s instrument/sim -p 'test_*.py'
```

原始回归数据和日志另存于 `outputs/expression-m3-scheduler/regression/` 并随 Release 分发，避免后续仿真覆盖。实板状态与仿真、布局布线结果分别记录，便于按验证层级复核。
