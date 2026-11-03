#ifndef BOARD_GPIO_H
#define BOARD_GPIO_H

void board_gpio_init(void);
void board_led_set(int on);
void board_led_toggle(void);
void board_buzzer_set(int on);

#endif
