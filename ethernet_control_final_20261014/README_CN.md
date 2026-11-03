# CS500 整机控制台：以太网控制与 CAN 报警

电脑双击 `start_dashboard.bat` 打开统一控制台。电机及板端命令通过 SSH/以太网发送到 CS500；CS500 的 CAN0 只向 STM32 发布故障报警，由 STM32 驱动蜂鸣器。电脑端不再连接 USB-CAN。

CAN 线上字段见 [STM32_CAN_ALARM_PROTOCOL.md](../can_comm_candidate_20261018/STM32_CAN_ALARM_PROTOCOL.md)。当前约定为经典 CAN、500 kbit/s、报警 ID `0x180`、STM32 确认 ID `0x280`。

## 控制台功能

- 查看板端 NPU 画面、实时 ADC 波形、PL/电机状态与黑匣子故障记录。
- 通过 SSH/以太网查询状态、启动/停止 AI、启动波形/黑匣子操作。
- 通过 SSH/以太网启动电机、运行中调整目标占空比、正常停机、锁存停机和清除故障。启动、调速、锁存停机和清故障均有逐次确认；电机命令不会由识别框触发。
- AI 启动时若板端最新状态显示电机仍在运行，控制台先经以太网请求正常停机；只有命令成功且新状态确认电机停止后才启动 AI。拒绝或超时会取消 AI 启动。
- 故障波形和事件文件经 SSH/以太网读取；CAN 报警确认不影响板端黑匣子文件及以太网故障历史。

## 安全和接线

电机 VM 供电、机械固定与现场急停仍由现场人员确认。网络停止不能替代物理断电。STM32 最小系统板必须外接 CAN 收发器：CS500 J11 1 脚 GND、2 脚 CANL、3 脚 CANH；两端 CANH/CANL 对接并共地，终端电阻只放在总线两端。

## 工作区状态

STM32 固件已经烧录；新版 CAN 配对协议和 `board_service.py` 已部署到
CS500，新版 Ethernet-only `board_control_duty.py` 与配套 agent 也已部署，
`can-control-alarm` 服务正在运行。桌面控制台新增只读
`board_can_status.py`，每 0.5 秒读取服务状态、STM32 配对 nonce、CAN0
状态和收发统计，并用实时结果替代原静态“待部署”文案。清除故障锁存时，
helper 也会移除旧版遗留的 `can_stop_hold`。

板端当前版本对应 `ethernet_control_final_20261014/board_control.py`
和 `board_agent_candidate.py`；新 agent 白名单允许的电机操作仍由 helper
的 PL/故障检查把关。

`start_dashboard.bat` 保留现有 Windows Python/Pillow/Tk 启动选择。控制仍使用已配置的 SSH 22 端口；视频与波形数据沿用现有以太网链路。
