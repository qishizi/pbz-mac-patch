#!/bin/bash
# Phantom Blade Zero in a CrossOver 26.3.0.39832 bottle (Windows Steam inside the bottle)
#
#   crossover.sh status  [--bottle NAME] [--app PATH]
#   crossover.sh bottles                       one line per bottle: name, Windows Steam, game
#   crossover.sh apply   --bottle NAME [--app PATH] [--d3dmetal SRC]
#   crossover.sh restore --bottle NAME [--app PATH]
#
# --bottle     the bottle Windows Steam is installed in (as named in CrossOver)
# --app        the CrossOver app: default "CrossOver (GPTK 4.0b3).app", else CrossOver.app
# --d3dmetal   where to take D3DMetal 4.0b3 from (default: the copy in components/gptk):
#              Apple's Game Porting Toolkit 4.0 beta 3
#              (the mounted disk image or its redist/lib folder) or a CrossOver that has it
#
# Quit CrossOver first. Every step keeps a backup and can be undone.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
C="$HERE/components"
BOTTLES="$HOME/Library/Application Support/CrossOver/Bottles"
DLLS="msvcp140 msvcp140_1 msvcp140_2 msvcp140_atomic_wait msvcp140_codecvt_ids vcruntime140 vcruntime140_1 vcruntime140_threads"
APPKEY='HKEY_CURRENT_USER\Software\Wine\AppDefaults\PBZ.exe'

# files from a downloaded zip carry the quarantine flag, and macOS will not load a
# quarantined ntdll.so into wine
xattr -dr com.apple.quarantine "$HERE" 2>/dev/null || true

CMD="${1:-status}"; APP=""; BOTTLE=""; D3DM=""
shift || true
while [ $# -gt 0 ]; do
    case "$1" in
        --app)      APP="$2"; shift 2 ;;
        --bottle)   BOTTLE="$2"; shift 2 ;;
        --d3dmetal) D3DM="$2"; shift 2 ;;
        *) sed -n '2,13p' "$0"; exit 1 ;;
    esac
done
if [ -z "$APP" ]; then
    for a in "/Applications/CrossOver (GPTK 4.0b3).app" "/Applications/CrossOver.app"; do
        [ -d "$a" ] && { APP="$a"; break; }
    done
fi
APP_ROOT="$APP/Contents/SharedSupport/CrossOver"
if [ "$CMD" = bottles ]; then
    # Windows Steam and the game inside each bottle (default Steam library on C:)
    for b in "$BOTTLES"/*/; do
        [ -f "$b/cxbottle.conf" ] || continue
        st="$b/drive_c/Program Files (x86)/Steam"
        steam=no; [ -f "$st/steam.exe" ] && steam=yes
        game=no; [ -f "$st/steamapps/common/PBZ/platform/steam/PBZ.exe" ] && game=yes
        echo "bottle: $(basename "$b")|steam=$steam|game=$game"
    done
    exit 0
fi
[ -d "$APP_ROOT" ] || { echo "CrossOver not found: ${APP:-none in /Applications}"; exit 1; }
# the copy of Apple's Game Porting Toolkit 4.0 beta 3 redistributables in components/gptk
# (distributed non-commercially under Apple's license, included there) comes first
[ -z "$D3DM" ] && "$C/gptk_d3dmetal.sh" find "$C/gptk" >/dev/null 2>&1 && D3DM="$C/gptk"
if [ -z "$D3DM" ]; then
    for a in "/Applications/CrossOver (GPTK 4.0b3).app" "$APP"; do
        s=$("$C/gptk_d3dmetal.sh" find "$a" 2>/dev/null) || continue
        [ -e "$s/wine/x86_64-windows/d3d12core.dll" ] && { D3DM="$a"; break; }
    done
fi
BDIR="$BOTTLES/$BOTTLE"
CONF="$BDIR/cxbottle.conf"

need_bottle() {
    [ -n "$BOTTLE" ] || { echo "say which bottle: --bottle NAME"; exit 1; }
    [ -f "$CONF" ] || { echo "no bottle \"$BOTTLE\" in $BOTTLES"; exit 1; }
}

crossover_closed() {
    if pgrep -f "$APP/Contents/MacOS/" >/dev/null || ps axo comm= | grep -F "$APP_ROOT/" | grep -q '/wineserver$'; then
        echo "quit CrossOver (and the game) first"; exit 1
    fi
}

# GPTK Patcher's "DLSS to MetalFX in every bottle" option puts D3DM_ENABLE_METALFX=1 (and
# DXMT_ENABLE_NVEXT=1) into the app's own CrossOver.conf. That makes every program see an NVIDIA
# GPU, and Steam's built-in browser then draws a black window.
# apply comments those lines out (marked, so restore can put them back).
APP_CONF="$APP_ROOT/etc/CrossOver.conf"
MARK=";; pbz-crossover-patch off: "
global_metalfx() {   # global_metalfx off|on|status
    [ -f "$APP_CONF" ] || { [ "$1" = status ] && echo "not set"; return 0; }
    case "$1" in
    status)
        if grep -qE '^"(D3DM_ENABLE_METALFX|DXMT_ENABLE_NVEXT)" = "1"' "$APP_CONF"; then echo "on (all bottles)"
        elif grep -qF "$MARK" "$APP_CONF"; then echo "off (turned off by this patch)"
        else echo "not set"; fi ;;
    off)
        grep -qE '^"(D3DM_ENABLE_METALFX|DXMT_ENABLE_NVEXT)" = "1"' "$APP_CONF" || return 0
        [ -e "$APP_CONF.orig-pbz" ] || cp -p "$APP_CONF" "$APP_CONF.orig-pbz"
        sed -i '' -E "s/^(\"(D3DM_ENABLE_METALFX|DXMT_ENABLE_NVEXT)\" = \"1\")/$MARK\1/" "$APP_CONF"
        echo "CrossOver.conf: global D3DM_ENABLE_METALFX / DXMT_ENABLE_NVEXT turned off (Steam would show a black window)" ;;
    on)
        grep -qF "$MARK" "$APP_CONF" || return 0
        sed -i '' "s/^$MARK//" "$APP_CONF"
        echo "CrossOver.conf: global MetalFX settings put back" ;;
    esac
}

SHADER_DIR="$HOME/Library/Application Support/notproton/pbzshader"   # left by earlier patch versions

registry() {   # registry add|delete: per-game settings in the bottle, for PBZ.exe only
    local reg="$BDIR/drive_c/pbz-crossover-patch.reg" d
    {
        echo "REGEDIT4"; echo
        echo "[$APPKEY\\Environment]"
        if [ "$1" = add ]; then echo '"WINE_ROSETTA_CPUID7_OR"="01800000,00400000"'; else echo '"WINE_ROSETTA_CPUID7_OR"=-'; fi
        echo; echo "[$APPKEY\\DllOverrides]"
        for d in $DLLS; do
            if [ "$1" = add ]; then echo "\"$d\"=\"native,builtin\""; else echo "\"$d\"=-"; fi
        done
    } > "$reg"
    "$APP_ROOT/bin/wine" --bottle "$BOTTLE" regedit /S 'C:\pbz-crossover-patch.reg' >/dev/null 2>&1 || true
    "$APP_ROOT/bin/wineserver" --bottle "$BOTTLE" -w >/dev/null 2>&1 || WINEPREFIX="$BDIR" "$APP_ROOT/bin/wineserver" -w 2>/dev/null || true
    rm -f "$reg"
    if [ "$1" = add ]; then
        grep -q '"WINE_ROSETTA_CPUID7_OR"="01800000,00400000"' "$BDIR/user.reg" &&
            echo "registry: CPUID setting and native VC++ runtime set for PBZ.exe" ||
            { echo "registry: could not write the settings into bottle $BOTTLE"; return 1; }
    else
        echo "registry: PBZ.exe settings removed"
    fi
}

case "$CMD" in
status)
    echo "crossover app: $APP"
    echo "crossover version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null)"
    pgrep -f "$APP/Contents/MacOS/" >/dev/null && echo "crossover running: yes" || echo "crossover running: no"
    echo "$(basename "$APP"):"
    echo "  ntdll.so (Denuvo/Rosetta + D3DMetal fallback): $("$C/install.sh" status "$APP" | cut -d' ' -f1)"
    echo "  winegstreamer.dll (NV12 video):                 $(python3 -I "$C/nv12_patch.py" status "$APP" | cut -d' ' -f1)"
    echo "  $("$C/gptk_d3dmetal.sh" status "$APP_ROOT")"
    echo "  global MetalFX (DLSS) setting: $(global_metalfx status)"
    if [ -n "$BOTTLE" ] && [ -f "$CONF" ]; then
        echo "bottle $BOTTLE:"
        echo "  graphics backend: $(python3 -I "$C/bottle_conf.py" status "$CONF")"
        grep -q '"WINE_ROSETTA_CPUID7_OR"="01800000,00400000"' "$BDIR/user.reg" && r=set || r="not set"
        echo "  PBZ.exe registry settings: $r"
    fi
    echo "D3DMetal 4.0b3 source: ${D3DM:-none found}"
    ;;
apply)
    need_bottle; crossover_closed
    "$C/install.sh" apply "$APP"
    python3 -I "$C/nv12_patch.py" apply "$APP"
    if [ -n "$D3DM" ]; then "$C/gptk_d3dmetal.sh" apply "$APP_ROOT" "$D3DM"
    else echo "D3DMetal: no 4.0b3 source found; pass --d3dmetal <Game Porting Toolkit 4.0 beta 3>"; fi
    global_metalfx off
    python3 -I "$C/bottle_conf.py" apply "$CONF"   # also drops the D3DMetal copy of earlier patch versions
    rm -rf "${SHADER_DIR:?}"
    registry add
    echo
    echo "Done. In bottle \"$BOTTLE\", start Steam, install Phantom Blade Zero and play; no launch options are needed."
    ;;
restore)
    need_bottle; crossover_closed
    "$C/install.sh" restore "$APP" || true
    python3 -I "$C/nv12_patch.py" restore "$APP" || true
    "$C/gptk_d3dmetal.sh" restore "$APP_ROOT" || true
    python3 -I "$C/bottle_conf.py" restore "$CONF" || true
    global_metalfx on || true
    rm -rf "${SHADER_DIR:?}"
    registry delete || true
    ;;
*)
    sed -n '2,13p' "$0"; exit 1 ;;
esac
