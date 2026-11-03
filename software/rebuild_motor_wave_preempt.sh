#!/usr/bin/env bash
# Build a PREEMPT module candidate for the existing 6.1.111-rt42 board kernel.
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
sdk_root=${MOTOR_SDK_ROOT:-"$HOME/sdk.2025.7/sdk"}
linux_root="$sdk_root/linux"
cross_prefix=${MOTOR_WAVE_CROSS_COMPILE:-aarch64-linux-gnu-}
build_jobs=${MOTOR_WAVE_BUILD_JOBS:-2}
expected_release=6.1.111-rt42
expected_magic='6.1.111-rt42 SMP preempt mod_unload aarch64'

if [[ ! "$build_jobs" =~ ^[1-9][0-9]*$ ]]; then
    printf 'MOTOR_WAVE_BUILD_JOBS must be a positive integer.\n' >&2
    exit 1
fi
for program in make modinfo python3 sha256sum "${cross_prefix}gcc"; do
    if ! command -v "$program" >/dev/null 2>&1; then
        printf 'Missing command: %s\n' "$program" >&2
        exit 1
    fi
done
for required in "$linux_root/arch/arm64/configs/anlogic_dr1m90_defconfig" \
                "$script_dir/Makefile" "$script_dir/motor_wave_dma.c" \
                "$script_dir/motor_wave_dma_uapi.h"; do
    if [[ ! -f "$required" ]]; then
        printf 'Missing input: %s\n' "$required" >&2
        exit 1
    fi
done

kernel_output=$(mktemp -d "$HOME/kernel-preempt-out.XXXXXX")
module_output=$(mktemp -d "$HOME/motor_wave_dma_preempt_build.XXXXXX")
printf 'Kernel output: %s\nModule output: %s\n' "$kernel_output" "$module_output"
kernel_make=(make -C "$linux_root" "O=$kernel_output" ARCH=arm64
             "CROSS_COMPILE=$cross_prefix")
"${kernel_make[@]}" anlogic_dr1m90_defconfig
"${kernel_make[@]}" olddefconfig

python3 - "$kernel_output/.config" <<'PY'
import sys
from pathlib import Path
lines = set(Path(sys.argv[1]).read_text().splitlines())
for name in ("PREEMPT", "PREEMPT_BUILD", "SMP", "MODULES", "MODULE_UNLOAD"):
    if "CONFIG_{}=y".format(name) not in lines:
        raise SystemExit("Unexpected kernel configuration: {} must be y".format(name))
for name in ("PREEMPT_RT", "MODVERSIONS"):
    if "CONFIG_{}=y".format(name) in lines:
        raise SystemExit("Unexpected kernel configuration: {} must be disabled".format(name))
print("Configuration check PASS: PREEMPT, SMP, module unload; no RT or modversions")
PY

release=$("${kernel_make[@]}" -s --no-print-directory kernelrelease)
if [[ "$release" != "$expected_release" ]]; then
    printf 'Kernel release mismatch: %s; expected %s\n' "$release" "$expected_release" >&2
    exit 1
fi

# A complete kernel build is needed for the kernel symbol table, not just
# modules_prepare. Leave the previous RT build and running board untouched.
"${kernel_make[@]}" -j"$build_jobs" KBUILD_MODPOST_WARN= Image modules \
    2>&1 | tee "$kernel_output/build.log"
if [[ ! -s "$kernel_output/Module.symvers" ]]; then
    printf 'Kernel Module.symvers is missing or empty.\n' >&2
    exit 1
fi
cp -- "$script_dir/Makefile" "$script_dir/motor_wave_dma.c" \
      "$script_dir/motor_wave_dma_uapi.h" "$module_output/"
"${kernel_make[@]}" "M=$module_output" -j"$build_jobs" KBUILD_MODPOST_WARN= modules \
    2>&1 | tee "$module_output/build.log"
magic=$(modinfo -F vermagic "$module_output/motor_wave_dma.ko")
magic=${magic%"${magic##*[![:space:]]}"}
if [[ "$magic" != "$expected_magic" ]]; then
    printf 'Module vermagic mismatch: %s\nExpected: %s\n' "$magic" "$expected_magic" >&2
    exit 1
fi

result_dir=$(mktemp -d "$script_dir/preempt-candidate.XXXXXX")
cp -- "$module_output/motor_wave_dma.ko" "$module_output/build.log" "$result_dir/"
cp -- "$kernel_output/.config" "$result_dir/kernel.config"
printf 'Candidate directory: %s\nvermagic: %s\n' "$result_dir" "$magic"
sha256sum "$result_dir/motor_wave_dma.ko"
printf 'PASS: PREEMPT module candidate built; board loading and DMA test still pending.\n'
