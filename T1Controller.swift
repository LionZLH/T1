import Cocoa
import SwiftUI
import Combine
import CoreGraphics
import IOKit
import IOKit.hid
import Foundation

// ============================================================
// MARK: - 真实底层硬件 SenderID 与纯净 IOHIDEvent 提取接口 (macOS CoreGraphics Private)
// ============================================================
@_silgen_name("CGEventCopyIOHIDEvent")
func CGEventCopyIOHIDEvent(_ event: CGEvent) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventGetSenderID")
func IOHIDEventGetSenderID(_ event: AnyObject) -> UInt64

@_silgen_name("IOHIDEventGetDoubleValue")
func IOHIDEventGetDoubleValue(_ event: AnyObject, _ field: UInt32) -> Double

@_silgen_name("IOHIDEventGetIntegerValue")
func IOHIDEventGetIntegerValue(_ event: AnyObject, _ field: UInt32) -> Int

let kIOHIDEventFieldPointerX: UInt32 = (17 << 16) | 0
let kIOHIDEventFieldPointerY: UInt32 = (17 << 16) | 1

struct RemoteButton: Identifiable {
    var id: String
    var title: String
    var symbol: String
    var side: Int
    var anchorX: CGFloat
    var anchorY: CGFloat
    var nativeSingle: String
    var fnLegend: String
}

struct ButtonMap: Codable, Identifiable, Equatable {
    var id: String
    var kind: Int?
    var source: Int?
    var single: Int?
    var doubleTap: Int?
    var hold: Int?
}

enum RemoteCatalog {
    // 正面 14 颗按键：圆盘上、左、确认、下，返回、静音、飞鼠；电源、音量+、音量-、右、语音、主页、菜单
    // 左右各 7 颗对称排布，双侧键独立识别（音量加 / 音量减），坐标精准对齐 remote-front.png（225x662 像素级测绘）
    static let front: [RemoteButton] = [
        // 顶部与侧边（右侧 7 颗）
        RemoteButton(id: "power", title: "电源", symbol: "power", side: 1, anchorX: 0.781, anchorY: 0.066, nativeSingle: "电源", fnLegend: ""),
        RemoteButton(id: "volup", title: "音量+", symbol: "speaker.plus", side: 1, anchorX: 0.982, anchorY: 0.169, nativeSingle: "音量+", fnLegend: ""),
        RemoteButton(id: "voldown", title: "音量−", symbol: "speaker.minus", side: 1, anchorX: 0.982, anchorY: 0.240, nativeSingle: "音量−", fnLegend: ""),
        RemoteButton(id: "right", title: "右", symbol: "chevron.right", side: 1, anchorX: 0.698, anchorY: 0.236, nativeSingle: "右", fnLegend: ""),
        RemoteButton(id: "voice", title: "语音", symbol: "mic", side: 1, anchorX: 0.692, anchorY: 0.392, nativeSingle: "语音", fnLegend: ""),
        RemoteButton(id: "home", title: "主页", symbol: "house", side: 1, anchorX: 0.691, anchorY: 0.514, nativeSingle: "主页", fnLegend: ""),
        RemoteButton(id: "menu", title: "菜单", symbol: "line.3.horizontal", side: 1, anchorX: 0.693, anchorY: 0.636, nativeSingle: "菜单", fnLegend: ""),

        // 导航圆盘与左下（左侧 7 颗）
        RemoteButton(id: "up", title: "上", symbol: "chevron.up", side: 0, anchorX: 0.493, anchorY: 0.166, nativeSingle: "上", fnLegend: ""),
        RemoteButton(id: "left", title: "左", symbol: "chevron.left", side: 0, anchorX: 0.289, anchorY: 0.236, nativeSingle: "左", fnLegend: ""),
        RemoteButton(id: "ok", title: "确认", symbol: "circle", side: 0, anchorX: 0.493, anchorY: 0.236, nativeSingle: "左键", fnLegend: ""),
        RemoteButton(id: "down", title: "下", symbol: "chevron.down", side: 0, anchorX: 0.493, anchorY: 0.305, nativeSingle: "下", fnLegend: ""),
        RemoteButton(id: "back", title: "返回", symbol: "arrow.left", side: 0, anchorX: 0.282, anchorY: 0.395, nativeSingle: "返回", fnLegend: ""),
        RemoteButton(id: "mute", title: "静音", symbol: "speaker.slash", side: 0, anchorX: 0.284, anchorY: 0.515, nativeSingle: "静音", fnLegend: ""),
        RemoteButton(id: "pointer", title: "飞鼠", symbol: "hand.raised", side: 0, anchorX: 0.291, anchorY: 0.637, nativeSingle: "切换飞鼠", fnLegend: "")
    ]

    // 背面键位：坐标已精确对齐 remote-back.png（673x230 像素级测绘，45 颗物理按键几何质心对齐）
    static let columnCtrl: [RemoteButton] = [
        key("ctrl", "Ctrl", 0.241, 0.130, "Ctrl", ";"),
        key("fn", "Fn", 0.241, 0.210, "Fn", ""),
        key("minus", "−", 0.241, 0.278, "−", "["),
        key("equal", "=", 0.241, 0.346, "=", "]"),
        key("alt", "Alt", 0.241, 0.413, "Alt", "("),
        key("space", "空格", 0.241, 0.513, "空格", ""),
        key("altgr", "AltGr", 0.241, 0.612, "AltGr", "}"),
        key("homeKey", "Home", 0.241, 0.678, "Home", ""),
        key("pgdn", "PgDn", 0.241, 0.743, "下翻页", ""),
        key("end", "End", 0.241, 0.808, "End", ""),
        key("www", "WWW", 0.241, 0.880, "WWW", "")
    ]
    static let columnShift: [RemoteButton] = [
        key("shift", "Shift", 0.415, 0.148, "Shift", "\\"),
        key("z", "Z", 0.415, 0.245, "Z", "<"),
        key("x", "X", 0.415, 0.314, "X", ">"),
        key("c", "C", 0.415, 0.382, "C", ":"),
        key("v", "V", 0.415, 0.449, "V", "\""),
        key("b", "B", 0.415, 0.515, "B", ";"),
        key("n", "N", 0.415, 0.581, "N", "'"),
        key("m", "M", 0.415, 0.647, "M", "?"),
        key("slash", "/", 0.417, 0.712, "/", ""),
        key("pgup", "PgUp", 0.417, 0.778, "上翻页", ""),
        key("enter", "回车", 0.417, 0.864, "回车", "Ctrl+Alt+Del")
    ]
    static let columnCaps: [RemoteButton] = [
        key("caps", "Caps", 0.589, 0.156, "Caps", "~"),
        key("a", "A", 0.589, 0.261, "A", "!"),
        key("s", "S", 0.589, 0.330, "S", "@"),
        key("d", "D", 0.589, 0.397, "D", "#"),
        key("f", "F", 0.589, 0.464, "F", "$"),
        key("g", "G", 0.591, 0.530, "G", "%"),
        key("h", "H", 0.593, 0.596, "H", "^"),
        key("j", "J", 0.593, 0.662, "J", "&"),
        key("k", "K", 0.593, 0.727, "K", "*"),
        key("l", "L", 0.593, 0.793, "L", "("),
        key("backspace", "BACK", 0.593, 0.871, "退格", "")
    ]
    static let columnEsc: [RemoteButton] = [
        key("esc", "Esc", 0.763, 0.130, "Esc", "`"),
        key("q", "Q", 0.763, 0.210, "Q", "'"),
        key("w", "W", 0.765, 0.278, "W", "1"),
        key("e", "E", 0.765, 0.345, "E", "2"),
        key("r", "R", 0.765, 0.413, "R", "3"),
        key("t", "T", 0.767, 0.480, "T", "4"),
        key("y", "Y", 0.767, 0.547, "Y", "5"),
        key("u", "U", 0.767, 0.612, "U", "6"),
        key("i", "I", 0.767, 0.678, "I", "7"),
        key("o", "O", 0.767, 0.743, "O", "8"),
        key("p", "P", 0.767, 0.808, "P", "9"),
        key("del", "Del", 0.767, 0.879, "Del", "0")
    ]
    static let back: [RemoteButton] = columnCtrl + columnShift + columnCaps + columnEsc

    private static func key(_ id: String, _ title: String, _ x: CGFloat, _ y: CGFloat, _ single: String, _ fn: String) -> RemoteButton {
        RemoteButton(id: id, title: title, symbol: "circle", side: 0, anchorX: x, anchorY: y, nativeSingle: single, fnLegend: fn)
    }

    static func title(for id: String) -> String {
        let all = front + back
        return all.first { $0.id == id }?.title ?? "按键"
    }

    static func note(for side: Int) -> String {
        if side == 0 {
            return "点照片或卡片上的按键改映射。圆盘上、下、左、右为方向键，中间是确认。电源在右上，音量加减在右侧边。返回和语音在圆盘下面。左下为静音和飞鼠，右下为主页和菜单。"
        }
        return "点单击、双击或长按，再按键盘上要映射成的键。蓝色字要按住 Fn。"
    }

    // 默认硬件源：正面按键与背面 44 颗全键盘键
    // kind: 0=键盘键码, 1=媒体键码, 2=鼠标键码(1001左键, 1002右键)
    static let defaultSources: [String: (kind: Int, source: Int)] = [
        // 正面 14 颗按键
        "ok": (2, 1001),         // 鼠标左键
        "back": (2, 1002),       // 鼠标右键
        "up": (0, 126),          // 上方向键
        "down": (0, 125),        // 下方向键
        "left": (0, 123),        // 左方向键
        "right": (0, 124),       // 右方向键
        "mute": (1, 7),          // 媒体静音
        "pointer": (0, 999),     // 飞鼠键
        "power": (0, 127),       // 电源
        "volup": (1, 0),         // 侧上键 (音量加)
        "voldown": (1, 1),       // 侧下键 (音量减)
        "voice": (0, 129),       // 语音
        "home": (0, 115),        // 主页
        "menu": (0, 130),        // 菜单

        // 背面 44 颗全键盘按键
        "ctrl": (0, 59), "fn": (0, 63), "minus": (0, 27), "equal": (0, 24), "alt": (0, 58), "space": (0, 49),
        "altgr": (0, 61), "homeKey": (0, 115), "pgdn": (0, 121), "end": (0, 119), "www": (0, 131),
        "shift": (0, 56), "z": (0, 6), "x": (0, 7), "c": (0, 8), "v": (0, 9), "b": (0, 11), "n": (0, 45), "m": (0, 46), "slash": (0, 44),
        "pgup": (0, 116), "enter": (0, 36),
        "caps": (0, 57), "a": (0, 0), "s": (0, 1), "d": (0, 2), "f": (0, 3), "g": (0, 5), "h": (0, 4), "j": (0, 38), "k": (0, 40), "l": (0, 37),
        "backspace": (0, 51),
        "esc": (0, 53), "q": (0, 12), "w": (0, 13), "e": (0, 14), "r": (0, 15), "t": (0, 17), "y": (0, 16), "u": (0, 32), "i": (0, 34), "o": (0, 31), "p": (0, 35),
        "del": (0, 117)
    ]

    static var keycodes: [String: Int] {
        var res: [String: Int] = [:]
        for (k, v) in defaultSources {
            res[k] = v.source
        }
        return res
    }
}

enum KeyCatalog {
    static let targets: [(name: String, code: Int)] = [
        ("回车", 36),
        ("Esc", 53),
        ("空格", 49),
        ("Tab", 48),
        ("退格", 51),
        ("删除", 117),
        ("左", 123),
        ("右", 124),
        ("上", 126),
        ("下", 125),
        ("Home", 115),
        ("End", 119),
        ("上翻页", 116),
        ("下翻页", 121),
        ("鼠标左键", 1001),
        ("鼠标右键", 1002),
        ("音量+", 2000),
        ("音量−", 2001),
        ("静音", 2007)
    ]

    static func name(kind: Int, code: Int) -> String {
        if kind == 1 {
            switch code {
            case 0: return "音量加"
            case 1: return "音量减"
            case 7: return "静音"
            case 16: return "播放"
            default: return "媒体键 \(code)"
            }
        }
        if let titled = titles[code] { return titled }
        return "键 \(code)"
    }

    static let titles: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "回车",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        48: "Tab", 49: "空格", 50: "`", 51: "退格", 53: "Esc",
        56: "Shift", 57: "Caps", 58: "Alt", 59: "Ctrl", 61: "AltGr", 63: "Fn",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
        115: "Home", 116: "上翻页", 117: "删除", 118: "F4", 119: "End", 120: "F2", 121: "下翻页", 122: "F1",
        123: "左", 124: "右", 125: "下", 126: "上",
        1001: "左键", 1002: "右键",
        2000: "音量+", 2001: "音量−", 2007: "静音"
    ]

    static func targetName(_ code: Int?) -> String {
        guard let code = code else { return "未设置" }
        if code >= 2000 && code <= 2020 {
            return titles[code] ?? name(kind: 1, code: code - 2000)
        }
        return name(kind: 0, code: code)
    }
}

// ============================================================
// MARK: - 响应式配置中心 (纯粹专注飞鼠平滑与人体工学)
// ============================================================
final class T1Settings: ObservableObject {
    // 主控开关
    @Published var isEngineEnabled: Bool = true

    // 是否在 Dock 中显示图标（默认 false：不在 Dock 显示，仅在顶部菜单栏常驻）
    @Published var showInDock: Bool = false {
        didSet {
            UserDefaults.standard.set(showInDock, forKey: "t1.showInDock")
            applyDockPolicy()
        }
    }

    // 绳子物理模型
    @Published var ropeLength: Double = 4.0      // 虚拟绳长 0 ~ 12px (手抖死区)
    @Published var followRate: Double = 0.25      // 牵引跟手率 0.05 ~ 0.80
    @Published var adaptiveRope: Bool = true      // 快速扫动时绳子自适应收紧

    // 灵敏度与人体工学
    @Published var scaleX: Double = 1.0           // X轴倍率
    @Published var scaleY: Double = 1.25          // Y轴倍率
    @Published var rightHandMode: Bool = true     // 右手模式
    @Published var tiltAngle: Double = -8.0       // 倾角校正 (-20° ~ 20°)
    @Published var rightBias: Double = 1.15       // 向右受限补偿 (1.0 ~ 1.5)

    // 实时状态监控。热路径计数不发布，界面按固定节拍取样，避免飞鼠每帧重绘面板。
    @Published var isConnected: Bool = false
    var totalFrames: Int = 0
    var absorbedFrames: Int = 0
    @Published var displayFrames: Int = 0
    @Published var displayAbsorbed: Int = 0
    @Published var isReceiving: Bool = false
    @Published var needsAccessibility: Bool = false
    @Published var keyMapEnabled: Bool = false
    @Published var captureButtonID: String? = nil
    @Published var captureSlot: Int? = nil
    @Published var keyCaptureNote: String = "点单击、双击或长按，再按键盘上要映射成的键"
    @Published var lastSuccessNote: String? = nil
    @Published var lastSuccessTime: CFAbsoluteTime = 0
    @Published var lastInputDisplay: String? = nil
    @Published var lastInputTime: CFAbsoluteTime = 0
    @Published var selectedBackKeyID: String = "a"

    func reportLastInput(_ text: String, senderButtonID: String? = nil) {
        lastInputDisplay = text
        lastInputTime = CFAbsoluteTimeGetCurrent()
        if let id = senderButtonID {
            selectedBackKeyID = id
        }
    }

    func cancelCapture() {
        captureButtonID = nil
        captureSlot = nil
        pendingTarget = nil
        keyCaptureNote = "已取消按键录制"
        syncKeyRuntime()
    }

    private var sourceSettle: DispatchWorkItem?
    private var pendingTarget: Int? = nil
    var lastBoundID: String?
    var lastBoundAt: CFAbsoluteTime = 0

    func shouldAdoptMouseSource() -> Bool {
        guard let id = lastBoundID, CFAbsoluteTimeGetCurrent() - lastBoundAt < 0.45 else { return false }
        return buttonMap(id)?.kind != 2
    }

    func adoptMouseSource(_ code: Int) {
        guard let id = lastBoundID, shouldAdoptMouseSource() else { return }
        writeSource(id: id, kind: 2, source: code)
        lastBoundID = nil
        saveKeys()
    }
    @Published var buttonMaps: [ButtonMap] = []
    private var lastPublishedFrames: Int = 0

    var absorbedRatio: Double {
        guard displayFrames > 0 else { return 0 }
        return Double(displayAbsorbed) / Double(displayFrames)
    }

    var absorbedPercent: String {
        guard displayFrames > 0 else { return "0.0%" }
        return String(format: "%.1f%%", absorbedRatio * 100.0)
    }

    func publishStats() {
        let receiving = totalFrames != lastPublishedFrames
        lastPublishedFrames = totalFrames
        if displayFrames != totalFrames { displayFrames = totalFrames }
        if displayAbsorbed != absorbedFrames { displayAbsorbed = absorbedFrames }
        if isReceiving != receiving { isReceiving = receiving }
        if lastSuccessNote != nil && CFAbsoluteTimeGetCurrent() - lastSuccessTime > 4.5 {
            lastSuccessNote = nil
        }
        if lastInputDisplay != nil && CFAbsoluteTimeGetCurrent() - lastInputTime > 3.5 {
            lastInputDisplay = nil
        }
    }

    func resetStats() {
        totalFrames = 0
        absorbedFrames = 0
        lastPublishedFrames = 0
        displayFrames = 0
        displayAbsorbed = 0
        isReceiving = false
    }

    func matchingPreset() -> Preset? {
        for preset in Preset.allCases where Self.matches(preset, rope: ropeLength, follow: followRate, scaleX: scaleX, scaleY: scaleY, adaptive: adaptiveRope) {
            return preset
        }
        return nil
    }

    // 一键预设方案
    func applyPreset(_ preset: Preset) {
        let spec = Self.spec(for: preset)
        ropeLength = spec.rope
        followRate = spec.follow
        scaleX = spec.scaleX
        scaleY = spec.scaleY
        adaptiveRope = spec.adaptive
        isEngineEnabled = preset != .native
        gCore.resetMotion()
        if preset == .native {
            gVirtualPos = nil
        }
    }

    private static func matches(_ preset: Preset, rope: Double, follow: Double, scaleX: Double, scaleY: Double, adaptive: Bool) -> Bool {
        let spec = spec(for: preset)
        return abs(rope - spec.rope) < 0.001
            && abs(follow - spec.follow) < 0.001
            && abs(scaleX - spec.scaleX) < 0.001
            && abs(scaleY - spec.scaleY) < 0.001
            && adaptive == spec.adaptive
    }

    private static func spec(for preset: Preset) -> (rope: Double, follow: Double, scaleX: Double, scaleY: Double, adaptive: Bool) {
        switch preset {
        case .balanced:
            return (4.0, 0.25, 1.0, 1.25, true)
        case .heavySmooth:
            return (10.0, 0.08, 0.85, 1.05, true)
        case .responsive:
            return (1.0, 0.70, 1.20, 1.55, true)
        case .native:
            return (0.0, 1.00, 1.0, 1.0, false)
        }
    }

    enum Preset: CaseIterable {
        case balanced
        case heavySmooth
        case responsive
        case native

        var title: String {
            switch self {
            case .balanced: return "舒适平衡"
            case .heavySmooth: return "彻底消抖"
            case .responsive: return "极速跟手"
            case .native: return "原生直通"
            }
        }

        var detail: String {
            switch self {
            case .balanced: return "日常悬空的默认手感"
            case .heavySmooth: return "慢速瞄准时把抖吃掉"
            case .responsive: return "轻推就走"
            case .native: return "不改写指针"
            }
        }
    }

    func buttonMap(_ id: String) -> ButtonMap? {
        buttonMaps.first { $0.id == id }
    }

    func loadKeys() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "t1.buttonMaps") == nil,
           let old = defaults.persistentDomain(forName: "T1Controller") {
            if let enabled = old["t1.keyMapEnabled"] as? Bool {
                defaults.set(enabled, forKey: "t1.keyMapEnabled")
            }
            if let data = old["t1.buttonMaps"] as? Data {
                defaults.set(data, forKey: "t1.buttonMaps")
            }
        }
        if defaults.object(forKey: "t1.keyMapEnabled") != nil {
            keyMapEnabled = defaults.bool(forKey: "t1.keyMapEnabled")
        }
        if defaults.object(forKey: "t1.showInDock") != nil {
            showInDock = defaults.bool(forKey: "t1.showInDock")
        } else {
            showInDock = false
        }
        if let data = defaults.data(forKey: "t1.buttonMaps"),
           let decoded = try? JSONDecoder().decode([ButtonMap].self, from: data) {
            buttonMaps = decoded
        }
        cleanupCorruptedMaps()
        syncKeyRuntime()
    }

    private func cleanupCorruptedMaps() {
        var changed = false
        // 1. 修复返回键硬件类型：返回键为鼠标右键 (kind: 2, source: 1002)
        if let idx = buttonMaps.firstIndex(where: { $0.id == "back" && ($0.kind != 2 || $0.source != 1002) }) {
            buttonMaps[idx].kind = 2
            buttonMaps[idx].source = 1002
            changed = true
        }
        // 2. 清理之前误把下方向键 (125) 绑定到主页 (home) 的损坏记录
        if let idx = buttonMaps.firstIndex(where: { $0.id == "home" && $0.source == 125 }) {
            buttonMaps.remove(at: idx)
            changed = true
        }
        // 3. 迁移旧的单个 side 按键配置为独立的 volup / voldown
        if let idx = buttonMaps.firstIndex(where: { $0.id == "side" }) {
            buttonMaps.remove(at: idx)
            changed = true
        }
        if changed {
            saveKeys()
        }
    }

    func clearAllMappings() {
        buttonMaps.removeAll()
        captureButtonID = nil
        captureSlot = nil
        pendingTarget = nil
        keyCaptureNote = "已清空所有按键映射，恢复系统默认原生功能"
        saveKeys()
    }

    func clearFrontMappings() {
        let frontIDs = Set(RemoteCatalog.front.map { $0.id })
        buttonMaps.removeAll { frontIDs.contains($0.id) }
        if let cap = captureButtonID, frontIDs.contains(cap) {
            cancelCapture()
        }
        lastSuccessNote = "已重置正面按键为默认原生功能"
        lastSuccessTime = CFAbsoluteTimeGetCurrent()
        keyCaptureNote = "已重置正面按键为默认原生功能"
        saveKeys()
    }

    func clearBackMappings() {
        let backIDs = Set(RemoteCatalog.back.map { $0.id })
        buttonMaps.removeAll { backIDs.contains($0.id) }
        if let cap = captureButtonID, backIDs.contains(cap) {
            cancelCapture()
        }
        lastSuccessNote = "已重置背面全键盘为默认原生功能"
        lastSuccessTime = CFAbsoluteTimeGetCurrent()
        keyCaptureNote = "已重置背面全键盘为默认原生功能"
        saveKeys()
    }

    func setKeyMapEnabled(_ on: Bool) {
        keyMapEnabled = on
        saveKeys()
    }

    func armButtonCapture(_ id: String) {
        armTargetCapture(id, 0)
    }

    func armTargetCapture(_ id: String, _ slot: Int) {
        if captureButtonID == id && captureSlot == slot {
            cancelCapture()
            return
        }
        bindKnownSource(id)
        captureButtonID = id
        captureSlot = slot
        pendingTarget = nil
        lastSuccessNote = nil
        keyCaptureNote = "按下键盘上要映射成的键，或右键直接选取"
        syncKeyRuntime()
    }

    func rememberKeyboardTarget(_ code: Int) {
        guard let id = captureButtonID, let slot = captureSlot else { return }
        bindKnownSource(id)
        finishTarget(id: id, slot: slot, code: code)
    }

    func capturePress(kind: Int, code: Int) {
        guard let id = captureButtonID else { return }
        if captureSlot != nil && buttonMap(id)?.source != nil {
            if kind == 0 {
                rememberKeyboardTarget(code)
                return
            } else if kind == 1 {
                rememberKeyboardTarget(2000 + code)
                return
            }
        }
        rememberButton(kind: kind, source: code)
    }
    func rememberButton(kind: Int, source: Int) {
        guard let id = captureButtonID else { return }
        if kind == 2 {
            sourceSettle?.cancel()
            commitSource(id: id, kind: kind, source: source)
            return
        }
        writeSource(id: id, kind: kind, source: source)
        if captureSlot != nil && pendingTarget != nil {
            let item = DispatchWorkItem {
                guard let id = gSettings.captureButtonID, let slot = gSettings.captureSlot, let target = gSettings.pendingTarget else { return }
                gSettings.finishTarget(id: id, slot: slot, code: target)
            }
            sourceSettle = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
            return
        }
        if captureSlot != nil {
            keyCaptureNote = "已认出\(RemoteCatalog.title(for: id))。按键盘上要映射成的键"
            saveKeys()
            return
        }
        captureButtonID = nil
        keyMapEnabled = true
        keyCaptureNote = "已认出\(RemoteCatalog.title(for: id))。点单击、双击或长按，再按键盘上的键"
        saveKeys()
    }

    private func commitSource(id: String, kind: Int, source: Int) {
        writeSource(id: id, kind: kind, source: source)
        if let slot = captureSlot, let target = pendingTarget {
            finishTarget(id: id, slot: slot, code: target)
            return
        }
        if captureSlot != nil {
            keyCaptureNote = "已认出\(RemoteCatalog.title(for: id))。按键盘上要映射成的键"
            saveKeys()
            return
        }
        captureButtonID = nil
        keyMapEnabled = true
        keyCaptureNote = "已认出\(RemoteCatalog.title(for: id))。点单击、双击或长按，再按键盘上的键"
        saveKeys()
    }

    func setGesture(id: String, slot: Int, target: Int?) {
        bindKnownSource(id)
        let slotName = slot == 0 ? "单击" : (slot == 1 ? "双击" : "长按")
        let btnName = RemoteCatalog.title(for: id)
        if let target = target {
            let targetName = KeyCatalog.targetName(target)
            lastSuccessNote = "「\(btnName)」[\(slotName)] 已映射为 ➔【\(targetName)】"
            lastSuccessTime = CFAbsoluteTimeGetCurrent()
            keyCaptureNote = "\(btnName) 已映射成 \(targetName)"
        } else {
            lastSuccessNote = "「\(btnName)」[\(slotName)] 已恢复默认"
            lastSuccessTime = CFAbsoluteTimeGetCurrent()
            keyCaptureNote = "\(btnName) [\(slotName)] 已恢复默认"
        }
        guard let index = buttonMaps.firstIndex(where: { $0.id == id }) else {
            if let target = target, let def = RemoteCatalog.defaultSources[id] {
                var newMap = ButtonMap(id: id, kind: def.kind, source: def.source, single: nil, doubleTap: nil, hold: nil)
                switch slot {
                case 1: newMap.doubleTap = target
                case 2: newMap.hold = target
                default: newMap.single = target
                }
                buttonMaps.append(newMap)
                keyMapEnabled = true
                saveKeys()
            }
            return
        }
        if target != nil { keyMapEnabled = true }
        switch slot {
        case 1: buttonMaps[index].doubleTap = target
        case 2: buttonMaps[index].hold = target
        default: buttonMaps[index].single = target
        }
        if buttonMaps[index].single == nil && buttonMaps[index].doubleTap == nil && buttonMaps[index].hold == nil {
            buttonMaps.remove(at: index)
        }
        saveKeys()
    }

    private func bindKnownSource(_ id: String) {
        guard buttonMap(id)?.source == nil else { return }
        if let def = RemoteCatalog.defaultSources[id] {
            writeSource(id: id, kind: def.kind, source: def.source)
        }
    }

    private func writeSource(id: String, kind: Int, source: Int) {
        buttonMaps.removeAll { $0.id != id && $0.kind == kind && $0.source == source }
        if let index = buttonMaps.firstIndex(where: { $0.id == id }) {
            buttonMaps[index].kind = kind
            buttonMaps[index].source = source
        } else {
            buttonMaps.append(ButtonMap(id: id, kind: kind, source: source, single: nil, doubleTap: nil, hold: nil))
        }
    }

    func finishTarget(id: String, slot: Int, code: Int) {
        lastBoundID = id
        lastBoundAt = CFAbsoluteTimeGetCurrent()
        let slotName = slot == 0 ? "单击" : (slot == 1 ? "双击" : "长按")
        let btnName = RemoteCatalog.title(for: id)
        let targetName = KeyCatalog.targetName(code)

        captureButtonID = nil
        captureSlot = nil
        pendingTarget = nil
        keyMapEnabled = true
        setGesture(id: id, slot: slot, target: code)
        lastSuccessNote = "「\(btnName)」[\(slotName)] 已成功映射为 ➔【\(targetName)】"
        lastSuccessTime = CFAbsoluteTimeGetCurrent()
        keyCaptureNote = "\(btnName) 已映射成 \(targetName)"
    }

    private func saveKeys() {
        let defaults = UserDefaults.standard
        defaults.set(keyMapEnabled, forKey: "t1.keyMapEnabled")
        if let data = try? JSONEncoder().encode(buttonMaps) {
            defaults.set(data, forKey: "t1.buttonMaps")
        }
        syncKeyRuntime()
    }
}

let gSettings = T1Settings()

// ============================================================
// MARK: - 绳子拖拽平滑物理引擎 (Photoshop Pulled String 核心算法)
// ============================================================
final class PulledStringCore {
    private var stringX: Double = 0.0
    private var stringY: Double = 0.0
    private var velX: Double = 0.0
    private var velY: Double = 0.0
    private var clickFreezeCount: Int = 0

    func notifyClick() {
        clickFreezeCount = 5
    }

    func resetMotion() {
        stringX = 0
        stringY = 0
        velX = 0
        velY = 0
    }

    func process(rawDx: Double, rawDy: Double) -> (dx: Double, dy: Double) {
        gSettings.totalFrames += 1

        guard gSettings.isEngineEnabled && gSettings.ropeLength > 0.01 else {
            return (rawDx * gSettings.scaleX, rawDy * gSettings.scaleY)
        }

        var dx = rawDx
        var dy = rawDy

        // 1. 右手微倾角校正 (-8° 旋转摆正)
        if gSettings.rightHandMode && abs(gSettings.tiltAngle) > 0.001 {
            let rad = gSettings.tiltAngle * .pi / 180.0
            let cosT = cos(rad)
            let sinT = sin(rad)
            let rx = dx * cosT - dy * sinT
            let ry = dx * sinT + dy * cosT
            dx = rx
            dy = ry
        }

        // 2. 右手向右活动受限补偿 (+15%)
        if gSettings.rightHandMode && dx > 0 {
            dx *= gSettings.rightBias
        }

        // 3. 灵敏度倍率
        dx *= gSettings.scaleX
        dy *= gSettings.scaleY

        // 4. 点击瞬间防下沉抖动
        if clickFreezeCount > 0 {
            clickFreezeCount -= 1
            gSettings.absorbedFrames += 1
            return (0, 0)
        }

        // 5. 绳子物理模型。自适应看这一帧的速度，不看绳子里已经积着的长度，
        // 否则日常移动也会被当成快速扫动，几档预设的跟手率会被拉成同一个数。
        let frameSpeed = hypot(dx, dy)
        stringX += dx
        stringY += dy

        let dist = hypot(stringX, stringY)
        let ropeLen = gSettings.ropeLength

        var currentRope = ropeLen
        if gSettings.adaptiveRope {
            // 快速扫动时绳长迅速收窄，给大手部动作零阻滞通行；慢速微动时保留完整防抖死区
            let speedRatio = min(frameSpeed / 20.0, 1.0)
            currentRope = max(0.5, ropeLen * (1.0 - speedRatio * 0.85))
        }

        // 绳子松弛状态：手在微抖或停顿，光标绝对静止停死，彻底消除残余滑行与漂浮感！
        if dist <= currentRope {
            gSettings.absorbedFrames += 1
            velX = 0
            velY = 0
            return (0, 0)
        }

        // 绳子绷紧牵引状态
        let excess = dist - currentRope
        let pullUnitX = stringX / dist
        let pullUnitY = stringY / dist

        var rate = gSettings.followRate
        if gSettings.adaptiveRope {
            // 快速移动时跟手率直达 1.0（100% 原生跟手，零滞后、零吃距离）
            let fastRatio = min(frameSpeed / 20.0, 1.0)
            rate = min(1.0, rate + (1.0 - rate) * pow(fastRatio, 1.2))
        }

        let stepX = pullUnitX * excess * rate
        let stepY = pullUnitY * excess * rate

        // 核心向量保留：实际位移多少，绳子相对向量相应缩减，严禁直接丢弃剩余距离
        stringX -= stepX
        stringY -= stepY

        // 安全限位：防止数值长期漂移积累
        let remainingDist = hypot(stringX, stringY)
        if remainingDist > currentRope * 1.5 {
            let clampUnitX = stringX / remainingDist
            let clampUnitY = stringY / remainingDist
            stringX = clampUnitX * currentRope
            stringY = clampUnitY * currentRope
        }

        return (stepX, stepY)
    }
}

let gCore = PulledStringCore()

// ============================================================
// MARK: - 全局硬件捕获与分发管线 (仅且只拦截鼠标动作，不碰键盘)
// ============================================================
var gT1SenderIDs = Set<UInt64>()
var gNonT1SenderIDs = Set<UInt64>()
var gVirtualPos: CGPoint? = nil
var gTapRef: CFMachPort? = nil
var gKeyTapRef: CFMachPort? = nil
struct RuntimeGesture {
    var single: UInt16?
    var doubleTap: UInt16?
    var hold: UInt16?
    var owns: Bool { single != nil || doubleTap != nil || hold != nil }
}

struct PressTrack {
    var downs: Int
    var longFired: Bool
    var longItem: DispatchWorkItem?
    var singleItem: DispatchWorkItem?
}

var gGestures: [UInt64: RuntimeGesture] = [:]
var gPress: [UInt64: PressTrack] = [:]
var gKeyMapEnabled = false
var gCapturing = false
var gCaptureSlot: Int? = nil
var gSwallowUp: UInt64? = nil
let gEventMarker: Int64 = 0x54310001

func syncKeyRuntime() {
    gKeyMapEnabled = gSettings.keyMapEnabled
    gCapturing = gSettings.captureButtonID != nil
    gCaptureSlot = gSettings.captureSlot
    var next: [UInt64: RuntimeGesture] = [:]
    for item in gSettings.buttonMaps {
        guard let kind = item.kind, let source = item.source else { continue }
        let token = (UInt64(kind) << 32) | UInt64(UInt32(truncatingIfNeeded: source))
        var singleCode = gestureCode(item.single)
        // 若用户仅配置了双击或长按，单击未显式修改时，自动保留物理按键的原生动作
        if singleCode == nil && (item.doubleTap != nil || item.hold != nil) {
            if kind == 0 {
                singleCode = UInt16(truncatingIfNeeded: source)
            } else if kind == 1 {
                singleCode = UInt16(2000 + source)
            } else if kind == 2 {
                singleCode = UInt16(truncatingIfNeeded: source)
            }
        }
        next[token] = RuntimeGesture(
            single: singleCode,
            doubleTap: gestureCode(item.doubleTap),
            hold: gestureCode(item.hold)
        )
    }
    gGestures = next
}

func gestureCode(_ value: Int?) -> UInt16? {
    guard let value = value, value >= 0 else { return nil }
    return UInt16(truncatingIfNeeded: value)
}

func refreshHardwareIDs() {
    var newIDs = Set<UInt64>()
    var iterator: io_iterator_t = 0
    let matchDict = IOServiceMatching("IOService")
    if IOServiceGetMatchingServices(kIOMasterPortDefault, matchDict, &iterator) == kIOReturnSuccess {
        var service: io_object_t = IOIteratorNext(iterator)
        while service != 0 {
            if registryChainMatchesT1(service) {
                var entryID: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(service, &entryID)
                if entryID != 0 { newIDs.insert(entryID) }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
    }
    if !newIDs.isEmpty {
        gT1SenderIDs.formUnion(newIDs)
        gNonT1SenderIDs.subtract(newIDs)
    }

    let connected = !newIDs.isEmpty || !gT1SenderIDs.isEmpty
    DispatchQueue.main.async {
        gSettings.isConnected = connected
    }
}

func isT1Sender(_ sender: UInt64) -> Bool {
    if sender == 0 { return false }
    if gT1SenderIDs.contains(sender) { return true }
    if gNonT1SenderIDs.contains(sender) { return false }
    
    if checkSenderIDIsT1(sender) {
        gT1SenderIDs.insert(sender)
        gNonT1SenderIDs.remove(sender)
        DispatchQueue.main.async { gSettings.isConnected = true }
        return true
    } else {
        gNonT1SenderIDs.insert(sender)
        return false
    }
}

func checkSenderIDIsT1(_ entryID: UInt64) -> Bool {
    let service = IORegistryEntryIDMatching(entryID)
    let entry = IOServiceGetMatchingService(kIOMasterPortDefault, service)
    if entry != 0 {
        defer { IOObjectRelease(entry) }
        return registryChainMatchesT1(entry)
    }
    return false
}

func registryString(_ entry: io_registry_entry_t, _ key: String) -> String {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? ""
}

func registryInt(_ entry: io_registry_entry_t, _ key: String) -> Int? {
    guard let raw = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
        return nil
    }
    return (raw as? NSNumber)?.intValue
}

func nodeLooksLikeT1(_ entry: io_registry_entry_t) -> Bool {
    let vendor = registryInt(entry, "VendorID") ?? registryInt(entry, "idVendor")
    // 🛡️ 绝对排除 Apple 原生硬件（触控板、Magic Mouse、内置键盘 VendorID 均为 1452）
    if vendor == 1452 { return false }
    let name = registryString(entry, "Product")
    let mfg = registryString(entry, "Manufacturer")
    if name.range(of: "T1", options: .caseInsensitive) != nil { return true }
    if mfg.range(of: "shenzhen", options: .caseInsensitive) != nil { return true }
    let product = registryInt(entry, "ProductID") ?? registryInt(entry, "idProduct")
    return vendor == 25098 && product == 1031
}

func registryChainMatchesT1(_ entry: io_registry_entry_t) -> Bool {
    if nodeLooksLikeT1(entry) { return true }
    var current = entry
    var depth = 0
    while depth < 5 {
        var parent: io_registry_entry_t = 0
        if IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) != kIOReturnSuccess {
            if current != entry { IOObjectRelease(current) }
            return false
        }
        if current != entry { IOObjectRelease(current) }
        if nodeLooksLikeT1(parent) {
            IOObjectRelease(parent)
            return true
        }
        current = parent
        depth += 1
    }
    if current != entry { IOObjectRelease(current) }
    return false
}

func eventDelta(_ event: CGEvent, _ ioEvent: AnyObject? = nil) -> (Double, Double) {
    if let io = ioEvent {
        let x = IOHIDEventGetDoubleValue(io, kIOHIDEventFieldPointerX)
        let y = IOHIDEventGetDoubleValue(io, kIOHIDEventFieldPointerY)
        if x != 0 || y != 0 {
            return (x, y)
        }
        let ix = Double(IOHIDEventGetIntegerValue(io, kIOHIDEventFieldPointerX))
        let iy = Double(IOHIDEventGetIntegerValue(io, kIOHIDEventFieldPointerY))
        if ix != 0 || iy != 0 {
            return (ix, iy)
        }
    }
    let dx = event.getDoubleValueField(.mouseEventDeltaX)
    let dy = event.getDoubleValueField(.mouseEventDeltaY)
    let ix = Double(event.getIntegerValueField(.mouseEventDeltaX))
    let iy = Double(event.getIntegerValueField(.mouseEventDeltaY))
    return (abs(dx) >= abs(ix) ? dx : ix, abs(dy) >= abs(iy) ? dy : iy)
}

func isPointerMove(_ type: CGEventType) -> Bool {
    type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged
}

func isMouseButton(_ type: CGEventType) -> Bool {
    mouseButtonCode(type) != nil
}

func mouseButtonCode(_ type: CGEventType) -> Int? {
    switch type {
    case .leftMouseDown, .leftMouseUp: return 1001
    case .rightMouseDown, .rightMouseUp: return 1002
    case .otherMouseDown, .otherMouseUp: return 1003
    default: return nil
    }
}

func isMouseDown(_ type: CGEventType) -> Bool {
    type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
}

func clampToScreens(_ point: CGPoint) -> CGPoint {
    var displayCount: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
        return point
    }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
    guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
        return point
    }
    for d in displays {
        let bounds = CGDisplayBounds(d)
        if bounds.contains(point) {
            return point
        }
    }
    var unionRect = CGDisplayBounds(displays[0])
    for d in displays.dropFirst() {
        unionRect = unionRect.union(CGDisplayBounds(d))
    }
    return CGPoint(
        x: max(unionRect.minX, min(unionRect.maxX - 1, point.x)),
        y: max(unionRect.minY, min(unionRect.maxY - 1, point.y))
    )
}

func clearPointerDelta(_ event: CGEvent) {
    event.setDoubleValueField(.mouseEventDeltaX, value: 0)
    event.setDoubleValueField(.mouseEventDeltaY, value: 0)
    event.setIntegerValueField(.mouseEventDeltaX, value: 0)
    event.setIntegerValueField(.mouseEventDeltaY, value: 0)
}

func hardwareFilteredCallback(
    proxy:  CGEventTapProxy,
    type:   CGEventType,
    event:  CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // 拦截器自愈恢复
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = gTapRef { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passRetained(event)
    }

    var senderID: UInt64 = 0
    var ioEvent: AnyObject? = nil
    if let unmanagedIO = CGEventCopyIOHIDEvent(event) {
        let io = unmanagedIO.takeRetainedValue()
        senderID = IOHIDEventGetSenderID(io)
        ioEvent = io
    }

    let isFromT1 = isT1Sender(senderID)

    // ────────────────────────────────────────────────────────
    // 🛡️ 严格硬件隔离：任何非 T1 硬件事件（MacBook 触控板、文本拖拽、外接鼠标、系统合成事件）
    // 100% 原生纯净直通放行，绝对不修改任何坐标、不拦截、不清零 Delta！
    // ────────────────────────────────────────────────────────
    if !isFromT1 {
        if senderID != 0 {
            gVirtualPos = nil
            gCore.resetMotion()
        }
        return Unmanaged.passRetained(event)
    }

    // ────────────────────────────────────────────────────────
    // 下面的逻辑【仅且只对 T1 遥控器硬件】生效：
    // ────────────────────────────────────────────────────────

    // 1. T1 鼠标按键（如 OK 键发出鼠标左键，返回键发出鼠标右键）
    if isMouseButton(type), let code = mouseButtonCode(type) {
        let down = isMouseDown(type)
        if gCapturing {
            if down {
                DispatchQueue.main.async {
                    gSettings.rememberButton(kind: 2, source: code)
                }
            }
            return nil
        }
        if down && gSettings.shouldAdoptMouseSource() {
            DispatchQueue.main.async {
                gSettings.adoptMouseSource(code)
            }
            return nil
        }
        let token = (UInt64(2) << 32) | UInt64(UInt32(truncatingIfNeeded: code))
        if gKeyMapEnabled, let gesture = gGestures[token], gesture.owns {
            _ = dispatchGesture(token: token, isDown: down, isRepeat: false, gesture: gesture)
            return nil
        }
        if down {
            gCore.notifyClick()
        }
        clearPointerDelta(event)
        return Unmanaged.passRetained(event)
    }

    // 2. 飞鼠移动事件
    guard isPointerMove(type) else {
        return Unmanaged.passRetained(event)
    }

    guard gSettings.isEngineEnabled else {
        gVirtualPos = nil
        return Unmanaged.passRetained(event)
    }

    // 🌟 纯物理硬件位移（直接提取自 DriverKit IOHIDEvent，杜绝任何干扰）
    let raw = eventDelta(event, ioEvent)
    let rawDx = raw.0
    let rawDy = raw.1

    let (sdx, sdy) = gCore.process(rawDx: rawDx, rawDy: rawDy)
    if sdx == 0 && sdy == 0 {
        // 微抖死区吸收：手部微颤直接丢弃，彻底消除微抖，绝不让无效位移污染系统坐标
        return nil
    }

    // 锚定于当前屏幕物理光标真实位置，严防开环漂移
    let current = event.location
    let next = clampToScreens(CGPoint(x: current.x + CGFloat(sdx), y: current.y + CGFloat(sdy)))
    gVirtualPos = next

    event.location = next
    event.setDoubleValueField(.mouseEventDeltaX, value: sdx)
    event.setDoubleValueField(.mouseEventDeltaY, value: sdy)
    event.setIntegerValueField(.mouseEventDeltaX, value: Int64(round(sdx)))
    event.setIntegerValueField(.mouseEventDeltaY, value: Int64(round(sdy)))

    return Unmanaged.passRetained(event)
}

struct T1KeyID {
    var kind: Int
    var code: Int
    var isDown: Bool
    var isRepeat: Bool
    var token: UInt64 {
        (UInt64(kind) << 32) | UInt64(UInt32(truncatingIfNeeded: code))
    }
}

func eventSenderID(_ event: CGEvent) -> UInt64 {
    guard let unmanaged = CGEventCopyIOHIDEvent(event) else { return 0 }
    return IOHIDEventGetSenderID(unmanaged.takeRetainedValue())
}

func identifyKey(_ type: CGEventType, _ event: CGEvent) -> T1KeyID? {
    if type == .keyDown || type == .keyUp || type == .flagsChanged {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .flagsChanged {
            let flags = event.flags.rawValue
            let down: Bool
            switch code {
            case 56, 60: down = (flags & CGEventFlags.maskShift.rawValue) != 0
            case 59, 62: down = (flags & CGEventFlags.maskControl.rawValue) != 0
            case 58, 61: down = (flags & CGEventFlags.maskAlternate.rawValue) != 0
            case 55, 54: down = (flags & CGEventFlags.maskCommand.rawValue) != 0
            case 63: down = (flags & 0x00800000) != 0
            default: return nil
            }
            return T1KeyID(kind: 0, code: code, isDown: down, isRepeat: false)
        }
        return T1KeyID(
            kind: 0,
            code: code,
            isDown: type == .keyDown,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
    }
    guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
        return nil
    }
    let data1 = ns.data1
    let code = Int((data1 & 0xFFFF0000) >> 16)
    let flags = data1 & 0x0000FFFF
    let state = (flags & 0xFF00) >> 8
    guard state == 0xA || state == 0xB else { return nil }
    return T1KeyID(kind: 1, code: code, isDown: state == 0xA, isRepeat: (flags & 0x1) != 0)
}

let gEventSource = CGEventSource(stateID: .hidSystemState)

func postMediaKey(_ key: Int, isDown: Bool) {
    let state: UInt32 = isDown ? 0xA00 : 0xB00
    let flags: UInt32 = state
    let data1 = Int((UInt32(key) << 16) | flags)
    if let ev = NSEvent.otherEvent(
        with: .systemDefined,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        subtype: 8,
        data1: data1,
        data2: -1
    ), let cg = ev.cgEvent {
        cg.setIntegerValueField(.eventSourceUserData, value: gEventMarker)
        cg.post(tap: .cgSessionEventTap)
    }
}

func postMediaAction(_ key: Int) {
    postMediaKey(key, isDown: true)
    usleep(15000)
    postMediaKey(key, isDown: false)
}

func postMappedKey(_ target: UInt16, isDown: Bool, isRepeat: Bool) {
    if target >= 2000 && target <= 2020 {
        if isRepeat { return }
        postMediaKey(Int(target - 2000), isDown: isDown)
        return
    }
    if target == 1001 || target == 1002 {
        if isRepeat { return }
        let button: CGMouseButton = target == 1002 ? .right : .left
        let mouseType: CGEventType
        if target == 1002 {
            mouseType = isDown ? .rightMouseDown : .rightMouseUp
        } else {
            mouseType = isDown ? .leftMouseDown : .leftMouseUp
        }
        let cursor = CGEvent(source: nil)?.location ?? CGPoint.zero
        guard let event = CGEvent(mouseEventSource: gEventSource, mouseType: mouseType, mouseCursorPosition: cursor, mouseButton: button) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: gEventMarker)
        event.post(tap: .cgSessionEventTap)
        return
    }
    guard let event = CGEvent(keyboardEventSource: gEventSource, virtualKey: target, keyDown: isDown) else { return }
    event.setIntegerValueField(.eventSourceUserData, value: gEventMarker)
    if isRepeat {
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
    }
    event.post(tap: .cgSessionEventTap)
}

func postMappedAction(_ target: UInt16) {
    let cursor = CGEvent(source: nil)?.location ?? CGPoint.zero
    if target >= 2000 && target <= 2020 {
        postMediaAction(Int(target - 2000))
        return
    }
    if target == 1001 || target == 1002 {
        let button: CGMouseButton = target == 1002 ? .right : .left
        let downType: CGEventType = target == 1002 ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = target == 1002 ? .rightMouseUp : .leftMouseUp
        guard let down = CGEvent(mouseEventSource: gEventSource, mouseType: downType, mouseCursorPosition: cursor, mouseButton: button),
              let up = CGEvent(mouseEventSource: gEventSource, mouseType: upType, mouseCursorPosition: cursor, mouseButton: button) else { return }
        down.setIntegerValueField(.eventSourceUserData, value: gEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: gEventMarker)
        down.post(tap: .cgSessionEventTap)
        usleep(15000)
        up.post(tap: .cgSessionEventTap)
        return
    }
    guard let down = CGEvent(keyboardEventSource: gEventSource, virtualKey: target, keyDown: true),
          let up = CGEvent(keyboardEventSource: gEventSource, virtualKey: target, keyDown: false) else { return }
    down.setIntegerValueField(.eventSourceUserData, value: gEventMarker)
    up.setIntegerValueField(.eventSourceUserData, value: gEventMarker)
    down.post(tap: .cgSessionEventTap)
    usleep(15000)
    up.post(tap: .cgSessionEventTap)
}

func dispatchGesture(token: UInt64, isDown: Bool, isRepeat: Bool, gesture: RuntimeGesture) -> Bool {
    if gesture.doubleTap == nil && gesture.hold == nil, let single = gesture.single {
        postMappedKey(single, isDown: isDown, isRepeat: isRepeat)
        return true
    }
    if isRepeat { return true }
    if isDown {
        var track = gPress[token] ?? PressTrack(downs: 0, longFired: false, longItem: nil, singleItem: nil)
        track.singleItem?.cancel()
        track.longItem?.cancel()
        track.downs += 1
        if track.downs == 1, let hold = gesture.hold {
            let item = DispatchWorkItem {
                guard var current = gPress[token], !current.longFired else { return }
                current.longFired = true
                current.singleItem?.cancel()
                gPress[token] = current
                postMappedAction(hold)
            }
            track.longItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
        }
        gPress[token] = track
        return true
    }

    guard var track = gPress[token] else { return true }
    track.longItem?.cancel()
    if track.longFired {
        gPress[token] = nil
        return true
    }
    if track.downs >= 2 {
        gPress[token] = nil
        if let target = gesture.doubleTap ?? gesture.single {
            postMappedAction(target)
        }
        return true
    }
    if gesture.doubleTap == nil {
        gPress[token] = nil
        if let singleTarget = gesture.single {
            postMappedAction(singleTarget)
        }
        return true
    }
    let singleTarget = gesture.single
    let item = DispatchWorkItem {
        gPress[token] = nil
        if let singleTarget = singleTarget {
            postMappedAction(singleTarget)
        }
    }
    track.singleItem = item
    gPress[token] = track
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: item)
    return true
}

func keyRemapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = gKeyTapRef { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passRetained(event)
    }
    if event.getIntegerValueField(.eventSourceUserData) == gEventMarker {
        return Unmanaged.passRetained(event)
    }
    guard let id = identifyKey(type, event) else {
        return Unmanaged.passRetained(event)
    }

    let sender = eventSenderID(event)
    let isT1 = isT1Sender(sender)

    // 实时按键回显：让用户在界面实时看到遥控器与键盘输入，并自动联动界面选中对应按键
    if id.isDown && !id.isRepeat {
        let name = KeyCatalog.name(kind: id.kind, code: id.code)
        let sourceTag = isT1 ? "遥控器" : "键盘"
        var matchedID: String? = nil
        if isT1 {
            matchedID = RemoteCatalog.defaultSources.first(where: { $0.value.kind == id.kind && $0.value.source == id.code })?.key
        }
        DispatchQueue.main.async {
            gSettings.reportLastInput("\(sourceTag): \(name)", senderButtonID: matchedID)
        }
    }

    if !isT1 {
        if gCapturing && gCaptureSlot != nil {
            if id.isDown && !id.isRepeat {
                let code = id.code
                DispatchQueue.main.async {
                    if id.kind == 0 && code == 53 {
                        gSettings.cancelCapture()
                    } else if id.kind == 0 {
                        gSettings.rememberKeyboardTarget(code)
                    } else if id.kind == 1 {
                        gSettings.rememberKeyboardTarget(2000 + code)
                    }
                }
            }
            return nil
        }
        return Unmanaged.passRetained(event)
    }

    if gCapturing && id.isDown && !id.isRepeat {
        gSwallowUp = id.token
        let kind = id.kind
        let code = id.code
        DispatchQueue.main.async {
            gSettings.capturePress(kind: kind, code: code)
        }
        return nil
    }
    if gSwallowUp == id.token && !id.isDown {
        gSwallowUp = nil
        return nil
    }

    guard gKeyMapEnabled, let gesture = gGestures[id.token], gesture.owns else {
        return Unmanaged.passRetained(event)
    }

    _ = dispatchGesture(token: id.token, isDown: id.isDown, isRepeat: id.isRepeat, gesture: gesture)
    return nil
}

// ============================================================
// MARK: - 面板视觉（平面、单强调色、跟随系统浅色与深色）
// ============================================================
enum T1Palette {
    static let canvas = dynamic(light: rgb(0.965, 0.965, 0.957), dark: rgb(0, 0, 0))
    static let surface = dynamic(light: rgb(1, 1, 1), dark: rgb(0.094, 0.094, 0.094))
    static let surfaceRaised = dynamic(light: rgb(0.945, 0.945, 0.937), dark: rgb(0.122, 0.122, 0.122))
    static let ink = dynamic(light: rgb(0.094, 0.094, 0.094), dark: rgb(0.96, 0.96, 0.96))
    static let inkInverse = dynamic(light: rgb(0.97, 0.97, 0.97), dark: rgb(0.07, 0.07, 0.07))
    static let muted = dynamic(light: rgb(0.38, 0.38, 0.36), dark: rgb(0.62, 0.62, 0.60))
    static let line = dynamic(light: rgb(0.90, 0.90, 0.88), dark: rgb(0.192, 0.192, 0.192))
    static let accent = dynamic(light: rgb(0.180, 0.361, 0.420), dark: rgb(0.549, 0.722, 0.761))
    static let fillInverse = dynamic(light: rgb(0.094, 0.094, 0.094), dark: rgb(0.93, 0.93, 0.91))

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }))
    }
}

struct ControlPanelView: View {
    @ObservedObject var s = gSettings
    @State private var page: Int
    @State private var side: Int

    init(initialSide: Int = 0) {
        _page = State(initialValue: 1)
        _side = State(initialValue: initialSide)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if s.needsAccessibility {
                permissionBanner
                Hairline()
            }
            GeometryReader { geo in
                if page == 0 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            masterCard
                            presetSection
                            HStack(alignment: .top, spacing: 16) {
                                feelSection
                                    .frame(width: columnWidth(in: geo.size.width), alignment: .top)
                                VStack(alignment: .leading, spacing: 24) {
                                    pointerSection
                                    gripSection
                                }
                                .frame(width: columnWidth(in: geo.size.width), alignment: .top)
                            }
                        }
                        .padding(24)
                        .frame(width: geo.size.width, alignment: .topLeading)
                    }
                } else {
                    ScrollView {
                        keyMapPage
                            .padding(24)
                            .frame(width: geo.size.width, alignment: .topLeading)
                    }
                }
            }
            Hairline()
            footer
        }
        .background(T1Palette.canvas)
        .frame(minWidth: 920, minHeight: 680)
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            s.publishStats()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("T1")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(T1Palette.ink)
                Text(page == 0 ? "飞鼠平滑" : "按键映射")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(T1Palette.muted)
            }
            HStack(spacing: 0) {
                pageTab("手感", index: 0)
                pageTab("按键", index: 1)
            }
            .background(T1Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(T1Palette.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Circle()
                    .fill(s.isReceiving ? T1Palette.accent : T1Palette.line)
                    .frame(width: 8, height: 8)
                Text(s.isReceiving ? "接收中" : "等待移动")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(T1Palette.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(T1Palette.surface))
            .overlay(Capsule().stroke(T1Palette.line, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(s.isReceiving ? "正在接收飞鼠移动" : "等待飞鼠移动")

            Button(action: refreshHardwareIDs) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(T1Palette.ink)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .background(RoundedRectangle(cornerRadius: 8).fill(T1Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(T1Palette.line, lineWidth: 1))
            .help("重新扫描硬件")
            .accessibilityLabel("重新扫描硬件")
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, 16)
    }

    private var permissionBanner: some View {
        HStack(spacing: 16) {
            Text("辅助功能权限未就绪。请在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 T1（若已在列表中，请先关闭再重新打开）。")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(T1Palette.ink)
            Spacer(minLength: 16)
            Button("打开设置") { openAccessibilitySettings() }
                .buttonStyle(PlainButtonStyle())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(T1Palette.inkInverse)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(T1Palette.fillInverse))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(T1Palette.surface)
    }

    private var masterCard: some View {
        PanelCard {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("绳子平滑")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(T1Palette.ink)
                    Text(s.isEngineEnabled ? "正在改写这只遥控器的指针" : "指针按系统原样移动")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(T1Palette.muted)
                }
                Spacer(minLength: 16)
                Toggle("绳子平滑", isOn: $s.isEngineEnabled)
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
                    .accentColor(T1Palette.ink)
            }
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("吸收")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(T1Palette.muted)
                    Text(s.absorbedPercent)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundColor(T1Palette.ink)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("帧数")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(T1Palette.muted)
                    Text(frameCount)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundColor(T1Palette.ink)
                }
                Spacer(minLength: 8)
                Button("清零") { s.resetStats() }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(T1Palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(T1Palette.surfaceRaised))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(T1Palette.line, lineWidth: 1))
            }
            MeterBar(ratio: s.absorbedRatio)
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(s.matchingPreset() == nil ? "预设 · 自定义" : "预设")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(T1Settings.Preset.allCases, id: \.self) { preset in
                    PresetCard(preset: preset, selected: s.matchingPreset() == preset) {
                        s.applyPreset(preset)
                    }
                }
            }
        }
    }

    private var feelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("平滑")
            PanelCard {
                ParamSlider(
                    title: "绳长",
                    value: String(format: "%.1f px", s.ropeLength),
                    hint: "这个半径里的微抖不会带动光标",
                    amount: $s.ropeLength,
                    range: 0...12,
                    step: 0.2
                )
                Hairline()
                ParamSlider(
                    title: "跟手",
                    value: String(format: "%.2f", s.followRate),
                    hint: "越小越稳，越大越贴手",
                    amount: $s.followRate,
                    range: 0.05...1.0,
                    step: 0.01
                )
                Hairline()
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("快速收绳")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(T1Palette.ink)
                        Text("大幅挥动时绳子自动变短")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(T1Palette.muted)
                    }
                    Spacer(minLength: 16)
                    Toggle("快速收绳", isOn: $s.adaptiveRope)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                        .accentColor(T1Palette.ink)
                }
            }
        }
    }

    private var pointerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("指针")
            PanelCard {
                ParamSlider(
                    title: "横向",
                    value: String(format: "%.2f×", s.scaleX),
                    hint: "左右摆动的幅度",
                    amount: $s.scaleX,
                    range: 0.5...2.5,
                    step: 0.05
                )
                Hairline()
                ParamSlider(
                    title: "纵向",
                    value: String(format: "%.2f×", s.scaleY),
                    hint: "上下摆动的幅度",
                    amount: $s.scaleY,
                    range: 0.5...2.5,
                    step: 0.05
                )
            }
        }
    }

    private var gripSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("右手")
            PanelCard {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("握持校正")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(T1Palette.ink)
                        Text("补偿手腕内旋和向右扫动")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(T1Palette.muted)
                    }
                    Spacer(minLength: 16)
                    Toggle("握持校正", isOn: $s.rightHandMode)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                        .accentColor(T1Palette.ink)
                }
                if s.rightHandMode {
                    Hairline()
                    ParamSlider(
                        title: "手腕倾角",
                        value: signedDegrees(s.tiltAngle),
                        hint: "把自然内旋的坐标系摆正",
                        amount: $s.tiltAngle,
                        range: -20...20,
                        step: 1
                    )
                    Hairline()
                    ParamSlider(
                        title: "向右补偿",
                        value: String(format: "%.2f×", s.rightBias),
                        hint: "向右扫动时略微加大",
                        amount: $s.rightBias,
                        range: 1.0...1.5,
                        step: 0.05
                    )
                }
            }
        }
    }

    private var keyMapPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                Text("按键映射")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(T1Palette.ink)
                Spacer(minLength: 12)
                HStack(spacing: 0) {
                    pageTab("正面", index: 0, selection: side) { side = 0 }
                    pageTab("背面", index: 1, selection: side) { side = 1 }
                }
                .background(T1Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(T1Palette.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(side == 0 ? "重置正面映射" : "重置背面映射") {
                    if side == 0 {
                        s.clearFrontMappings()
                    } else {
                        s.clearBackMappings()
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(T1Palette.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(T1Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(T1Palette.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contextMenu(ContextMenu(menuItems: {
                    Button("重置正面映射") { s.clearFrontMappings() }
                    Button("重置背面映射") { s.clearBackMappings() }
                    Divider()
                    Button("重置全部映射 (正面+背面)") { s.clearAllMappings() }
                }))

                Toggle("启用", isOn: Binding(
                    get: { s.keyMapEnabled },
                    set: { s.setKeyMapEnabled($0) }
                ))
                .toggleStyle(SwitchToggleStyle())
                .accentColor(T1Palette.ink)
            }
            KeyMappingHUD(side: side)
            Group {
                if side == 0 {
                    MapStage(buttons: RemoteCatalog.front, imageName: "remote-front.png")
                } else {
                    KeyboardBoard()
                }
            }
        }
    }

    private func pageTab(_ title: String, index: Int) -> some View {
        pageTab(title, index: index, selection: page) { page = index }
    }

    private func pageTab(_ title: String, index: Int, selection: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(selection == index ? T1Palette.inkInverse : T1Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selection == index ? T1Palette.fillInverse : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("触控板和键盘保持系统原生")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(T1Palette.muted)
            Spacer(minLength: 16)
            Toggle("在 Dock 中显示", isOn: $s.showInDock)
                .toggleStyle(SwitchToggleStyle())
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(T1Palette.ink)
            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(PlainButtonStyle())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(T1Palette.ink)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(T1Palette.canvas)
    }

    private func columnWidth(in total: CGFloat) -> CGFloat {
        max(0, (total - 48 - 16) / 2)
    }

    private var frameCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: s.displayFrames)) ?? "\(s.displayFrames)"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(T1Palette.muted)
    }

    private func signedDegrees(_ value: Double) -> String {
        let number = String(format: "%.0f°", abs(value))
        if value < -0.01 { return "−" + number }
        if value > 0.01 { return "+" + number }
        return "0°"
    }
}

private struct KeyMappingHUD: View {
    @ObservedObject var s = gSettings
    let side: Int

    private var slotName: String {
        guard let slot = s.captureSlot else { return "单击" }
        switch slot {
        case 1: return "双击"
        case 2: return "长按"
        default: return "单击"
        }
    }

    private var captureButtonTitle: String {
        guard let id = s.captureButtonID else { return "" }
        return RemoteCatalog.title(for: id)
    }

    var body: some View {
        Group {
            if let buttonID = s.captureButtonID, let slot = s.captureSlot {
                // 1. 录制中状态 (高亮强调、动画呼吸指示、快捷预设键)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 10, height: 10)
                        HStack(spacing: 6) {
                            Text("正在录制按键：")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(T1Palette.ink)
                            Text("「\(captureButtonTitle)」")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(T1Palette.ink)
                            Text("➔")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(T1Palette.muted)
                            Text("[\(slotName)] 动作")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(T1Palette.accent)
                        }
                        Spacer()
                        Button(action: { s.cancelCapture() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("取消录制 (Esc)")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(T1Palette.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(T1Palette.surface)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(T1Palette.line, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    HStack(spacing: 8) {
                        Text("请直接按下 Mac 键盘或遥控器任意键，或点击右侧快捷设定：")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(T1Palette.muted)
                        Spacer()
                        HStack(spacing: 6) {
                            quickChip("左键", code: 1001, id: buttonID, slot: slot)
                            quickChip("右键", code: 1002, id: buttonID, slot: slot)
                            quickChip("回车", code: 36, id: buttonID, slot: slot)
                            quickChip("空格", code: 49, id: buttonID, slot: slot)
                            quickChip("音量+", code: 2000, id: buttonID, slot: slot)
                            quickChip("音量−", code: 2001, id: buttonID, slot: slot)
                            quickChip("Esc", code: 53, id: buttonID, slot: slot)
                            quickChip("恢复默认", code: nil, id: buttonID, slot: slot)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(T1Palette.accent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(T1Palette.accent, lineWidth: 1.5)
                )
            } else if let success = s.lastSuccessNote, CFAbsoluteTimeGetCurrent() - s.lastSuccessTime < 4.0 {
                // 2. 映射成功提示 (绿色高亮横幅，持续 4 秒)
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Color.green)
                    Text(success)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(T1Palette.ink)
                    Spacer()
                    Text("✓ 已实时保存生效")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.green.opacity(0.4), lineWidth: 1)
                )
            } else {
                // 3. 常规就绪状态与实时按键监听回显
                HStack(spacing: 10) {
                    Circle()
                        .fill(s.keyMapEnabled ? Color.green : T1Palette.muted)
                        .frame(width: 8, height: 8)
                    Text(s.keyMapEnabled ? "映射已启用" : "映射已关闭（右上角可开启）")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(s.keyMapEnabled ? T1Palette.ink : T1Palette.muted)
                    Text("•")
                        .foregroundColor(T1Palette.muted.opacity(0.5))
                    Text(side == 0 ? "点击下方按键卡片上的「单击 / 双击 / 长按」开始映射" : "点击下方按键卡片开始映射，带蓝色符号键需配合遥控器 Fn 键")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(T1Palette.muted)
                    Spacer()
                    if let lastInput = s.lastInputDisplay, CFAbsoluteTimeGetCurrent() - s.lastInputTime < 3.0 {
                        HStack(spacing: 4) {
                            Text("刚刚按下:")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(T1Palette.muted)
                            Text(lastInput)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(T1Palette.accent)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(T1Palette.surface)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(T1Palette.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(T1Palette.surfaceRaised)
                )
            }
        }
    }

    private func quickChip(_ title: String, code: Int?, id: String, slot: Int) -> some View {
        Button(action: {
            if let code = code {
                s.finishTarget(id: id, slot: slot, code: code)
            } else {
                s.setGesture(id: id, slot: slot, target: nil)
                s.cancelCapture()
            }
        }) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(T1Palette.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(T1Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(T1Palette.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct MapCard: View {
    let button: RemoteButton
    let active: Bool
    var selected: Bool = false
    var width: CGFloat = 240
    @ObservedObject var s = gSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: button.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(active ? T1Palette.accent : T1Palette.ink)
                    .frame(width: 16, height: 16)
                Text(button.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(T1Palette.ink)
                if active {
                    Text("• 录制中")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.orange)
                }
                Spacer(minLength: 4)
            }
            HStack(spacing: 4) {
                gestureSlot("单击", slot: 0)
                gestureSlot("双击", slot: 1)
                gestureSlot("长按", slot: 2)
            }
        }
        .padding(6)
        .frame(width: width, height: 76, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(active ? T1Palette.accent.opacity(0.04) : T1Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(active ? T1Palette.accent : (selected ? T1Palette.fillInverse : T1Palette.line), lineWidth: active ? 2 : (selected ? 1.5 : 1))
        )
    }

    private func gestureValue(_ slot: Int) -> Int? {
        guard let map = s.buttonMap(button.id) else { return nil }
        switch slot {
        case 1: return map.doubleTap
        case 2: return map.hold
        default: return map.single
        }
    }

    private func gestureSlot(_ label: String, slot: Int) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(T1Palette.muted)
            slotControl(slot)
        }
        .frame(maxWidth: .infinity)
    }

    private func shownName(_ slot: Int) -> String {
        if active && s.captureSlot == slot {
            return "● 请按键..."
        }
        if let code = gestureValue(slot) {
            return KeyCatalog.targetName(code)
        }
        if slot == 0 && !button.nativeSingle.isEmpty {
            return button.nativeSingle
        }
        return "未设置"
    }

    private func slotControl(_ slot: Int) -> some View {
        let clearTitle = button.nativeSingle.isEmpty ? "未设置" : "恢复默认"
        let waiting = active && s.captureSlot == slot
        let isCustom = gestureValue(slot) != nil
        return Button(action: { s.armTargetCapture(button.id, slot) }) {
            slotLabel(shownName(slot), waiting: waiting, isCustom: isCustom)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu(ContextMenu(menuItems: {
            Group {
                Button(clearTitle) { s.setGesture(id: button.id, slot: slot, target: nil) }
                Button("鼠标左键") { s.setGesture(id: button.id, slot: slot, target: 1001) }
                Button("鼠标右键") { s.setGesture(id: button.id, slot: slot, target: 1002) }
                Divider()
                Button("回车 (Enter)") { s.setGesture(id: button.id, slot: slot, target: 36) }
                Button("退格 (Backspace)") { s.setGesture(id: button.id, slot: slot, target: 51) }
                Button("空格 (Space)") { s.setGesture(id: button.id, slot: slot, target: 49) }
                Button("Tab") { s.setGesture(id: button.id, slot: slot, target: 48) }
                Button("Esc") { s.setGesture(id: button.id, slot: slot, target: 53) }
            }
            Group {
                Divider()
                Button("上方向 (↑)") { s.setGesture(id: button.id, slot: slot, target: 126) }
                Button("下方向 (↓)") { s.setGesture(id: button.id, slot: slot, target: 125) }
                Button("左方向 (←)") { s.setGesture(id: button.id, slot: slot, target: 123) }
                Button("右方向 (→)") { s.setGesture(id: button.id, slot: slot, target: 124) }
                Button("上翻页 (PgUp)") { s.setGesture(id: button.id, slot: slot, target: 116) }
                Button("下翻页 (PgDn)") { s.setGesture(id: button.id, slot: slot, target: 121) }
            }
            Group {
                Divider()
                Button("音量+ (Sound Up)") { s.setGesture(id: button.id, slot: slot, target: 2000) }
                Button("音量− (Sound Down)") { s.setGesture(id: button.id, slot: slot, target: 2001) }
                Button("静音 (Mute)") { s.setGesture(id: button.id, slot: slot, target: 2007) }
            }
        }))
    }

    private func slotLabel(_ text: String, waiting: Bool, isCustom: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: waiting ? .bold : .medium))
            .foregroundColor(waiting ? Color.white : (text == "未设置" ? T1Palette.muted : (isCustom ? T1Palette.accent : T1Palette.ink)))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(waiting ? T1Palette.accent : (isCustom ? T1Palette.accent.opacity(0.12) : T1Palette.surfaceRaised))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(waiting ? T1Palette.accent : (isCustom ? T1Palette.accent.opacity(0.4) : Color.clear), lineWidth: waiting ? 1.5 : 1)
            )
    }
}

func loadRemoteImage(_ name: String) -> NSImage {
    let file = name as NSString
    if let url = Bundle.main.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension),
       let image = NSImage(contentsOf: url), image.isValid {
        return image
    }
    let beside = URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
        .appendingPathComponent(name)
    if let image = NSImage(contentsOf: beside), image.isValid { return image }
    if let resURL = Bundle.main.resourceURL?.appendingPathComponent(name),
       let image = NSImage(contentsOf: resURL), image.isValid {
        return image
    }
    return NSImage()
}

private struct RemotePhoto: View {
    let name: String
    var height: CGFloat = 468

    var body: some View {
        Image(nsImage: loadRemoteImage(name))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
    }
}

private struct KeyChip: View {
    let button: RemoteButton
    let selected: Bool
    var compact: Bool = false
    let action: () -> Void
    @ObservedObject var s = gSettings

    private var hasCustomMap: Bool {
        guard let m = s.buttonMap(button.id) else { return false }
        return m.single != nil || m.doubleTap != nil || m.hold != nil
    }

    private var singleText: String {
        if let code = s.buttonMap(button.id)?.single {
            return "单击 " + KeyCatalog.targetName(code)
        }
        return "单击 " + button.nativeSingle
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: compact ? 0 : 4) {
                HStack(spacing: 4) {
                    Text(button.title)
                        .font(.system(size: compact ? 11 : 13, weight: .semibold))
                        .foregroundColor(selected ? T1Palette.accent : T1Palette.ink)
                        .lineLimit(1)
                    if hasCustomMap {
                        Circle()
                            .fill(T1Palette.accent)
                            .frame(width: 4, height: 4)
                    }
                    if !compact {
                        Spacer(minLength: 4)
                        fnMark
                    }
                }
                if !compact {
                    Text(singleText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(T1Palette.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, compact ? 4 : 8)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, minHeight: compact ? 26 : 32, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? T1Palette.accent.opacity(0.12) : T1Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? T1Palette.accent : (hasCustomMap ? T1Palette.accent.opacity(0.5) : T1Palette.line), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(button.title + "，" + singleText)
        .contextMenu(ContextMenu(menuItems: {
            Group {
                Button("选中按键: \(button.title)") { s.selectedBackKeyID = button.id }
                Divider()
                Button("恢复默认") {
                    s.setGesture(id: button.id, slot: 0, target: nil)
                    s.setGesture(id: button.id, slot: 1, target: nil)
                    s.setGesture(id: button.id, slot: 2, target: nil)
                }
                Button("单击 ➔ 鼠标左键") { s.setGesture(id: button.id, slot: 0, target: 1001) }
                Button("单击 ➔ 鼠标右键") { s.setGesture(id: button.id, slot: 0, target: 1002) }
            }
            Group {
                Divider()
                Button("单击 ➔ 回车 (Enter)") { s.setGesture(id: button.id, slot: 0, target: 36) }
                Button("单击 ➔ 空格 (Space)") { s.setGesture(id: button.id, slot: 0, target: 49) }
                Button("单击 ➔ 退格 (Backspace)") { s.setGesture(id: button.id, slot: 0, target: 51) }
                Button("单击 ➔ Esc") { s.setGesture(id: button.id, slot: 0, target: 53) }
                Button("单击 ➔ 音量+") { s.setGesture(id: button.id, slot: 0, target: 2000) }
                Button("单击 ➔ 音量−") { s.setGesture(id: button.id, slot: 0, target: 2001) }
            }
        }))
    }

    @ViewBuilder
    private var fnMark: some View {
        if !button.fnLegend.isEmpty {
            Text("Fn " + button.fnLegend)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(T1Palette.accent)
                .lineLimit(1)
        }
    }
}

private struct BackKeyInspectorCard: View {
    let button: RemoteButton
    let active: Bool
    @ObservedObject var s = gSettings

    private func gestureValue(_ slot: Int) -> Int? {
        guard let map = s.buttonMap(button.id) else { return nil }
        switch slot {
        case 1: return map.doubleTap
        case 2: return map.hold
        default: return map.single
        }
    }

    private func shownName(_ slot: Int) -> String {
        if active && s.captureSlot == slot {
            return "● 请按键..."
        }
        if let code = gestureValue(slot) {
            return KeyCatalog.targetName(code)
        }
        if slot == 0 && !button.nativeSingle.isEmpty {
            return button.nativeSingle
        }
        return "未设置"
    }

    private func slotControl(_ slot: Int) -> some View {
        let clearTitle = button.nativeSingle.isEmpty ? "未设置" : "恢复默认"
        let waiting = active && s.captureSlot == slot
        let isCustom = gestureValue(slot) != nil
        return Button(action: { s.armTargetCapture(button.id, slot) }) {
            Text(shownName(slot))
                .font(.system(size: 12, weight: waiting ? .bold : .medium))
                .foregroundColor(waiting ? Color.white : (shownName(slot) == "未设置" ? T1Palette.muted : (isCustom ? T1Palette.accent : T1Palette.ink)))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(waiting ? T1Palette.accent : (isCustom ? T1Palette.accent.opacity(0.12) : T1Palette.surfaceRaised))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(waiting ? T1Palette.accent : (isCustom ? T1Palette.accent.opacity(0.4) : Color.clear), lineWidth: waiting ? 1.5 : 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu(ContextMenu(menuItems: {
            Group {
                Button(clearTitle) { s.setGesture(id: button.id, slot: slot, target: nil) }
                Button("鼠标左键") { s.setGesture(id: button.id, slot: slot, target: 1001) }
                Button("鼠标右键") { s.setGesture(id: button.id, slot: slot, target: 1002) }
                Divider()
                Button("回车 (Enter)") { s.setGesture(id: button.id, slot: slot, target: 36) }
                Button("退格 (Backspace)") { s.setGesture(id: button.id, slot: slot, target: 51) }
                Button("空格 (Space)") { s.setGesture(id: button.id, slot: slot, target: 49) }
                Button("Tab") { s.setGesture(id: button.id, slot: slot, target: 48) }
                Button("Esc") { s.setGesture(id: button.id, slot: slot, target: 53) }
            }
            Group {
                Divider()
                Button("上方向 (↑)") { s.setGesture(id: button.id, slot: slot, target: 126) }
                Button("下方向 (↓)") { s.setGesture(id: button.id, slot: slot, target: 125) }
                Button("左方向 (←)") { s.setGesture(id: button.id, slot: slot, target: 123) }
                Button("右方向 (→)") { s.setGesture(id: button.id, slot: slot, target: 124) }
                Button("上翻页 (PgUp)") { s.setGesture(id: button.id, slot: slot, target: 116) }
                Button("下翻页 (PgDn)") { s.setGesture(id: button.id, slot: slot, target: 121) }
            }
            Group {
                Divider()
                Button("音量+ (Sound Up)") { s.setGesture(id: button.id, slot: slot, target: 2000) }
                Button("音量− (Sound Down)") { s.setGesture(id: button.id, slot: slot, target: 2001) }
                Button("静音 (Mute)") { s.setGesture(id: button.id, slot: slot, target: 2007) }
            }
        }))
    }

    private func gestureSlot(_ label: String, slot: Int) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(T1Palette.muted)
            slotControl(slot)
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(T1Palette.surfaceRaised)
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? T1Palette.accent : T1Palette.line, lineWidth: active ? 1.5 : 1))
                    Text(button.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(T1Palette.ink)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("当前配置按键：【\(button.title)】")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(T1Palette.ink)
                        if !button.fnLegend.isEmpty {
                            Text("Fn组合: \(button.fnLegend)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(T1Palette.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(T1Palette.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        if active {
                            Text("• 录制中")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.orange)
                        }
                    }
                    Text("直接点击下方槽位改键，或在键盘照片上点选任意按键（也可直接在遥控器实体键上按下）")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(T1Palette.muted)
                }

                Spacer()

                Button(action: {
                    s.setGesture(id: button.id, slot: 0, target: nil)
                    s.setGesture(id: button.id, slot: 1, target: nil)
                    s.setGesture(id: button.id, slot: 2, target: nil)
                }) {
                    Text("恢复本键默认")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(T1Palette.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(T1Palette.surface)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(T1Palette.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
            }

            HStack(spacing: 12) {
                gestureSlot("单击动作", slot: 0)
                gestureSlot("双击动作", slot: 1)
                gestureSlot("长按动作", slot: 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(T1Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(active ? T1Palette.accent : T1Palette.line, lineWidth: active ? 1.5 : 1)
        )
    }
}

private struct KeyboardBoard: View {
    @ObservedObject var s = gSettings

    private var photoW: CGFloat { 840 }
    private var photoH: CGFloat { photoW * 230 / 673 }

    // 素材已转成横版：原图上方落到左边，原图右侧落到上边。
    private func landscapeX(_ button: RemoteButton) -> CGFloat { button.anchorY }
    private func landscapeY(_ button: RemoteButton) -> CGFloat { 1 - button.anchorX }

    private var selectedButton: RemoteButton {
        RemoteCatalog.back.first { $0.id == s.selectedBackKeyID } ?? RemoteCatalog.columnCaps[1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. 顶部按键映射控制中枢（直观醒目，点击即可改键）
            BackKeyInspectorCard(button: selectedButton, active: s.captureButtonID == selectedButton.id)

            // 2. 遥控器实物背部键盘高清图（点击/右键任意键帽直接改键）
            ZStack(alignment: .topLeading) {
                RemotePhoto(name: "remote-back.png", height: photoH)
                    .frame(width: photoW, height: photoH)
                GeometryReader { geo in
                    ForEach(RemoteCatalog.back) { button in
                        KeyHotspot(
                            title: button.title,
                            selected: s.selectedBackKeyID == button.id,
                            isCapturing: s.captureButtonID == button.id,
                            hasCustomMap: s.buttonMap(button.id)?.single != nil || s.buttonMap(button.id)?.doubleTap != nil || s.buttonMap(button.id)?.hold != nil,
                            width: 46,
                            height: 34,
                            buttonID: button.id
                        ) {
                            s.selectedBackKeyID = button.id
                        }
                        .position(
                            x: landscapeX(button) * geo.size.width,
                            y: landscapeY(button) * geo.size.height
                        )
                    }
                }
                .frame(width: photoW, height: photoH)
            }
            .frame(width: photoW, height: photoH)

            // 3. 全键盘矩阵 4 行快捷按钮
            VStack(alignment: .leading, spacing: 4) {
                keyRow(RemoteCatalog.columnEsc)
                keyRow(RemoteCatalog.columnCaps)
                keyRow(RemoteCatalog.columnShift)
                keyRow(RemoteCatalog.columnCtrl)
            }
        }
    }

    private func keyRow(_ buttons: [RemoteButton]) -> some View {
        HStack(spacing: 4) {
            ForEach(buttons) { button in
                KeyChip(button: button, selected: s.selectedBackKeyID == button.id, compact: true) {
                    s.selectedBackKeyID = button.id
                }
            }
        }
        .frame(width: photoW, alignment: .leading)
    }
}

private struct KeyHotspot: View {
    let title: String
    let selected: Bool
    var isCapturing: Bool = false
    var hasCustomMap: Bool = false
    var width: CGFloat = 36
    var height: CGFloat = 36
    var buttonID: String? = nil
    let action: () -> Void
    @ObservedObject var s = gSettings

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.001))
                if isCapturing {
                    Circle()
                        .stroke(Color.orange, lineWidth: 2)
                        .background(Circle().fill(Color.orange.opacity(0.20)))
                        .frame(width: min(width, height) * 0.95, height: min(width, height) * 0.95)
                } else if selected {
                    Circle()
                        .stroke(T1Palette.accent, lineWidth: 2)
                        .background(Circle().fill(T1Palette.accent.opacity(0.16)))
                        .frame(width: min(width, height) * 0.78, height: min(width, height) * 0.78)
                }
                Circle()
                    .fill(isCapturing ? Color.orange : (hasCustomMap ? Color.green : T1Palette.accent))
                    .frame(width: (selected || isCapturing) ? 7 : 5, height: (selected || isCapturing) ? 7 : 5)
            }
            .frame(width: width, height: height)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(title)
        .contextMenu(ContextMenu(menuItems: {
            if let id = buttonID {
                Button("选中按键: \(title)") { s.selectedBackKeyID = id }
                Divider()
                Button("恢复默认") {
                    s.setGesture(id: id, slot: 0, target: nil)
                    s.setGesture(id: id, slot: 1, target: nil)
                    s.setGesture(id: id, slot: 2, target: nil)
                }
                Button("单击 ➔ 鼠标左键") { s.setGesture(id: id, slot: 0, target: 1001) }
                Button("单击 ➔ 鼠标右键") { s.setGesture(id: id, slot: 0, target: 1002) }
                Button("单击 ➔ 回车 (Enter)") { s.setGesture(id: id, slot: 0, target: 36) }
                Button("单击 ➔ 空格 (Space)") { s.setGesture(id: id, slot: 0, target: 49) }
                Button("单击 ➔ 退格 (Backspace)") { s.setGesture(id: id, slot: 0, target: 51) }
                Button("单击 ➔ Esc") { s.setGesture(id: id, slot: 0, target: 53) }
            }
        }))
    }
}

private struct MapStage: View {
    let buttons: [RemoteButton]
    let imageName: String
    @State private var selectedID: String? = nil
    @ObservedObject var s = gSettings

    private var cardH: CGFloat { 76 }
    private var gap: CGFloat { 8 }
    private var photoH: CGFloat { 540 }

    private var left: [RemoteButton] { buttons.filter { $0.side == 0 } }
    private var right: [RemoteButton] { buttons.filter { $0.side == 1 } }

    private func stackHeight(_ count: Int) -> CGFloat {
        if count == 0 { return 0 }
        return CGFloat(count) * cardH + CGFloat(count - 1) * gap
    }

    private var stageH: CGFloat {
        max(photoH, stackHeight(left.count), stackHeight(right.count))
    }

    var body: some View {
        GeometryReader { geo in
            arranged(in: geo.size)
        }
        .frame(height: stageH)
    }

    private func centers(count: Int) -> [CGFloat] {
        if count == 0 { return [] }
        let stack = stackHeight(count)
        let top = (stageH - stack) / 2
        var result: [CGFloat] = []
        for index in 0..<count {
            result.append(top + cardH / 2 + CGFloat(index) * (cardH + gap))
        }
        return result
    }

    private func arranged(in size: CGSize) -> some View {
        let photoW = photoH * 225.0 / 662.0
        let cardW = max(200, (size.width - photoW - 32) / 2)
        let photoX = (size.width - photoW) / 2
        let photoY = (stageH - photoH) / 2
        let leftYs = centers(count: left.count)
        let rightYs = centers(count: right.count)
        return ZStack(alignment: .topLeading) {
            RemotePhoto(name: imageName, height: photoH)
                .frame(width: photoW, height: photoH)
                .position(x: photoX + photoW / 2, y: photoY + photoH / 2)
            leads(leftYs: leftYs, rightYs: rightYs, photoX: photoX, photoY: photoY, photoW: photoW, cardW: cardW, width: size.width)
                .frame(width: size.width, height: stageH)
            ForEach(buttons) { button in
                KeyHotspot(
                    title: button.title,
                    selected: selectedID == button.id,
                    isCapturing: s.captureButtonID == button.id,
                    width: 34,
                    height: 34
                ) {
                    selectedID = button.id
                }
                .position(x: photoX + button.anchorX * photoW, y: photoY + button.anchorY * photoH)
            }
            ForEach(Array(left.enumerated()), id: \.element.id) { item in
                MapCard(button: item.element, active: s.captureButtonID == item.element.id, selected: selectedID == item.element.id, width: cardW)
                    .position(x: cardW / 2, y: leftYs[item.offset])
            }
            ForEach(Array(right.enumerated()), id: \.element.id) { item in
                MapCard(button: item.element, active: s.captureButtonID == item.element.id, selected: selectedID == item.element.id, width: cardW)
                    .position(x: size.width - cardW / 2, y: rightYs[item.offset])
            }
        }
        .frame(width: size.width, height: stageH)
    }

    private func leads(leftYs: [CGFloat], rightYs: [CGFloat], photoX: CGFloat, photoY: CGFloat, photoW: CGFloat, cardW: CGFloat, width: CGFloat) -> some View {
        Path { path in
            stroke(path: &path, buttons: left, ys: leftYs, fromX: cardW, photoX: photoX, photoY: photoY, photoW: photoW)
            stroke(path: &path, buttons: right, ys: rightYs, fromX: width - cardW, photoX: photoX, photoY: photoY, photoW: photoW)
        }
        .stroke(T1Palette.line, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
    }

    private func stroke(path: inout Path, buttons: [RemoteButton], ys: [CGFloat], fromX: CGFloat, photoX: CGFloat, photoY: CGFloat, photoW: CGFloat) {
        for index in 0..<buttons.count {
            let button = buttons[index]
            let target = CGPoint(x: photoX + button.anchorX * photoW, y: photoY + button.anchorY * photoH)
            let origin = CGPoint(x: fromX, y: ys[index])
            let gutterX = button.side == 0 ? photoX - 8 : photoX + photoW + 8
            path.move(to: origin)
            path.addLine(to: CGPoint(x: gutterX, y: origin.y))
            path.addLine(to: CGPoint(x: gutterX, y: target.y))
            path.addLine(to: target)
        }
    }

}

private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(T1Palette.line)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

private struct PanelCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(T1Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T1Palette.line, lineWidth: 1))
    }
}

private struct PresetCard: View {
    let preset: T1Settings.Preset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(preset.title)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 8)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .medium))
                            .accessibilityHidden(true)
                    }
                }
                Text(selected ? "选用" : preset.detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(selected ? T1Palette.inkInverse : T1Palette.muted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .foregroundColor(selected ? T1Palette.inkInverse : T1Palette.ink)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? T1Palette.fillInverse : T1Palette.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? T1Palette.fillInverse : T1Palette.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(preset.title)
        .accessibilityValue(selected ? "已选用" : preset.detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ParamSlider: View {
    let title: String
    let valueText: String
    let hint: String
    @Binding var amount: Double
    let range: ClosedRange<Double>
    let step: Double

    init(title: String, value: String, hint: String, amount: Binding<Double>, range: ClosedRange<Double>, step: Double) {
        self.title = title
        self.valueText = value
        self.hint = hint
        self._amount = amount
        self.range = range
        self.step = step
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(T1Palette.ink)
                Spacer(minLength: 12)
                Text(valueText)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(T1Palette.ink)
            }
            Slider(value: $amount, in: range, step: step)
                .accentColor(T1Palette.ink)
                .accessibilityLabel(title)
            Text(hint)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(T1Palette.muted)
        }
    }
}

private struct MeterBar: View {
    let ratio: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(T1Palette.line)
                Capsule()
                    .fill(T1Palette.accent)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, ratio))))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("吸收率")
        .accessibilityValue("\(Int((ratio * 100).rounded()))%")
    }
}

// ============================================================
// MARK: - App 启动与菜单栏集成
// ============================================================
func applyDockPolicy() {
    let policy: NSApplication.ActivationPolicy = gSettings.showInDock ? .regular : .accessory
    NSApp.setActivationPolicy(policy)
    if policy == .regular {
        NSApp.activate(ignoringOtherApps: true)
    }
    (NSApp.delegate as? AppDelegate)?.updateDockMenuItem()
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var dockMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        gSettings.loadKeys()
        applyDockPolicy()

        // 1. 先把面板摆出来，权限未授予时也能看见界面
        let contentView = ControlPanelView()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.title = "T1"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
                : NSColor(srgbRed: 0.965, green: 0.965, blue: 0.957, alpha: 1)
        })
        window.contentMinSize = NSSize(width: 920, height: 680)
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 2. 鼠标平滑和按键映射使用两条拦截，键盘超时不会带走指针
        setupEventTap(promptUser: true)

        // 3. 构建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "scope", accessibilityDescription: "T1") {
                image.isTemplate = true
                button.image = image
            }
            button.title = " T1"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示控制面板", action: #selector(showWindow), keyEquivalent: "o"))
        let dockItem = NSMenuItem(title: "在 Dock 中显示", action: #selector(toggleDock), keyEquivalent: "")
        dockItem.state = gSettings.showInDock ? .on : .off
        dockMenuItem = dockItem
        menu.addItem(dockItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 T1 调优", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu

        // 4. 定时 2 秒轮询蓝牙外设连接状态，处理断连重连
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            refreshHardwareIDs()
        }

        // 5. 定时 1 秒静默检测辅助功能授权（静默探测，绝对不弹出授权弹窗）
        // 一旦用户在系统设置勾选，立即自动装载拦截器
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            if gSettings.needsAccessibility {
                self?.setupEventTap(promptUser: false)
            }
        }

        // 6. 本地窗口按键监听：面板处于录制状态时，直接捕获键盘按键并完成绑定，双保险杜绝任何窗口或事件拦截影响
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if gCapturing && gCaptureSlot != nil {
                let code = Int(event.keyCode)
                if code == 53 {
                    gSettings.cancelCapture()
                } else {
                    gSettings.rememberKeyboardTarget(code)
                }
                return nil
            }
            return event
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window.orderOut(nil)
        return false
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleDock() {
        gSettings.showInDock.toggle()
    }

    func updateDockMenuItem() {
        dockMenuItem?.state = gSettings.showInDock ? .on : .off
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    private func setupEventTap(promptUser: Bool = false) {
        let isTrusted: Bool
        if promptUser {
            let axOpts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            isTrusted = AXIsProcessTrustedWithOptions(axOpts)
        } else {
            isTrusted = AXIsProcessTrusted()
        }
        guard isTrusted else {
            gSettings.needsAccessibility = true
            markTap("missing")
            return
        }
        gSettings.needsAccessibility = false

        refreshHardwareIDs()

        // 严格仅拦截鼠标移动和点击防抖，完全不拦截 keyDown / keyUp
        let m1 = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        let m2 = CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
        let m3 = CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)
        let m4 = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let m5 = CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let m6 = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        let m7 = CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
        let m8 = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        let m9 = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        let eventMask: CGEventMask = m1|m2|m3|m4|m5|m6|m7|m8|m9

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hardwareFilteredCallback,
            userInfo: nil
        ) else {
            gSettings.needsAccessibility = true
            markTap("missing")
            return
        }

        gTapRef = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        installKeyTap()
        markTap("armed")
    }

    private func installKeyTap() {
        let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let keyUp = CGEventMask(1 << CGEventType.keyUp.rawValue)
        let flagsChanged = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let systemDefined = CGEventMask(1 << 14)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyDown | keyUp | flagsChanged | systemDefined,
            callback: keyRemapCallback,
            userInfo: nil
        ) else {
            fputs("T1 key tap missing\n", stderr)
            fflush(stderr)
            return
        }
        gKeyTapRef = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

func markTap(_ state: String) {
    try? state.write(to: URL(fileURLWithPath: "/tmp/t1-tap-status.txt"), atomically: true, encoding: .utf8)
    fputs("T1 \(state)\n", stderr)
    fflush(stderr)
}

func openAccessibilitySettings() {
    let candidates = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    ]
    for raw in candidates {
        if let url = URL(string: raw), NSWorkspace.shared.open(url) {
            return
        }
    }
}

// 启动原生应用
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
