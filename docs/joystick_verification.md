# 单 ADS1115 复用、摇杆与压力输入验证（2026-10-26）

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
