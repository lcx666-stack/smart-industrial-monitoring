#!/usr/bin/env bash
# Isolated round2_118 bias ROI preview with the 1:1 preprocessing fast path.
set -euo pipefail
trap 'rc=$?; if (( rc != 0 )); then printf "BOARD_AI_PRE_CAPTURE_ABORT exit=%d\n" "$rc" >&2; fi' EXIT
[[ $# -eq 0 ]] || { echo 'FAIL: no arguments expected' >&2; exit 2; }
[[ $(uname -r) == 6.1.111-rt42 ]] || { echo 'FAIL: unexpected kernel' >&2; exit 1; }

here=$(cd -- "$(dirname -- "$0")" && pwd)
app="$here/cs500_board_ai_overlay_fast_20261017"
libs=/data/fused_npu_eth_probe_20261012
model="$here/models/round2_118_bias.onnx"
app_sha=d9755773791a1c67b25d6d1045d7c0728d4642064a196c1b6c8ded6603abd64a
model_sha=e56f166a443d20394ad7eaa93e624d4bb25040ef47cecc38ba96ea3504deb860

[[ -f $app && -f $model && -d $libs ]] || {
    echo 'FAIL: round2 bias fast ROI files missing' >&2
    exit 1
}
[[ $(sha256sum -- "$app" | cut -d ' ' -f1) == "$app_sha" &&
   $(sha256sum -- "$model" | cut -d ' ' -f1) == "$model_sha" ]] || {
    echo 'FAIL: round2 bias fast ROI binary or model hash changed' >&2
    exit 1
}
for name in libarmnn.so.32 libarmnnOnnxParser.so.24 libprotobuf.so.23; do
    [[ -f $libs/$name ]] || { echo "FAIL: missing $name" >&2; exit 1; }
done
if pgrep -af '[c]s500_board_ai_overlay' >/dev/null; then
    echo 'FAIL: another board AI overlay is already running' >&2
    exit 1
fi

(test -c /dev/cma_mem || insmod "$libs/cma_mem.ko")
(test -c /dev/hard_npu || insmod "$libs/hard_npu.ko")
(test -c /dev/soft_npu || insmod "$libs/soft_npu.ko")
ip link set eth0 up
eth0_ipv4=$(ip -4 -o addr show dev eth0)
if [[ $eth0_ipv4 != *'inet 192.168.0.50/24'* ]]; then
    if ! ip addr add 192.168.0.50/24 dev eth0; then
        eth0_ipv4=$(ip -4 -o addr show dev eth0)
        [[ $eth0_ipv4 == *'inet 192.168.0.50/24'* ]] || {
            echo 'FAIL: control IP 192.168.0.50/24 unavailable' >&2
            exit 1
        }
    fi
fi

echo 'BOARD_AI round2_118 bias ROI fast preflight PASS; motor 12 V VM must remain disconnected'
exec env LD_LIBRARY_PATH="$libs" "$app" --bind 192.168.0.50 --model "$model" \
    --roi 160,90,640,360 --infer-every 5
