#ifndef CAN_LINK_H
#define CAN_LINK_H

#include <stdbool.h>
#include <stdint.h>

#define CAN_PAIR_REQUEST_ID  0x190U
#define CAN_PAIR_CONFIRM_ID  0x191U
#define CAN_ALARM_ID         0x180U
#define CAN_ALARM_ACK_ID     0x280U
#define CAN_PAIR_MAGIC       0x31505343UL
#define CAN_PROTOCOL_VERSION 1U

typedef struct {
    uint32_t id;
    uint8_t dlc;
    uint8_t data[8];
} can_frame_t;

typedef struct {
    uint32_t rx_frames;
    uint32_t rx_overflow;
    uint32_t tx_dropped;
    uint32_t bus_errors;
} can_link_stats_t;

bool can_link_init(void);
bool can_link_pop_frame(can_frame_t *frame);
bool can_link_send_pair_request(uint16_t nonce);
bool can_link_send_alarm_ack(uint32_t alarm_seq);
void can_link_get_stats(can_link_stats_t *stats);

#endif
