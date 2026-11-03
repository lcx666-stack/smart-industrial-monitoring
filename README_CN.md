# 智能工业状态监测与安全控制系统源码

本目录是从工作区整理出的源码副本，原工程文件保持原样。按硬件逻辑、板端 Linux、CAN/RTC、上位机和板载 AI 分开存放；各子目录中的文件仍保留原有相对路径。

## 目录

- `hardware_can_rtc/`：当前 CAN＋RTC FPGA 工程源码与 IP 配置。顶层为 `motor_camera_npu_eth_can_top.v`，构建入口为 `build_can_bit.tcl`。只包含源码和设计配置，不含 bitstream、BOOT、布线报告或构建日志。构建需安装对应版本的安路 TD 工具和器件/IP 库。
- `software/`：板端 Linux 电机控制、波形 DMA、黑匣子、ADC 检查与配套 C/Python 工具。
- `can_comm_candidate_20261018/`：CS500 到 STM32 的 CAN 故障报警协议、SocketCAN 报警服务、波形通知、RTC 服务和离线检查。CAN 不再接收电机控制命令。
- `ethernet_control_final_20261014/`：Windows 统一控制台及启动脚本。保留与 CAN 目录的同级布局，控制台可从此目录双击 `start_dashboard.bat` 启动。
- `can_to_fpga/`：STM32F103C8T6 的 CAN 报警接收、复位配对、蜂鸣器和状态机源码，可直接用 STM32Cube VS Code/CMake 构建。
- `board_ai_source/`：板载视觉推理源码、显示工具及当前模型启动脚本。

统一控制台的电机启停、调速、锁存与清故障经 SSH/以太网发送。点击“启动 AI 预览”时，若最新板端状态显示电机运行，会先经以太网停机，并在状态确认停止后再启动 AI。

## 当前版本索引

- FPGA：`hardware_can_rtc/motor_camera_npu_eth_can_top.v`
- 板端 CAN：`can_comm_candidate_20261018/board_service.py`
- 板端控制：`ethernet_control_final_20261014/board_control.py`
- 波形服务：`can_comm_candidate_20261018/board_wave_service_can.py`
- PC 控制台：`ethernet_control_final_20261014/desktop_dashboard.py`
- STM32 固件：`can_to_fpga/Src/main.c`、`can_to_fpga/Src/can_link.c`
- AI 推理源码：`board_ai_source/cs500_board_ai_overlay.cpp`

模型权重、训练数据、SQLite 现场事件库、虚拟环境、可执行文件、BOOT/bitstream、综合布线输出和历史日志不属于源码整理包，未复制。各原始目录的项目说明保留在 CAN 与 AI 子目录中供查阅。


2026-10-30 当前版本：CAN 使用 `0x180` 报警、`0x280` 确认，并通过
`0x190`/`0x191` 完成 STM32 复位配对；电机与板端控制统一走
SSH/以太网。新版板端 helper、agent、报警服务和 STM32 固件已经部署，
STM32 已验证配对成功，故障锁存与黑匣子波形链路已联调。
