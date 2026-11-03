# STM32 复位配对扩展

原报警链路保持 `0x180` 报警、`0x280` 确认。新增：

| 方向 | CAN ID | DLC | 数据 |
|---|---:|---:|---|
| STM32 → CS500 | `0x190` | 8 | `magic:u32`, `version:u8`, `nonce:u16`, `reserved:u8` |
| CS500 → STM32 | `0x191` | 8 | `magic:u32`, `version:u8`, `nonce:u16`, `reserved:u8` |

`magic` 为小端值 `0x31505343`，线上字节是 ASCII `CSP1`；
`version=1`，`reserved=0`，`nonce` 范围为 `1..65535`。

STM32 每次复位生成新 nonce，并每 1 秒发送配对请求。CS500 原样返回
nonce。STM32 在收到正确确认前忽略报警帧。`board_service.py` 在配对前
也不会发布报警，收到新请求时替换当前配对 nonce，从而支持 STM32 再复位。

该握手用于阻止复位过程、残留报警和错误节点提前触发蜂鸣器。它不是安全认证，
适用于现有隔离的板内外设 CAN 总线。
