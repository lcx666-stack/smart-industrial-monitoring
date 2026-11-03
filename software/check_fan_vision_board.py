#!/usr/bin/env python3
"""Read-only camera/NPU gate for the current DR1 motor BOOT image.

This deliberately never opens hardware devices, loads modules, starts camera
DMA, writes motor registers, or claims model/backend compatibility.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path


def _device_tree_nodes(compatible: str) -> list[str]:
    root = Path("/proc/device-tree")
    if not root.is_dir():
        return []
    found = []
    for parent, _, files in os.walk(root):
        if "compatible" not in files:
            continue
        try:
            values = (Path(parent) / "compatible").read_bytes().split(b"\0")
        except OSError:
            continue
        if compatible.encode("ascii") in values:
            found.append(str(Path(parent).relative_to(root)))
    return sorted(found)


def _modules() -> list[str]:
    try:
        return [line.split()[0] for line in Path("/proc/modules").read_text().splitlines()]
    except OSError:
        return []


def _model_info(path: Path) -> dict:
    if not path.is_file():
        return {"exists": False}
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return {"exists": True, "bytes": path.stat().st_size, "sha256": digest.hexdigest()}


def audit(model: Path | None = None) -> dict:
    modules = _modules()
    camera_dt = _device_tree_nodes("anlogic,mipicam")
    camera_dev = Path("/dev/mipicam").exists()
    hard_npu_dt = _device_tree_nodes("anlogic,hard_npu")
    soft_npu_dt = _device_tree_nodes("anlogic,soft_npu")
    video_nodes = sorted(str(p) for p in Path("/dev").glob("video*"))
    result = {
        "schema": "fan-vision-readonly-gate-v1",
        "camera": {
            "mipicam_dt_nodes": camera_dt,
            "mipicam_device": camera_dev,
            "mipicam_module_loaded": "mipicam" in modules,
            "video_nodes": video_nodes,
            "i2c_nodes": sorted(str(p) for p in Path("/dev").glob("i2c-*")),
            "device_path_visible": bool(camera_dt and camera_dev),
            "frame_captured": False,
        },
        "npu": {
            "hard_npu_dt_nodes": hard_npu_dt,
            "soft_npu_dt_nodes": soft_npu_dt,
            "hard_npu_device": Path("/dev/hard_npu").exists(),
            "cma_mem_device": Path("/dev/cma_mem").exists(),
            "model_on_alnpu_tested": False,
        },
        "motor_control_writes": False,
        "module_loads": False,
    }
    if model is not None:
        result["model"] = _model_info(model)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, help="Optional ONNX to hash without loading it")
    args = parser.parse_args()
    result = audit(args.model)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not result["camera"]["device_path_visible"]:
        print("NOT READY: camera PL/device path is missing; do not load the vendor driver blindly.")
    else:
        print("CAMERA PATH VISIBLE: frame capture still requires a separate bounded test.")
    if not (result["npu"]["hard_npu_device"] and result["npu"]["cma_mem_device"]):
        print("NPU DEVICES NOT READY: this check does not load modules.")
    else:
        print("NPU DEVICES VISIBLE: the fan ONNX has not been validated on Alnpu.")


if __name__ == "__main__":
    main()
