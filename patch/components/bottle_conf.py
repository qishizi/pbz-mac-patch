#!/usr/bin/env python3
"""Set (or undo) the D3DMetal graphics backend in a CrossOver bottle's cxbottle.conf.

    bottle_conf.py apply <cxbottle.conf> [KEY=VALUE ...]   extra settings go in the same block
    bottle_conf.py restore|status <cxbottle.conf>
    bottle_conf.py has <cxbottle.conf> KEY               exit 0 if our block sets KEY

The setting goes in [EnvironmentVariables] between two marker lines. A backend the
bottle had before is commented out where it stands and uncommented by restore, so a
restored file is the original byte for byte.
"""
import os, re, shutil, sys

BEGIN = ";; >>> pbz-crossover-patch"
END = ";; <<< pbz-crossover-patch"
WAS = ";; pbz-crossover-patch was: "
KEY = re.compile(r'^\s*"CX_GRAPHICS_BACKEND"\s*=')
SETTING = '"CX_GRAPHICS_BACKEND" = "d3dmetal"'
# the default Metal shader cache holds only part of this game's shaders, so every launch
# compiled the rest again; the value is a 32-bit byte count (2^32 or more turns it off)
CACHE = '"MTL_SHADER_CACHE_SIZE" = "4000000000"'


def strip_block(lines):
    """Lines without our block, with set-aside backend lines uncommented in place."""
    out, saved, inside = [], [], False
    for line in lines:
        s = line.rstrip("\n")
        if s == BEGIN:
            inside = True
        elif s == END:
            inside = False
        elif inside:
            continue
        elif s.startswith(WAS):
            saved.append(s[len(WAS):] + "\n")
            out.append(saved[-1])
        else:
            out.append(line)
    return out, saved


def env_section(lines):
    """(start, end) of the [EnvironmentVariables] body, or None."""
    start = None
    for i, line in enumerate(lines):
        if line.strip().startswith("["):
            if start is not None:
                return start, i
            if line.strip() == "[EnvironmentVariables]":
                start = i + 1
    return (start, len(lines)) if start is not None else None


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("apply", "restore", "status", "has"):
        sys.exit(__doc__)
    cmd, path, extra = sys.argv[1], sys.argv[2], sys.argv[3:]
    lines = open(path, encoding="utf-8").readlines()
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    applied = any(l.rstrip("\n") == BEGIN for l in lines)
    if cmd == "has":
        block, inside = [], False
        for l in lines:
            t = l.rstrip("\n")
            if t == BEGIN: inside = True
            elif t == END: inside = False
            elif inside: block.append(t)
        sys.exit(0 if any(b.startswith('"%s"' % extra[0]) for b in block) else 1)
    if cmd == "status":
        print("d3dmetal (set by this patch)" if applied else
              next((l.split("=", 1)[1].strip().strip('"') for l in lines if KEY.match(l)), "not set (Auto)"))
        return
    lines, saved = strip_block(lines)
    if cmd == "restore":
        result = "graphics backend restored" + (" to " + saved[0].strip() if saved else " (was Auto)")
    else:
        if not os.path.exists(path + ".orig-pbz"):
            shutil.copy2(path, path + ".orig-pbz")
        sec = env_section(lines)
        if sec is None:
            lines += ["[EnvironmentVariables]\n"]
            sec = (len(lines), len(lines))
        start, end = sec
        body = [WAS + l if KEY.match(l) else l for l in lines[start:end]]
        more = ['"%s" = "%s"\n' % tuple(kv.split("=", 1)) for kv in extra]
        lines[start:end] = [BEGIN + "\n", SETTING + "\n", CACHE + "\n"] + more + [END + "\n"] + body
        result = "graphics backend set to D3DMetal, Metal shader cache limit raised"
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.writelines(lines)
    shutil.copystat(path, tmp)
    os.replace(tmp, path)
    print(result)


if __name__ == "__main__":
    main()
