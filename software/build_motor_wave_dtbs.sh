#!/usr/bin/env bash
# Build two offline DR1M90 device-tree candidates without editing the SDK or SD card.
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
sdk_root=${MOTOR_SDK_ROOT:-"$HOME/sdk.2025.7/sdk"}
linux_root="$sdk_root/linux"
dts_dir="$linux_root/arch/arm64/boot/dts/anlogic"
include_prefixes="$linux_root/scripts/dtc/include-prefixes"
dtc_bin=${MOTOR_DTC:-"$HOME/kernel-out/scripts/dtc/dtc"}

for required in "$dts_dir/anlogic-dr1m90-ad101-v10-qt.dts" \
                "$dts_dir/anlogic-dr1m90-ad101-v20-qt.dts" \
                "$include_prefixes" \
                "$script_dir/motor_wave_dma.dtsi" \
                "$script_dir/verify_motor_wave_dtb.py"; do
    if [[ ! -e "$required" ]]; then
        printf 'Missing required path: %s\n' "$required" >&2
        exit 1
    fi
done

for program in cpp python3 sha256sum; do
    if ! command -v "$program" >/dev/null 2>&1; then
        printf 'Missing required command: %s\n' "$program" >&2
        exit 1
    fi
done
if [[ ! -x "$dtc_bin" ]]; then
    dtc_bin=$(command -v dtc || true)
fi
if [[ -z "$dtc_bin" || ! -x "$dtc_bin" ]]; then
    printf 'dtc not found; build the SDK kernel host tools or install device-tree-compiler.\n' >&2
    exit 1
fi

out_dir=$(mktemp -d "$HOME/motor_wave_dtb_candidates.XXXXXX")
printf 'Output directory: %s\n' "$out_dir"
printf 'SDK source: %s\n' "$linux_root"
printf 'DTC: %s\n' "$dtc_bin"

for revision in v10 v20; do
    stem="anlogic-dr1m90-ad101-${revision}-qt-motor-wave"
    base="anlogic-dr1m90-ad101-${revision}-qt.dts"
    source_dts="$out_dir/$stem.dts"
    preprocessed_dts="$out_dir/$stem.pp.dts"
    output_dtb="$out_dir/$stem.dtb"
    cpp_log="$out_dir/$stem.cpp.log"
    dtc_log="$out_dir/$stem.dtc.log"

    printf '#include "%s"\n#include "motor_wave_dma.dtsi"\n' "$base" > "$source_dts"
    if ! cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
        -I "$include_prefixes" -I "$dts_dir" -I "$script_dir" \
        -o "$preprocessed_dts" "$source_dts" 2> "$cpp_log"; then
        printf 'CPP failed for %s; see %s\n' "$stem" "$cpp_log" >&2
        exit 1
    fi
    if ! "$dtc_bin" -I dts -O dtb -b 0 \
        -i "$dts_dir" -i "$include_prefixes" \
        -o "$output_dtb" "$preprocessed_dts" 2> "$dtc_log"; then
        printf 'DTC failed for %s; see %s\n' "$stem" "$dtc_log" >&2
        exit 1
    fi

    python3 "$script_dir/verify_motor_wave_dtb.py" "$output_dtb"
    if [[ -s "$dtc_log" ]]; then
        printf 'DTC emitted warnings for %s; see %s\n' "$stem" "$dtc_log"
    fi
done

sha256sum "$out_dir"/*.dtb
printf 'Offline candidates only. Do not replace the boot DTB until the active board DTB is identified.\n'
