#!/bin/bash
# Give a CrossOver tree the complete D3DMetal 4.0b3 set (framework, libd3dshared and the
# Windows-side DLLs incl. d3d12core).
#
#   gptk_d3dmetal.sh status  <root>
#   gptk_d3dmetal.sh apply   <root> <source>
#   gptk_d3dmetal.sh restore <root>
#   gptk_d3dmetal.sh find    <source>        print the D3DMetal dir found in <source>
#
# <root> is a CrossOver directory (…/CrossOver, holding lib64/apple_gptk).
# <source> may be a CrossOver .app or directory that has D3DMetal 4.0b3, Apple's Game
# Porting Toolkit .dmg as downloaded (mounted read-only for the run) or its mounted disk,
# its "redist/lib" folder, or any folder holding external/ and wine/ like it.
set -e
CMD="$1"; ROOT="$2"; SRC="$3"
G="$ROOT/lib64/apple_gptk"
BAK="$ROOT/lib64/apple_gptk.orig-cx26.3"

# Apple's download is a .dmg that holds a second .dmg with the toolkit: mount both
# read-only, use the inner one, and detach them again on exit
MOUNTS=()
cleanup() { local i; for ((i = ${#MOUNTS[@]} - 1; i >= 0; i--)); do hdiutil detach -quiet "${MOUNTS[i]}" 2>/dev/null && rmdir "${MOUNTS[i]}" 2>/dev/null; done; true; }
trap cleanup EXIT
mount_dmg() {   # mount_dmg <file.dmg>: mount it and set MP (no subshell, so MOUNTS keeps it)
    MP=$(mktemp -d "${TMPDIR:-/tmp}/pbz-gptk.XXXXXX")
    hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$MP" "$1" >/dev/null || return 1
    MOUNTS+=("$MP")
}
open_source() {   # a .dmg in SRC (outer or inner) becomes its mounted folder
    local inner
    case "$SRC" in *.dmg) [ -f "$SRC" ] && mount_dmg "$SRC" && SRC="$MP" ;; esac
    [ -d "$SRC" ] || return 0
    inner=$(ls -d "$SRC"/Evaluation*environment*.dmg 2>/dev/null | head -1)
    if [ -n "$inner" ] && mount_dmg "$inner"; then SRC="$MP"; fi
}

version() {
    local plist
    plist=$(find "$1/external/D3DMetal.framework/" -name Info.plist 2>/dev/null | head -1)
    [ -n "$plist" ] && /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo none
}

find_src() {   # find_src <source>: the dir that holds external/ and wine/
    local d
    for d in "$1/Contents/SharedSupport/CrossOver/lib64/apple_gptk" "$1/lib64/apple_gptk" \
             "$1/redist/lib" "$1/lib" "$1"; do
        [ -d "$d/external/D3DMetal.framework" ] && [ -d "$d/wine/x86_64-windows" ] && { echo "$d"; return 0; }
    done
    # a folder that holds one a level or two down, e.g. GPTK Patcher's GPTKPatcher/Toolkits/4.0b3
    for d in "$1"/*/ "$1"/*/*/; do
        d="${d%/}"
        [ -d "$d/external/D3DMetal.framework" ] && [ -d "$d/wine/x86_64-windows" ] &&
            [ "$(version "$d")" = 4.0b3 ] && { echo "$d"; return 0; }
    done
    return 1
}

complete() {   # same Windows-side DLLs and the same D3DMetal binaries as the source
    # (the unix side is only links to libd3dshared, which apply may have added itself)
    # (and nvngx.dll, which apply makes from nvngx-on-metalfx.dll for DLSS)
    diff -rq -x nvngx.dll "$G/wine/x86_64-windows" "$S/wine/x86_64-windows" >/dev/null 2>&1 &&
        cmp -s "$G/wine/x86_64-windows/nvngx.dll" "$G/wine/x86_64-windows/nvngx-on-metalfx.dll" &&
        cmp -s "$G/external/libd3dshared.dylib" "$S/external/libd3dshared.dylib" &&
        cmp -s "$G/external/D3DMetal.framework/Versions/A/D3DMetal" "$S/external/D3DMetal.framework/Versions/A/D3DMetal"
}

running() { ps axo comm= | grep -F "$ROOT/" | grep -q '/wineserver$'; }

case "$CMD" in
status)
    v=$(version "$G"); extra=""
    case "$v" in 4.*) [ -e "$G/wine/x86_64-windows/d3d12core.dll" ] || extra=" (no d3d12core: D3D12 falls back to vkd3d)" ;; esac
    case "$v" in 4.*) cmp -s "$G/wine/x86_64-windows/nvngx.dll" "$G/wine/x86_64-windows/nvngx-on-metalfx.dll" || extra="$extra (no DLSS nvngx.dll)" ;; esac
    echo "D3DMetal $v$extra"
    ;;
find)
    SRC="$ROOT"; open_source
    S=$(find_src "$SRC") || { echo "no D3DMetal in $ROOT" >&2; exit 1; }
    echo "$S"
    ;;
apply)
    open_source
    if ! S=$(find_src "$SRC"); then
        # Apple's download is a disk that holds a second disk image with the toolkit
        if ls "$SRC"/Evaluation*environment*.dmg >/dev/null 2>&1; then
            echo "D3DMetal: $SRC is the outer Game Porting Toolkit disk. Open it, double-click"
            echo "  \"Evaluation environment for Windows games ...dmg\" inside, and pass that second disk; skipped"
        else
            echo "D3DMetal: no D3DMetal found in $SRC; skipped"
        fi
        exit 0
    fi
    [ "$(version "$S")" = 4.0b3 ] || { echo "D3DMetal: $S has $(version "$S"), not 4.0b3; skipped"; exit 0; }
    [ -e "$S/wine/x86_64-windows/d3d12core.dll" ] || { echo "D3DMetal: $S lacks d3d12core.dll; skipped"; exit 0; }
    [ "$S" = "$G" ] && { echo "D3DMetal 4.0b3 already in place"; exit 0; }
    if complete; then echo "D3DMetal 4.0b3 already complete"; exit 0; fi
    running && { echo "a wineserver from this CrossOver is running; quit the game first"; exit 1; }
    # an earlier manual swap kept its backups inside apple_gptk: rebuild the original first
    [ ! -e "$BAK" ] && [ -d "$G/external/D3DMetal.framework.bak-3.0" ] && "$0" restore "$ROOT" >/dev/null
    if [ -e "$BAK" ]; then rm -rf "$G"; else mv "$G" "$BAK"; fi
    ditto --norsrc --noextattr "$S" "$G"
    # CrossOver sends the game's nvngx.dll (DLSS) to apple_gptk/wine; Apple ships it as nvngx-on-metalfx
    [ -f "$G/wine/x86_64-windows/nvngx-on-metalfx.dll" ] && cp -p "$G/wine/x86_64-windows/nvngx-on-metalfx.dll" "$G/wine/x86_64-windows/nvngx.dll"
    # Apple's GPTK names the unix side after the DLLs; make sure each DLL has its .so link
    for dll in "$G"/wine/x86_64-windows/*.dll; do
        so="$G/wine/x86_64-unix/$(basename "${dll%.dll}").so"
        [ -e "$so" ] || ln -s ../../external/libd3dshared.dylib "$so"
    done
    echo "D3DMetal 4.0b3 copied from $S (original kept as $BAK)"
    ;;
restore)
    running && { echo "a wineserver from this CrossOver is running; quit the game first"; exit 1; }
    if [ -d "$BAK" ]; then
        rm -rf "$G" && mv "$BAK" "$G"
        echo "D3DMetal restored to $(version "$G")"
    elif [ -d "$G/external/D3DMetal.framework.bak-3.0" ] && [ -d "$G/bak-3.0-wineside" ]; then
        # layout left by the earlier manual swap: backups kept inside apple_gptk
        W="$G/bak-3.0-wineside"
        rm -rf "$G/external/D3DMetal.framework"
        mv "$G/external/D3DMetal.framework.bak-3.0" "$G/external/D3DMetal.framework"
        cp -p "$W/external/libd3dshared.dylib" "$G/external/libd3dshared.dylib"
        for f in d3d10 d3d12core nvngx-on-metalfx; do
            rm -f "$G/wine/x86_64-windows/$f.dll" "$G/wine/x86_64-unix/$f.so"
        done
        cp -p "$W/wine/x86_64-windows/"*.dll "$G/wine/x86_64-windows/"
        [ -e "$W/wine/x86_64-unix/atidxx64.so" ] && mv "$W/wine/x86_64-unix/atidxx64.so" "$G/wine/x86_64-unix/"
        rm -rf "$W"
        echo "D3DMetal restored to $(version "$G")"
    else
        echo "D3DMetal: no backup; left as $(version "$G")"
    fi
    ;;
*)
    sed -n '2,13p' "$0"; exit 1 ;;
esac
