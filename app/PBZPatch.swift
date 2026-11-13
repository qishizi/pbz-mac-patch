// 影之刃零补丁: a step-by-step window around pbz-crossover-patch for two setups:
//   NotProton  - Mac Steam running the game through NotProton (patch.sh)
//   CrossOver  - Windows Steam inside a CrossOver bottle (crossover.sh)
// It reads the script's status every few seconds, works out which step the player is on and
// shows only what that step needs. The patch files ship in Resources/patch and are copied to
// Application Support before use, so the scripts never write inside the app bundle.
import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

@main
struct PBZPatchApp: App {
    var body: some Scene {
        WindowGroup(T("影之刃零补丁")) {
            ContentView()
                .frame(minWidth: 960, minHeight: 700)
                .preferredColorScheme(.dark)
                .tint(brandRed)
        }
        .windowResizability(.contentMinSize)
    }
}

enum Mode: String { case notproton, crossover }

let brandRed = Color(red: 0.86, green: 0.16, blue: 0.16)

// Game art in Resources/art (official Steam store images, © S-GAME).
func art(_ name: String) -> NSImage? {
    Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "art").flatMap { NSImage(contentsOf: $0) }
}

// A picture strip with a dark fade so text on top stays readable.
struct Banner<Content: View>: View {
    let image: String
    var height: CGFloat = 180
    var align: Alignment = .bottomLeading
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align)
        .frame(height: height)
        .background {
            GeometryReader { g in
                ZStack {
                    if let img = art(image) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: g.size.width, height: g.size.height).clipped()
                    } else { Color.black }
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
    }
}

// Donation page opened from the "More" menu and the sidebar; the entry is hidden while this is empty.
let donationURL = ""

// UI language: "auto" follows the system (Chinese systems get Chinese, everything else English).
func uiLang() -> String {
    let v = UserDefaults.standard.string(forKey: "lang") ?? "auto"
    if v == "zh" || v == "en" { return v }
    return (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? "zh" : "en"
}
// The source strings are Chinese; English comes from Strings.swift, falling back to the Chinese text.
func T(_ zh: String) -> String { uiLang() == "zh" ? zh : (englishStrings[zh] ?? zh) }

// MARK: - status of the NotProton setup (`patch.sh status`)

struct NPStatus {
    var loaded = false
    var runnerFound = false
    var ntdll = "?"
    var gstreamer = "?"
    var d3dmetal = "?"
    var prefix = false
    var registry = false
    var launcher = false
    var gameFiles = false
    var launchOptions = "none"      // set | other | none
    var lsfgSources = ""            // "ok" or "missing ..."
    var lsfg = ""                   // on | off | not installed
    var fsr4 = ""                   // on | off | not installed
    var fsr4Toolchain = ""          // "ok" or "missing ..."
    var dlssFiles = false

    var patched: Bool { ntdll == "patched" && gstreamer == "patched" && d3dmetal.contains("4.0b3") && registry && launcher }

    static func parse(_ text: String) -> NPStatus {
        var s = NPStatus()
        s.loaded = true
        var section = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            func value(_ prefix: String) -> String? { line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil }
            if !line.hasPrefix(" ") { section = line }
            if line.hasPrefix("NotProton runner") { s.runnerFound = !line.contains("not found") }
            if section.hasPrefix("NotProton runner") && line.hasPrefix(" ") {
                parsePatchLine(line, &s.ntdll, &s.gstreamer, &s.d3dmetal)
            }
            if let v = value("game prefix: ") { s.prefix = !v.hasPrefix("none") }
            if let v = value("game registry: ") { s.registry = v == "set" }
            if let v = value("launcher: ") { s.launcher = v == "installed" }
            if let v = value("game files: ") { s.gameFiles = v != "none" }
            if let v = value("launch options: ") { s.launchOptions = v }
            if let v = value("lsfg sources: ") { s.lsfgSources = v }
            if let v = value("lsfg: ") { s.lsfg = v }
            if let v = value("fsr4: ") { s.fsr4 = v }
            if let v = value("fsr4 toolchain: ") { s.fsr4Toolchain = v }
            if let v = value("game DLSS files: ") { s.dlssFiles = v == "set" }
        }
        return s
    }
}

func parsePatchLine(_ line: String, _ ntdll: inout String, _ gst: inout String, _ d3d: inout String) {
    let t = line.trimmingCharacters(in: .whitespaces)
    let v = t.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces) ?? "?"
    if t.hasPrefix("ntdll.so") { ntdll = v }
    else if t.hasPrefix("winegstreamer.dll") { gst = v }
    else if t.hasPrefix("D3DMetal") { d3d = t }
}

// MARK: - status of the CrossOver setup (`crossover.sh bottles` + `crossover.sh status`)

struct Bottle: Hashable { var name: String; var steam: Bool; var game: Bool }

struct CXStatus {
    var loaded = false
    var appPath = ""
    var version = ""
    var running = false
    var ntdll = "?"
    var gstreamer = "?"
    var d3dmetal = "?"
    var backend = ""
    var registry = false
    var globalMetalFX = ""          // "on (all bottles)" makes Steam's window black
    var bottles: [Bottle] = []

    var rightVersion: Bool { version == "26.3.0.39832" }
    var appPatched: Bool { ntdll == "patched" && gstreamer == "patched" && d3dmetal.contains("4.0b3") && !globalMetalFX.hasPrefix("on") }
    var bottlePatched: Bool { backend.contains("d3dmetal") && registry }

    static func parse(_ text: String) -> CXStatus {
        var s = CXStatus()
        s.loaded = true
        var section = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            func value(_ prefix: String) -> String? { line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil }
            if !line.hasPrefix(" ") { section = line }
            if let v = value("bottle: ") {
                let f = v.components(separatedBy: "|")
                if f.count == 3 { s.bottles.append(Bottle(name: f[0], steam: f[1] == "steam=yes", game: f[2] == "game=yes")) }
            }
            if let v = value("crossover app: ") { s.appPath = v }
            if let v = value("crossover version: ") { s.version = v }
            if let v = value("crossover running: ") { s.running = v == "yes" }
            if section.hasSuffix(".app:") && line.hasPrefix(" ") {
                parsePatchLine(line, &s.ntdll, &s.gstreamer, &s.d3dmetal)
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("global MetalFX (DLSS) setting: ") { s.globalMetalFX = String(t.dropFirst("global MetalFX (DLSS) setting: ".count)) }
            }
            if section.hasPrefix("bottle ") && line.hasPrefix(" ") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("graphics backend: ") { s.backend = String(t.dropFirst("graphics backend: ".count)) }
                if t.hasPrefix("PBZ.exe registry settings: ") { s.registry = t.hasSuffix(": set") }
            }
        }
        return s
    }
}

// MARK: - steps

struct StepInfo: Identifiable {
    let id: Int
    let title: String
    let done: Bool
}

// MARK: - running the scripts

@MainActor
final class Patcher: ObservableObject {
    @Published var np = NPStatus()
    @Published var cx = CXStatus()
    @Published var log = ""
    @Published var busy = false
    @Published var gptkSource: URL?
    @Published var cxApp: URL?
    @Published var needsForce = false
    @Published var lastOK: Bool?
    private var refreshing = false

    let home = FileManager.default.homeDirectoryForCurrentUser
    var workDir: URL { home.appendingPathComponent("Library/Application Support/PBZPatch/patch") }
    var launcherPath: String { home.appendingPathComponent("Library/Application Support/notproton/pbz-launch.sh").path }

    var launchOptions: String {
        #"D3DM_ENABLE_METALFX=1 D3DM_SUPPORT_DXR=0 WINEMSYNC=0 WINEDLLOVERRIDES="msvcp140,msvcp140_1,msvcp140_2,msvcp140_atomic_wait,msvcp140_codecvt_ids,vcruntime140,vcruntime140_1,vcruntime140_threads=n,b" CX_GRAPHICS_BACKEND=d3dmetal ROSETTA_ADVERTISE_AVX=1 ""# + launcherPath + #"" %command%"#
    }

    func preparePatch() throws {
        guard let src = Bundle.main.url(forResource: "patch", withExtension: nil) else {
            throw NSError(domain: "PBZPatch", code: 1, userInfo: [NSLocalizedDescriptionKey: T("App 里缺少补丁文件")])
        }
        let fm = FileManager.default
        try? fm.removeItem(at: workDir)
        try fm.createDirectory(at: workDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: src, to: workDir)
    }

    func run(_ script: String, _ args: [String], quiet: Bool = false, done: ((Int32, String) -> Void)? = nil) {
        if !quiet { busy = true; log += "\n$ \(script) " + args.joined(separator: " ") + "\n" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [workDir.appendingPathComponent(script).path] + args
        p.currentDirectoryURL = workDir
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let collected = Collected()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            collected.append(s)
            if !quiet { Task { @MainActor in self.log += s } }
        }
        p.terminationHandler = { proc in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)     // let the last output arrive
                pipe.fileHandleForReading.readabilityHandler = nil
                if !quiet { self.busy = false }
                done?(proc.terminationStatus, collected.text)
            }
        }
        do { try p.run() } catch {
            if !quiet { busy = false }
            log += T("无法运行补丁脚本：") + error.localizedDescription + "\n"
        }
    }

    func cxArgs(_ bottle: String) -> [String] {
        var a: [String] = []
        if !bottle.isEmpty { a += ["--bottle", bottle] }
        if let app = cxApp { a += ["--app", app.path] }
        return a
    }

    func refresh(mode: Mode, bottle: String) {
        guard !refreshing else { return }
        refreshing = true
        switch mode {
        case .notproton:
            run("patch.sh", ["status"], quiet: true) { _, out in self.np = NPStatus.parse(out); self.refreshing = false }
        case .crossover:
            run("crossover.sh", ["bottles"], quiet: true) { _, bottles in
                self.run("crossover.sh", ["status"] + self.cxArgs(bottle), quiet: true) { _, out in
                    self.cx = CXStatus.parse(bottles + "\n" + out)
                    self.refreshing = false
                }
            }
        }
    }

    func applyNotProton(force: Bool, then: @escaping () -> Void) {
        var args = ["apply", "notproton"]
        if let g = gptkSource { args += ["--d3dmetal", g.path] }
        if force { args.append("--force") }
        finish(run: ("patch.sh", args), then: then)
    }

    func applyCrossOver(bottle: String, force: Bool, then: @escaping () -> Void) {
        var args = ["apply"] + cxArgs(bottle)
        if let g = gptkSource { args += ["--d3dmetal", g.path] }
        finish(run: ("crossover.sh", args), force: force, then: then)
    }

    private func finish(run job: (String, [String]), force: Bool = false, then: @escaping () -> Void) {
        needsForce = false
        lastOK = nil
        // crossover.sh hands --force on to install.sh through PBZ_FORCE
        if force { setenv("PBZ_FORCE", "1", 1) } else { unsetenv("PBZ_FORCE") }
        run(job.0, job.1) { code, out in
            unsetenv("PBZ_FORCE")
            self.lastOK = code == 0
            if out.contains("rerun with --force") { self.needsForce = true }
            then()
        }
    }

    func setFsr4(_ on: Bool, then: @escaping () -> Void) {
        lastOK = nil
        run("patch.sh", ["fsr4", on ? "on" : "off"]) { code, _ in self.lastOK = code == 0; then() }
    }

    func setLsfg(_ on: Bool, then: @escaping () -> Void) {
        lastOK = nil
        run("patch.sh", ["lsfg", on ? "on" : "off"]) { code, _ in self.lastOK = code == 0; then() }
    }

    func restore(mode: Mode, bottle: String, then: @escaping () -> Void) {
        lastOK = nil
        let job = mode == .notproton ? ("patch.sh", ["restore", "notproton"]) : ("crossover.sh", ["restore"] + cxArgs(bottle))
        run(job.0, job.1) { code, _ in self.lastOK = code == 0; then() }
    }
}

final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var s = ""
    func append(_ t: String) { lock.lock(); s += t; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return s }
}

// MARK: - views

struct ContentView: View {
    @StateObject private var patcher = Patcher()
    @AppStorage("mode") private var modeRaw = ""
    @AppStorage("bottle") private var bottle = ""
    @AppStorage("lang") private var lang = "auto"
    @State private var showRestoreConfirm = false
    @State private var showLog = false
    @State private var showDonate = false
    @AppStorage("donateHide") private var donateHide = false
    @State private var copied = false
    @State private var selected: Int?
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var mode: Mode? { Mode(rawValue: modeRaw) }
    var np: NPStatus { patcher.np }
    var cx: CXStatus { patcher.cx }
    var loaded: Bool { mode == .notproton ? np.loaded : cx.loaded }

    var steps: [StepInfo] {
        switch mode {
        case .notproton:
            return [
                StepInfo(id: 1, title: T("安装 NotProton，设置 CrossOver"), done: np.runnerFound),
                StepInfo(id: 2, title: T("在 Steam 里选 NotProton，下载游戏"), done: np.gameFiles),
                StepInfo(id: 3, title: T("启动一次游戏"), done: np.prefix),
                StepInfo(id: 4, title: T("安装补丁"), done: np.patched && np.dlssFiles),
                StepInfo(id: 5, title: T("粘贴 Steam 启动选项"), done: np.launchOptions == "set"),
            ]
        case .crossover:
            let b = cx.bottles.first { $0.name == bottle }
            return [
                StepInfo(id: 1, title: T("安装 CrossOver 26.3"), done: cx.rightVersion),
                StepInfo(id: 2, title: T("新建 bottle，安装 Windows 版 Steam"), done: b?.steam == true),
                StepInfo(id: 3, title: T("在 bottle 的 Steam 里下载游戏"), done: b?.game == true),
                StepInfo(id: 4, title: T("安装补丁"), done: cx.appPatched && cx.bottlePatched),
            ]
        case nil:
            return []
        }
    }
    var current: Int? { steps.first { !$0.done }?.id }
    var shown: Int? { selected ?? current }

    func refresh() { if let m = mode { patcher.refresh(mode: m, bottle: bottle) } }

    var body: some View {
        Group {
            if mode == nil { modeChooser } else { wizard }
        }
        .id(lang)
        .sheet(isPresented: $showDonate) { donateSheet }
        .onAppear {
            // the donation window opens at launch (Chinese UI with the Alipay code) until the user turns it off
            if uiLang() == "zh", alipayQR != nil, !donateHide { showDonate = true }
            do { try patcher.preparePatch(); refresh() }
            catch { patcher.log = T("准备补丁文件失败：") + error.localizedDescription; showLog = true }
        }
        .onReceive(timer) { _ in if !patcher.busy { refresh() } }
        .onChange(of: current) { selected = nil; copied = false }
        .onChange(of: modeRaw) { selected = nil; patcher.lastOK = nil; patcher.needsForce = false; refresh() }
        .onChange(of: bottle) { refresh() }
        .onChange(of: cx.bottles) { pickBottle() }
        .confirmationDialog(T("把所有改动还原成官方原版？"), isPresented: $showRestoreConfirm) {
            Button(T("还原"), role: .destructive) { patcher.restore(mode: mode ?? .notproton, bottle: bottle) { refresh() } }
        } message: {
            Text(mode == .crossover ? T("会还原 CrossOver 的文件，以及所选 bottle 的设置。请先完全退出 CrossOver。")
                                    : T("会还原 CrossOver 的文件、删除启动脚本。之后记得清空 Steam 里的启动选项。"))
        }
    }

    // choose a bottle with Windows Steam (and the game) when none is chosen yet
    func pickBottle() {
        guard mode == .crossover, !cx.bottles.contains(where: { $0.name == bottle && $0.steam }) else { return }
        if let b = cx.bottles.first(where: { $0.game }) ?? cx.bottles.first(where: { $0.steam }) { bottle = b.name }
    }

    var languagePicker: some View {
        Picker(T("语言"), selection: $lang) {
            Text(T("跟随系统")).tag("auto")
            Text("简体中文").tag("zh")
            Text("English").tag("en")
        }
    }

    // Chinese UI: the Alipay QR code shipped in Resources. Other languages: the donation web page.
    var alipayQR: NSImage? { Bundle.main.url(forResource: "donate-alipay", withExtension: "png").flatMap { NSImage(contentsOf: $0) } }
    var canDonate: Bool { uiLang() == "zh" ? (alipayQR != nil || !donationURL.isEmpty) : !donationURL.isEmpty }
    func openDonation() {
        if uiLang() == "zh", alipayQR != nil { showDonate = true }
        else if let u = URL(string: donationURL) { NSWorkspace.shared.open(u) }
    }
    var donateSheet: some View {
        VStack(spacing: 14) {
            Banner(image: "key", height: 110, align: .bottom) { Text(T("支持作者")).font(.title2.bold()).foregroundStyle(.white) }
            Text(T("制作补丁不易，花了很多时间调试。补丁永久免费，如果它帮到了你，欢迎用支付宝扫码支持作者。")).multilineTextAlignment(.center)
            if let img = alipayQR { Image(nsImage: img).resizable().scaledToFit().frame(height: 420) }
            Toggle(T("启动时不再自动弹出"), isOn: $donateHide).font(.callout)
            Button(T("关闭")) { showDonate = false }.keyboardShortcut(.defaultAction)
        }
        .padding(24).frame(width: 380)
    }

    // MARK: first screen

    var modeChooser: some View {
        VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(T("影之刃零 · Mac 补丁")).font(.system(size: 30, weight: .heavy))
                        Text(T("在 Apple 芯片 Mac 上畅玩《影之刃零》")).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    ForEach([T("一键安装"), "DLSS", "FSR 4", T("插帧"), "中文 / English"], id: \.self) { t in
                        Text(t).font(.caption.bold()).lineLimit(1).fixedSize().padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(brandRed.opacity(0.25))).overlay(Capsule().stroke(brandRed.opacity(0.6)))
                    }
                }
                Text(T("你打算怎么玩？")).font(.title3.bold()).padding(.top, 6)
                VStack(spacing: 12) {
                    modeCard(.notproton, symbol: "gamecontroller.fill", title: "NotProton", subtitle: T("用 Mac 版 Steam 玩（推荐）"),
                             points: [T("已实测，能正常游玩"), T("支持 DLSS；每次启动编译着色器约 7～10 分钟"), T("需要安装 NotProton")])
                    modeCard(.crossover, symbol: "macwindow.on.rectangle", title: "CrossOver", subtitle: T("在 CrossOver 的 bottle 里装 Windows 版 Steam"),
                             points: [T("不需要 NotProton"), T("尚未在 bottle 里实测过游戏"), T("没有打开 DLSS")])
                }
                HStack {
                    languagePicker.pickerStyle(.segmented).fixedSize()
                    Spacer()
                    Text(T("之后可以在左上角随时切换。")).font(.caption).foregroundStyle(.secondary)
                }
                Text(T("非官方补丁，与 S-GAME 无关；需要在 Steam 购买正版游戏。游戏图片版权归 S-GAME 所有。"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        .padding(32)
        .frame(width: 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .background {
            GeometryReader { g in
                ZStack {
                    if let img = art("key") {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: g.size.width, height: g.size.height, alignment: .trailing).clipped()
                    }
                    LinearGradient(stops: [.init(color: .black.opacity(0.0), location: 0), .init(color: .black.opacity(0.5), location: 0.4),
                                           .init(color: .black.opacity(0.93), location: 0.62)], startPoint: .leading, endPoint: .trailing)
                }
            }
        }
    }

    func modeCard(_ m: Mode, symbol: String, title: String, subtitle: String, points: [String]) -> some View {
        Button { modeRaw = m.rawValue } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: symbol).font(.title).foregroundStyle(Color.accentColor).frame(width: 40)
                    Text(title).font(.title2.bold())
                }
                Text(subtitle).foregroundStyle(.secondary)
                Divider()
                ForEach(points, id: \.self) { p in
                    HStack(alignment: .firstTextBaseline, spacing: 6) { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(brandRed); Text(p) }.font(.callout)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(m.rawValue == modeRaw ? brandRed : .white.opacity(0.12), lineWidth: m.rawValue == modeRaw ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: wizard

    var wizard: some View {
        HStack(alignment: .top, spacing: 0) {
            stepList.frame(width: 290).background(Color.black.opacity(0.35))
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !loaded { ProgressView(T("正在检测…")) }
                        else if let id = shown { banner(id); detail(id) }
                        else { allDone }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                footer
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var stepList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Banner(image: "side", height: 120) {
                HStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                    Text(T("影之刃零 · Mac 补丁")).font(.title3.bold()).foregroundStyle(.white)
                }
            }
            Picker("", selection: $modeRaw) {
                Text("NotProton").tag(Mode.notproton.rawValue)
                Text("CrossOver").tag(Mode.crossover.rawValue)
            }
            .pickerStyle(.segmented).labelsHidden().padding(.vertical, 8)
            ForEach(steps) { step in
                let isCurrent = step.id == current
                let done = loaded && step.done
                Button { selected = step.id } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(done ? Color.green : isCurrent ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 26, height: 26)
                            if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                            else { Text("\(step.id)").font(.callout.bold()).foregroundStyle(isCurrent ? .white : .secondary) }
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.title).font(.callout.weight(isCurrent ? .semibold : .regular))
                                .foregroundStyle(done || isCurrent ? .primary : .secondary)
                                .multilineTextAlignment(.leading)
                            if isCurrent { Text(T("← 你在这一步")).font(.caption).foregroundStyle(Color.accentColor) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(shown == step.id ? Color.accentColor.opacity(0.12) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if mode == .notproton {
                Divider().padding(.vertical, 6)
                Button { selected = 100 } label: {
                    HStack(spacing: 10) {
                        Image(systemName: np.lsfg == "on" ? "sparkles" : "sparkles.square.filled.on.square")
                            .frame(width: 26).foregroundStyle(np.lsfg == "on" ? Color.green : Color.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(T("可选：Lossless 插帧")).font(.callout)
                            Text(np.lsfg == "on" ? T("已开启") : T("未开启")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selected == 100 ? Color.accentColor.opacity(0.12) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if mode == .notproton {
                Button { selected = 101 } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(width: 26).foregroundStyle(np.fsr4 == "on" ? Color.green : Color.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(T("可选：FSR 4 放大")).font(.callout)
                            Text(np.fsr4 == "on" ? T("已开启") : T("未开启")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selected == 101 ? Color.accentColor.opacity(0.12) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if canDonate {
                Button { openDonation() } label: { Label(T("支持作者（捐赠）"), systemImage: "heart.fill") }
                    .buttonStyle(.link).font(.callout)
            }
            Text(T("每 4 秒自动检测一次，做完一步会自动跳到下一步。")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    func banner(_ id: Int) -> some View {
        let tag = id >= 100 ? T("可选") : String(format: T("第 %d 步"), id)
        let title = id == 100 ? T("Lossless 插帧") : id == 101 ? T("FSR 4 放大") : (steps.first { $0.id == id }?.title ?? "")
        let img = id == 100 ? "lsfg" : id == 101 ? "fsr4" : "step\(min(id, 5))"
        return Banner(image: img, height: 170) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tag).font(.headline).foregroundStyle(brandRed)
                Text(title).font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    func detail(_ id: Int) -> some View {
        if id == 100 { lsfgPanel } else if id == 101 { fsr4Panel } else { stepDetail(id) }
    }

    var fsr4Panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("开启后，游戏里选 DLSS 时实际运行 FSR 4，而不是 MetalFX。画质通常更好，但会增加 GPU 负担、降低帧数，所以默认关闭。只在 NotProton 下可用。"))
            instructions([
                T("安装 Xcode 26 或更高，再在终端运行 xcodebuild -downloadComponent MetalToolchain。"),
                T("下面打勾后，点“开启 FSR 4”，再启动游戏。不用改启动选项。"),
                T("在游戏里把放大方式选成 DLSS。第一次运行时 FSR 4 要编译着色器，会卡十几秒。"),
                T("启动时会同时弹出 FSR 4 面板，可以调锐度。如果游戏停在警告画面没反应，点一下游戏窗口。")
            ])
            GroupBox {
                VStack(alignment: .leading, spacing: 3) {
                    check(T("Xcode 的 Metal Toolchain 和 Python 3"), np.fsr4Toolchain == "ok")
                    check(T("NotProton 运行环境"), np.runnerFound)
                }
                .font(.callout)
            }
            HStack {
                if np.fsr4 == "on" {
                    Button { patcher.setFsr4(false) { refresh() } } label: { Label(T("关闭 FSR 4"), systemImage: "stop.circle") }
                        .controlSize(.large)
                } else {
                    Button { patcher.setFsr4(true) { refresh() } } label: { Label(T("开启 FSR 4"), systemImage: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(patcher.busy || np.fsr4Toolchain != "ok" || !np.runnerFound)
                }
                Text(np.fsr4 == "on" ? T("已开启") : T("未开启")).foregroundStyle(.secondary)
            }
            if let ok = patcher.lastOK, selected == 101 {
                Label(ok ? T("完成，下次启动游戏生效") : T("没有完成，点下面“显示输出”查看原因"), systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? .green : .red)
            }
        }
    }

    var lsfgPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("用 Lossless Scaling 的插帧，把每秒约 60 帧变成约 120 帧。只在 NotProton 下可用。"))
            instructions([
                T("在 Steam 购买 Lossless Scaling（付费软件，补丁不能附带它的文件），并让它的 Lossless.dll 出现在 Steam 库里，或者放到 ~/lsfg/lsfg-vk.dll。"),
                T("安装 LsfgInjector，打开一次，让它准备好 ~/lsfg 里的文件。"),
                T("下面两项都打勾后，点“开启插帧”，再启动游戏。"),
                T("游戏里的帧生成要关掉，只留一个插帧。")
            ])
            GroupBox {
                VStack(alignment: .leading, spacing: 3) {
                    check("Lossless.dll", !np.lsfgSources.contains("Lossless.dll"))
                    check(T("LsfgInjector 的文件（~/lsfg）"), !np.lsfgSources.contains("lsfg-shim") && !np.lsfgSources.contains("moltenvk"))
                    check(T("NotProton 运行环境"), np.runnerFound)
                }
                .font(.callout)
            }
            HStack {
                if np.lsfg == "on" {
                    Button { patcher.setLsfg(false) { refresh() } } label: { Label(T("关闭插帧"), systemImage: "stop.circle") }
                        .controlSize(.large)
                } else {
                    Button { patcher.setLsfg(true) { refresh() } } label: { Label(T("开启插帧"), systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(patcher.busy || np.lsfgSources != "ok" || !np.runnerFound)
                }
                Text(np.lsfg == "on" ? T("已开启") : T("未开启")).foregroundStyle(.secondary)
            }
            if let ok = patcher.lastOK, selected == 100 {
                Label(ok ? T("完成，下次启动游戏生效") : T("没有完成，点下面“显示输出”查看原因"), systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(ok ? .green : .red)
            }
            Text(T("设置文件在 ~/.config/lsfg-metal/conf.toml，游戏运行中也可以改：multiplier 是倍数，flow_scale 是光流精度。override_present_mode 必须保持 true，否则游戏会卡死。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func stepDetail(_ id: Int) -> some View {
        let step = steps.first { $0.id == id }
        if step?.done == true && id != current {
            Label(T("这一步已经完成"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
        if mode == .notproton { npDetail(id) } else { cxDetail(id) }
    }

    // MARK: NotProton steps

    @ViewBuilder
    func npDetail(_ id: Int) -> some View {
        switch id {
        case 1:
            instructions([
                T("从 github.com/NotProtonNot/NotProton 下载安装 NotProton（或用 brew 安装）。"),
                T("打开 NotProton，在 CrossOver 一栏找到 CrossOver 26.3（构建版本 26.3.0.39832），点“设置”，等左边的圆圈变成绿点。"),
                T("建议同时打开“阻止 Steam 客户端更新”。"),
                T("完全退出 Steam，再重新打开。")
            ])
            Button(T("打开 NotProton 网页")) { NSWorkspace.shared.open(URL(string: "https://github.com/NotProtonNot/NotProton")!) }
        case 2:
            instructions([
                T("在 Steam 库里右键影之刃零 → 属性 → 兼容性。"),
                T("勾选“强制使用特定 Steam Play 兼容性工具”，选 NotProton 26.3，图形选 D3DMetal。"),
                T("回到游戏页面，点“安装”，等它下载完。"),
                T("下拉菜单里没有 NotProton：回到第 1 步，确认已经设置好并重启过 Steam。")
            ])
        case 3:
            instructions([
                T("在 Steam 里点“开始”，启动一次影之刃零。"),
                T("这次可能卡住、闪退或者没反应，都没关系，目的是让 NotProton 建好游戏的运行环境。"),
                T("等半分钟左右，在 Steam 里点“停止”。")
            ])
        case 4:
            VStack(alignment: .leading, spacing: 10) {
                instructions([
                    T("确认游戏已经退出。"),
                    T("点“安装补丁”，等下面出现“完成”。苹果的 D3DMetal 4.0b3 已经包含在补丁里，不用另外下载。")
                ])
                gptkPicker
                applyButtons { force in patcher.applyNotProton(force: force) { refresh() } }
                GroupBox {
                    VStack(alignment: .leading, spacing: 3) {
                        check(T("Denuvo 修正"), np.ntdll == "patched")
                        check(T("视频解码（NV12）"), np.gstreamer == "patched")
                        check("D3DMetal 4.0b3", np.d3dmetal.contains("4.0b3") && !np.d3dmetal.contains("no DLSS"))
                        check(T("Denuvo 设置（注册表）"), np.registry)
                        check(T("DLSS 文件"), np.dlssFiles)
                        check(T("启动脚本"), np.launcher)
                    }
                    .font(.callout)
                }
            }
        case 5:
            instructions([
                T("点下面的“复制”。"),
                T("Steam 里右键影之刃零 → 属性 → 通用 → 启动选项，粘贴进去，替换原有内容。"),
                T("关掉属性窗口，这一步会自动打勾。")
            ])
            HStack(alignment: .top) {
                Text(patcher.launchOptions).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
                Button(copied ? T("已复制") : T("复制")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(patcher.launchOptions, forType: .string)
                    copied = true
                }
                .buttonStyle(.borderedProminent)
            }
            if np.launchOptions == "other" {
                Label(T("现在的启动选项里没有补丁的启动脚本，请整行替换。"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        default:
            instructions([
                T("在 Steam 里启动影之刃零。"),
                T("弹出“运行环境检查”（提示缺 VC++）就点“继续游戏”。"),
                T("每次启动都要编译着色器，大约 7～10 分钟。")
            ])
        }
    }

    // MARK: CrossOver steps

    @ViewBuilder
    func cxDetail(_ id: Int) -> some View {
        switch id {
        case 1:
            instructions([
                T("从 codeweavers.com 下载安装 CrossOver 26.3（构建版本必须是 26.3.0.39832）。"),
                T("装好后打开一次 CrossOver，再完全退出。")
            ])
            if !cx.version.isEmpty && !cx.rightVersion {
                Label(String(format: T("找到的 CrossOver 版本是 %@，补丁只支持 26.3.0.39832。"), cx.version), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            cxAppPicker
            Button(T("打开 CrossOver 网页")) { NSWorkspace.shared.open(URL(string: "https://www.codeweavers.com/crossover")!) }
        case 2:
            instructions([
                T("打开 CrossOver，点“安装”，搜索 Steam，按提示新建一个 bottle 并安装 Windows 版 Steam。"),
                T("装好后在这个 bottle 里启动 Steam，登录账号。"),
                T("如果有好几个 bottle，在下面选你装了 Steam 的那个。")
            ])
            bottlePicker
        case 3:
            instructions([
                T("在 bottle 里的 Steam 搜索并安装影之刃零（装在默认的 Steam 库里）。"),
                T("等它下载完。")
            ])
            bottlePicker
        case 5:
            cxLaunchStep()
        default:
            VStack(alignment: .leading, spacing: 10) {
                instructions([
                    T("完全退出 CrossOver（包括里面的 Steam 和游戏）。"),
                    T("点“安装补丁”，等下面出现“完成”。苹果的 D3DMetal 4.0b3 已经包含在补丁里。")
                ])
                if cx.running {
                    Label(T("CrossOver 还在运行，请先完全退出（菜单栏 CrossOver → 退出）。"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                gptkPicker
                applyButtons(disabled: cx.running || bottle.isEmpty) { force in
                    patcher.applyCrossOver(bottle: bottle, force: force) { refresh() }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 3) {
                        check(T("Denuvo 修正"), cx.ntdll == "patched")
                        check(T("视频解码（NV12）"), cx.gstreamer == "patched")
                        check("D3DMetal 4.0b3", cx.d3dmetal.contains("4.0b3") && !cx.d3dmetal.contains("no DLSS"))
                        check(T("关闭全局 DLSS→MetalFX（否则 Steam 黑屏）"), !cx.globalMetalFX.hasPrefix("on"))
                        check(T("bottle 图形后端设为 D3DMetal"), cx.backend.contains("d3dmetal"))
                        check(T("Denuvo 设置和 VC++ 运行库（注册表）"), cx.registry)
                    }
                    .font(.callout)
                }
            }
        }
    }

    @ViewBuilder
    func cxLaunchStep() -> some View {
        instructions([
            String(format: T("打开 CrossOver，在 bottle「%@」里启动 Steam，运行影之刃零。不需要设置启动选项。"), bottle),
            T("弹出“运行环境检查”（提示缺 VC++）就点“继续游戏”。"),
            T("每次启动都要编译着色器，大约 7～10 分钟。")
        ])
    }

    var bottlePicker: some View {
        HStack {
            Text(T("bottle：")).bold()
            if cx.bottles.isEmpty {
                Text(T("还没有 bottle")).foregroundStyle(.secondary)
            } else {
                Picker("", selection: $bottle) {
                    ForEach(cx.bottles, id: \.name) { b in
                        Text(b.name + (b.game ? T("（有游戏）") : b.steam ? T("（有 Steam）") : T("（没有 Steam）"))).tag(b.name)
                    }
                }
                .labelsHidden().fixedSize()
            }
            Spacer()
        }
    }

    var cxAppPicker: some View {
        HStack {
            Text(T("CrossOver：")).bold()
            Text(cx.appPath.isEmpty ? T("没找到") : cx.appPath + (cx.version.isEmpty ? "" : " (\(cx.version))"))
                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(T("选择…")) {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.applicationBundle]
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                panel.message = T("选择 CrossOver 26.3")
                if panel.runModal() == .OK { patcher.cxApp = panel.url; refresh() }
            }
        }
    }

    // MARK: shared pieces

    var gptkPicker: some View {
        DisclosureGroup(T("高级：换用别的 GPTK")) {
            HStack {
                Text(patcher.gptkSource.map { T("使用：") + $0.path } ?? T("使用补丁自带的 D3DMetal 4.0b3（苹果 Game Porting Toolkit 4.0 beta 3）"))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(T("选择…")) { chooseGPTK() }
                if patcher.gptkSource != nil { Button(T("用自带的")) { patcher.gptkSource = nil } }
            }
            .padding(.top, 4)
        }
        .font(.callout)
    }

    func applyButtons(disabled: Bool = false, _ action: @escaping (Bool) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { action(false) } label: { Label(T("安装补丁"), systemImage: "wrench.and.screwdriver") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(patcher.busy || disabled)
                if patcher.needsForce {
                    Button(T("仍然安装（官方签名的另一版本）")) { action(true) }.disabled(patcher.busy || disabled)
                }
            }
            if patcher.needsForce {
                Text(T("你的 CrossOver 是官方签名的同版本另一次编译，可以放心点“仍然安装”，原文件会先备份。")).font(.callout).foregroundStyle(.secondary)
            }
            if let ok = patcher.lastOK {
                Label(ok ? T("完成") : T("没有完成，点下面“显示输出”查看原因"), systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(ok ? .green : .red)
            }
        }
    }

    var allDone: some View {
        VStack(alignment: .leading, spacing: 10) {
            Banner(image: "done", height: 240) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(T("全部完成"), systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.green)
                    Text(T("准备开战")).font(.system(size: 34, weight: .heavy)).foregroundStyle(.white)
                }
            }
            if mode == .crossover {
                instructions([
                    String(format: T("打开 CrossOver，在 bottle「%@」里启动 Steam，运行影之刃零。不需要设置启动选项。"), bottle),
                    T("弹出“运行环境检查”（提示缺 VC++）就点“继续游戏”。"),
                    T("每次启动都要编译着色器，大约 7～10 分钟。")
                ])
            } else {
                instructions([
                    T("在 Steam 里启动影之刃零。"),
                    T("弹出“运行环境检查”（提示缺 VC++）就点“继续游戏”。"),
                    T("每次启动都要编译着色器，大约 7～10 分钟。"),
                    T("想用 DLSS：在游戏设置里把放大方式选成 DLSS。")
                ])
            }
            Text(T("NotProton 或 CrossOver 更新后，补丁可能被覆盖，这里会自动退回到相应的步骤，照着重新做一遍即可。"))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showLog {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(patcher.log.isEmpty ? T("（还没有运行）") : patcher.log)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id("end")
                    }
                    .onChange(of: patcher.log) { proxy.scrollTo("end", anchor: .bottom) }
                }
                .frame(height: 150)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.4)))
            }
            HStack {
                if patcher.busy { ProgressView().controlSize(.small); Text(T("运行中…")).font(.callout) }
                Button(showLog ? T("隐藏输出") : T("显示输出")) { showLog.toggle() }
                Spacer()
                Menu(T("更多")) {
                    Button(T("打开说明")) { NSWorkspace.shared.open(patcher.workDir.appendingPathComponent("README.md")) }
                    Button(T("苹果 GPTK 许可")) { NSWorkspace.shared.open(patcher.workDir.appendingPathComponent("components/gptk/License.rtf")) }
                    languagePicker
                    if canDonate { Button(T("支持作者（捐赠）")) { openDonation() } }
                    Divider()
                    Button(T("全部还原…"), role: .destructive) { showRestoreConfirm = true }
                }
                .fixedSize()
                .disabled(patcher.busy)
            }
        }
    }

    func instructions(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1).").bold().frame(width: 18, alignment: .trailing)
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    func check(_ title: String, _ ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? .green : .secondary)
            Text(title)
        }
    }

    func chooseGPTK() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.diskImage, .folder, .applicationBundle]
        panel.message = T("选择 Game Porting Toolkit 4.0 beta 3 的 .dmg、GPTKPatcher 文件夹或 CrossOver")
        if panel.runModal() == .OK { patcher.gptkSource = panel.url }
    }
}
