#!/usr/bin/env python3
"""Read completed black-box events over the existing authenticated SSH link.

This helper never opens the DMA device or changes motor/control state.  The
binary waveform stays on the board; ``fetch`` streams one bounded copy for
desktop verification and display.
"""

import argparse
import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path('/data/ethernet_control_20261014')
EVENT_ID = re.compile(r'^(wave-events|blackbox)-[0-9]+-[0-9a-f]{8}/event-[A-Za-z0-9_-]+$')
MAX_BINARY_BYTES = 16 * 1024 * 1024
MAX_EVENTS = 256


def paths(event_id, root=ROOT):
    if not EVENT_ID.fullmatch(event_id):
        raise ValueError('invalid event ID')
    directory, name = event_id.split('/')
    folder = root / directory
    metadata = folder / (name + '.json')
    binary = folder / (name + '.bin')
    if folder.is_symlink() or metadata.is_symlink() or binary.is_symlink():
        raise ValueError('event symlink refused')
    return metadata, binary


def read_event(event_id, root=ROOT):
    metadata_path, binary_path = paths(event_id, root)
    with metadata_path.open('r', encoding='utf-8') as source:
        metadata = json.load(source)
    count = metadata.get('frame_count')
    size = metadata.get('binary_bytes')
    if (metadata.get('format') != 'FRM1' or metadata.get('frame_bytes') != 32 or
            type(count) is not int or not 0 < count <= MAX_BINARY_BYTES // 32 or
            type(size) is not int or size != count * 32 or
            metadata.get('binary_file') != binary_path.name):
        raise ValueError('invalid event metadata')
    actual_size = binary_path.stat().st_size
    if actual_size != size:
        raise ValueError('event binary size mismatch')
    return metadata, binary_path


def alarm_code(reason):
    text = str(reason or '')
    codes = []
    for marker, code in (('PL motor fault', 'PL_MOTOR_FAULT'),
                         ('ADC error', 'ADC_ERROR'),
                         ('PL DMA frame loss', 'DMA_DROP'),
                         ('DMA dropped', 'DMA_DROP'),
                         ('waveform timestamp mismatch', 'TIMESTAMP_MISMATCH'),
                         ('waveform sequence gap', 'SEQ_GAP'),
                         ('current threshold', 'CURRENT_LIMIT'),
                         ('vibration threshold', 'VIBRATION_LIMIT'),
                         ('manual', 'MANUAL')):
        if marker.lower() in text.lower():
            codes.append(code)
    return '+'.join(codes) or 'OTHER_EVENT'


def event_summary(event_id, root=ROOT):
    metadata, _ = read_event(event_id, root)
    return {'id': event_id, 'code': alarm_code(metadata.get('reason')),
            'reason': str(metadata.get('reason', '')),
            'created_utc': str(metadata.get('created_utc', '')),
            'trigger_seq': metadata.get('trigger_seq'),
            'pre_count': metadata.get('pre_count'),
            'frame_count': metadata['frame_count'],
            'incomplete': bool(metadata.get('incomplete')),
            'binary_bytes': metadata['binary_bytes'],
            'binary_sha256': metadata.get('binary_sha256'),
            'saved': True}


def list_events(root=ROOT):
    candidates = []
    for pattern in ('wave-events-*', 'blackbox-*'):
        for folder in root.glob(pattern):
            if not folder.is_dir() or folder.is_symlink():
                continue
            for metadata in folder.glob('event-*.json'):
                if metadata.is_symlink():
                    continue
                event_id = folder.name + '/' + metadata.stem
                if EVENT_ID.fullmatch(event_id):
                    candidates.append((metadata.stat().st_mtime, event_id))
    candidates.sort(reverse=True)
    events = []
    for _, event_id in candidates[:MAX_EVENTS]:
        try:
            events.append(event_summary(event_id, root))
        except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
            # Writer publishes the JSON last; skip files still being completed.
            continue
    return events


def fetch(event_id, root=ROOT, output=None):
    metadata, binary_path = read_event(event_id, root)
    output = output or sys.stdout.buffer
    header = json.dumps(event_summary(event_id, root), ensure_ascii=False,
                        separators=(',', ':')).encode('utf-8')
    output.write(struct.pack('<I', len(header)))
    output.write(header)
    with binary_path.open('rb') as source:
        while True:
            block = source.read(65536)
            if not block:
                break
            output.write(block)
    output.flush()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('list', 'fetch'))
    parser.add_argument('event_id', nargs='?')
    args = parser.parse_args()
    if args.operation == 'list':
        if args.event_id:
            parser.error('list takes no event ID')
        print(json.dumps({'events': list_events()}, ensure_ascii=False))
    else:
        if not args.event_id:
            parser.error('fetch requires an event ID')
        fetch(args.event_id)


if __name__ == '__main__':
    main()
