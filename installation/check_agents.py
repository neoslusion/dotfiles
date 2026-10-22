#!/usr/bin/env python3
"""Check that deployed agent wiring actually works, not just that files exist.

Usage: check_agents.py <home>

Prints one "pass|warn|fail <message>" line per check for doctor.sh and
windows/doctor.ps1 to relay. Read-only: inspects files, never runs the agents.

- Claude mods: the my-mods marketplace must point at <home>/.claude/mods and
  every mod in it must be installed. A registration pointing elsewhere (a
  deleted temp dir) makes every mod fail to load with no other symptom.
- Statusline commands (Claude, Antigravity): every path in the command must
  exist. On Windows the Antigravity command must be unquoted: it runs through
  cmd, which receives the quotes escaped and cannot find the program.
"""
import json
import os
import shlex
import shutil
import sys
from pathlib import Path


def emit(level, message):
    print(f"{level} {message}")


def load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def same_path(a, b):
    return os.path.normcase(os.path.abspath(a)) == os.path.normcase(os.path.abspath(b))


def check_mods(home):
    mods = home / ".claude" / "mods"
    catalog = load_json(mods / ".claude-plugin" / "marketplace.json")
    if catalog is None:
        return
    name = catalog.get("name", "my-mods")
    plugins_dir = home / ".claude" / "plugins"
    known = load_json(plugins_dir / "known_marketplaces.json")
    if not known or name not in known:
        emit("warn", f"claude: {name} not registered (needs the claude CLI; rerun the installer)")
        return
    paths = [known[name].get("source", {}).get("path")]
    settings = load_json(home / ".claude" / "settings.json") or {}
    declared = settings.get("extraKnownMarketplaces", {}).get(name)
    if declared:
        paths.append(declared.get("source", {}).get("path"))
    stale = [p for p in paths if not p or not same_path(p, mods)]
    if stale:
        emit("fail", f"claude: {name} registered at {stale[0]}, not {mods} (rerun the installer)")
        return
    installed = (load_json(plugins_dir / "installed_plugins.json") or {}).get("plugins", {})
    missing = [p["name"] for p in catalog.get("plugins", []) if f"{p['name']}@{name}" not in installed]
    if missing:
        emit("fail", f"claude: mods not installed: {', '.join(missing)} (rerun the installer)")
    else:
        emit("pass", f"claude: {name} mods registered")


def check_statusline(label, settings_path, unquoted):
    settings = load_json(settings_path)
    command = ((settings or {}).get("statusLine") or {}).get("command")
    if not command:
        return
    if unquoted and '"' in command:
        emit("fail", f"{label}: statusline command is quoted; cmd cannot run it (rerun the installer)")
        return
    # posix=False keeps Windows backslashes; strip the quotes it leaves on.
    parts = [p.strip('"') for p in shlex.split(command, posix=False)]
    missing = [p for p in parts if ("/" in p or "\\" in p) and not Path(p).exists()]
    if not missing and parts and shutil.which(parts[0]) is None and not Path(parts[0]).exists():
        missing = [parts[0]]
    if missing:
        emit("fail", f"{label}: statusline needs {missing[0]}, which does not exist")
    else:
        emit("pass", f"{label}: statusline command")


def main(home):
    home = Path(home)
    check_mods(home)
    check_statusline("claude", home / ".claude" / "settings.json", unquoted=False)
    check_statusline("antigravity", home / ".gemini" / "antigravity-cli" / "settings.json",
                     unquoted=os.name == "nt")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
