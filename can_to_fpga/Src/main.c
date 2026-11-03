#include <stdbool.h>
#include <stdint.h>

#include "board_config.h"
#include "board_gpio.h"
#include "buzzer.h"
#include "can_link.h"
#include "system_stm32f103.h"

static uint16_t make_pair_nonce(uint32_t now_ms)
{
    const volatile uint32_t *uid =
        (const volatile uint32_t *) 0x1FFFF7E8UL;
    uint32_t value = uid[0] ^ uid[1] ^ uid[2] ^ now_ms;
    value ^= value >> 16U;
    value *= 0x7FEB352DUL;
    value ^= value >> 15U;
    value = (uint16_t) value;
    return (uint16_t) (value == 0U ? 1U : value);
}

static uint32_t read_u32_le(const uint8_t *data)
{
    return (uint32_t) data[0] |
           ((uint32_t) data[1] << 8U) |
           ((uint32_t) data[2] << 16U) |
           ((uint32_t) data[3] << 24U);
}

static bool pair_frame_is_valid(const can_frame_t *frame, uint16_t nonce)
{
    uint16_t reply_nonce;
    if (frame->id != CAN_PAIR_CONFIRM_ID || frame->dlc != 8U) {
        return false;
    }
    reply_nonce = (uint16_t) ((uint16_t) frame->data[5] |
                              ((uint16_t) frame->data[6] << 8U));
    return read_u32_le(frame->data) == CAN_PAIR_MAGIC &&
           frame->data[4] == CAN_PROTOCOL_VERSION &&
           reply_nonce == nonce &&
           frame->data[7] == 0U;
}

int main(void)
{
    bool paired = false;
    bool alarm_seen = false;
    uint32_t last_alarm_seq = 0U;
    uint32_t next_pair_request = 0U;
    uint32_t next_status_blink = 0U;
    uint16_t pairing_nonce;
    can_frame_t frame;

    system_clock_post_bss_init();
    systick_init_1ms();

    board_gpio_init();
    buzzer_init();
    board_led_set(0);
    (void) can_link_init();
    pairing_nonce = make_pair_nonce(millis_get());

    for (;;) {
        uint32_t now = millis_get();

        if (!paired && (int32_t) (now - next_pair_request) >= 0) {
            (void) can_link_send_pair_request(pairing_nonce);
            next_pair_request = now + BOARD_PAIR_RETRY_MS;
        }

        if (!paired && (int32_t) (now - next_status_blink) >= 0) {
            board_led_toggle();
            next_status_blink = now + BOARD_STATUS_BLINK_MS;
        }

        while (can_link_pop_frame(&frame)) {
            if (!paired && pair_frame_is_valid(&frame, pairing_nonce)) {
                paired = true;
                board_led_set(1);
                buzzer_start_pair_ok(now);
                continue;
            }

            if (paired && frame.id == CAN_ALARM_ID && frame.dlc == 8U) {
                uint32_t alarm_seq = read_u32_le(frame.data);
                (void) can_link_send_alarm_ack(alarm_seq);
                if (!alarm_seen || alarm_seq != last_alarm_seq) {
                    last_alarm_seq = alarm_seq;
                    alarm_seen = true;
                    buzzer_start_alarm(now);
                }
            }
        }

        buzzer_poll(now);
    }
}
