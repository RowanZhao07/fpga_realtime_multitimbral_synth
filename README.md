# FPGA 实时多音色电子乐器

Tang Mega 60K NEO（GW5AT-60B）上的纯 HDL 合成器，不使用处理器、MCU 或预录音源。

当前 PCB 使用 EC11 工程：13 键触摸演奏、32 声部、压力调音量及旋钮延音控制；800×600 HDMI 显示琴键、512 点波形、4096 点 Hann 窗 FFT 和 GUIDE。

- 13 个触摸音键，四档音区 C3～C4 / C4～C5 / C5～C6 / C6～C7，默认 C4～C5。
- 四档音区合计 49 个不同音高，最多 32 声部同时发声；重按分配新声部，跨音区的旧延音和释音尾巴保持原音高。
- 四音色：正弦、电钢琴感、合成弦乐、金属音；数学波表合成，新音锁定音色，旧尾音不受音色切换影响。
- 公共压力、颤音、延迟效果、延音、13 键灯和蓝牙参数控制。单音最大起音接近数字满幅，多声部叠加采用静态软限幅，主音量和压力在限幅之后线性调节；无按声部数自动降增益。
- GUIDE 最多 512 步，自动切换音区。内置《遇见》“阴天傍晚车窗外”至“拿着爱的号码牌”，G 调、76 个音，按对立即推进，单遍结束显示 DONE；不含前奏、间奏或反复。曲谱只指导真人演奏，不自行发声。

**chenxi639** 的波形/琴键反馈、`feature/sustain-pedal` 与 `feature/ec11-sustain` 延音实现及原始提交均已保留；**zrb** 主导平台集成、PCB 验证与需求，Codex 协助实现与验证。详见[协作与更新说明](docs/collaboration_update.md)。

EC11 旋转调节 **16 档尾音衰减速度**，按压切换延音开关；默认 T1 电钢琴、主音量 50%、延音关闭、03 档。HDMI 显示实际开关和档位，延音开启后松键按所选档位衰减。接线和操作见 [EC11 使用说明](docs/ec11_sustain.md)。实体踏板适配器尚未接入，串口 H0/H1 可控制延音。

## 构建与回归

在仓库根目录执行，工具路径按本机填写：

```powershell
$env:GOWIN_HOME = Read-Host 'Gowin IDE 目录'
powershell -NoProfile -ExecutionPolicy Bypass -File instrument/build.ps1 -Ec11

$env:VIVADO_BIN = Read-Host 'Vivado bin 目录'
powershell -NoProfile -ExecutionPolicy Bypass -File instrument/sim/run.ps1 -Python python
```

Python 依赖见 instrument/tools/requirements.txt。上述命令使用 instrument/instrument_ec11.gprj，产出 **dist/instrument_ec11.fs**；仅在新位流及全部时序检查通过后更新产物。下载选择 **GW5AT-60B → SRAM Program**，断电需重新下载。不加选项构建通用工程并产出 dist/instrument.fs；-TouchDebug 构建默认延音调试版，与 -Ec11 互斥。位流和工具缓存不纳入 Git，克隆后需本机构建。

2026-10-25 当前 EC11 构建通过全部时序检查；本次 GUIDE/UI 更新通过 11 项 RTL、13 项 Python 测试，具体范围及位流校验值见 [EC11 验证](docs/ec11_verification.md)。此前旋钮版已通过用户实物实验，新的 GUIDE/UI 仍待重新烧录验收。

完整触键到模拟输出延迟仍待示波器测量，数字仿真不代替整机验收；方法见 [延迟验收](docs/latency_measurement.md)。此前 32 声部实时预算见 [升级验证](docs/upgrade_verification.md)。

## 接线

所有模块共地。J13 为底板物理针号，球号以 instrument/src/instrument.cst 为准；EC11 新增 A13/A14/C13 三根输入，接线细节见专门说明，不改变下表原有连接。

| 信号 | J13 | FPGA 球号 |
|---|---|---|
| MPR121 A SCL / SDA | 1 / 2 | E14 / E13 |
| PCM5102 BCK / LRCK / DIN | 3 / 4 / 5 | C15 / C14 / B13 |
| EC11 SW / B(DT) / A(CLK) | 6 / 7 / 8 | C13 / A14 / A13 |
| EC11 公共地 | 12 | — |
| MPR121 B SCL / SDA | 13 / 14 | A16 / A15 |
| ADS1115 SCL / SDA | 15 / 16 | A20 / B20 |
| 74HC595 SER / SRCLK / RCLK / OE | 17 / 18 / 19 / 20 | A21 / B21 / B18 / B17 |
| BT05 TXD→RX / RXD←TX | 21 / 22 | C17 / D17 |

- MPR121 两块独立 I²C，3.3V 供电，ADD 接地（0x5A），IRQ 留空；任何一块离线均释放所有键并重试。杜邦线必须固定。
- ADS1115 3.3V，ADDR 接地（0x48）；3.3V → FSR → A0 → 10kΩ → GND，A0/GND 并 100nF。A1～A3 留空。
- 现有 PCM5102 底板 5V，SCK 接地、FMT 经 1kΩ 下拉、XSMT 高，模拟输出接有源音箱；其他型号先核对模块电路。
- 两片 74HC595 3.3V，U5 QH′ 接 U6 SER，每次发送 16 位；13 路各经 1kΩ 驱动 LED，其余 3 位为零。LED 按半音阶从低 C 到高 C 排列。
- 已验证 BT05 ZS-040 底板 VCC 5V，TX/RX 为 3.3V，EN/STATE 留空。

| 触摸板 | 电极 0 起顺序 |
|---|---|
| A 0～9 | K0、S0、K1、S1、K2、K3、S2、K4、S3、K5 |
| B 0～7 | S4、K6、K7、X0、C0、C1、C2、C3 |

K0～K7 为自然音，S0～S4 为五个黑键。其余电极悬空。

## 演奏与 GUIDE

C0 短按换音色、长按切换延迟；C1/C2 调音量，两者同时长按切换 GUIDE；按住 C3 开颤音。四个控制键同时长按进入八自然音正弦校准，再次操作退出。

按住 X0 再按 C0/C1/C2/C3，选择第 3/4/5/6 音区；一次组合只生效一次，多键歧义不选。X0 单独按住仍检查 13 灯全亮。校准模式固定 C4～C5。

内置 GUIDE 按对键就在下一个音频采样推进，不等时值或松键，节奏由演奏者掌握。HDMI **整键绿色为下一目标，按下为浅蓝色**，目标 LED 常亮；必要时自动换八度，已发声的音保持原音高。连奏可保持上一键再按下一键；连续同键需松开后再按，不会因按住而连跳。76 音结束后显示 DONE 并熄灭目标灯；重新开关 GUIDE 或发送 R 可从头开始。关闭 GUIDE 恢复手动音区。

公共压力 0V 对应主增益 25%，按用户实测 **3.235V 标定为 100%**，超出钳位，ADC 离线回到主增益；它不是每键力度。掉线、复位或校准模式会取消延音请求。

屏幕 DIGITAL WAVE 显示送 I²S 的数字 PCM，**1X 满幅刻度**，上下边界对应约 ±32768；LIMIT 表示软限幅正在压缩峰值。最大音量和满压力时单音起音约占满幅 92%～94%，尾音按包络衰减；多音过载会改变波形，不能当作无失真放大。八正弦校准保留原线性增益。VOICES 为实际发声声部数，琴键条显示包络；右下角显示 YU JIAN/步数/BPM，D1 切换诊断页。

## 蓝牙串口与曲谱

9600 / 8N1，无流控，每条 LF 或 CRLF，等 K 再发下一条；E 表示拒绝。手机可使用 Serial Bluetooth Terminal，BLE 不一定提供 COM 口。

| 命令 | 功能 |
|---|---|
| ? | 通信检查 |
| T0～T3 / V0～V4096 | 音色 / 主音量 |
| E0/E1、H0/H1、G0/G1 | 回声、延音、GUIDE 开关 |
| B40～B240 | 节拍速度；也影响上传的计时曲谱，内置曲不等待节拍 |
| R | 恢复内置 76 音《遇见》片段并从头开始，BPM 恢复 93 |
| N、Axxxx、Z | 开始上传、追加四位十六进制键位掩码、原子提交 |
| O3～O6 | 上传时设置后续步骤的音区 |
| U1～U255 | 上传时设置后续步骤时值，单位十六分音符；U2 是八分音符 |
| D0/D1 | GUIDE 页 / UART 诊断页 |
| J0～J8191 / J8192 | PCB LED 掩码测试 5 秒 / 取消 |
| L0～L255 / L256 | 旧八白键灯掩码 / 取消 |

每次 N 默认音区 4、不计时模式。A 的 bit0～7 对应 K0～K7，bit8～12 对应 S0～S4；设置 U 后 A0000 表示休止，未设置 U 的空音符拒绝。最多 512 步，上传错误必须重新 N，Z 成功前旧曲谱不变。上传曲谱仍循环播放：设 U 的事件按规定时值和松键推进，未设 U 的非空事件按对立即推进；复位/断电后失效。

文本曲谱支持 C4:2、C#5:1、C4+E4+G4:4、REST:2；和弦必须能放在同一物理音区，工具会在发送前检查。行首 # 为注释。下列上传例子会启用计时模式；内置《遇见》无需上传。

```powershell
python instrument/tools/serial_control.py --score assets/scores/yujian.txt --bpm 93 --emit
# 有实际 SPP/USB-UART 数据串口时（不是 JTAG 下载口）：
python instrument/tools/serial_control.py --port COM7 --score assets/scores/yujian.txt --bpm 93
```

失步时工具会先发送无效行清除半行，再用 ? 同步。上传不自动重发 A，避免重复追加。完整 TX= 状态行静默忽略。J1/J2/.../J4096 依次可检查 13 个 PCB 灯。

光电与手势本轮仅规划：[硬件准备与条件接线](docs/optical_hardware_plan.md)。不用重画现有主 PCB；先做外接验证。
