#ifndef SYSTEM_STM32F103_H
#define SYSTEM_STM32F103_H

#include <stdint.h>

extern uint32_t SystemCoreClock;

void SystemInit(void);
void system_clock_post_bss_init(void);
void systick_init_1ms(void);
uint32_t millis_get(void);
uint32_t system_get_pclk1_hz(void);

#endif
