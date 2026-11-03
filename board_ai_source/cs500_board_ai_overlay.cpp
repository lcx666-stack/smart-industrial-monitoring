// CS500 -> board Arm NN Hybrid inference -> RGB and board-originated boxes.
// Reuse the board-tested one-shot DMA and NEON/AWB path. No motor writes.
#define main cs500_preview_legacy_main
#include "../ethernet_isp_candidate_20261013/cs500_tcp_preview.cpp"
#undef main

#include "yolo_raw_decode.hpp"
#include <armnn/ArmNN.hpp>
#include <armnn/IRuntime.hpp>
#include <armnn/Tensor.hpp>
#include <armnnOnnxParser/IOnnxParser.hpp>
#include <algorithm>
#include <array>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <sstream>

namespace board_ai {
constexpr unsigned kInputSide = 640;
constexpr size_t kInputElements = 3U * kInputSide * kInputSide;

bool supported_tensor_type(armnn::DataType type) {
    return type == armnn::DataType::Float32 ||
           type == armnn::DataType::Float16 ||
           type == armnn::DataType::QAsymmU8 ||
           type == armnn::DataType::QAsymmS8 ||
           type == armnn::DataType::QSymmS8 ||
           type == armnn::DataType::QSymmS16;
}

float half_to_float(uint16_t bits) {
    const unsigned sign = (bits >> 15) & 1U;
    const unsigned exponent = (bits >> 10) & 31U;
    const unsigned fraction = bits & 1023U;
    float value;
    if (exponent == 0) value = std::ldexp(static_cast<float>(fraction), -24);
    else if (exponent == 31) value = fraction ? NAN : INFINITY;
    else value = std::ldexp(static_cast<float>(1024U + fraction),
                            static_cast<int>(exponent) - 25);
    return sign ? -value : value;
}

struct HeadBinding {
    armnn::DataType type = armnn::DataType::Float32;
    float scale = 1.0f;
    int offset = 0;
    const void* raw = nullptr;
    unsigned channels = 0;
    unsigned side = 0;
    bool nhwc = false;
    std::vector<float> decoded;
};

class NpuBuffer {
public:
    explicit NpuBuffer(size_t bytes) : buffer_(static_cast<uint32_t>(bytes)) {
        if (!bytes || bytes > UINT32_MAX || cma_mem_alloc(&buffer_) != 0 ||
            !buffer_.virt_addr || !buffer_.phys_addr)
            throw std::runtime_error("NPU tensor CMA allocation failed");
        allocated_ = true;
    }
    ~NpuBuffer() { if (allocated_) cma_mem_free(&buffer_); }
    NpuBuffer(const NpuBuffer&) = delete;
    NpuBuffer& operator=(const NpuBuffer&) = delete;
    void* data() const { return buffer_.virt_addr; }
    void to_device() const {
        if (cma_mem_sync_for_device(buffer_.phys_addr, buffer_.size) != 0)
            throw std::runtime_error("NPU tensor device cache sync failed");
    }
    void to_cpu() const {
        if (cma_mem_sync_for_cpu(buffer_.phys_addr, buffer_.size) != 0)
            throw std::runtime_error("NPU tensor CPU cache sync failed");
    }
private:
    cma_buffer_t buffer_;
    bool allocated_ = false;
};

[[noreturn]] void retain_npu_buffers(const char* reason) {
    std::cerr << "FAIL: " << reason
              << "; NPU/CMA retained. Power off board before retrying.\n"
              << std::flush;
    std::signal(SIGINT, SIG_IGN);
    std::signal(SIGTERM, SIG_IGN);
    std::signal(SIGHUP, SIG_IGN);
    for (;;) ::sleep(3600);
}

armnn::IRuntimePtr make_runtime() {
    armnn::IRuntime::CreationOptions options;
    options.m_CustomAllocatorMap["CpuAcc"] =
        options.m_CustomAllocatorMap["CpuRef"] =
            std::shared_ptr<armnn::ICustomAllocator>(new armnn::CmaAllocator);
    return armnn::IRuntime::Create(options);
}

class NpuRunner {
public:
    explicit NpuRunner(const std::string& model, const Letterbox& letterbox = Letterbox{})
        : runtime_(make_runtime()), parser_(armnnOnnxParser::IOnnxParser::Create()),
          letterbox_(letterbox) {
        auto network = parser_->CreateNetworkFromBinaryFile(model.c_str());
        if (!network) throw std::runtime_error("fan ONNX parse failed");
        std::cout << "BOARD_AI roi=" << letterbox_.roi_x << "," << letterbox_.roi_y
                  << "," << letterbox_.roi_width << "," << letterbox_.roi_height
                  << " scale=" << letterbox_.scale
                  << " pad=" << letterbox_.pad_left << "," << letterbox_.pad_top
                  << "\n" << std::flush;
        armnn::OptimizerOptionsOpaque options;
        options.SetImportEnabled(true);
        options.SetExportEnabled(true);
        auto optimized = armnn::Optimize(
            *network, {"Alnpu", "CpuAcc", "CpuRef"}, runtime_->GetDeviceSpec(), options);
        if (!optimized) throw std::runtime_error("Hybrid model optimization failed");
        std::ostringstream placement;
        if (optimized->SerializeToDot(placement) != armnn::Status::Success ||
            placement.str().find("Alnpu") == std::string::npos)
            throw std::runtime_error("no Alnpu placement found; CPU-only run refused");
        armnn::INetworkProperties properties(false, armnn::MemorySource::Malloc,
                                             armnn::MemorySource::Malloc);
        std::string error;
        if (runtime_->LoadNetwork(network_id_, std::move(optimized), error,
                                  properties) != armnn::Status::Success)
            throw std::runtime_error("Hybrid LoadNetwork failed: " + error);
        loaded_ = true;

        const auto input_names = parser_->GetInputTensorNames();
        if (input_names.size() != 1 || input_names[0] != "images")
            throw std::runtime_error("fan model input name mismatch");
        auto binding = parser_->GetNetworkInputBindingInfo(input_names[0]);
        armnn::TensorInfo info = binding.second;
        const auto& shape = info.GetShape();
        if (shape.GetNumDimensions() != 4 || shape[0] != 1 ||
            info.GetNumElements() != kInputElements ||
            !supported_tensor_type(info.GetDataType()))
            throw std::runtime_error("fan model input shape/type mismatch");
        if (shape[1] == 3 && shape[2] == 640 && shape[3] == 640)
            input_nhwc_ = false;
        else if (shape[1] == 640 && shape[2] == 640 && shape[3] == 3)
            input_nhwc_ = true;
        else throw std::runtime_error("fan model input layout mismatch");
        input_type_ = info.GetDataType();
        if (input_type_ != armnn::DataType::Float32 &&
            input_type_ != armnn::DataType::QAsymmU8)
            throw std::runtime_error("unsupported fan input tensor type");
        if (input_type_ == armnn::DataType::QAsymmU8) {
            if (info.HasMultipleQuantizationScales() ||
                !std::isfinite(info.GetQuantizationScale()) ||
                info.GetQuantizationScale() <= 0.0f)
                throw std::runtime_error("fan input quantization invalid");
            input_scale_ = info.GetQuantizationScale();
            input_offset_ = info.GetQuantizationOffset();
        }
        const char* reference_env = std::getenv("BOARD_AI_REFERENCE_PREPROCESS");
        reference_preprocess_ = reference_env && *reference_env &&
                                std::string(reference_env) != "0";
        const char* hash_env = std::getenv("BOARD_AI_DUMP_INPUT_HASH");
        dump_input_hash_ = hash_env && *hash_env && std::string(hash_env) != "0";
        if (input_type_ == armnn::DataType::QAsymmU8) {
            auto quantize = [this](float normalized) -> uint8_t {
                return static_cast<uint8_t>(std::max(0L, std::min(255L,
                    std::lround(normalized / input_scale_ + input_offset_))));
            };
            for (unsigned value = 0; value < 256; ++value)
                input_lut_[value] = quantize(static_cast<float>(value) / 255.0f);
            input_lut_identity_ = true;
            for (unsigned value = 0; value < 256; ++value) {
                if (input_lut_[value] != value) {
                    input_lut_identity_ = false;
                    break;
                }
            }
        }
        const unsigned scaled_width = std::max(1U, static_cast<unsigned>(
            std::lround(letterbox_.roi_width * letterbox_.scale)));
        const unsigned scaled_height = std::max(1U, static_cast<unsigned>(
            std::lround(letterbox_.roi_height * letterbox_.scale)));
        fast_1to1_ = input_type_ == armnn::DataType::QAsymmU8 &&
                     !reference_preprocess_ &&
                     scaled_width == letterbox_.roi_width &&
                     scaled_height == letterbox_.roi_height;
        std::cout << "BOARD_AI input type=" << static_cast<int>(input_type_)
                  << " bytes=" << info.GetNumBytes()
                  << " nhwc=" << input_nhwc_ << " scale=" << input_scale_
                  << " offset=" << input_offset_ << '\n' << std::flush;
        input_.reset(new NpuBuffer(info.GetNumBytes()));
        if (input_type_ == armnn::DataType::QAsymmU8) {
            uint8_t* destination = static_cast<uint8_t*>(input_->data());
            std::fill(destination, destination + kInputElements, input_lut_[114]);
        } else {
            float* destination = static_cast<float*>(input_->data());
            std::fill(destination, destination + kInputElements, 114.0f / 255.0f);
        }
        std::cout << "BOARD_AI preprocess="
                  << (fast_1to1_ ? "1to1-fast" : "bilinear-reference")
                  << '\n' << std::flush;
        info.SetConstant(true);
        inputs_.push_back({binding.first, armnn::ConstTensor(info, input_->data())});

        const auto output_names = parser_->GetOutputTensorNames();
        if (output_names.size() != 6)
            throw std::runtime_error("expected exactly six YOLO raw heads");
        std::array<bool, 6> seen{};
        for (const std::string& name : output_names) {
            const bool regression = name.find("/cv2.") != std::string::npos;
            const bool classification = name.find("/cv3.") != std::string::npos;
            if (regression == classification) throw std::runtime_error("unknown YOLO head name");
            unsigned scale = 3;
            for (unsigned i = 0; i < 3; ++i) {
                const std::string key = regression ? "/cv2." : "/cv3.";
                if (name.find(key + std::to_string(i) + "/") != std::string::npos)
                    scale = i;
            }
            if (scale >= 3) throw std::runtime_error("unknown YOLO scale");
            const unsigned slot = 2 * scale + (classification ? 1 : 0);
            if (seen[slot]) throw std::runtime_error("duplicate YOLO output head");
            seen[slot] = true;
            auto output = parser_->GetNetworkOutputBindingInfo(name);
            const armnn::TensorInfo& tensor = output.second;
            const auto& dims = tensor.GetShape();
            const unsigned side = 80U >> scale;
            const unsigned channels = regression ? 64U : 1U;
            if (dims.GetNumDimensions() != 4 || dims[0] != 1 ||
                tensor.GetNumElements() != channels * side * side ||
                !supported_tensor_type(tensor.GetDataType()))
                throw std::runtime_error("YOLO output shape/type mismatch");
            bool nhwc = false;
            if (dims[1] == channels && dims[2] == side && dims[3] == side)
                nhwc = false;
            else if (dims[1] == side && dims[2] == side && dims[3] == channels)
                nhwc = true;
            else throw std::runtime_error("YOLO output layout mismatch");
            if (tensor.GetDataType() != armnn::DataType::Float32 &&
                tensor.GetDataType() != armnn::DataType::Float16 &&
                (tensor.HasMultipleQuantizationScales() ||
                 !std::isfinite(tensor.GetQuantizationScale()) ||
                 tensor.GetQuantizationScale() <= 0.0f))
                throw std::runtime_error("YOLO output quantization invalid");
            std::unique_ptr<NpuBuffer> buffer(new NpuBuffer(tensor.GetNumBytes()));
            HeadBinding& head = heads_[slot];
            head.type = tensor.GetDataType();
            head.scale = (tensor.GetDataType() == armnn::DataType::Float32 ||
                          tensor.GetDataType() == armnn::DataType::Float16)
                             ? 1.0f : tensor.GetQuantizationScale();
            head.offset = (tensor.GetDataType() == armnn::DataType::Float32 ||
                           tensor.GetDataType() == armnn::DataType::Float16)
                              ? 0 : tensor.GetQuantizationOffset();
            head.raw = buffer->data();
            head.channels = channels;
            head.side = side;
            head.nhwc = nhwc;
            head.decoded.resize(tensor.GetNumElements());
            std::cout << "BOARD_AI head=" << slot
                      << " type=" << static_cast<int>(head.type)
                      << " bytes=" << tensor.GetNumBytes()
                      << " nhwc=" << nhwc << " scale=" << head.scale
                      << " offset=" << head.offset << '\n' << std::flush;
            outputs_.push_back({output.first, armnn::Tensor(tensor, buffer->data())});
            output_buffers_.push_back(std::move(buffer));
        }
        if (!std::all_of(seen.begin(), seen.end(), [](bool value){ return value; }))
            throw std::runtime_error("missing YOLO output head");
        std::cout << "BOARD_AI model loaded; Alnpu placement present; 6 raw heads\n"
                  << std::flush;
    }

    ~NpuRunner() { if (loaded_) runtime_->UnloadNetwork(network_id_); }

    std::vector<Box> infer(const std::vector<uint8_t>& rgb, double& elapsed_ms) {
        if (rgb.size() != kHalfBytes) throw std::runtime_error("preview RGB size mismatch");
        float* float_dst = static_cast<float*>(input_->data());
        uint8_t* byte_dst = static_cast<uint8_t*>(input_->data());
        const bool quantized_input = input_type_ == armnn::DataType::QAsymmU8;
        auto quantize_input = [&](float normalized) -> uint8_t {
            return static_cast<uint8_t>(std::max(0L, std::min(255L,
                std::lround(normalized / input_scale_ + input_offset_))));
        };
        constexpr unsigned plane = kInputSide * kInputSide;
        // OpenCV INTER_LINEAR-style half-pixel mapping of the ROI into the input.
        const unsigned scaled_width = std::max(1U, static_cast<unsigned>(
            std::lround(letterbox_.roi_width * letterbox_.scale)));
        const unsigned scaled_height = std::max(1U, static_cast<unsigned>(
            std::lround(letterbox_.roi_height * letterbox_.scale)));
        if (fast_1to1_) {
            const size_t source_stride = size_t(kHalfWidth) * 3U;
            const size_t source_base = (size_t(letterbox_.roi_y) * kHalfWidth +
                                        letterbox_.roi_x) * 3U;
            for (unsigned y = 0; y < scaled_height; ++y) {
                const uint8_t* source = rgb.data() + source_base +
                                        size_t(y) * source_stride;
                const unsigned destination_row =
                    (y + letterbox_.pad_top) * kInputSide + letterbox_.pad_left;
                if (input_nhwc_) {
                    uint8_t* destination = byte_dst + size_t(destination_row) * 3U;
                    if (input_lut_identity_) {
                        std::memcpy(destination, source, size_t(scaled_width) * 3U);
                    } else {
                        for (unsigned x = 0; x < scaled_width * 3U; ++x)
                            destination[x] = input_lut_[source[x]];
                    }
                } else {
                    uint8_t* red = byte_dst + destination_row;
                    uint8_t* green = byte_dst + plane + destination_row;
                    uint8_t* blue = byte_dst + 2U * plane + destination_row;
                    if (input_lut_identity_) {
                        for (unsigned x = 0; x < scaled_width; ++x) {
                            red[x] = source[3U * x];
                            green[x] = source[3U * x + 1U];
                            blue[x] = source[3U * x + 2U];
                        }
                    } else {
                        for (unsigned x = 0; x < scaled_width; ++x) {
                            red[x] = input_lut_[source[3U * x]];
                            green[x] = input_lut_[source[3U * x + 1U]];
                            blue[x] = input_lut_[source[3U * x + 2U]];
                        }
                    }
                }
            }
        } else {
        const float inverse_scale = 1.0f / letterbox_.scale;
        for (unsigned y = 0; y < scaled_height; ++y) {
            const float yf = (static_cast<float>(y) + 0.5f) * inverse_scale - 0.5f;
            const unsigned y0 = std::min(
                static_cast<unsigned>(std::max(0.0f, std::floor(yf))),
                letterbox_.roi_height - 1);
            const unsigned y1 = std::min(y0 + 1, letterbox_.roi_height - 1);
            const float wy = std::max(0.0f, yf - static_cast<float>(y0));
            const size_t row0 = size_t(letterbox_.roi_y + y0) * kHalfWidth + letterbox_.roi_x;
            const size_t row1 = size_t(letterbox_.roi_y + y1) * kHalfWidth + letterbox_.roi_x;
            for (unsigned x = 0; x < scaled_width; ++x) {
                const float xf = (static_cast<float>(x) + 0.5f) * inverse_scale - 0.5f;
                const unsigned x0 = std::min(
                    static_cast<unsigned>(std::max(0.0f, std::floor(xf))),
                    letterbox_.roi_width - 1);
                const unsigned x1 = std::min(x0 + 1, letterbox_.roi_width - 1);
                const float wx = std::max(0.0f, xf - static_cast<float>(x0));
                const size_t a = (row0 + x0) * 3;
                const size_t b = (row0 + x1) * 3;
                const size_t c = (row1 + x0) * 3;
                const size_t d = (row1 + x1) * 3;
                const unsigned index = (y + letterbox_.pad_top) * kInputSide +
                                       (x + letterbox_.pad_left);
                for (unsigned color = 0; color < 3; ++color) {
                    const float top = rgb[a+color]*(1-wx) + rgb[b+color]*wx;
                    const float bottom = rgb[c+color]*(1-wx) + rgb[d+color]*wx;
                    const float normalized = (top*(1-wy) + bottom*wy) / 255.0f;
                    const size_t target = input_nhwc_ ? size_t(index)*3 + color
                                                      : size_t(color)*plane + index;
                    if (quantized_input) byte_dst[target] = quantize_input(normalized);
                    else float_dst[target] = normalized;
                }
            }
        }
        }
        if (dump_input_hash_) {
            const uint8_t* bytes = static_cast<const uint8_t*>(input_->data());
            const size_t count = quantized_input
                ? kInputElements : kInputElements * sizeof(float);
            uint64_t hash = 1469598103934665603ULL;
            for (size_t i = 0; i < count; ++i) {
                hash ^= bytes[i];
                hash *= 1099511628211ULL;
            }
            std::cout << "BOARD_AI input_hash=" << std::hex << hash
                      << std::dec << '\n' << std::flush;
        }
        input_->to_device();
        const auto begin = std::chrono::steady_clock::now();
        if (runtime_->EnqueueWorkload(network_id_, inputs_, outputs_) !=
            armnn::Status::Success)
            retain_npu_buffers("Hybrid EnqueueWorkload failed");
        elapsed_ms = std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - begin).count();
        for (const auto& buffer : output_buffers_) buffer->to_cpu();
        for (HeadBinding& head : heads_) {
            const size_t plane_size = size_t(head.side) * head.side;
            for (unsigned channel = 0; channel < head.channels; ++channel) {
                for (size_t pixel = 0; pixel < plane_size; ++pixel) {
                    const size_t target = size_t(channel) * plane_size + pixel;
                    const size_t source = head.nhwc
                        ? pixel * head.channels + channel : target;
                    float value = 0.0f;
                    switch (head.type) {
                    case armnn::DataType::Float32:
                        value = static_cast<const float*>(head.raw)[source];
                        break;
                    case armnn::DataType::Float16:
                        value = half_to_float(static_cast<const uint16_t*>(head.raw)[source]);
                        break;
                    case armnn::DataType::QAsymmU8:
                        value = (int(static_cast<const uint8_t*>(head.raw)[source]) -
                                 head.offset) * head.scale;
                        break;
                    case armnn::DataType::QAsymmS8:
                    case armnn::DataType::QSymmS8:
                        value = (int(static_cast<const int8_t*>(head.raw)[source]) -
                                 head.offset) * head.scale;
                        break;
                    case armnn::DataType::QSymmS16:
                        value = (int(static_cast<const int16_t*>(head.raw)[source]) -
                                 head.offset) * head.scale;
                        break;
                    default: throw std::runtime_error("unsupported YOLO output type");
                    }
                    head.decoded[target] = value;
                }
            }
        }
        std::array<RawHead, 3> heads{};
        for (unsigned scale = 0; scale < 3; ++scale) {
            heads[scale] = {heads_[2*scale].decoded.data(),
                            heads_[2*scale+1].decoded.data(),
                            80U >> scale, 8U << scale};
        }
        return decode(heads, letterbox_);
    }

    // Diagnostic only: print what the NPU actually produced for the input it got.
    // Used by the offline image probe; it never runs during the camera preview.
    void report_heads(std::ostream& out) const {
        static const char* kKind[6] = {"reg", "cls", "reg", "cls", "reg", "cls"};
        out << "PROBE input_type=" << static_cast<int>(input_type_)
            << " scale=" << input_scale_ << " offset=" << input_offset_
            << " nhwc=" << input_nhwc_ << "\n";
        for (unsigned slot = 0; slot < 6; ++slot) {
            const HeadBinding& head = heads_[slot];
            float low = INFINITY, high = -INFINITY;
            double sum = 0.0;
            for (float value : head.decoded) {
                low = std::min(low, value);
                high = std::max(high, value);
                sum += value;
            }
            const unsigned element_bytes =
                head.type == armnn::DataType::Float32 ? 4U
                : (head.type == armnn::DataType::Float16 ||
                   head.type == armnn::DataType::QSymmS16) ? 2U : 1U;
            uint64_t byte_sum = 0;
            const uint8_t* raw = static_cast<const uint8_t*>(head.raw);
            for (size_t i = 0; i < head.decoded.size() * element_bytes; ++i)
                byte_sum += raw[i];
            out << "PROBE head=" << slot << " " << kKind[slot]
                << " type=" << static_cast<int>(head.type)
                << " side=" << head.side
                << " scale=" << head.scale << " offset=" << head.offset
                << " min=" << low << " max=" << high
                << " mean=" << (head.decoded.empty() ? 0.0
                                 : sum / static_cast<double>(head.decoded.size()))
                << " byte_sum=" << byte_sum << "\n";
        }
        const float thresholds[3] = {0.10f, 0.25f, 0.50f};
        for (unsigned slot = 1; slot < 6; slot += 2) {
            const HeadBinding& head = heads_[slot];
            float best = -INFINITY;
            size_t best_cell = 0, counts[3] = {0, 0, 0};
            for (size_t cell = 0; cell < head.decoded.size(); ++cell) {
                const float logit = head.decoded[cell];
                if (logit > best) { best = logit; best_cell = cell; }
                const float score = sigmoid(logit);
                for (unsigned i = 0; i < 3; ++i)
                    if (score >= thresholds[i]) ++counts[i];
            }
            out << "PROBE cls_head=" << slot
                << " max_logit=" << best
                << " max_score=" << sigmoid(best)
                << " cells_ge_0.10=" << counts[0]
                << " cells_ge_0.25=" << counts[1]
                << " cells_ge_0.50=" << counts[2]
                << " best_cell=" << best_cell
                << " best_x=" << (head.side ? best_cell % head.side : 0)
                << " best_y=" << (head.side ? best_cell / head.side : 0) << "\n";
            const HeadBinding& regression = heads_[slot - 1];
            const unsigned pixels = regression.side * regression.side;
            if (pixels && regression.decoded.size() == size_t(64) * pixels) {
                out << "PROBE dfl_head=" << (slot - 1) << " at_best_cell";
                for (unsigned axis = 0; axis < 4; ++axis) {
                    const float* base =
                        regression.decoded.data() + size_t(axis) * 16U * pixels;
                    float peak = -INFINITY;
                    for (unsigned bin = 0; bin < 16; ++bin)
                        peak = std::max(peak, base[bin * pixels + best_cell]);
                    float total = 0.0f, weighted = 0.0f;
                    for (unsigned bin = 0; bin < 16; ++bin) {
                        const float probability = std::exp(base[bin * pixels + best_cell] - peak);
                        total += probability;
                        weighted += probability * static_cast<float>(bin);
                    }
                    out << " d" << axis << "=" << (total > 0.0f ? weighted / total : -1.0f);
                }
                out << "\n";
            }
        }
        out << std::flush;
    }
private:
    armnn::IRuntimePtr runtime_;
    armnnOnnxParser::IOnnxParserPtr parser_;
    armnn::NetworkId network_id_ = 0;
    bool loaded_ = false;
    armnn::DataType input_type_ = armnn::DataType::Float32;
    float input_scale_ = 1.0f;
    int input_offset_ = 0;
    bool input_nhwc_ = false;
    Letterbox letterbox_{};
    bool reference_preprocess_ = false;
    bool fast_1to1_ = false;
    bool dump_input_hash_ = false;
    bool input_lut_identity_ = false;
    std::array<uint8_t, 256> input_lut_{};
    std::unique_ptr<NpuBuffer> input_;
    std::vector<std::unique_ptr<NpuBuffer>> output_buffers_;
    std::array<HeadBinding, 6> heads_{};
    armnn::InputTensors inputs_;
    armnn::OutputTensors outputs_;
};

int run_overlay(const std::string& address, const std::string& model,
                unsigned infer_every, const Letterbox& letterbox = Letterbox{}) {
    Fd server(::socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0));
    const int yes = 1;
    if (::setsockopt(server.get(), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes)) != 0)
        throw std::runtime_error("TCP reuseaddr failed");
    sockaddr_in local{};
    local.sin_family = AF_INET;
    local.sin_port = htons(5000);
    if (::inet_pton(AF_INET, address.c_str(), &local.sin_addr) != 1)
        throw std::runtime_error("invalid bind IPv4 address");
    if (::bind(server.get(), reinterpret_cast<sockaddr*>(&local), sizeof(local)) != 0 ||
        ::listen(server.get(), 1) != 0)
        throw std::runtime_error("TCP server setup failed");
    std::cout << "BOARD_AI waiting at " << address << ":5000; infer_every="
              << infer_every << "; motor 12 V must stay disconnected\n" << std::flush;
    while (!gStop) {
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(server.get(), &readfds);
        timeval timeout{0, 200000};
        const int ready = ::select(server.get()+1, &readfds, nullptr, nullptr, &timeout);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0) throw std::runtime_error("TCP accept failed");
        if (!ready) continue;
        Fd client(::accept(server.get(), nullptr, nullptr));
        timeval send_timeout{3, 0};
        if (::setsockopt(client.get(), SOL_SOCKET, SO_SNDTIMEO,
                         &send_timeout, sizeof(send_timeout)) != 0)
            throw std::runtime_error("TCP send timeout setup failed");
        CameraRegisters regs;
        check_camera_ready(regs);
        CmaSession cma;
        NpuRunner npu(model, letterbox);
        CmaFrame frame;
        std::vector<uint8_t> rgb(kHalfBytes);
        IspColorPipeline isp;
        IspColorPipeline::Stats stats{0, 256, 256, 0, false};
        const uint32_t guard_before = regs.read(kGuardFaults);
        uint32_t frame_sequence = 0, infer_sequence = 0;
        std::vector<Box> boxes;
        double infer_ms = 0.0;
        const auto report_begin = std::chrono::steady_clock::now();
        std::cout << "BOARD_AI client connected; camera and Hybrid active\n" << std::flush;
        try {
            while (!gStop) {
                capture(regs, frame);
                if (regs.read(kGuardFaults) != guard_before)
                    retain_dma_buffer("DDR guard changed", regs.read(kCameraStatus));
                downsample_2x2_bgrx_to_rgb<true>(frame.data(), rgb, &isp, &stats);
                ++frame_sequence;
                if ((frame_sequence - 1) % infer_every == 0) {
                    boxes = npu.infer(rgb, infer_ms);
                    infer_sequence = frame_sequence;
                }
                uint8_t header[22] = {'C','S','N','B'};
                put_le32(header+4, frame_sequence);
                put_le16(header+8, kHalfWidth);
                put_le16(header+10, kHalfHeight);
                put_le32(header+12, kHalfBytes);
                put_le32(header+16, infer_sequence);
                put_le16(header+20, static_cast<uint16_t>(boxes.size()));
                send_all(client.get(), header, sizeof(header));
                send_all(client.get(), rgb.data(), rgb.size());
                for (const Box& box : boxes) {
                    uint8_t record[10];
                    put_le16(record, box.x1);
                    put_le16(record+2, box.y1);
                    put_le16(record+4, box.x2);
                    put_le16(record+6, box.y2);
                    put_le16(record+8, box.score_per_mille);
                    send_all(client.get(), record, sizeof(record));
                }
                if (frame_sequence % 30 == 0) {
                    const double seconds = std::chrono::duration<double>(
                        std::chrono::steady_clock::now()-report_begin).count();
                    std::cout << "BOARD_AI frames=" << frame_sequence
                              << " average_fps=" << frame_sequence/seconds
                              << " infer_ms=" << infer_ms
                              << " boxes=" << boxes.size()
                              << " guard_faults=0x" << std::hex << regs.read(kGuardFaults)
                              << std::dec << "\n" << std::flush;
                }
            }
        } catch (const TcpDisconnect& error) {
            std::cerr << "BOARD_AI client stopped: " << error.what() << "\n";
        }
        std::cout << "BOARD_AI_STOPPED frames=" << frame_sequence
                  << " guard_faults_before=0x" << std::hex << guard_before
                  << " guard_faults_after=0x" << regs.read(kGuardFaults)
                  << std::dec << "; CMA released\n" << std::flush;
        return 0;
    }
    return 0;
}

// Diagnostic entry point: run the same NpuRunner on one recorded 960x540 RGB
// frame instead of the camera, so the board's own numbers can be compared with
// the PC reference. It never touches the camera, the socket, or the motor.
int run_image_probe(const std::string& image_path, const std::string& model,
                    const Letterbox& letterbox = Letterbox{}) {
    const size_t expected = size_t(kHalfWidth) * kHalfHeight * 3;
    std::ifstream stream(image_path, std::ios::binary);
    if (!stream) throw std::runtime_error("cannot open image: " + image_path);
    std::vector<uint8_t> rgb(expected);
    stream.read(reinterpret_cast<char*>(rgb.data()), static_cast<std::streamsize>(expected));
    if (stream.gcount() != static_cast<std::streamsize>(expected))
        throw std::runtime_error("image must be exactly 960x540 RGB bytes");
    if (stream.peek() != std::char_traits<char>::eof())
        throw std::runtime_error("image file is longer than 960x540 RGB");
    std::cout << "PROBE image=" << image_path << " bytes=" << rgb.size() << "\n" << std::flush;
    CmaSession cma;
    NpuRunner npu(model, letterbox);
    double elapsed_ms = 0.0;
    const std::vector<Box> boxes = npu.infer(rgb, elapsed_ms);
    std::cout << "PROBE infer_ms=" << elapsed_ms << " boxes=" << boxes.size() << "\n";
    for (const Box& box : boxes)
        std::cout << "PROBE box x1=" << box.x1 << " y1=" << box.y1
                  << " x2=" << box.x2 << " y2=" << box.y2
                  << " score_per_mille=" << box.score_per_mille << "\n";
    npu.report_heads(std::cout);
    std::cout << "PROBE done; camera, socket and motor untouched\n" << std::flush;
    return 0;
}
}  // namespace board_ai

#ifndef BOARD_AI_NO_MAIN
int main(int argc, char** argv) {
    try {
        std::string address, model, image_raw, roi;
        unsigned infer_every = 5;
        if (argc < 2 || (argc & 1) == 0)
            throw std::runtime_error(
                "usage: cs500_board_ai_overlay --bind IP --model FILE"
                " [--infer-every 1..30] [--roi x,y,w,h]"
                " | --image-raw FILE --model FILE [--roi x,y,w,h]");
        for (int i = 1; i + 1 < argc; i += 2) {
            const std::string key = argv[i];
            const std::string value = argv[i+1];
            if (key == "--bind") address = value;
            else if (key == "--model") model = value;
            else if (key == "--image-raw") image_raw = value;
            else if (key == "--roi") roi = value;
            else if (key == "--infer-every") {
                const int n = std::stoi(value);
                if (n < 1 || n > 30) throw std::runtime_error("infer-every outside 1..30");
                infer_every = static_cast<unsigned>(n);
            } else throw std::runtime_error("unknown argument");
        }
        board_ai::Letterbox letterbox{};
        if (!roi.empty()) {
            std::vector<unsigned> values;
            std::stringstream stream(roi);
            std::string field;
            while (std::getline(stream, field, ',')) {
                if (field.empty()) throw std::runtime_error("--roi must be x,y,w,h");
                const int parsed = std::stoi(field);
                if (parsed < 0) throw std::runtime_error("--roi values must be non-negative");
                values.push_back(static_cast<unsigned>(parsed));
            }
            if (values.size() != 4) throw std::runtime_error("--roi must be x,y,w,h");
            letterbox = board_ai::letterbox_for(values[0], values[1], values[2], values[3]);
        }
        if (model.empty()) throw std::runtime_error("model missing");
        if (!image_raw.empty()) return board_ai::run_image_probe(image_raw, model, letterbox);
        if (address.empty()) throw std::runtime_error("bind missing");
        std::signal(SIGINT, stop_requested);
        std::signal(SIGTERM, stop_requested);
        std::signal(SIGHUP, stop_requested);
        std::signal(SIGPIPE, SIG_IGN);
        return board_ai::run_overlay(address, model, infer_every, letterbox);
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << "\n";
        return 1;
    }
}
#endif  // BOARD_AI_NO_MAIN
