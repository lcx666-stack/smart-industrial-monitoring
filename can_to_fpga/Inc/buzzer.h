#ifndef BUZZER_H
#define BUZZER_H

#include <stdint.h>

void buzzer_init(void);
void buzzer_start_pair_ok(uint32_t now_ms);
void buzzer_start_alarm(uint32_t now_ms);
void buzzer_cancel(void);
void buzzer_poll(uint32_t now_ms);

#endif
