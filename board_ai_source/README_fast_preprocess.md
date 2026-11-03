# AI 预处理快路径候选（2026-10-17）

本目录保存第一档主机侧优化的 AArch64 构建产物。快路径已完成电脑端与板端 A/B，
并已接入板端默认 AI 入口；旧的参考 launcher 和旧控制脚本仍保留用于回退。

## 改了什么

修改源码：`board_ai_overlay_candidate_20261014/cs500_board_ai_overlay.cpp`

- ROI 为 1:1（640×360 → 640×640 的 640×360 区域）时，跳过双线性插值和逐像素
  `lround`，直接按行拷贝。
- 输入量化改为 256 项 LUT；当前模型输入 scale `0.00392156886`、offset 0，
  LUT 是恒等映射。
- NCHW 输入用逐行 RGB 解交织，保持原来的平面顺序。
- padding 只在构造时填一次，不再每帧重填 640×640。
- 新增 `BOARD_AI_REFERENCE_PREPROCESS=1`，强制走旧的参考路径。
- 新增 `BOARD_AI_DUMP_INPUT_HASH=1`，每次推理打印输入张量 FNV-1a 哈希，供 A/B。

旧的参考路径完整保留；快路径只在该 ROI/量化条件成立时启用，否则自动回退。

## 产物

| 文件 | SHA-256 | 大小 |
| --- | --- | ---: |
| `cs500_board_ai_overlay_fast_20261017` | `d9755773791a1c67b25d6d1045d7c0728d4642064a196c1b6c8ded6603abd64a` | 123,080 |
| `cs500_board_ai_batch_eval_fast_20261017` | `2fc94a7677d6a099521e8fa7c497ef7fe788e406b19761a085ee27e79080b5b5` | 137,528 |

两者都是 ELF64/AArch64，依赖不高于 GLIBC 2.17、GLIBCXX 3.4.21。

## 电脑端等价性验证

```powershell
& .\.venv_fan\Scripts\python.exe .\tools\verify_fast_preprocess.py
```

电脑端结果：

- 模型输入 scale `0.00392156886`，offset 0
- LUT identity = True
- padding = 114
- 第三轮封存 72 帧，参考路径与快路径的输入张量 **72/72 逐字节完全一致**

板端 A/B 随后也已完成，见下节。

## 板端 A/B 结果

使用同一第三轮封存 72 帧、当前 bias 模型和 36/36/36 ROI 计数：

| 路径 | 输入哈希 | 正常误框 | 缺陷 TP/FP/FN | NPU 中位 / P95 | 流水线中位 / P95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 参考双线性 | 72/72 一致 | 0 | 30 / 9 / 6 | 84.786 / 85.028 ms | 205.064 / 205.417 ms |
| 1:1 快路径 | 72/72 一致 | 0 | 30 / 9 / 6 | 84.607 / 84.853 ms | **117.302 / 117.595 ms** |

- 72 个 `input_hash` 完全一致。
- 去掉计时字段后，72 条逐帧 TP/FP/FN 完全一致。
- NPU 时间基本不变（约 84.6–84.8 ms），缩短来自主机侧。
- 流水线中位数缩短 **87.762 ms（42.8%）**，主机侧开销从约 120.3 ms 降到约 32.7 ms。
- 两次运行都开了输入哈希，因此计时包含哈希开销；相对比较仍然有效。

## 默认入口部署

| 项目 | SHA-256 |
| --- | --- |
| 快路径 overlay | `d9755773791a1c67b25d6d1045d7c0728d4642064a196c1b6c8ded6603abd64a` |
| 快路径 launcher | `e259daab54c951f526749d0f1d6e4bcbc368b2f9fc60cbbf0c181e53db51dc26` |
| 切换后控制脚本 | `f89321c20689ed42e2b8deab69c35b875e69e19f93a2c4003d987347195e095a` |
| 切换前控制脚本备份 | `185f9c854df3e81195ecfb108853f9242cd8405ddfb10a3c30667e48a72a56e7` |

默认入口验收：`ai_start` 返回 ready；客户端接收 120 帧，约 7.70 fps，
24 次推理；`ai_stop` 返回 `AI stopped; CMA released`。
板端较长会话日志的平均帧率约 6.97 fps，NPU 约 84.5–85.0 ms。
该正常画面在客户端 120 帧窗口内 0 框；更长的板端日志出现过 1–2 个孤立框，
仍需继续观察正常场景误报。

## 板端复现 A/B（保留命令）

把 `cs500_board_ai_batch_eval_fast_20261017` 传到板端独立目录，使用同一封存包和
当前 bias 模型：

```bash
cd /data/board_round3_eval_20261017
libs=/data/fused_npu_eth_probe_20261012
model=/data/board_ai_round2_bias_default_20261017/models/round2_118_bias.onnx

LD_LIBRARY_PATH="$libs" BOARD_AI_REFERENCE_PREPROCESS=1 BOARD_AI_DUMP_INPUT_HASH=1 \
  ./batch_eval_fast "$model" data 36 36 36 roi > logs/ab_reference.log 2>&1
echo REFERENCE_EXIT=$?

LD_LIBRARY_PATH="$libs" BOARD_AI_DUMP_INPUT_HASH=1 \
  ./batch_eval_fast "$model" data 36 36 36 roi > logs/ab_fast.log 2>&1
echo FAST_EXIT=$?
```

要求：

```bash
diff <(grep input_hash logs/ab_reference.log) <(grep input_hash logs/ab_fast.log)
diff <(grep 'BOARD_BATCH frame=' logs/ab_reference.log | sed 's/ npu_ms=.*$//') \
     <(grep 'BOARD_BATCH frame=' logs/ab_fast.log | sed 's/ npu_ms=.*$//')
grep -E 'BOARD_AI preprocess=|BOARD_BATCH_SUMMARY|BOARD_BATCH_TIMING|BOARD_BATCH_DONE' logs/ab_reference.log logs/ab_fast.log
```

输入哈希和逐帧结果必须完全一致；再看 `BOARD_BATCH_TIMING` 的实际主机侧节省。

## 构建

本机使用：

- Linaro：`D:\Anlogic\FD_2026.1_SP1\toolchain\gcc\aarch64_linux\bin\aarch64-linux-gnu-g++.exe`
- Arm NN SDK：`D:\VMware-Share\fan_vision_candidate_20261011\live_preview_candidate_20261012\armnn_lib`

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_board_ai_fast.ps1
```

## 默认入口状态

板端默认 launcher 已切换到
`run_round2_bias_roi_fast_20261017.sh`，控制脚本 SHA-256 为
`f89321c20689ed42e2b8deab69c35b875e69e19f93a2c4003d987347195e095a`。
旧的参考 launcher 和切换前控制脚本
（`board_control_duty.py.pre_fast_preprocess_20261017`，SHA-256
`185f9c85...`）都保留。

回退：

```bash
python3 -B /data/board_ai_round2_bias_default_20261017/deploy_fast_preprocess_default.py --check-rollback
python3 -B /data/board_ai_round2_bias_default_20261017/deploy_fast_preprocess_default.py --rollback
```

回退后重新打开电脑控制台。
