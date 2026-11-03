#!/bin/sh
set -eu

stage=/tmp/live-duty-20261025
root=/data/can_comm_candidate_20261018
control=/data/ethernet_control_20261014
motor=/data/motor_anomaly_candidate_20261017/motor_open_loop_pwm10_anomaly.py
backup=/data/live_duty_backup_20261025

check_hash() {
    expected=$1
    path=$2
    actual=$(sha256sum "$path" | cut -d' ' -f1)
    [ "$actual" = "$expected" ] || {
        echo "Unexpected hash: $path ($actual)" >&2
        exit 1
    }
}

python3 - "$control/board_control_duty.py" <<'PY'
import importlib.util
import json
import subprocess
import sys

helper = sys.argv[1]
result = subprocess.run(['python3', '-B', helper, 'status'],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        universal_newlines=True, timeout=12, check=True)
data = json.loads(result.stdout)['data']
if any(data.get(key) for key in ('motor_running', 'ai_running',
                                  'blackbox_running', 'wave_running')):
    raise SystemExit('Refusing deployment: board task still running')
if data['pl'].get('applied_duty') != 0:
    raise SystemExit('Refusing deployment: PL duty is not zero')
if ('CMA released' not in data.get('ai_tail', '') or
        'CMA retained' in data.get('ai_tail', '')):
    raise SystemExit('Refusing deployment: AI CMA release is not confirmed')
spec = importlib.util.spec_from_file_location('live_duty_board', helper)
board = importlib.util.module_from_spec(spec)
spec.loader.exec_module(board)
if board.dma_device_open():
    raise SystemExit('Refusing deployment: DMA device still open')
print('Board idle; CMA and DMA released; fault latch preserved:',
      data.get('fault_latched'))
PY

[ ! -e "$control/wave-service.sock" ] || {
    echo 'Waveform socket still present' >&2
    exit 1
}
[ ! -e "$backup" ] || {
    echo "Backup path already exists: $backup" >&2
    exit 1
}

check_hash 058647638289ec754c1f6a04bf4b713a28723e62deb99fad37c19e737442da0b "$control/board_control_duty.py"
check_hash 058647638289ec754c1f6a04bf4b713a28723e62deb99fad37c19e737442da0b "$root/board_control_can.py"
check_hash 1e7fc89b0c21bc455e18f7d6f97a681a0de6299e96aa49e495dbc708427494b5 "$control/board_control_agent.py"
check_hash f262d9d3e6ce735ddfe70f3368b0d50d557beac421624c76f3d4c165dd709f77 "$root/board_service.py"
check_hash e06f62064874622cceade95050ba24640f063be0d8888bb38586d45773cac0c5 "$root/protocol.py"
check_hash e81cb098e58239fbcb4dfe513d290b0fbceb2f3a923d33fee38911a4f458c790 "$motor"
check_hash affbb6e5de7ca3a69dd52a48e4ff73b6b4bcda15e94ea78604e07b73fe69532b "$stage/motor_open_loop_pwm10_anomaly.py"
check_hash fe5ab7c8c455cb035c81724b5676183c9e47d5f2b2ec9384af2dafbd52e59f19 "$stage/board_control_can.py"
check_hash 07f4d0867cf489175c14952acafc6c28b3cdf74ed9f597eb30e21c82530dda2c "$stage/board_service.py"
check_hash 3ece3844c16cace90ecfb8b099cb5691c97ebccee2db7ef87a7f06a5f2ed9b89 "$stage/protocol.py"
check_hash 02adff95d4c91d6f926e4c46e85500c23ddcccf829dc374d1b496e9f6063a3d5 "$stage/board_agent_candidate.py"

mkdir -m 700 "$backup"
committed=0
restore() {
    code=$?
    trap - EXIT
    if [ "$committed" -ne 1 ]; then
        for name in board_control_duty.py board_control_agent.py; do
            [ ! -e "$backup/$name" ] || cp -p "$backup/$name" "$control/$name"
        done
        for name in board_control_can.py board_service.py protocol.py; do
            [ ! -e "$backup/$name" ] || cp -p "$backup/$name" "$root/$name"
        done
        [ ! -e "$backup/motor_open_loop_pwm10_anomaly.py" ] ||
            cp -p "$backup/motor_open_loop_pwm10_anomaly.py" "$motor"
        systemctl start can-control-alarm.service || code=1
    fi
    exit "$code"
}
trap restore EXIT

cp -p "$control/board_control_duty.py" "$backup/board_control_duty.py"
cp -p "$control/board_control_agent.py" "$backup/board_control_agent.py"
cp -p "$root/board_control_can.py" "$backup/board_control_can.py"
cp -p "$root/board_service.py" "$backup/board_service.py"
cp -p "$root/protocol.py" "$backup/protocol.py"
cp -p "$motor" "$backup/motor_open_loop_pwm10_anomaly.py"

systemctl stop can-control-alarm.service
pkill -TERM -f '^python3 -u -B /data/ethernet_control_20261014/board_control_agent.py$' || true

install_file() {
    source=$1
    target=$2
    mode=$3
    cp "$source" "$target.new"
    chmod "$mode" "$target.new"
    mv -f "$target.new" "$target"
}
install_file "$stage/motor_open_loop_pwm10_anomaly.py" "$motor" 700
install_file "$stage/board_control_can.py" "$root/board_control_can.py" 700
install_file "$stage/board_control_can.py" "$control/board_control_duty.py" 700
install_file "$stage/board_service.py" "$root/board_service.py" 755
install_file "$stage/protocol.py" "$root/protocol.py" 644
install_file "$stage/board_agent_candidate.py" "$control/board_control_agent.py" 700

check_hash affbb6e5de7ca3a69dd52a48e4ff73b6b4bcda15e94ea78604e07b73fe69532b "$motor"
check_hash fe5ab7c8c455cb035c81724b5676183c9e47d5f2b2ec9384af2dafbd52e59f19 "$root/board_control_can.py"
check_hash fe5ab7c8c455cb035c81724b5676183c9e47d5f2b2ec9384af2dafbd52e59f19 "$control/board_control_duty.py"
check_hash 07f4d0867cf489175c14952acafc6c28b3cdf74ed9f597eb30e21c82530dda2c "$root/board_service.py"
check_hash 3ece3844c16cace90ecfb8b099cb5691c97ebccee2db7ef87a7f06a5f2ed9b89 "$root/protocol.py"
check_hash 02adff95d4c91d6f926e4c46e85500c23ddcccf829dc374d1b496e9f6063a3d5 "$control/board_control_agent.py"

python3 -B "$root/board_service.py" --check-only
systemctl start can-control-alarm.service
systemctl is-active --quiet can-control-alarm.service
python3 - "$control/board_control_duty.py" <<'PY'
import json
import subprocess
import sys

result = subprocess.run(['python3', '-B', sys.argv[1], 'status'],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        universal_newlines=True, timeout=12, check=True)
data = json.loads(result.stdout)['data']
if any(data.get(key) for key in ('motor_running', 'ai_running',
                                  'blackbox_running', 'wave_running')):
    raise SystemExit('Post-deploy status is not idle')
if data['pl'].get('applied_duty') != 0:
    raise SystemExit('Post-deploy PL duty is not zero')
if not data.get('fault_latched'):
    raise SystemExit('Existing fault latch unexpectedly changed')
print('Deployment status verified: idle, duty 0, previous fault latch preserved')
PY

pkill -TERM -f '^python3 -u -B /data/ethernet_control_20261014/board_control_agent.py$' || true
committed=1
trap - EXIT
echo "DEPLOY_OK backup=$backup"
