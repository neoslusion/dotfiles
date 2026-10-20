import os
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple


SCRIPT_PATH = Path(__file__).resolve()
REPO_ROOT = SCRIPT_PATH.parent.parent
REPO_NVIM_DIR = REPO_ROOT / "config" / "nvim" / "lua"
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
XDG_NVIM_DIR = XDG_CONFIG_HOME / "nvim" / "lua"

DIRECT_RE = re.compile(
    r'(?:keymap|vim\.keymap\.set)\(\s*(?P<mode>[^,]+),\s*["\'](?P<lhs>[^"\']+)["\']'
)
SPEC_RE = re.compile(r'^\s*\{\s*["\'](?P<lhs>[^"\']+)["\']')
MODE_RE = re.compile(r'mode\s*=\s*(?P<mode>\{[^}]+\}|["\'][^"\']+["\'])')


def normalize_mode(mode: str) -> str:
    mode = mode.strip()
    if mode.startswith("{"):
        return ",".join(re.findall(r'["\']([^"\']+)["\']', mode)) or "?"
    if mode.startswith(("'", '"')):
        return mode.strip("'\"")
    return mode


def interesting(lhs: str) -> bool:
    return (
        lhs.startswith("<leader>")
        or lhs.startswith("<C-")
        or lhs.startswith("<A-")
        or lhs.startswith("<M-")
        or lhs.startswith("<F")
    )


def resolve_target(target_arg: Optional[str]) -> Tuple[Path, Path]:
    if target_arg:
        target = Path(target_arg).expanduser().resolve()
        candidates = [
            (target, target) if target.name == "lua" else (target / "lua", target),
            (target / "config" / "nvim" / "lua", target),
        ]
    elif REPO_NVIM_DIR.is_dir():
        candidates = [(REPO_NVIM_DIR, REPO_ROOT)]
    else:
        candidates = [(XDG_NVIM_DIR, XDG_CONFIG_HOME)]

    for nvim_dir, root in candidates:
        if nvim_dir.is_dir():
            return root, nvim_dir

    return candidates[0][1], candidates[0][0]


def iter_lua_files(nvim_dir: Path):
    targets = [
        nvim_dir / "config",
        nvim_dir / "plugins",
    ]

    for target in targets:
        if target.is_dir():
            yield from sorted(target.glob("*.lua"))


def main() -> int:
    if len(sys.argv) > 2:
        print("Usage: audit-nvim-keymaps [repo-root|nvim-config-root]", file=sys.stderr)
        return 2

    root, nvim_dir = resolve_target(sys.argv[1] if len(sys.argv) == 2 else None)
    lua_files = list(iter_lua_files(nvim_dir))
    if not lua_files:
        print(f"No Neovim Lua files found under {nvim_dir}", file=sys.stderr)
        return 2

    bindings: Dict[Tuple[str, str], List[Tuple[Path, int, str]]] = defaultdict(list)

    for path in lua_files:
        for line_no, line in enumerate(path.read_text(encoding='utf-8').splitlines(), start=1):
            direct = DIRECT_RE.search(line)
            if direct:
                mode = normalize_mode(direct.group("mode"))
                lhs = direct.group("lhs")
                if interesting(lhs):
                    bindings[(lhs, mode)].append((path, line_no, line.strip()))
                continue

            spec = SPEC_RE.search(line)
            if spec:
                lhs = spec.group("lhs")
                if interesting(lhs):
                    mode_match = MODE_RE.search(line)
                    mode = normalize_mode(mode_match.group("mode")) if mode_match else "n"
                    bindings[(lhs, mode)].append((path, line_no, line.strip()))

    duplicates = {key: value for key, value in bindings.items() if len(value) > 1}
    if not duplicates:
        print("No duplicate Neovim keymaps found.")
        return 0

    print("Duplicate Neovim keymaps:")
    for (lhs, mode), locations in sorted(duplicates.items()):
        print(f"\n{lhs} [{mode}]")
        for path, line_no, line in locations:
            rel = path.relative_to(root)
            print(f"  {rel}:{line_no}: {line}")

    return 1


if __name__ == "__main__":
    sys.exit(main())
