#ifndef MOTOR_STATUS_H
#define MOTOR_STATUS_H

#include <stdint.h>

/* ABI 1.0. Use ordered, uncached 32-bit MMIO accesses. Byte offsets below. */
#define MOTOR_STATUS_BASE          UINT64_C(0x80000000)
#define MOTOR_STATUS_MAP_SIZE      UINT32_C(0x1000)
#define MOTOR_STATUS_MAGIC         UINT32_C(0x4d535431)
#define MOTOR_STATUS_ABI_V1         UINT32_C(0x00010000)

enum motor_status_register {
    MST_ID              = 0x00,
    MST_ABI             = 0x04,
    MST_CAPTURE         = 0x08, /* Write bit 0 to atomically refresh snapshot. */
    MST_SNAPSHOT_SEQ    = 0x0c,
    MST_FLAGS           = 0x10,
    MST_SPEED_Q16_16    = 0x14,
    MST_CURRENT_MA      = 0x18, /* Signed 32-bit integer mA. */
    MST_VIBRATION1      = 0x1c, /* Signed ADC code, sign-extended to 32 bits. */
    MST_VIBRATION2      = 0x20,
    MST_VIBRATION3      = 0x24,
    MST_SAMPLE_COUNT    = 0x28,
    MST_SAMPLE_AGE      = 0x2c, /* PL clock cycles; 0xffffffff = saturated/no frame. */
    MST_FAULT_CODE      = 0x30,
    MST_TARGET_Q16_16   = 0x34,
    MST_CTRL            = 0x38,
    MST_ADC_ERROR_COUNT = 0x3c, /* Rising edges, saturates at 0xffffffff. */
    MST_TICKS_LO        = 0x40,
    MST_TICKS_HI        = 0x44,
    MST_LIVE_FLAGS      = 0x48,
    MST_LIVE_SAMPLES    = 0x4c,
    MST_LIVE_FAULT      = 0x50,
    MST_FEATURE_FLAGS   = 0x54, /* Read-only image capabilities. */
    MST_TRIAL_STATUS    = 0x58  /* Write magic to arm, 0 to stop. */
};

#define MST_CAPTURE_NOW          UINT32_C(1)
#define MST_F_SNAPSHOT_VALID     (UINT32_C(1) << 0)
#define MST_F_SAMPLE_SEEN        (UINT32_C(1) << 1)
#define MST_F_ADC_ERROR          (UINT32_C(1) << 2)
#define MST_F_ADC_ERROR_SEEN     (UINT32_C(1) << 3)
#define MST_F_MOTOR_FAULT        (UINT32_C(1) << 4)
#define MST_F_DIRECTION          (UINT32_C(1) << 5)
#define MST_F_STBY               (UINT32_C(1) << 6)
#define MST_F_AN1                (UINT32_C(1) << 7)
#define MST_F_AN2                (UINT32_C(1) << 8)
#define MST_FAULT_ENCODER        (UINT32_C(1) << 0)
#define MST_FAULT_STARTUP        (UINT32_C(1) << 1)
#define MST_FAULT_FEEDBACK       (UINT32_C(1) << 2)

#define MST_FEATURE_ADC_BYTE             (UINT32_C(1) << 0)
#define MST_FEATURE_CURRENT_IN5          (UINT32_C(1) << 1)
#define MST_FEATURE_ONE_SHOT_TRIAL       (UINT32_C(1) << 4)
/* Current telemetry exists, but PL overcurrent gating is off. */
#define MST_FEATURE_NO_CURRENT_CUTOFF    (UINT32_C(1) << 5)

#define MST_TRIAL_ARM_MAGIC     UINT32_C(0x53414645)
#define MST_TRIAL_ARMED         (UINT32_C(1) << 0)
#define MST_TRIAL_USED          (UINT32_C(1) << 1)
#define MST_TRIAL_CURRENT_TRIP  (UINT32_C(1) << 2) /* Disabled in 0x33 image. */
#define MST_TRIAL_ADC_TRIP      (UINT32_C(1) << 3)
#define MST_TRIAL_CORE_TRIP     (UINT32_C(1) << 4)
#define MST_TRIAL_CMD_TIMEOUT  (UINT32_C(1) << 5) /* Also normal 0.5 s end. */

/* A software result object, NOT a packed MMIO layout. Read each register above. */
struct motor_status_snapshot {
    uint32_t sequence;
    uint32_t flags;
    uint32_t speed_q16_16;
    int32_t current_mA;
    int32_t vibration1;
    int32_t vibration2;
    int32_t vibration3;
    uint32_t sample_count;
    uint32_t sample_age_cycles;
    uint32_t fault_code;
    uint32_t target_q16_16;
    uint32_t ctrl;
    uint32_t adc_error_count;
    uint64_t ticks;
};

#endif
