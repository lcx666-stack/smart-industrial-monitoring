#ifndef MOTOR_WAVE_DMA_UAPI_H
#define MOTOR_WAVE_DMA_UAPI_H

#include <linux/ioctl.h>
#include <linux/types.h>

struct motor_wave_status {
    __u32 produced_bytes;
    __u32 consumed_bytes;
    __u32 dropped_frames;
    __u32 frame_seq;
    __u32 flags;
    __u32 fifo_used;
    __u32 buffer_bytes;
    __u32 live_flags;
    __u32 adc_error_count;
    __u32 reserved;
};

#define MOTOR_WAVE_IOC_MAGIC 'W'
#define MOTOR_WAVE_IOC_START _IO(MOTOR_WAVE_IOC_MAGIC, 1)
#define MOTOR_WAVE_IOC_STOP _IO(MOTOR_WAVE_IOC_MAGIC, 2)
#define MOTOR_WAVE_IOC_STATUS _IOR(MOTOR_WAVE_IOC_MAGIC, 3, struct motor_wave_status)

#endif
