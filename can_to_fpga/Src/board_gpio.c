#include "board_gpio.h"
#include "board_config.h"
#include "stm32f103_regs.h"

#define BOARD_LED_PIN 13U
#define BOARD_BUZZER_PIN 12U

static void buzzer_apply(int on)
{
#if BOARD_BUZZER_ACTIVE_HIGH
    stm32_gpio_write(STM32_GPIOB, BOARD_BUZZER_PIN, on);
#else
    stm32_gpio_write(STM32_GPIOB, BOARD_BUZZER_PIN, !on);
#endif
}

void board_gpio_init(void)
{
    STM32_RCC->APB2ENR |= RCC_APB2ENR_IOPBEN | RCC_APB2ENR_IOPCEN;
    (void) STM32_RCC->APB2ENR;

    /* Keep the buzzer off while its output driver is configured. */
    buzzer_apply(0);
    stm32_gpio_configure(STM32_GPIOB, BOARD_BUZZER_PIN,
                         GPIO_MODE_OUTPUT_PP_2MHZ);

    /* The common blue-pill LED on PC13 is active low. */
    stm32_gpio_write(STM32_GPIOC, BOARD_LED_PIN, 1);
    stm32_gpio_configure(STM32_GPIOC, BOARD_LED_PIN,
                         GPIO_MODE_OUTPUT_OD_2MHZ);
}

void board_led_set(int on)
{
    stm32_gpio_write(STM32_GPIOC, BOARD_LED_PIN, !on);
}

void board_led_toggle(void)
{
    stm32_gpio_toggle(STM32_GPIOC, BOARD_LED_PIN);
}

void board_buzzer_set(int on)
{
    buzzer_apply(on);
}
