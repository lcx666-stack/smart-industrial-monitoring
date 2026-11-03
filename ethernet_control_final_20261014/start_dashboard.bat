@echo off
cd /d "%~dp0"
if exist "%~dp0..\can_comm_candidate_20261018\.venv\bin\python.exe" (
    "%~dp0..\can_comm_candidate_20261018\.venv\bin\python.exe" desktop_dashboard.py --host 192.168.0.50
) else if exist "C:\msys64\ucrt64\bin\python.exe" (
    "C:\msys64\ucrt64\bin\python.exe" desktop_dashboard.py --host 192.168.0.50
) else (
    py -3 desktop_dashboard.py --host 192.168.0.50
)
if errorlevel 1 pause
