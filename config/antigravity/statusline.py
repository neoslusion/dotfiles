#!/usr/bin/env python3
# Antigravity (AGY) statusline - port of oh-my-pi default preset
# Blazing fast (<50ms), zero external dependencies, 100% crash-proof.
import os
import sys
import json
import subprocess

def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    raw = ""
    try:
        raw = sys.stdin.read()
    except Exception:
        pass

    try:
        j = json.loads(raw) if raw and raw.strip() else {}
    except Exception:
        j = {}

    ESC = "\x1b"
    def fg(code, s):
        return f"{ESC}[38;5;{code}m{s}{ESC}[0m"

    c_icon = 39       # Cyan
    c_model = 255     # White
    c_path = 117      # Sky blue
    c_branch = 114    # Green
    c_unstaged = 214  # Orange
    c_staged = 120    # Light green
    c_untracked = 245 # Muted grey
    c_cost = 213      # Magenta
    c_sep = 240       # Dark grey
    c_ctx_ok = 114    # Green
    c_ctx_warn = 214  # Orange
    c_ctx_hot = 203   # Red

    sep = f" {fg(c_sep, chr(0xE0B1))} "
    mark = chr(0x03C0)      # pi symbol (omp signature)
    hexagon = chr(0x2B22)   # black hexagon (omp model icon)

    # 1. Model
    model = j.get("model") or {}
    model_name = model.get("display_name") or model.get("id") or "agy"
    model_seg = fg(c_model, f"{hexagon} {model_name}")

    # 2. Path (omp-style repo relative or leaf)
    ws = j.get("workspace") or {}
    cwd = ws.get("current_dir") or j.get("cwd") or os.getcwd()
    norm_cwd = os.path.normpath(cwd)
    leaf = os.path.basename(norm_cwd) or norm_cwd

    # 3. Git status (single sub-30ms git call)
    git_seg = ""
    branch = ""
    staged = 0
    unstaged = 0
    untracked = 0
    repo_root = ""

    try:
        p = subprocess.run(
            ["git", "-C", norm_cwd, "status", "--porcelain=v2", "--branch"],
            capture_output=True,
            text=True,
            timeout=0.6,
            encoding="utf-8",
            errors="replace"
        )
        if p.returncode == 0:
            for line in p.stdout.splitlines():
                if line.startswith("# branch.head "):
                    branch = line[14:].strip()
                elif line.startswith("1 ") or line.startswith("2 "):
                    parts = line.split(" ", 3)
                    if len(parts) >= 2:
                        xy = parts[1]
                        if len(xy) >= 2:
                            if xy[0] != ".":
                                staged += 1
                            if xy[1] != ".":
                                unstaged += 1
                elif line.startswith("? "):
                    untracked += 1
    except Exception:
        pass

    if branch and branch != "(detached)":
        git_seg = fg(c_branch, f"{chr(0xE0A0)} {branch}")
        if unstaged > 0:
            git_seg += fg(c_unstaged, f" *{unstaged}")
        if staged > 0:
            git_seg += fg(c_staged, f" +{staged}")
        if untracked > 0:
            git_seg += fg(c_untracked, f" ?{untracked}")

    # 4. Context Window % (omp style: ◫ pct%/limit ⟲)
    ctx_seg = ""
    ctx = j.get("context_window") or {}
    used_pct = ctx.get("used_percentage")
    if used_pct is not None:
        try:
            used_pct = float(used_pct)
            # agy names the window `context_window_size` (as Claude Code does);
            # when it is absent, show no limit rather than a guessed one.
            limit = ctx.get("context_window_size")
            limit_str = ""
            if limit:
                limit = int(limit)
                if limit >= 1000000:
                    limit_str = f"/{round(limit / 1000000)}M"
                elif limit >= 1000:
                    limit_str = f"/{round(limit / 1000)}K"
                else:
                    limit_str = f"/{limit}"
            cc = c_ctx_hot if used_pct >= 85 else (c_ctx_warn if used_pct >= 70 else c_ctx_ok)
            sq = chr(0x25EB)
            arr = chr(0x27F2)
            ctx_seg = fg(cc, f"{sq} {used_pct:.1f}%{limit_str} {arr}")
        except Exception:
            pass

    # 5. Quota (omp style: clock pct%)
    quota_seg = ""
    quota = j.get("quota") or {}
    rem = quota.get("remaining_fraction")
    if rem is not None:
        try:
            q_pct = round(float(rem) * 100)
            q_col = c_ctx_hot if q_pct < 20 else (c_ctx_warn if q_pct < 50 else c_ctx_ok)
            clock = chr(0x23F1)
            quota_seg = fg(q_col, f"{clock} {q_pct}%")
        except Exception:
            pass

    # 6. Cost (if present)
    cost_seg = ""
    cost = j.get("cost") or {}
    usd = cost.get("total_cost_usd")
    if usd is not None:
        try:
            cost_seg = fg(c_cost, f"${float(usd):.2f}")
        except Exception:
            pass

    # Assemble segments in oh-my-pi order
    segs = [fg(c_icon, mark), model_seg, fg(c_path, leaf)]
    if git_seg:
        segs.append(git_seg)
    if ctx_seg:
        segs.append(ctx_seg)
    if quota_seg:
        segs.append(quota_seg)
    if cost_seg:
        segs.append(cost_seg)

    output = sep.join(s for s in segs if s)
    if not output:
        output = "agy"

    sys.stdout.write(output + "\n")
    sys.stdout.flush()

if __name__ == "__main__":
    try:
        main()
    except Exception:
        try:
            sys.stdout.write("agy\n")
            sys.stdout.flush()
        except Exception:
            pass
    sys.exit(0)
