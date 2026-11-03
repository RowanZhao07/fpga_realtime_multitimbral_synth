# 八种合成音色

当前 EXPR M2 8T 提供八套数学波表与包络参数。上电默认 T1，短按松开 C0/TONE 循环切换；UART 使用 `T0`～`T7`。音色在每个声部起音时锁存，切换不改变已发声的尾音。

| 编号 | 屏幕名称 | 合成特征 |
|---|---|---|
| T0 | SINE | 正弦纯音，作为频率与响应基准 |
| T1 | EPIANO | 较快起音，谐波随尾音衰减 |
| T2 | STRINGS | 缓慢起音，持续发声 |
| T3 | METAL | 明亮起音，打击衰减 |
| T4 | FLUTE | 柔和起音，基音与少量谐波 |
| T5 | ORGAN | 快速起音，持续八度谐波，短释放 |
| T6 | PLUCK | 明亮拨弦起音，快速变暗与衰减 |
| T7 | BASS | 较厚实起音，缓慢的音量和谐波衰减 |

波表容量为 8 × 256 × 16 bit，由 `instrument/tools/generate_visual_tables.py` 生成。各音色通过谐波权重、ADSR 与时变亮度形成特征。它们是合成音色，不使用乐器录音。原四种波表的 1024 个整数采样与参数保持一致。

32 声部共用运算通路而各自保存相位、频率、包络和音色。每个采样帧依次执行分配、相位与插值、包络、混合及提交；密集重触发与跨音区尾音用例最重帧为 829 / 1024 时钟。

八音色专项回归解码 164,211 个立体声 I²S 帧，检查声道数据、起音和释放静音；八音色 × 16 档延音检查尾音单调与档位顺序。测试条件为 C4、最大主音量、无压力衰减、效果关闭。最终版本的资源和回归分层见[发布验证](release_verification.md)。

```powershell
./instrument/sim/run.ps1 -VivadoBin '<Vivado>/bin' -GowinSimLib '<Gowin IDE>/simlib/gw5a/prim_sim.v' -NoAnalysis -Only 'tb_eight_timbres,tb_timbre_mailbox,tb_variable_sustain'
python instrument/tools/analyze_eight_timbres.py
```
