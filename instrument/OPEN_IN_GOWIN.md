# 打开表情演奏工程 EXPR M2 8T

活动工程为 `instrument_expression.gprj`，BCK / LRCK / DIN 使用 C15 / C14 / B13。

1. 在 Gowin IDE 打开本目录的 `instrument_expression.gprj`。器件为 `GW5AT-LV60PG484AC1/I0`，顶层为 `instrument_top`。
2. 首次打开前建立 `impl`，把 `config/expression_process_config.json` 复制为 `impl/instrument_expression_process_config.json`。Include Path 为 `src`，VCCX 为 1.8 V，Use CPU as GPIO 开启。
3. 推荐从仓库根目录运行 `./instrument/build.ps1 -Expression -GowinShell '<IDE>/bin/gw_sh.exe'`。脚本检查构建新鲜度、源码哈希及 setup/hold/脉宽后，发布 `dist/instrument_expression_metronome_v2_louder.fs` 与 manifest。
4. 直接由 IDE Run All 生成的文件名为 `impl/pnr/instrument_expression.fs`。发布时使用构建脚本生成带哈希与时序检查结果的 manifest。
5. 下载选择 GW5AT-60B → SRAM Program，断电后需重新下载。`EXPR M2 8T` 标识显示在屏幕右上角，两个图均显示 `3X`。默认 T1 电钢琴、50% 主音量、延音关闭、03 档、Y 弯音关闭；短按 C0 循环八种音色。节拍器默认关闭、120 BPM、4/4。

源码、约束、配置和测试纳入 Git；位流与构建缓存保留在本地 `dist/`、`impl/`，最终发布身份见[发布验证](../docs/release_verification.md)。

[节拍器操作与验证](../docs/metronome.md) & [八音色验证记录](../docs/eight_timbres.md) & [表情控制](../docs/expression_controls.md) & [当前接线](../docs/wiring_current.md)
