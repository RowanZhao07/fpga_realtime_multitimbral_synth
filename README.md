# FPGA 实时多音色电子乐器

Tang Mega 60K NEO（GW5AT-60B）上的纯 HDL 合成器，不使用处理器、MCU 或预录音源。

运行版移除了壁纸 ROM，保留 800×600 HDMI 琴键、512 点波形、4096 点 Hann 窗 FFT 和 GUIDE。原始壁纸图片仍保留在 assets/wallpapers，当前工程不使用它们。

- 13 个触摸音键，四档音区 C3～C4 / C4～C5 / C5～C6 / C6～C7，默认 C4～C5。
- 32 个独立相位、音高、音色、ADSR 状态；共享计算流水线在每个音频样本内计算全部声部。四档音区合计 49 个不同音高，最大同时发声 32 个。
- 每次重按分配新声部，跨音区的旧延音和释音尾巴保留。满载时先找空闲，再选最轻的释放声部，最后抢占最老声部；抢占保留 8 样本短淡出。
- 四音色：正弦、电钢琴感、合成弦乐、金属音。数学波表插值，基波与泛音层采用不同时间变化；新音锁定音色，旧尾音不被全局切换。
- 公共压力、颤音、延迟效果、延音、13 键灯和蓝牙参数控制。混音固定增益，32 声部预留额外 6dB 余量，新增按键不会使旧音自动变小。
- GUIDE 最多 512 步，支持时值、休止、和弦、自动切换音区。内置原创《夜航练习曲》24 小节、192 步，覆盖四档音区；曲谱只指导真人演奏，不自行发声。

队友 **chenxi639** 的波形/琴键反馈与 `feature/sustain-pedal` 延音实现已保留；**zrb** 主导平台集成、PCB 验证及本轮需求，Codex 协助实现与验证。详见[协作与更新说明](docs/collaboration_update.md)。此前的[延音版本说明](docs/sustain_release.md) 是历史记录，声部分配与 GUIDE 以当前实现为准。实体踏板适配器尚未接入，串口 H0/H1 可控制延音。

## 构建与回归

在仓库根目录执行，工具路径按本机填写：

```powershell
$env:GOWIN_HOME = Read-Host 'Gowin IDE 目录'
powershell -NoProfile -ExecutionPolicy Bypass -File instrument/build.ps1

$env:VIVADO_BIN = Read-Host 'Vivado bin 目录'
powershell -NoProfile -ExecutionPolicy Bypass -File instrument/sim/run.ps1 -Python python
```

Python 依赖见 instrument/tools/requirements.txt。构建仅在新位流、setup/hold、recovery/removal 和最小脉宽检查通过后更新 dist/instrument.fs。下载选择 **GW5AT-60B → SRAM Program**；断电需重新下载。触摸默认延音工程仍为 instrument/instrument_touch_debug.gprj，构建脚本加 -TouchDebug。

本轮未连接实物：RTL 仿真、布局布线通过不等于已实测模拟输出。完整触键到 DAC 的方法与工具见 [延迟验收](docs/latency_measurement.md)。数字状态到 I²S 的 tb_latency 不包含 MPR121 和模拟链路，不能替代整机 ≤10ms 验收。

此次构建资源、实时预算、验证记录及位流校验值见 [升级验证](docs/upgrade_verification.md)。

## 接线

所有模块共地。J13 为底板物理针号，球号以 instrument/src/instrument.cst 为准；本轮没有新增硬件引脚。

| 信号 | J13 | FPGA 球号 |
|---|---|---|
| MPR121 A SCL / SDA | 1 / 2 | E14 / E13 |
| PCM5102 BCK / LRCK / DIN | 3 / 4 / 5 | C15 / C14 / B13 |
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

GUIDE 开启时以当前曲谱事件的绝对音区为准，HDMI 音名同步变化；无需手动换八度。等待正确键/和弦后开始计时，经过规定时值且按键释放才进入下一步；提前松手仍等待剩余时值，按住不放不会误触发下一音区。休止符自动计时，额外按键会阻止其结束。这是可等待演奏者的节奏辅助跟弹，不是严格节拍评分器。关闭 GUIDE 恢复此前手动音区，已发声的尾音保持原音高。

新声部保留旧音尾巴会比旧版更饱满；满 32 声部才抢占。公共压力 0V 对应主增益 25%，≥3.072V 对应 100%，ADC 离线回到主增益；它不是每键力度。正弦和弦乐可延音保持，电钢琴与金属音仍自然衰减。掉线、复位或校准模式会取消串口延音请求。

屏幕 DIGITAL WAVE 显示送 I²S 的数字 PCM，4 倍纵向放大，不是声压；VOICES 为实际发声声部数，琴键蓝色/小条聚合该物理键各尾音的包络。右下角保留 GUIDE/曲目/步数/BPM/状态，D1 才切换诊断页。

## 蓝牙串口与曲谱

9600 / 8N1，无流控，每条 LF 或 CRLF，等 K 再发下一条；E 表示拒绝。手机可使用 Serial Bluetooth Terminal，BLE 不一定提供 COM 口。

| 命令 | 功能 |
|---|---|
| ? | 通信检查 |
| T0～T3 / V0～V4096 | 音色 / 主音量 |
| E0/E1、H0/H1、G0/G1 | 回声、延音、GUIDE 开关 |
| B40～B240 | BPM，改变后影响后续时值计时 |
| R | 恢复内置 192 步《夜航》 |
| N、Axxxx、Z | 开始上传、追加四位十六进制键位掩码、原子提交 |
| O3～O6 | 上传时设置后续步骤的音区 |
| U1～U255 | 上传时设置后续步骤时值，单位十六分音符；U2 是八分音符 |
| D0/D1 | GUIDE 页 / UART 诊断页 |
| J0～J8191 / J8192 | PCB LED 掩码测试 5 秒 / 取消 |
| L0～L255 / L256 | 旧八白键灯掩码 / 取消 |

每次 N 默认音区 4、旧版不计时模式。A 的 bit0～7 对应 K0～K7，bit8～12 对应 S0～S4；设置 U 后 A0000 表示休止，未设置 U 的空音符拒绝。最多 512 步，上传错误必须重新 N，Z 成功前旧曲谱不变。自定义曲谱在复位/断电后失效。旧版非空掩码曲谱仍是按对立即推进。

文本曲谱支持 C4:2、C#5:1、C4+E4+G4:4、REST:2；和弦必须能放在同一物理音区，工具会在发送前检查。行首 # 为注释。

```powershell
python instrument/tools/serial_control.py --score assets/scores/nocturne.txt --bpm 120 --emit
# 有实际 SPP/USB-UART 数据串口时（不是 JTAG 下载口）：
python instrument/tools/serial_control.py --port COM7 --score assets/scores/nocturne.txt --bpm 120
```

失步时工具会先发送无效行清除半行，再用 ? 同步。上传不自动重发 A，避免重复追加。完整 TX= 状态行静默忽略。J1/J2/.../J4096 依次可检查 13 个 PCB 灯。

光电与手势本轮仅规划：[硬件准备与条件接线](docs/optical_hardware_plan.md)。不用重画现有主 PCB；先做外接验证。
