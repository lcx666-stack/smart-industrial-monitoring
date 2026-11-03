#!/usr/bin/env python3
"""Retired USB-CAN control console, kept for reading its historical inbox.

The active architecture sends alarms to STM32 over CAN and controls the board
over Ethernet. The board service ignores CAN control frames.
"""

import argparse
import datetime
import queue
import random
import sqlite3
import sys
import threading
import time
import tkinter as tk
from tkinter import messagebox, scrolledtext, ttk
from pathlib import Path
import zlib

import protocol as p
from transport import PythonCan


OP_NAMES = {p.GET_STATUS: '查询状态', p.MOTOR_START: '启动电机',
            p.MOTOR_SET_DUTY: '运行中调速',
            p.CLEAR_FAULT: '清除锁存', p.MARK_EVENT: '手动记录',
            p.STOP: '正常停机', p.ESTOP: '锁存停机'}
OUTCOMES = {p.ACCEPTED: '已接收', p.DONE: '已完成',
            p.REJECTED: '已拒绝', p.FAILED: '执行失败'}
SAVE_NAMES = {p.SAVE_PENDING: '待保存', p.SAVE_COMPLETE: '完整保存',
              p.SAVE_PARTIAL: '部分保存', p.SAVE_FAILED: '保存失败'}


class Receiver(threading.Thread):
    def __init__(self, bus_source, events):
        super().__init__(daemon=True)
        self.bus_source, self.bus, self.events = bus_source, None, events
        self.stop = threading.Event()
        self.outgoing = queue.Queue()

    def send(self, frame):
        # Keep all PCAN calls on this worker thread. Some USB-CAN drivers do
        # not reliably deliver RX while another thread calls send().
        self.outgoing.put(frame)

    def run(self):
        try:
            # Create, use, and close the PCAN handle on this same thread.
            self.bus = self.bus_source() if callable(self.bus_source) else self.bus_source
            self.events.put(('connected', None))
            while not self.stop.is_set():
                try:
                    outgoing = self.outgoing.get_nowait()
                except queue.Empty:
                    outgoing = None
                if outgoing is not None:
                    self.bus.send(*outgoing)
                frame = self.bus.recv(.05)
                if frame:
                    self.events.put(('frame', frame))
        except Exception as error:
            if not self.stop.is_set():
                self.events.put(('error', str(error)))
        finally:
            if self.bus is not None:
                try:
                    self.bus.close()
                except Exception:
                    pass
                self.bus = None


class Inbox:
    """Commit alarm frames locally before the application-level ACK."""

    def __init__(self, path):
        self.db = sqlite3.connect(str(path))
        self.db.execute('''CREATE TABLE IF NOT EXISTS frames (
            seq INTEGER NOT NULL, can_id INTEGER NOT NULL, payload BLOB NOT NULL,
            PRIMARY KEY(seq,can_id,payload))''')
        self.db.commit()

    def save(self, seq, can_id, payload):
        self.db.execute('INSERT OR IGNORE INTO frames VALUES (?,?,?)',
                        (seq, can_id, payload))
        self.db.commit()

    def load(self):
        return self.db.execute('SELECT can_id,payload FROM frames ORDER BY seq,can_id')

    def close(self):
        self.db.close()


class Console:
    def __init__(self, bus, inbox_path, host=None, key_path=None,
                 root=None, parent=None, on_alarm=None, on_waveform=None,
                 on_reconnect=None, on_connected=None, on_connection_error=None):
        self.bus = None
        self.inbox = Inbox(inbox_path)
        self.host, self.key_path = host, key_path
        self.on_alarm = on_alarm
        self.on_waveform = on_waveform
        self.on_reconnect = on_reconnect
        self.on_connected = on_connected
        self.on_connection_error = on_connection_error
        self.history_window = None
        self.events = queue.Queue()
        self.receiver = None
        self.closed = False
        self.motor_running = False
        self.last_heartbeat_at = None
        self.command_outcomes = {}
        self.command_states = {}
        self.counter = random.SystemRandom().randint(1, 0xffffffff)
        self.alarms = {}
        self.owns_root = root is None
        self.root = root if root is not None else tk.Tk()
        self.parent = parent if parent is not None else self.root
        if self.owns_root:
            self.root.title('CAN 电机控制与故障报警')
            self.root.geometry('900x650')
        self.parent.columnconfigure(0, weight=1)
        self.parent.rowconfigure(2, weight=1)
        bar = ttk.Frame(self.parent, padding=(12, 5), style='Card.TFrame')
        bar.grid(row=0, column=0, sticky='ew')
        self.link = tk.StringVar(value='CAN 未连接；历史记录可查看')
        link_row = ttk.Frame(bar, style='Card.TFrame')
        link_row.pack(fill='x')
        ttk.Label(link_row, textvariable=self.link,
                  style='Card.TLabel').pack(side='left')
        if on_reconnect is not None:
            ttk.Button(link_row, text='重新连接',
                       command=on_reconnect).pack(side='right')
        self.status = tk.StringVar(value='电机状态未知')
        ttk.Label(bar, textvariable=self.status,
                  style='Muted.Card.TLabel').pack(anchor='w', pady=(2, 0))

        controls = ttk.LabelFrame(self.parent, text='CAN 控制',
                                  style='Card.TLabelframe', padding=8)
        controls.grid(row=1, column=0, sticky='ew', padx=10, pady=(2, 6))
        for column in range(6):
            controls.columnconfigure(column, weight=1)
        ttk.Button(controls, text='查询状态',
                   command=lambda: self.request(p.GET_STATUS)).grid(
                       row=0, column=0, padx=3, pady=3, sticky='ew')
        ttk.Label(controls, text='占空比目标 (%)').grid(row=0, column=1)
        self.duty = tk.StringVar(value='15')
        ttk.Entry(controls, textvariable=self.duty, width=5).grid(row=0, column=2, padx=3)
        ttk.Button(controls, text='启动电机', style='Primary.TButton',
                   command=self.start_motor).grid(row=0, column=3, padx=3, pady=3, sticky='ew')
        ttk.Button(controls, text='正常停机',
                   command=lambda: self.request(p.STOP)).grid(
                       row=0, column=4, padx=3, pady=3, sticky='ew')
        ttk.Button(controls, text='锁存停机', style='Danger.TButton',
                   command=lambda: self.request(p.ESTOP)).grid(
                       row=0, column=5, padx=3, pady=3, sticky='ew')
        ttk.Button(controls, text='清除故障', command=self.clear_fault).grid(
            row=1, column=0, padx=3, pady=3, sticky='ew')
        ttk.Button(controls, text='手动记录波形',
                   command=lambda: self.request(p.MARK_EVENT)).grid(
                       row=1, column=1, columnspan=2, padx=3, pady=3, sticky='ew')
        ttk.Label(controls, text='运行目标 (%)').grid(row=1, column=3)
        ttk.Button(controls, text='应用运行占空比', command=self.set_running_duty).grid(
            row=1, column=4, columnspan=2, padx=3, pady=3, sticky='ew')
        columns = ('seq', 'fault', 'time', 'save', 'event')
        table_card = ttk.Frame(self.parent, style='Card.TFrame', padding=(10, 5))
        table_card.grid(row=2, column=0, sticky='nsew', padx=10)
        ttk.Label(table_card, text='故障记录', style='Section.TLabel').pack(anchor='w')
        table_row = ttk.Frame(table_card, style='Card.TFrame')
        table_row.pack(fill='both', expand=True, pady=(5, 0))
        scrollbar = ttk.Scrollbar(table_row, orient='vertical')
        self.table = ttk.Treeview(table_row, columns=columns, show='headings',
                                  height=8, yscrollcommand=scrollbar.set)
        scrollbar.configure(command=self.table.yview)
        for key, title, width in (('seq', '序号', 80), ('fault', '故障', 150),
                                  ('time', '北京时间', 180), ('save', '黑匣子', 120),
                                  ('event', '事件校验码', 150)):
            self.table.heading(key, text=title)
            self.table.column(key, width=width, anchor='center')
        self.table.pack(side='left', fill='both', expand=True)
        scrollbar.pack(side='right', fill='y')
        self.table.tag_configure('even', background='#f3f7fb')
        ttk.Button(self.parent, text='查看所选故障波形（以太网）',
                   style='Primary.TButton', command=self.open_selected_wave).grid(
                       row=3, column=0, sticky='w', padx=20, pady=(5, 6))
        log_card = ttk.Frame(self.parent, style='Card.TFrame', padding=(10, 5))
        log_card.grid(row=4, column=0, sticky='ew', padx=10, pady=(0, 8))
        ttk.Label(log_card, text='CAN 通信日志', style='Section.TLabel').pack(anchor='w')
        self.log = scrolledtext.ScrolledText(
            log_card, height=3, state='disabled', borderwidth=0,
            font=('Microsoft YaHei UI', 10), bg='#ffffff', fg='#192b3c')
        self.log.pack(fill='x', pady=(4, 0))
        if self.owns_root:
            self.root.protocol('WM_DELETE_WINDOW', self.close)
        for can_id, payload in self.inbox.load():
            self.process(can_id, payload, acknowledge=False)
        if bus is not None:
            self.attach_bus(bus)
        self.root.after(100, self.drain)

    def attach_bus(self, bus):
        if self.closed:
            return
        self.disconnect_bus()
        self.receiver = Receiver(bus, self.events)
        self.receiver.start()
        self.link.set('正在连接 USB-CAN…')

    def disconnect_bus(self):
        receiver = self.receiver
        self.receiver = self.bus = None
        if receiver is not None:
            receiver.stop.set()
            if receiver.is_alive():
                receiver.join(timeout=0.5)

    def write(self, line):
        self.log.configure(state='normal')
        self.log.insert('end', datetime.datetime.now().strftime('%H:%M:%S ') + line + '\n')
        self.log.see('end')
        self.log.configure(state='disabled')

    def board_heartbeat_fresh(self, max_age=3.0):
        return (self.receiver is not None and self.last_heartbeat_at is not None and
                time.monotonic() - self.last_heartbeat_at <= max_age)

    def request(self, opcode, value=0):
        self.write('CAN 仅用于故障报警；电机与板端控制请使用以太网控制台')
        return None

    def start_motor(self):
        if not self.board_heartbeat_fresh():
            messagebox.showerror(
                '板端 CAN 无心跳',
                '未发送启动命令：USB-CAN 已打开，但最近 3 秒没有收到板端心跳。'
                '请先检查 CANH/CANL、共地、500 kbit/s 和总线终端。')
            return
        try:
            duty = int(self.duty.get())
            if not 10 <= duty <= 60:
                raise ValueError()
        except ValueError:
            messagebox.showerror('参数错误', '启动占空比必须为 10–60 的整数')
            return
        if messagebox.askyesno('现场确认',
                '确认电机供电已接通，电机已固定，周围没有手或线材，'
                '并且可以立即物理断电。\n\n'
                '本次将通过 CAN 以 {}% 占空比启动电机，是否发送？'.format(duty)):
            self.request(p.MOTOR_START, duty)

    def clear_fault(self):
        if not self.board_heartbeat_fresh():
            messagebox.showerror(
                '板端 CAN 无心跳',
                '未发送清故障命令：请先恢复板端心跳和 CAN 通信。')
            return
        if messagebox.askyesno('现场检查',
                '确认已现场检查并排除故障？\n\n'
                '清除锁存不会启动电机。'):
            self.request(p.CLEAR_FAULT)

    def set_running_duty(self):
        if not self.board_heartbeat_fresh():
            messagebox.showerror(
                '板端 CAN 无心跳',
                '未发送调速命令：请先恢复板端心跳和 CAN 通信。')
            return
        if not self.motor_running:
            messagebox.showinfo('电机未运行', '请先启动电机，运行中调速命令才会生效。')
            return
        try:
            duty = int(self.duty.get())
            if not 10 <= duty <= 60:
                raise ValueError()
        except ValueError:
            messagebox.showerror('参数错误', '运行占空比必须为 10–60 的整数')
            return
        if messagebox.askyesno('确认调整目标占空比',
                '将电机运行目标调整到 {}%。PL 会按硬件斜坡逐步变化；'
                '这不是转速闭环。确认电机和现场仍处于安全状态后继续。'.format(duty),
                icon='warning'):
            self.request(p.MOTOR_SET_DUTY, duty)

    def open_selected_wave(self):
        chosen = self.table.selection()
        if not chosen:
            messagebox.showinfo('选择故障', '请先选中一条 CAN 故障')
            return
        entry = self.alarms.get(int(chosen[0]), {})
        if 'event_key' not in entry:
            messagebox.showinfo('等待保存', '黑匣子保存结果和事件校验码尚未到达')
            return
        host = self.host() if callable(self.host) else self.host
        key_path = self.key_path() if callable(self.key_path) else self.key_path
        if not host or not key_path:
            messagebox.showinfo('以太网参数',
                '启动窗口时传入 --host 和 --key，才能读取完整板端波形')
            return
        event_key = entry['event_key']
        self.write('正在按事件校验码 {:08X} 查找并校验波形'.format(event_key))

        def work():
            client = None
            try:
                sys.path.insert(0, str(Path(__file__).resolve().parents[1] /
                                        'ethernet_control_final_20261014'))
                from control_client import ControlClient
                from fault_history import event_envelope
                client = ControlClient(host, key_path)
                matches = [item for item in client.list_alarm_events()
                           if zlib.crc32(item['id'].encode('utf-8')) & 0xffffffff ==
                              event_key]
                if len(matches) != 1:
                    raise ValueError('事件校验码匹配 {} 条记录；请在原控制台按时间核对'.format(
                        len(matches)))
                fault_name = p.FAULT_NAMES.get(entry.get('fault'))
                if fault_name and fault_name not in str(matches[0].get('code', '')).split('+'):
                    raise ValueError('事件校验码匹配，但故障码不一致')
                if entry.get('flags', 0) & 4 and 'utc_seconds' in entry:
                    second = datetime.datetime.utcfromtimestamp(
                        entry['utc_seconds']).strftime('%Y-%m-%dT%H:%M:%S')
                    if not str(matches[0].get('created_utc', '')).startswith(second):
                        raise ValueError('事件校验码匹配，但板端故障时间不一致')
                event, binary = client.fetch_alarm_event(matches[0]['id'])
                bins = event_envelope(binary)
                self.events.put(('waveform', (event, bins)))
            except Exception as error:
                self.events.put(('error', '故障波形读取失败：' + str(error)))
            finally:
                if client is not None:
                    client.close()

        threading.Thread(target=work, daemon=True).start()

    def update_alarm(self, seq):
        entry = self.alarms[seq]
        time_text = '未校时'
        if 'utc_seconds' in entry and entry.get('flags', 0) & 4:
            try:
                stamp = entry['utc_seconds'] + entry.get('ms', 0) / 1000.0
                shanghai = datetime.timezone(datetime.timedelta(hours=8))
                time_text = datetime.datetime.fromtimestamp(stamp, shanghai).strftime(
                    '%Y-%m-%d %H:%M:%S.%f')[:-3]
            except (ValueError, OverflowError):
                pass
        values = (seq, p.FAULT_NAMES.get(entry.get('fault'), '待接收'),
                  time_text, SAVE_NAMES.get(entry.get('result'), '待保存'),
                  '{:08X}'.format(entry['event_key']) if 'event_key' in entry else '')
        self.table.item(str(seq), values=values) if self.table.exists(str(seq)) else \
            self.table.insert('', 0, iid=str(seq), values=values,
                              tags=('even',) if seq % 2 == 0 else ())

    def process(self, can_id, payload, acknowledge=True):
        try:
            data = p.decode(can_id, payload)
        except ValueError:
            return
        if can_id == p.HEARTBEAT_ID:
            state = data['state']
            self.motor_running = bool(state & 1)
            self.last_heartbeat_at = time.monotonic()
            self.link.set('板端心跳：运行 {} 秒，协议 v{}'.format(data['uptime_s'],
                                                  data['version']))
            self.status.set('电机{}  故障锁存{}  黑匣子{}  PL fault=0x{:02X}'.format(
                '运行' if state & 1 else '停止', '是' if state & 2 else '否',
                '运行' if state & 4 else '停止', data['guard_fault']))
            if state & 8:
                self.status.set(self.status.get() + ' | CAN stop hold')
            return
        if can_id == p.REPLY_ID:
            request_id = data['request_id']
            self.command_outcomes[request_id] = data['outcome']
            self.command_states[request_id] = data['state']
            while len(self.command_outcomes) > 64:
                oldest = next(iter(self.command_outcomes))
                self.command_outcomes.pop(oldest, None)
                self.command_states.pop(oldest, None)
            self.write('{} [{}] request_id={} 状态={} 明细={}'.format(
                OP_NAMES.get(data['opcode'], '未知命令'),
                OUTCOMES.get(data['outcome'], '?'), request_id,
                data['state'], data['detail']))
            if data['opcode'] == p.MOTOR_SET_DUTY and data['outcome'] == p.DONE:
                self.write('目标占空比已接受 {}%；PL 正在渐变'.format(data['detail']))
            return
        bit = {p.ALARM_ID: p.ACK_ALARM, p.TIME_ID: p.ACK_TIME,
               p.SAVE_ID: p.ACK_SAVE, p.EVENT_KEY_ID: p.ACK_KEY}[can_id]
        seq = data['seq']
        if acknowledge:
            try:
                self.inbox.save(seq, can_id, payload)
            except sqlite3.Error as error:
                self.write('本机报警落盘失败，暂不确认：' + str(error))
                return
        entry = self.alarms.setdefault(seq, {})
        entry.update(data)
        self.update_alarm(seq)
        if acknowledge:
            try:
                self.receiver.send(p.alarm_ack(seq, bit))
            except Exception as error:
                self.write('报警确认帧发送失败：' + str(error))
        if acknowledge and self.on_alarm is not None and can_id in (p.ALARM_ID, p.SAVE_ID):
            self.on_alarm(seq, entry, can_id)
        if can_id == p.ALARM_ID:
            self.write('CAN 故障报警 seq={} {}'.format(seq,
                       p.FAULT_NAMES.get(data['fault'], '未知故障')))
        elif can_id == p.SAVE_ID:
            self.write('黑匣子 seq={} {} ({} KiB)'.format(
                seq, SAVE_NAMES.get(data['result'], '?'), data['size_kib']))

    def drain(self):
        if self.closed:
            return
        try:
            while True:
                kind, value = self.events.get_nowait()
                if kind == 'connected':
                    self.link.set('CAN 已连接；等待板端心跳')
                    if self.on_connected is not None:
                        self.on_connected()
                elif kind == 'frame':
                    self.process(*value)
                elif kind == 'waveform':
                    event, bins = value
                    if self.on_waveform is not None:
                        self.on_waveform(event, bins)
                    else:
                        from fault_history import FaultHistoryWindow
                        if self.history_window is None or not self.history_window.exists():
                            self.history_window = FaultHistoryWindow(
                                self.root, lambda: None, lambda _event_id: None)
                        self.history_window.set_events([event])
                        self.history_window.show_waveform(event, bins)
                        self.history_window.lift()
                else:
                    self.write(value)
                    if not value.startswith('故障波形'):
                        self.link.set('CAN 接收已中断')
                        self.disconnect_bus()
                        if self.on_connection_error is not None:
                            self.on_connection_error(value)
        except queue.Empty:
            pass
        self.root.after(100, self.drain)

    def close(self):
        if self.closed:
            return
        self.closed = True
        self.disconnect_bus()
        self.inbox.close()
        if self.owns_root:
            self.root.destroy()


def main():
    raise SystemExit('USB-CAN control console is retired; start the Ethernet dashboard instead.')


if __name__ == '__main__':
    main()
