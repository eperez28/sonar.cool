import AppKit
import SwiftUI
import AVFoundation
import CoreAudio
import CryptoKit
import UniformTypeIdentifiers

// Aggregate-only setup evidence. Never persists microphone buffers or spectra.
struct SetupMeasurement: Codable {
    var frames = 0
    var carrierSum = 0.0
    var contrastSum = 0.0
    var toward = 0
    var away = 0
    var actions = 0
    var scrollActions = 0
    var swipeActions = 0
    var zoomActions = 0
    var directionChanges = 0
    var peak: Float = 0
    var clipped = 0
    var carrier: Double { frames > 0 ? carrierSum / Double(frames) : -160 }
    var contrast: Double { frames > 0 ? contrastSum / Double(frames) : 0 }
    mutating func record(_ r: Reading, actions: Int, scroll: Int = 0, swipe: Int = 0, zoom: Int = 0, taps: Int = 0) {
        guard r.carrierDB.isFinite, r.snr.isFinite else { return }
        frames += 1; carrierSum += Double(r.carrierDB); contrastSum += Double(r.snr)
        if r.direction == "APPROACHING" { toward += 1 }
        if r.direction == "MOVING AWAY" { away += 1 }
        self.actions += actions
        scrollActions += scroll; swipeActions += swipe; zoomActions += zoom; directionChanges += taps
    }
    mutating func input(_ block: [Float]) {
        for value in block where value.isFinite {
            peak = max(peak,abs(value)); if abs(value) >= 0.999 { clipped += 1 }
        }
    }
}
struct SetupCandidate: Codable {
    var frequency: Double
    var off = SetupMeasurement()
    var still = SetupMeasurement()
    var preparation = SetupMeasurement()
    var movement = SetupMeasurement()
    var stopped = SetupMeasurement()
    var result = "Not completed"
    var inputRate = 0.0
    var outputRate = 0.0
    var audioErrors = 0
    var inputCallbacks = 0
    var outputCallbacks = 0
    var missingOutputBuffers = 0
    // Require quiet detectors as well as a detectable carrier. A louder tone
    // alone must never pass a candidate (Maxwell's 100% report).
    var stable: Bool {
        off.frames >= 40 && still.frames >= 80 && still.contrast >= 20 &&
        still.carrier - off.carrier >= 6 && still.clipped == 0 &&
        still.actions == 0 && still.toward == 0 && still.away == 0 && audioErrors == 0
    }
    var failureReasons: [String] {
        var reasons: [String] = []
        if audioErrors > 0 { reasons.append("The audio connection reported errors.") }
        if off.frames < 40 || still.frames < 80 || preparation.frames < 20 || movement.frames < 80 || stopped.frames < 60 { reasons.append("Not enough microphone readings arrived.") }
        if still.contrast < 20 || still.carrier - off.carrier < 6 { reasons.append("Sonar couldn’t hear its test sound clearly enough.") }
        if [still,preparation,movement,stopped].contains(where: { $0.clipped > 0 }) { reasons.append("The microphone input clipped.") }
        for (name, value) in [("during the sound check",still),("before GO",preparation),("after STOP",stopped)] {
            if value.actions > 0 || value.toward > 0 || value.away > 0 { reasons.append("Sonar detected unwanted gestures \(name).") }
        }
        if movement.toward < 3 || movement.away < 3 || movement.actions == 0 { reasons.append("Sonar didn’t clearly detect both parts of your hand movement.") }
        return reasons
    }
    var verified: Bool {
        stable && preparation.frames >= 20 && preparation.actions == 0 && preparation.toward == 0 && preparation.away == 0 && preparation.clipped == 0 && movement.frames >= 80 && movement.toward >= 3 && movement.away >= 3 &&
        movement.actions > 0 && movement.clipped == 0 &&
        stopped.frames >= 60 && stopped.actions == 0 && stopped.toward == 0 && stopped.away == 0 && stopped.clipped == 0
    }
}
struct SetupProfile: Codable {
    static let key = "sonarDeviceSetup.v1"
    let revision: Int
    let frequency: Double
    let amplitude: Double
    let model: String
    let date: String
    static func load() -> Self? {
        guard let data = UserDefaults.standard.data(forKey:key),
              let value = try? JSONDecoder().decode(Self.self,from:data), value.revision == 1,
              [18000.0,19000,20000].contains(value.frequency), value.amplitude == 0.008,
              value.model == DiagnosticHardware.modelIdentifier() else { return nil }
        return value
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data,forKey:Self.key) } }
}

final class DeviceSetup: ObservableObject {
    enum Stage { case intro, permission, off, calibrating, still, ready, prepare, movement, stopped, failed, passed, saved }
    @Published private(set) var stage = Stage.intro
    @Published private(set) var remaining = 0
    @Published private(set) var detail = "We’ll find a sound setting for your Mac, then ask you to move your hand and stop. Each check takes about 25 seconds."
    @Published private(set) var candidates: [SetupCandidate] = []
    private let frequencies = [20000.0,19000,18000]
    private var index = 0
    @Published private(set) var nextAvailable = false
    private var current = SetupCandidate(frequency:20000)
    private var volume: SpeakerVolume.Snapshot?
    private var engine: HardwareAudio?
    private var timer: Timer?
    private let queue = DispatchQueue(label:"sonar.device-setup")
    private var token = UUID()
    private var phaseStart = 0.0
    private var deadline = 0.0
    private var lastReading = 0.0
    private var scroll = ScrollMotion()
    private var taps = DoublePushDetector()
    private var swipe = ImmediateWave()
    private var zoom = ZoomMotion()
    var active: Bool { [.permission,.off,.calibrating,.still,.ready,.prepare,.movement,.stopped].contains(stage) }
    var cueUp: Bool { ((6 - remaining) / 2) % 2 == 0 }
    var countdown: Int { remaining + (stage == .off ? 7 : stage == .calibrating ? 4 : 0) }
    var canSave: Bool { stage == .passed && current.verified }
    var title: String {
        switch stage {
        case .intro: return "Set up Sonar for your Mac"
        case .permission: return "Allow microphone access"
        case .off,.calibrating,.still: return "1. Check the sound"
        case .ready: return "2. Move your hand"
        case .prepare: return "Get ready — hold still"
        case .movement: return cueUp ? "GO — lift your hand" : "GO — lower your hand"
        case .stopped: return "STOP — hold your hand still"
        case .failed: return detail.hasPrefix("Setup stopped") ? "Setup stopped" : "We couldn’t find reliable settings"
        case .passed: return "Your settings passed the checks"
        case .saved: return "Settings saved"
        }
    }
    deinit { timer?.invalidate(); engine?.stop() }
    private func transition(_ next: Stage, seconds: Double = 0, message: String) {
        stage = next; phaseStart = ProcessInfo.processInfo.systemUptime
        deadline = phaseStart + seconds; remaining = Int(ceil(seconds)); detail = message
        if next == .movement || next == .stopped {
            NSAccessibility.post(element:NSApp.mainWindow as Any,notification:.announcementRequested,
                userInfo:[.announcement:title,.priority:NSAccessibilityPriorityLevel.high.rawValue])
        }
    }
    func start() {
        halt(); candidates = []; nextAvailable = false; index = 0
        UserDefaults.standard.removeObject(forKey:SetupProfile.key)
        current = SetupCandidate(frequency:frequencies[0]); volume = SpeakerVolume.snapshot()
        guard volume?.state == .ready else { fail("Unmute your built-in speakers and raise the volume, then try again."); return }
        transition(.permission,message:"If macOS asks, allow Sonar to use your microphone.")
        let attempt = token
        AVCaptureDevice.requestAccess(for:.audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.token == attempt else { return }
                if granted { self.beginCandidate() }
                else { self.fail("Microphone access is needed. Allow Sonar in System Settings → Privacy & Security → Microphone, then try again.") }
            }
        }
    }
    private func resetDetectors() { scroll = ScrollMotion(); taps = DoublePushDetector(); swipe = ImmediateWave(); zoom = ZoomMotion() }
    private func beginCandidate() {
        current = SetupCandidate(frequency:frequencies[index]); resetDetectors()
        transition(.off,seconds:3,message:"First, rest your hands for 10 seconds while we check the sound. Then you’ll lift and lower your hand.")
        runAudio(amplitude:0)
    }
    private func runAudio(amplitude: Double) {
        halt(); let attempt = token; let frequency = current.frequency
        var analyzer: Analyzer?
        var buffer: [Float] = []
        let audio = HardwareAudio(tone:frequency,amplitude:amplitude) { [weak self] block in
            let received = ProcessInfo.processInfo.systemUptime
            self?.queue.async { [weak self] in
                buffer.append(contentsOf:block)
                var readings: [Reading] = []
                if let analyzer {
                    while buffer.count >= analyzer.n {
                        readings.append(analyzer.analyze(Array(buffer.prefix(analyzer.n))))
                        buffer.removeFirst(analyzer.hop)
                    }
                } else { buffer.removeAll(keepingCapacity:true) }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.token == attempt, self.active else { return }
                    self.receive(readings,block:block,time:received)
                }
            }
        }
        do {
            engine = audio; try audio.start()
            current.inputRate = audio.inputRate; current.outputRate = audio.outputRate
            guard audio.inputRate > 2 * (frequency + 600), audio.outputRate > 2 * frequency else {
                current.audioErrors += 1; fail("This audio connection can’t handle the test sound. Save the report so we can investigate."); return
            }
            let rate = audio.inputRate
            queue.async { analyzer = Analyzer(rate:rate,tone:frequency) }
            lastReading = ProcessInfo.processInfo.systemUptime
            let poll = Timer(timeInterval:0.1,repeats:true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(poll,forMode:.common); timer = poll
        } catch { fail("Sonar couldn’t start the built-in audio. Stop other audio tools and try again.") }
    }
    private func receive(_ readings: [Reading], block: [Float], time: Double) {
        guard time >= phaseStart else { return }
        if !readings.isEmpty { lastReading = ProcessInfo.processInfo.systemUptime }
        if stage == .off { current.off.input(block) }
        if stage == .still { current.still.input(block) }
        if stage == .prepare && time - phaseStart >= 1 { current.preparation.input(block) }
        if stage == .movement { current.movement.input(block) }
        if stage == .stopped { current.stopped.input(block) }
        for r in readings {
            let dt = 2048 / current.inputRate
            var actions = 0
            var scrollCount = 0, swipeCount = 0, zoomCount = 0, tapCount = 0
            scroll.feed(direction:r.direction,strength:r.strength,now:time)
            if taps.feed(direction:r.direction,now:time) { scroll.switchDirection(now:time); actions += 1; tapCount += 1 }
            if abs(scroll.step(dt:dt,now:time)) > 0.01 { actions += 1; scrollCount += 1 }
            if swipe.feed(r,now:time) != nil { actions += 1; swipeCount += 1 }
            if zoom.feed(r,now:time,reversed:false) != nil { actions += 1; zoomCount += 1 }
            switch stage {
            case .off: current.off.record(r,actions:0)
            case .still: if r.calibrationRemaining == nil { current.still.record(r,actions:actions,scroll:scrollCount,swipe:swipeCount,zoom:zoomCount,taps:tapCount) }
            case .prepare: if time - phaseStart >= 1 { current.preparation.record(r,actions:actions,scroll:scrollCount,swipe:swipeCount,zoom:zoomCount,taps:tapCount) }
            case .movement: current.movement.record(r,actions:actions,scroll:scrollCount,swipe:swipeCount,zoom:zoomCount,taps:tapCount)
            case .stopped:
                // Allow one second to react to STOP and let normal momentum end.
                // Keep the same analyzer and detectors: no hidden recalibration.
                if time - phaseStart >= 1 { current.stopped.record(r,actions:actions,scroll:scrollCount,swipe:swipeCount,zoom:zoomCount,taps:tapCount) }
            default: break
            }
        }
    }
    private func tick() {
        guard active else { return }
        guard SpeakerVolume.snapshot() == volume else {
            fail("Your audio settings changed during the check. Leave the volume steady and try again."); return
        }
        if let engine, (try? builtInDevice(scope:kAudioDevicePropertyScopeInput)) != engine.inputDeviceID {
            fail("Your microphone connection changed. Try the check again."); return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastReading < 2 else { fail("Microphone readings stopped arriving. Try again, or save this report for help."); return }
        if stage == .ready { return }
        remaining = max(0,Int(ceil(deadline-now)))
        guard now >= deadline else { return }
        switch stage {
        case .off:
            captureAudio(); transition(.calibrating,seconds:3,message:"Listening to the test sound. Keep still."); runAudio(amplitude:0.008)
        case .calibrating:
            resetDetectors(); transition(.still,seconds:4,message:"Almost ready. Next, you’ll lift and lower your hand above the keyboard.")
        case .still:
            transition(.ready,message:"Now we’ll test your hand. Press I’m ready, place your palm above the keyboard, and wait for GO. Then lift and lower it.")
        case .prepare:
            transition(.movement,seconds:6,message:"Follow the green arrow: lift for ↑, lower for ↓. Stop when the hand turns red.")
        case .movement: transition(.stopped,seconds:5,message:"Keep your hand in place and still. We’re checking that gestures stop too.")
        case .stopped:
            captureAudio()
            if current.verified {
                current.result = "Passed stillness, movement, and stopping"
                transition(.passed,message:"Sonar detected your hand moving and stopping. Save these settings, then try Scroll, Swipe, and Zoom in the app.")
            } else {
                fail(current.failureReasons.joined(separator:" "))
                nextAvailable = index + 1 < frequencies.count
                if !nextAvailable { detail += " Save the report for help, or try again at a different volume." }
            }
            candidates.append(current)
        default: break
        }
    }
    func tryNext() {
        guard nextAvailable else { return }
        nextAvailable = false; index += 1
        beginCandidate()
    }
    func move() {
        guard stage == .ready else { return }
        guard SpeakerVolume.snapshot() == volume else { fail("Your volume changed. Try again with the volume steady."); return }
        resetDetectors()
        transition(.prepare,seconds:3,message:"Put your palm above the keyboard and hold it still. Wait for GO before moving.")
    }
    private func halt() {
        token = UUID(); timer?.invalidate(); timer = nil
        engine?.stop(); engine = nil
    }
    private func captureAudio() {
        guard let audio = engine else { halt(); return }
        audio.stop()
        current.audioErrors += audio.inputErrors
        current.inputCallbacks += audio.inputCallbacks; current.outputCallbacks += audio.outputCallbacks
        current.missingOutputBuffers += audio.missingOutputBuffers
        if audio.outputCallbacks == 0 || audio.missingOutputBuffers > 0 { current.audioErrors += 1 }
        halt()
    }
    func cancel() {
        if active { fail("Setup stopped. No new settings were saved.") } else { halt() }
    }
    private func fail(_ reason: String) {
        nextAvailable = false; captureAudio(); current.result = reason; transition(.failed,message:reason)
    }
    func save(to sonar: Sonar) {
        guard canSave, SpeakerVolume.snapshot() == volume else {
            fail("Your audio settings changed. Run the check again before saving."); return
        }
        let profile = SetupProfile(revision:1,frequency:current.frequency,amplitude:0.008,
            model:DiagnosticHardware.modelIdentifier(),date:ISO8601DateFormatter().string(from:Date()))
        profile.save(); sonar.frequency = profile.frequency; sonar.level = profile.amplitude
        transition(.saved,message:"You’re ready to try Sonar. Recalibrate any time from the sidebar.")
    }
    func saveReport() {
        struct Report: Encodable {
            let schema = 1
            let generatedAt: String
            let model: String
            let chip: String
            let macOS: String
            let version: String
            let build: String
            let executableSHA256: String
            let modelName: String
            let modelYear: String
            let digitalAmplitude = 0.008
            let volume: [Float?]
            let result: String
            let candidates: [SetupCandidate]
            let finalCheck: SetupCandidate
            let limitations = "Aggregate-only local measurements; no audio, device names, serial numbers, or window contents. Detector actions are simulated without controlling apps. This checks basic sensing and stopping, not every gesture or other-app delivery. Thresholds are provisional."
        }
        let value = Report(generatedAt:ISO8601DateFormatter().string(from:Date()),model:DiagnosticHardware.modelIdentifier(),chip:DiagnosticHardware.chip(),
            macOS:ProcessInfo.processInfo.operatingSystemVersionString,version:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development",
            build:Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "development",
            executableSHA256:Bundle.main.executableURL.flatMap { try? Data(contentsOf:$0) }.map { SHA256.hash(data:$0).map { String(format:"%02x",$0) }.joined() } ?? "Unavailable",
            modelName:DiagnosticHardware.names[DiagnosticHardware.modelIdentifier()] ?? "Unknown",
            modelYear:DiagnosticHardware.year(DiagnosticHardware.modelIdentifier()),
            volume:volume?.volumes ?? [],result:detail,candidates:candidates,finalCheck:current)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        guard let data = try? encoder.encode(value), let json = String(data:data,encoding:.utf8) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "Sonar-setup-report.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try "Sonar setup report\n\(detail)\n\nTechnical details\n\(json)".write(to:url,atomically:true,encoding:.utf8) }
        catch { detail = "Couldn’t save the report. Choose another location and try again." }
    }
}

struct DeviceSetupView: View {
    @ObservedObject var sonar: Sonar
    @StateObject private var setup = DeviceSetup()
    let close: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if setup.stage == .movement {
                HStack(spacing:14) {
                    Image(systemName:"arrow.up").foregroundStyle(setup.cueUp ? Color.green : Color.secondary.opacity(0.25))
                    Image(systemName:"arrow.down").foregroundStyle(setup.cueUp ? Color.secondary.opacity(0.25) : Color.green)
                }.font(.system(size:32,weight:.bold))
                    .accessibilityLabel(setup.cueUp ? "Lift your hand" : "Lower your hand")
            } else {
                Image(systemName:setup.stage == .passed || setup.stage == .saved ? "checkmark.circle" : "hand.raised.fill")
                    .font(.system(size:28)).foregroundStyle(setup.stage == .stopped ? Color.red : Color.accentColor)
            }
            Text(setup.title).font(.headline).fixedSize(horizontal:false,vertical:true)
            Text(setup.detail).fixedSize(horizontal:false,vertical:true)
            if setup.active && setup.stage != .ready && setup.stage != .permission {
                Text("\(setup.countdown)s").font(.title.monospacedDigit()).foregroundStyle(.secondary)
            }
            switch setup.stage {
            case .intro,.failed:
                Button(setup.stage == .intro ? "Start setup" : setup.nextAvailable ? "Try next sound setting" : "Try again") { if setup.nextAvailable { setup.tryNext() } else { setup.start() } }.buttonStyle(.borderedProminent)
                if setup.stage == .failed { Button("Save report…") { setup.saveReport() } }
                Button("Later") { close() }
            case .ready:
                Button("I’m ready") { setup.move() }.buttonStyle(.borderedProminent)
                Button("Stop setup") { setup.cancel() }
            case .passed:
                Button("Save settings") { setup.save(to:sonar) }.buttonStyle(.borderedProminent)
                Button("Save report…") { setup.saveReport() }
            case .saved: Button("Done") { close() }.buttonStyle(.borderedProminent)
            default: Button("Stop setup") { setup.cancel() }
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
        .onAppear { sonar.stop(); sonar.diagnosticsOpen = true; sonar.cancelDiagnostics = { setup.cancel() } }
        .onExitCommand { setup.cancel(); close() }
        .onDisappear { setup.cancel(); sonar.cancelDiagnostics = nil; sonar.diagnosticsOpen = false }
    }
}

func testDeviceSetup() {
    var c = SetupCandidate(frequency:20000)
    c.off.frames = 80; c.off.carrierSum = -130 * 80
    c.still.frames = 100; c.still.carrierSum = -90 * 100; c.still.contrastSum = 35 * 100
    precondition(c.stable && !c.verified)
    c.movement.frames = 100; c.movement.toward = 5; c.movement.away = 5; c.movement.actions = 1
    c.preparation.frames = 40
    c.stopped.frames = 80
    precondition(c.verified)
    var failed = c; failed.still.actions = 1; precondition(!failed.stable && !failed.verified)
    failed = c; failed.stopped.away = 1; precondition(!failed.verified)
    failed = c; failed.still.contrastSum = 4 * 100; precondition(!failed.stable)
    failed = c; failed.still.clipped = 1; precondition(!failed.stable)
    failed = c; failed.audioErrors = 1; precondition(!failed.verified)
    failed = c; failed.movement.away = 0; precondition(!failed.verified)
    failed = c; failed.stopped.frames = 0; precondition(!failed.verified)
    // Regression fixtures from the reported low-volume and full-volume runs.
    var reported = SetupCandidate(frequency:20000)
    reported.off.frames = 102; reported.off.carrierSum = -13273.3591
    reported.still.frames = 102; reported.still.carrierSum = -13265.3860; reported.still.contrastSum = 407.4118
    precondition(!reported.stable)
    reported.off.carrierSum = -13229.5532
    reported.still.carrierSum = -11606.9490; reported.still.contrastSum = 2019.3539
    reported.still.away = 6; reported.still.toward = 12; reported.still.actions = 48
    precondition(!reported.stable)
    // The louder, more detectable 18 kHz run must also fail for phantom actions.
    reported.off.carrierSum = -13234.6976
    reported.still.carrierSum = -9402.007; reported.still.contrastSum = 4146.8470
    reported.still.actions = 92
    precondition(!reported.stable)
    let setup = DeviceSetup(); setup.cancel(); precondition(!setup.canSave)
    print("PASS setup rejects weak signals, phantom actions, clipping, missing audio, incomplete movement and failed stopping")
}
