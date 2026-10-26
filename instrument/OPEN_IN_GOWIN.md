# 用高云 IDE 打开默认延音触摸调试工程

**KY-023 摇杆 + EC11 + 单 ADS1115 复用 组合版请打开 `instrument_joystick.gprj`。** 本机已准备 IDE 配置；异机先复制 `config/joystick_process_config.json` 到 `impl/instrument_joystick_process_config.json`。接线与调试见 [摇杆组合版说明](../docs/joystick_controls.md)。

本目录的调试工程入口：**instrument_touch_debug.gprj**。

**使用 EC11 旋钮时请改开 instrument_ec11.gprj**，先将 config/ec11_process_config.json 复制到本地 impl/instrument_ec11_process_config.json。该工程默认关闭延音，旋转调节 16 档、按压切换开关；完整步骤及五脚接线见 [EC11 说明](../docs/ec11_sustain.md)。下面的默认开启步骤专用于没有旋钮的触摸调试工程。

## 直接打开与编译

1. 在高云 IDE 1.9.12.04 中选择 File → Open Project，打开本目录下的 `instrument_touch_debug.gprj`。请选这个调试工程；`instrument.gprj` 是正常版本入口，默认延音关闭。
2. 确认器件为 `GW5AT-LV60PG484AC1/I0`（GW5AT-60B），顶层为 `instrument_top`。
3. 从 GitHub 首次下载时，先建立 `impl` 文件夹，将 `config/touch_debug_process_config.json` 复制为 `impl/instrument_touch_debug_process_config.json`，再打开工程；如果已经打开，请关闭后重新打开。`impl` 是本地生成目录，不随 Git 提交。也可在 IDE 中设置 Include Path 为 `src`，VCCX 为 `1.8V`，Use CPU as GPIO 开启。文件路径均相对本工程目录。
4. 在 IDE 中执行 Synthesize，再执行 Place & Route（或执行 Run All）。检查 Timing Analysis：建立/保持时间及最小脉宽均应无违规，再进入烧录。
5. 由 IDE 本次编译生成的烧录文件为 `impl/pnr/instrument_touch_debug.fs`。在 Gowin Programmer 中选择 GW5AT-60B → SRAM Program，载入这个文件后执行。

如果清理过 `impl` 目录，在 IDE 配置界面重新设置上述三项，或先将 `config/touch_debug_process_config.json` 复制到 `impl/instrument_touch_debug_process_config.json`，再打开工程。复制整个项目文件夹时保留 `config`、`src`、工程文件以及该 IDE 配置文件。

## 本测试版的默认行为

- 使用原触摸输入，实际触摸才触发音符。
- 上电默认 T1 电钢琴、延音开启、主音量 50%、回声关闭。
- 无需踏板，也无需开机先发送 H1；触摸板必须正常上线。
- 松键后尾音自然衰减，最终消音；同音重按可以再次起音。
- 原来的 C0 音色控制、C1/C2 音量控制继续有效。
- 如果已有蓝牙或数据串口，可发送 H0 释放延音，H1 开启延音。复位、触摸重新上线及退出校准模式后恢复默认开启。
- HDMI 显示 `SUST DEBUG`；真实外设的在线状态仍正常显示。

## 烧录后快速检查

短触 C4 后松开，确认声音继续衰减；再短触 C4、E4、G4，确认尾音叠加与同音重弹。外接键灯反映实际按住状态，屏幕包络条反映余音，因此松键后键灯熄灭、包络仍在变化是预期行为。

当前源码包含 32 动态声部及自动音区 GUIDE；默认延音行为已通过 RTL 测试。2026-10-22 完成的是正常工程的布局布线与位流生成，详见[升级验证](../docs/upgrade_verification.md)。调试工程需要按上述步骤单独编译，不能把旧调试位流当作本轮升级版；新版本仍需实板验收。
