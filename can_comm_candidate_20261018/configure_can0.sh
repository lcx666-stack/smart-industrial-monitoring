#!/bin/sh
# Run only after the candidate PS CAN0 -> J11 PL image is installed.
set -eu
if [ "${1:-}" != '--route-confirmed' ]; then
    echo 'Refusing: pass --route-confirmed only after CAN0 PL route is installed' >&2
    exit 2
fi
ip link set can0 down
# This ipms_canfd driver refuses to start without data-phase timing even when
# the application sends only classic eight-byte CAN frames.  The explicit
# nominal/data timing below matches the vendor's DR1M90 example and was
# confirmed to bring can0 UP on this board.  Application frames remain classic.
ip link set can0 type can tq 200 prop-seg 2 phase-seg1 5 phase-seg2 2 sjw 2 \
    dtq 20 dprop-seg 2 dphase-seg1 5 dphase-seg2 2 dsjw 2 \
    restart-ms 100 fd on
ip link set can0 up
ip -details link show can0
