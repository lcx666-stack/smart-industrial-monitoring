"""Read-only viewer for verified, saved four-channel fault waveforms."""

import statistics
import struct
import tkinter as tk
from tkinter import ttk

from waveform_display import (CHANNELS, COLORS, CURRENT_TRIP_MA,
                              CURRENT_VIEW_MA, THRESHOLD_COLOR,
                              display_current_interval)

FRAME = struct.Struct('<hhhhIIQiI')
MAGIC = 0x314D5246


def event_envelope(binary, width=960):
    """Min/max each visual column, retaining short peaks in the 50 kHz data."""
    if not binary or len(binary) % FRAME.size or width <= 0:
        raise ValueError('invalid black-box waveform length')
    count = len(binary) // FRAME.size
    columns = [[None] * 8 for _ in range(min(width, count))]
    for index in range(count):
        frame = FRAME.unpack_from(binary, index * FRAME.size)
        if frame[8] != MAGIC or not frame[5] & 1:
            raise ValueError('invalid saved waveform frame at {}'.format(index))
        values = (frame[7], frame[1], frame[2], frame[3])
        column = columns[index * len(columns) // count]
        for channel, value in enumerate(values):
            low = channel * 2
            if column[low] is None or value < column[low]:
                column[low] = value
            if column[low + 1] is None or value > column[low + 1]:
                column[low + 1] = value
    return columns


class FaultHistoryWindow:
    def __init__(self, root, refresh, open_event):
        self.window = tk.Toplevel(root)
        self.window.title('黑匣子故障记录与波形')
        self.window.geometry('1020x800')
        self.refresh = refresh
        self.open_event = open_event
        self.info = tk.StringVar(value='请选择一条记录；波形从开发板经 SSH 读取并校验 SHA-256。')
        self.events = {}
        top = ttk.Frame(self.window, padding=8)
        top.pack(fill='both', expand=True)
        columns = ('time', 'code', 'saved', 'frames')
        self.tree = ttk.Treeview(top, columns=columns, show='headings', height=7)
        for column, title, size in (('time', '板端时间（UTC）', 245),
                                    ('code', '故障码', 250),
                                    ('saved', '保存状态', 140),
                                    ('frames', '帧数', 100)):
            self.tree.heading(column, text=title)
            self.tree.column(column, width=size)
        self.tree.pack(fill='x')
        buttons = ttk.Frame(top)
        buttons.pack(fill='x', pady=5)
        ttk.Button(buttons, text='刷新记录', command=refresh).pack(side='left')
        ttk.Button(buttons, text='查看选中故障波形', command=self.selected).pack(side='left', padx=8)
        ttk.Label(top, textvariable=self.info, wraplength=980).pack(anchor='w', pady=4)
        self.canvas = tk.Canvas(top, width=960, height=540, bg='#111820',
                                highlightthickness=0)
        self.canvas.pack(anchor='w')
        ttk.Label(top, text='红线为触发位置；每列保留该时间段内的最小/最大值。板端时钟尚未校准，时间仅供参考。',
                  foreground='#526474').pack(anchor='w', pady=4)

    def exists(self):
        return self.window.winfo_exists()

    def lift(self):
        self.window.lift()

    def selected(self):
        chosen = self.tree.selection()
        if chosen:
            self.info.set('正在读取并校验板端记录…')
            self.open_event(chosen[0])

    def set_events(self, events):
        previous = self.tree.selection()
        self.events = {event['id']: event for event in events}
        self.tree.delete(*self.tree.get_children())
        for event in events:
            saved = '不完整' if event.get('incomplete') else '已保存，待校验'
            self.tree.insert('', 'end', iid=event['id'],
                             values=(event.get('created_utc', ''), event.get('code', ''),
                                     saved, event.get('frame_count', 0)))
        if previous and previous[0] in self.events:
            self.tree.selection_set(previous[0])

    def set_error(self, message):
        self.info.set(message)

    def show_waveform(self, event, bins):
        count = event['frame_count']
        pre = event.get('pre_count')
        self.info.set('{} | {} | {} | {}帧 | {} | SHA-256 通过'.format(
            event.get('code', ''), event.get('reason', ''),
            event.get('created_utc', ''), count,
            '不完整' if event.get('incomplete') else '已保存'))
        canvas = self.canvas
        canvas.delete('all')
        width, height = 960, 540
        row_height = height / 4
        for channel in range(4):
            top = channel * row_height
            mid = top + row_height / 2
            canvas.create_line(0, mid, width, mid, fill='#33414c')
            canvas.create_text(8, top + 6, anchor='nw', text=CHANNELS[channel],
                               fill=COLORS[channel])
            if channel == 0:
                centre, scale = 0, CURRENT_VIEW_MA
                threshold = CURRENT_TRIP_MA * row_height * .45 / scale
                for y in (mid - threshold, mid + threshold):
                    canvas.create_line(0, y, width, y, fill=THRESHOLD_COLOR,
                                       dash=(8, 4))
            else:
                centre = round(statistics.median((b[2 * channel] + b[2 * channel + 1]) / 2
                                                 for b in bins))
                scale = max(2048, max(abs(v - centre) for b in bins
                                      for v in b[2 * channel:2 * channel + 2]))
            for x, sample in enumerate(bins):
                low, high = sample[channel * 2:channel * 2 + 2]
                if channel == 0:
                    low, high = display_current_interval((low, high))
                y_low = max(top + 3, min(top + row_height - 3,
                                         mid - (low - centre) * row_height * .45 / scale))
                y_high = max(top + 3, min(top + row_height - 3,
                                          mid - (high - centre) * row_height * .45 / scale))
                canvas.create_line(x, y_low, x, y_high, fill=COLORS[channel])
        if type(pre) is int and 0 <= pre < count:
            x = pre * width / count
            canvas.create_line(x, 0, x, height, fill=THRESHOLD_COLOR, width=2)
            canvas.create_text(x + 5, 3, anchor='nw', text='故障触发', fill=THRESHOLD_COLOR)
