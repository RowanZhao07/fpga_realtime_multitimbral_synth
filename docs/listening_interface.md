# 听音算法接入接口 v1

日期：2026-10-09。当前实现的是接口与数据发布，不是音高、和弦或旋律识别算法。

## 接入边界

`instrument_top.v` 的 `analysis_port` 实例提供本机播放 PCM 参考流，默认 `SOURCE_EXTERNAL=0`。其 `external_ce` 和 `external_sample` 目前接零，识别结果端也接零，界面不会显示虚构的识别结果。这些未消费的接口允许被综合器裁剪；它们是源码级扩展点，不是已经存在的物理音频输入引脚。

PCM5102 是输出 DAC；外部听音需要另外的麦克风/ADC 或数字麦克风接收模块。未来新增接收器、引脚约束、时钟域转换和输入测试后，将输入接到 `external_*`，并设 `SOURCE_EXTERNAL=1`。所有进入本模块的信号必须已经同步到系统 `clk`；异步 I2S 接收数据应通过异步 FIFO 进入该时钟域。切换源或采样率配置时复位分析链路。

## 原始 PCM 通道

| 信号 | 含义 |
|---|---|
| `analysis_ce` | 单周期样本有效；消费者在系统时钟上升沿采样 |
| `analysis_sample[15:0]` | 二进制补码、有符号 PCM16 |
| `sample_index[31:0]` | 当前有效样本编号；首个为 0，按有效样本递增，32 位回绕 |
| `analysis_external` | 0=本机播放参考，1=外部输入；不要将二者混淆 |
| `analysis_rate_numerator/denominator` | 精确采样率比值；默认 50000000/1024，即 48828.125 Hz |

通道没有 `ready`，算法不能暂停 DAC 或外部采样。消费者必须跟上输入或自带环形缓冲/FIFO，并自行上报溢出。`RATE_NUMERATOR`、`RATE_DENOMINATOR` 只是元数据，必须由接入方与真实接收器配置保持一致；它们不会调整采样时钟。默认播放流与 I2S 装载的样本对应。

## FFT 通道

`audio_spectrum` 公开 `bin_valid`、`bin_index[8:0]`、`bin_real`、`bin_imag`、`bin_magnitude`、`bin_frame_start` 和 `frame_sample_index`；顶层保留了同名用途的 `fft_*` 连接线。

- 4096 点、Hann 窗、每级缩放 1/2；复数输出总体约为 FFT(x × Hann)/4096。
- 公开前 512 个频点，索引 0～511，分辨率约 11.92093 Hz，覆盖到约 6091.60 Hz。
- `bin_frame_start` 与第 0 个 `bin_valid` 同时有效。
- `frame_sample_index` 标识本次窗口第一个样本的流编号；所有频点属于同一窗口。
- 在 `bin_valid=1` 的上升沿读取结果；其余时间数据不保证为有效频点。
- `bin_magnitude` 是 |Re|+|Im| 的近似值，精密幅度/能量算法可使用公开复数结果。
- FFT 是间歇快照，不是连续重叠 STFT。音频在计算与等待阶段继续输出，但该阶段的样本不进入本次 FFT 窗口。
- 现有顶层 FFT 输入仍然是本机输出，不能将其频谱当作麦克风频谱。外部听音可将独立分析 FFT 接到外部 PCM，或另外实现时域算法。

保留 `ENABLE_SCOPE=1` 默认值兼容旧测试与复用场景；整机实例设为 0，只发布频谱。显示器的 `frame_ack` 仍控制这一 FFT 的发布，不应被听音算法占用。算法接收没有背压，在结果输出的短突发期间应能逐项接收或使用自己的 FIFO。

## 结果通道与 96 位载荷约定

算法驱动 `result_valid` 与 `result_payload`。`result_ready` 在非复位期间为 1，`valid && ready` 的上升沿接受结果。接受后产生单周期 `result_update`，更新 `latest_result` 并置 `latest_valid=1`。允许连续每周期提交新结果；只保留最近一次，不是消息队列。

建议所有后续算法采用以下统一布局；模块本身将载荷视为不透明数据，不替算法检查这些字段：

| 位段 | 字段 | 编码 |
|---|---|---|
| 95:64 | `window_end_index` | 分析窗口最后一个样本的编号，与 PCM 流对应 |
| 63:40 | `frequency_q8` | 无符号频率 Hz×256；0 表示不可用 |
| 39:28 | `pitch_class_mask` | 12 位音级集合，bit0=C、bit1=C#、…、bit11=B |
| 27:21 | `midi_note` | 0～127；是否有效由 flags 指定 |
| 20:13 | `confidence` | 0～255；算法自行校准，不能跨算法直接比较 |
| 12:5 | `flags` | bit0=有效音高；bit1=有效音级集合；bit2=起音；bit3=输入溢出；其余预留为0 |
| 4 | `source_external` | 必须与分析源一致 |
| 3 | `voiced` | 算法判定存在可分析的周期性/乐音成分 |
| 2:0 | reserved | 固定为0，后续升级约定再分配 |

`latest_valid` 表示结果尚未过期，不表示音高一定有效，仍需检查 flags/voiced。默认经过 50000000 个系统时钟没有新结果后失效，50 MHz 下为1秒；输入停采时也会失效。可通过 `EXPIRE_CYCLES` 调整，改变系统频率时必须同步配置。失效时保留载荷便于诊断，消费者必须用 `latest_valid` 屏蔽它。界面建议将结果与有效位打包，再通过 mailbox 跨到像素域，不直接跨域读载荷。

## 接入示例

```verilog
// algorithm 是下一阶段实际实现的识别模块，当前工程没有这个模块。
algorithm detector (
    .clk(clk), .rst(analyser_rst),
    .sample_ce(analysis_ce), .sample(analysis_sample),
    .sample_index(analysis_index),
    .result_valid(detected_valid), .result_payload(detected_payload),
    .result_ready(result_ready)
);
// 将 analysis_port 实例中原有 result_valid(1'b0)、result_payload(96'd0)
// 替换成 detected_valid、detected_payload；勿保持接零。
```

先用本机合成音建立可重复的数据集，再验证独立外部录音。建议最先实现单音音高及音准评价，随后按赛题要求扩展音级集合/和弦、起音、旋律和节奏对齐。单音可评估 YIN/自相关与 FFT 谐波评分的资源、精度和延迟取舍；YIN 原始论文：[de Cheveigné & Kawahara, 2002](https://pubmed.ncbi.nlm.nih.gov/12002874/)。多音场景不能仅取最强 FFT 柱作为基音，需要另外的多候选、谐波消歧及数据集评测。

## 已有验证

`tb_listening_port` 验证来源隔离、带符号样本、样本编号、结果握手、无样本时的过期和复位。`tb_spectrum` 使用公开复数输出进行独立参考比较，并检查帧开始及窗口样本编号。尚未验证真实麦克风接收、噪声鲁棒性、多音识别或识别准确率。
