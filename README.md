# 弦外之芯——实时复音合成器

**U tEll the DJ to plAY this soNG!**

![弦外之芯，一拍即核团队](assets/showcase/xianwai-zhixin-landscape-v1.png)

**一拍即核团队 | 2026 FPGA 创新设计竞赛 | 高云赛道赛题二**

**以确定性实时音频计算为核心的纯 FPGA 电子乐器。** 基于 Tang Mega 60K NEO，32 组独立声部状态通过共享运算核逐样本生成声音，接入八种音色、硬件效果器、演奏表情与练习指引。完整发声通路由 HDL 实现，经 I²S 送入 DAC；波形、频谱与琴键灯同步反馈演奏状态。

## 设计特点

- **32 声部 & 固定采样预算。** 独立相位、频率、音色与 ADSR 状态；M3 负载回归最重帧 589 / 1024 时钟，保留 435 时钟调度余量。重触发保留旧尾音，抢占附加 8 样本淡出。
- **逐样本合成 & 硬件效果。** 数学波表、线性插值、包络与混音全部在 FPGA 内完成；混响采用 4 路阻尼反馈梳状滤波与 2 级全通，合唱采用分数延迟插值。
- **演奏 & 分析 & 练习。** 触摸、压力、摇杆与旋钮连接演奏动作；4096 点 FFT 独立于合成运行，配合脱机曲谱、蓝牙参数控制和五拍号节拍器。

## 核心参数

| 项目 | 最终实现 |
|---|---|
| 复音引擎 | 32 组独立声部状态；最重 RTL 合成帧 589 / 1024 时钟 |
| 调度容量 | 1,562,500 声部采样 / 秒；采样帧剩余 435 时钟，约 42.48% |
| 音键与音色 | 13 键、4 档音区、49 个不同音高；8 种数学波表音色 |
| 数字音频 | 16 bit I²S；标称采样率 48,828.125 Hz |
| 核心数字响应 | **47.93～65.87 μs**；T0、节拍器关闭、8 个触发相位；控制状态入口 → 完整非零 I²S 样本 |
| 示波器事件读数 | **472 μs**：IRQ 下降沿 → LOUT 首次明显突变附近；**1.75 ms**：IRQ 下降沿 → LOUT 后续变化 |
| 表情采样周期 | **9.97572 ms / 通道**（约 100.24 Hz）；三通道 ADS1115、100 kHz I²C、2 ms 转换等待模型 |
| 视听反馈 | 800 × 600 HDMI、512 点波形、4096 点 Hann FFT、13 路键灯；FFT 频点间隔 **11.9209 Hz** |
| 节拍器 | 2/2、2/4、3/4、4/4、6/8；40～240 BPM，强弱拍与屏幕拍点同步 |
| 脱机指引 | 内置 76 音《遇见》片段，按对推进；UART 曲谱容量 512 步 |
| FPGA 资源 | Logic **61.01%**；Register **14.51%**；BSRAM **83.90%**；DSP **33.05%** |
| 布局布线时序 | Setup / Hold 违规端点均为 **0**；最小余量分别为 **0.162 ns / 0.050 ns** |

M3 调度优化与 M2 完成 **26,992 帧 PCM / 声部状态对照**，最重帧计算时钟数减少 **28.95%**。32 声部容量及调度结果由 RTL 负载回归验证，现有频谱校准模式使用 8 路独立正弦音。上表资源与时序对应 **EXPR M3 8T** 完整布局布线；42.48% 为采样帧预算余量。项目维护者于 **2026-11-13 确认新版已完成实板实测**，见[实板状态记录](docs/evidence/m3_hardware_status.json)。工具警告与原始记录见[M3 优化验证](docs/scheduler_optimization.md)，先前交付见[M2 发布验证](docs/release_verification.md)。

## 时延测量

Tektronix TBS1102C 同步采集 **CH1：MPR121 IRQ** 与 **CH2：PCM5102 LOUT**，两通道均为 1 V/div、公共地参考。

| IRQ → LOUT 首次明显突变附近 | IRQ → LOUT 后续变化 |
|---|---|
| ![IRQ 与 LOUT，游标间隔 472 微秒](assets/measurements/time_delay_2.jpg) | ![IRQ 与 LOUT，游标间隔 1.75 毫秒](assets/measurements/time_delay.jpg) |
| **Δt = 472 μs**；100 μs/div，12.5 MS/s | **Δt = 1.75 ms**；200 μs/div，6.25 MS/s |

两图保留先前版本的实测记录，分别报告游标所选电气事件间隔；数字核心的 47.93～65.87 μs 则来自 M3 RTL 回归，从 FPGA 控制状态入口计时至完整 I²S 样本。三者的端点与条件分别列示，便于复核。[原图判读与测量步骤](docs/latency_measurement.md)

## 演奏与练习

短按 TONE/C0 依次选择正弦、电钢琴、弦乐、金属、长笛、管风琴、拨弦、贝斯；长按切换数字效果。摇杆切换音区，压力片连续调节音量，EC11 控制延音与 16 档衰减。

节拍器上电默认关闭、120 BPM、4/4。按住 LED_TEST/X0，配合 VIB 开关、TONE 切换拍号、VOL± 持续调速。6/8 按附点四分音符计 BPM，并发出六个八分音符细分拍点。

[完整操作](docs/usage.md) & [八种音色](docs/eight_timbres.md) & [节拍器](docs/metronome.md) & [表情与音效](docs/expression_controls.md)

## 界面预览

下列八图为 **EXPR M3 8T 的 800 × 600 RTL 仿真截图**。左下角显示 BPM、拍号与拍点，频谱区以相邻频点峰值压缩保留细峰。波形与延迟 XY 的 3X 增益只作用于绘图，音频和 FFT 使用原始 PCM。

<table>
  <tr>
    <td width="25%"><img src="assets/simulation/wallpapers/01.png" alt="节拍器与壁纸界面"></td>
    <td width="25%"><img src="assets/simulation/wallpapers/02.png" alt="节拍器与壁纸界面"></td>
    <td width="25%"><img src="assets/simulation/wallpapers/03.png" alt="节拍器与壁纸界面"></td>
    <td width="25%"><img src="assets/simulation/wallpapers/04.png" alt="节拍器与壁纸界面"></td>
  </tr>
  <tr>
    <td><img src="assets/simulation/wallpapers/05.png" alt="节拍器与壁纸界面"></td>
    <td><img src="assets/simulation/wallpapers/06.png" alt="节拍器与壁纸界面"></td>
    <td><img src="assets/simulation/wallpapers/07.png" alt="节拍器与壁纸界面"></td>
    <td><img src="assets/simulation/wallpapers/08.png" alt="节拍器与壁纸界面"></td>
  </tr>
</table>

## 构建与使用

活动工程：[`instrument/instrument_expression.gprj`](instrument/instrument_expression.gprj)，器件 `GW5AT-LV60PG484AC1/I0`，顶层 `instrument_top`。

直接下载位流与原始验证资料：[EXPR M3 8T Release](https://github.com/RowanZhao07/fpga_realtime_multitimbral_synth/releases/tag/expr-m3-20261113)。下载后可用 `Get-FileHash -Algorithm SHA256` 与 Release 附带的 `SHA256SUMS.txt` 核对。

```powershell
# Gowin 1.9.12.03
./instrument/build.ps1 -GowinShell '<Gowin IDE>/bin/gw_sh.exe'

# XSim / Vivado 2025.1，GW5A 官方原语库
./instrument/sim/run.ps1 -VivadoBin '<Vivado>/bin' -GowinSimLib '<Gowin IDE>/simlib/gw5a/prim_sim.v' -NoAnalysis -Only 'tb_engine_equivalence,tb_metronome_control,tb_metronome_audio,tb_metronome_core,tb_expression_latency,tb_expression_screen'

# 导出曲谱命令
python instrument/tools/serial_control.py --score assets/scores/yujian.txt --bpm 93 --emit
```

构建生成 `dist/instrument_expression_m3_scheduler.fs` 和同名 manifest。下载选择 **GW5AT-60B → SRAM Program**，屏幕版本为 **EXPR M3 8T**。M3 的实板验证状态见[优化验证](docs/scheduler_optimization.md)。

[工程打开说明](instrument/OPEN_IN_GOWIN.md) & [接线清单](docs/wiring_current.md)

## 仓库内容

| 目录 | 内容 |
|---|---|
| `instrument/src` | 合成、效果、节拍器、传感、I²S 与 HDMI RTL |
| `instrument/sim` | 模块、核心、顶层与接口回归 |
| `instrument/tools` | 曲谱、ROM 生成、音频分析与发布核查 |
| `assets` | 波表、曲谱、壁纸、界面及测量照片 |
| `docs` | 当前操作、接线、实现及验证说明 |

位流存放于本地 `dist/` 并通过 Release 分发；原始布局布线与回归资料存放于本地 `outputs/`，本次验证资料同时打包到 Release。构建缓存及历史资料归档于本地 `.local/`；视频素材、成片、剪辑工程与接线绘图在本地独立保存，均不进入源码仓库。

琴体外壳与支架经多轮拓竹 3D 打印完成，底板 PCB 与定制触摸键盘由嘉立创提供，壁纸取材于 Phigros。
