import AppKit
import Carbon
import ApplicationServices

struct ZoomMotion {
    var steps = 0
    var enlarged: Bool { steps > 0 }
    private var direction = ""
    private var began = 0.0
    private var last = -Double.infinity
    private var budget = 0.0
    mutating func clearEvidence() { direction = ""; last = -.infinity; budget = 0 }
    static func returnRate(_ r: Reading) -> Double {
        guard r.spectrum.count == r.baseline.count, r.spectrum.count > 7, r.binWidth > 0 else { return 15 }
        let center = r.spectrum.count / 2
        var weighted = 0.0, total = 0.0
        for i in r.spectrum.indices where abs(i-center) >= 3 {
            guard (r.direction == "MOVING AWAY") == (i < center) else { continue }
            let energy = max(0, pow(10,Double(r.spectrum[i])/10)-2*pow(10,Double(r.baseline[i])/10))
            weighted += energy * Double(abs(i-center)) * r.binWidth; total += energy
        }
        guard total > 0, weighted.isFinite else { return 15 }
        return min(45,max(5,weighted/total * 0.15))
    }
    // +3: enlarge, -1: one smaller step, 0: final reset to normal.
    mutating func feed(_ r: Reading, now: Double, reversed: Bool) -> Int? {
        let gap = now-last
        defer { last = now }
        if gap > 0.16 { direction = ""; budget = 0 }
        guard r.snr > 15, r.strength > 0.0003,
              ["APPROACHING","MOVING AWAY"].contains(r.direction) else {
            // Short ambiguous frames must not erase a valid return stroke.
            if now-began > 0.16 { direction = ""; budget = 0 }
            return nil
        }
        let toward = (r.direction == "APPROACHING") != reversed
        if direction != r.direction { direction = r.direction; began = now; budget = 0 }
        if toward {
            guard steps == 0, now-began >= 0.10 else { return nil }
            steps = 3; direction = ""; return 3
        }
        guard steps > 0 else { return nil }
        budget += min(0.06,max(0,gap.isFinite ? gap : 0)) * Self.returnRate(r)
        guard now-began >= 0.025, budget >= 1 else { return nil }
        budget -= 1; steps -= 1
        return steps == 0 ? 0 : -1
    }
}

enum AppZoom {
    private static var addedSteps: [pid_t:Int] = [:]
    static func keys(action:Int,browser:Bool,remaining:Int) -> [CGKeyCode] {
        if action > 0 { return Array(repeating:CGKeyCode(kVK_ANSI_Equal),count:3) }
        if action < 0 { return [CGKeyCode(kVK_ANSI_Minus)] }
        return browser ? [CGKeyCode(kVK_ANSI_0)] : Array(repeating:CGKeyCode(kVK_ANSI_Minus),count:max(0,remaining))
    }
    static var pid: pid_t { NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0 }
    static var frontmost: Bool { AppControlTarget.frontmost }
    static func send(enlarge: Bool) -> Bool { send(action:enlarge ? 3 : 0) }
    static func send(action: Int) -> Bool {
        guard AXIsProcessTrusted(), frontmost else { return false }
        let target = pid
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(target),kAXFocusedUIElementAttribute as CFString,&focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = unsafeBitCast(focused,to:AXUIElement.self)
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element,kAXRoleAttribute as CFString,&role)
        if let role = role as? String, [kAXTextFieldRole,kAXTextAreaRole,kAXComboBoxRole].contains(role) { return false }
        var editable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element,kAXValueAttribute as CFString,&editable) == .success && editable.boolValue { return false }
        let browser=AppControlTarget.browserIDs.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
        let events=keys(action:action,browser:browser,remaining:addedSteps[target] ?? 0)
        for key in events {
            guard frontmost, pid == target else { return false }
            guard let down=CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:true),
                  let up=CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:false) else { return false }
            down.flags = .maskCommand; up.flags = .maskCommand
            down.post(tap:.cghidEventTap); up.post(tap:.cghidEventTap)
            if key == CGKeyCode(kVK_ANSI_Equal) { addedSteps[target,default:0] += 1 }
            else if key == CGKeyCode(kVK_ANSI_Minus) { addedSteps[target] = max(0,(addedSteps[target] ?? 0)-1) }
            else { addedSteps[target] = 0 }
        }
        return true
    }
}

func testZoomMotion() {
    testCheck(AppZoom.keys(action:0,browser:false,remaining:1) == [CGKeyCode(kVK_ANSI_Minus)],"Native final return must undo its last step, not send Command-0")
    testCheck(AppZoom.keys(action:0,browser:false,remaining:3).count == 3,"Stopping native zoom must undo remaining steps")
    testCheck(AppZoom.keys(action:0,browser:true,remaining:1) == [CGKeyCode(kVK_ANSI_0)],"Browsers retain reset-to-100 shortcut")
    testCheck(AppZoom.keys(action:0,browser:false,remaining:0).isEmpty,"No native zoom means no reset keystrokes")
    func sample(_ direction:String, offset:Int) -> Reading {
        var spectrum = [Float](repeating:-100,count:121)
        spectrum[60 + (direction == "APPROACHING" ? offset : -offset)] = -30
        return Reading(spectrum:spectrum,baseline:[Float](repeating:-100,count:121),direction:direction,carrierDB:-20,snr:40,strength:0.004,opposedStrength:0.0004,binWidth:10)
    }
    func trial(_ offset:Int, reversed:Bool=false) -> Double {
        var detector = ZoomMotion(); var actions:[Int] = []; var resetTime = 0.0
        for i in 0..<100 {
            let push = i < 7
            let direction = push != reversed ? "APPROACHING" : "MOVING AWAY"
            if let event = detector.feed(sample(direction,offset:offset),now:Double(i)*0.02,reversed:reversed) {
                actions.append(event); if event == 0 { resetTime = Double(i)*0.02 }
            }
        }
        testCheck(actions == [3,-1,-1,0],"Zoom should step back once per level without re-triggering: \(actions)")
        return resetTime
    }
    let slow = trial(4), fast = trial(30)
    testCheck(fast < slow && fast < 0.32,"Fast immediate pull must reset without the old cooldown")
    _ = trial(30,reversed:true)
    var detector = ZoomMotion()
    for i in 0..<20 {
        var r = sample("APPROACHING",offset:30); r.snr = 0
        testCheck(detector.feed(r,now:Double(i)*0.02,reversed:false) == nil,"Weak signal triggered zoom")
    }
    print("PASS speed-paced zoom return, immediate reversal, opposing energy tolerance and weak-signal rejection")
}
