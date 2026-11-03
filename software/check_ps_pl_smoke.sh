#!/bin/sh
# Run on the DR1 Linux board only after booting the smoke-test hardware image.
# Without --snapshot this performs read-only MMIO accesses.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root to access /dev/mem." >&2
    exit 1
fi

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--snapshot" ]; }; then
    echo "Usage: $0 [--snapshot]" >&2
    exit 2
fi

if command -v devmem >/dev/null 2>&1; then
    mmio() { devmem "$@"; }
elif command -v busybox >/dev/null 2>&1; then
    mmio() { busybox devmem "$@"; }
else
    echo "Neither devmem nor BusyBox was found." >&2
    exit 1
fi

id_value=$(mmio 0x80000000 32)
abi_value=$(mmio 0x80000004 32)
printf 'ID  = %s (expected 0x4D535431)\n' "$id_value"
printf 'ABI = %s (expected 0x00010000)\n' "$abi_value"

id_upper=$(printf '%s' "$id_value" | tr '[:lower:]' '[:upper:]')
abi_upper=$(printf '%s' "$abi_value" | tr '[:lower:]' '[:upper:]')
if [ "$id_upper" != "0X4D535431" ] || [ "$abi_upper" != "0X00010000" ]; then
    echo "FAIL: wrong hardware image, address mapping, or PS-PL connection." >&2
    echo "No register write was attempted." >&2
    exit 1
fi

if [ "$#" -eq 1 ]; then
    # A capture write is safe only after both identification reads match.
    mmio 0x80000008 32 0x1
    seq_value=$(mmio 0x8000000C 32)
    flags_value=$(mmio 0x80000010 32)
    printf 'SEQ = %s\nFLAGS = %s\n' "$seq_value" "$flags_value"
fi

echo "PASS: PS can read the PL status-register block."
