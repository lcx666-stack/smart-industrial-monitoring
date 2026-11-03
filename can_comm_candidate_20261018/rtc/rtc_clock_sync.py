#!/usr/bin/env python3
"""Synchronize Linux with the board RTC, or save NTP time back to the RTC."""
import argparse
import datetime as dt
from pathlib import Path
import subprocess
import sys


def run(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, universal_newlines=True).stdout.strip()


def rtc_exists():
    return Path("/sys/class/rtc/rtc0/date").exists()


def valid_rtc():
    try:
        value = Path("/sys/class/rtc/rtc0/date").read_text().strip()
        year = dt.datetime.strptime(value, "%Y-%m-%d").year
        return 2024 <= year <= 2099
    except (OSError, ValueError):
        return False


def ntp_synchronized():
    if Path("/run/systemd/timesync/synchronized").exists():
        return True
    for line in run("timedatectl", "status").splitlines():
        if "System clock synchronized:" in line:
            return line.rsplit(":", 1)[-1].strip().lower() == "yes"
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("boot", "save"))
    mode = parser.parse_args().mode
    if not rtc_exists():
        print("RTC device absent", file=sys.stderr)
        return 1
    if mode == "boot":
        if not valid_rtc():
            print("RTC time uninitialized; skip boot clock restore", file=sys.stderr)
            return 0
        if ntp_synchronized():
            print("NTP already synchronized; keep system time")
            return 0
        run("hwclock", "--hctosys", "--utc", "--rtc=/dev/rtc0")
        print("system time restored from RTC")
    elif ntp_synchronized():
        run("hwclock", "--systohc", "--utc", "--rtc=/dev/rtc0")
        print("NTP synchronized time saved to RTC")
    else:
        print("NTP not synchronized; keep RTC time")
    return 0


if __name__ == "__main__":
    sys.exit(main())
