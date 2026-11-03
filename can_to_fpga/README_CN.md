# STM32 CAN 报警与复位配对

本工程面向 `STM32F103C8T6` 最小系统板，负责：

- 上电或按下复位键后主动与 CS500/FPGA 配对；
- 配对成功后才接收 `0x180` 故障报警；
- 收到新报警时驱动蜂鸣器，并向 CS500 回复 `0x280`；
- 重复报警只确认、不重复鸣叫；
- 配对和报警处理都不阻塞 CAN 接收。

电机启停、调速、清故障和黑匣子操作仍走原有以太网/SSH 控制链路。本工程
不接收任何电机控制 CAN 帧。

## 默认硬件连接

| STM32F103C8T6 | CAN 收发器 | 说明 |
|---|---|---|
| PA12 | TXD / D | CAN_TX |
| PA11 | RXD / R | CAN_RX |
| 3.3V | VCC | 推荐 3.3 V 收发器，如 SN65HVD230 |
| GND | GND | 必须与 CS500 共地 |

收发器总线侧连接 CS500 `J11`：

| CS500 J11 | 信号 |
|---|---|
| 1 | GND |
| 2 | CANL |
| 3 | CANH |

不要把 STM32 的 PA11/PA12 直接接到 CANH/CANL。总线使用 500 kbit/s
经典 CAN，只在物理总线两端保留 `120 ohm` 终端。

PB12 默认连接高电平触发的有源蜂鸣器模块，低电平关闭。蜂鸣器线圈不能直接
由 GPIO 供电，应经三极管或成品模块驱动。PC13 为板载 LED，配对前闪烁，
配对成功后常亮。

需要改用 PB8/PB9 时，在 [board_config.h](Inc/board_config.h) 中把
`BOARD_USE_CAN_REMAP` 改为 `1`，并保持收发器连接：

| 重映射引脚 | CAN 收发器 |
|---|---|
| PB9 | TXD / D |
| PB8 | RXD / R |

## 配对协议

每次 STM32 复位都会清除旧配对状态并生成新的 16 位 nonce。STM32 每 1 秒发送
一次 `0x190` 配对请求；CS500 收到后回复同一 nonce 的 `0x191`。只有收到正确
确认后，STM32 才处理 `0x180` 报警。

所有帧均为 11 位标准帧、DLC=8、小端：

| 帧 | ID | 数据格式 |
|---|---|---|
| STM32 配对请求 | `0x190` | `"CSP1", version:u8, nonce:u16, reserved:u8` |
| FPGA 配对确认 | `0x191` | `"CSP1", version:u8, 同一 nonce:u16, reserved:u8` |
| FPGA 故障报警 | `0x180` | `seq:u32, fault:u8, flags:u8, milliseconds:u16` |
| STM32 报警确认 | `0x280` | `seq:u32, mask:u8, receiver:u8, reserved:u16` |

报警确认帧实际字节为：

```text
seq[0] seq[1] seq[2] seq[3] 01 01 00 00
```

CS500 的 Python 端已在 `protocol.py` 和 `board_service.py` 增加 `0x190` /
`0x191` 处理。板端未配对时，服务不会向 STM32 发布报警。

## 编译

STM32Cube VS Code 工程可直接选择 `Debug` 或 `Release` 预设。命令行示例：

```powershell
cmake --preset Debug
cmake --build --preset Debug
```

输出位于：

```text
build/Debug/CAN_to_fpga.elf
build/Debug/CAN_to_fpga.bin
build/Debug/CAN_to_fpga.hex
```

当前工程固定按 8 MHz 外部晶振配置 72 MHz SYSCLK、36 MHz PCLK1。若最小系统板
没有可起振的外部晶振，程序会自动退回内部 8 MHz HSI，CAN 位时序按实际 PCLK1
重新计算。若晶振不是 8 MHz，必须同时修改 `BOARD_HSE_HZ` 和
`system_stm32f103.c` 中的 PLL 倍频，确保 SYSCLK 不超过 72 MHz。

## 上板验证顺序

1. 只连接 STM32、3.3 V CAN 收发器和蜂鸣器，确认 CANH/CANL/GND 无误。
2. 启动更新后的 CS500 `can-control-alarm` 服务。
3. STM32 上电或按复位键；LED 应闪烁并持续发送配对请求。
4. CS500 日志出现 `STM32 paired: nonce=...` 后，LED 常亮、蜂鸣器短鸣两次。
5. 产生一次故障报警，蜂鸣器鸣叫，CS500 日志收到 `0x280` 确认。
6. 同一条未确认报警因丢失确认而重发时，STM32 再次确认，但不重复鸣叫。

本工程已在本地完成 Debug/Release 交叉编译和配对协议离线测试。实板配对和
蜂鸣器测试仍需连接收发器、CS500 与 USB-CAN 工具后执行；未执行前不能把编译
通过视为实机验证。
