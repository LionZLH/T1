import Cocoa
import CoreGraphics
import IOKit
import IOKit.hid
import Foundation

// ============================================================
// MARK: - 真实底层硬件 SenderID 提取接口 (macOS CoreGraphics Private)
// ============================================================
@_silgen_name("CGEventCopyIOHIDEvent")
func CGEventCopyIOHIDEvent(_ event: CGEvent) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventGetSenderID")
func IOHIDEventGetSenderID(_ event: AnyObject) -> UInt64

// ============================================================
// MARK: - PS 绳子拖拽平滑引擎
// ============================================================
final class PulledStringEngine {

    var ropeLength: Double        // 虚拟绳长 (像素)
    var followRate: Double        // 牵引跟手率
    var adaptiveRope: Bool
    var scaleX: Double
    var scaleY: Double
    var rightHandMode: Bool
    var tiltAngleRad: Double
    var rightBiasGain: Double
    var clickFreezeCount: Int = 0

    private var stringX: Double = 0.0
    private var stringY: Double = 0.0
    private var velX: Double = 0.0
    private var velY: Double = 0.0

    private(set) var totalFrames: Int = 0
    private(set) var absorbedFrames: Int = 0
    private(set) var scrollEventsCount: Int = 0

    init(
        ropeLength: Double = 4.5,
        followRate: Double = 0.22,
        scaleX: Double = 1.0,
        scaleY: Double = 1.25,
        rightHand: Bool = true,
        tiltDegrees: Double = -8.0,
        rightBias: Double = 1.15,
        adaptive: Bool = true
    ) {
        self.ropeLength = ropeLength
        self.followRate = followRate
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rightHandMode = rightHand
        self.tiltAngleRad = tiltDegrees * .pi / 180.0
        self.rightBiasGain = rightBias
        self.adaptiveRope = adaptive
    }

    func notifyClick() {
        clickFreezeCount = 5
    }

    func incrementScroll() {
        scrollEventsCount += 1
    }

    func process(rawDx: Double, rawDy: Double) -> (dx: Double, dy: Double) {
        totalFrames += 1

        var dx = rawDx
        var dy = rawDy

        // 1. 右手自然握姿微倾角校正 (-8° 旋转摆正)
        if rightHandMode && abs(tiltAngleRad) > 0.001 {
            let cosT = cos(tiltAngleRad)
            let sinT = sin(tiltAngleRad)
            let rx = dx * cosT - dy * sinT
            let ry = dx * sinT + dy * cosT
            dx = rx
            dy = ry
        }

        // 2. 右手向右活动受限补偿 (+15% 增益)
        if rightHandMode && dx > 0 {
            dx *= rightBiasGain
        }

        // 3. 灵敏度倍率
        dx *= scaleX
        dy *= scaleY

        // 4. 点击防抖
        if clickFreezeCount > 0 {
            clickFreezeCount -= 1
            absorbedFrames += 1
            velX *= 0.3
            velY *= 0.3
            return (velX, velY)
        }

        // 5. 绳子物理模型
        stringX += dx
        stringY += dy

        let dist = hypot(stringX, stringY)

        var currentRope = ropeLength
        if adaptiveRope {
            let speedRatio = min(dist / 24.0, 1.0)
            currentRope = max(1.5, ropeLength * (1.0 - speedRatio * 0.50))
        }

        if dist <= currentRope {
            absorbedFrames += 1
            velX *= 0.65
            velY *= 0.65
            if abs(velX) < 0.05 { velX = 0 }
            if abs(velY) < 0.05 { velY = 0 }
            return (velX, velY)
        }

        let excess = dist - currentRope
        let pullUnitX = stringX / dist
        let pullUnitY = stringY / dist

        let targetPullX = pullUnitX * excess
        let targetPullY = pullUnitY * excess

        var rate = followRate
        if adaptiveRope {
            let fastRatio = min(dist / 20.0, 1.0)
            rate = followRate + (1.0 - followRate) * pow(fastRatio, 1.3)
        }

        velX += rate * (targetPullX - velX)
        velY += rate * (targetPullY - velY)

        stringX = pullUnitX * currentRope
        stringY = pullUnitY * currentRope

        return (velX, velY)
    }
}

// ============================================================
// MARK: - 全局状态与 T1 硬件 SenderID 动态发现
// ============================================================
var gEngine: PulledStringEngine!
var gSmartScrollEnabled: Bool = true
var gScrollSpeed: Int32 = 5
var gInvertScroll: Bool = false

var gVirtualPos: CGPoint? = nil
var gLastT1EventTime: Date = .distantPast
var gTapRef: CFMachPort? = nil

// T1-Remote 的硬件唯一 SenderID 集合 (动态扫描填充)
var gT1SenderIDs = Set<UInt64>()

func refreshT1SenderIDs() {
    gT1SenderIDs.removeAll()
    var iterator: io_iterator_t = 0
    // 匹配所有 IOService 服务（涵盖 IOHIDUserDevice, IOHIDInterface, AppleUserHIDEventDriver）
    let matchDict = IOServiceMatching("IOService")
    if IOServiceGetMatchingServices(kIOMasterPortDefault, matchDict, &iterator) == kIOReturnSuccess {
        var service: io_object_t = IOIteratorNext(iterator)
        while service != 0 {
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            let name = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? ""
            let mfg = IORegistryEntryCreateCFProperty(service, "Manufacturer" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? ""
            if name.contains("T1") || mfg.contains("shenzhen") {
                gT1SenderIDs.insert(entryID)
                print("🎯 [发现T1硬件] 登记硬件 SenderID: 0x\(String(entryID, radix: 16)) (名称: \(name))")
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
    }
    // 兼容保底（已知 T1 硬件与驱动全链路 ID）
    gT1SenderIDs.insert(0x10047a50c)
    gT1SenderIDs.insert(0x10047a50e)
    gT1SenderIDs.insert(0x10047a510)
}

func postT1Scroll(direction: Int32) {
    var dir = direction
    if gInvertScroll { dir *= -1 }
    let lines = dir * gScrollSpeed
    // 关键修复：滚轮事件必须精确投递到当前光标所在位置，否则 macOS 会默认投向屏幕左边缘，导致聊天框/子视图无法滚动！
    let targetLoc = gVirtualPos ?? (CGEvent(source: nil)?.location ?? CGPoint(x: 500, y: 500))
    if let scrollEvent = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .line,
        wheelCount: 1,
        wheel1: lines,
        wheel2: 0,
        wheel3: 0
    ) {
        scrollEvent.location = targetLoc
        scrollEvent.post(tap: .cghidEventTap)
        gEngine.incrementScroll()
    }
}

// ============================================================
// MARK: - 精准硬件 SenderID 过滤器 (修复指针变态位移 Bug + 滚轮精准投递)
// ============================================================
func hardwareFilteredCallback(
    proxy:  CGEventTapProxy,
    type:   CGEventType,
    event:  CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // 🛡️ 事件拦截器自愈保护：防止 macOS 在高负载或超时时自动休眠拦截器
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = gTapRef {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    var senderID: UInt64 = 0
    if let unmanagedIO = CGEventCopyIOHIDEvent(event) {
        senderID = IOHIDEventGetSenderID(unmanagedIO.takeRetainedValue())
    }

    let isFromT1 = gT1SenderIDs.contains(senderID)

    // ────────────────────────────────────────────────────────
    // 🛡️ 非 T1 硬件事件安全处理：
    // 关键修复：绝不把系统合成事件（如光标形状切换、Hover事件，senderID==0）
    // 误当作触控板移动而重置坐标！只有真正的物理外设动作才重置！
    // ────────────────────────────────────────────────────────
    if !isFromT1 {
        // 只有非 0 的硬件 SenderID (如真正的 MacBook 触控板 0x100000aXX) 在物理移动时，才重置锚点
        if senderID != 0 && (type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged) {
            gVirtualPos = nil
        }
        return Unmanaged.passRetained(event)
    }

    // ────────────────────────────────────────────────────────
    // 下面的逻辑【仅且只对 T1 遥控器硬件】生效：
    // ────────────────────────────────────────────────────────

    // 1. T1 上下键转滚轮
    if gSmartScrollEnabled && (type == .keyDown || type == .keyUp) {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if keycode == 126 || keycode == 125 {
            if type == .keyDown {
                let dir: Int32 = (keycode == 126) ? 1 : -1
                postT1Scroll(direction: dir)
            }
            return nil
        }
        return Unmanaged.passRetained(event)
    }

    // 2. 点击防抖
    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
        gEngine.notifyClick()
        return Unmanaged.passRetained(event)
    }

    // 3. T1 飞鼠移动事件
    guard type == .mouseMoved ||
          type == .leftMouseDragged ||
          type == .rightMouseDragged
    else {
        return Unmanaged.passRetained(event)
    }

    let now = Date()
    // 坐标锚定：如果虚拟坐标为空，或者停顿超过 0.6 秒，才从当前屏幕物理位置同步
    if gVirtualPos == nil || now.timeIntervalSince(gLastT1EventTime) > 0.6 {
        gVirtualPos = event.location
    }
    gLastT1EventTime = now

    let rawDx = event.getDoubleValueField(.mouseEventDeltaX)
    let rawDy = event.getDoubleValueField(.mouseEventDeltaY)

    let (sdx, sdy) = gEngine.process(rawDx: rawDx, rawDy: rawDy)

    gVirtualPos!.x += CGFloat(sdx)
    gVirtualPos!.y += CGFloat(sdy)

    if let screen = NSScreen.main {
        let f = screen.frame
        gVirtualPos!.x = max(0, min(f.width - 1, gVirtualPos!.x))
        gVirtualPos!.y = max(0, min(f.height - 1, gVirtualPos!.y))
    }

    event.location = gVirtualPos!
    
    // 关键同步：仅对 T1 调用 CGWarpMouseCursorPosition 固化坐标！
    // 确保 WindowServer 内部坐标与 gVirtualPos 永远 100% 同步！
    // 这样当光标变成文本 I-Beam、小手或十字时，WindowServer 的热点不会产生任何跳跃！
    CGWarpMouseCursorPosition(gVirtualPos!)

    event.setDoubleValueField(.mouseEventDeltaX, value: sdx)
    event.setDoubleValueField(.mouseEventDeltaY, value: sdy)

    return Unmanaged.passRetained(event)
}

// ============================================================
// MARK: - 主入口
// ============================================================
var ropeLen = 4.5
var followRate = 0.22
var scaleGlobal = 1.0
var scaleX = 1.0
var scaleY = 1.25
var rightHand = true
var tiltAngle = -8.0
var rightBias = 1.15

var idx = 1
while idx < CommandLine.arguments.count {
    let arg = CommandLine.arguments[idx]
    switch arg {
    case "-r", "--rope":
        idx += 1
        if idx < CommandLine.arguments.count { ropeLen = Double(CommandLine.arguments[idx]) ?? ropeLen }
    case "-f", "--follow":
        idx += 1
        if idx < CommandLine.arguments.count { followRate = Double(CommandLine.arguments[idx]) ?? followRate }
    case "--scale":
        idx += 1
        if idx < CommandLine.arguments.count { scaleGlobal = Double(CommandLine.arguments[idx]) ?? 1.0 }
    case "-x":
        idx += 1
        if idx < CommandLine.arguments.count { scaleX = Double(CommandLine.arguments[idx]) ?? scaleX }
    case "-y":
        idx += 1
        if idx < CommandLine.arguments.count { scaleY = Double(CommandLine.arguments[idx]) ?? scaleY }
    case "--scroll-lines":
        idx += 1
        if idx < CommandLine.arguments.count { gScrollSpeed = Int32(CommandLine.arguments[idx]) ?? 4 }
    case "--no-scroll":
        gSmartScrollEnabled = false
    case "--invert-scroll":
        gInvertScroll = true
    case "--no-right":
        rightHand = false
    default:
        break
    }
    idx += 1
}

scaleX *= scaleGlobal
scaleY *= scaleGlobal

gEngine = PulledStringEngine(
    ropeLength: ropeLen,
    followRate: followRate,
    scaleX: scaleX,
    scaleY: scaleY,
    rightHand: rightHand,
    tiltDegrees: tiltAngle,
    rightBias: rightBias
)

print("")
print("🚀 T1Smooth v4.3 [光标热点零跳跃 + 纯粹绳子拖拽版]")
print("────────────────────────────────────────────────────────")
print("  跳变修复:   🎯 解决光标变态(文本/小手/箭头)时大范围位移的致命Bug")
print("  硬件隔离:   🔒 严格限定仅 T1 (0x10047a50e) 触发平滑与滚轮")
print("  Mac键盘:    🛡️ 100% 原生正常上下键")
print("  Mac触控板:  🛡️ 100% 原生正常手势")
print("  专属滚轮:   📜 T1 遥控器专属上下键转滚轮 (4 行)")
print("  绳子平滑:   🧶 PS 虚拟绳长 = \(ropeLen)px (悬空微颤彻底消除)")
print("  退出程序:   Ctrl+C\n")

let axOpts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(axOpts) else {
    print("⚠️ 缺少辅助功能权限。"); exit(1)
}

refreshT1SenderIDs()

let m1 = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
let m2 = CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
let m3 = CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)
let m4 = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
let m5 = CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
let m6 = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
let m7 = CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
let m8 = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
let m9 = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
let m10 = CGEventMask(1 << CGEventType.keyDown.rawValue)
let m11 = CGEventMask(1 << CGEventType.keyUp.rawValue)
let eventMask: CGEventMask = m1|m2|m3|m4|m5|m6|m7|m8|m9|m10|m11

guard let tap = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: hardwareFilteredCallback,
    userInfo: nil
) else {
    print("❌ 无法创建事件拦截"); exit(1)
}

gTapRef = tap
let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("🎯 运行中！请移动飞鼠在文本、链接和空白区间划过，测试光标形态切换！")

Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
    let total    = gEngine.totalFrames
    let absorbed = gEngine.absorbedFrames
    let scrolls  = gEngine.scrollEventsCount
    let pct = total > 0 ? String(format: "%.1f", Double(absorbed) / Double(total) * 100.0) : "0.0"
    print("📊 统计: T1 移动 \(total) 帧 (吸收微抖 \(absorbed) 帧, \(pct)%) | T1 滚轮 \(scrolls) 次")
}

RunLoop.main.run()
