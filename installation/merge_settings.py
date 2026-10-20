#!/usr/bin/env python3
"""Merge the repo's Claude settings into a live settings.json.

Usage: merge_settings.py <rendered-repo-settings.json> <live-settings.json>

Other tools write into the same file (rtk's hook, other installers' hooks and
settings, /plugin, /effort), so replacing it would wipe their entries on every
refresh. Repo keys win, nested objects merge, and every key the repo does not
set is kept - which also means a key deleted from the repo is NOT removed from
the live file. A missing or unparseable live file is
replaced outright (nothing in it can be preserved). Mirrored by
Merge-JsonObject in windows/install.ps1.
"""
import copy
import json
import shutil
import sys
from pathlib import Path


def merge(live, repo):
    for key, value in repo.items():
        if isinstance(value, dict) and isinstance(live.get(key), dict):
            merge(live[key], value)
        else:
            live[key] = value
    return live


def main(repo_path, live_path):
    repo = json.loads(Path(repo_path).read_text(encoding="utf-8"))
    live_file = Path(live_path)
    try:
        live = json.loads(live_file.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        live = None
    if not isinstance(live, dict):
        live = None
    merged = merge(copy.deepcopy(live or {}), repo)
    # Compare content, not text: Claude rewrites the file in its own JSON style,
    # and only a real change should rewrite it (and leave a .bak).
    if merged == live:
        return 0
    if live_file.exists():
        shutil.copy2(live_file, live_file.with_name(live_file.name + ".bak"))
    # Bytes, not text mode: no newline translation on Windows.
    live_file.write_bytes((json.dumps(merged, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
