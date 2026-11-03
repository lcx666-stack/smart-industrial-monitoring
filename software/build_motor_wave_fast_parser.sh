#!/usr/bin/env bash
# Build the userspace batch validator only; no kernel or PL rebuild is needed.
set -euo pipefail
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cross_prefix=${MOTOR_WAVE_CROSS_COMPILE:-aarch64-linux-gnu-}
for program in "${cross_prefix}gcc" "${cross_prefix}readelf" sha256sum python3; do
    if ! command -v "$program" >/dev/null 2>&1; then
        printf 'Missing command: %s\n' "$program" >&2
        exit 1
    fi
done
for name in motor_wave_stats.c motor_wave_stats.py check_waveform_dma.py motor_blackbox.py check_blackbox_event.py; do
    if [[ ! -f "$script_dir/$name" ]]; then
        printf 'Missing source: %s\n' "$name" >&2
        exit 1
    fi
done
result_dir=$(mktemp -d "$script_dir/fast-parser-candidate.XXXXXX")
"${cross_prefix}gcc" -std=c11 -O3 -Wall -Wextra -Werror -fPIC \
    -fno-builtin -fno-stack-protector -nostdlib -shared \
    -Wl,--no-undefined -Wl,-z,noexecstack -Wl,-soname,lib_motor_wave_stats.so \
    "$script_dir/motor_wave_stats.c" -o "$result_dir/lib_motor_wave_stats.so"
elf_header=$("${cross_prefix}readelf" -h "$result_dir/lib_motor_wave_stats.so")
if [[ "$elf_header" != *AArch64* ]]; then
    printf 'Unexpected native parser architecture.\n' >&2
    exit 1
fi
dependencies=$("${cross_prefix}readelf" -d "$result_dir/lib_motor_wave_stats.so")
if [[ "$dependencies" == *NEEDED* ]]; then
    printf 'Parser unexpectedly depends on shared libraries.\n' >&2
    exit 1
fi
cp -- "$script_dir/motor_wave_stats.py" "$script_dir/check_waveform_dma.py" \
      "$script_dir/motor_blackbox.py" "$script_dir/check_blackbox_event.py" "$result_dir/"
# Import the actual deployment bundle in a fresh Python process. This catches
# a plain ctypes library accidentally shadowing the Python wrapper with the
# same module basename, without loading AArch64 code on the build host.
python3 -B "$result_dir/check_waveform_dma.py" --help >/dev/null
python3 -B "$result_dir/motor_blackbox.py" --help >/dev/null
python3 -B "$result_dir/check_blackbox_event.py" --help >/dev/null
symbols=$("${cross_prefix}readelf" --dyn-syms --wide "$result_dir/lib_motor_wave_stats.so")
if [[ "$symbols" != *motor_wave_scan_ingest* ]]; then
    printf 'Native library lacks the black-box scanner.\n' >&2
    exit 1
fi
printf 'Candidate directory: %s\n' "$result_dir"
sha256sum "$result_dir/lib_motor_wave_stats.so" "$result_dir/motor_wave_stats.py" \
          "$result_dir/check_waveform_dma.py" "$result_dir/motor_blackbox.py" \
          "$result_dir/check_blackbox_event.py"
printf 'PASS: AArch64 parser built without libc dependencies; bundle import checked; board retest pending.\n'
