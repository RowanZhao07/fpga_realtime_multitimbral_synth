# KY-023 + EC11 + 单 ADS1115 复用版

本轮基于远端最新 `1c9400b` 实现，纳入已实测的 3235 mV 力敏满量程和新版 GUIDE/输出标定，保持 32 复音、音色、ADSR、EC11 16 档延音、GUIDE 和 HDMI 的原有架构。新增工程 `instrument/instrument_joystick.gprj` 同时启用摇杆和 EC11，并启用压力滤波；原有三个工程入口保持原输入行为。本轮仅发布工程源码与说明，不生成位流或烧录。

## 操作方式

- 左拨降低一个八度，右拨升高一个八度，范围 C3..C6，默认 C4；拨住不连发。方向反了可设置顶层 `JOYSTICK_REVERSE=1`。
- 每次必须回中并取得连续 8 个中心区域的有效 ADC 样本才重新允许切换。中心默认 1650 mV，回中范围 ±300 mV，触发范围超过中心 ±800 mV。中间区域保持状态；上电或重连时偏置在一边不会切换。
- 按住 SW 开启已有颤音，释放关闭；默认低电平有效、10 ms 去抖。上电按住时先释放才能使用。按压期间禁止切换八度，释放后也需要回中。
- GUIDE 自动音区优先；GUIDE、校准模式和触摸掉线期间不接受手动八度事件，退出后回中再拨。已发声声部保持原音高，新音符使用新八度。
- 本组合工程不再使用 X0+C0..C3 切八度和单独 C3 触发颤音。C0 音色/回声、C1/C2 音量、C1+C2 GUIDE、四控制键校准、X0 灯测试保留。触摸音符输入仍需原来的两块 MPR121。
- 共享 ADC 掉线会同时使力敏与摇杆读数失效：力敏增益平滑回到主音量，摇杆停止切八度，恢复后先回中。触摸和 EC11 不依赖 ADC；SW 是独立数字输入，ADC 掉线时仍可按住产生颤音。

## 接线表（Tang Mega 60K NEO 的 J13）

| 信号 | 外设连接 | FPGA 接口 | FPGA 球位 |
|---|---|---|---|
| 共享 ADC SCL | 原 ADS1115 SCL | J13-15，保持原接线 | A20 |
| 共享 ADC SDA | 原 ADS1115 SDA | J13-16，保持原接线 | B20 |
| 力敏模拟量 | 原 FSR 分压节点 | ADS1115 AIN0 | 不直接接 FPGA |
| 摇杆横轴 | KY-023 VRx | 同一 ADS1115 AIN1 | 不直接接 FPGA |
| 摇杆按键 | KY-023 SW | J13-23 | A19 |
| EC11 A / B / SW | 保持原接线 | J13-8 / 7 / 6 | A13 / A14 / C13 |
| 公共地 | ADS1115、KY-023、EC11 共地 | J13-12 / 板上 GND | — |

J13 编号是连接器物理脚号，不是 FPGA 球位。J13-11 是 5V，不能当 GND；上述 SDRAM 扩展引脚不能再并接 SDRAM。针脚依据官方 [60K SDRAM 约束](https://github.com/sipeed/TangMega-60K-example/blob/main/sdram_neo/src/sdram.cst) 与 [NEO Dock-60K 原理图](https://dl.sipeed.com/fileList/TANG/Mega_138K_60K/02_Schematic/DOCK/Tang_Mega_NEO_Dock-60K_31004_Schematics.pdf) 的 J13 对照。

只需要原有一块 ADS1115，3.3V 供电，ADDR 接 GND（0x48）。AIN0 保持原 FSR 分压电路，AIN1 新接 KY-023 VRx。VRy、AIN2/AIN3 和 ALERT/RDY 暂不使用。J13-9/10 已取消软件端口与约束，不需要接线。

单 ADC 采用单次转换轮询：写入 AIN0 配置 `C3E3` → 等待并轮询配置寄存器的 OS 位 → 确认转换完成 → 读取压力 → 写入 AIN1 配置 `D3E3` → 同样等待完成后读横轴，再循环。每次验证 MUX/PGA/MODE/DR，OS=0 时不读旧转换值。不是在连续转换时直接切 MUX 后立刻读寄存器。实现依据 [TI ADS1115 数据手册](https://www.ti.com/lit/ds/symlink/ads1115.pdf)。

860 SPS 是 ADC 转换速率上限，不是每个输入的更新速率；当前 100kHz I2C、默认等待 2ms，加配置写入/状态读取/数据读取，默认时序的总线模型仿真得到每通道间隔 6.65048 ms，约 150 次/秒，实板仍需测量确认。回中需 8 个有效横轴样本，约 53 ms；按键去抖独立于 ADC。共享设备故障会使两路同时无效，恢复从 AIN0 重新开始。

KY-023 电位器电源接板上标明的 3.3V，GND 共地；不要因模块丝印 `+5V` 就把 5V 模拟输出送入本系统。上电后先确认 VRx 回中约 1.65V、两端约 0V/3.3V，再连接 ADC。

SW 默认按下接地，外接 4.7k~10k 上拉到 3.3V（FPGA 内部也启用上拉）。实测模块若是相反极性，可改 `JOYSTICK_BUTTON_ACTIVE_LOW`，同时按模块电路调整上下拉；不要把 5V 上拉接入 FPGA。原 I2C 线需上拉到 3.3V，优先使用模块已有上拉，避免重复并联过低阻值。洞洞板使用分开的电源/地母线，ADS1115 旁放 100nF 去耦，模拟线短、远离 HDMI/时钟；摇杆壳体单独固定，焊点不承担手部机械力。

## 力敏输入优化及校准

保持原电路：3.3V → FSR → AIN0 → 10k → GND，AIN0 对地 100nF。此结构按压越大，电压越高。默认映射沿用最新实测标定： 0 mV 时 25% 表现音量、3235 mV 时 100%；主音量独立限制最终音量。它是全局表现控制，不是每个琴键独立力度。

新增 Q4 定点 IIR：每个有效 ADC 样本，增大方向追随差值的 1/4、减小方向追随差值的 1/8；保留小数避免整数量化停滞。零点附近 16 mV 死区抑制无压力噪声。Q9 音量增益每个音频采样最多移动 1/512，满行程约 7.9 ms，另加 ADC/滤波延迟和原有音频输出级的增益渐变时间（不是总响应时间 7.9 ms）。ADC 掉线平滑回到原主音量，重新接入也平滑过渡。

显示原始压力电压；ADC 内部通道切换后只更新各自的样本寄存器，屏幕不会交替显示摇杆电压。先在 HDMI 的原始压力 mV 显示上记录无压力电压和舒适最大力度电压，再调整顶层 `PRESSURE_ZERO_MV` 与 `PRESSURE_FULL_MV`，要求 0 ≤ ZERO < FULL ≤ 4095 且 FULL > ZERO+16；机械结构装好后再测。`JOYSTICK_CENTER_MV` 也可按实测中位调整，建议保留 3.3V 中位附近。当前采用可配置固定中位加回中确认，没有自动学习中心，避免开机拨住时错误校准。

## 高云打开与调试

1. 打开 `instrument/instrument_joystick.gprj`。本机已准备 `impl/instrument_joystick_process_config.json`；复制仓库到别处时，将 `config/joystick_process_config.json` 复制为该文件后再打开 IDE。
2. 器件 GW5AT-LV60PG484AC1/I0；顶层 instrument_top；Include Path 为 src；VCCX 1.8V；Use CPU as GPIO 开启。
3. 只检查综合可运行 `./instrument/build.ps1 -Joystick -SynthesisOnly`。省略 `-SynthesisOnly` 的旧构建流程会生成位流，本轮没有执行。
4. RTL 仿真使用可配置的 XSim 或 Icarus Verilog 和高云 GW5A 官方原语模型；本轮实际使用的工具、版本与通过项目见验证报告。这是 RTL 功能验证，不是布局布线后的时序仿真。
5. 模块到齐后先万用表确认电源、电压、按键极性，再由你在 IDE 执行布局布线并检查建立/保持及最小脉宽。最后烧录，依次验收：触摸与原压力 → 摇杆回中/左右 → 按住颤音 → EC11 延音 → GUIDE → 断开共享 ADC 后检查压力回退与摇杆停止切换。

测试内容与本轮综合结果见 [验证报告](joystick_verification.md)。
