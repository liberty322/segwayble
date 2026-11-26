#!/usr/bin/env python3
"""
Bundle device configuration files into app assets.

Reads the device_configs manifest and copies each device's device_commands.json
into app/assets/device_configs/{serverId}.json. Also produces a registry.json
with simplified metadata for every device.
"""

import json
import os
import shutil
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)

MANIFEST_PATH = os.path.join(PROJECT_ROOT, "device_configs", "manifest.json")
DEVICE_CONFIGS_DIR = os.path.join(PROJECT_ROOT, "device_configs")
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "assets", "device_configs")
BACKUP_CONFIG_PATH = os.path.join(PROJECT_ROOT, "archive", "backup_config_decrypted.json")


def load_backup_module_mappings():
    """
    Try to load module mappings from the backup config.
    Returns a dict keyed by serverId if any relevant data is found, else empty dict.
    """
    if not os.path.isfile(BACKUP_CONFIG_PATH):
        print(f"  Backup config not found at {BACKUP_CONFIG_PATH}, skipping.")
        return {}

    try:
        with open(BACKUP_CONFIG_PATH, "r") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"  Could not read backup config: {e}")
        return {}

    # Look for module_mapping or similar per-device fields
    # The backup config has: rn, pkg, searchConfig
    # pkg[].detail[] has {serverId, url, version} -- no module mapping
    # Check if any top-level key has module-related data
    module_mappings = {}

    if isinstance(data, dict):
        for key in data:
            if "module" in key.lower() or "mapping" in key.lower():
                print(f"  Found potential module mapping key: {key}")
                module_mappings[key] = data[key]

    if not module_mappings:
        print("  No module mapping data found in backup config.")

    return module_mappings


def main():
    print(f"Loading manifest from {MANIFEST_PATH}")
    with open(MANIFEST_PATH, "r") as f:
        manifest = json.load(f)

    print(f"Found {len(manifest)} devices in manifest.")

    # Try to load module mappings from backup config
    print("\nChecking backup config for module mappings...")
    module_mappings = load_backup_module_mappings()

    # Ensure output directory exists
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Build registry and copy files
    registry = []
    copied = 0
    skipped = 0
    missing = 0

    for entry in manifest:
        server_id = entry["serverId"]
        name = entry.get("name", "").strip()
        model = entry.get("model", "")
        hardware_id = entry.get("hardwareId", "")
        directory = entry.get("directory", "")
        command_count = entry.get("commandCount", 0)
        version = entry.get("version", 0)

        # Source path
        src = os.path.join(
            DEVICE_CONFIGS_DIR, directory, "decrypted", "code", "device_commands.json"
        )

        # Destination path
        dst = os.path.join(OUTPUT_DIR, f"{server_id}.json")

        registry_entry = {
            "serverId": server_id,
            "name": name,
            "model": model,
            "hardwareId": hardware_id,
            "commandCount": command_count,
            "version": version,
        }

        if os.path.isfile(src):
            shutil.copy2(src, dst)
            copied += 1
            registry_entry["hasCommands"] = True
        else:
            print(f"  MISSING: {src}")
            missing += 1
            registry_entry["hasCommands"] = False

        registry.append(registry_entry)

    # Sort registry by serverId for deterministic output
    registry.sort(key=lambda x: x["serverId"])

    # Write registry.json
    registry_path = os.path.join(OUTPUT_DIR, "registry.json")
    with open(registry_path, "w") as f:
        json.dump(registry, f, indent=2, ensure_ascii=False)

    print(f"\nDone.")
    print(f"  Devices in manifest:  {len(manifest)}")
    print(f"  Configs copied:       {copied}")
    print(f"  Missing configs:      {missing}")
    print(f"  Registry written to:  {registry_path}")
    print(f"  Output directory:     {OUTPUT_DIR}")

    # List output files
    output_files = sorted(os.listdir(OUTPUT_DIR))
    print(f"  Total output files:   {len(output_files)}")


if __name__ == "__main__":
    main()
