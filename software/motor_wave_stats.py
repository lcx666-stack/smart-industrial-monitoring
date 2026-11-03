#!/usr/bin/env python3
"""Load the optional dependency-free native waveform batch validator."""
import ctypes
import os


NATIVE_LIBRARY_NAME = "lib_motor_wave_stats.so"


class NativeState(ctypes.Structure):
    _fields_ = [
        ("frames", ctypes.c_uint64),
        ("sequence_gaps", ctypes.c_uint64),
        ("tick_mismatches", ctypes.c_uint64),
        ("first_ticks", ctypes.c_uint64),
        ("last_ticks", ctypes.c_uint64),
        ("last_seq", ctypes.c_uint32),
        ("current_min", ctypes.c_int32),
        ("current_max", ctypes.c_int32),
        ("motor_fault_frames", ctypes.c_uint64),
        ("adc_error_frames", ctypes.c_uint64),
        ("have_frame", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32),
        ("expected_ticks", ctypes.c_uint64),
    ]


def load_native():
    path = os.environ.get("MOTOR_WAVE_STATS_LIBRARY")
    if not path:
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            NATIVE_LIBRARY_NAME)
    if not os.path.isfile(path):
        return None
    library = ctypes.CDLL(path)
    library.motor_wave_stats_abi.argtypes = []
    library.motor_wave_stats_abi.restype = ctypes.c_uint32
    library.motor_wave_stats_size.argtypes = []
    library.motor_wave_stats_size.restype = ctypes.c_size_t
    if library.motor_wave_stats_abi() != 1 or \
            library.motor_wave_stats_size() != ctypes.sizeof(NativeState):
        raise RuntimeError("Native waveform parser ABI/layout mismatch")
    library.motor_wave_stats_ingest.argtypes = [
        ctypes.POINTER(NativeState), ctypes.c_char_p, ctypes.c_size_t]
    library.motor_wave_stats_ingest.restype = ctypes.c_int
    return library


class NativeParser(object):
    def __init__(self, library, expected_ticks):
        self.library = library
        self.state = NativeState()
        self.state.expected_ticks = expected_ticks

    def ingest(self, owner, data):
        # c_char_p accepts immutable bytes without making a per-frame copy.
        result = self.library.motor_wave_stats_ingest(
            ctypes.byref(self.state), data, len(data))
        state = self.state
        for name in ("frames", "sequence_gaps", "tick_mismatches",
                     "motor_fault_frames", "adc_error_frames"):
            setattr(owner, name, getattr(state, name))
        if state.have_frame:
            for name in ("first_ticks", "last_ticks", "last_seq",
                         "current_min", "current_max"):
                setattr(owner, name, getattr(state, name))
        if result == 1:
            raise RuntimeError("driver returned a partial frame")
        if result == 2:
            raise ValueError("Bad waveform frame magic/valid flag")
        if result:
            raise RuntimeError("Native waveform parser failed: {}".format(result))


class NativeDetector(ctypes.Structure):
    _fields_ = [("baseline_sum", ctypes.c_int64 * 3),
                ("baseline_count", ctypes.c_uint64),
                ("baseline_frames", ctypes.c_uint64),
                ("current_limit", ctypes.c_int32),
                ("current_zero", ctypes.c_int32),
                ("vibration_threshold", ctypes.c_int32),
                ("enabled", ctypes.c_uint32),
                ("previous", ctypes.c_uint32)]


class NativeTrigger(ctypes.Structure):
    _fields_ = [("index", ctypes.c_uint32), ("reasons", ctypes.c_uint32)]


class NativeScanner(object):
    def __init__(self, library, expected_ticks, current_limit=None,
                 current_zero=None, vibration_threshold=None, baseline_frames=2000):
        if not hasattr(library, "motor_wave_scan_ingest"):
            raise RuntimeError("Native library lacks black-box scanner; rebuild lib_motor_wave_stats.so")
        for name in ("motor_wave_scan_abi", "motor_wave_detector_size", "motor_wave_trigger_size"):
            function = getattr(library, name)
            function.argtypes = []
            function.restype = ctypes.c_size_t if name.endswith("size") else ctypes.c_uint32
        if library.motor_wave_scan_abi() != 1 or \
                library.motor_wave_detector_size() != ctypes.sizeof(NativeDetector) or \
                library.motor_wave_trigger_size() != ctypes.sizeof(NativeTrigger):
            raise RuntimeError("Native black-box scanner ABI/layout mismatch")
        library.motor_wave_scan_ingest.argtypes = [
            ctypes.POINTER(NativeState), ctypes.POINTER(NativeDetector),
            ctypes.c_char_p, ctypes.c_size_t, ctypes.POINTER(NativeTrigger),
            ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
        library.motor_wave_scan_ingest.restype = ctypes.c_int
        self.library = library
        self.state = NativeState()
        self.state.expected_ticks = expected_ticks
        self.detector = NativeDetector()
        self.detector.baseline_frames = baseline_frames
        if current_limit is not None:
            self.detector.enabled |= 1
            self.detector.current_limit = current_limit
            self.detector.current_zero = current_zero
        if vibration_threshold is not None:
            self.detector.enabled |= 2
            self.detector.vibration_threshold = vibration_threshold
        self.capacity = 0
        self.triggers = None
        self.count = ctypes.c_size_t()

    def scan(self, owner, data):
        required = len(data) // 32
        if required > self.capacity:
            self.capacity = max(2048, required)
            self.triggers = (NativeTrigger * self.capacity)()
        before = self.state.frames
        result = self.library.motor_wave_scan_ingest(
            ctypes.byref(self.state), ctypes.byref(self.detector), data, len(data),
            self.triggers, self.capacity, ctypes.byref(self.count))
        state = self.state
        for name in ("frames", "sequence_gaps", "tick_mismatches",
                     "motor_fault_frames", "adc_error_frames"):
            setattr(owner, name, getattr(state, name))
        if state.have_frame:
            for name in ("first_ticks", "last_ticks", "last_seq",
                         "current_min", "current_max"):
                setattr(owner, name, getattr(state, name))
        triggers = [(self.triggers[index].index, self.triggers[index].reasons)
                    for index in range(self.count.value)]
        return result, triggers, state.frames - before
