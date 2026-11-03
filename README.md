# 弦外之芯——实时复音合成器

![弦外之芯，一拍即核团队](assets/showcase/xianwai-zhixin-landscape-v1.png)

**一拍即核团队 | 2026 FPGA 创新设计竞赛 | 高云赛道赛题二**

以 Tang Mega 60K NEO 为核心的电子乐器。FPGA 独立完成逐样本发声、复音混合、数字效果和视听反馈；触摸琴键选择音符，压力片、摇杆和旋钮控制演奏表情。声音由数学波表与包络实时生成，无需处理器或预录 PCM。

## 设计特点

- **32 声部确定性调度。** 每声部保存独立相位、频率、音色与包络，复用运算资源；重按与跨音区演奏保留旧尾音，满载抢占采用短淡出。
- **声音与分析并行。** 音频按固定采样节拍运行，4096 点 FFT 独立处理；波形、频谱、延迟李萨如与琴键灯共同反馈演奏状态。
- **从演奏到练习。** 八种合成音色、延迟／混响／合唱、压力与延音控制，结合脱机曲谱指引、蓝牙参数控制和电子节拍器。

## 核心参数

| 项目 | 最终实现 |
|---|---|
| 复音引擎 | 32 组独立声部状态；最重 RTL 合成帧 829 / 1024 时钟 |
| 调度容量 | 1,562,500 声部采样 / 秒；采样帧剩余 195 时钟，约 19.04% |
| 音键与音色 | 13 键、4 档音区、49 个不同音高；8 种数学波表音色 |
| 数字音频 | 16 bit I²S；标称采样率 48,828.125 Hz |
| 核心数字响应 | 47.93～65.87 μs，T0、8 个触发相位，数字状态入口至完整非零 I²S 样本 |
| 视听反馈 | 800 × 600 HDMI、512 点波形、4096 点 Hann FFT、13 路键灯 |
| 节拍器 | 2/2、2/4、3/4、4/4、6/8；40～240 BPM，强弱拍与屏幕拍点同步 |
| 脱机指引 | 内置 76 音《遇见》片段，按对推进；UART 曲谱容量 512 步 |
| FPGA 资源 | Logic 36,017 / 59,904；BSRAM 99 / 118；DSP 39 / 118 |

调度容量与数字响应来自 RTL 回归，资源来自最终 M2 布局布线报告。数字响应计量区间不包含 MPR121 感知与 DAC 模拟输出。测试条件、版本与文件校验值见[发布验证](docs/release_verification.md)。

## 演奏与练习

短按 TONE/C0 依次选择正弦、电钢琴、弦乐、金属、长笛、管风琴、拨弦、贝斯；长按切换数字效果。摇杆切换音区，压力片连续调节音量，EC11 控制延音与 16 档衰减。

节拍器上电默认关闭、120 BPM、4/4。按住 LED_TEST/X0，配合 VIB 开关、TONE 切换拍号、VOL± 持续调速。6/8 按附点四分音符计 BPM，并发出六个八分音符细分拍点。

[完整操作](docs/usage.md) · [八种音色](docs/eight_timbres.md) · [节拍器](docs/metronome.md) · [表情与音效](docs/expression_controls.md)

## 界面预览

下列八图为 **EXPR M2 8T 的 800 × 600 RTL 仿真截图**。左下角显示 BPM、拍号与拍点，频谱区以相邻频点峰值压缩保留细峰。波形与延迟 XY 的 3X 增益只作用于绘图，音频和 FFT 使用原始 PCM。

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

## 现场测量记录

Tektronix TBS1102C 双通道记录 MPR121 IRQ 与 PCM5102 LOUT。两张照片分别保留 **472 μs** 与 **1.75 ms** 的游标间隔；前者标记 IRQ 下降沿至模拟输出突变附近，后者右侧光标位于更晚的一次输出变化。记录量为具体波形事件间隔，未把它们作为整机起音延迟或 p95 统计。接线、原图与判读见[测量记录](docs/latency_measurement.md)。

## 构建与使用

活动工程：[`instrument/instrument_expression.gprj`](instrument/instrument_expression.gprj)，器件 `GW5AT-LV60PG484AC1/I0`，顶层 `instrument_top`。

```powershell
# Gowin 1.9.12.03
./instrument/build.ps1 -GowinShell '<Gowin IDE>/bin/gw_sh.exe'

# XSim / Vivado 2025.1，GW5A 官方原语库
./instrument/sim/run.ps1 -VivadoBin '<Vivado>/bin' -GowinSimLib '<Gowin IDE>/simlib/gw5a/prim_sim.v' -NoAnalysis -Only 'tb_metronome_control,tb_metronome_audio,tb_metronome_core,tb_expression_latency,tb_expression_screen'

# 导出曲谱命令
python instrument/tools/serial_control.py --score assets/scores/yujian.txt --bpm 93 --emit
```

构建生成 `dist/instrument_expression_metronome_v2_louder.fs` 和同名 manifest。下载选择 **GW5AT-60B → SRAM Program**，屏幕版本为 **EXPR M2 8T**。构建脚本核对输入哈希、位流时间以及时序报告。

[工程打开说明](instrument/OPEN_IN_GOWIN.md) · [接线清单](docs/wiring_current.md)

## 仓库内容

| 目录 | 内容 |
|---|---|
| `instrument/src` | 合成、效果、节拍器、传感、I²S 与 HDMI RTL |
| `instrument/sim` | 模块、核心、顶层与接口回归 |
| `instrument/tools` | 曲谱、ROM 生成、音频分析与发布核查 |
| `assets` | 波表、曲谱、壁纸、界面及测量照片 |
| `docs` | 当前操作、接线、实现及验证说明 |
| `videos` | 可复现剪辑脚本、时间表与节拍器台词 |

原始视频、配音、位流和构建缓存单独保存，不进入 Git。[视频工程](videos/README.md) · [团队贡献与素材来源](docs/collaboration_update.md)
