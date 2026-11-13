# 影之刃零 (Phantom Blade Zero) · Mac CrossOver 补丁

让 Steam 版《影之刃零》在 Apple 芯片 Mac 上，通过 **NotProton + CrossOver 26.3** 运行。

已在这套环境实测通过：M4 Pro、macOS 27、CrossOver 26.3.0.39832、NotProton、D3DMetal 4.0b3。

---

## 一、准备

| 需要 | 说明 |
|---|---|
| Apple 芯片的 Mac，macOS 26 或 27 | Intel Mac 不行 |
| **CrossOver 26.3.0.39832** | 必须是这个版本。版本不对时，脚本会拒绝修改任何文件 |
| **NotProton** | 让 Mac 版 Steam 直接用 CrossOver 运行 Windows 游戏，见 github.com/NotProtonNot/NotProton |
| Mac 版 Steam，游戏已装好 | 正常在 Steam 里下载即可 |
| Game Porting Toolkit 4.0 beta 3 | **已包含**在 `components/gptk`（苹果 D3DMetal 4.0b3，按苹果许可免费分发，见下方"文件与许可"）。想换用别的版本，可用 `--d3dmetal` 指定 |

## 二、安装（NotProton，已实测）

1. 在 Steam 里右键游戏 → 属性 → 兼容性，选择 NotProton 26.3，图形后端选 **D3DMetal**。
2. **先启动一次游戏**，让 NotProton 建好游戏的运行环境。启动失败或卡住都没关系，然后在 Steam 里停止游戏。
3. 打开"终端"，进入解压后的补丁文件夹：输入 `cd `（cd 后面有一个空格），把文件夹拖进终端窗口，回车。
4. 运行下面的命令（D3DMetal 4.0b3 已包含在补丁里，不用另外下载）：
   ```bash
   bash patch.sh apply notproton
   ```
5. 把下面这行 **Steam 启动选项**整行复制，粘贴到游戏的"属性 → 通用 → 启动选项"，替换原有内容：
   ```
   D3DM_ENABLE_METALFX=1 D3DM_SUPPORT_DXR=0 WINEMSYNC=0 WINEDLLOVERRIDES="msvcp140,msvcp140_1,msvcp140_2,msvcp140_atomic_wait,msvcp140_codecvt_ids,vcruntime140,vcruntime140_1,vcruntime140_threads=n,b" CX_GRAPHICS_BACKEND=d3dmetal ROSETTA_ADVERTISE_AVX=1 "$HOME/Library/Application Support/notproton/pbz-launch.sh" %command%
   ```
   - 这行对每个人都一样，**不用改**。`$HOME` 代表"当前用户的主文件夹"，会自动换成你自己的，比如 `/Users/你的用户名`。
   - **必须先完成第 4 步**。启动选项调用的 `pbz-launch.sh` 是第 4 步装进 `~/Library/Application Support/notproton/` 的，没装的话 Steam 找不到它，游戏启动不了。
   - 第 4 步结束时终端也会打印一行启动选项，里面写的是你自己的完整路径，用那一行也可以。
6. 启动游戏。如果弹出"运行环境检查"（提示缺 VC++），点 **继续游戏**。每次启动都要编译着色器，大约 7～10 分钟，这是目前的正常现象。
7. 想用 DLSS：在游戏设置里把放大方式选成 DLSS（第 5 步的启动选项已经打开了它）。

查看安装状态：`bash patch.sh status`
全部还原：`bash patch.sh restore notproton`

## 可选：FSR 4 放大（仅 NotProton，默认关闭）

补丁里带了 [fsr4-native-macos](https://github.com/UzenUPoZiTiV4ik/fsr4-native-macos) v3.0。开启后，游戏里选 DLSS 时，实际运行的是 FSR 4，而不是 Apple 的 MetalFX。画质通常更好，但**会增加 GPU 负担、降低帧数**，所以默认不装，想用时再开。

- **需要：** Xcode 26 或更高，以及它的 Metal Toolchain（`xcodebuild -downloadComponent MetalToolchain`）。FSR 4 第一次运行时要编译自己的着色器，会卡十几秒。
- **开启：** `bash patch.sh fsr4 on`，或在 App 里点“开启 FSR 4”。然后在游戏里把放大方式选成 DLSS。
- **关闭：** `bash patch.sh fsr4 off`。游戏里的 DLSS 会变回 MetalFX。
- 开关都不用改启动选项，下次启动游戏生效。
- 开启后启动游戏会同时弹出 FSR 4 面板。如果游戏停在警告画面没反应，点一下游戏窗口就行。

## 可选：Lossless 插帧（仅 NotProton）

把每秒约 60 帧插到约 120 帧。需要你自己购买 Lossless Scaling（补丁不能附带它的 Lossless.dll），并装好 LsfgInjector（打开一次，让它准备好 `~/lsfg`）。然后：

```bash
bash patch.sh lsfg on     # 开启；bash patch.sh lsfg off 关闭
```

- 设置在 `~/.config/lsfg-metal/conf.toml`，游戏运行中也能改。`override_present_mode` 必须是 `true`：关掉时游戏会占满全部画面缓冲区，插帧会把游戏卡死在加载界面。
- 游戏自带的帧生成要关掉，只留一个插帧。

## 三、不用 NotProton，直接用 CrossOver？

如果是在 CrossOver 的 bottle 里装 Windows 版 Steam 来玩：完全退出 CrossOver，运行 `bash crossover.sh apply --bottle 你的bottle名`（或者用"影之刃零补丁" App 的 CrossOver 模式）。它会把 CrossOver 和 bottle 一起配置好，不需要启动选项。

用 GPTK Patcher 打过"所有 bottle 开启 DLSS→MetalFX"的 CrossOver，Steam 窗口会是黑的；`crossover.sh apply` 会把这个全局设置关掉（`restore` 时恢复）。

注意：CrossOver bottle 方式还没有实际跑过游戏。这种方式也没有打开 DLSS，要用 DLSS 请走 NotProton。

## 四、补丁做了什么

| 部分 | 解决的问题 |
|---|---|
| `ntdll.so`：Rosetta 修正 | Denuvo 卡在单核 100%、不出窗口。补上 CPUID 第 7 页（CLFLUSHOPT/CLWB/RDPID）、模拟 CLWB/RDPID 指令、模拟硬件执行断点、按 x86 规则上报非规范地址异常。 |
| `ntdll.so`：D3DMetal 兜底 | 经 NotProton 的 Steam 桥接启动时，CrossOver 不把游戏交给 D3DMetal，退回 vkd3d，游戏报 SM6 不支持后退出 |
| `winegstreamer.dll`：NV12 | 教学界面不出、主菜单背景 CG 不动。虚幻 5 的视频播放器只接受 NV12，而 CrossOver 在 Mac 上把它藏起来了。效果同 winevideo 的补丁 0006 |
| D3DMetal 4.0b3 | CrossOver 26.3 自带 3.0，这个游戏需要 4.0b3 |
| 注册表 `WINE_ROSETTA_CPUID7_OR` | NotProton 会过滤掉 `WINE_*` 环境变量，改从游戏 prefix 的注册表读取，只对 `PBZ.exe` 生效 |
| 启动选项 + `pbz-launch.sh` | 上一局还没退出时弹窗让你选"等待 / 结束旧进程 / 取消启动"，避免两个进程抢占 Metal 着色器缓存、导致全部重编；跳过会误报 VC++ 的引导程序 `steam/PBZ.exe`，补上它原本会传的 `ProjectPBZ -basedir=… -pc-platform=Steam`（否则游戏报"没有商店身份"）；让游戏加载微软原版 VC++ 运行库（否则运行库检查会让游戏退出）；设置 macOS 的 Metal 着色器缓存上限（效果有限，见常见问题）。脚本安装在 `~/Library/Application Support/notproton/pbz-launch.sh`，`restore` 时会删除 |

## 五、安全与还原

- 每个被替换的文件，第一次替换前都会保存官方原版，命名为 `*.orig-cx26.3` 或 `apple_gptk.orig-cx26.3`。`restore` 会全部换回去。
- 只有文件与 CrossOver 26.3.0.39832 原版逐字节一致时才会打补丁。
- 游戏或 CrossOver 正在运行时，脚本拒绝操作。
- CrossOver 或 NotProton 更新后，补丁会被覆盖，重新运行一次 `apply` 即可。如果新版本对不上，脚本会提示，不会改动文件。
- 脚本会清除补丁包自身的"从网上下载"隔离标记，否则 macOS 会拒绝加载 `ntdll.so`。

## 六、常见问题

- **提示 `ntdll.so is not the CrossOver 26.3.0.39832 original`，并说 `rerun with --force`**：CodeWeavers 对 26.3.0.39832 发布过不止一次编译，你的文件是官方签名的另一次编译。在命令末尾加上 `--force` 再运行一次即可，原文件照样会先备份。没有出现 `--force` 提示的，说明文件被第三方改过，不要强行替换。
- **单核 100%、一直不出窗口**：Denuvo 修正没生效。检查 `bash patch.sh status`，以及第二步的"先启动一次"是否做过（没有 prefix 时 CPUID 设置写不进去），做过之后再运行一次 `apply`。
- **启动后很快退出**：确认启动选项是整行替换的，并且包含 `WINEDLLOVERRIDES` 和 `pbz-launch.sh`。
- **教学界面卡住、主菜单背景黑或不动**：NV12 补丁没生效，检查 `status`。
- **每次启动都要编译着色器很久**：第一次启动编译是正常的。之后如果还每次都编译，有两个原因：
  - 上一局还没完全退出就又启动了。启动脚本会弹窗提示。
  - macOS 默认的 Metal 着色器缓存装不下这个游戏的全部着色器，表现为每次很快编译到六十多，然后变慢。启动脚本把上限设成约 3.7GB（`MTL_SHADER_CACHE_SIZE=4000000000`），但实测单个缓存文件仍停在约 1.1GB，这部分目前没有解决，剩下的着色器每次启动都会再编译一遍。
  - 另外，改动 DLSS、Metal HUD 这类开关后，着色器也会重新编译一次。
- **插帧**：LsfgInjector 对这个游戏无效，因为游戏走的是 D3DMetal，不经过 Vulkan。D3DMetal 自带把 DLSS 帧生成转成 MetalFX 插帧的功能，启动选项里已经开了 `D3DM_ENABLE_METALFX=1`（DLSS），并用 `D3DM_SUPPORT_DXR=0` 关掉光追，否则开 DLSS 进关卡会闪退。不想用 DLSS 就把 `1` 改成 `0`。

## 七、文件与许可

- `patch.sh`：入口脚本
- `components/`：
  - `ntdll.so`：用 CodeWeavers 公开的 `crossover-sources-26.3.0.tar.gz`（media.codeweavers.com/pub/crossover/source/）加 `source/` 里的两个补丁编译
  - `install.sh`、`nv12_patch.py`、`gptk_d3dmetal.sh`、`pbz-launch.sh`（Steam 启动脚本）
  - `gptk/`：苹果 D3DMetal 4.0b3 可再分发组件及其许可
  - `fsr4/`：fsr4-native-macos v3.0（MIT，AMD 部分的许可见 `fsr4/third_party/fsr411/`）
- `source/`：`ntdll-rosetta-cpu-fidelity.patch`、`ntdll-d3dmetal-fallback.patch`

Wine 及其修改以 LGPL-2.1-or-later 发布。

`components/gptk/redist` 是苹果 Game Porting Toolkit 4.0 beta 3 的可再分发组件（D3DMetal），版权归 Apple 所有。按其许可第 2A(iii) 和 2C 条，仅可**非商业**分发；许可原文、致谢和说明见同目录的 `License.rtf`、`Acknowledgements.rtf`、`Read Me.rtf`。请勿将本补丁用于任何收费用途。
