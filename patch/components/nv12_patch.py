#!/usr/bin/env python3
"""Binary-patch CrossOver 26.3.0.39832's x86_64 winegstreamer.dll so the H.264
decoder MFT behaves like winevideo's patch 0006:

  * not D3D-aware on macOS (MF_SA_D3D_AWARE / MF_SA_D3D11_AWARE = 0)
  * MFT_MESSAGE_SET_D3D_MANAGER -> E_NOTIMPL
  * NV12 offered again in GetOutputAvailableType (CW HACK 26265 disabled)

UE5 Electra only takes NV12; without a D3D manager the frames stay in system
memory, so D3DMetal never has to create an NV12 texture.

Usage:  nv12_patch.py apply | restore | status  [app]
        app defaults to "/Applications/CrossOver (GPTK 4.0b3).app"; a bare CrossOver
        directory (NotProton's runners/crossover-26.3.0.39832/CrossOver) works too
"""
import hashlib, os, shutil, subprocess, sys

ORIG_MD5 = "605b62640fd890013278f9174cd38ddc"

# (file offset, original bytes, patched bytes, what)
PATCHES = [
    (0x2bab2, "75 0c", "eb 0c", "GetOutputAvailableType: never skip NV12"),
    (0x2dbd2, "48 8b 8e d0 00 00 00", "b8 01 40 00 80 eb 91",
     "ProcessMessage(SET_D3D_MANAGER): return E_NOTIMPL"),
    (0x3334e, "41 b8 01 00 00 00", "41 b8 00 00 00 00", "MF_SA_D3D_AWARE = 0"),
    (0x33372, "41 b8 01 00 00 00", "41 b8 00 00 00 00", "MF_SA_D3D11_AWARE = 0"),
]


def state(data):
    s = set()
    for off, orig, new, _ in PATCHES:
        cur = data[off:off + len(bytes.fromhex(orig))]
        s.add("original" if cur == bytes.fromhex(orig) else "patched" if cur == bytes.fromhex(new) else "unknown")
    return s.pop() if len(s) == 1 else "mixed"


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    app = sys.argv[2] if len(sys.argv) > 2 else "/Applications/CrossOver (GPTK 4.0b3).app"
    root = os.path.join(app, "Contents/SharedSupport/CrossOver")
    if not os.path.isdir(root):
        root = app  # a bare CrossOver directory, e.g. NotProton's runner
    dll = os.path.join(root, "lib/wine/x86_64-windows/winegstreamer.dll")
    bak = dll + ".orig-cx26.3"
    data = bytearray(open(dll, "rb").read())
    st = state(data)

    if cmd == "status":
        print(st, f"({dll})")
        return
    procs = subprocess.run(["ps", "axo", "comm="], capture_output=True, text=True).stdout.splitlines()
    if cmd in ("apply", "restore") and any(p.startswith(root + "/") and p.endswith("/wineserver") for p in procs):
        sys.exit("a wineserver from this app is running; quit CrossOver and its programs first")
    if cmd == "apply":
        if st == "patched":
            print("already patched"); return
        if st != "original":
            sys.exit("not the CrossOver 26.3.0.39832 winegstreamer.dll; nothing changed")
        if hashlib.md5(data).hexdigest() != ORIG_MD5:
            # another compile of the release: all four sites must still hold the expected bytes
            print("note: winegstreamer.dll differs from the reference copy, but every patch site matches")
        shutil.copy2(dll, bak)
        for off, orig, new, what in PATCHES:
            data[off:off + len(bytes.fromhex(new))] = bytes.fromhex(new)
            print("patched", hex(off), what)
        tmp = dll + ".tmp"
        open(tmp, "wb").write(data)
        shutil.copystat(bak, tmp)
        os.replace(tmp, dll)
        print("done:", state(bytearray(open(dll, "rb").read())), "- original saved as", bak)
    elif cmd == "restore":
        if not os.path.exists(bak):
            sys.exit("no backup at " + bak)
        shutil.copy2(bak, dll)
        print("restored:", state(bytearray(open(dll, "rb").read())))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
