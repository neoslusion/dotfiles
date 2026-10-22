#!/usr/bin/env python3
# Claude Code statusline: agent mark, model, path, git, context %, cost.
# Claude re-runs this on every conversation event, so git results are cached
# for a second.
import json
import os
import subprocess
import sys
import time

STATE_FILE = os.path.join(os.path.expanduser("~"), ".cache", "dotfiles", "claude-statusline.json")
GIT_TTL_MS = 1000

C_ICON, C_MODEL, C_PATH, C_BRANCH = 213, 255, 117, 114
C_UNSTAGED, C_STAGED, C_UNTRACKED, C_COST = 214, 120, 245, 213
C_SEP, C_CTX_OK, C_CTX_WARN, C_CTX_HOT = 240, 114, 214, 203


def fg(code, s):
    return "\x1b[38;5;%dm%s\x1b[0m" % (code, s)


def git(cwd, *args):
    # --no-optional-locks: `git status` otherwise takes .git/index.lock to save
    # its index refresh. On Windows the timeout hard-kills git, which then
    # leaves that lock behind and breaks every later git command in the repo.
    p = subprocess.run(["git", "--no-optional-locks", "-C", cwd] + list(args), capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=1)
    return p.stdout if p.returncode == 0 else ""


def read_git(cwd):
    top = git(cwd, "rev-parse", "--show-toplevel").strip()
    info = {"top": top, "branch": "", "staged": 0, "unstaged": 0, "untracked": 0}
    if not top:
        return info
    for line in git(cwd, "status", "--porcelain=v2", "--branch").splitlines():
        if line.startswith("# branch.head "):
            info["branch"] = line[14:].strip()
        elif line[:2] in ("1 ", "2 ", "u "):
            xy = line[2:4]
            info["staged"] += xy[0] != "."
            info["unstaged"] += xy[1] != "."
        elif line.startswith("? "):
            info["untracked"] += 1
    return info


def short_path(cwd, top):
    out = cwd
    if top:
        cwd_n = os.path.normpath(cwd)
        top_n = os.path.normpath(top)
        leaf = os.path.basename(top_n)
        if os.path.normcase(cwd_n) == os.path.normcase(top_n):
            out = leaf
        elif os.path.normcase(cwd_n).startswith(os.path.normcase(top_n) + os.sep):
            out = leaf + "↳" + cwd_n[len(top_n) + 1:]
    if len(out) > 40:
        out = "…" + out[-39:]
    return out


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    j = json.loads(sys.stdin.read() or "{}")

    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            state = json.load(f)
    except (OSError, ValueError):
        state = {}

    model = j.get("model") or {}
    model_name = model.get("display_name") or model.get("id") or "claude"
    cwd = (j.get("workspace") or {}).get("current_dir") or j.get("cwd") or os.getcwd()

    now_ms = int(time.time() * 1000)
    if state.get("gitDir") == cwd and now_ms - int(state.get("gitAt") or 0) < GIT_TTL_MS:
        gi = state.get("git") or {}
    else:
        try:
            gi = read_git(cwd)
        except (OSError, subprocess.SubprocessError):
            gi = {}
        state.update(gitDir=cwd, gitAt=now_ms, git=gi)

    segs = [fg(C_ICON, "✻"), fg(C_MODEL, model_name), fg(C_PATH, short_path(cwd, gi.get("top", "")))]

    branch = gi.get("branch")
    if branch:
        seg = fg(C_BRANCH, " " + branch)
        if gi.get("unstaged"):
            seg += fg(C_UNSTAGED, " *%d" % gi["unstaged"])
        if gi.get("staged"):
            seg += fg(C_STAGED, " +%d" % gi["staged"])
        if gi.get("untracked"):
            seg += fg(C_UNTRACKED, " ?%d" % gi["untracked"])
        segs.append(seg)

    # Claude computes this against the model's real window; null until the
    # session's first API response, and again right after /compact.
    used_pct = (j.get("context_window") or {}).get("used_percentage")
    if used_pct is not None:
        pct = round(float(used_pct))
        color = C_CTX_HOT if pct >= 85 else C_CTX_WARN if pct >= 70 else C_CTX_OK
        segs.append(fg(color, "ctx %d%%" % pct))

    usd = (j.get("cost") or {}).get("total_cost_usd")
    if usd is not None:
        segs.append(fg(C_COST, "$%.2f" % float(usd)))

    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(state, f)
    except OSError:
        pass

    sys.stdout.write((" " + fg(C_SEP, "") + " ").join(segs) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # A statusline must never surface a traceback inside the agent's UI.
        sys.stdout.write("claude\n")
