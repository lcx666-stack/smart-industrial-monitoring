# round2_118 bias 默认 AI 入口（2026-10-17）

本目录的 bias 模型已按用户决定设为 CS500 板端默认 AI 入口。它不是新的训练权重，
而是第三轮候选的 Arm NN 兼容版加上 Conv bias 补偿。

## 板端文件

- 默认目录：`/data/board_ai_round2_bias_default_20261017/`
- 启动脚本：`run_round2_bias_roi.sh`
  - SHA-256 `b124de290642df01c3a03575dba210addc3f121d0553ab3d7ea08d91c32d08f1`
- 模型：`models/round2_118_bias.onnx`
  - SHA-256 `e56f166a443d20394ad7eaa93e624d4bb25040ef47cecc38ba96ea3504deb860`
- ROI：`160,90,640,360`，`--infer-every 5`

控制脚本 `/data/ethernet_control_20261014/board_control_duty.py` 已指向本目录，
切换后的 SHA-256 为
`185f9c854df3e81195ecfb108853f9242cd8405ddfb10a3c30667e48a72a56e7`。
随后又启用了 1:1 预处理快路径，当前控制脚本 SHA-256 为
`f89321c20689ed42e2b8deab69c35b875e69e19f93a2c4003d987347195e095a`，
快路径 launcher 为 `run_round2_bias_roi_fast_20261017.sh`，详见
[board_ai_fast_preprocess_20261017/README_CN.md](../board_ai_fast_preprocess_20261017/README_CN.md)。

## 验证摘要

- 第三轮封存盲测板端：正常 36 帧 0 误框；缺陷 36 帧命中 30 框、漏 6 框、
  缺陷图额外误框 9 个。
- 实时连续预览：200 帧，6.85 fps，40 次推理，正常叶片场景 0 框，
  NPU 约 84.8 ms，`guard_faults=0x0`，正常退出并 `CMA released`。
- 默认入口启停：`ai_start` 返回 ready；60 帧、6.69 fps、0 框；
  `ai_stop` 返回 `AI stopped; CMA released`。

详细记录：

- `docs/seed13_round3_board_result_20261017.md`
- `docs/seed13_round3_live_bias_20261017.md`
- `docs/round2_bias_default_deployment_20261017.md`

## 回退

关闭电脑控制台并确认 AI/电机停止后，在板端运行：

```bash
python3 -B /data/board_ai_round2_bias_default_20261017/deploy_round2_bias_default.py --check-rollback
python3 -B /data/board_ai_round2_bias_default_20261017/deploy_round2_bias_default.py --rollback
```

回退恢复 `b77bec7d...` 控制脚本和 seed13 入口；seed13 目录与模型未被覆盖。
回退后重新打开电脑控制台。

## 限制

本候选仍有 6 帧漏检、9 个缺陷图额外误框；实时测试画面是正常叶片，尚未完成
“已知缺陷叶片在 ROI 内”的现场框位置检查。继续使用时应补做该检查并观察更多
正常场景误报。电机 12 V VM 仍须按项目规则保持物理断开；AI 入口不构成安全认证。
