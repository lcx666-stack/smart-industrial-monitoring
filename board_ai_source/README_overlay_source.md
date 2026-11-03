# CS500 板载 NPU 缺陷框图验证（2026-10-14）

已验证入口是板端 `/data/board_ai_overlay_candidate_20261014/run_board_quant.sh`，
电脑端是 `view_board_ai_cv.py --host 192.168.0.50`。旧版 `run_board.sh` 和
`cs500_board_ai_overlay` 是首次失败的候选，不要再运行。电机驱动 12 V VM 必须
始终物理断开；本候选不做电机控制或安全判断。电脑仅接收板端 RGB 与框，
不加载模型、不推理。

模型仍是此前训练的单类 `blade_defect`：
`best_raw_heads_qdq_inferred_trial.onnx`。Arm NN Hybrid 图含 Alnpu，
量化输入和六路输出按板端实际 TensorInfo 处理；YOLOv8 DFL、阈值 0.25、
NMS IoU 0.70、框坐标映射全在开发板执行。每五帧推理一次，其他帧沿用最近框。
使用既有 CS500 单帧 DMA、960×540 NEON 缩图和 AWB；没有修改 BOOT、DTB、
内核、相机寄存器、FPGA bitstream 或电机文件。

本次板上验证：厂商模型及本模型各单次 Hybrid 推理 EXIT=0；整合预览超过
5571 帧，约 6.9–7.0 fps，NPU 单次约 85 ms，`guard_faults=0x0`；
正常扇叶 `boxes=0`，相机对准已有裂纹测试图时 `boxes=1`，电脑出现绿色框，
位置在裂纹附近。关闭电脑端后板端打印 `BOARD_AI_STOPPED ... CMA released`。
这仅证明板端推理、传输和画框通路；屏幕反拍的合成图不能代表真实缺陷准确率。
此前相机本身单帧采集约 10 fps，因此本候选不声称达到 30 fps。

`stage_rootfs_vm.sh` 是给完全断电、唯一 SD 在 Ubuntu 虚拟机时的新卡首次
安装脚本；它只向 ext4 rootfs 的新目录添加量化版程序和启动脚本，先核对
唯一 SD 序号、BOOT、模型和依赖，不覆盖现有目标目录。本轮已在运行中的
开发板上按 SHA-256 单独安装修正版程序和启动脚本，不需要再写卡。
若板端打印 `FAIL ... CMA retained`、AXI/FIFO fault 或 NPU timeout，不要重试或
强杀，直接切断开发板电源；电机 12 V 继续断开。

## 2026-10-15 新增：源文件里的 `--roi` 与 `--image-raw`

`cs500_board_ai_overlay.cpp` 现在支持两个新参数（**部署中的
`cs500_board_ai_overlay_quant_20261014` 仍是从改动前的源码构建的**，
`run_board_quant.sh` 用 SHA-256 锁住它，本轮没有替换）：

- `--roi x,y,w,h`：只把 960×540 半幅帧里的一块区域按 1:1 补边送进 640×640
  输入（不缩放），框坐标再映射回整帧坐标。单次推理耗时不变（约 85 ms），
  但缺陷像素多 1.5 倍；实测 mAP50 从 0.145 提到 0.328，叠加裁窗抖动增广后
  到 0.515。几何核对脚本：`board_ai_accuracy_20261014/verify_roi_letterbox.py`。
- `--image-raw FILE`：不开摄像头、不开端口，对一张 960×540 原始 RGB 帧跑一次
  推理并打印各检测头的统计量（`report_heads`），用于和电脑端
  `board_ai_accuracy_20261014/predict_head_stats.py` 逐行对比 Alnpu 数值。

新构建的二进制（含上述两个参数）放在 `board_ai_roi_20261015/`，配套模型、
启动脚本与部署说明见该目录 README；本轮因模型召回不足**未部署**。
