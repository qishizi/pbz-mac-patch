#!/bin/bash
# Steam launch wrapper for Phantom Blade Zero under NotProton.
#
# Launch options:   <env vars> "/path/to/pbz-launch.sh" %command%
#
# 1. If the previous run is still alive, ask whether to wait for it or end it. A second
#    game process cannot use the Metal shader cache the first one holds open, so it
#    would compile every shader again.
# 2. Start platform/steam/PBZ.exe directly (steam/PBZ.exe's VC++ check misfires under
#    wine) with the arguments that launcher would have passed.
# 3. Raise macOS's Metal shader cache limit. The default holds only part of this game's
#    shaders, so every launch compiled the rest again. The value is a 32-bit byte count:
#    4294967296 or more wraps around and turns the cache off.

# test hooks: PBZ_LAUNCH_CHOICE answers the dialog, PBZ_LAUNCH_WAIT caps the wait (seconds)
WAIT="${PBZ_LAUNCH_WAIT:-120}"
# Steam passes the game's own prefix (in whichever library holds the game)
PREFIX="${STEAM_COMPAT_DATA_PATH:-$HOME/Library/Application Support/Steam/steamapps/compatdata/4115450}/pfx"
RUNNER="$HOME/Library/Application Support/notproton/runners/crossover-26.3.0.39832/CrossOver"
[ -d "$RUNNER" ] || RUNNER=$(ls -d "$HOME/Library/Application Support/notproton/runners/"*/CrossOver 2>/dev/null | tail -1)
# -basedir below uses S:, which NotProton maps to the Steam library that holds the game

previous_run() { pgrep -f 'platform[/\\]steam[/\\]PBZ\.exe' >/dev/null; }

ask() {
    [ -n "$PBZ_LAUNCH_CHOICE" ] && { echo "$PBZ_LAUNCH_CHOICE"; return; }
    osascript -e 'button returned of (display dialog "影之刃零上一次的游戏进程还没有退出。\n\n同时运行两个会抢占着色器缓存，新的那个要从头编译所有着色器。" buttons {"取消启动", "结束旧进程", "等待"} default button "等待" with title "影之刃零" with icon caution)' 2>/dev/null || echo "取消启动"
}

if previous_run; then
    case "$(ask)" in
        结束旧进程)
            WINEPREFIX="$PREFIX" "$RUNNER/bin/wineserver" -k 2>/dev/null
            pkill -f 'platform[/\\]steam[/\\]PBZ\.exe' 2>/dev/null ;;
        等待) ;;
        *) exit 0 ;;
    esac
    for _ in $(seq "$WAIT"); do previous_run || break; sleep 1; done
    if previous_run; then
        [ -n "$PBZ_LAUNCH_CHOICE" ] || osascript -e 'display alert "影之刃零" message "上一次的游戏进程仍未退出，这次启动已取消。"' >/dev/null 2>&1
        exit 0
    fi
fi

# Lossless Scaling frame generation (lsfg-metal, x86_64 build) if it is set up; NotProton
# injects STEAM_DYLD_INSERT_LIBRARIES into the game. Settings: ~/.config/lsfg-metal/conf.toml
LSFG="$HOME/Library/Application Support/notproton/lsfg/libMoltenVK.dylib"
[ -f "$LSFG" ] && [ -z "$PBZ_NO_LSFG" ] &&
    export STEAM_DYLD_INSERT_LIBRARIES="${STEAM_DYLD_INSERT_LIBRARIES:+$STEAM_DYLD_INSERT_LIBRARIES:}${LSFG%/*}/lsfgenv.dylib:$LSFG"
# With DLSS (D3DMetal's MetalFX path) available and ray tracing on, the game quits as soon as a
# level loads, whichever upscaler is picked; without ray tracing DLSS works. An explicit
# D3DM_SUPPORT_DXR in the launch options wins.
[ "$D3DM_ENABLE_METALFX" = 1 ] && [ -z "$D3DM_SUPPORT_DXR" ] && export D3DM_SUPPORT_DXR=0
# FSR 4 (fsr4-native-macos) if it is set up: with DLSS picked in the game it replaces the MetalFX
# upscaler D3DMetal uses for DLSS. Loaded into the game instead of patching D3DMetal.
FSR4="$HOME/Library/Application Support/notproton/fsr4"
if [ -f "$FSR4/dist/crossover/libfsr4hook.dylib" ] && [ "$D3DM_ENABLE_METALFX" = 1 ] && [ -z "$PBZ_NO_FSR4" ]; then
    export FSR4_ROOT="$FSR4" FSR4_REPLACE=1 FSR4_VERSION="${FSR4_VERSION:-4.1.2}" FSR4_PROFILE="${FSR4_PROFILE:-int8-lite}"
    export FSR4_HOOK_LOG="$FSR4/dist/crossover/hook.log"
    [ -d "$FSR4/dist/crossover/FSR4 Panel.app" ] && export FSR4_PANEL=1
    [ -f "$FSR4_HOOK_LOG" ] && [ "$(wc -l < "$FSR4_HOOK_LOG")" -gt 5000 ] && tail -n 2000 "$FSR4_HOOK_LOG" > "$FSR4_HOOK_LOG.tmp" && mv "$FSR4_HOOK_LOG.tmp" "$FSR4_HOOK_LOG"
    export STEAM_DYLD_INSERT_LIBRARIES="${STEAM_DYLD_INSERT_LIBRARIES:+$STEAM_DYLD_INSERT_LIBRARIES:}$FSR4/dist/crossover/libfsr4hook.dylib"
fi
export MTL_SHADER_CACHE_SIZE="${MTL_SHADER_CACHE_SIZE:-4000000000}"

exec "${@/\/PBZ\/steam\/PBZ.exe//PBZ/platform/steam/PBZ.exe}" \
    ProjectPBZ -basedir=S:/steamapps/common/PBZ/ProjectPBZ/Binaries/Win64 -pc-platform=Steam -dx12
