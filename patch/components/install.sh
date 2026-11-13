#!/bin/bash
# Install the Rosetta/Denuvo ntdll.so (CrossOver 26.3.0.39832 + the
# ntdll-rosetta-cpu-fidelity patch) into a CrossOver app, and set the CPUID
# variable for one game in one bottle.
#
#   install.sh apply   [app]            replace ntdll.so (backup kept)
#   install.sh restore [app]            put the original back
#   install.sh status  [app]
#   install.sh env     <bottle> [exe] [app]   WINE_ROSETTA_CPUID7_OR for exe (default PBZ.exe)
#   install.sh env-prefix <prefix> [runner] [exe]   the same for a plain wine prefix (NotProton)
#
# app defaults to "/Applications/CrossOver (GPTK 4.0b3).app"; it may also be a bare
# CrossOver directory such as NotProton's runners/crossover-26.3.0.39832/CrossOver.
# Quit CrossOver / Steam games first.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-status}"
APP="/Applications/CrossOver (GPTK 4.0b3).app"
NOTPROTON_RUNNER="$HOME/Library/Application Support/notproton/runners/crossover-26.3.0.39832/CrossOver"
case "$CMD" in
    env) [ -n "$4" ] && APP="$4" ;;
    env-prefix) APP="${3:-$NOTPROTON_RUNNER}" ;;
    *) [ -n "$2" ] && APP="$2" ;;
esac
ROOT="$APP/Contents/SharedSupport/CrossOver"
[ -d "$ROOT" ] || ROOT="$APP"
LIB="$ROOT/lib/wine/x86_64-unix/ntdll.so"
BAK="$LIB.orig-cx26.3"
ORIG_MD5=02473e972416a55681933d2dc2b7ab2f
# CodeWeavers has shipped 26.3.0.39832 signed more than once, so the same code can carry a
# different signature; this is the md5 of the original up to its code signature
ORIG_CODE_MD5=d51360228e2934eef2fd39b87c54e0c5
NEW_MD5=$(md5 -q "$HERE/ntdll.so")

code_md5() {   # md5 of a Mach-O file up to its LC_CODE_SIGNATURE data (the whole file if unsigned)
    python3 -I - "$1" <<'PY'
import hashlib, struct, sys
d = open(sys.argv[1], "rb").read()
end = len(d)
if d[:4] == b"\xcf\xfa\xed\xfe":
    ncmds = struct.unpack_from("<I", d, 16)[0]
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", d, off)
        if cmd == 0x1d:
            end = struct.unpack_from("<I", d, off + 8)[0]
        off += size
print(hashlib.md5(d[:end]).hexdigest())
PY
}
# earlier builds of this package that may be upgraded in place
OLD_MD5S="d889d6b3ac751386466f197b2d3e1446 ef1d0875a1e338d43ee428a55025e134"

state() {
    local sum
    sum=$(md5 -q "$LIB")
    case "$sum" in
        $ORIG_MD5) echo original; return ;;
        $NEW_MD5)  echo patched; return ;;
    esac
    [ "$(code_md5 "$LIB")" = "$ORIG_CODE_MD5" ] && { echo original; return; }
    case " $OLD_MD5S " in
        *" $sum "*) echo old-patch ;;
        *)          echo unknown ;;
    esac
}

same_release() {   # CrossOver says 26.3.0.39832 and ntdll.so carries CodeWeavers' signature
    grep -q '"ProductVersion" = "26.3.0.39832"' "$ROOT/share/crossover/data/CrossOver.conf" 2>/dev/null &&
        codesign -dvv "$LIB" 2>&1 | grep -q "Authority=Developer ID Application: CodeWeavers" && codesign -v "$LIB" 2>/dev/null
}

running() { ps axo comm= | grep -F "$ROOT/" | grep -q '/wineserver$'; }

case "$CMD" in
status)
    echo "$(state)  ($LIB)"
    ;;
apply)
    running && { echo "a wineserver from this app is running; quit CrossOver and its programs first"; exit 1; }
    s=$(state)
    [ "$s" = patched ] && { echo "already patched"; exit 0; }
    case "$s" in
        original)  cp -p "$LIB" "$BAK" ;;
        old-patch) { [ "$(md5 -q "$BAK" 2>/dev/null)" = $ORIG_MD5 ] || [ "$(code_md5 "$BAK" 2>/dev/null)" = $ORIG_CODE_MD5 ]; } || { echo "upgrade needs the original backup at $BAK; nothing changed"; exit 1; } ;;
        *)
            if [ -n "$PBZ_FORCE" ] && same_release; then
                echo "ntdll.so is a different compile of CrossOver 26.3.0.39832 (CodeWeavers-signed); --force: replacing it"
                cp -p "$LIB" "$BAK"
            else
                echo "ntdll.so is not the CrossOver 26.3.0.39832 original; nothing changed"
                same_release && echo "  it is CodeWeavers-signed 26.3.0.39832 though: rerun with --force to replace it (a backup is kept)"
                exit 1
            fi ;;
    esac
    cp "$HERE/ntdll.so" "$LIB.tmp" && chmod 755 "$LIB.tmp" && xattr -c "$LIB.tmp" && mv "$LIB.tmp" "$LIB"
    echo "patched; original kept as $BAK"
    ;;
restore)
    running && { echo "a wineserver from this app is running; quit CrossOver and its programs first"; exit 1; }
    [ -f "$BAK" ] || { echo "no backup at $BAK"; exit 1; }
    cp -p "$BAK" "$LIB" && echo "restored: $(state)"
    ;;
env)
    BOTTLE="$2"; EXE="${3:-PBZ.exe}"
    [ -n "$BOTTLE" ] || { echo "usage: install.sh env <bottle> [exe]"; exit 1; }
    # read by the patched ntdll for this exe even when an already-running Steam starts it
    "$ROOT/bin/wine" --bottle "$BOTTLE" reg add \
        "HKCU\\Software\\Wine\\AppDefaults\\$EXE\\Environment" \
        /v WINE_ROSETTA_CPUID7_OR /t REG_SZ /d 01800000,00400000 /f
    ;;
env-prefix)
    PFX="$2"; EXE="${4:-PBZ.exe}"
    [ -d "$PFX" ] || { echo "usage: install.sh env-prefix <prefix> [runner] [exe]"; exit 1; }
    # NotProton's run script drops WINE_* from the launch environment; the registry copy still reaches the game
    WINEPREFIX="$PFX" WINEDEBUG=-all "$ROOT/lib/wine/x86_64-unix/wine" reg add \
        "HKCU\\Software\\Wine\\AppDefaults\\$EXE\\Environment" \
        /v WINE_ROSETTA_CPUID7_OR /t REG_SZ /d 01800000,00400000 /f
    WINEPREFIX="$PFX" "$ROOT/bin/wineserver" -w
    ;;
*)
    sed -n '2,17p' "$0"; exit 1 ;;
esac
