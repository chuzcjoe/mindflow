#!/usr/bin/env python3
"""Reuse this Mac's verified model cache inside this development simulator only."""
from pathlib import Path
import shutil
import subprocess
import sys

container = Path(subprocess.check_output(
    ["xcrun", "simctl", "get_app_container", sys.argv[1], "com.mindflow.ios", "data"], text=True).strip())
relative = Path("MindFlow/Models/SenseVoice/models/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17")
source = Path.home() / "Library/Application Support" / relative
destination = container / "Library/Application Support" / relative
for name in ("model.int8.onnx", "tokens.txt"):
    origin, target = source / name, destination / name
    if origin.is_file() and not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        incoming = target.with_suffix(target.suffix + ".incoming")
        shutil.copyfile(origin, incoming)
        incoming.replace(target)
        print("Reused local model cache: " + name)
# The app still checks pinned sizes and SHA-256 before using the files.
