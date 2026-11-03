"""Windows desktop dashboard: board NPU video, quick actions, and root SSH."""

import argparse
import concurrent.futures
import ipaddress
import json
import os
from pathlib import Path
import queue
import re
import socket
import subprocess
import sys
import threading
import time
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk

from PIL import Image, ImageDraw, ImageTk

from control_client import ControlClient
from fault_history import FaultHistoryWindow, event_envelope
from video_protocol import HEIGHT, WIDTH, read_packet
from waveform_display import WaveformPanel, WaveformWorker

ROI_REPORT = re.compile(r"(?:^|\n)BOARD_AI roi=(\d+),(\d+),(\d+),(\d+)(?:\s|$)")

BG = '#edf2f7'
WHITE = '#ffffff'
INK = '#192b3c'
MUTED = '#53677a'
ACCENT = '#1767b3'
RED = '#b52b39'
GREEN = '#1d7a46'
BORDER = '#d7e1eb'


def configure_dashboard_style(root):
    """Use one readable palette for native Tk and ttk controls."""
    root.configure(bg=BG)
    style = ttk.Style(root)
    style.theme_use('clam')
    style.configure('.', font=('Microsoft YaHei UI', 10), background=BG,
                    foreground=INK)
    style.configure('App.TFrame', background=BG)
    style.configure('Card.TFrame', background=WHITE)
    style.configure('Card.TLabel', background=WHITE, foreground=INK)
    style.configure('Muted.Card.TLabel', background=WHITE, foreground=MUTED)
    style.configure('Section.TLabel', background=WHITE, foreground=INK,
                    font=('Microsoft YaHei UI', 11, 'bold'))
    style.configure('Header.TFrame', background='#14283b')
    style.configure('HeaderTitle.TLabel', background='#14283b', foreground=WHITE,
                    font=('Microsoft YaHei UI', 18, 'bold'))
    style.configure('HeaderSub.TLabel', background='#14283b', foreground='#b7cadc')
    style.configure('Note.TLabel', background=BG, foreground=MUTED)
    style.configure('Safety.TLabel', background=BG, foreground=RED,
                    font=('Microsoft YaHei UI', 10, 'bold'))
    style.configure('TButton', background=WHITE, foreground=INK,
                    bordercolor=BORDER, lightcolor=BORDER, darkcolor=BORDER,
                    padding=(10, 6), relief='flat')
    style.map('TButton', background=[('active', '#e7eff8')],
              foreground=[('disabled', '#8898a8')])
    for name, base, hover in (('Primary', ACCENT, '#10548f'),
                              ('Danger', RED, '#93212e')):
        style.configure(name + '.TButton', background=base, foreground=WHITE,
                        bordercolor=base, lightcolor=base, darkcolor=base,
                        padding=(10, 6), relief='flat')
        style.map(name + '.TButton', background=[('active', hover)],
                  foreground=[('active', WHITE), ('disabled', '#8898a8')])
    style.configure('TNotebook', background=BG, borderwidth=0)
    style.configure('TNotebook.Tab', background='#dfe8f1', foreground=MUTED,
                    padding=(18, 8), borderwidth=0)
    style.map('TNotebook.Tab', background=[('selected', WHITE),
                                            ('active', '#e9f1fa')],
              foreground=[('selected', ACCENT), ('active', INK)])
    style.configure('Card.TLabelframe', background=WHITE, bordercolor=BORDER)
    style.configure('Card.TLabelframe.Label', background=WHITE, foreground=INK,
                    font=('Microsoft YaHei UI', 10, 'bold'))
    style.configure('Treeview', background=WHITE, fieldbackground=WHITE,
                    foreground=INK, rowheight=27, borderwidth=0)
    style.map('Treeview', background=[('selected', '#d7eafa')],
              foreground=[('selected', INK)])
    style.configure('Treeview.Heading', background='#e9f0f7', foreground=INK,
                    font=('Microsoft YaHei UI', 10, 'bold'), relief='flat')
    style.configure('TEntry', fieldbackground=WHITE, foreground=INK)


def roi_from_board_log(log):
    """Only display an ROI after the board reports its active crop geometry."""
    matches = ROI_REPORT.findall(log)
    if not matches:
        return None
    x, y, width, height = map(int, matches[-1])
    if width <= 0 or height <= 0 or x + width > WIDTH or y + height > HEIGHT:
        return None
    return x, y, width, height


def format_can_alarm_status(data):
    """Format live service, pairing, and CAN bus state."""
    service = data.get('service') if isinstance(data, dict) else None
    pairing = data.get('pairing') if isinstance(data, dict) else None
    can = data.get('can') if isinstance(data, dict) else None
    service = service if isinstance(service, dict) else {}
    pairing = pairing if isinstance(pairing, dict) else {}
    can = can if isinstance(can, dict) else {}

    active_state = str(service.get('active_state') or 'unknown')
    sub_state = str(service.get('sub_state') or 'unknown')
    if can.get('available'):
        speed = int(can.get('bitrate') or 0) // 1000
        bus = 'CAN0 {} / {} kbit/s；收 {} / 发 {}；总线错误 {}'.format(
            can.get('state', 'UNKNOWN'), speed,
            int(can.get('rx_packets') or 0),
            int(can.get('tx_packets') or 0),
            int(can.get('bus_errors') or 0))
    else:
        bus = 'CAN0 不可读：{}'.format(can.get('error') or '接口不可用')

    if active_state != 'active':
        return 'STM32 报警通道：主板 CAN 服务 {} / {}；{}'.format(
            active_state, sub_state, bus), RED
    if pairing.get('paired'):
        nonce = pairing.get('nonce')
        return 'STM32 报警通道：已配对{}；服务 active / {}；{}'.format(
            '，nonce=' + str(nonce) if nonce else '',
            sub_state, bus), GREEN
    if pairing.get('known') is False:
        return 'STM32 报警通道：服务 active / {}；配对状态不可读；{}'.format(
            sub_state, bus), RED
    return ('STM32 报警通道：服务 active / {}；等待 STM32 复位配对；{}'
            ).format(sub_state, bus), ACCENT


def latest_put(items, value):
    try:
        items.put_nowait(value)
    except queue.Full:
        try:
            items.get_nowait()
        except queue.Empty:
            pass
        items.put_nowait(value)


class VideoWorker:
    def __init__(self, host, events, frames):
        self.host = host
        self.events = events
        self.frames = frames
        self.stop = threading.Event()
        self.connection = None
        self.thread = threading.Thread(target=self.run, daemon=True)

    def start(self):
        self.thread.start()

    def close(self):
        self.stop.set()
        connection = self.connection
        if connection is not None:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()

    def run(self):
        for attempt in range(15):
            if self.stop.is_set():
                return
            try:
                connection = socket.create_connection((self.host, 5000), timeout=1)
                break
            except OSError:
                time.sleep(0.4)
        else:
            self.events.put(("video_error", "6 秒内未连接到板端视频端口 5000"))
            self.events.put(("video_ended", self))
            return
        self.connection = connection
        previous = 0
        try:
            with connection:
                connection.settimeout(10)
                self.events.put(("video_connected", "板端视频已连接"))
                while not self.stop.is_set():
                    packet = read_packet(connection)
                    if packet[0] != previous + 1:
                        raise ValueError("视频帧序号跳变")
                    previous = packet[0]
                    latest_put(self.frames, (time.monotonic(), packet))
        except (OSError, ConnectionError, ValueError) as error:
            if not self.stop.is_set():
                self.events.put(("video_error", str(error)))
        finally:
            self.connection = None
            self.events.put(("video_ended", self))


class CanStatusWorker:
    """Keep one SSH stream open so live CAN state does not re-handshake."""

    def __init__(self, client, events, interval_ms=500):
        self.client = client
        self.events = events
        self.interval_ms = interval_ms
        self.stop = threading.Event()
        self.process = None
        self.thread = threading.Thread(target=self.run, daemon=True)

    def start(self):
        self.thread.start()

    def close(self):
        self.stop.set()
        process = self.process
        if process is not None:
            try:
                process.terminate()
                process.wait(timeout=2)
            except (OSError, subprocess.SubprocessError):
                try:
                    process.kill()
                except OSError:
                    pass

    def run(self):
        while not self.stop.is_set():
            try:
                process = self.client.open_can_alarm_stream(self.interval_ms)
            except OSError as error:
                self.events.put(('can_alarm_stream_error', self, str(error)))
                self.stop.wait(1.0)
                continue
            self.process = process
            try:
                if process.stdout is not None:
                    for line in process.stdout:
                        if self.stop.is_set():
                            break
                        try:
                            data = json.loads(line)
                        except (TypeError, ValueError):
                            continue
                        if isinstance(data, dict) and data.get('ok') is True:
                            self.events.put(('can_alarm_status', self, data))
            except (OSError, ValueError) as error:
                if not self.stop.is_set():
                    self.events.put(('can_alarm_stream_error', self, str(error)))
            finally:
                self.process = None
                try:
                    process.wait(timeout=2)
                except (OSError, subprocess.SubprocessError):
                    process.kill()
            if not self.stop.is_set():
                self.stop.wait(1.0)
        self.events.put(('can_alarm_stream_ended', self))


class Dashboard:
    # One SSH round trip per request is unavoidable on Windows OpenSSH, so the
    # authoritative state is refreshed often and every command also updates the
    # panel immediately instead of waiting for the next poll.
    STATUS_POLL_MS = 1200
    CAN_STATUS_STREAM_MS = 500

    def __init__(self, root, host):
        self.root = root
        root.title("CS500 整机控制台 — 板载 NPU 推理")
        root.geometry("1360x840")
        root.minsize(1180, 690)
        configure_dashboard_style(root)
        self.host = tk.StringVar(value=host)
        self.key_path = tk.StringVar(value=os.path.join(os.path.expanduser("~"),
                                                       ".ssh", "fan_board_ed25519"))
        self.connection_text = tk.StringVar(value="控制未连接")
        self.pending_text = tk.StringVar(value="")
        self.timing_text = tk.StringVar(value="")
        self.video_text = tk.StringVar(value="视频未启动")
        self.frame_text = tk.StringVar(value="帧：—  FPS：—  NPU 帧龄：—  框：—")
        self.pl_text = tk.StringVar(value="PL：—  守护：—  故障：—  占空比：—")
        self.ai_text = tk.StringVar(value="板端 AI：—")
        self.blackbox_text = tk.StringVar(value="黑匣子：—")
        self.alarm_live_text = tk.StringVar(value="板端故障：等待连接")
        self.alarm_text = tk.StringVar(value="故障记录：等待连接")
        self.can_alarm_text = tk.StringVar(value="STM32 报警通道：连接板端后读取实时状态")
        self.motor_text = tk.StringVar(value="电机状态：等待以太网连接")
        self.alarm_events = []
        self.alarm_seen = set()
        self.alarm_initialized = False
        self.alarm_pending = False
        self.last_board_fault = None
        self.alarm_window = None
        self.closed = False
        self.control = None
        self.video = None
        self.video_window = None
        self.wave = None
        self.wave_view_wanted = False
        self.wave_start_pending = False
        self.wave_text = tk.StringVar(value="四路实时波形未启动；采样源为板端 ADC DMA")
        self.ai_wanted = False
        self.ai_start_pending = False
        self.ai_waiting_for_ethernet_stop = False
        self.ai_stop_command_done = False
        self.ai_stop_requested_at = 0.0
        self.ai_stop_deadline = 0.0
        self.events = queue.Queue()
        self.frames = queue.Queue(maxsize=1)
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=3)
        self.last_frame_time = None
        self.estimated_fps = None
        self.latest_status = None
        self.latest_status_at = 0.0
        self.motor_duty = tk.IntVar(value=15)
        self.active_roi = None
        self.status_pending = False
        self.can_status_worker = None
        self.last_can_alarm_state = None
        self.pending_ops = 0
        self._build()
        root.protocol("WM_DELETE_WINDOW", self.close)
        root.after(40, self.refresh)
        root.after(1000, self.poll_status)
        root.after(1800, self.poll_alarm)

    def _build(self):
        main = ttk.Frame(self.root, padding=12, style='App.TFrame')
        main.pack(fill="both", expand=True)
        main.columnconfigure(0, weight=1)
        main.columnconfigure(1, weight=0)
        main.rowconfigure(1, weight=1)
        header = ttk.Frame(main, style='Header.TFrame', padding=(18, 12))
        header.grid(row=0, column=0, columnspan=2, sticky='ew', pady=(0, 12))
        ttk.Label(header, text='CS500  整机控制台', style='HeaderTitle.TLabel').pack(anchor='w')
        ttk.Label(header, text='实时波形  ·  以太网控制  ·  CAN 故障报警至 STM32',
                  style='HeaderSub.TLabel').pack(anchor='w', pady=(2, 0))
        left = ttk.Frame(main, style='App.TFrame')
        left.grid(row=1, column=0, sticky="nsew")
        self.views = ttk.Notebook(left)
        self.views.pack(fill='both', expand=True)
        wave_tab = ttk.Frame(self.views, style='Card.TFrame', padding=8)
        can_tab = ttk.Frame(self.views, style='Card.TFrame', padding=16)
        self.views.add(wave_tab, text='实时波形')
        self.views.add(can_tab, text='电机控制与 STM32 报警')
        # Leave room inside the notebook for the action row and status labels.
        # A 540 px canvas caused Tk to squeeze the buttons below their text height.
        self.wave_panel = WaveformPanel(wave_tab, WIDTH, 420)
        wave_buttons = ttk.Frame(wave_tab, style='Card.TFrame')
        wave_buttons.pack(fill="x", pady=(8, 0))
        ttk.Button(wave_buttons, text="启动四路实时波形", style='Primary.TButton',
                   command=self.start_wave).pack(side="left")
        ttk.Button(wave_buttons, text="隐藏波形", command=self.stop_wave).pack(side="left", padx=8)
        ttk.Button(wave_buttons, text="停止板端监测", command=self.stop_wave_service).pack(side="left")
        wave_status = ttk.Label(wave_tab, textvariable=self.wave_text,
                                style='Card.TLabel')
        wave_status.pack(anchor="w", pady=(8, 0))
        wave_info = ttk.Label(
            wave_tab, text="每列为 2 ms 内 100 个 ADC 原始采样的最小/最大值；振动为原始 ADC 码值。",
            style='Muted.Card.TLabel')
        wave_info.pack(anchor="w", pady=(3, 0))

        def fit_wave(_event):
            reserved = (wave_buttons.winfo_reqheight() + wave_status.winfo_reqheight() +
                        wave_info.winfo_reqheight() + 43)
            self.wave_panel.resize(
                min(WIDTH, max(320, wave_tab.winfo_width() - 16)),
                min(420, max(180, wave_tab.winfo_height() - reserved)))

        wave_tab.bind('<Configure>', fit_wave)

        ethernet_motor = ttk.LabelFrame(
            can_tab, text='以太网电机控制', style='Card.TLabelframe', padding=10)
        ethernet_motor.pack(fill='x', pady=(0, 14))
        for column in range(6):
            ethernet_motor.columnconfigure(column, weight=1)
        ttk.Label(ethernet_motor, text='占空比目标 (%)', style='Card.TLabel').grid(
            row=0, column=0, sticky='w', padx=4, pady=4)
        ttk.Spinbox(ethernet_motor, from_=10, to=60, increment=5,
                    textvariable=self.motor_duty, width=8).grid(
            row=0, column=1, sticky='ew', padx=4, pady=4)
        ttk.Button(ethernet_motor, text='启动电机', style='Primary.TButton',
                   command=self.start_motor).grid(row=0, column=2, sticky='ew', padx=4, pady=4)
        ttk.Button(ethernet_motor, text='应用运行占空比',
                   command=self.set_motor_duty).grid(row=0, column=3, sticky='ew', padx=4, pady=4)
        ttk.Button(ethernet_motor, text='正常停机',
                   command=lambda: self.command('motor_stop')).grid(
            row=0, column=4, sticky='ew', padx=4, pady=4)
        ttk.Button(ethernet_motor, text='锁存停机', style='Danger.TButton',
                   command=self.emergency_stop_motor).grid(
            row=0, column=5, sticky='ew', padx=4, pady=4)
        ttk.Button(ethernet_motor, text='清除故障锁存',
                   command=self.clear_motor_fault).grid(
            row=1, column=0, columnspan=2, sticky='ew', padx=4, pady=4)
        ttk.Label(ethernet_motor, textvariable=self.motor_text,
                  style='Card.TLabel').grid(row=1, column=2, columnspan=4,
                                            sticky='w', padx=8, pady=4)

        ttk.Label(can_tab, text='STM32 故障报警通道', style='Section.TLabel').pack(anchor='w')
        self.can_alarm_label = ttk.Label(
            can_tab, textvariable=self.can_alarm_text, style='Card.TLabel',
            foreground=INK, wraplength=820)
        self.can_alarm_label.pack(anchor='w', pady=(10, 6))
        ttk.Label(can_tab,
                  text='目标链路：板端通过 CAN0 向 STM32 发送故障码，STM32 收到后驱动蜂鸣器。'
                       '本机控制台不再占用 USB-CAN，电机和板端操作统一走 SSH/以太网。'
                       '下方状态每 0.5 秒从主板实时读取。',
                  style='Muted.Card.TLabel', wraplength=820).pack(anchor='w', pady=(0, 12))
        ttk.Label(can_tab,
                  text='当前约定：经典 CAN，500 kbit/s，11 位标准帧；报警 ID 0x180，'
                       '确认 ID 0x280。详细字段见 can_comm_candidate_20261018/STM32_CAN_ALARM_PROTOCOL.md。',
                  style='Muted.Card.TLabel', wraplength=820).pack(anchor='w', pady=(0, 14))
        ttk.Button(can_tab, text='查看故障记录与波形', style='Primary.TButton',
                   command=self.open_fault_history).pack(anchor='w')
        right_outer = ttk.Frame(main, width=320, height=HEIGHT, style='Card.TFrame')
        right_outer.grid(row=1, column=1, sticky="ns", padx=(14, 0))
        right_outer.grid_propagate(False)
        right_canvas = tk.Canvas(right_outer, width=300, height=HEIGHT,
                                 bg=WHITE, highlightthickness=0)
        right_scroll = ttk.Scrollbar(right_outer, orient="vertical", command=right_canvas.yview)
        right_canvas.configure(yscrollcommand=right_scroll.set)
        right_canvas.pack(side="left", fill="both", expand=True)
        right_scroll.pack(side="right", fill="y")
        right = ttk.Frame(right_canvas, style='Card.TFrame')
        right_window = right_canvas.create_window((0, 0), window=right, anchor="nw")
        right.bind("<Configure>", lambda _: right_canvas.configure(
            scrollregion=right_canvas.bbox("all")))
        right_canvas.bind("<Configure>", lambda event: right_canvas.itemconfigure(
            right_window, width=event.width))
        def group(title):
            section = ttk.LabelFrame(right, text=title, style='Card.TLabelframe',
                                     padding=(9, 8))
            section.pack(fill='x', padx=8, pady=(9, 0))
            return section

        connection = group('板端连接')
        ttk.Label(connection, text="开发板 IP", style='Card.TLabel').pack(anchor="w")
        ttk.Entry(connection, textvariable=self.host).pack(fill="x", pady=(3, 0))
        ttk.Label(connection, text="SSH 私钥（仅在电脑使用）",
                  style='Card.TLabel').pack(anchor="w", pady=(8, 0))
        key_row = ttk.Frame(connection, style='Card.TFrame')
        key_row.pack(fill="x")
        ttk.Entry(key_row, textvariable=self.key_path, width=27).pack(side="left", fill="x", expand=True)
        ttk.Button(key_row, text="浏览", width=5, command=self.choose_key).pack(side="right")
        ttk.Button(connection, text="连接板端 SSH", style='Primary.TButton',
                   command=self.connect).pack(fill="x", pady=(8, 0))
        ttk.Button(connection, text="打开完整 root SSH 终端", command=self.open_root_terminal).pack(
            fill="x", pady=(2, 0))
        ttk.Label(connection, textvariable=self.connection_text, style='Card.TLabel',
                  wraplength=260).pack(anchor="w", pady=(6, 0))
        ttk.Label(connection, textvariable=self.pending_text, style='Card.TLabel',
                  foreground=RED, wraplength=260).pack(anchor="w")
        ttk.Label(connection, textvariable=self.timing_text, style='Muted.Card.TLabel',
                  wraplength=260).pack(anchor="w")

        ai_group = group('板载 AI')
        ttk.Button(ai_group, text="启动 AI 预览", style='Primary.TButton',
                   command=self.start_ai).pack(fill="x", pady=2)
        ttk.Button(ai_group, text="停止 AI 预览", command=self.stop_ai).pack(fill="x", pady=2)
        ttk.Label(ai_group, textvariable=self.ai_text, style='Card.TLabel',
                  wraplength=260).pack(anchor="w", pady=(5, 0))

        blackbox_group = group('黑匣子与报警')
        ttk.Button(blackbox_group, text="标记事件 / 单次采集", command=lambda: self.command("blackbox_start")).pack(
            fill="x", pady=2)
        ttk.Label(blackbox_group, textvariable=self.blackbox_text, style='Card.TLabel',
                  wraplength=260).pack(anchor="w", pady=(4, 6))
        ttk.Button(blackbox_group, text="查看故障记录与波形", style='Primary.TButton',
                   command=self.open_fault_history).pack(
            fill="x", pady=2)
        ttk.Label(blackbox_group, textvariable=self.alarm_live_text,
                  style='Card.TLabel', foreground=RED,
                  wraplength=260).pack(anchor="w", pady=(5, 2))
        ttk.Label(blackbox_group, textvariable=self.alarm_text,
                  style='Card.TLabel', wraplength=260).pack(anchor="w", pady=(0, 5))
        self.can_alarm_side_label = ttk.Label(
            blackbox_group, textvariable=self.can_alarm_text,
            style='Card.TLabel', foreground=INK, wraplength=260)
        self.can_alarm_side_label.pack(anchor="w", pady=(0, 5))
        ttk.Label(blackbox_group, text="事件时间来自板端时钟；日志记录电脑接收时间。",
                  style='Muted.Card.TLabel', wraplength=260).pack(anchor="w")
        diagnostics = group('PL 状态')
        ttk.Label(diagnostics, textvariable=self.pl_text,
                  style='Card.TLabel', wraplength=260).pack(anchor="w")
        ttk.Label(main, text="提示：电脑不推理；电机命令不由识别框触发。网络 STOP 不能替代物理断电。",
                  style='Safety.TLabel').grid(row=2, column=0, columnspan=2,
                                              sticky="w", pady=(10, 5))
        log_section = ttk.Frame(main, style='Card.TFrame', padding=(10, 6))
        log_section.grid(row=3, column=0, columnspan=2, sticky='ew')
        ttk.Label(log_section, text='运行日志', style='Section.TLabel').pack(anchor='w')
        self.log = scrolledtext.ScrolledText(
            log_section, height=4, state="disabled", wrap="word", borderwidth=0,
            font=('Microsoft YaHei UI', 10), bg=WHITE, fg=INK,
            insertbackground=INK)
        self.log.pack(fill='x', pady=(4, 0))

    def write_log(self, line):
        self.log.configure(state="normal")
        self.log.insert("end", time.strftime("%H:%M:%S ") + str(line) + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def run_control(self, label, operation):
        def work():
            started = time.monotonic()
            try:
                result = operation()
                self.events.put(("control_result", label, result,
                                 time.monotonic() - started))
            except Exception as error:
                self.events.put(("control_error", label, str(error),
                                 time.monotonic() - started))
        self.pool.submit(work)

    def choose_key(self):
        chosen = filedialog.askopenfilename(title="选择 OpenSSH 私钥")
        if chosen:
            self.key_path.set(chosen)

    def finish_pending(self, label, elapsed):
        self.pending_ops = max(0, self.pending_ops - 1)
        self.pending_text.set("" if self.pending_ops == 0 else "命令执行中…")
        if elapsed is None:
            return
        if label == "status":
            # The poll runs continuously; show its cost quietly instead of
            # filling the log with a line every second.
            self.timing_text.set("状态往返 {:.2f}s".format(elapsed))
        else:
            self.write_log("← {} 返回（{:.1f}s）".format(label, elapsed))

    def open_root_terminal(self):
        if self.control is None:
            messagebox.showwarning("SSH 未连接", "先验证 SSH 连接。")
            return
        try:
            host = str(ipaddress.IPv4Address(self.host.get().strip()))
            argv = ['ssh', '-tt', '-i', self.key_path.get().strip(),
                    '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=yes',
                    'root@' + host]
            subprocess.Popen(argv, creationflags=getattr(subprocess, 'CREATE_NEW_CONSOLE', 0))
            self.write_log("已打开完整 root SSH 终端；该终端不受快捷按钮参数限制")
        except (OSError, ValueError) as error:
            messagebox.showerror("SSH 终端启动失败", str(error))

    def connect(self):
        if self.control is not None:
            self.write_log("控制通道已经连接")
            return
        host, key_path = self.host.get().strip(), self.key_path.get().strip()
        if not host or not key_path:
            messagebox.showwarning("缺少配置", "请填写开发板 IP 并选择 SSH 私钥。")
            return
        self.connection_text.set("正在验证 SSH 主机和密钥…")
        self.run_control("connect", lambda: ControlClient(host, key_path))

    def command(self, op, **fields):
        if self.control is None:
            self.write_log("SSH 未连接；先连接开发板")
            return
        self.pending_ops += 1
        self.pending_text.set("命令执行中：{}".format(op))
        self.write_log("→ {} 已发送".format(op))
        self.run_control(op, lambda: self.control.request(op, **fields))

    def _duty_value(self):
        try:
            duty = int(self.motor_duty.get())
        except (TypeError, ValueError, tk.TclError):
            raise ValueError('占空比请输入 10 到 60 的整数')
        if not 10 <= duty <= 60:
            raise ValueError('占空比必须在 10 到 60 之间')
        return duty

    def start_motor(self):
        if self.control is None:
            messagebox.showwarning('SSH 未连接', '先连接板端，再启动电机。')
            return
        try:
            duty = self._duty_value()
        except ValueError as error:
            messagebox.showwarning('占空比无效', str(error))
            return
        message = ('将通过以太网以 {}% 占空比启动电机。请确认电机固定、传感器接线正确、'
                   '现场可立即断开 12 V VM。继续吗？').format(duty)
        if messagebox.askyesno('确认启动电机', message, icon='warning'):
            self.command('motor_start', operator_confirmed=True, duty_percent=duty)

    def set_motor_duty(self):
        if self.control is None:
            messagebox.showwarning('SSH 未连接', '先连接板端，再调整运行占空比。')
            return
        try:
            duty = self._duty_value()
        except ValueError as error:
            messagebox.showwarning('占空比无效', str(error))
            return
        if messagebox.askyesno('确认调整占空比',
                               '通过以太网将运行目标占空比调整到 {}%？'.format(duty),
                               icon='warning'):
            self.command('motor_set_duty', operator_confirmed=True,
                         duty_percent=duty)

    def emergency_stop_motor(self):
        if self.control is None:
            messagebox.showwarning('SSH 未连接', '无法发送锁存停机命令；必要时立即物理断电。')
            return
        if messagebox.askyesno('确认锁存停机',
                               '通过以太网请求 PL 锁存停机。确认电机需要立即锁存停止？',
                               icon='warning'):
            self.command('motor_estop', operator_confirmed=True)

    def clear_motor_fault(self):
        if self.control is None:
            messagebox.showwarning('SSH 未连接', '先连接板端，再清除故障锁存。')
            return
        if messagebox.askyesno('确认清除故障',
                               '仅在电机已停止并检查完故障原因后清除锁存。继续吗？',
                               icon='warning'):
            self.command('motor_clear', operator_confirmed=True)

    def open_ai_window(self):
        if self.video_window is not None and self.video_window.winfo_exists():
            self.video_window.lift()
            return
        window = tk.Toplevel(self.root)
        window.title("CS500 板端 AI 识别")
        window.geometry("990x630")
        window.protocol("WM_DELETE_WINDOW", self.stop_ai)
        self.video_window = window
        self.canvas = tk.Canvas(window, width=WIDTH, height=HEIGHT,
                                bg="#111820", highlightthickness=0)
        self.canvas.pack(anchor="nw", padx=10, pady=8)
        self.image_item = self.canvas.create_image(0, 0, anchor="nw")
        self.roi_item = self.canvas.create_rectangle(
            0, 0, 0, 0, outline="#ffd400", width=2, dash=(9, 5), state="hidden")
        self.roi_label = self.canvas.create_text(
            0, 0, anchor="sw", text="NPU ROI", fill="#ffd400",
            font=("Microsoft YaHei UI", 11, "bold"), state="hidden")
        self.active_roi = None
        ttk.Label(window, textvariable=self.frame_text).pack(anchor="w", padx=10)
        ttk.Label(window, textvariable=self.video_text).pack(anchor="w", padx=10)
        ttk.Label(window, text="黄色虚线：板端 NPU ROI    绿色框：缺陷识别结果").pack(anchor="w", padx=10)

    def start_wave(self):
        if self.control is None:
            self.wave_text.set("先连接板端 SSH，再启动 ADC DMA 波形")
            return
        if self.wave is not None or self.wave_start_pending:
            return
        self.wave_view_wanted = True
        self.wave_start_pending = True
        self.wave_text.set("正在启动/连接板端单一 DMA 采集服务；故障事件同时写入板端黑匣子")
        self.command('wave_start')

    def stop_wave(self):
        self.wave_view_wanted = False
        if self.wave is not None:
            self.wave.close()
            self.wave = None
        self.wave_panel.mark_stopped()
        self.wave_text.set("波形窗口已隐藏；板端故障黑匣子仍在监测")

    def stop_wave_service(self):
        if not messagebox.askyesno("停止板端监测", "这会停止实时 ADC 和自动故障前后帧保存。确定停止吗？"):
            return
        self.stop_wave()
        self.command('wave_stop')

    def start_ai(self):
        if self.control is None:
            self.write_log("SSH 未连接；先连接开发板")
            return
        if self.ai_start_pending:
            self.open_ai_window()
            self.write_log("AI 预览启动流程正在处理")
            return
        if self.ai_wanted or self.video is not None:
            self.open_ai_window()
            self.write_log("预览已经启动")
            return
        if self.latest_status is None:
            self.poll_now()
            messagebox.showwarning('状态未就绪', '正在读取板端状态，请稍后再启动 AI。')
            return
        if time.monotonic() - self.latest_status_at > 3.5:
            self.poll_now()
            messagebox.showwarning('状态已过期', '正在刷新板端电机状态，请稍后再启动 AI。')
            return
        self.ai_wanted = True
        ethernet_running = bool((self.latest_status or {}).get('motor_running'))
        if ethernet_running:
            if not messagebox.askyesno(
                    'AI 启动前停止电机',
                    '检测到电机正在运行。现在通过以太网发送正常停机，'
                    '并在板端状态确认停止后启动 AI？', icon='warning'):
                self.ai_wanted = False
                return
            self.ai_stop_requested_at = time.monotonic()
            self.ai_start_pending = True
            self.ai_waiting_for_ethernet_stop = True
            self.ai_stop_command_done = False
            self.ai_stop_deadline = self.ai_stop_requested_at + 8.0
            self.video_text.set("已通过以太网请求正常停机，等待板端确认…")
            self.open_ai_window()
            self.write_log('AI 启动前检测到电机运行，已通过以太网请求正常停机')
            self.command('motor_stop')
            self.root.after(100, self._check_ethernet_stop_before_ai)
            return
        self._launch_ai()

    def _launch_ai(self):
        self.ai_waiting_for_ethernet_stop = False
        self.ai_stop_command_done = False
        self.ai_start_pending = True
        self.video_text.set("正在启动板端 AI…")
        self.open_ai_window()
        self.command("ai_start")

    def _check_ethernet_stop_before_ai(self):
        if not self.ai_waiting_for_ethernet_stop:
            return
        status_confirmed = bool(
            self.latest_status_at >= self.ai_stop_requested_at and
            not (self.latest_status or {}).get('motor_running'))
        if self.ai_stop_command_done and status_confirmed:
            if not self.ai_wanted:
                self.ai_waiting_for_ethernet_stop = False
                self.ai_start_pending = False
                return
            self.write_log('以太网正常停机及板端停止状态已确认，开始启动 AI')
            self._launch_ai()
            return
        if time.monotonic() >= self.ai_stop_deadline:
            self._cancel_ai_after_ethernet_stop('未通过以太网确认电机停止；AI 未启动')
            return
        if not self.status_pending:
            self.poll_now()
        self.root.after(100, self._check_ethernet_stop_before_ai)

    def _cancel_ai_after_ethernet_stop(self, reason):
        self.ai_waiting_for_ethernet_stop = False
        self.ai_start_pending = False
        self.ai_wanted = False
        self.video_text.set(reason)
        if self.video_window is not None:
            self.video_window.destroy()
            self.video_window = None
            self.active_roi = None
        self.write_log(reason)
        messagebox.showerror('AI 启动已取消', reason)

    def stop_ai(self):
        self.ai_wanted = False
        was_waiting_for_ethernet_stop = self.ai_waiting_for_ethernet_stop
        if self.ai_waiting_for_ethernet_stop:
            self.ai_waiting_for_ethernet_stop = False
            self.ai_start_pending = False
            self.video_text.set('AI 启动已取消；以太网停机命令仍在执行')
        if self.video is not None:
            self.video.close()
            self.video = None
        if self.video_window is not None:
            self.video_window.destroy()
            self.video_window = None
            self.active_roi = None
        if not self.ai_start_pending and not was_waiting_for_ethernet_stop:
            self.command("ai_stop")

    def poll_status(self):
        self.poll_now()
        self.root.after(self.STATUS_POLL_MS, self.poll_status)

    def poll_alarm(self):
        self.request_alarm_catalog()
        self.root.after(4000, self.poll_alarm)

    def start_can_alarm_stream(self):
        if self.control is None or self.can_status_worker is not None:
            return
        self.can_status_worker = CanStatusWorker(
            self.control, self.events, self.CAN_STATUS_STREAM_MS)
        self.can_status_worker.start()

    def stop_can_alarm_stream(self):
        worker, self.can_status_worker = self.can_status_worker, None
        if worker is not None:
            worker.close()

    def show_can_alarm_status(self, data):
        text, color = format_can_alarm_status(data)
        self.can_alarm_text.set(text)
        self.can_alarm_label.configure(foreground=color)
        self.can_alarm_side_label.configure(foreground=color)
        pairing = data.get('pairing', {}) if isinstance(data, dict) else {}
        service = data.get('service', {}) if isinstance(data, dict) else {}
        state = (service.get('active_state'), pairing.get('paired'),
                 pairing.get('nonce'))
        if state != self.last_can_alarm_state:
            self.write_log(text)
            self.last_can_alarm_state = state

    def request_alarm_catalog(self):
        if self.control is None or self.alarm_pending:
            return
        self.alarm_pending = True
        client = self.control
        def work():
            try:
                self.events.put(('alarm_catalog', client.list_alarm_events()))
            except Exception as error:
                self.events.put(('alarm_error', str(error)))
        self.pool.submit(work)

    def open_fault_history(self):
        if self.control is None:
            messagebox.showwarning('SSH 未连接', '先连接板端，再查看故障记录。')
            return
        if self.alarm_window is not None and self.alarm_window.exists():
            self.alarm_window.lift()
        else:
            self.alarm_window = FaultHistoryWindow(
                self.root, self.request_alarm_catalog, self.fetch_fault_event)
            self.alarm_window.set_events(self.alarm_events)
        self.request_alarm_catalog()

    def fetch_fault_event(self, event_id):
        client = self.control
        if client is None:
            return
        def work():
            try:
                event, binary = client.fetch_alarm_event(event_id)
                bins = event_envelope(binary)
                self.events.put(('alarm_wave', event, bins))
            except Exception as error:
                self.events.put(('alarm_wave_error', str(error)))
        self.pool.submit(work)

    def show_alarm_catalog(self, events):
        self.alarm_events = events
        current = {event['id'] for event in events}
        if self.alarm_initialized:
            for event in reversed(events):
                if event['id'] not in self.alarm_seen:
                    line = '{} {} {} 保存{}（{}帧）'.format(
                        event.get('code', 'OTHER_EVENT'), event.get('created_utc', ''),
                        event.get('reason', ''),
                        '不完整' if event.get('incomplete') else '完成',
                        event.get('frame_count', 0))
                    self.write_log('板端新故障记录（电脑接收 {}）：{}'.format(
                        time.strftime('%Y-%m-%d %H:%M:%S %z'), line))
                    if event.get('code') != 'MANUAL':
                        self.root.bell()
        self.alarm_seen.update(current)
        self.alarm_initialized = True
        if events:
            newest = events[0]
            self.alarm_text.set('最近记录：{} | {} | {}（{}帧）'.format(
                newest.get('code', ''), newest.get('created_utc', ''),
                '不完整' if newest.get('incomplete') else '已保存',
                newest.get('frame_count', 0)))
        else:
            self.alarm_text.set('故障记录：板端暂无已保存事件')
        if self.alarm_window is not None and self.alarm_window.exists():
            self.alarm_window.set_events(events)

    def poll_now(self):
        if self.control is not None and not self.status_pending:
            self.status_pending = True
            self.run_control("status", lambda: self.control.request("status"))

    def show_status(self, data):
        self.latest_status = data
        self.latest_status_at = time.monotonic()
        self.motor_text.set('电机状态：{}；目标占空比 {}%；应用占空比 {}%'.format(
            '运行中' if data.get('motor_running') else '已停止',
            data.get('motor_target_duty', data.get('motor_duty', 0)),
            data.get('pl', {}).get('applied_duty', 0)))
        pl = data.get("pl", {})
        wave_tail = data.get('wave_tail', '')
        failure = next((line.strip() for line in reversed(wave_tail.splitlines())
                        if 'WAVE_SERVICE_FAIL:' in line), '')
        fault = (pl.get('guard_fault', 0), pl.get('motor_fault', 0),
                 bool(data.get('fault_latched')), failure)
        if any(fault):
            line = ('板端故障：守护 0x{:X}，电机 0x{:X}，锁存 {}{}').format(
                fault[0], fault[1], '是' if fault[2] else '否',
                '；波形服务：' + failure[-140:] if failure else '')
            self.alarm_live_text.set(line)
            if fault != self.last_board_fault:
                self.write_log('自动报警：' + line)
                self.root.bell()
        else:
            self.alarm_live_text.set('板端故障：当前无锁存')
        self.last_board_fault = fault
        self.pl_text.set("PL：{:08X}  守护：{:08X}  故障：{:08X}  占空比：{}%  许可：{}–60%  相机：{:08X}".format(
            pl.get("features", 0), pl.get("guard_state", 0),
            pl.get("guard_fault", 0), pl.get("applied_duty", 0),
            pl.get('duty_min', 15),
            pl.get("camera_status", 0)))
        ai_tail = data.get("ai_tail", "")
        if data.get("ai_running"):
            roi = roi_from_board_log(ai_tail)
            if roi is not None:
                self.set_roi(roi)
        else:
            self.set_roi(None)
        reports = re.findall(r"BOARD_AI frames=\d+ average_fps=\S+ infer_ms=\S+ boxes=\d+ guard_faults=\S+", ai_tail)
        board_report = reports[-1] if reports else ""
        self.ai_text.set("板端 AI：{}  {}  {}".format(
            "运行中" if data.get("ai_running") else "停止",
            "故障锁存" if data.get("fault_latched") else "", board_report))
        if data.get('wave_running'):
            self.blackbox_text.set('黑匣子：持续监测中；点击按钮会标记一段故障前后波形')
        else:
            self.blackbox_text.set("黑匣子：{}".format(
                "8 秒单次采集中" if data.get("blackbox_running") else "未监测"))
        for key in ("ai_tail", "motor_tail", "blackbox_tail", "wave_tail"):
            text = data.get(key, "")
            if "CMA retained" in text or "FAIL:" in text or "timeout" in text:
                self.connection_text.set("板端日志包含故障；停止操作并检查现场")

    def show_frame(self, when, packet):
        if self.video_window is None or not self.video_window.winfo_exists():
            return
        sequence, infer_sequence, rgb, boxes = packet
        frame = Image.frombytes("RGB", (WIDTH, HEIGHT), rgb)
        draw = ImageDraw.Draw(frame)
        for x1, y1, x2, y2, score in boxes:
            draw.rectangle((x1, y1, x2, y2), outline="#4dff7a", width=3)
            draw.text((x1, max(0, y1 - 18)), "blade_defect {:.1f}%".format(score / 10),
                      fill="#4dff7a")
        photo = ImageTk.PhotoImage(frame)
        self.canvas.itemconfigure(self.image_item, image=photo)
        self.canvas.image = photo
        if self.last_frame_time is not None and when > self.last_frame_time:
            instantaneous = 1.0 / (when - self.last_frame_time)
            self.estimated_fps = (instantaneous if self.estimated_fps is None else
                                  0.85 * self.estimated_fps + 0.15 * instantaneous)
        self.last_frame_time = when
        fps = "—" if self.estimated_fps is None else "{:.1f}".format(self.estimated_fps)
        self.frame_text.set("帧：{}  FPS：{}  NPU 帧龄：{}  框：{}".format(
            sequence, fps, sequence - infer_sequence, len(boxes)))

    def set_roi(self, roi):
        """Canvas overlay is separate from RGB data and green prediction boxes."""
        if self.video_window is None or not self.video_window.winfo_exists():
            self.active_roi = None
            return
        if roi == self.active_roi:
            return
        self.active_roi = roi
        if roi is None:
            self.canvas.itemconfigure(self.roi_item, state="hidden")
            self.canvas.itemconfigure(self.roi_label, state="hidden")
            return
        x, y, width, height = roi
        self.canvas.coords(self.roi_item, x, y, x + width, y + height)
        self.canvas.coords(self.roi_label, x, max(16, y - 4))
        self.canvas.itemconfigure(self.roi_item, state="normal")
        self.canvas.itemconfigure(self.roi_label, state="normal")

    def refresh(self):
        try:
            while True:
                event = self.events.get_nowait()
                kind = event[0]
                if kind == "control_result":
                    label, result = event[1], event[2]
                    elapsed = event[3] if len(event) > 3 else None
                    self.finish_pending(label, elapsed)
                    if label == "connect":
                        self.control = result
                        self.connection_text.set("SSH 已认证")
                        self.write_log("SSH 已连接；电机不会自动启动")
                        self.start_can_alarm_stream()
                    elif label == "status":
                        self.status_pending = False
                        if result.get("ok"):
                            self.show_status(result["data"])
                        else:
                            self.write_log("状态读取失败：" + result.get("error", "未知错误"))
                    else:
                        if result.get("ok"):
                            data = result.get("data", {})
                            self.write_log("{}: {}".format(label, data.get("message", "完成")))
                            if label == "ai_start":
                                self.ai_start_pending = False
                                if self.ai_wanted:
                                    self.set_roi(None)
                                    self.video = VideoWorker(self.host.get().strip(), self.events, self.frames)
                                    self.video.start()
                                else:
                                    self.command("ai_stop")
                            elif label == "ai_stop":
                                self.video_text.set("视频已停止；请核对板端 CMA released")
                            elif label == 'motor_stop' and self.ai_waiting_for_ethernet_stop:
                                self.ai_stop_command_done = True
                                self.poll_now()
                            elif label == 'motor_stop':
                                self.poll_now()
                            elif label in ('motor_start', 'motor_set_duty',
                                           'motor_estop', 'motor_clear'):
                                self.poll_now()
                            elif label == 'wave_start' and self.wave_view_wanted and self.wave is None:
                                self.wave_start_pending = False
                                self.wave = WaveformWorker(self.control.host,
                                                           self.key_path.get().strip(), self.events)
                                self.wave.start()
                            elif label == 'wave_start':
                                self.wave_start_pending = False
                            elif label == 'wave_stop':
                                self.wave_text.set('板端波形与黑匣子已停止；请核对 DMA 释放及存储冲刷')
                        else:
                            if label == "ai_start":
                                self.ai_start_pending = False
                                self.ai_wanted = False
                                self.video_text.set("板端 AI 启动失败")
                            if label == 'motor_stop' and self.ai_waiting_for_ethernet_stop:
                                self._cancel_ai_after_ethernet_stop(
                                    '板端拒绝以太网正常停机；AI 未启动：' +
                                    result.get('error', '未知错误'))
                            if label == 'wave_start':
                                self.wave_start_pending = False
                                self.wave_view_wanted = False
                                self.wave_text.set('板端波形启动失败：' + result.get('error', '未知错误'))
                            self.write_log("{} 拒绝：{}".format(label, result.get("error", "未知错误")))
                elif kind == "control_error":
                    label, error = event[1], event[2]
                    elapsed = event[3] if len(event) > 3 else None
                    self.finish_pending(label, elapsed)
                    self.stop_can_alarm_stream()
                    if label == "status":
                        self.status_pending = False
                    elif label == 'ai_start':
                        self.ai_start_pending = False
                        self.ai_wanted = False
                    elif label == 'wave_start':
                        self.wave_start_pending = False
                        self.wave_view_wanted = False
                    elif label == 'motor_stop' and self.ai_waiting_for_ethernet_stop:
                        self._cancel_ai_after_ethernet_stop(
                            '以太网正常停机命令失败；AI 未启动：' + str(error))
                    self.connection_text.set("控制通信故障；必要时物理断电")
                    self.write_log("{} 通信失败：{}".format(label, error))
                    if self.control is not None:
                        self.control.close()
                        self.control = None
                elif kind == "video_connected":
                    self.video_text.set(event[1])
                elif kind == "video_error":
                    self.video_text.set("视频故障：" + event[1])
                    self.write_log(event[1])
                elif kind == "video_ended":
                    if self.video is event[1]:
                        self.video = None
                        self.ai_wanted = False
                elif kind == "wave_packet":
                    if self.wave is event[1]:
                        self.wave_panel.add(event[2])
                        self.wave_text.set("ADC DMA 实时：50 kHz 原始采集 / 2 ms 包络；丢帧 {}，序号缺口 {}".format(
                            event[2]['dropped'], event[2]['seq_gaps']))
                elif kind == "wave_error":
                    if self.wave is event[1]:
                        self.wave_panel.mark_stopped()
                        self.wave_text.set("波形不可用：" + event[2])
                        self.write_log("波形不可用：" + event[2])
                elif kind == "wave_ended":
                    if self.wave is event[1]:
                        self.wave_panel.mark_stopped()
                        self.wave = None
                elif kind == 'alarm_catalog':
                    self.alarm_pending = False
                    self.show_alarm_catalog(event[1])
                elif kind == 'alarm_error':
                    self.alarm_pending = False
                    self.alarm_text.set('故障记录读取失败：' + event[1])
                elif kind == 'can_alarm_status':
                    worker, data = event[1], event[2]
                    if worker is self.can_status_worker:
                        self.show_can_alarm_status(data)
                elif kind == 'can_alarm_stream_error':
                    worker = event[1]
                    if worker is self.can_status_worker:
                        self.can_alarm_text.set(
                            'STM32 报警通道：实时状态流重连中：' + event[2])
                        self.can_alarm_label.configure(foreground=RED)
                        self.can_alarm_side_label.configure(foreground=RED)
                elif kind == 'can_alarm_stream_ended':
                    if event[1] is self.can_status_worker:
                        self.can_status_worker = None
                elif kind == 'alarm_wave':
                    if self.alarm_window is not None and self.alarm_window.exists():
                        self.alarm_window.show_waveform(event[1], event[2])
                elif kind == 'alarm_wave_error':
                    if self.alarm_window is not None and self.alarm_window.exists():
                        self.alarm_window.set_error('故障波形读取失败：' + event[1])
        except queue.Empty:
            pass
        try:
            while True:
                self.show_frame(*self.frames.get_nowait())
        except queue.Empty:
            pass
        self.root.after(40, self.refresh)

    def close(self):
        if self.closed:
            return
        self.closed = True
        self.stop_can_alarm_stream()
        if self.video is not None:
            self.video.close()
        if self.wave is not None:
            self.wave.close()
        if self.control is not None:
            self.control.close()
        self.pool.shutdown(wait=False, cancel_futures=True)
        self.root.destroy()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="192.168.0.50")
    args = parser.parse_args()
    root = tk.Tk()
    Dashboard(root, args.host)
    root.mainloop()


if __name__ == "__main__":
    main()
