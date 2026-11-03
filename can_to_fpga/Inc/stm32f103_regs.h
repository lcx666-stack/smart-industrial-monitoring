#ifndef STM32F103_REGS_H
#define STM32F103_REGS_H

#include <stdint.h>

#define STM32_PERIPH_BASE 0x40000000UL
#define STM32_APB1_BASE   (STM32_PERIPH_BASE + 0x00000000UL)
#define STM32_APB2_BASE   (STM32_PERIPH_BASE + 0x00010000UL)
#define STM32_AHB_BASE    (STM32_PERIPH_BASE + 0x00020000UL)

typedef struct {
    volatile uint32_t CR;
    volatile uint32_t CFGR;
    volatile uint32_t CIR;
    volatile uint32_t APB2RSTR;
    volatile uint32_t APB1RSTR;
    volatile uint32_t AHBENR;
    volatile uint32_t APB2ENR;
    volatile uint32_t APB1ENR;
    volatile uint32_t BDCR;
    volatile uint32_t CSR;
} stm32_rcc_t;

typedef struct {
    volatile uint32_t ACR;
    volatile uint32_t KEYR;
    volatile uint32_t OPTKEYR;
    volatile uint32_t SR;
    volatile uint32_t CR;
    volatile uint32_t AR;
    volatile uint32_t RESERVED;
    volatile uint32_t OBR;
    volatile uint32_t WRPR;
} stm32_flash_t;

typedef struct {
    volatile uint32_t CRL;
    volatile uint32_t CRH;
    volatile uint32_t IDR;
    volatile uint32_t ODR;
    volatile uint32_t BSRR;
    volatile uint32_t BRR;
    volatile uint32_t LCKR;
} stm32_gpio_t;

typedef struct {
    volatile uint32_t EVCR;
    volatile uint32_t MAPR;
    volatile uint32_t EXTICR[4];
    volatile uint32_t RESERVED0;
    volatile uint32_t MAPR2;
} stm32_afio_t;

typedef struct {
    volatile uint32_t MCR;
    volatile uint32_t MSR;
    volatile uint32_t TSR;
    volatile uint32_t RF0R;
    volatile uint32_t RF1R;
    volatile uint32_t IER;
    volatile uint32_t ESR;
    volatile uint32_t BTR;
} stm32_can_t;

typedef struct {
    volatile uint32_t TIR;
    volatile uint32_t TDTR;
    volatile uint32_t TDLR;
    volatile uint32_t TDHR;
} stm32_can_tx_mailbox_t;

typedef struct {
    volatile uint32_t RIR;
    volatile uint32_t RDTR;
    volatile uint32_t RDLR;
    volatile uint32_t RDHR;
} stm32_can_rx_mailbox_t;

typedef struct {
    volatile uint32_t CTRL;
    volatile uint32_t LOAD;
    volatile uint32_t VAL;
    volatile uint32_t CALIB;
} stm32_systick_t;

#define STM32_RCC     ((stm32_rcc_t *) 0x40021000UL)
#define STM32_FLASH   ((stm32_flash_t *) 0x40022000UL)
#define STM32_GPIOA   ((stm32_gpio_t *) 0x40010800UL)
#define STM32_GPIOB   ((stm32_gpio_t *) 0x40010C00UL)
#define STM32_GPIOC   ((stm32_gpio_t *) 0x40011000UL)
#define STM32_AFIO    ((stm32_afio_t *) 0x40010000UL)
#define STM32_CAN1    ((stm32_can_t *) 0x40006400UL)
#define STM32_SYSTICK ((stm32_systick_t *) 0xE000E010UL)

#define STM32_CAN1_TX_MAILBOX(n) \
    ((stm32_can_tx_mailbox_t *) (0x40006400UL + 0x180UL + ((n) * 0x10UL)))
#define STM32_CAN1_RX_MAILBOX(n) \
    ((stm32_can_rx_mailbox_t *) (0x40006400UL + 0x1B0UL + ((n) * 0x10UL)))
#define STM32_CAN1_FILTER_BANK(n) \
    ((volatile uint32_t *) (0x40006400UL + 0x240UL + ((n) * 0x08UL)))
#define STM32_CAN_FMR  (*(volatile uint32_t *) (0x40006400UL + 0x200UL))
#define STM32_CAN_FM1R (*(volatile uint32_t *) (0x40006400UL + 0x204UL))
#define STM32_CAN_FS1R (*(volatile uint32_t *) (0x40006400UL + 0x20CUL))
#define STM32_CAN_FFA1R (*(volatile uint32_t *) (0x40006400UL + 0x214UL))
#define STM32_CAN_FA1R (*(volatile uint32_t *) (0x40006400UL + 0x21CUL))

#define STM32_NVIC_ISER ((volatile uint32_t *) 0xE000E100UL)
#define STM32_NVIC_ICER ((volatile uint32_t *) 0xE000E180UL)
#define STM32_NVIC_IPR  ((volatile uint8_t *) 0xE000E400UL)

#define RCC_CR_HSION       (1UL << 0)
#define RCC_CR_HSIRDY      (1UL << 1)
#define RCC_CR_HSEON       (1UL << 16)
#define RCC_CR_HSERDY      (1UL << 17)
#define RCC_CR_PLLON       (1UL << 24)
#define RCC_CR_PLLRDY      (1UL << 25)

#define RCC_CFGR_SW_HSI    (0UL << 0)
#define RCC_CFGR_SW_HSE    (1UL << 0)
#define RCC_CFGR_SW_PLL    (2UL << 0)
#define RCC_CFGR_SWS_SHIFT 2U
#define RCC_CFGR_SWS_HSI   (0UL << 2)
#define RCC_CFGR_SWS_HSE   (1UL << 2)
#define RCC_CFGR_SWS_PLL   (2UL << 2)
#define RCC_CFGR_HPRE_SHIFT 4U
#define RCC_CFGR_PPRE1_SHIFT 8U
#define RCC_CFGR_PLLSRC_HSE (1UL << 16)
#define RCC_CFGR_PLLMUL_SHIFT 18U
#define RCC_CFGR_PLL_X9    (7UL << RCC_CFGR_PLLMUL_SHIFT)

#define RCC_APB2ENR_AFIOEN (1UL << 0)
#define RCC_APB2ENR_IOPAEN (1UL << 2)
#define RCC_APB2ENR_IOPBEN (1UL << 3)
#define RCC_APB2ENR_IOPCEN (1UL << 4)
#define RCC_APB1ENR_CAN1EN (1UL << 25)

#define FLASH_ACR_LATENCY_2 (2UL << 0)
#define FLASH_ACR_PRFTBE    (1UL << 4)

#define AFIO_MAPR_CAN_REMAP_MASK (3UL << 13)
#define AFIO_MAPR_CAN_REMAP_PB8_PB9 (2UL << 13)

#define GPIO_MODE_INPUT_FLOATING 0x4UL
#define GPIO_MODE_OUTPUT_PP_2MHZ 0x2UL
#define GPIO_MODE_OUTPUT_OD_2MHZ 0x6UL
#define GPIO_MODE_AF_PP_50MHZ    0xBUL

#define CAN_MCR_INRQ    (1UL << 0)
#define CAN_MCR_SLEEP   (1UL << 1)
#define CAN_MCR_TXFP    (1UL << 2)
#define CAN_MCR_RFLM    (1UL << 3)
#define CAN_MCR_NART    (1UL << 4)
#define CAN_MCR_AWUM    (1UL << 5)
#define CAN_MCR_ABOM    (1UL << 6)
#define CAN_MCR_TTCM    (1UL << 7)
#define CAN_MCR_RESET   (1UL << 15)
#define CAN_MSR_INAK    (1UL << 0)
#define CAN_MSR_SLAK    (1UL << 1)

#define CAN_TSR_RQCP0   (1UL << 0)
#define CAN_TSR_TXOK0   (1UL << 1)
#define CAN_TSR_ALST0   (1UL << 2)
#define CAN_TSR_TERR0   (1UL << 3)
#define CAN_TSR_TME0    (1UL << 26)
#define CAN_TSR_TME1    (1UL << 27)
#define CAN_TSR_TME2    (1UL << 28)

#define CAN_RF0R_FMP0_MASK (3UL << 0)
#define CAN_RF0R_FOVR0     (1UL << 4)
#define CAN_RF0R_RFOM0     (1UL << 5)

#define CAN_IER_TMEIE   (1UL << 0)
#define CAN_IER_FMPIE0  (1UL << 1)
#define CAN_IER_FFIE0   (1UL << 2)
#define CAN_IER_FOVIE0  (1UL << 3)
#define CAN_IER_EWGIE   (1UL << 8)
#define CAN_IER_EPVIE   (1UL << 9)
#define CAN_IER_BOFIE   (1UL << 10)
#define CAN_IER_LECIE   (1UL << 11)
#define CAN_IER_ERRIE   (1UL << 15)

#define CAN_ESR_LEC_CLEAR (7UL << 4)

#define CAN_TIR_TXRQ    (1UL << 0)
#define CAN_TIR_IDE     (1UL << 2)
#define CAN_TIR_STID_SHIFT 21U
#define CAN_RIR_RTR     (1UL << 1)
#define CAN_RIR_IDE     (1UL << 2)
#define CAN_RIR_STID_SHIFT 21U

#define SYSTICK_CTRL_ENABLE    (1UL << 0)
#define SYSTICK_CTRL_TICKINT   (1UL << 1)
#define SYSTICK_CTRL_CLKSOURCE (1UL << 2)

#define STM32_IRQ_USB_LP_CAN_RX0 20U
#define STM32_IRQ_CAN_RX1        21U
#define STM32_IRQ_CAN_SCE        22U

static inline void stm32_memory_barrier(void)
{
    __asm__ volatile ("" ::: "memory");
}

static inline void stm32_nvic_enable_irq(uint32_t irq)
{
    STM32_NVIC_ISER[irq >> 5U] = 1UL << (irq & 31U);
}

static inline void stm32_nvic_set_priority(uint32_t irq, uint8_t priority)
{
    STM32_NVIC_IPR[irq] = (uint8_t) (priority << 4U);
}

static inline void stm32_gpio_write(stm32_gpio_t *gpio, uint32_t pin,
                                    int high)
{
    if (high) {
        gpio->BSRR = 1UL << pin;
    } else {
        gpio->BRR = 1UL << pin;
    }
}

static inline void stm32_gpio_toggle(stm32_gpio_t *gpio, uint32_t pin)
{
    if ((gpio->ODR & (1UL << pin)) != 0U) {
        gpio->BRR = 1UL << pin;
    } else {
        gpio->BSRR = 1UL << pin;
    }
}

static inline void stm32_gpio_configure(stm32_gpio_t *gpio, uint32_t pin,
                                        uint32_t mode)
{
    volatile uint32_t *reg = (pin < 8U) ? &gpio->CRL : &gpio->CRH;
    uint32_t shift = (pin & 7U) * 4U;
    uint32_t value = *reg;
    value &= ~(0xFUL << shift);
    value |= mode << shift;
    *reg = value;
}

#endif
