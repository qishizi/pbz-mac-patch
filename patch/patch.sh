#!/bin/bash
# Phantom Blade Zero on CrossOver 26.3.0.39832 (macOS, Apple silicon)
#
#   patch.sh status    [--app PATH]
#   patch.sh apply     notproton [--d3dmetal SRC] [--force]
#   patch.sh apply     crossover [--app PATH] [--bottle NAME] [--d3dmetal SRC]
#   patch.sh lsfg      on|off           Lossless Scaling frame generation under NotProton
#   patch.sh fsr4      on|off           optional FSR 4 upscaling under NotProton (costs frame rate)
#   patch.sh restore   notproton
#   patch.sh restore   crossover [--app PATH] [--bottle NAME]
#
# notproton    NotProton's runner + the game's Steam prefix (compatdata/4115450)
# crossover    a CrossOver app: --app, else "CrossOver (GPTK 4.0b3).app", else CrossOver.app
# --bottle     also set the CPUID variable for PBZ.exe in that CrossOver bottle
# --d3dmetal   where to take D3DMetal 4.0b3 from (default: the copy in components/gptk):
#              Apple's Game Porting Toolkit 4.0 beta 3
#              (the mounted disk image or its redist/lib folder) or a CrossOver that has it
#
# --force      accept a CodeWeavers-signed 26.3.0.39832 ntdll.so from a different compile
#              of that release (backed up first like any other)
#
# Quit the game (and CrossOver) first. Every step keeps a backup and can be undone.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
C="$HERE/components"
NP_ROOT="$HOME/Library/Application Support/notproton/runners/crossover-26.3.0.39832/CrossOver"
STEAM_DIR="$HOME/Library/Application Support/Steam"
# Steam keeps a game's prefix in the library the game is installed in, which need not be
# the main one; look through every library Steam knows about
find_prefix() {
    local lib
    { echo "$STEAM_DIR"
      sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$STEAM_DIR/steamapps/libraryfolders.vdf" 2>/dev/null
    } | while IFS= read -r lib; do
        [ -d "$lib/steamapps/compatdata/4115450/pfx" ] && { echo "$lib/steamapps/compatdata/4115450/pfx"; break; }
    done
}
NP_PREFIX="$(find_prefix || true)"
[ -n "$NP_PREFIX" ] || NP_PREFIX="$STEAM_DIR/steamapps/compatdata/4115450/pfx"
KEY='HKCU\Software\Wine\AppDefaults\PBZ.exe\Environment'

# files from a downloaded zip carry the quarantine flag, and macOS will not load a
# quarantined ntdll.so into wine
xattr -dr com.apple.quarantine "$HERE" 2>/dev/null || true

CMD="${1:-status}"; TARGET=""; APP=""; BOTTLE=""; D3DM=""
shift || true
[ "$CMD" = lsfg ] && { LSFG_ACTION="$1"; shift || true; }
[ "$CMD" = fsr4 ] && { FSR4_ACTION="$1"; shift || true; }
case "$1" in notproton|crossover|gptk) TARGET="$1"; shift ;; esac
while [ $# -gt 0 ]; do
    case "$1" in
        --app)      APP="$2"; shift 2 ;;
        --bottle)   BOTTLE="$2"; shift 2 ;;
        --d3dmetal) D3DM="$2"; shift 2 ;;
        --force)    export PBZ_FORCE=1; shift ;;
        *) echo "unknown option $1"; exit 1 ;;
    esac
done
[ "$TARGET" = gptk ] && { TARGET=crossover; [ -n "$APP" ] || APP="/Applications/CrossOver (GPTK 4.0b3).app"; }
if [ -z "$APP" ]; then
    for a in "/Applications/CrossOver (GPTK 4.0b3).app" "/Applications/CrossOver.app"; do
        [ -d "$a" ] && { APP="$a"; break; }
    done
fi
APP_ROOT="$APP/Contents/SharedSupport/CrossOver"
# default D3DMetal source: the copy of Apple's Game Porting Toolkit 4.0 beta 3 redistributables
# that ships in components/gptk (distributed non-commercially under Apple's license, which is
# included there), else a CrossOver app on this Mac that already has 4.0b3
[ -z "$D3DM" ] && "$C/gptk_d3dmetal.sh" find "$C/gptk" >/dev/null 2>&1 && D3DM="$C/gptk"
if [ -z "$D3DM" ]; then
    for a in "/Applications/CrossOver (GPTK 4.0b3).app" "$APP"; do
        s=$("$C/gptk_d3dmetal.sh" find "$a" 2>/dev/null) || continue
        [ -e "$s/wine/x86_64-windows/d3d12core.dll" ] && { D3DM="$a"; break; }
    done
fi

LAUNCHER="$HOME/Library/Application Support/notproton/pbz-launch.sh"
SHADER_DIR="$HOME/Library/Application Support/notproton/pbzshader"

remove_old_shader() {   # the shader archive of earlier patch versions used up the memory; it is gone
    [ -d "$SHADER_DIR" ] || return 0
    rm -rf "${SHADER_DIR:?}" && echo "old shader archive removed"
}

# FSR 4 upscaling (fsr4-native-macos, components/fsr4), optional and off by default: it replaces the
# MetalFX upscaler behind the game's DLSS option and costs frame rate. pbz-launch.sh loads it when
# the folder is there, so turning it on or off needs no change to the launch options. It compiles
# its shaders on first use, which needs Xcode's Metal Toolchain. .pbz-managed marks a copy made
# here, so restore does not remove an FSR 4 the player installed themselves.
FSR4_DIR="$HOME/Library/Application Support/notproton/fsr4"
fsr4_toolchain() {
    command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1 || { echo "python3"; return 1; }
    xcrun metal --version >/dev/null 2>&1 || { echo "metal"; return 1; }
    return 0
}
fsr4_status() {
    local missing
    if missing=$(fsr4_toolchain); then echo "fsr4 toolchain: ok"; else echo "fsr4 toolchain: missing $missing"; fi
    if [ -f "$FSR4_DIR/dist/crossover/libfsr4hook.dylib" ]; then echo "fsr4: on"
    elif [ -d "$FSR4_DIR.off" ]; then echo "fsr4: off"
    else echo "fsr4: not installed"; fi
}
fsr4_on() {
    local missing
    [ -f "$FSR4_DIR/dist/crossover/libfsr4hook.dylib" ] && { echo "fsr4: already on"; return; }
    missing=$(fsr4_toolchain) || { echo "fsr4: needs Xcode with the Metal Toolchain and python3 (missing: $missing). Install Xcode, then run: xcodebuild -downloadComponent MetalToolchain"; exit 1; }
    if [ -d "$FSR4_DIR.off" ]; then
        [ -e "$FSR4_DIR" ] && { echo "fsr4: both $FSR4_DIR and $FSR4_DIR.off exist; remove one first"; exit 1; }
        mv "$FSR4_DIR.off" "$FSR4_DIR"
    else
        [ -e "$FSR4_DIR" ] && { echo "fsr4: $FSR4_DIR exists but has no hook; remove it first"; exit 1; }
        mkdir -p "${FSR4_DIR%/*}"
        ditto --norsrc --noextattr "$C/fsr4" "$FSR4_DIR.tmp" && mv "$FSR4_DIR.tmp" "$FSR4_DIR"
        touch "$FSR4_DIR/.pbz-managed"
        # the bundled dxc/spirv tools are run at shader compile time; a downloaded zip marks them quarantined
        xattr -dr com.apple.quarantine "$FSR4_DIR" 2>/dev/null || true
    fi
    echo "fsr4: on (pick DLSS in the game; the next launch uses FSR 4, and costs some frame rate)"
}
fsr4_off() {
    [ -d "$FSR4_DIR" ] || { echo "fsr4: already off"; return; }
    [ -e "$FSR4_DIR.off" ] && { echo "fsr4: $FSR4_DIR.off already exists; remove it first"; exit 1; }
    mv "$FSR4_DIR" "$FSR4_DIR.off"
    echo "fsr4: off (the game's DLSS goes back to MetalFX)"
}
fsr4_remove() {
    local d
    for d in "$FSR4_DIR" "$FSR4_DIR.off"; do
        [ -f "$d/.pbz-managed" ] && rm -rf "${d:?}" && echo "fsr4 removed"
    done
    return 0
}

# DLSS: the game's own folder of Windows system files holds 1 KB placeholders for these two; put the
# real ones from D3DMetal there (the placeholders are kept beside them for restore).
prefix_dlss() {   # prefix_dlss add|delete|status
    local s32="$NP_PREFIX/drive_c/windows/system32" src="$NP_ROOT/lib64/apple_gptk/wine/x86_64-windows" f ok=set
    case "$1" in
    add)
        [ -d "$s32" ] || return 0
        for f in nvngx.dll nvapi64.dll; do
            [ -f "$src/$f" ] || { echo "DLSS: $f not found in D3DMetal"; return 1; }
            cmp -s "$src/$f" "$s32/$f" && continue
            [ -f "$s32/$f" ] && [ ! -e "$s32/$f.pbz-stub" ] && cp -p "$s32/$f" "$s32/$f.pbz-stub"
            cp "$src/$f" "$s32/$f"
        done
        echo "DLSS: files in the game prefix" ;;
    delete)
        for f in nvngx.dll nvapi64.dll; do
            [ -f "$s32/$f.pbz-stub" ] && mv -f "$s32/$f.pbz-stub" "$s32/$f"
        done ;;
    status)
        for f in nvngx.dll nvapi64.dll; do cmp -s "$src/$f" "$s32/$f" || ok="not set"; done
        echo "game DLSS files: $ok" ;;
    esac
}

# Lossless Scaling frame generation (lsfg-metal) under NotProton. Nothing of it ships here:
# Lossless.dll comes from the player's own Lossless Scaling, and the x86_64 lsfg-metal shim
# and the newer MoltenVK from the player's LsfgInjector install (~/lsfg). This only wires
# them up the way that works for this game: the shim in front of the runner's MoltenVK,
# lsfgenv.dylib to set LSFGM_METAL / LSFGM_GENERATOR_MOLTENVK inside the game (NotProton
# drops LSFGM_* from the environment), and override_present_mode = true (without it the
# game holds all three drawables and frame generation deadlocks it).
LSFG_DIR="$HOME/Library/Application Support/notproton/lsfg"
LSFG_CONF="$HOME/.config/lsfg-metal/conf.toml"
lsfg_dll() {
    local f lib
    for f in "$HOME/lsfg/lsfg-vk.dll" "$HOME/lsfg/Lossless.dll"; do [ -f "$f" ] && { echo "$f"; return; }; done
    { echo "$STEAM_DIR"; sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$STEAM_DIR/steamapps/libraryfolders.vdf" 2>/dev/null; } |
        while IFS= read -r lib; do
            for f in "$lib/steamapps/common/Lossless Scaling/Lossless.dll" "$lib/steamapps/common/Lossless Scaling/lsfg-vk.dll"; do
                [ -f "$f" ] && { echo "$f"; return; }
            done
        done
    true
}
lsfg_status() {
    local dll shim gen missing=""
    dll=$(lsfg_dll); shim="$HOME/lsfg/patch/shim/libMoltenVK.dylib"; gen="$HOME/lsfg/patch/moltenvk/libMoltenVK.dylib"
    [ -n "$dll" ] || missing="$missing Lossless.dll"
    [ -f "$shim" ] || missing="$missing lsfg-shim"
    [ -f "$gen" ] || missing="$missing moltenvk"
    if [ -n "$missing" ]; then echo "lsfg sources: missing$missing"; else echo "lsfg sources: ok"; fi
    if [ -f "$LSFG_DIR/libMoltenVK.dylib" ]; then echo "lsfg: on"
    elif [ -d "$LSFG_DIR.off" ]; then echo "lsfg: off"
    else echo "lsfg: not installed"; fi
}
lsfg_on() {
    local dll shim gen
    dll=$(lsfg_dll); shim="$HOME/lsfg/patch/shim/libMoltenVK.dylib"; gen="$HOME/lsfg/patch/moltenvk/libMoltenVK.dylib"
    [ -n "$dll" ] || { echo "lsfg: Lossless.dll not found (buy and install Lossless Scaling, or put it at ~/lsfg/lsfg-vk.dll)"; exit 1; }
    [ -f "$shim" ] && [ -f "$gen" ] || { echo "lsfg: LsfgInjector files not found in ~/lsfg (install and open LsfgInjector once)"; exit 1; }
    [ -d "$NP_ROOT" ] || { echo "lsfg: NotProton runner not found"; exit 1; }
    rm -rf "${LSFG_DIR:?}.off"; mkdir -p "$LSFG_DIR"
    cp "$shim" "$LSFG_DIR/libMoltenVK.dylib"
    cp "$gen" "$LSFG_DIR/libMoltenVK.generator.dylib"
    cp "$C/lsfg/lsfgenv.dylib" "$C/lsfg/lsfgenv.c" "$LSFG_DIR/"
    ln -sfn "$NP_ROOT/lib64/libMoltenVK.dylib" "$LSFG_DIR/libMoltenVK.real.dylib"
    xattr -cr "$LSFG_DIR" 2>/dev/null || true
    mkdir -p "${LSFG_CONF%/*}"
    [ -f "$LSFG_CONF" ] && ! grep -q 'Phantom Blade Zero under NotProton' "$LSFG_CONF" && cp -p "$LSFG_CONF" "$LSFG_CONF.orig-pbz"
    if ! grep -q 'Phantom Blade Zero under NotProton' "$LSFG_CONF" 2>/dev/null; then
        cat > "$LSFG_CONF" <<CONF
# lsfg-metal for Phantom Blade Zero under NotProton (loaded by notproton/pbz-launch.sh).
# Edit the profile while the game runs; the file is reloaded on save.
version = 2

[global]
allow_fp16 = true
# debug | info | warning | error
log_level = "info"
log_file = "$HOME/lsfg/notproton-pbz.log"
dll = "$dll"

[[profile]]
name = "PhantomBladeZero"
# Steam App ID and exe name
active_in = ["4115450", "PBZ.exe"]
# adaptive | vsync
pacing_mode = "vsync"
# 2 | 3 | 4
multiplier = 2
# optical flow resolution 0.25-1.0
flow_scale = 0.30
performance_mode = false
# must stay true: otherwise the game holds all three drawables and frame generation deadlocks it
override_present_mode = true
preserve_swapchain_image_count = false
CONF
    else
        sed -i '' -E 's/^override_present_mode = false/override_present_mode = true/' "$LSFG_CONF"
    fi
    echo "lsfg: on (2x; settings in $LSFG_CONF; turn off the game's own frame generation)"
}
lsfg_off() {
    [ -d "$LSFG_DIR" ] || { echo "lsfg: already off"; return; }
    rm -rf "${LSFG_DIR:?}.off"; mv "$LSFG_DIR" "$LSFG_DIR.off"
    echo "lsfg: off"
}

install_launcher() {
    cp "$C/pbz-launch.sh" "$LAUNCHER.tmp" && chmod 755 "$LAUNCHER.tmp" && xattr -c "$LAUNCHER.tmp" && mv "$LAUNCHER.tmp" "$LAUNCHER"
    echo "launcher: $LAUNCHER"
}

launch_options() {
    cat <<EOF

Steam launch options for Phantom Blade Zero (Properties > General > Launch Options):

D3DM_ENABLE_METALFX=1 D3DM_SUPPORT_DXR=0 WINEMSYNC=0 WINEDLLOVERRIDES="msvcp140,msvcp140_1,msvcp140_2,msvcp140_atomic_wait,msvcp140_codecvt_ids,vcruntime140,vcruntime140_1,vcruntime140_threads=n,b" CX_GRAPHICS_BACKEND=d3dmetal ROSETTA_ADVERTISE_AVX=1 "$LAUNCHER" %command%
EOF
}

prefix_reg() {   # prefix_reg add|delete
    if [ ! -d "$NP_PREFIX" ]; then
        [ "$1" = add ] && echo "registry: no prefix yet at $NP_PREFIX - start the game once with NotProton, then run apply again"
        return 0
    fi
    if [ "$1" = add ]; then
        "$C/install.sh" env-prefix "$NP_PREFIX" "$NP_ROOT" >/dev/null 2>&1 && echo "registry: WINE_ROSETTA_CPUID7_OR set for PBZ.exe"
    else
        WINEPREFIX="$NP_PREFIX" WINEDEBUG=-all "$NP_ROOT/lib/wine/x86_64-unix/wine" reg delete "$KEY" /v WINE_ROSETTA_CPUID7_OR /f >/dev/null 2>&1 || true
        WINEPREFIX="$NP_PREFIX" "$NP_ROOT/bin/wineserver" -w
        echo "registry: WINE_ROSETTA_CPUID7_OR removed"
    fi
}

bottle_reg() {   # bottle_reg add|delete
    [ -n "$BOTTLE" ] || return 0
    if [ "$1" = add ]; then
        "$C/install.sh" env "$BOTTLE" "PBZ.exe" "$APP" >/dev/null 2>&1 && echo "registry: WINE_ROSETTA_CPUID7_OR set for PBZ.exe in bottle $BOTTLE"
    else
        "$APP_ROOT/bin/wine" --bottle "$BOTTLE" reg delete "$KEY" /v WINE_ROSETTA_CPUID7_OR /f >/dev/null 2>&1 || true
        echo "registry: WINE_ROSETTA_CPUID7_OR removed from bottle $BOTTLE"
    fi
}

d3dmetal() {   # d3dmetal <root>
    if [ -n "$D3DM" ]; then "$C/gptk_d3dmetal.sh" apply "$1" "$D3DM"
    else echo "D3DMetal: no 4.0b3 source found; pass --d3dmetal <Game Porting Toolkit 4.0 beta 3>"; fi
}

status_of() {   # status_of <name> <root>
    [ -d "$2" ] || { echo "$1: not found"; return; }
    echo "$1:"
    echo "  ntdll.so (Denuvo/Rosetta + D3DMetal fallback): $("$C/install.sh" status "$2" | cut -d' ' -f1)"
    echo "  winegstreamer.dll (NV12 video):                 $(python3 -I "$C/nv12_patch.py" status "$2" | cut -d' ' -f1)"
    echo "  $("$C/gptk_d3dmetal.sh" status "$2")"
}

case "$CMD/$TARGET" in
status/*)
    status_of "NotProton runner" "$NP_ROOT"
    if [ -d "$NP_PREFIX" ]; then echo "game prefix: $NP_PREFIX"; else echo "game prefix: none (start the game once with NotProton)"; fi
    if grep -q '"WINE_ROSETTA_CPUID7_OR"="01800000,00400000"' "$NP_PREFIX/../pfx/user.reg" 2>/dev/null || grep -q 'WINE_ROSETTA_CPUID7_OR' "$NP_PREFIX/user.reg" 2>/dev/null; then echo "game registry: set"; else echo "game registry: not set"; fi
    if [ -x "$LAUNCHER" ]; then echo "launcher: installed"; else echo "launcher: not installed"; fi
    game=$( { echo "$STEAM_DIR"; sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$STEAM_DIR/steamapps/libraryfolders.vdf" 2>/dev/null; } |
        while IFS= read -r lib; do [ -f "$lib/steamapps/common/PBZ/platform/steam/PBZ.exe" ] && { echo "$lib/steamapps/common/PBZ"; break; }; done; true )
    echo "game files: ${game:-none}"
    # the game's launch options live in each Steam user's localconfig.vdf, in its apps/"4115450" block
    opts=none
    for f in "$STEAM_DIR"/userdata/*/config/localconfig.vdf; do
        [ -f "$f" ] || continue
        if awk '/^[[:space:]]*"4115450"[[:space:]]*$/{f=1; n=0} f{n++} f&&/"LaunchOptions"/{print; exit} n>60{f=0}' "$f" | grep -q 'pbz-launch.sh'; then opts=set; break; fi
        awk '/^[[:space:]]*"4115450"[[:space:]]*$/{f=1; n=0} f{n++} f&&/"LaunchOptions"/{print; exit} n>60{f=0}' "$f" | grep -q . && opts=other
    done
    echo "launch options: $opts"
    [ -n "$APP" ] && status_of "$(basename "$APP")" "$APP_ROOT"
    echo "D3DMetal 4.0b3 source: ${D3DM:-none found}"
    prefix_dlss status
    lsfg_status
    fsr4_status
    ;;
apply/notproton)
    [ -d "$NP_ROOT" ] || { echo "NotProton runner for CrossOver 26.3.0.39832 not found at $NP_ROOT"; exit 1; }
    "$C/install.sh" apply "$NP_ROOT"
    python3 -I "$C/nv12_patch.py" apply "$NP_ROOT"
    d3dmetal "$NP_ROOT"
    prefix_reg add
    prefix_dlss add
    install_launcher
    remove_old_shader
    launch_options
    ;;
apply/crossover)
    [ -d "$APP_ROOT" ] || { echo "CrossOver not found: ${APP:-none in /Applications}"; exit 1; }
    "$C/install.sh" apply "$APP"
    python3 -I "$C/nv12_patch.py" apply "$APP"
    d3dmetal "$APP_ROOT"
    bottle_reg add
    ;;
fsr4/*)
    case "$FSR4_ACTION" in on) fsr4_on ;; off) fsr4_off ;; *) fsr4_status ;; esac
    ;;
lsfg/*)
    case "$LSFG_ACTION" in on) lsfg_on ;; off) lsfg_off ;; *) lsfg_status ;; esac
    ;;
restore/notproton)   # undo each part on its own, even when another has nothing to undo
    "$C/install.sh" restore "$NP_ROOT" || true
    python3 -I "$C/nv12_patch.py" restore "$NP_ROOT" || true
    "$C/gptk_d3dmetal.sh" restore "$NP_ROOT" || true
    prefix_reg delete
    prefix_dlss delete
    fsr4_remove
    rm -f "$LAUNCHER" && echo "launcher removed (clear the game's Steam launch options too)"
    [ -d "$SHADER_DIR" ] && rm -rf "${SHADER_DIR:?}" && echo "shader archive removed"
    rm -rf "${LSFG_DIR:?}" "${LSFG_DIR:?}.off" && echo "frame generation removed"
    ;;
restore/crossover)
    "$C/install.sh" restore "$APP" || true
    python3 -I "$C/nv12_patch.py" restore "$APP" || true
    "$C/gptk_d3dmetal.sh" restore "$APP_ROOT" || true
    bottle_reg delete
    ;;
*)
    sed -n '2,17p' "$0"; exit 1 ;;
esac
