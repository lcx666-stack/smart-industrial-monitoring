"""Four-channel DMA waveform display for the Windows controller.

The board sends 2 ms min/max envelopes of its 50 kHz ADC stream.  This is
live waveform data, not the slow PL status snapshot; each vertical stroke
preserves the extrema of all 100 raw samples in that interval.
"""

import collections
import json
import math
import os
import subprocess
import threading
import tkinter as tk


BOARD_STREAM = '/data/ethernet_control_20261014/board_wave_stream.py'
CHANNELS = ('电机电流 (mA)', '振动 X (ADC)', '振动 Y (ADC)', '振动 Z (ADC)')
COLORS = ('#e87a57', '#58c7d8', '#a58ce2', '#83c77d')
VIBRATION_COLORS = ('#24e7f2', '#ee8cff', '#78ff9a')
VIBRATION_FILLS = ('#173f47', '#40284a', '#173f2a')
CURRENT_TRIP_MA = 800
CURRENT_VIEW_MA = 1600
VIBRATION_TRIP_RAW = 7000
VIBRATION_MIN_VIEW_RAW = 256
VIBRATION_MAX_VIEW_RAW = 2048
THRESHOLD_COLOR = '#ff4d4f'


def display_current_interval(raw_bin):
    """Reverse only the GUI polarity; keep the board's raw interval intact."""
    return -raw_bin[1], -raw_bin[0]


def current_readout(latest_bin, live=True):
    """Describe the newest 2 ms envelope without claiming an instant sample."""
    if latest_bin is None:
        return '最新 2 ms：等待数据'
    label = '最新 2 ms' if live else '末次 2 ms（已停止）'
    low, high = display_current_interval(latest_bin)
    return '{}：{}～{} mA'.format(label, low, high)


def vibration_view(history, channel, maximum=VIBRATION_MAX_VIEW_RAW):
    """Return centre, auto-zoom range and visible peak deviation."""
    if not history:
        return 0, VIBRATION_MIN_VIEW_RAW, 0
    recent = list(history)[-min(100, len(history)):]
    centre = round(sum((row[2 * channel] + row[2 * channel + 1]) / 2
                       for row in recent) / len(recent))
    peak = max(max(abs(row[2 * channel] - centre),
                   abs(row[2 * channel + 1] - centre))
               for row in history)
    view = max(VIBRATION_MIN_VIEW_RAW,
               min(maximum, int(math.ceil(peak * 1.35))))
    return centre, view, peak


def parse_wave_packet(line):
    packet = json.loads(line)
    if packet.get('kind') != 'wave' or packet.get('bin_ms') != 2:
        raise ValueError('invalid waveform packet')
    columns = packet.get('bins')
    if not isinstance(columns, list) or len(columns) > 100:
        raise ValueError('invalid waveform bin count')
    for column in columns:
        if (not isinstance(column, list) or len(column) != 8 or
                any(type(v) is not int for v in column) or
                any(column[2 * i] > column[2 * i + 1] for i in range(4))):
            raise ValueError('invalid waveform sample')
    if type(packet.get('seq_gaps')) is not int or type(packet.get('dropped')) is not int:
        raise ValueError('missing waveform health counters')
    return packet


class WaveformWorker:
    def __init__(self, host, key_path, events):
        self.host = host
        self.key_path = key_path
        self.events = events
        self.process = None
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)

    def start(self):
        self.thread.start()

    def close(self):
        self.stop.set()
        if self.process is not None and self.process.poll() is None:
            try:
                self.process.terminate()
            except OSError:
                pass

    def run(self):
        flags = getattr(subprocess, 'CREATE_NO_WINDOW', 0) if os.name == 'nt' else 0
        argv = ['ssh', '-T', '-n', '-i', self.key_path,
                '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes',
                '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5',
                'root@' + self.host, 'python3', '-u', '-B', BOARD_STREAM]
        try:
            self.process = subprocess.Popen(argv, stdout=subprocess.PIPE,
                                            stderr=subprocess.PIPE, text=True,
                                            encoding='utf-8', errors='replace',
                                            bufsize=1, creationflags=flags)
            for line in self.process.stdout:
                if self.stop.is_set():
                    break
                packet = parse_wave_packet(line)
                self.events.put(('wave_packet', self, packet))
            if not self.stop.is_set():
                error = self.process.stderr.read()[-500:]
                self.events.put(('wave_error', self, error or '波形采集已结束'))
        except (OSError, ValueError, json.JSONDecodeError) as error:
            if not self.stop.is_set():
                self.events.put(('wave_error', self, str(error)))
        finally:
            if self.process is not None and self.process.poll() is None:
                try:
                    self.process.terminate()
                except OSError:
                    pass
            self.events.put(('wave_ended', self))


class WaveformPanel:
    """One-second rolling view; fixed channel ranges avoid visual autoscale jumps."""

    def __init__(self, parent, width=960, height=540):
        self.canvas = tk.Canvas(parent, width=width, height=height,
                                bg='#111820', highlightthickness=0)
        self.canvas.pack(anchor='nw')
        self.width, self.height = width, height
        self.history = collections.deque(maxlen=500)
        self.live = False
        self.current_range = CURRENT_VIEW_MA
        self.vibration_range = 2048
        self.draw()

    def resize(self, width, height):
        width, height = int(width), int(height)
        if (width, height) == (self.width, self.height):
            return
        self.width, self.height = width, height
        self.canvas.configure(width=width, height=height)
        self.draw()

    def add(self, packet):
        self.history.extend(packet['bins'])
        self.live = True
        self.draw()

    def mark_stopped(self):
        self.live = False
        self.draw()

    def draw(self):
        c = self.canvas
        c.delete('wave')
        row_h = self.height / 4
        for channel in range(4):
            top = channel * row_h
            mid = top + row_h / 2
            if channel:
                color = VIBRATION_COLORS[channel - 1]
                c.create_rectangle(0, top, self.width, top + row_h,
                                   fill='#0d141b' if channel % 2 else '#121c24',
                                   outline='', tags='wave')
            c.create_line(0, mid, self.width, mid, fill='#33414c', tags='wave')
            c.create_text(8, top + 8, anchor='nw', text=CHANNELS[channel],
                          fill=COLORS[channel] if channel == 0 else color,
                          font=('Microsoft YaHei UI', 12, 'bold'), tags='wave')
            if channel == 0:
                positive_y = mid - CURRENT_TRIP_MA * row_h * .45 / self.current_range
                negative_y = mid + CURRENT_TRIP_MA * row_h * .45 / self.current_range
                c.create_line(0, positive_y, self.width, positive_y,
                              fill=THRESHOLD_COLOR, width=2, dash=(8, 4), tags='wave')
                c.create_line(0, negative_y, self.width, negative_y,
                              fill=THRESHOLD_COLOR, width=2, dash=(8, 4), tags='wave')
                c.create_text(8, positive_y + 4, anchor='nw',
                              text='+{} mA'.format(CURRENT_TRIP_MA),
                              fill=THRESHOLD_COLOR, tags='wave')
                c.create_text(8, negative_y + 4, anchor='nw',
                              text='-{} mA'.format(CURRENT_TRIP_MA),
                              fill=THRESHOLD_COLOR, tags='wave')
                c.create_text(self.width - 8, top + 8, anchor='ne',
                              text=current_readout(self.history[-1] if self.history else None,
                                                   self.live),
                              fill=COLORS[channel], font=('Microsoft YaHei UI', 13, 'bold'),
                              tags='wave')
                c.create_text(self.width - 8, top + 34, anchor='ne',
                              text='PL 已设固定零点，未扣本次空载基线',
                              fill='#8c9ba6', tags='wave')
            scale = self.current_range
            centre = 0
            peak = 0
            # Vibration ADC readings are uncalibrated signed raw codes. Their
            # typical centre is measured from the visible rolling interval.
            if channel:
                centre, scale, peak = vibration_view(
                    self.history, channel, self.vibration_range)
            upper_points = []
            lower_points = []
            for index, sample in enumerate(self.history):
                x = self.width - len(self.history) + index
                low, high = sample[channel * 2:channel * 2 + 2]
                if channel == 0:
                    low, high = display_current_interval(sample)
                y1 = max(top + 3, min(top + row_h - 3,
                                      mid - (low - centre) * row_h * .45 / scale))
                y2 = max(top + 3, min(top + row_h - 3,
                                      mid - (high - centre) * row_h * .45 / scale))
                if channel:
                    crossing = max(abs(low - centre), abs(high - centre)) >= VIBRATION_TRIP_RAW
                    stroke = THRESHOLD_COLOR if crossing else color
                    c.create_line(x, y1, x, y2, fill=stroke, width=3, tags='wave')
                    upper_points.append((x, y2))
                    lower_points.append((x, y1))
                else:
                    c.create_line(x, y1, x, y2,
                                  fill=COLORS[channel], width=2, tags='wave')
            if channel:
                if len(upper_points) > 1:
                    polygon = upper_points + list(reversed(lower_points))
                    c.create_polygon([value for point in polygon for value in point],
                                     fill=VIBRATION_FILLS[channel - 1],
                                     outline='', tags='wave')
                    c.create_line([value for point in upper_points for value in point],
                                  fill=color, width=2, tags='wave')
                    c.create_line([value for point in lower_points for value in point],
                                  fill=color, width=1, tags='wave')
                threshold_y = mid - ((VIBRATION_TRIP_RAW - centre) *
                                     row_h * .45 / scale)
                visible_y = max(top + 3, min(top + row_h - 3, threshold_y))
                c.create_line(0, visible_y, self.width, visible_y,
                              fill=THRESHOLD_COLOR, width=2, dash=(8, 4), tags='wave')
                c.create_text(self.width - 8, visible_y - 4, anchor='se',
                              text='{} >= {} ADC'.format('XYZ'[channel - 1],
                                                        VIBRATION_TRIP_RAW),
                              fill=THRESHOLD_COLOR,
                              font=('Microsoft YaHei UI', 10, 'bold'), tags='wave')
                c.create_text(self.width - 8, top + 8, anchor='ne',
                              text='Δ峰值 {} · 自动纵轴 ±{} ADC'.format(
                                  peak, scale), fill=color,
                              font=('Microsoft YaHei UI', 10, 'bold'), tags='wave')
                c.create_text(self.width - 8, top + 31, anchor='ne',
                              text='中心 {}'.format(centre), fill='#a9bac7', tags='wave')

    def _centre(self, channel):
        return vibration_view(self.history, channel)[0]
