#include "board_config.h"
#include "can_link.h"
#include "stm32f103_regs.h"
#include "system_stm32f103.h"

#define CAN_RX_QUEUE_SIZE 8U

static can_frame_t rx_queue[CAN_RX_QUEUE_SIZE];
static volatile uint8_t rx_head;
static volatile uint8_t rx_tail;
static volatile can_link_stats_t stats;

static uint32_t pack_low_word(const uint8_t data[8])
{
    return (uint32_t) data[0] |
           ((uint32_t) data[1] << 8U) |
           ((uint32_t) data[2] << 16U) |
           ((uint32_t) data[3] << 24U);
}

static uint32_t pack_high_word(const uint8_t data[8])
{
    return (uint32_t) data[4] |
           ((uint32_t) data[5] << 8U) |
           ((uint32_t) data[6] << 16U) |
           ((uint32_t) data[7] << 24U);
}

static int transmit_standard(uint32_t id, const uint8_t data[8])
{
    uint32_t mailbox_mask = STM32_CAN1->TSR &
                            (CAN_TSR_TME0 | CAN_TSR_TME1 | CAN_TSR_TME2);
    stm32_can_tx_mailbox_t *mailbox;

    if ((mailbox_mask & CAN_TSR_TME0) != 0U) {
        mailbox = STM32_CAN1_TX_MAILBOX(0);
    } else if ((mailbox_mask & CAN_TSR_TME1) != 0U) {
        mailbox = STM32_CAN1_TX_MAILBOX(1);
    } else if ((mailbox_mask & CAN_TSR_TME2) != 0U) {
        mailbox = STM32_CAN1_TX_MAILBOX(2);
    } else {
        ++stats.tx_dropped;
        return 0;
    }

    mailbox->TDTR = 8U;
    mailbox->TDLR = pack_low_word(data);
    mailbox->TDHR = pack_high_word(data);
    mailbox->TIR = (id << CAN_TIR_STID_SHIFT) & 0xFFE00000UL;
    stm32_memory_barrier();
    mailbox->TIR |= CAN_TIR_TXRQ;
    return 1;
}

static int calculate_bit_timing(uint32_t pclk1, uint32_t baud,
                                uint32_t *brp_out, uint32_t *ts1_out,
                                uint32_t *ts2_out)
{
    uint32_t best_error = 0xFFFFFFFFUL;
    uint32_t best_brp = 0U;
    uint32_t best_ts1 = 0U;
    uint32_t best_ts2 = 0U;
    uint32_t brp;
    uint32_t ts1;
    uint32_t ts2;

    for (brp = 1U; brp <= 1024U; ++brp) {
        for (ts1 = 1U; ts1 <= 16U; ++ts1) {
            for (ts2 = 1U; ts2 <= 8U; ++ts2) {
                uint32_t total_tq = 1U + ts1 + ts2;
                uint32_t actual;
                uint32_t error;
                uint32_t sample_milli;
                uint32_t sample_error;
                if (total_tq > 25U) {
                    continue;
                }
                actual = pclk1 / (brp * total_tq);
                if (actual > baud) {
                    error = actual - baud;
                } else {
                    error = baud - actual;
                }
                sample_milli = ((ts1 + 1U) * 1000U) / total_tq;
                sample_error = sample_milli > 875U ?
                               sample_milli - 875U : 875U - sample_milli;
                if (error > 4000000UL) {
                    error = 0xFFFFFFFFUL;
                } else {
                    error = error * 1000UL + sample_error;
                }
                if (error < best_error) {
                    best_error = error;
                    best_brp = brp;
                    best_ts1 = ts1;
                    best_ts2 = ts2;
                }
            }
        }
    }

    if (best_brp == 0U) {
        return 0;
    }
    *brp_out = best_brp;
    *ts1_out = best_ts1;
    *ts2_out = best_ts2;
    return 1;
}

static void configure_filters(void)
{
    volatile uint32_t *filter0 = STM32_CAN1_FILTER_BANK(0);
    volatile uint32_t *filter1 = STM32_CAN1_FILTER_BANK(1);

    STM32_CAN_FMR |= 1UL;
    STM32_CAN_FA1R = 0U;
    STM32_CAN_FM1R = 0U;
    STM32_CAN_FS1R = (1UL << 0U) | (1UL << 1U);
    STM32_CAN_FFA1R = 0U;

    filter0[0] = CAN_PAIR_CONFIRM_ID << 21U;
    filter0[1] = (0x7FFUL << 21U) | (1UL << 2U) | (1UL << 1U);
    filter1[0] = CAN_ALARM_ID << 21U;
    filter1[1] = (0x7FFUL << 21U) | (1UL << 2U) | (1UL << 1U);

    STM32_CAN_FA1R = (1UL << 0U) | (1UL << 1U);
    STM32_CAN_FMR &= ~1UL;
}

bool can_link_init(void)
{
    uint32_t pclk1 = system_get_pclk1_hz();
    uint32_t brp;
    uint32_t ts1;
    uint32_t ts2;
    uint32_t limit = 200000UL;

    rx_head = 0U;
    rx_tail = 0U;
    stats.rx_frames = 0U;
    stats.rx_overflow = 0U;
    stats.tx_dropped = 0U;
    stats.bus_errors = 0U;

    if (!calculate_bit_timing(pclk1, BOARD_CAN_BAUD_HZ, &brp, &ts1, &ts2)) {
        return false;
    }

    STM32_RCC->APB2ENR |= RCC_APB2ENR_IOPAEN | RCC_APB2ENR_IOPBEN |
                          RCC_APB2ENR_AFIOEN;
    STM32_RCC->APB1ENR |= RCC_APB1ENR_CAN1EN;
    (void) STM32_RCC->APB2ENR;
    (void) STM32_RCC->APB1ENR;

#if BOARD_USE_CAN_REMAP
    STM32_AFIO->MAPR = (STM32_AFIO->MAPR & ~AFIO_MAPR_CAN_REMAP_MASK) |
                       AFIO_MAPR_CAN_REMAP_PB8_PB9;
    stm32_gpio_configure(STM32_GPIOB, 8U, GPIO_MODE_INPUT_FLOATING);
    stm32_gpio_configure(STM32_GPIOB, 9U, GPIO_MODE_AF_PP_50MHZ);
#else
    STM32_AFIO->MAPR &= ~AFIO_MAPR_CAN_REMAP_MASK;
    stm32_gpio_configure(STM32_GPIOA, 11U, GPIO_MODE_INPUT_FLOATING);
    stm32_gpio_configure(STM32_GPIOA, 12U, GPIO_MODE_AF_PP_50MHZ);
#endif

    STM32_CAN1->MCR = CAN_MCR_INRQ;
    while ((STM32_CAN1->MSR & CAN_MSR_INAK) == 0U && --limit != 0U) {
    }
    if (limit == 0U) {
        return false;
    }

    STM32_CAN1->MCR = CAN_MCR_INRQ | CAN_MCR_ABOM | CAN_MCR_AWUM |
                      CAN_MCR_NART | CAN_MCR_TXFP;
    STM32_CAN1->BTR = ((brp - 1U) & 0x3FFUL) |
                      ((ts1 - 1U) << 16U) |
                      ((ts2 - 1U) << 20U);
    STM32_CAN1->IER = CAN_IER_FMPIE0 | CAN_IER_FOVIE0 | CAN_IER_EWGIE |
                      CAN_IER_EPVIE | CAN_IER_BOFIE | CAN_IER_LECIE |
                      CAN_IER_ERRIE;
    configure_filters();

    stm32_nvic_set_priority(STM32_IRQ_USB_LP_CAN_RX0, 1U);
    stm32_nvic_set_priority(STM32_IRQ_CAN_SCE, 2U);
    stm32_nvic_enable_irq(STM32_IRQ_USB_LP_CAN_RX0);
    stm32_nvic_enable_irq(STM32_IRQ_CAN_SCE);

    STM32_CAN1->MCR &= ~CAN_MCR_INRQ;
    limit = 200000UL;
    while ((STM32_CAN1->MSR & CAN_MSR_INAK) != 0U && --limit != 0U) {
    }
    return limit != 0U;
}

bool can_link_pop_frame(can_frame_t *frame)
{
    uint8_t tail = rx_tail;
    if (frame == 0 || tail == rx_head) {
        return false;
    }

    *frame = rx_queue[tail];
    stm32_memory_barrier();
    rx_tail = (uint8_t) ((tail + 1U) % CAN_RX_QUEUE_SIZE);
    return true;
}

bool can_link_send_pair_request(uint16_t nonce)
{
    uint8_t data[8];
    data[0] = (uint8_t) (CAN_PAIR_MAGIC & 0xFFUL);
    data[1] = (uint8_t) ((CAN_PAIR_MAGIC >> 8U) & 0xFFUL);
    data[2] = (uint8_t) ((CAN_PAIR_MAGIC >> 16U) & 0xFFUL);
    data[3] = (uint8_t) ((CAN_PAIR_MAGIC >> 24U) & 0xFFUL);
    data[4] = CAN_PROTOCOL_VERSION;
    data[5] = (uint8_t) (nonce & 0xFFU);
    data[6] = (uint8_t) ((nonce >> 8U) & 0xFFU);
    data[7] = 0U;
    return transmit_standard(CAN_PAIR_REQUEST_ID, data) != 0;
}

bool can_link_send_alarm_ack(uint32_t alarm_seq)
{
    uint8_t data[8];
    data[0] = (uint8_t) (alarm_seq & 0xFFUL);
    data[1] = (uint8_t) ((alarm_seq >> 8U) & 0xFFUL);
    data[2] = (uint8_t) ((alarm_seq >> 16U) & 0xFFUL);
    data[3] = (uint8_t) ((alarm_seq >> 24U) & 0xFFUL);
    data[4] = 0x01U;
    data[5] = 0x01U;
    data[6] = 0U;
    data[7] = 0U;
    return transmit_standard(CAN_ALARM_ACK_ID, data) != 0;
}

void can_link_get_stats(can_link_stats_t *out)
{
    if (out != 0) {
        *out = stats;
    }
}

static void receive_fifo0(void)
{
    while ((STM32_CAN1->RF0R & CAN_RF0R_FMP0_MASK) != 0U) {
        stm32_can_rx_mailbox_t *mailbox = STM32_CAN1_RX_MAILBOX(0);
        uint32_t rir = mailbox->RIR;
        uint32_t rdtr = mailbox->RDTR;
        uint32_t rdlr = mailbox->RDLR;
        uint32_t rdhr = mailbox->RDHR;
        uint8_t next = (uint8_t) ((rx_head + 1U) % CAN_RX_QUEUE_SIZE);

        if (next != rx_tail &&
            (rir & (CAN_RIR_RTR | CAN_RIR_IDE)) == 0U) {
            can_frame_t *frame = &rx_queue[rx_head];
            frame->id = (rir >> CAN_RIR_STID_SHIFT) & 0x7FFUL;
            frame->dlc = (uint8_t) (rdtr & 0xFU);
            frame->data[0] = (uint8_t) rdlr;
            frame->data[1] = (uint8_t) (rdlr >> 8U);
            frame->data[2] = (uint8_t) (rdlr >> 16U);
            frame->data[3] = (uint8_t) (rdlr >> 24U);
            frame->data[4] = (uint8_t) rdhr;
            frame->data[5] = (uint8_t) (rdhr >> 8U);
            frame->data[6] = (uint8_t) (rdhr >> 16U);
            frame->data[7] = (uint8_t) (rdhr >> 24U);
            stm32_memory_barrier();
            rx_head = next;
            ++stats.rx_frames;
        } else {
            ++stats.rx_overflow;
        }

        STM32_CAN1->RF0R = CAN_RF0R_RFOM0;
    }
}

void USB_LP_CAN_RX0_IRQHandler(void)
{
    if ((STM32_CAN1->RF0R & CAN_RF0R_FOVR0) != 0U) {
        ++stats.rx_overflow;
        STM32_CAN1->RF0R &= ~CAN_RF0R_FOVR0;
    }
    if ((STM32_CAN1->RF0R & CAN_RF0R_FMP0_MASK) != 0U) {
        receive_fifo0();
    }
}

void CAN_SCE_IRQHandler(void)
{
    (void) STM32_CAN1->ESR;
    STM32_CAN1->ESR = CAN_ESR_LEC_CLEAR;
    ++stats.bus_errors;
}
