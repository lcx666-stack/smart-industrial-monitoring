#pragma once

// Board-side YOLOv8 one-class raw-head decoder. No motor control or PC inference.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace board_ai {
struct RawHead {
    const float* regression = nullptr;  // [1,64,S,S], NCHW
    const float* classification = nullptr;  // [1,1,S,S], NCHW
    unsigned side = 0;
    unsigned stride = 0;
};

struct Box {
    uint16_t x1, y1, x2, y2, score_per_mille;
};

struct Candidate {
    float x1, y1, x2, y2, score;
};

// Region of the 960x540 preview frame that is fed to the 640x640 input, plus the
// letterbox that maps it. The default is the whole frame, which reproduces the
// original 1.5x-downscale path exactly.
struct Letterbox {
    unsigned roi_x = 0, roi_y = 0, roi_width = 960, roi_height = 540;
    float scale = 2.0f / 3.0f;
    unsigned pad_left = 0, pad_top = 140;
};

inline Letterbox letterbox_for(unsigned roi_x, unsigned roi_y,
                               unsigned roi_width, unsigned roi_height) {
    if (!roi_width || !roi_height || roi_width > 960 || roi_height > 540 ||
        roi_x + roi_width > 960 || roi_y + roi_height > 540)
        throw std::runtime_error("ROI outside the 960x540 preview frame");
    Letterbox box;
    box.roi_x = roi_x;
    box.roi_y = roi_y;
    box.roi_width = roi_width;
    box.roi_height = roi_height;
    box.scale = std::min(640.0f / static_cast<float>(roi_width),
                         640.0f / static_cast<float>(roi_height));
    const unsigned scaled_width =
        std::max(1U, static_cast<unsigned>(std::lround(roi_width * box.scale)));
    const unsigned scaled_height =
        std::max(1U, static_cast<unsigned>(std::lround(roi_height * box.scale)));
    box.pad_left = (640U - std::min(640U, scaled_width)) / 2U;
    box.pad_top = (640U - std::min(640U, scaled_height)) / 2U;
    return box;
}

inline float sigmoid(float x) {
    if (x >= 0) return 1.0f / (1.0f + std::exp(-x));
    const float e = std::exp(x);
    return e / (1.0f + e);
}

inline float dfl_distance(const float* base, unsigned pixels, unsigned cell) {
    float peak = -INFINITY;
    for (unsigned bin = 0; bin < 16; ++bin)
        peak = std::max(peak, base[bin * pixels + cell]);
    float sum = 0.0f, weighted = 0.0f;
    for (unsigned bin = 0; bin < 16; ++bin) {
        const float p = std::exp(base[bin * pixels + cell] - peak);
        sum += p;
        weighted += p * static_cast<float>(bin);
    }
    return weighted / sum;
}

inline float iou(const Candidate& a, const Candidate& b) {
    const float w = std::max(0.0f, std::min(a.x2, b.x2) - std::max(a.x1, b.x1));
    const float h = std::max(0.0f, std::min(a.y2, b.y2) - std::max(a.y1, b.y1));
    const float overlap = w * h;
    const float aa = std::max(0.0f, a.x2-a.x1) * std::max(0.0f, a.y2-a.y1);
    const float bb = std::max(0.0f, b.x2-b.x1) * std::max(0.0f, b.y2-b.y1);
    const float denom = aa + bb - overlap;
    return denom > 0.0f ? overlap / denom : 0.0f;
}

inline std::vector<Box> decode(const std::array<RawHead, 3>& heads,
                               const Letterbox& letterbox = Letterbox{},
                               float threshold = 0.25f) {
    std::vector<Candidate> candidates;
    candidates.reserve(512);
    for (unsigned scale = 0; scale < heads.size(); ++scale) {
        const RawHead& head = heads[scale];
        const unsigned side = 80U >> scale;
        const unsigned stride = 8U << scale;
        if (head.side != side || head.stride != stride ||
            !head.regression || !head.classification)
            throw std::runtime_error("YOLO output head layout mismatch");
        const unsigned pixels = side * side;
        for (unsigned cell = 0; cell < pixels; ++cell) {
            const float logit = head.classification[cell];
            if (!std::isfinite(logit)) throw std::runtime_error("non-finite class logit");
            const float score = sigmoid(logit);
            if (score < threshold) continue;
            float d[4];
            for (unsigned axis = 0; axis < 4; ++axis)
                d[axis] = dfl_distance(head.regression + axis * 16U * pixels,
                                       pixels, cell);
            if (!std::isfinite(d[0]) || !std::isfinite(d[1]) ||
                !std::isfinite(d[2]) || !std::isfinite(d[3]))
                throw std::runtime_error("non-finite DFL output");
            const float ax = static_cast<float>(cell % side) + 0.5f;
            const float ay = static_cast<float>(cell / side) + 0.5f;
            candidates.push_back({(ax-d[0])*stride, (ay-d[1])*stride,
                                  (ax+d[2])*stride, (ay+d[3])*stride, score});
        }
    }
    std::sort(candidates.begin(), candidates.end(),
              [](const Candidate& a, const Candidate& b) { return a.score > b.score; });
    if (candidates.size() > 300) candidates.resize(300);
    std::vector<Candidate> selected;
    std::vector<Box> boxes;
    for (const Candidate& c : candidates) {
        bool suppressed = false;
        for (const Candidate& old : selected)
            if (iou(c, old) >= 0.70f) { suppressed = true; break; }
        if (suppressed) continue;
        selected.push_back(c);
        // Undo the letterbox: 640-space -> ROI-local -> 960x540 frame pixels.
        const float inverse = 1.0f / letterbox.scale;
        const auto clamp_x = [&letterbox, inverse](float x) {
            const float frame = static_cast<float>(letterbox.roi_x) +
                                (x - static_cast<float>(letterbox.pad_left)) * inverse;
            return std::max(0.0f, std::min(960.0f, frame));
        };
        const auto clamp_y = [&letterbox, inverse](float y) {
            const float frame = static_cast<float>(letterbox.roi_y) +
                                (y - static_cast<float>(letterbox.pad_top)) * inverse;
            return std::max(0.0f, std::min(540.0f, frame));
        };
        const float x1 = clamp_x(c.x1), y1 = clamp_y(c.y1);
        const float x2 = clamp_x(c.x2), y2 = clamp_y(c.y2);
        if (x2 > x1 + 1.0f && y2 > y1 + 1.0f) {
            boxes.push_back({static_cast<uint16_t>(std::lround(x1)),
                             static_cast<uint16_t>(std::lround(y1)),
                             static_cast<uint16_t>(std::lround(x2)),
                             static_cast<uint16_t>(std::lround(y2)),
                             static_cast<uint16_t>(std::lround(c.score*1000.0f))});
            if (boxes.size() == 64) break;
        }
    }
    return boxes;
}
}  // namespace board_ai
