#!/bin/sh
set -eu

stage=/tmp/board_service_console_authorization_20261025.py
root=/data/can_comm_candidate_20261018
target=$root/board_service.py
control=/data/ethernet_control_20261014/board_control_duty.py
backup=/data/console_direct_authorization_backup_20261025
expected=4d34a10a0c8668f612a654da39600da644a15315f3afc979163d860d4946e70c

actual=$(sha256sum "$stage" | cut -d' ' -f1)
[ "$actual" = "$expected" ] || {
    echo "Unexpected staged board_service.py hash: $actual" >&2
    exit 1
}
[ ! -e "$backup" ] || {
    echo "Backup path already exists: $backup" >&2
    exit 1
}

python3 - "$control" <<'PY'
import json
import subprocess
import sys

result = subprocess.run(['python3', '-B', sys.argv[1], 'status'],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        universal_newlines=True, timeout=12, check=True)
data = json.loads(result.stdout)['data']
if any(data.get(key) for key in ('motor_running', 'ai_running',
                                  'blackbox_running', 'wave_running')):
    raise SystemExit('Refusing deployment: board task is running')
if data['pl'].get('applied_duty') != 0:
    raise SystemExit('Refusing deployment: PL duty is not zero')
if 'CMA released' not in data.get('ai_tail', ''):
    raise SystemExit('Refusing deployment: AI CMA release is not confirmed')
print('Board idle; duty is zero; AI CMA released; fault latch preserved:',
      data.get('fault_latched'))
PY

mkdir -m 700 "$backup"
cp -p "$target" "$backup/board_service.py"
committed=0
restore() {
    code=$?
    trap - EXIT
    if [ "$committed" -ne 1 ]; then
        cp -p "$backup/board_service.py" "$target"
        systemctl start can-control-alarm.service || code=1
    fi
    exit "$code"
}
trap restore EXIT

systemctl stop can-control-alarm.service
cp "$stage" "$target.new"
chmod 755 "$target.new"
mv -f "$target.new" "$target"
python3 -B "$target" --check-only
systemctl start can-control-alarm.service
systemctl is-active --quiet can-control-alarm.service
python3 - "$control" <<'PY'
import json
import subprocess
import sys

result = subprocess.run(['python3', '-B', sys.argv[1], 'status'],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        universal_newlines=True, timeout=12, check=True)
data = json.loads(result.stdout)['data']
if data.get('motor_running') or data['pl'].get('applied_duty') != 0:
    raise SystemExit('Post-deploy motor state is not stopped at zero duty')
print('CAN service updated; motor remains stopped; duty is zero')
PY

committed=1
trap - EXIT
