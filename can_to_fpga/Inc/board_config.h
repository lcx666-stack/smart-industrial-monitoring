#ifndef BOARD_CONFIG_H
#define BOARD_CONFIG_H

/*
 * STM32F103C8T6 blue-pill defaults.
 *
 * CAN default pins:
 *   PA11 = CAN_RX, PA12 = CAN_TX.
 *
 * Set BOARD_USE_CAN_REMAP to 1 for:
 *   PB8 = CAN_RX, PB9 = CAN_TX.
 */
#define BOARD_USE_CAN_REMAP 0

/*
 * The buzzer output is PB12. The default assumes an active-high buzzer module.
 * Use a transistor/module for a buzzer coil; do not drive a coil from a GPIO.
 */
#define BOARD_BUZZER_ACTIVE_HIGH 1

#define BOARD_HSE_HZ 8000000UL
#define BOARD_CAN_BAUD_HZ 500000UL

#define BOARD_PAIR_RETRY_MS 1000UL
#define BOARD_STATUS_BLINK_MS 250UL

#define BOARD_ALARM_CHIRP_COUNT 4U
#define BOARD_ALARM_ON_MS 180UL
#define BOARD_ALARM_OFF_MS 160UL

#define BOARD_PAIR_CHIRP_COUNT 2U
#define BOARD_PAIR_ON_MS 80UL
#define BOARD_PAIR_OFF_MS 100UL

#endif
