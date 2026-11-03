#!/bin/sh
set -eu

stage=/tmp/board_agent_can_only_20261025.py
target=/data/ethernet_control_20261014/board_control_agent.py
backup=/data/ethernet_control_20261014/board_control_agent_before_can_only_20261025.py
expected=6ce37d076c9744922bdb81bf55229a76ec155989e04fd05fa7481ef6cd1cecf1

actual=$(sha256sum "$stage" | cut -d' ' -f1)
[ "$actual" = "$expected" ] || {
    echo "Unexpected staged agent hash: $actual" >&2
    exit 1
}
[ -f "$target" ] || {
    echo "Board agent is missing: $target" >&2
    exit 1
}
[ ! -e "$backup" ] || {
    echo "Backup already exists: $backup" >&2
    exit 1
}

cp -p "$target" "$backup"
cp "$stage" "$target.new"
chmod 700 "$target.new"
mv -f "$target.new" "$target"
actual=$(sha256sum "$target" | cut -d' ' -f1)
[ "$actual" = "$expected" ] || {
    cp -p "$backup" "$target"
    echo "Installed agent hash mismatch; previous agent restored" >&2
    exit 1
}
echo "Ethernet agent now accepts status, AI, black-box and waveform operations only"
echo "Backup: $backup"
