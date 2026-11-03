#!/usr/bin/env python3
"""Read-only DR1 NPU audit; never load modules or run a model."""
import argparse
import json
import os
import sys


HARD_COMPATIBLE = b"anlogic,hard_npu"
SOFT_COMPATIBLE = b"anlogic,soft_npu"
REQUIRED_DEVICES = ("hard_npu", "cma_mem")
ALNPU_DEVICES = ("hard_npu", "soft_npu", "cma_mem")
REQUIRED_LIBRARIES = ("libarmnn.so", "libarmnnOnnxParser.so")


def read_bytes(path):
    try:
        with open(path, "rb") as source:
            return source.read()
    except OSError:
        return None


def inspect(root="/", runtime_dir=None):
    """Inspect procfs, device tree, device nodes and optional Arm NN libraries."""
    root = os.path.abspath(root)
    soc = os.path.join(root, "proc", "device-tree", "soc")
    matches = {"hard_npu": [], "soft_npu": []}
    try:
        children = os.listdir(soc)
    except OSError:
        children = []
    for name in children:
        node = os.path.join(soc, name)
        compatible = read_bytes(os.path.join(node, "compatible"))
        if not compatible:
            continue
        values = compatible.split(b"\0")
        status = read_bytes(os.path.join(node, "status"))
        entry = {"node": name, "enabled": status is None or
                 status.split(b"\0", 1)[0] == b"okay"}
        if HARD_COMPATIBLE in values:
            matches["hard_npu"].append(entry)
        if SOFT_COMPATIBLE in values:
            matches["soft_npu"].append(entry)
    hard_dt_ok = len(matches["hard_npu"]) == 1 and matches["hard_npu"][0]["enabled"]
    soft_dt_ok = len(matches["soft_npu"]) == 1 and matches["soft_npu"][0]["enabled"]
    devices = {name: os.path.exists(os.path.join(root, "dev", name))
               for name in ALNPU_DEVICES}
    modules_raw = read_bytes(os.path.join(root, "proc", "modules")) or b""
    loaded = {name: any(line.split(b" ", 1)[0] == name.encode("ascii")
                        for line in modules_raw.splitlines())
              for name in ALNPU_DEVICES}
    release_raw = read_bytes(os.path.join(root, "proc", "sys", "kernel", "osrelease"))
    release = release_raw.decode("ascii", "replace").strip() if release_raw else None
    libraries = None
    if runtime_dir is not None:
        libraries = {name: os.path.isfile(os.path.join(runtime_dir, name))
                     for name in REQUIRED_LIBRARIES}
    device_ready = hard_dt_ok and all(devices[name] for name in REQUIRED_DEVICES)
    alnpu_ready = device_ready and soft_dt_ok and devices["soft_npu"]
    return {"schema": "dr1-npu-readiness-v2", "kernel_release": release,
            "hard_npu_nodes": matches["hard_npu"], "hard_npu_dt_enabled": hard_dt_ok,
            "soft_npu_nodes": matches["soft_npu"], "soft_npu_dt_enabled": soft_dt_ok,
            "device_nodes": devices, "modules_loaded": loaded,
            "armnn_libraries": libraries,
            "device_ready": device_ready,
            "alnpu_path_ready": alnpu_ready,
            "runtime_files_ready": None if libraries is None else all(libraries.values()),
            "model_inference_tested": False,
            "motor_control_writes": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-dir", help="Optional directory containing Arm NN shared libraries")
    parser.add_argument("--require-alnpu", action="store_true",
                        help="Require the soft-NPU path used by the supplied Alnpu runtime")
    args = parser.parse_args(argv)
    result = inspect(runtime_dir=args.runtime_dir)
    print(json.dumps(result, sort_keys=True, indent=2))
    if args.require_alnpu and not result["alnpu_path_ready"]:
        print("NOT READY: Alnpu requires hard and soft NPU nodes; nothing was loaded",
              file=sys.stderr)
        return 1
    if not result["device_ready"]:
        print("NOT READY: inspect device tree and NPU/CMA drivers; nothing was loaded", file=sys.stderr)
        return 1
    print("PASS: hard-NPU device path visible; inference and model compatibility remain untested")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
