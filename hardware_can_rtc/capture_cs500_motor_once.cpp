// One-shot capture or provisional live preview on the merged motor+camera BOOT.
// Never writes motor control/guard registers; motor rotation and waveform DMA
// may remain active. Live preview reuses one DMA buffer, so tearing is possible.
// Uses the vendor MIT-licensed CMA userspace API from the supplied Arm NN SDK.
#include <armnnALUtils/cma_mem_init.hpp>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/mman.h>
#include <unistd.h>

namespace {
constexpr uint64_t kStatusBase = 0x80000000ULL;
constexpr size_t kPageBytes = 4096;
constexpr uint32_t kFrameBytes = 1920U * 1080U * 4U;
constexpr unsigned kCamId = 0xC00 / 4;
constexpr unsigned kCamVersion = 0xC04 / 4;
constexpr unsigned kCamControl = 0xC08 / 4;
constexpr unsigned kCamBase = 0xC0C / 4;
constexpr unsigned kCamSize = 0xC10 / 4;
constexpr unsigned kCamStatus = 0xC14 / 4;
constexpr unsigned kCamSequence = 0xC18 / 4;
constexpr unsigned kFeatureFlags = 0x054 / 4;
constexpr unsigned kGuardFaults = 0x124 / 4;
constexpr unsigned kWaveDropped = 0x0A0 / 4;
constexpr unsigned kWaveStatus = 0x0A8 / 4;
constexpr unsigned kDsiId = 0xC80 / 4;
constexpr unsigned kDsiControl = 0xC88 / 4;
constexpr unsigned kDsiBase = 0xC8C / 4;
constexpr unsigned kDsiStatus = 0xC90 / 4;
constexpr unsigned kDsiErrorDetail = 0xCA0 / 4;
constexpr unsigned kDsiFirstReadAddress = 0xCA4 / 4;
volatile std::sig_atomic_t gStopDisplay = 0;
void request_display_stop(int) { gStopDisplay = 1; }

class File {
public:
    explicit File(int fd) : fd_(fd) {
        if (fd_ < 0) throw std::runtime_error(std::strerror(errno));
    }
    ~File() { if (fd_ >= 0) ::close(fd_); }
    int get() const { return fd_; }
    File(const File&) = delete;
    File& operator=(const File&) = delete;
private:
    int fd_;
};

class CameraRegisters {
public:
    CameraRegisters() : memory_(::open("/dev/mem", O_RDWR | O_SYNC | O_CLOEXEC)) {
        void* mapped = ::mmap(nullptr, kPageBytes, PROT_READ | PROT_WRITE,
                              MAP_SHARED, memory_.get(), kStatusBase);
        if (mapped == MAP_FAILED) throw std::runtime_error("camera status mmap failed");
        words_ = static_cast<volatile uint32_t*>(mapped);
    }
    ~CameraRegisters() { ::munmap(const_cast<uint32_t*>(words_), kPageBytes); }
    uint32_t read(unsigned offset) const { return words_[offset]; }
    void write(unsigned offset, uint32_t value) {
        words_[offset] = value;
        __sync_synchronize();
    }
    CameraRegisters(const CameraRegisters&) = delete;
    CameraRegisters& operator=(const CameraRegisters&) = delete;
private:
    File memory_;
    volatile uint32_t* words_ = nullptr;
};

class CmaSession {
public:
    CmaSession() {
        if (cma_mem_init() != 0) throw std::runtime_error("CMA init failed");
    }
    ~CmaSession() { cma_mem_deinit(); }
};

class CmaFrame {
public:
    CmaFrame() : buffer_(kFrameBytes) {
        if (cma_mem_alloc(&buffer_) != 0 || !buffer_.virt_addr || !buffer_.phys_addr)
            throw std::runtime_error("CMA frame allocation failed");
        allocated_ = true;
        if (buffer_.phys_addr > UINT32_MAX ||
            buffer_.phys_addr + kFrameBytes - 1 > UINT32_MAX ||
            (buffer_.phys_addr & 63U) != 0) {
            cma_mem_free(&buffer_);
            allocated_ = false;
            throw std::runtime_error("CMA frame address is not a valid 32-bit aligned DMA range");
        }
    }
    ~CmaFrame() { if (allocated_) cma_mem_free(&buffer_); }
    uint32_t physical() const { return static_cast<uint32_t>(buffer_.phys_addr); }
    const uint8_t* data() const { return static_cast<const uint8_t*>(buffer_.virt_addr); }
    void prepare() {
        std::memset(buffer_.virt_addr, 0, kFrameBytes);
        if (cma_mem_sync_for_device(buffer_.phys_addr, kFrameBytes) != 0)
            throw std::runtime_error("CMA pre-DMA sync failed");
    }
    void finish() {
        if (cma_mem_sync_for_cpu(buffer_.phys_addr, kFrameBytes) != 0)
            throw std::runtime_error("CMA post-DMA sync failed");
    }
    void prepare_for_display() {
        if (cma_mem_sync_for_device(buffer_.phys_addr, kFrameBytes) != 0)
            throw std::runtime_error("CMA display-read sync failed");
    }
private:
    cma_buffer_t buffer_;
    bool allocated_ = false;
};

void write_new(const std::string& path, const uint8_t* data) {
    File output(::open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0644));
    size_t done = 0;
    while (done < kFrameBytes) {
        ssize_t count = ::write(output.get(), data + done, kFrameBytes - done);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) throw std::runtime_error("frame file write failed");
        done += static_cast<size_t>(count);
    }
    if (::fsync(output.get()) != 0) throw std::runtime_error("frame fsync failed");
}

// If a started DMA never completes, exiting could release the still-active
// physical buffer to Linux. Hold it until the operator powers off the board.
[[noreturn]] void hold_dma_buffer_on_timeout(uint32_t status) {
    std::cerr << "FAIL: capture timeout, status=0x" << std::hex << status
              << "; DMA buffer retained. Power off the board before retrying.\n";
    std::signal(SIGINT, SIG_IGN);
    std::signal(SIGTERM, SIG_IGN);
    for (;;) ::sleep(3600);
}

[[noreturn]] void retain_buffer_on_live_fault(const char* reason, uint32_t status) {
    std::cerr << "FAIL: live preview " << reason << ", status=0x" << std::hex
              << status << "; DMA buffer retained. Power off the board before retrying.\n";
    std::signal(SIGINT, SIG_IGN);
    std::signal(SIGTERM, SIG_IGN);
    for (;;) ::sleep(3600);
}

// Use the existing one-frame PL ABI repeatedly. The camera writer and DSI
// reader share a stable physical allocation for the entire preview session.
// This is deliberately a focus preview, not tear-free double buffering.
int run_live_preview() {
    CameraRegisters regs;
    if (regs.read(0) != 0x4D535431 || regs.read(kFeatureFlags) != 0x4143 ||
        regs.read(kCamId) != 0x43414D32 || regs.read(kCamVersion) != 0x00020000 ||
        regs.read(kDsiId) != 0x4453'4931U)
        throw std::runtime_error("merged motor/camera/DSI identity mismatch");
    uint32_t status = regs.read(kCamStatus);
    if (status & (1U << 11))
        throw std::runtime_error("CS500 did not acknowledge PL I2C initialization");
    if ((status & ((1U << 6) | (1U << 7))) != ((1U << 6) | (1U << 7)))
        throw std::runtime_error("CS500 sensor configuration or camera PLL not ready");
    if (status & ((1U << 0) | (1U << 2) | (1U << 4) | (1U << 5)))
        throw std::runtime_error("camera is busy or has a latched DMA/FIFO error");
    status = regs.read(kDsiStatus);
    if ((status & (1U << 3)) == 0 || (status & ((1U << 0) | (1U << 4) | (1U << 5))))
        throw std::runtime_error("DSI panel not ready or display already in use");

    CmaSession cma;
    CmaFrame frame;
    frame.prepare();
    std::signal(SIGINT, request_display_stop);
    std::signal(SIGTERM, request_display_stop);
    std::signal(SIGHUP, request_display_stop);
    regs.write(kCamBase, frame.physical());
    regs.write(kCamSize, kFrameBytes);
    const uint32_t guard_faults_before = regs.read(kGuardFaults);
    uint64_t frames = 0;
    bool display_started = false;

    auto capture_next = [&]() {
        const uint32_t before_seq = regs.read(kCamSequence);
        status = regs.read(kCamStatus);
        if (status & ((1U << 0) | (1U << 2) | (1U << 3) |
                      (1U << 4) | (1U << 5))) {
            if (display_started) retain_buffer_on_live_fault("camera not idle", status);
            throw std::runtime_error("camera not idle before first frame");
        }
        regs.write(kCamControl, 1);
        status = regs.read(kCamStatus);
        if ((status & 1U) == 0 || (status & (1U << 10))) {
            if (display_started) retain_buffer_on_live_fault("camera start rejected", status);
            throw std::runtime_error("camera start rejected before display enabled");
        }
        const auto started = std::chrono::steady_clock::now();
        for (;;) {
            status = regs.read(kCamStatus);
            if ((status & (1U << 1)) && regs.read(kCamSequence) != before_seq &&
                (status & (1U << 3)) == 0) break;
            if (std::chrono::steady_clock::now() - started >
                std::chrono::seconds(3)) hold_dma_buffer_on_timeout(status);
            ::usleep(1000);
        }
        regs.write(kCamControl, 2);
        if (status & ((1U << 4) | (1U << 5)))
            retain_buffer_on_live_fault("camera AXI/FIFO error", status);
        const auto cleared = std::chrono::steady_clock::now();
        do {
            status = regs.read(kCamStatus);
            if ((status & ((1U << 0) | (1U << 2) | (1U << 3))) == 0) break;
            if (std::chrono::steady_clock::now() - cleared >
                std::chrono::seconds(3)) retain_buffer_on_live_fault("camera did not clear", status);
            ::usleep(1000);
        } while (true);
        ++frames;
    };

    capture_next();
    // Both DMA engines access DDR directly. Do not touch the CPU mapping while
    // the display is active, and do not free it until display reads drain.
    regs.write(kDsiBase, frame.physical());
    regs.write(kDsiControl, 1);
    status = regs.read(kDsiStatus);
    if ((status & 1U) == 0 || (status & (1U << 5))) {
        if (status & 1U) retain_buffer_on_live_fault("DSI enable ambiguous", status);
        throw std::runtime_error("DSI display enable rejected");
    }
    display_started = true;
    const auto display_started_at = std::chrono::steady_clock::now();
    while ((regs.read(kDsiStatus) & (1U << 1)) == 0) {
        if (std::chrono::steady_clock::now() - display_started_at >
            std::chrono::seconds(3))
            retain_buffer_on_live_fault("DSI reader did not arm", regs.read(kDsiStatus));
        ::usleep(1000);
    }
    std::cout << "LIVE_PREVIEW active; one CMA buffer, tearing possible. "
              << "Press Ctrl-C once to stop safely.\n" << std::flush;

    while (!gStopDisplay) {
        capture_next();
        status = regs.read(kDsiStatus);
        if ((status & (1U << 4)) || (status & 1U) == 0) {
            std::cerr << "DSI_DIAG detail=0x" << std::hex
                      << regs.read(kDsiErrorDetail) << " first_araddr=0x"
                      << regs.read(kDsiFirstReadAddress) << std::dec
                      << "\n" << std::flush;
            retain_buffer_on_live_fault("DSI read error or stopped", status);
        }
        if (frames % 30 == 0)
            std::cout << "LIVE_PREVIEW frames=" << frames
                      << " guard_faults=0x" << std::hex << regs.read(kGuardFaults)
                      << std::dec << "\n" << std::flush;
    }
    regs.write(kDsiControl, 2);
    const auto stopped = std::chrono::steady_clock::now();
    do {
        status = regs.read(kDsiStatus);
        if ((status & ((1U << 0) | (1U << 1) | (1U << 2))) == 0) break;
        if (std::chrono::steady_clock::now() - stopped >
            std::chrono::seconds(3)) retain_buffer_on_live_fault("DSI did not drain", status);
        ::usleep(1000);
    } while (true);
    std::cout << "LIVE_PREVIEW_STOPPED frames=" << frames
              << " guard_faults_before=0x" << std::hex << guard_faults_before
              << " guard_faults_after=0x" << regs.read(kGuardFaults) << std::dec
              << "; DMA buffer released\n";
    return 0;
}
}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc == 2 && std::string(argv[1]) == "--live-preview")
            return run_live_preview();
        const bool hold_display = argc == 4 &&
                                  std::string(argv[3]) == "--display-hold";
        if ((argc != 3 && !hold_display) || std::string(argv[1]) != "--output")
            throw std::runtime_error(
                "usage: capture_cs500_motor_once --output NEW.raw [--display-hold] | --live-preview");
        const std::string path(argv[2]);
        if (path.empty() || ::access(path.c_str(), F_OK) == 0)
            throw std::runtime_error("output path is empty or already exists");

        CameraRegisters regs;
        if (regs.read(0) != 0x4D535431 || regs.read(kFeatureFlags) != 0x4143 ||
            regs.read(kCamId) != 0x43414D32 || regs.read(kCamVersion) != 0x00020000)
            throw std::runtime_error("merged motor/CS500 register identity mismatch");
        uint32_t status = regs.read(kCamStatus);
        if (status & (1U << 11))
            throw std::runtime_error("CS500 did not acknowledge PL I2C initialization");
        if ((status & ((1U << 6) | (1U << 7))) != ((1U << 6) | (1U << 7)))
            throw std::runtime_error("CS500 sensor configuration or camera PLL not ready");
        if (status & ((1U << 0) | (1U << 4) | (1U << 5)))
            throw std::runtime_error("camera is busy or has a latched DMA/FIFO error");

        CmaSession cma;
        CmaFrame frame;
        frame.prepare();
        const uint32_t start_status = status;
        const uint32_t before_seq = regs.read(kCamSequence);
        const uint32_t before_faults = regs.read(kGuardFaults);
        const uint32_t before_dropped = regs.read(kWaveDropped);
        const uint32_t before_wave_status = regs.read(kWaveStatus);
        std::signal(SIGINT, request_display_stop);
        std::signal(SIGTERM, request_display_stop);
        std::signal(SIGHUP, request_display_stop);
        regs.write(kCamBase, frame.physical());
        regs.write(kCamSize, kFrameBytes);
        regs.write(kCamControl, 1);
        status = regs.read(kCamStatus);
        if ((status & 1U) == 0 || (status & (1U << 10)))
            throw std::runtime_error("camera start rejected by PL; DMA not armed");

        const auto started = std::chrono::steady_clock::now();
        for (;;) {
            status = regs.read(kCamStatus);
            const uint32_t seq = regs.read(kCamSequence);
            if ((status & (1U << 1)) && seq != before_seq &&
                (status & (1U << 3)) == 0) break;
            if (std::chrono::steady_clock::now() - started >
                std::chrono::seconds(3)) hold_dma_buffer_on_timeout(status);
            ::usleep(1000);
        }
        const auto elapsed = std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - started).count();
        regs.write(kCamControl, 2);  // clear completed camera capture only
        if (status & ((1U << 4) | (1U << 5)))
            throw std::runtime_error("camera AXI response or pixel FIFO overflow; frame discarded");
        frame.finish();
        write_new(path, frame.data());
        const size_t nonzero = std::count_if(frame.data(), frame.data() + kFrameBytes,
                                             [](uint8_t x) { return x != 0; });
        std::cout << "CAPTURED_RAW " << path << " bytes=" << kFrameBytes
                  << " nonzero=" << nonzero << " elapsed_ms=" << elapsed
                  << " motor_running_start/end=" << ((start_status >> 9) & 1U)
                  << "/" << ((status >> 9) & 1U)
                  << " waveform_dma_active_start/end=" << ((start_status >> 8) & 1U)
                  << "/" << ((status >> 8) & 1U)
                  << " guard_faults_before=0x" << std::hex << before_faults
                  << " guard_faults_after=0x" << regs.read(kGuardFaults)
                  << " wave_dropped_before/after=" << std::dec << before_dropped
                  << "/" << regs.read(kWaveDropped)
                  << " wave_status_before/after=0x" << std::hex << before_wave_status
                  << "/0x" << regs.read(kWaveStatus)
                  << "; visual validity pending\n";
        if (hold_display) {
            if (regs.read(kDsiId) != 0x4453'4931U)
                throw std::runtime_error("DSI1 register identity not present");
            if ((regs.read(kDsiStatus) & (1U << 3)) == 0)
                throw std::runtime_error("DSI panel initialization not complete");
            frame.prepare_for_display();
            regs.write(kDsiBase, frame.physical());
            regs.write(kDsiControl, 1);
            uint32_t dsi_status = regs.read(kDsiStatus);
            if ((dsi_status & 1U) == 0 || (dsi_status & (1U << 5)))
                throw std::runtime_error("DSI static display enable rejected");
            std::cout << "DISPLAY_HOLD active; press Ctrl-C to stop display and drain DDR reads\n";
            while (!gStopDisplay) ::usleep(100000);
            regs.write(kDsiControl, 2);
            const auto stop_started = std::chrono::steady_clock::now();
            do {
                dsi_status = regs.read(kDsiStatus);
                if ((dsi_status & ((1U << 0) | (1U << 1) | (1U << 2))) == 0)
                    break;
                if (std::chrono::steady_clock::now() - stop_started >
                    std::chrono::seconds(3))
                    hold_dma_buffer_on_timeout(dsi_status);
                ::usleep(1000);
            } while (true);
            std::cout << "DISPLAY_STOPPED; CMA buffer may now be freed\n";
        }
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << "\n";
        return 1;
    }
}
