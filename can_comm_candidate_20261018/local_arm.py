#!/usr/bin/env python3
"""One-shot local authorization for CAN motor start or fault clear.

Run on the board's physical serial console. It intentionally rejects SSH.
"""

import argparse
import json
import os
from pathlib import Path
import secrets
import time

ARM_FILE = Path('/data/ethernet_control_20261014/can-local-arm.json')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('motor_start', 'motor_clear'))
    args = parser.parse_args()
    if os.geteuid() != 0 or not os.isatty(0) or os.environ.get('SSH_CONNECTION'):
        parser.error('run as root on the physical board serial console')
    phrase = 'ARM MOTOR' if args.operation == 'motor_start' else 'CLEAR FAULT'
    answer = input('Confirm local inspection; type {}: '.format(phrase))
    if answer != phrase:
        parser.error('confirmation mismatch')
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    record = dict(operation=args.operation, boot_id=boot,
                  expires=time.time() + 30)
    ARM_FILE.parent.mkdir(mode=0o700, exist_ok=True)
    temp = ARM_FILE.with_name('can-local-arm-{}.tmp'.format(secrets.token_hex(8)))
    fd = os.open(str(temp), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, 'w') as output:
            json.dump(record, output)
            output.flush()
            os.fsync(output.fileno())
        os.replace(str(temp), str(ARM_FILE))
    finally:
        if temp.exists():
            temp.unlink()
    print('One {} CAN command may be accepted for 30 seconds'.format(args.operation))


if __name__ == '__main__':
    main()
