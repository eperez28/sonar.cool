import SwiftUI

// Immediate Doppler flicks. The sign is radial, so the user can invert the
// screen mapping without providing labeled examples. Never infer finger count.
struct ImmediateWave {
    private var quietSince: Double?
    private var armed = false
    private var started: Double?
    private var lastSample = -Double.infinity
    private var cooldownUntil = 0.0
    private var balanceSum = 0.0
    private var votes = 0
    mutating func feed(_ r: Reading, now: Double) -> String? {
        if now-lastSample > 0.2 { self = ImmediateWave() }
        lastSample = now
        guard !r.direction.contains("Calibrating"), r.snr > 15 else {
            armed = false; quietSince = nil; started = nil; votes = 0; balanceSum = 0; return nil
        }
        guard now >= cooldownUntil else { return nil }
        // Match Analyzer’s minimum reflected-motion strength. Lower-level
        // fluctuations must not become swipes after the analyzer rejects them.
        let moving = r.strength > 0.0003
        if !moving {
            // Separate interrupted candidates without re-arming a completed swipe.
            started = nil; votes = 0; balanceSum = 0
            if quietSince == nil { quietSince = now }
            if now-(quietSince ?? now) >= 0.22 {
                armed = true; started = nil; votes = 0; balanceSum = 0
            }
            return nil
        }
        quietSince = nil
        guard armed else { return nil }
        if started == nil { started = now }
        var balance = 0.0
        if r.waveBands.count == 8 {
            let power = r.waveBands.map { expm1(min(20,max(0,$0))) }
            let away = power.prefix(4).reduce(0,+), toward = power.suffix(4).reduce(0,+)
            balance = (toward-away)/max(1e-9,toward+away)
        } else {
            balance = r.direction == "APPROACHING" ? 1 : r.direction == "MOVING AWAY" ? -1 : 0
        }
        // Use the first coherent lobe of a sweep; the opposite return is ignored.
        if abs(balance) > 0.16 {
            // A sweep's clear lobe must not compete with an earlier opposite twitch.
            if votes > 0 && balance * balanceSum < 0 {
                started = now; votes = 0; balanceSum = 0
            }
            balanceSum += balance; votes += 1
        } else {
            started = now; votes = 0; balanceSum = 0
        }
        let elapsed = now-(started ?? now)
        if elapsed > 0.65 {
            armed = false; started = nil; votes = 0; balanceSum = 0; return nil
        }
        guard elapsed >= 0.04, votes >= 3, abs(balanceSum)/Double(votes) > (1.7 - 1) / (1.7 + 1) else { return nil }
        let event = balanceSum > 0 ? "next" : "previous"
        armed = false; started = nil; votes = 0; balanceSum = 0; cooldownUntil = now+0.65
        return event
    }
}

// Retain the existing integration name; no templates or recording are used.
final class WaveCalibration: ObservableObject {
    @Published var enabled = true
    @Published var live = false
    @Published var message = "Ready · sweep across the keyboard"
    @Published var reversed = UserDefaults.standard.bool(forKey:"galleryWaveReversed") {
        didSet { UserDefaults.standard.set(reversed,forKey:"galleryWaveReversed"); resetInput() }
    }
    var recording: String? { nil }
    private var detector = ImmediateWave()
    func resetInput() { detector = ImmediateWave() }
    func cancel() { resetInput() }
    func clear() { resetInput() }
    func consume(_ r: Reading, now: Double) -> String? {
        guard enabled else { return nil }
        if r.direction.contains("Calibrating") { message = "Settling audio · hold still briefly" }
        else if message.hasPrefix("Settling") { message = "Ready · sweep across the keyboard" }
        guard var event = detector.feed(r,now:now) else { return nil }
        if reversed { event = event == "next" ? "previous" : "next" }
        message = event == "next" ? "→ Next image" : "← Previous image"
        return event
    }
}

struct WaveControls: View {
    @ObservedObject var wave: WaveCalibration
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("Wave to browse").font(.headline)
            Text("Palm down above the keyboard. Sweep sideways, then pause briefly before the next sweep.").font(.callout).foregroundStyle(.secondary)
            Toggle("Reverse directions",isOn:$wave.reversed)
            Text(wave.live ? wave.message : "Press Start gallery. No wave recording needed.").foregroundStyle(.mint)
        }.padding(14).background(.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius:12))
    }
}

func testWaveCalibration() {
    // Before this fix both weak, one-sided noise and an ambiguous 1.67:1
    // energy ratio emitted a swipe despite failing Analyzer's motion rules.
    for (strength,balance) in [(Float(0.00025),0.6),(Float(0.004),0.25)] {
        for sign in [1.0,-1.0] {
            var detector = ImmediateWave()
            for frame in 0..<60 {
                let active = (20..<28).contains(frame)
                var bands = [Double](repeating:0,count:8)
                if active { bands[2] = log1p(1-sign*balance); bands[5] = log1p(1+sign*balance) }
                let reading = Reading(spectrum:[],baseline:[],direction:"Mixed movement",carrierDB:0,snr:40,strength:active ? strength : 0,waveBands:bands)
                testCheck(detector.feed(reading,now:Double(frame)*0.02) == nil,"Swipe accepted weak or ambiguous evidence rejected by Analyzer")
            }
        }
    }

    for sign in [1.0,-1.0] {
        var wave = ImmediateWave(); var events: [String] = []
        for frame in 0..<80 {
            let motion = frame >= 20 && frame < 48
            let first = frame < 33
            let value = first ? sign : -sign
            var bands = [Double](repeating:0,count:8)
            if motion { bands[value > 0 ? 5 : 2] = 2 }
            let reading = Reading(spectrum:[],baseline:[],direction:"Mixed movement",carrierDB:0,snr:40,strength:motion ? 0.004 : 0,waveBands:bands)
            if let event = wave.feed(reading,now:Double(frame)*0.02) { events.append(event) }
        }
        testCheck(events == [sign > 0 ? "next" : "previous"],"Immediate wave / return suppression failed")
    }
    var wave = ImmediateWave()
    for frame in 0..<100 {
        let reading = Reading(spectrum:[],baseline:[],direction:"Mixed movement",carrierDB:0,snr:40,strength:frame > 20 ? 0.004 : 0,waveBands:[1,1,1,1,1,1,1,1])
        testCheck(wave.feed(reading,now:Double(frame)*0.02) == nil,"Symmetric motion guessed a direction")
    }
    // A short pause before returning must not re-arm the opposite stroke.
    // A later deliberate gesture still works after the protected reset interval.
    for sign in [1.0,-1.0] {
        var protected = ImmediateWave(); var fired: [String] = []; var times: [Double] = []
        for frame in 0..<120 {
            let t = Double(frame)*0.02
            let forward = (0.3..<0.44).contains(t) || (1.6..<1.74).contains(t)
            let returning = (0.70..<0.90).contains(t)
            var bands = [Double](repeating:0,count:8)
            if forward { bands[sign > 0 ? 5 : 2] = 2 }
            if returning { bands[sign > 0 ? 2 : 5] = 2 }
            let reading = Reading(spectrum:[],baseline:[],direction:"Mixed movement",carrierDB:0,snr:40,strength:forward || returning ? 0.004 : 0,waveBands:bands)
            if let event = protected.feed(reading,now:t) { fired.append(event); times.append(t) }
        }
        let expected = sign > 0 ? "next" : "previous"
        testCheck(fired == [expected,expected],"Paused return stroke triggered gallery navigation")
        testCheck(times.count == 2 && times[0] <= 0.38,"Protected gallery lost its faster initial response")
    }
    // A faint opposite precursor must not cancel a coherent sweep in either direction.
    for sign in [1.0, -1.0] {
        var detector = ImmediateWave(); var fired: [String] = []
        for frame in 0..<40 {
            let active = (20..<26).contains(frame)
            let balance = frame < 22 ? -sign * 0.18 : sign * 0.32
            var bands = [Double](repeating:0,count:8)
            if active {
                bands[2] = log1p(1-balance)
                bands[5] = log1p(1+balance)
            }
            let r = Reading(spectrum:[],baseline:[],direction:"Mixed movement",carrierDB:0,snr:40,strength:active ? 0.004 : 0,waveBands:bands)
            if let event = detector.feed(r,now:Double(frame)*0.02) { fired.append(event) }
        }
        testCheck(fired == [sign > 0 ? "next" : "previous"],"Opposite precursor cancelled coherent swipe")
    }
    let events = AppSwipe.keyEvents(next:true)
    testCheck(events.count == 2 && events[0].type == .keyDown && events[1].type == .keyUp)
    testCheck(events[0].getIntegerValueField(.keyboardEventKeycode) == 124)
    testCheck(AppSwipe.keyEvents(next:false)[0].getIntegerValueField(.keyboardEventKeycode) == 123)
    print("PASS immediate waves without training, both directions, return suppression, ambiguous motion rejection, Chrome key encoding")
}
