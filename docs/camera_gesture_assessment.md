# 摄像头无接触手势可行性评估

日期：2026-10-24
对象：`D:\brat\fpga_realtime_multitimbral_synth`（Tang Mega 60K NEO / GW5AT-60B）
性质：代码与赛题核对 + 公开资料调研 + 资源/延迟工程估算。**未新增 RTL、未上板、未实测模拟延迟。**

## 1. 结论先行

1. **当前工程的基础要求大体已经满足**：13 个音键（8 白 + 5 黑）、四音区、32 声部、四音色、逐声部 ADSR、逐样本波表合成、I²S 到 PCM5102，全部是纯 HDL，没有处理器、没有预录 PCM。基础第 1、2、3 条的主要缺口不是“能不能发声”，而是**整机 ≤10ms 尚未实测**、**单音实时变调/滑音没有实现**、**拨弦没有实现**。
2. **摄像头在数值资源上做得到，但只能做“手势辅助层”**。按 160×120、帧差 + 包围盒/质心 + 手势状态机的方案估算，约 **1.5–2.5k LUT、9 个 BSRAM、0–2 个 DSP**；当前剩余约 31.9k LUT、13.1k CLS、86 BSRAM、86.5 DSP，数字上够。真正的问题是 **50MHz setup 余量只有 0.142ns、CLS 已用 57%**，加逻辑后是否还能收敛，必须先用一次布局布线试验回答。
3. **摄像头不能进入 ≤10ms 的起音路径**。30fps 单帧 33.3ms，60fps 单帧 16.7ms；加上曝光/读出、2–3 帧识别和去抖，实际手势响应约 **50–150ms**。它适合控制音色、音区、效果、亮度等“慢变/离散”参数，**不适合 note-on、力度、拨弦、pitch bend**。
4. **已有光电方案比摄像头更适合“无接触演奏”**：双光束 2ms 响应，适合扫弦触发；VL53L0X 20–33ms，适合手位→音色明暗。它们已经买了、延迟更低、资源更小。摄像头真正的增量是 **2D 离散手势 + 视觉展示**，不是核心演奏维度。
5. **推荐路线**：先补基础缺口（整机延迟实测、pitch bend/滑音、混响/合唱、双光束+ToF），再把摄像头作为可选的“手势预选 + HDMI 跟踪框”展示层。若做摄像头，采用 **摄像头预选音色/音区/亮度 + 光束负责起音/扫弦** 的混合架构，不要让摄像头直接触发音符。

## 2. 工程通读与赛题核对

### 2.1 数据流与关键模块

系统只有一个 50MHz 主时钟域和一个 40MHz/200MHz 视频域，音频采样率 48,828.125Hz（50MHz / 1024），每个采样周期 1024 个时钟：

- **触摸**：两片 MPR121（独立 I²C，0x5A）→ `touched[17:0]`；13 个音键 + 4 个控制键 + X0 音区修饰。[instrument_top.v](../instrument/src/instrument_top.v:31)
- **压力**：ADS1115（0x48）读 FSR → `pressure_mv[11:0]`，作为**全局**主增益/力度，不是每键力度。[instrument_top.v](../instrument/src/instrument_top.v:36) [instrument_core.v](../instrument/src/instrument_core.v:92)
- **演奏控制**：`performance_control` 产生 `gates[12:0]`、`timbre[1:0]`、`volume[12:0]`、`octave_select`、`vibrato`、`spectrum_mode`、`echo_enabled`、`guide_enabled`。[performance_control.v](../instrument/src/performance_control.v:33)
- **合成引擎**：`polyphonic_engine` 保存 32 份独立相位/步进/年龄/音色/亮度/包络状态；每个采样周期用一个共享流水线依次处理 32 个声部（每声部约 12 个状态），最后固定 6dB 余量混音。[polyphonic_engine.v](../instrument/src/polyphonic_engine.v:15) [polyphonic_engine.v](../instrument/src/polyphonic_engine.v:90) [polyphonic_engine.v](../instrument/src/polyphonic_engine.v:128)
- **音色**：`timbre_lut` 4×256 点数学波表；每个声部把“富波表”和“纯正弦”按 `brightness` 混合，形成随时间变化的泛音。[timbre_lut.v](../instrument/src/timbre_lut.v:3) [polyphonic_engine.v](../instrument/src/polyphonic_engine.v:141)
- **包络**：每声部一个 `envelope_adsr`，四种音色不同 attack/decay/sustain/release；延音踏板可保持。[envelope_adsr.v](../instrument/src/envelope_adsr.v:15)
- **效果**：`audio_output` 只有前馈 echo（16,384 样本延迟 RAM）、音量平滑、限幅；没有 reverb/chorus。[audio_output.v](../instrument/src/audio_output.v:13)
- **输出**：`i2s_transmitter` 双声道 16bit，BCK 3.125MHz、LRCK 48.828kHz。[i2s_transmitter.v](../instrument/src/i2s_transmitter.v:12)
- **可视化**：HDMI 800×600；`audio_spectrum` 做 4096 点 Hann 窗 FFT、512 根谱线；`waveform_capture` 512 点波形；`instrument_screen` 画琴键、波形、频谱、GUIDE、声部数；`visual_buffer` 双缓冲在垂直消隐切换。[audio_spectrum.v](../instrument/src/audio_spectrum.v:3) [instrument_screen.v](../instrument/src/instrument_screen.v:27)
- **GUIDE**：内置 192 步原创曲、512 步上传容量；等待正确键/和弦后计时，LED 与屏幕同步。[practice_guide.v](../instrument/src/practice_guide.v:1)
- **蓝牙**：9600 8N1 UART，T/V/E/H/G/B/R/N/A/Z/O/U/D/J/L 命令；可上传曲谱、控制音色/音量/延音/回声/GUIDE。[uart_control.v](../instrument/src/uart_control.v:1)

### 2.2 已经做到的

- 32 个独立声部，13 键同时按下可累积到 32 个尾音；满载时先回收最轻释放声部，最后抢占最老声部，8 样本淡出。
- 四音色（正弦、电钢琴感、合成弦乐、金属音），每声部锁定起音时的音色，旧尾音不被全局切换。
- 逐声部 ADSR、颤音（全局 LFO）、延音、压力→主增益、echo。
- 4096 点实时频谱、512 点波形、13 键灯、GUIDE、HDMI 键位/声部/音名。
- 41 项 RTL 回归、14 项 Python 测试、六类数值分析通过；布局布线通过。[upgrade_verification.md](upgrade_verification.md:32)
- 数字“触摸状态 → 解码后首个非零 I²S 样本”最大 0.10683ms（8 个事件相位）。[verification.json](../.local/verification/upgrade-20261022/verification.json:66)

### 2.3 资源与时序基线

来自 2026-10-22 的布局布线报告：[instrument.rpt.txt](../.local/verification/upgrade-20261022/instrument.rpt.txt) [verification.json](../.local/verification/upgrade-20261022/verification.json:74)

| 资源 | 已用 / 总量 | 占用 | 剩余 |
|---|---:|---:|---:|
| Logic（LUT+ALU） | 27,967 / 59,904 | 47% | 31,937 |
| CLS | 16,845 / 29,952 | **57%** | **13,107** |
| 逻辑寄存器 FF | 6,738 / 59,904 | 12% | 53,166 |
| BSRAM | 32 / 118 | 28% | 86 |
| DSP | 31.5 / 118 | 27% | 86.5 |
| IOLOGIC | 8 / 293 | 3% | 285 |

时序（50MHz 系统域、40MHz 像素域、200MHz 串行域）：

| 检查 | 最差余量 |
|---|---:|
| Setup | **+0.142ns** |
| Hold | +0.046ns |
| Recovery | +0.107ns |
| Removal | +0.651ns |
| 最小脉宽 | +5.594ns |

**关键判断**：不能按“LUT 还剩 53%”推断一定能加摄像头。CLS 已 57%，setup 只有 0.142ns；新增 2k LUT 本身不大，但布线和时钟域交叉可能把余量吃掉。必须做一次“带摄像头空壳”的综合/布局布线试验。

### 2.4 赛题逐条核对

| 赛题条目 | 当前实现 | 判定 | 说明 |
|---|---|---|---|
| 基础 1：自研交互、≥2 个独立维度 | 13 音键（8 白 + 5 黑）+ X0 音区 + 4 控制键 + FSR | 满足 | 选音、和弦、触发、音区、压力、颤音、音色、延音，维度足够 |
| 基础 1：选音/和弦/触发 | `gates[12:0]` 多键掩码；32 声部分配 | 满足 | 13 键可同时按下；和弦可跨声部 |
| 基础 1：拨弦 | 无 | **缺口** | 目前只有规划中的双光束；摄像头也不适合做 ≤10ms 拨弦 |
| 基础 1：力度感应 | 单块 FSR → 全局主增益 | **部分** | README 明确写“不是每键力度”；若评委要求每键力度，这是风险 |
| 基础 2：纯 HDL、逐样本、逐声部 | 波表 + 泛音混合 + 32 声部共享流水线 | 满足 | 无 CPU/MCU/预录 PCM |
| 基础 2：控制到音频 ≤10ms | 数字段 0.107ms；整机未测 | **未证明** | 估算触摸前端 + DAC 约 3–4ms，但必须示波器实测 |
| 基础 2：无软件串行滞后 | 全硬件状态机 | 满足 | 音频引擎在 1024 时钟/样本内完成 |
| 基础 3：复音 ≥4、四路以上并发 | 32 声部 | 满足 | 最大 32 个独立包络/相位 |
| 基础 3：单音实时变调 | 无 pitch bend/portamento；只有颤音 LFO | **缺口** | `steps[]` 在起音时锁定；没有滑音/弯音输入 |
| 基础 3：ADSR、多声部混音 | 每声部 ADSR；固定 6dB 余量混音 | 满足 | 抢占时 8 样本淡出 |
| 基础 3：禁止预录 PCM | 数学波表逐样本生成 | 满足 | 没有 PCM 播放器 |
| 拓展 1：复音 ≥32 或 32 路加法/多物理建模 | 32 声部 | 满足（第一分支） | 但 32 声部是**时分复用共享流水线**，不是 32 套并行振荡器；“最大化并行”是定性风险 |
| 拓展 2：≥3 维表情、力度/滑音/颤音 | 压力、颤音；无滑音 | **部分** | 连续表情目前主要是压力 + 颤音；第三维可用 ToF/摄像头补 |
| 拓展 2：≥2 音色自由切换 | 4 音色 | 满足 | C0 短按切换；UART T0–T3 |
| 拓展 2：混响/延迟/合唱 | 只有 echo/delay | **缺口** | 没有 reverb/chorus；这是拓展 2 的明确失分点 |
| 拓展 3：≤5ms 确定性延迟 | 数字段 0.107ms；整机未测 | **未证明** | MPR121 轮询/I²C 会带来抖动；≤5ms 比 ≤10ms 紧得多 |
| 拓展 3：LED/李萨如/频谱/波形 | LED 指引、4096 点频谱、512 点波形 | 部分满足 | 李萨如没有；“等”是举例，但加一个很便宜 |
| 拓展 4：脱机 LED 曲目指引 | 192 步 GUIDE + 13 键灯 | 满足 | 原创《夜航练习曲》 |
| 拓展 4：蓝牙 App/在线曲谱/键位自定义/录音回传 | BT05 UART、曲谱上传 | **部分** | 没有手机 App、在线下载、录音回放；键位自定义只到曲谱掩码级 |

**总体**：基础 1/2/3 的“发声与复音”已经很强；最该补的是 **整机 ≤10ms 实测、pitch bend/滑音、拨弦、混响/合唱**。摄像头不解决这些，反而会占用最紧的时序余量。

## 3. 调研：FPGA 视觉算法与无接触手势

### 3.1 算法家族与 FPGA 成本

以下成本是“在 60K LUT / 2.1Mb BSRAM / 118 DSP 这个量级”的工程估算；标“文献”的来自公开实现，标“估算”的需要综合验证。

| 方案 | 典型做法 | 资源量级 | 延迟 | 适用性 |
|---|---|---|---|---|
| 帧差/背景减除 + 投影/包围盒 | 低分辨率灰度，存一帧背景，阈值、列/行投影、bbox/质心 | **1–3k LUT，3–9 BSRAM，0–2 DSP**（估算） | 1–3 帧 | **最适合**；对固定舞台、固定光照稳 |
| 肤色分割 + blob | OV5640 直接出 YUV422，阈值 Cb/Cr，连通域/bbox | 2–4k LUT，0–9 BSRAM，2–4 DSP（估算） | 1–2 帧 | 可行；受光照/肤色影响，需校准 |
| 形状特征/模板匹配 | 轮廓、Hu 矩、模板相关 | 5–15k LUT，DSP 若干（文献/估算） | 1–2 帧 | 中等；比 CNN 轻，但调试量大 |
| 稀疏光流/块匹配 | 角点/块 SAD，运动矢量 | 6–15k LUT，10–30 BSRAM，8–16 DSP（估算） | 1–3 帧 | 偏高；适合“方向/速度”，不适合低成本 |
| 稠密光流（LK/金字塔） | 梯度、特征匹配、块滤波 | **>20k LUT，>40 BSRAM，>20 DSP** | 1–3 帧 | **不适合**；Zynq-7020 上 480p/720p 已以 BRAM 为最 dominant 资源 |
| Tiny CNN | 32×32/64×64 灰度，2–4 层 | 15–30k LUT，20–40 BSRAM，30–60 DSP（估算） | 2–5 帧 | 风险很高；GoAI 2.0 未列 GW5AT-60 |
| 事件相机 | 异步像素、稀疏事件 | 5–15k LUT（估算） | <1ms | 延迟最好，但传感器/DVP 不兼容、成本高 |

**文献依据**：

- 稠密光流 + 块滤波在 Xilinx Zynq-7000 XC7Z020 上做到 480p/720p 60fps、无外部内存，但作者明确说 **Block RAM 是最 dominant 的资源**；720p + 3bit 量化会超过 BRAM（141 块）而无法实现。Zynq-7020 有 85k LUT、4.9Mb BRAM、220 DSP；GW5AT-60 只有 59.9k LUT、2.1Mb BSRAM、118 DSP。**稠密光流在 60K 上不现实。** [J-STAGE 论文](https://www.jstage.jst.go.jp/article/transfun/E106.A/3/E106.A_2022VLP0009/_article/-char/en)
- 形状特征 + 普通 2D 摄像头的手势/AR 标记识别，在低功耗 FPGA 上 25MHz 即可 30fps，识别率 93.2%。说明“经典特征 + 低分辨率”是可行的，不必上 CNN。[MSA 论文](https://repository.msa.edu.eg/items/69680002-764e-45f4-b787-952d947cc7a7/full)
- MIT 6.111 的 FPGA Air Brush 用 OV7670 640×480@30fps + 帧缓存，最终因为时间不够**放弃了手势识别**，改成颜色检测 + LED“点击”。这是一个很现实的工期警告。[MIT Air Brush 报告](https://web.mit.edu/6.111/www/f2016/projects/weeracha_Project_Final_Report.pdf)
- Gowin GoAI 2.0 是官方 CNN 部署流程，但列出的开发板是 GW1NSR4、GW2AR18、GW2A55，**没有 GW5AT-60**；不能假设“把 TFLite 丢进去就能跑”。[GoAI 2.0](https://www.gowinsemi.com/en/market/featured/11/)
- 事件相机 + FPGA 的综述：延迟低、稀疏、省电，但传感器和 DVP 接口是另一套生态，不适合当前 BOM。[Event-based vision on FPGAs – a survey](https://arxiv.org/abs/2407.08356)

### 3.2 别人用无接触手势控制什么

| 场景 | 手势 | 被控量 | 延迟敏感 | 结论 |
|---|---|---|---|---|
| Theremin | 手位/距离 | 音高、音量 | 高 | 相机版本有，但跟手性差；适合演示，不适合评分 |
| Air guitar | 扫弦/拨动 | 音符触发 | **很高** | 通常用 IR/IMU/雷达，不用相机 |
| 音乐播放器 | 左右挥、握拳 | 切歌、播放/暂停、音量 | 低 | 相机很合适 |
| DJ/效果器 | 手位、推拉 | 滤波、效果量 | 中 | 适合慢变参数 |
| 机器人/智能家居 | 离散手势 | 模式/开关 | 低 | 相机常见 |
| 本作品 | 左右/上下/推/手位 | 音色、音区、效果、亮度 | 低–中 | **只做这些** |

**结论**：相机手势的甜区是“离散模式切换 + 慢变连续量”，不是“低延迟音符触发”。这正好对应本作品已有的触摸/光束/ToF 分工。

## 4. 摄像头硬件路径

### 4.1 板卡与接口

Tang Mega 60K NEO 底板有 **DVP 摄像头接口**，与上侧 40P 排针、PMOD 复用；官方 `cam_dvi` 例程用 **OV5640、720p30、RGB565、DDR3 帧缓存、HDMI 输出**，并给出了完整的 DVP/SCCB/TMDS 约束。[ Tang Mega 60K Wiki](https://wiki.sipeed.com/hardware/en/tang/tang-mega-60k/mega-60k.html) [cam_dvi 例程](https://github.com/sipeed/TangMega-60K-example/tree/main/cam_dvi)

从 60K 底板原理图看：

- **J13** 是 `SDRAM0_D* / SDRAM0_A*` 的 2×20P 排针，当前工程用的就是 J13（MPR121、ADS1115、PCM5102、74HC595、UART）。
- **J14** 是 `SDRAM1 | DVP_CAM | PMOD` 的 2×20P 排针；摄像头的 `CAM0_D0..D7 / PCLK / HSYNC / VSYNC / MCLK / PWDN / RST` 走的是 J14 这一组球号。
- 因此，**摄像头与当前 J13 底板在 FPGA 引脚上不冲突**；前提是 J14 不被 SDRAM1/PMOD 占用。当前工程确实没有用 J14。
- 但 DVP 座、40P 排针、PMOD 在底板上是**复用（可能二选一/共位）**的，摄像头 FPC 插上后是否与你的 PCB 干涉，必须实板确认。
- 摄像头 TWI 的 SDA 在 **Y13（BANK9，1.5V）**，官方例程用 `LVCMOS15`；不要按 3.3V 约束。其余 DVP 信号在 BANK6/7/8，3.3V。原理图来源：[Sipeed 原理图下载](https://dl.sipeed.com/shareURL/TANG/Mega_138K_60K/02_Schematic)

### 4.2 与官方例程的差异

官方 `cam_dvi` 是“720p 采集 + DDR3 帧缓存 + HDMI 显示”，资源与引脚都很重；本作品不需要：

- 不需要 720p，160×120 或 80×60 足够做手势。
- 不需要 DDR3，一帧 160×120×8 = 153.6Kb，9 个 BSRAM；80×60 只需 3 个。
- 不需要把整幅图像显示到 HDMI；只需要把 bbox/手位画成一个小方框/光标，作为“视觉反馈”。
- 需要保留现有 HDMI 的 800×600 画面，不能动 TMDS 时序。

### 4.3 需要的额外硬件

- **OV5640 DVP 摄像头模块 + 与底板 DVP 座匹配的 FPC**（按官方例程同款模块核对针数/方向/供电）。如果没有，先确认 FPC 针数/方向/供电。
- 不需要电平转换模块（底板已有）；不需要 DDR3。
- 需要能同时插 J13 底板和 DVP FPC 的机械空间；如果 PCB 挡住，准备 40P 排线/弯角转接。

## 5. 资源、时序与延迟评估

### 5.1 摄像头“手势辅助层”估算

以 160×120、30fps、YUV422、帧差 + 包围盒/面积 + 手势状态机为例：

| 子模块 | LUT 估算 | BSRAM | DSP | 说明 |
|---|---:|---:|---:|---|
| DVP 捕获/同步/降采样 | 200–300 | 0 | 0 | PCLK 域，2FF 同步，行列计数 |
| 背景帧 RAM（160×120×8） | 20 | 9 | 0 | 单时钟 PCLK 域，避免双时钟 RAM |
| 背景更新/帧差/阈值 | 100–150 | 0 | 0 | 移位式 IIR，无乘法 |
| bbox/面积/质心 | 250–400 | 0 | 0–2 | min/max、sum_x/sum_y；可用加法器避免 DSP |
| 手势状态机/去抖/校准 | 400–700 | 0 | 0 | 3–4 种手势，2–3 帧确认 |
| SCCB 配置（复用官方 2 字节地址 I²C） | 600–1200 | 0–1 | 0 | 需要 16 位寄存器地址；现有 MPR121 的 8 位地址 master 不够 |
| CDC/状态总线/HDMI 跟踪框 | 100–200 | 0 | 0 | 帧级握手，不做逐像素 CDC |
| **合计** | **约 1.6–2.6k** | **9–10** | **0–2** | 占 Logic +3–4%，CLS +4–6%，BSRAM +8% |

如果降到 80×60：约 1.2–2.0k LUT、3–4 BSRAM，手势精度略差，但更稳。

**注意**：这是估算，不是综合结果。真正的数字要以 Gowin 报告为准。

### 5.2 时序风险

- 当前 setup 余量 0.142ns，CLS 57%。新增 2k LUT 后，CLS 可能到 62–65%；如果布局把新逻辑塞进关键路径附近，setup 可能变负。
- 摄像头本身可以跑在 PCLK 域（24–25MHz），其时序压力小；真正进入 50MHz 域的是 CDC、手势命令、状态总线和 HDMI 跟踪框，量不大，但**布线拥塞**会影响全局。
- 必须做一次“带摄像头空壳”的 PnR：只加 DVP 引脚、PCLK 约束、一个 160×120 帧缓存和 bbox 输出，不接音频，先看 CLS/setup。若 CLS > 75% 或 setup < 0，停止或降级（80×60、减 FFT、减 echo）。
- 可交换的资源：echo 16,384→8,192 样本可省约 7 个 BSRAM；FFT 4096→2048 可省 BSRAM/DSP，但频谱分辨率减半。**不要先动 FFT**，它是对外展示的核心。

### 5.3 延迟预算

| 路径 | 延迟 | 依据 |
|---|---:|---|
| 触摸状态 → 首个非零 I²S 样本 | **0.107ms** | 仿真，8 个事件相位 |
| MPR121 采样（1ms 采样 × 2 次确认）+ I²C 轮询/读取 | 约 2–3ms | 控制器参数 + 架构估算 |
| PCM5102 DAC + 模拟 | 约 0.5–1ms | 取决于滤波/功放，需实测 |
| **触摸 → DAC 模拟输出（估算）** | **约 3–4ms** | 未实测；≤10ms 大概率满足，≤5ms 偏紧 |
| 双光束 | **2ms**（模块标称） | 适合扫弦 |
| VL53L0X | 20–33ms | ST API 默认预算；适合慢变 |
| 摄像头 30fps | 33.3ms/帧；手势 66–100ms | 帧周期 + 2–3 帧确认 |
| 摄像头 60fps | 16.7ms/帧；手势 33–67ms | 仍 >10ms；曝光/读出未计 |

**结论**：摄像头不能用于 note-on、力度、拨弦、pitch bend。它可以用于“音色预选、音区切换、效果开关、亮度/明暗”等对 50–150ms 不敏感的场合。若评委把“所有演奏控制”都按 ≤10ms 考核，摄像头手势会被判不合格；必须把它定位为“辅助/展示层”，并单独报告延迟。

## 6. 手势控制映射与混合架构

### 6.1 建议的手势词汇

| 手势 | 控制量 | 类型 | 可接受延迟 | 备注 |
|---|---|---|---:|---|
| 左右挥 | 上一个/下一个音色（4 选 1） | 离散 | 100–200ms | 最稳；屏幕显示音色名 |
| 上下挥 | 音区 +/− | 离散 | 100–200ms | 与 X0 冲突；只在“手势模式”生效 |
| 前推（面积变大） | echo 开/关 或 GUIDE 页 | 离散 | 100–200ms | 2–3 帧确认，防误触 |
| 手掌停留 | All Notes Off / panic | 离散 | 100ms | 安全手势，不参与音乐 |
| 手的高度 | 音色亮度/泛音混合 | 连续 | 30–50ms | **第三维表情**；音频率平滑，避免 zipper |
| 双手距离 | detune/chorus 深度 | 连续 | 30–50ms | 需要先实现 chorus |
| 握拳 | 静音 | 离散 | 100ms | 安全 |
| 扫弦 | **不要用摄像头** | — | ≤10ms | 用双光束 |

### 6.2 推荐架构：摄像头预选 + 光束触发

```text
摄像头 → 手势 FSM → 音色/音区/亮度（慢变，50–150ms）
双光束 A/B → 扫弦/方向/速度 → 音符/和弦触发（快，≤10ms）
触摸/FSR → 选音/力度 → 32 声部引擎 → I²S
```

这样：

- 摄像头负责“准备音色/音区/明暗”，不进入起音路径；
- 光束负责“拨弦/扫弦”，满足 ≤10ms；
- 触摸/FSR 仍是主演奏入口；
- HDMI 可以画一个 bbox/手位小框，作为“视觉反馈”，强化拓展 3 的“视听”表现，而不需要整幅摄像头预览。

这是把摄像头变成“加分项”而不是“风险项”的唯一稳妥方式。

### 6.3 与现有/已购方案对比

| 方案 | 延迟 | 资源增量 | 最适合的控制 | 风险 |
|---|---:|---:|---|---|
| 电容触摸 + FSR | 约 3–4ms（估算） | 已有 | 音符、和弦、全局力度 | 低；整机延迟待实测 |
| 双光束 A/B | 2ms（标称） | 几百 LUT + 2 个引脚 | 扫弦方向/速度、快速触发 | 低；需结构固定 |
| VL53L0X ToF | 20–33ms | 约 1k LUT + I²C | 手位→音色明暗/滑音 | 低–中；受环境光/反射率影响 |
| 摄像头手势 | 50–150ms | 约 1.6–2.6k LUT + 9 BSRAM | 2D 离散手势、慢变亮度 | 中高；时序/工期/光照 |
| 摄像头 + 光束混合 | 起音 2ms；手势 50–150ms | 两者之和 | 预选 + 触发 | 中；架构最稳 |

**一句话**：如果目标是“无接触演奏”，双光束 + ToF 已经够；如果目标是“无接触 2D 手势展示”，摄像头才有增量。不要把两者混为一谈。

## 7. 建议路线与 Go/No-Go

### 7.1 先补基础（优先级高于摄像头）

1. **整机延迟实测**：按 [latency_measurement.md](latency_measurement.md:1) 用示波器测 MPR121 IRQ/触摸参考 → PCM5102 模拟输出；至少 100 次/组，覆盖四音色、高低音、HDMI/蓝牙同时工作。先证明 ≤10ms，再谈 ≤5ms。这是基础 2 和拓展 3 的硬指标。
2. **pitch bend/滑音**：给 `polyphonic_engine` 的 `steps[]` 加一个全局弯音/滑音偏移（例如压力在“solo 模式”下映射到 ±2 半音，或第二路 FSR/ToF）。这补基础 3 的“单音实时变调”和拓展 2 的“滑音”。
3. **混响/合唱**：在 `audio_output` 里加一个简单 Schroeder 混响（4 comb + 2 allpass）或 chorus（短延迟 + LFO）；BSRAM 够，DSP 也够。补拓展 2 的明确缺口。
4. **双光束 + ToF**：按 [optical_hardware_plan.md](optical_hardware_plan.md:44) 做扫弦方向/速度 + 手位→亮度；这是“无接触”最便宜、延迟最低的路径，且器件已购。
5. **李萨如 + App/录音**：李萨如可用现有波形缓冲便宜地画；App/录音是拓展 4 的加分项，但工作量大，量力而行。

### 7.2 如果仍要做摄像头：先做 3 天 Spike

**目标**：回答“能不能在不动音频时序的前提下，稳定采到 160×120 并算出 bbox/手势”。

- 第 1 天：接 OV5640，复用官方 SCCB 配置，改成 160×120 YUV422；用 ILA/GAO 或 UART 打印帧头/行列，确认 PCLK/VSYNC/HREF 稳定。
- 第 2 天：加 160×120 背景 RAM + 帧差 + bbox/面积；输出到 UART 或 HDMI 小框；跑一次 PnR，记录 CLS/setup/BSRAM。
- 第 3 天：加 3 个手势（左/右/推）+ 2–3 帧去抖；测端到端延迟（手过中线 → 命令有效），在两种光照下各 30 次。

**Go 条件**：CLS ≤ 70%、setup ≥ +0.05ns、无音频 overrun、3 个手势识别率 ≥ 90%、端到端 ≤ 150ms、摄像头 bring-up ≤ 1 周。
**No-Go 条件**：CLS > 75%、setup < 0、bring-up 超过 1 周、或手势延迟 > 200ms。
**降级顺序**：160×120 → 80×60；帧差 → 只做列投影；三手势 → 只做左右挥。

### 7.3 不建议做的事

- 不要在 GW5AT-60 上做 480p 稠密光流：BRAM 和 LUT 都不够，且时序会更紧。
- 不要做 CNN/手部骨架/手指计数：没有官方 GoAI 支持，资源/工期/鲁棒性都不划算。
- 不要让摄像头直接触发音符、力度、拨弦、pitch bend：延迟必然 >10ms。
- 不要为了摄像头去动 4096 点 FFT 或 HDMI 时序；它们是现有展示的核心。

## 8. 需要你确认的事

1. 你手上有 **OV5640 DVP 模块 + 24P FPC** 吗？底板 DVP 座与当前 J13 底板在机械上是否干涉？
2. 比赛截止时间/团队可投入人力？如果少于 4 周，建议直接放弃摄像头，先做 7.1 的 1–4。
3. 评委对“控制信号到音频输出 ≤10ms”的解释：是只算 note-on，还是所有演奏控制（包括手势）？这决定摄像头能不能被写进“演奏维度”。
4. “力度”是否要求每键力度？当前是全局 FSR；如果是每键，需要加硬件（每键 FSR/压感），摄像头也解决不了。
5. 下一步要我优先做哪一项：整机延迟实测脚本/接线、pitch bend、混响/合唱、还是摄像头 Spike？

## 9. 参考

- Sipeed Tang Mega 60K Wiki（DVP/40P/PMOD 复用、DDR3、资源）：https://wiki.sipeed.com/hardware/en/tang/tang-mega-60k/mega-60k.html
- Sipeed TangMega-60K `cam_dvi` 例程（OV5640 720p30、DDR3 帧缓存、DVP/SCCB 约束）：https://github.com/sipeed/TangMega-60K-example/tree/main/cam_dvi
- Sipeed 60K 底板原理图（J13=SDRAM0，J14=SDRAM1/DVP/PMOD）：https://dl.sipeed.com/shareURL/TANG/Mega_138K_60K/02_Schematic
- Manabe & Shibata, “Real-Time Image-Based Vibration Extraction with Memory-Efficient Optical Flow and Block-Based Adaptive Filter,” IEICE Trans. Fundamentals, 2023（Zynq-7020，480p/720p 60fps，BRAM 为最 dominant 资源）：https://www.jstage.jst.go.jp/article/transfun/E106.A/3/E106.A_2022VLP0009/_article/-char/en
- MIT 6.111 FPGA Air Brush（OV7670 640×480@30fps，最终放弃手势识别）：https://web.mit.edu/6.111/www/f2016/projects/weeracha_Project_Final_Report.pdf
- Gowin GoAI 2.0（支持 GW1NSR4/GW2AR18/GW2A55，未列 GW5AT-60）：https://www.gowinsemi.com/en/market/featured/11/
- “Event-based vision on FPGAs – a survey”（事件相机 + FPGA 的算法/平台综述）：https://arxiv.org/abs/2407.08356
- MSA 大学 FPGA 手势/AR 标记论文（低功耗 FPGA、25MHz、30fps、93.2%）：https://repository.msa.edu.eg/items/69680002-764e-45f4-b787-952d947cc7a7/full
