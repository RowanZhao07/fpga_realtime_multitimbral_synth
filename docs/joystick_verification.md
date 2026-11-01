# 单 ADS1115 复用、摇杆与压力输入验证

## 2026-10-31 临时 HDMI 接线诊断版

针对用户反馈 TOUCH 多数时间 OFFLINE、ADC OFF 且拔掉摇杆无改善，新增独立入口 `instrument_wiring_debug.gprj` / `build.ps1 -WiringDebug`。页面直接显示两块 MPR121 与 ADS1115 各自状态、E14/E13、A16/A15、A20/B20、最近空闲电平、保留的错误原因与饱和失败次数。沿用原 I²C 协议、重试和 GPIO 供电配置；ADC 补充错误记录，空闲电平仅在主机释放总线并等待同步稳定后更新。

XSim 2025.1 配合高云 GW5A 原语完成 **7 项测试，全部通过**：`tb_i2c_recovery`、`tb_shared_ads1115`、`tb_touch_link`、`tb_wiring_screen`、`tb_wiring_top`、`tb_screen_feedback`、`tb_joystick_top`。静音模式调整后重跑后四项，仍全部通过。覆盖真实总线模型的 NACK、SCL/SDA 低电平、ADC 配置/等待超时、错误保留、三路独立状态到跨时钟邮箱及帧锁存、全部引脚/数字标签、完整 800×600 三拍光栅，以及正常演奏入口的音区/颤音/压力/琴键和显示回归。

该临时入口将音频/演奏控制核心保持复位，屏幕标有 SILENT，三路外设仍正常轮询。不修改原演奏入口的复位行为。首轮保留完整合成器的诊断构建有 4 个 setup 违规端点（最差压力换算 -4.784ns），未发布；改为专用静音诊断模式后，完整综合、布局布线通过，setup/hold 违规均为 0，最小余量 setup 4.928ns、hold 0.247ns、recovery 0.310ns、removal 0.589ns、pulse width 6.538ns。未放宽约束，资源 Logic 3262/59904、Register 1328/60780、DSP 1.5/118。

- 诊断位流：`dist/instrument_wiring_debug.fs`，17,313,107 字节。
- SHA256：`6afad0da15278896df702fe318774b25d8142f46c539539a92edbf8d1a5cd732`。
- 原演奏位流 `dist/instrument_joystick.fs` 保持 SHA256 `5c3af525babbcf36145bc6cbde6af084b686594899e678a83238a33d02515f85`，可下载恢复演奏。
- 本机证据：`.local/verification/wiring-debug-20261031/`，包含测试、最终时序与引脚报告、仿真画面及首次失败报告。图像为故障注入仿真样例，不是实物屏幕读数。
- 未执行硬件下载；需要用户下载后反馈三行状态，不能由仿真结果宣布导线故障已经定位或修复。

## 2026-10-30 J13-9 GPIO 供电版

用户按电阻测量步骤反馈 20kΩ 档显示 2.6，按约 2.6kΩ 纯电阻负载估算，3.3V 下电流约 1.27mA；这不是带电电流实测，也不证明外部线束无误。按用户选择，新增 `joystick_vcc` 输出：组合工程配置后恒高，非摇杆工程高阻；约束为 J13-9 / B16、LVCMOS33、3.3V、DRIVE=8、PULL_MODE=NONE。只允许给这一只低功耗摇杆单独供电，必须断开原 5V 及其他供电源，具体接线和带载检查见[使用说明](joystick_controls.md)。未改回中/方向阈值。

本机 XSim 2025.1 配合高云 GW5A 原语重新执行 **3 项测试，全部通过**：`tb_joystick_controls`、`tb_joystick_top`、`tb_ec11_top`。覆盖新增供电脚在组合版持续为高、旧 EC11 版为高阻，以及 2.9V 供电模型下 1.45V 回中、两端切八度和 2.5V 非回中检测；同时保留原顶层音频/显示断言。仿真不能验证 GPIO 实际电压、电流或外部接线。

Gowin 1.9.12.03 完整综合、布局布线、位流生成通过，setup / hold 违规端点均为 0。最小余量：setup 0.159ns、hold 0.047ns、recovery 0.310ns、removal 0.640ns、pulse width 5.594ns。最终网表为 VCC 驱动的 OBUF，最终引脚报告确认 B16 / Bank 1 为输出、LVCMOS33、DRIVE=8、无弱上拉。保留已有位宽截取、优化和通用时钟布线告警。

- 当前位流：`dist/instrument_joystick.fs`，19,336,587 字节，2026-10-30 23:28 生成。
- SHA256：`5c3af525babbcf36145bc6cbde6af084b686594899e678a83238a33d02515f85`。
- 旧同名位流没有 J13-9 供电输出，须下载这次新文件；下载方式仍为 GW5AT-60B / SRAM Program。
- 用户决定自行下载观察，本轮未执行硬件下载；带载电压、外部接线和左右切八度的实物验收待完成。
- 本机证据：`.local/verification/joystick-gpio-power-20261030/`，包含三个测试日志、构建日志、最终时序/引脚报告、源码与位流哈希，并保留先前无 GPIO 供电版位流。

## 2026-10-30 先前固定电源方案与重新构建（无 GPIO 供电）

用户确认当前摇杆版 HDMI 有 STICK 提示，按压 SW 可切换 VIB，但 GUIDE OFF 时左右不能切八度；摇杆实际接在 PCB 5V。查图确认可将摇杆独立电源线移到开发板 J8/J9 的第 1 或 2 脚（固定 +3V3），无需新增 GPIO 供电端口。接线、回中电压和上板检查见[使用说明](joystick_controls.md)。3.3V 改接后的效果尚待用户实测，不把供电原因推断写作已修复。

本轮 RTL、约束、工程及测试源文件与 2026-10-29 验证记录的 SHA256 全部一致，未改中位阈值。按用户要求重新执行完整综合、布局布线和时序检查，通过；setup / hold 违规端点均为 0。最小余量为 setup 0.159ns、hold 0.047ns、recovery 0.310ns、removal 0.640ns、pulse width 5.594ns。资源与前次相同，保留既有告警。

- 当时位流：`dist/instrument_joystick.fs`，19,336,587 字节；已被上方 GPIO 供电版替换。
- SHA256：`3eee278324c16324a612479f336e0292ea8a30006269134e38100699d1449cb9`。
- USB Debugger A 扫描成功，发现 1 个 JTAG 器件，IDCODE `0x0001481B`；原 Programmer 设置为 GW5AT-60B / SRAM Program，文件路径为上述组合版。
- 本轮没有重新运行 RTL 仿真；先前通过项有源码哈希一致性支持。
- 用户决定自行改接、下载和观察效果；本轮未执行 SRAM 下载，改接完成与左右切八度结果未确认。
- 本机证据：`.local/verification/joystick-20261030/`，包含基线哈希、重新构建日志、时序/资源报告和 `verification.json`。

## 2026-10-29 本机合入与复核

`feature/joystick-shared-adc` 的 chenxi639 原提交 `85118b9` 已快进合入本地 main，保留 `1c9400b` 的曲谱和音量更新。合入后补充了当前工程入口和其他模块的逐根接线说明，并修复完整布局布线暴露的两处时序问题。外设管脚与时钟约束均保持原样。

本机使用 Gowin 1.9.12.03、XSim 2025.1 和 GW5A 官方原语模型，重新执行下表所列的 **13 项 RTL 测试，全部通过**。包括共享 ADC 的协议及默认更新率、摇杆/压力控制、真实音频时钟下的新旧八度、完整顶层、EC11、GUIDE、琴键反馈和输出幅度。每通道模型采样间隔仍为 6.65048 ms。未将队友机器上的 Icarus 结果替代本机结果，也未宣称全套回归通过。

首轮布局布线发现 21 个 setup 违规端点：压力滤波值到增益的组合换算最差 -7.242 ns，屏幕长提示行的字符选择/字形路径 -2.362 ns；hold 无违规。构建脚本阻止这份位流进入 dist。压力换算改为缩放、定值除法、限幅三步流水，保留原整数映射与逐音频帧增益渐变，只增加三个 50 MHz 时钟的换算延迟；HDMI 将相同的 60 字符提示拆成三个短标签，保持位置、内容和原三拍像素流水。没有放宽时序约束或关闭正式工程的 hold 修正。

修复后重新执行 **5 项 RTL 测试，全部通过**：tb_pressure_expression、tb_joystick_core、tb_joystick_top、tb_screen_feedback、tb_video。其中新增 3235 mV 标定的 0～4095 mV 全范围升降遍历，以及底部全部 60 字符逐格检查；完整 800×600 光栅、TMDS 和原三拍显示流水保持通过。

本机完整构建命令：`./instrument/build.ps1 -Joystick -GowinShell D:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe`。修复后综合、布局布线与全部时序检查通过，setup/hold 违规端点均为 0。

| 时序检查 | 最小余量 |
|---|---:|
| Setup | 0.159 ns |
| Hold | 0.047 ns |
| Recovery | 0.310 ns |
| Removal | 0.640 ns |
| 最小脉宽 | 5.594 ns |

Logic 29240/59904、Register 7297/60780、BSRAM 35/118、DSP 33.5/118。保留已有位宽截取、优化及 ref_clk_d 通用时钟布线告警；未全局屏蔽告警或改变时钟要求。

- 当前组合版位流：`dist/instrument_joystick.fs`，19,336,587 字节，2026-10-29 22:09（北京时间）生成。
- SHA256：`eeedb735262fd85e0e0ec147d990a3441935ba98b340e05b4d61aabaad7b544b`。
- 下载方式：GW5AT-60B → SRAM Program。原 `instrument_ec11.fs` 不包含摇杆功能。
- 实物烧录、模拟输入噪声、摇杆中位/方向和整机延迟验收尚未执行。

本机证据保存于 `.local/verification/joystick-20261029/`，包含合入时的 13 项日志、timing-fix 下的 5 项复核日志、最终源码/位流哈希和时序报告。first-build-failed 保留首轮失败报告，不作为下载版本；位流与工具产物不进入 Git。

## 队友初始验证记录（2026-10-26）

基线：远端 main `1c9400b`，新工作分支 `feature/joystick-shared-adc`。包含最新《遇见》GUIDE、音频输出标定和用户实测 3235 mV 压力满量程。需求与贡献者：**chenxi639 <chentseng908@gmail.com>**；Codex 协助实现、仿真与报告。本轮提交工程源码和说明，不生成新位流或烧录。

## 变更及理由

1. 复用现有一块 ADS1115：AIN0 接原力敏，AIN1 接 KY-023 VRx；SCL/SDA 保持 J13-15/16。只新增摇杆 SW 的 J13-23。删除上一轮尚未提交的第二 ADC 顶层端口与 J13-9/10 约束，减少硬件及接线。
2. 新增 `ads1115_scanner.v`：使用单次转换，在配置通道后检查配置寄存器与 OS 转换完成标志，确认后才读取转换值，再切换通道。避免读到上一通道的转换寄存器内容。依据 [TI 数据手册](https://www.ti.com/lit/ds/symlink/ads1115.pdf)，AIN0 配置 C3E3、AIN1 配置 D3E3，±4.096V、860 SPS 设置、地址 0x48。860 SPS 不等于每通道的实际更新率。
3. NACK、SCL 超时、配置错误及有界 OS 等待超时同时使两路失效，清除旧读数，从 AIN0 开始重试。压力平滑回到主音量，摇杆停止切八度；重新接入需要回中。触摸和 EC11 独立于 ADC，SW 也独立于模拟采样。
4. 集成上一轮本地摇杆交互与压力优化：左右拨动每次切一档八度、回中再触发，按住 SW 颤音、释放关闭；保留 GUIDE 自动八度优先和旧音高。力敏增加新样本驱动 IIR、死区、可配置两点校准及音频节拍上的渐变，顶层满量程沿用最新 3235 mV。
5. 新增 `instrument_joystick.gprj`、包装顶层、IDE 配置、HDMI 操作提示和接线说明。原三个入口保留原输入模式。合成声部、ADSR、音色、波表及音频输出算法使用最新基线。

## 本轮工具与验证

E 盘和此前的 XSim 2018.3 当前不可用。本轮使用 D:/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe 综合，Icarus Verilog 13.0（MSYS2 官方发行包，下载后按发布页面 SHA256 核对）配合 D 盘高云 GW5A 官方 `prim_sim.v` 完成功能仿真。没有把上轮 XSim 结果当成本轮结果。

高云初次启动提示旧许可证 hostid 不符，已将本机许可配置指向 Downloads 中匹配当前机器的 C03532613F23 许可证。许可证、许可配置及下载工具不进入 Git。

| 测试 | 结果与覆盖范围 |
|---|---|
| tb_shared_ads1115 | 通过；双通道交替、旧转换值隔离、OS 忙轮询、负值钳位、3235mV、ADC 到摇杆回中/方向事件、NACK/错配置/SCL 卡死/转换不完成的失效与恢复 |
| tb_shared_ads1115_rate | 通过；默认 50MHz/100kHz I2C/2ms 等待，通道更新间隔 6.65048ms，约 150 次/秒（总线模型，不是实测） |
| tb_joystick_controls | 通过；回中确认、保持不连发、中心抖动、上下限、无新样本不动作、重连、按键去抖、方向/极性、GUIDE 与校准优先级 |
| tb_pressure_expression | 通过；零点/满量程/过范围、仅新样本滤波、升降响应、单音频帧步长、掉线渐变、自定义两点校准 |
| tb_joystick_core | 通过；真实 1024 时钟音频间隔、C4 旧音与新 C5 共存、EC11 尾音、按住/释放颤音、3235mV 满量程、有效 PCM 与无计算超时 |
| tb_joystick_top | 通过；高云 PLL/存储器/输出原语、波形/FFT 发布、13 键状态与音量包络、跨时钟 HDMI 音区、压力渐变、EC11 及提示行首尾 |
| tb_pressure_link | 通过；原单通道驱动协议、掉线、错配置、时钟超时及 ADC 复位恢复 |
| tb_ec11_core | 通过；原旋钮延音与 UART、模式/离线处理 |
| tb_guide_auto | 通过；最新 GUIDE 自动音区与手动恢复、旧尾音保持 |
| tb_ec11_allocator | 通过；32 声部、同音重弹、跨音区尾音、抢占、释放；最重一帧 829 时钟，小于 1024 预算 |
| tb_screen_feedback | 通过；原屏幕琴键、音区、GUIDE 与诊断反馈 |
| tb_builtin_score | 通过；最新内置曲谱与响应 |
| tb_output_level | 通过；全混音范围输出单调、对称、音量比例、限幅、回声与静音 |

共 13 项通过。完整顶层中只加速显示分析采样与帧提交，音频核心仍使用真实时钟。顶层测试注入触摸/ADC 结果，外部 I2C 交互另由 shared_ads1115 外设模型覆盖。没有宣称全套回归全部执行；耗时的旧 `tb_full_scale_audio` 本轮未完整跑完，不计入通过项。

Icarus 下旧声部分配测试在首帧遇到查表初值未知；定位为初始地址为 0 且未产生变化时 `always @*` 初次调度差异。在 `__ICARUS__` 条件下，仅在复位期间让查表地址变化一次以建立组合初值，保留全部 PCM、32 声部与时钟预算断言；生产 RTL 未因此修改，XSim 测试保留原启动流程。还修正了 Icarus 回归脚本对 allocator 包装测试文件的依赖。

复现命令（路径替换成本机工具目录）：

```powershell
./instrument/sim/run-inputs-iverilog.ps1 -IcarusBin '<iverilog>/bin' -GowinSimLib '<Gowin IDE>/simlib/gw5a/prim_sim.v'
./instrument/build.ps1 -Joystick -SynthesisOnly -GowinShell '<Gowin IDE>/bin/gw_sh.exe'
```

## 高云综合结果

退出码 0，0 error。综合在任务目录 `work/shared-adc-gowin-check` 中运行，源文件与项目源码按统一 LF 内容逐一核对，未覆盖原项目实现产物。

| 资源 | 综合报告 |
|---|---:|
| Logic（含 ALU 汇总） | 29,145 / 59,904，约 49% |
| Register | 7,262 / 60,780，约 12% |
| BSRAM | 32 / 118，约 28% |
| 原始 LUT / ALU | 26,241 / 2,855 |
| MULTALU27X18 / MULT12X12 | 17 / 33（原语数，不是等效 DSP 块数） |

保留 71 条 warnings：EX3073 1 条为已有 sustain_active 独立输出未单独消费（状态经 sustain_info 使用）；EX3791 55 条为位宽截取；NL0002 15 条为常量或未用实例优化，包括组合版不使用的旧 pressure_mapping 实例。新增滤波位宽在合法参数下有界，测试覆盖增益上下限与步长。未全局隐藏 warnings。

本机证据目录：`C:/Users/64443/Documents/Codex/2026-10-09/fpga-competition/work/`。综合日志 `shared-adc-synthesis.log`，源内容校验 `shared-adc-source-hashes.json`；通过的逐项日志在项目 `instrument/sim/output/icarus-inputs/`。综合 HTML 在 `work/shared-adc-gowin-check/impl/gwsynthesis/instrument_joystick_syn.rpt.html`。这些生成产物不随 Git 推送。

## 后续实板验收

本轮没有布局布线、最终时序收敛、回标仿真或生成位流，综合估算不能代替最终 STA。需要实物确认摇杆中位与按键极性、共享采样时的模拟噪声、实际更新率及听感。按 [接线与校准指南](joystick_controls.md) 将 VRx 接原 ADC AIN1，保持 FSR AIN0，再用高云官方 IDE 打开组合工程实施布局布线与烧录。
