// SPDX-License-Identifier: GPL-2.0
// Batch validation of the 32-byte waveform ABI. No allocation or libc calls.
#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#define WAVE_API __declspec(dllexport)
#else
#define WAVE_API __attribute__((visibility("default")))
#endif

struct wave_stats {
    uint64_t frames, sequence_gaps, tick_mismatches, first_ticks, last_ticks;
    uint32_t last_seq;
    int32_t current_min, current_max;
    uint64_t motor_fault_frames, adc_error_frames;
    uint32_t have_frame, reserved;
    uint64_t expected_ticks;
};

static uint32_t le32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint64_t le64(const uint8_t *p)
{
    return (uint64_t)le32(p) | ((uint64_t)le32(p + 4) << 32);
}

WAVE_API uint32_t motor_wave_stats_abi(void) { return 1; }
WAVE_API size_t motor_wave_stats_size(void) { return sizeof(struct wave_stats); }

// Return 1 for a partial frame, 2 for invalid magic/flags. The valid prefix
// stays accounted for on failure, exactly as in the Python reference parser.
WAVE_API int motor_wave_stats_ingest(struct wave_stats *s,
                                    const uint8_t *data, size_t bytes)
{
    if (bytes % 32) return 1;
    for (size_t offset = 0; offset < bytes; offset += 32) {
        const uint8_t *p = data + offset;
        uint32_t seq = le32(p + 8), flags = le32(p + 12);
        uint64_t ticks = le64(p + 16);
        int32_t raw = (int32_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8));
        if (le32(p + 28) != UINT32_C(0x314d5246) || !(flags & 1)) return 2;
        if (raw & 0x8000) raw -= 65536;
        if (s->have_frame) {
            uint32_t advance = seq - s->last_seq;
            if (advance != 1) s->sequence_gaps += (uint32_t)(advance - 1);
            else if (ticks - s->last_ticks != s->expected_ticks)
                s->tick_mismatches++;
            if (raw < s->current_min) s->current_min = raw;
            if (raw > s->current_max) s->current_max = raw;
        } else {
            s->have_frame = 1;
            s->first_ticks = ticks;
            s->current_min = s->current_max = raw;
        }
        s->last_seq = seq;
        s->last_ticks = ticks;
        s->motor_fault_frames += (flags >> 1) & 1;
        s->adc_error_frames += (flags >> 2) & 1;
        s->frames++;
    }
    return 0;
}

// Black-box detector ABI is separate from the unchanged statistics ABI.
// Reasons: fault=1, ADC=2, current=4, vibration=8, sequence=16, ticks=32.
struct wave_detector {
    int64_t baseline_sum[3];
    uint64_t baseline_count, baseline_frames;
    int32_t current_limit, current_zero, vibration_threshold;
    uint32_t enabled, previous;
};
struct wave_trigger { uint32_t index, reasons; };

WAVE_API uint32_t motor_wave_scan_abi(void) { return 1; }
WAVE_API size_t motor_wave_detector_size(void) { return sizeof(struct wave_detector); }
WAVE_API size_t motor_wave_trigger_size(void) { return sizeof(struct wave_trigger); }

static int32_t signed16(const uint8_t *p)
{
    uint32_t value = (uint32_t)p[0] | ((uint32_t)p[1] << 8);
    return value & 0x8000 ? (int32_t)value - 65536 : (int32_t)value;
}

WAVE_API int motor_wave_scan_ingest(struct wave_stats *s, struct wave_detector *d,
                                   const uint8_t *data, size_t bytes,
                                   struct wave_trigger *out, size_t capacity,
                                   size_t *count)
{
    *count = 0;
    if (bytes % 32) return 1;
    if (capacity < bytes / 32 || ((d->enabled & 2) && !d->baseline_frames)) return 3;
    for (size_t offset = 0; offset < bytes; offset += 32) {
        const uint8_t *p = data + offset;
        uint32_t seq = le32(p + 8), flags = le32(p + 12), reasons = 0;
        uint32_t active = ((flags >> 1) & 1) | (((flags >> 2) & 1) << 1);
        uint64_t ticks = le64(p + 16);
        if (le32(p + 28) != UINT32_C(0x314d5246) || !(flags & 1)) return 2;
        if (s->have_frame) {
            if (seq - s->last_seq != 1) reasons |= 16;
            else if (ticks - s->last_ticks != s->expected_ticks) reasons |= 32;
        }
        if (d->enabled & 1) {
            uint32_t encoded = le32(p + 24);
            int64_t current = encoded & UINT32_C(0x80000000)
                ? (int64_t)encoded - INT64_C(4294967296) : (int64_t)encoded;
            int64_t delta = current - d->current_zero;
            if (delta >= d->current_limit || delta <= -(int64_t)d->current_limit)
                active |= 4;
        }
        if (d->enabled & 2) {
            if (d->baseline_count < d->baseline_frames) {
                for (size_t axis = 0; axis < 3; ++axis)
                    d->baseline_sum[axis] += signed16(p + 2 + axis * 2);
                ++d->baseline_count;
            } else {
                int64_t limit = (int64_t)d->vibration_threshold * (int64_t)d->baseline_frames;
                for (size_t axis = 0; axis < 3; ++axis) {
                    int64_t delta = (int64_t)signed16(p + 2 + axis * 2) *
                                    (int64_t)d->baseline_frames - d->baseline_sum[axis];
                    if (delta >= limit || delta <= -limit) active |= 8;
                }
            }
        }
        reasons |= active & ~d->previous;
        d->previous = active;
        // Shared validator accounts for every sample, not just trigger frames.
        int result = motor_wave_stats_ingest(s, p, 32);
        if (result) return result;
        if (reasons) {
            out[*count].index = (uint32_t)(offset / 32);
            out[*count].reasons = reasons;
            ++*count;
        }
    }
    return 0;
}
