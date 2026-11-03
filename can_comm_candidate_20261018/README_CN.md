# CS500 CAN 故障报警链路

## 当前目标

CAN0 用于 CS500 与 STM32 最小系统板通信。CS500 检测到故障后，通过 CAN 报警帧通知 STM32，由 STM32 驱动蜂鸣器。电机启停、运行占空比、锁存停机、清除故障、AI 和波形操作统一经电脑到 CS500 的 SSH/以太网控制，不再接收 CAN 控制命令。

双方线上格式见 [STM32_CAN_ALARM_PROTOCOL.md](STM32_CAN_ALARM_PROTOCOL.md)
和 [PAIRING_PROTOCOL_CN.md](PAIRING_PROTOCOL_CN.md)。总线沿用现有
500 kbit/s 经典 CAN 配置，新增 `0x190` / `0x191` 复位配对；板端只对已配对
节点发布 `0x180` 报警，未确认故障约每 2 秒重发。

## 代码

- `board_service.py`：处理复位配对，配对后从黑匣子事件队列发布 `0x180`
  报警并处理 `0x280` 确认。CAN 控制帧一律忽略。
- `protocol.py`：配对、报警和确认帧的打包、解包及故障码定义。
- `transport.py`：Linux SocketCAN 传输。
- `configure_can0.sh`、`can-control-alarm.service`：板端 CAN0 配置与 systemd 服务入口。
- `board_control_can.py`：保留当前 AI、波形和守护脚本路径的板端控制 helper 源码；部署时作为以太网控制 helper 使用，不接受 CAN 控制。
- `desktop_can.py`：旧 USB-CAN 控制台已停用；新的统一控制台不加载它。
- `hardware/`：CS500 CAN0 到 J11 的引脚路由与 BOOT 构建资料。

## 物理接口

CS500 J11：1 脚 GND、2 脚 CANL、3 脚 CANH。STM32 需要 CAN 收发器，不能把 MCU 的 CAN_TX/RX 直接接到 CANH/CANL。两端 CANH、CANL 对接并共地；总线两端各保留一个 120 Ω 终端。速率为 500 kbit/s。

## 事件确认行为

报警帧 ID `0x180` 数据为 8 字节小端：事件序号 `u32`、故障码 `u8`、标志 `u8`、毫秒 `u16`。STM32 新序号鸣叫一次，重复序号只确认、不重复鸣叫。确认帧 ID `0x280` 数据为：事件序号 `u32`、确认掩码 `0x01`、接收节点 `0x01`、保留字段 `0`。收到有效确认后，板端把事件标记为已由 STM32 确认。

## 状态

已在同一工作区新增 `can_to_fpga` STM32F103C8T6 工程，并完成复位配对、
`0x180` 报警接收、蜂鸣器提示和 `0x280` 确认实现。STM32 Debug/Release
镜像均已交叉编译通过；CS500 当前运行中的服务仍需部署本次 `protocol.py`
与 `board_service.py` 改动后才能响应 `0x190` 配对请求。实板联调前继续
保持电机 12 V VM 断开，除非另行完成带电安全验收。
