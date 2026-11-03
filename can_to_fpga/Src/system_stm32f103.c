#include "board_config.h"
#include "stm32f103_regs.h"
#include "system_stm32f103.h"

uint32_t SystemCoreClock = 8000000UL;
static volatile uint32_t system_millis;

static int wait_until(volatile uint32_t *reg, uint32_t mask, uint32_t value,
                      uint32_t limit)
{
    while (limit-- != 0U) {
        if ((*reg & mask) == value) {
            return 1;
        }
    }
    return 0;
}

static void fallback_to_hsi(void)
{
    STM32_RCC->CFGR = 0U;
    STM32_RCC->CR &= ~RCC_CR_PLLON;
    STM32_FLASH->ACR = FLASH_ACR_PRFTBE;
    (void) wait_until(&STM32_RCC->CFGR, (3UL << 2U), RCC_CFGR_SWS_HSI,
                      200000UL);
}

void SystemInit(void)
{
    /*
     * Target: 8 MHz HSE * 9 = 72 MHz SYSCLK, 36 MHz PCLK1.
     * If the external crystal does not start, remain on the 8 MHz HSI clock.
     * CAN bit timing is calculated from the actual PCLK1 value later.
     */
    STM32_RCC->CR |= RCC_CR_HSION;
    (void) wait_until(&STM32_RCC->CR, RCC_CR_HSIRDY, RCC_CR_HSIRDY,
                      200000UL);

    STM32_RCC->CR |= RCC_CR_HSEON;
    if (!wait_until(&STM32_RCC->CR, RCC_CR_HSERDY, RCC_CR_HSERDY,
                    200000UL)) {
        STM32_RCC->CR &= ~RCC_CR_HSEON;
        fallback_to_hsi();
        return;
    }

    STM32_FLASH->ACR = FLASH_ACR_PRFTBE | FLASH_ACR_LATENCY_2;
    STM32_RCC->CFGR = (4UL << RCC_CFGR_PPRE1_SHIFT) |
                      RCC_CFGR_PLLSRC_HSE | RCC_CFGR_PLL_X9;
    STM32_RCC->CR |= RCC_CR_PLLON;
    if (!wait_until(&STM32_RCC->CR, RCC_CR_PLLRDY, RCC_CR_PLLRDY,
                    200000UL)) {
        fallback_to_hsi();
        return;
    }

    STM32_RCC->CFGR = (STM32_RCC->CFGR & ~3UL) | RCC_CFGR_SW_PLL;
    if (!wait_until(&STM32_RCC->CFGR, (3UL << 2U), RCC_CFGR_SWS_PLL,
                    200000UL)) {
        fallback_to_hsi();
    }
}

static uint32_t pll_multiplier(uint32_t code)
{
    if (code <= 13U) {
        return code + 2U;
    }
    return 16U;
}

static uint32_t ahb_divider(uint32_t code)
{
    static const uint16_t divider[16] = {
        1U, 1U, 1U, 1U, 1U, 1U, 1U, 1U,
        2U, 4U, 8U, 16U, 64U, 128U, 256U, 512U
    };
    return divider[code & 0xFU];
}

static uint32_t apb_divider(uint32_t code)
{
    static const uint8_t divider[8] = {1U, 1U, 1U, 1U, 2U, 4U, 8U, 16U};
    return divider[code & 0x7U];
}

static uint32_t detect_sysclk_hz(void)
{
    uint32_t sws = STM32_RCC->CFGR & (3UL << RCC_CFGR_SWS_SHIFT);
    uint32_t cfgr = STM32_RCC->CFGR;

    if (sws == RCC_CFGR_SWS_HSI) {
        return 8000000UL;
    }
    if (sws == RCC_CFGR_SWS_HSE) {
        return BOARD_HSE_HZ;
    }
    if (sws == RCC_CFGR_SWS_PLL) {
        uint32_t source;
        if ((cfgr & RCC_CFGR_PLLSRC_HSE) != 0U) {
            source = BOARD_HSE_HZ;
        } else {
            source = 8000000UL / 2UL;
        }
        return source *
               pll_multiplier((cfgr >> RCC_CFGR_PLLMUL_SHIFT) & 0xFUL);
    }
    return 8000000UL;
}

void system_clock_post_bss_init(void)
{
    SystemCoreClock = detect_sysclk_hz();
}

uint32_t system_get_pclk1_hz(void)
{
    uint32_t cfgr = STM32_RCC->CFGR;
    uint32_t hclk = detect_sysclk_hz() /
                    ahb_divider((cfgr >> RCC_CFGR_HPRE_SHIFT) & 0xFUL);
    return hclk / apb_divider((cfgr >> RCC_CFGR_PPRE1_SHIFT) & 0x7UL);
}

void systick_init_1ms(void)
{
    uint32_t reload = SystemCoreClock / 1000UL;
    if (reload == 0U) {
        reload = 1U;
    }
    STM32_SYSTICK->CTRL = 0U;
    STM32_SYSTICK->LOAD = reload - 1U;
    STM32_SYSTICK->VAL = 0U;
    STM32_SYSTICK->CTRL = SYSTICK_CTRL_CLKSOURCE |
                          SYSTICK_CTRL_TICKINT |
                          SYSTICK_CTRL_ENABLE;
}

void SysTick_Handler(void)
{
    ++system_millis;
}

uint32_t millis_get(void)
{
    return system_millis;
}
