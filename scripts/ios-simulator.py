#!/usr/bin/env python3
"""Select an available iPhone 18 simulator, or validate the requested UDID."""
import json
import subprocess
import sys


def listing(kind):
    return json.loads(subprocess.check_output(["xcrun", "simctl", "list", kind, "--json"], text=True))[kind]


devices = listing("devices")
requested = sys.argv[1] if len(sys.argv) > 1 else None
if requested:
    for group in devices.values():
        for device in group:
            if device["udid"] == requested and device.get("isAvailable"):
                print(requested)
                sys.exit(0)
    sys.exit("Requested simulator is unavailable: " + requested)

device_type = "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"
runtimes = [r for r in listing("runtimes") if r.get("isAvailable") and
            any(t["identifier"] == device_type for t in r.get("supportedDeviceTypes", []))]
if not runtimes:
    sys.exit("Install an iPhone 18 runtime first, for example: "
             "xcodebuild -downloadPlatform iOS -buildVersion 27.0 -architectureVariant arm64")
runtime = max(runtimes, key=lambda r: tuple(int(v) for v in r["version"].split(".")))
for device in devices.get(runtime["identifier"], []):
    if device.get("isAvailable") and device.get("deviceTypeIdentifier") == device_type:
        print(device["udid"])
        sys.exit(0)
print(subprocess.check_output(["xcrun", "simctl", "create", "MindFlow · iPhone 18 Pro",
                               device_type, runtime["identifier"]], text=True).strip())
