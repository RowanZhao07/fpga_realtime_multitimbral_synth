# 打开表情演奏工程 EXPR U2

当前活动工程只有 `instrument_expression.gprj`，沿用原 L1 的 C15 音频接线。

1. 在 Gowin IDE 打开本目录的 `instrument_expression.gprj`。器件为 `GW5AT-LV60PG484AC1/I0`，顶层为 `instrument_top`。
2. 首次打开前建立 `impl`，把 `config/expression_process_config.json` 复制为 `impl/instrument_expression_process_config.json`。Include Path 为 `src`，VCCX 为 1.8 V，Use CPU as GPIO 开启。
3. 推荐从仓库根目录运行 `./instrument/build.ps1 -Expression -GowinShell '<IDE>/bin/gw_sh.exe'`。脚本检查构建新鲜度、源码哈希及 setup/hold/脉宽后，发布 `dist/instrument_expression_ui_v2_3x.fs` 与 manifest。
4. 直接由 IDE Run All 生成的文件名仍为 `impl/pnr/instrument_expression.fs`。请先检查时序，再明确区分它与冻结的 `dist/instrument_expression_link_v1.fs`。
5. 下载选择 GW5AT-60B → SRAM Program，断电后需重新下载。`EXPR U2 3X` 标识显示在屏幕右上角，两个图均显示 `3X`。默认 T1 电钢琴、50% 主音量、延音关闭、03 档、Y 弯音关闭。

原 L1 位流不覆盖。其他旧工程及原脚本在 `backups/expression-link-v1-20261101/source/instrument/`，旧诊断和 D16 配置应从归档副本恢复使用。

[界面、资源与验证记录](../docs/expression_ui_v2.md) & [表情控制](../docs/expression_controls.md) & [当前接线](../docs/wiring_current.md)
