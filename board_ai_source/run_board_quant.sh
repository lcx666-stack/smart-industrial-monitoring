#!/usr/bin/env bash
# Board-only camera + Hybrid NPU preview. Motor 12 V VM must stay unplugged.
set -euo pipefail
trap 'rc=$?; if (( rc != 0 )); then printf "BOARD_AI_PRE_CAPTURE_ABORT exit=%d\n" "$rc" >&2; fi' EXIT
[[ $# -eq 0 ]] || { echo 'FAIL: no arguments expected' >&2; exit 2; }
[[ $(uname -r) == 6.1.111-rt42 ]] || { echo 'FAIL: unexpected kernel' >&2; exit 1; }
app=/data/board_ai_overlay_candidate_20261014/cs500_board_ai_overlay_quant_20261014
model=/data/npu_demo_ab_candidate_20261013/best_raw_heads_qdq_inferred_trial.onnx
libs=/data/fused_npu_eth_probe_20261012
app_sha=cb144850e064d13725eb5f1c7e4c59d8186cd3e80b1809a301abdc30d528befb
model_sha=f24a5ce60668f28598c8aa22fd68483e401b732b9610c9e52418ed992d6d1744
[[ -f $app && -f $model && -d $libs ]] || { echo 'FAIL: board AI files missing' >&2; exit 1; }
[[ $(sha256sum -- "$app" | cut -d ' ' -f1) == "$app_sha" &&
   $(sha256sum -- "$model" | cut -d ' ' -f1) == "$model_sha" ]] || {
    echo 'FAIL: AI binary or model hash changed' >&2; exit 1;
}
for name in libarmnn.so.32 libarmnnOnnxParser.so.24 libprotobuf.so.23; do
    [[ -f $libs/$name ]] || { echo "FAIL: missing $name" >&2; exit 1; }
done
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
echo 'BOARD_AI quantized preflight PASS; motor 12 V VM must remain disconnected'
exec env LD_LIBRARY_PATH="$libs" "$app" --bind 192.168.0.50 --model "$model" --infer-every 5
