#include "yolo_raw_decode.hpp"
#include <array>
#include <cassert>
#include <iostream>
#include <vector>

int main() {
    std::array<std::vector<float>, 3> regression;
    std::array<std::vector<float>, 3> classification;
    std::array<board_ai::RawHead, 3> heads{};
    for (unsigned scale = 0; scale < 3; ++scale) {
        const unsigned side = 80U >> scale;
        regression[scale].resize(64U * side * side, 0.0f);
        classification[scale].resize(side * side, -20.0f);
        heads[scale] = {regression[scale].data(), classification[scale].data(),
                        side, 8U << scale};
    }
    classification[0][40U * 80 + 40] = 4.0f;
    const auto boxes = board_ai::decode(heads);
    assert(boxes.size() == 1);
    assert(boxes[0].x1 == 396 && boxes[0].y1 == 186);
    assert(boxes[0].x2 == 576 && boxes[0].y2 == 366);
    assert(boxes[0].score_per_mille == 982);
    const board_ai::Candidate a{0, 0, 20, 20, 0.9f};
    const board_ai::Candidate b{0, 0, 20, 20, 0.8f};
    assert(board_ai::iou(a, b) == 1.0f);
    std::cout << "PASS: DFL, letterbox inverse, confidence and IoU\n";
}
