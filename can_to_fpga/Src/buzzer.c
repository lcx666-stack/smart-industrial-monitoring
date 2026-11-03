#include "board_config.h"
#include "board_gpio.h"
#include "buzzer.h"

static struct {
    uint8_t active;
    uint8_t output_on;
    uint8_t pulses_done;
    uint8_t pulse_count;
    uint16_t on_ms;
    uint16_t off_ms;
    uint32_t next_at;
} state;

static void start_pattern(uint32_t now_ms, uint8_t pulses,
                          uint16_t on_ms, uint16_t off_ms)
{
    state.active = 1U;
    state.output_on = 1U;
    state.pulses_done = 0U;
    state.pulse_count = pulses;
    state.on_ms = on_ms;
    state.off_ms = off_ms;
    state.next_at = now_ms + on_ms;
    board_buzzer_set(1);
}

void buzzer_init(void)
{
    state.active = 0U;
    state.output_on = 0U;
    board_buzzer_set(0);
}

void buzzer_start_pair_ok(uint32_t now_ms)
{
    start_pattern(now_ms, BOARD_PAIR_CHIRP_COUNT,
                  BOARD_PAIR_ON_MS, BOARD_PAIR_OFF_MS);
}

void buzzer_start_alarm(uint32_t now_ms)
{
    start_pattern(now_ms, BOARD_ALARM_CHIRP_COUNT,
                  BOARD_ALARM_ON_MS, BOARD_ALARM_OFF_MS);
}

void buzzer_cancel(void)
{
    state.active = 0U;
    state.output_on = 0U;
    board_buzzer_set(0);
}

void buzzer_poll(uint32_t now_ms)
{
    if (!state.active || (int32_t) (now_ms - state.next_at) < 0) {
        return;
    }

    if (state.output_on) {
        board_buzzer_set(0);
        state.output_on = 0U;
        ++state.pulses_done;
        if (state.pulses_done >= state.pulse_count) {
            state.active = 0U;
            state.next_at = now_ms;
        } else {
            state.next_at = now_ms + state.off_ms;
        }
    } else {
        board_buzzer_set(1);
        state.output_on = 1U;
        state.next_at = now_ms + state.on_ms;
    }
}
