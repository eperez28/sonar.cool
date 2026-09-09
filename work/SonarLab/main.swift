import Foundation

func writeDiagnostic(_ text: String, name: String) {
    guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
    let folder = cache.appendingPathComponent("Sonar", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
}

import AppKit
import SwiftUI
import AVFoundation
import Accelerate
import CoreAudio
import PDFKit
import ApplicationServices
import Combine

// Passive pulse detector: it never changes scroll velocity or waits to release it.
struct DoublePushDetector {
    private var pulseStart: Double?
    private var lastToward = -Double.infinity
    private var previousPulse: Double?
    private var lastSample = -Double.infinity
    private var cooldownUntil = 0.0
    var feedback = ""
    var feedbackUntil = 0.0
    private mutating func say(_ message: String, now: Double) {
        feedback = message; feedbackUntil = now+1.2
    }
    mutating func feed(direction: String, now: Double) -> Bool {
        if now-lastSample > 0.2 { pulseStart = nil; previousPulse = nil }
        lastSample = now
        if now < cooldownUntil { return false }
        if let previous = previousPulse, now-previous > 0.85 {
            previousPulse = nil; say("Second push not detected",now:now)
        }
        if direction == "APPROACHING" {
            if pulseStart == nil { pulseStart = now }
            lastToward = now
            return false
        }
        // Ignore isolated mixed frames inside a pulse. A real return ends it faster.
        let gap = direction == "MOVING AWAY" ? 0.035 : 0.085
        guard let start = pulseStart, now-lastToward >= gap else { return false }
        pulseStart = nil
        let duration = lastToward-start+0.021
        guard duration >= 0.04 && duration <= 0.38 else {
            previousPulse = nil
            say(duration > 0.38 ? "Push too long for a tap" : "Push too brief",now:now)
            return false
        }
        if let previous = previousPulse, start-previous >= 0.13, start-previous <= 0.7 {
            previousPulse = nil; cooldownUntil = now+0.65
            say("Direction switched",now:now)
            return true
        }
        previousPulse = start
        say("1 push · push again",now:now)
        return false
    }
}

// Continuous scrolling never waits for a possible tap or a quiet re-arm period.
struct ScrollMotion {
    var velocity = 0.0
    var target = 0.0
    var forward = true
    var toggles = 0
    private var lastAway = -Double.infinity
    mutating func switchDirection(now: Double) {
        forward.toggle(); toggles += 1; velocity = 0; target = 0
        lastAway = -Double.infinity
    }
    mutating func feed(direction: String, strength: Float, now: Double) {
        if direction == "MOVING AWAY" {
            lastAway = now
            target = (forward ? 1 : -1) * min(700,110+120*log1p(Double(strength)/0.0003))
        } else if direction == "APPROACHING" || direction.contains("Calibrating") || direction.contains("Tone not clear") {
            target = 0; lastAway = -Double.infinity
        }
        // Bridge brief uncertain FFT frames; a confirmed return stops immediately.
    }
    mutating func step(dt: Double, now: Double) -> Double {
        if now-lastAway > 0.09 { target = 0 }
        let tau = target == 0 ? 0.075 : 0.07
        velocity += (target-velocity)*(1-exp(-dt/tau))
        if abs(velocity)<2 && target == 0 { velocity = 0 }
        return velocity*dt
    }
}

final class Reader: ObservableObject {
    let pdf = PDFView()
    let demo = DemoSession()
    let signal = SignalHistory()
    @Published var mode: DemoMode = .scroll { didSet { demo.wave.cancel(); resetMotion(); demo.feedback = "Start, stay still for 3 seconds, then try a gesture."; demo.inputFeedback = "Waiting for audio" } }
    @Published var chromeGallery = false { didSet { demo.wave.cancel(); resetMotion() } }
    var usesExternalControl: Bool { usesSystemScroll || (mode == .gallery && chromeGallery) }
    var usesSystemScroll: Bool { mode == .scroll && systemWide }
    @Published var action = "Lift to scroll · lower to reset"
    @Published private(set) var forward = true
    @Published private(set) var directionChanges = 0
    private var motion = ScrollMotion()
    private var taps = DoublePushDetector()
    @Published var airTapEnabled = true { didSet { resetMotion() } }
    @Published private(set) var gestureFeedback = ""
    private var trace: [String] = []
    @Published var systemWide = true { didSet { resetMotion() } }
    @Published var accessibilityGranted = AXIsProcessTrusted()
    private let systemScroll = SystemScroll()
    private var targetPID: pid_t = 0
    private var permissionObserver: NSObjectProtocol?
    private var permissionTimer: Timer?
    func testChrome(next: Bool) {
        guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier:"com.google.Chrome").first else { demo.feedback = "Open Chrome first"; return }
        chrome.activate(options:[])
        DispatchQueue.main.asyncAfter(deadline:.now()+0.6) { [weak self] in
            let sent = ChromeGallery.send(next:next)
            self?.demo.feedback = sent ? "Chrome arrow sent · verify the image changed" : "Chrome paused · focus a gallery outside text fields"
        }
    }
    func refreshPermission() { accessibilityGranted = AXIsProcessTrusted() }
    // Permission requests are never issued automatically. Opening Settings is explicit.
    func openAccessibilitySettings() {
        refreshPermission()
        guard !accessibilityGranted else { return }
        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    private var canScroll: Bool {
        if mode == .gallery && chromeGallery { return NSApp.isActive || (accessibilityGranted && ChromeGallery.frontmost && demo.wave.recording == nil) }
        return usesSystemScroll ? accessibilityGranted && !NSApp.isActive : NSApp.isActive
    }
    private var ticker: Timer?
    private var lastTick = 0.0
    func startMotion() {
        stopMotion()
        demo.wave.live = true
        signal.clear()
        trace = ["time\tdirection\tstrength\tfeedback\ttoggles"]
        lastTick = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval:1/60, repeats:true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t,forMode:.common); ticker = t
    }
    func stopMotion() {
        demo.wave.live = false
        demo.wave.cancel()
        ticker?.invalidate(); ticker = nil
        if trace.count > 1 {
            writeDiagnostic(trace.joined(separator:"\n"), name:"gesture-trace.tsv")
        }
        resetMotion()
        action = "Lift to scroll · lower to reset"
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(1/30, max(0,now-lastTick)); lastTick = now
        guard canScroll else { resetMotion(); return }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        if usesExternalControl && pid != targetPID { targetPID = pid; resetMotion(); return }
        if mode != .scroll { demo.tick(dt,mode:mode); return }
        let delta = motion.step(dt:dt,now:now)
        if abs(delta)>0.01 {
            if systemWide { systemScroll.scroll(delta) } else { scroll(points:CGFloat(delta)) }
        }
        let velocity = motion.velocity
        let next = airTapEnabled && now < taps.feedbackUntil ? taps.feedback : velocity > 10 ? "↓ Scrolling down" : (velocity < -10 ? "↑ Scrolling up" : "Lift to scroll · lower to reset")
        if action != next { action = next }
        let feedback = airTapEnabled && now < taps.feedbackUntil ? taps.feedback : ""
        if gestureFeedback != feedback { gestureFeedback = feedback }
    }
    init() {
        demo.galleryOutput = { [weak self] event in
            guard let self, self.chromeGallery, !NSApp.isActive else { return nil }
            return ChromeGallery.send(next:event == "next")
        }
        let poll = Timer(timeInterval:1,repeats:true) { [weak self] _ in self?.refreshPermission() }
        RunLoop.main.add(poll,forMode:.common); permissionTimer = poll
        permissionObserver = NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in self?.refreshPermission() }
        pdf.displayMode = .singlePageContinuous
        pdf.displayDirection = .vertical
        pdf.autoScales = true
        pdf.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        if let url = Bundle.main.url(forResource: "SoundWave", withExtension: "pdf") {
            pdf.document = PDFDocument(url: url)
        }
        if pdf.document == nil {
            let document = PDFDocument()
            for page in 1...5 {
                let image = NSImage(size: NSSize(width: 612, height: 792))
                image.lockFocus()
                NSColor.white.setFill()
                NSRect(x: 0, y: 0, width: 612, height: 792).fill()
                let text = "Sonar — practice reading\n\nPage \(page) of 5\n\nLift your palm to scroll. Lower it to reset.\n\nTwo short downward pushes switch direction.\n\nTry a slow movement, then pause. You can stop any time from the menu bar.\n\nThis is an experiment. Different Macs and rooms may respond differently."
                (text as NSString).draw(in: NSRect(x: 48, y: 80, width: 516, height: 640), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black])
                image.unlockFocus()
                if let pdfPage = PDFPage(image: image) { document.insert(pdfPage, at: document.pageCount) }
            }
            pdf.document = document
        }
    }
    var scroller: NSScrollView? {
        pdf.documentView?.enclosingScrollView
    }
    func consume(_ reading: Reading, duration: Double) {
        guard canScroll else { resetMotion(); return }
        let now = ProcessInfo.processInfo.systemUptime
        if mode == .signal { signal.append(reading,now:now); return }
        if mode != .scroll { demo.consume(reading,mode:mode,now:now); if gestureFeedback != demo.feedback { gestureFeedback = demo.feedback }; return }
        motion.feed(direction:reading.direction,strength:reading.strength,now:now)
        if airTapEnabled && taps.feed(direction:reading.direction,now:now) {
            motion.switchDirection(now:now)
        }
        forward = motion.forward; directionChanges = motion.toggles
        trace.append(String(format:"%.3f\t%@\t%.5f\t%@\t%d",now,reading.direction,reading.strength,taps.feedback,directionChanges))
        if trace.count > 2400 { trace.removeFirst(200) }
    }

    private func resetMotion() {
        demo.resetInput()
        systemScroll.reset()
        motion = ScrollMotion(); motion.forward = forward; motion.toggles = directionChanges
        taps = DoublePushDetector(); gestureFeedback = ""
    }
    func switchDirection() {
        forward.toggle(); directionChanges += 1; resetMotion()
    }

    func scroll(points: CGFloat) {
        guard let s = scroller, let doc = s.documentView else { return }
        var p = s.contentView.bounds.origin
        let maximum = max(0, doc.bounds.height-s.contentView.bounds.height)
        p.y = min(maximum, max(0, p.y + (doc.isFlipped ? points : -points)))
        s.contentView.scroll(to:p)
        s.reflectScrolledClipView(s.contentView)
    }
}

struct PaperView: NSViewRepresentable {
    let reader: Reader
    func makeNSView(context: Context) -> PDFView { reader.pdf }
    func updateNSView(_ view: PDFView, context: Context) {}
}

struct Reading {
    var spectrum: [Float]
    var baseline: [Float]
    var direction: String
    var carrierDB: Float
    var snr: Float
    var strength: Float
    var waveBands: [Double] = []
    var opposedStrength: Float = 0
    var waveform: [Float] = []
    var sampleRate: Double = 0
    var firstFrequency: Double = 0
    var binWidth: Double = 0
}

final class Analyzer {
    let n = 8192
    let hop = 2048
    let rate: Double
    let tone: Double
    let setup: vDSP_DFT_Setup
    var window = [Float](repeating: 0, count: 8192)
    var baseline: [Float] = []
    var frames = 0
    var history: [String] = []
    init(rate: Double, tone: Double) {
        self.rate = rate; self.tone = tone
        setup = vDSP_DFT_zop_CreateSetup(nil, 8192, .FORWARD)!
        vDSP_hann_window(&window, 8192, Int32(vDSP_HANN_NORM))
    }
    deinit { vDSP_DFT_DestroySetup(setup) }
    func analyze(_ input: [Float]) -> Reading {
        var real = [Float](repeating: 0, count: n)
        let imag = [Float](repeating: 0, count: n)
        var outR = real; var outI = real
        vDSP_vmul(input, 1, window, 1, &real, 1, vDSP_Length(n))
        vDSP_DFT_Execute(setup, real, imag, &outR, &outI)
        let center = Int((tone / rate * Double(n)).rounded())
        let radius = Int(600 / rate * Double(n))
        let bins = Array((center-radius)...(center+radius))
        let power = bins.map { max(Float(1e-16), (outR[$0]*outR[$0] + outI[$0]*outI[$0]) / Float(n*n)) }
        let db = power.map { 10 * log10($0) }
        let carrier = db[(radius-1)...(radius+1)].max()!
        let floor = (Array(db.prefix(5)) + Array(db.suffix(5))).reduce(0,+) / 10
        if baseline.isEmpty { baseline = power }
        let calibrating = Double(frames*hop) / rate < 2.5
        if calibrating {
            let a: Float = 1 / Float(frames+1)
            baseline = zip(baseline, power).map { $0*(1-a)+$1*a }
        }
        frames += 1
        var left: Float = 0; var right: Float = 0
        for i in power.indices where abs(i-radius) >= 3 {
            let excess = max(0, power[i] - baseline[i]*2)
            if i < radius { left += excess } else { right += excess }
        }
        let reference = max(power[radius-1...radius+1].reduce(0,+), 1e-12)
        let strength = max(left,right) / reference
        var raw = "Still / no clear motion"
        if strength > 0.0003 && carrier-floor > 15 {
            if right > left*1.7 { raw = "APPROACHING" }
            else if left > right*1.7 { raw = "MOVING AWAY" }
            else { raw = "Mixed movement" }
        }
        history.append(raw); if history.count > 2 { history.removeFirst() }
        let stable = history.count == 2 && history.allSatisfy { $0 == raw }
        let direction = calibrating ? "Calibrating — hands still" : (carrier-floor < 15 ? "Tone not clear — try another frequency" : (stable ? raw : "Listening…"))
        var bands = [Double](repeating:0,count:8)
        for i in power.indices where abs(i-radius) >= 3 {
            let band = min(7,i*8/power.count)
            bands[band] += Double(max(0,power[i]-baseline[i]*2)/reference)
        }
        bands = bands.map { log1p($0/0.0003) }
        return Reading(spectrum: db, baseline: baseline.map { 10*log10(max($0,1e-16)) }, direction: direction, carrierDB: carrier, snr: carrier-floor, strength: strength, waveBands: bands, opposedStrength: min(left,right)/reference, waveform: Array(input.suffix(512)), sampleRate: rate, firstFrequency: Double(center-radius)*rate/Double(n), binWidth: rate/Double(n))
    }
}

func builtInDevice(scope: AudioObjectPropertyScope) throws -> AudioDeviceID {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
    var ids = [AudioDeviceID](repeating: 0, count: Int(size)/MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
    for id in ids {
        var transport: UInt32 = 0; var s: UInt32 = 4
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, &transport) == noErr, transport == kAudioDeviceTransportTypeBuiltIn else { continue }
        a.mSelector = kAudioDevicePropertyStreams; a.mScope = scope; s = 0
        if AudioObjectGetPropertyDataSize(id, &a, 0, nil, &s) == noErr && s > 0 { return id }
    }
    throw NSError(domain: "SonarLab", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in audio device not found."])
}

final class Sonar: ObservableObject {
    let reader = Reader()
    let distance = DistanceModel()
    let position = PositionModel()
    @Published var running = false
    @Published var starting = false
    private var startAttempt = UUID()
    @Published var status = "Ready — sound is off"
    @Published var reading: Reading?
    @Published var frequency = (UserDefaults.standard.object(forKey:"sonarTone") as? Double ?? 20000.0) { didSet { if oldValue != frequency { reader.demo.wave.clear(); UserDefaults.standard.set(frequency,forKey:"sonarTone") } } }
    @Published var level = 0.008
    @Published var route = "Built-in speakers + microphone • AirPods excluded"
    private var engine: HardwareAudio?
    private let analysisQueue = DispatchQueue(label:"sonarlab.analysis")
    private var timer: Timer?
    var globalControlsReady = false
    private var session = UUID()
    func start() {
        guard !running && !starting else { return }
        reader.refreshPermission()
        if reader.usesExternalControl && !reader.accessibilityGranted {
            status = "macOS has not accepted this build’s Accessibility access. Check Sonar in Accessibility settings."; return
        }
        if reader.usesExternalControl && !globalControlsReady { status = "Global stop shortcut unavailable. Quit and reopen Sonar."; return }
        starting = true; status = "Starting…"
        startAttempt = UUID(); let attempt = startAttempt
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                guard self.startAttempt == attempt else { return }
                self.starting = false
                if granted { self.begin() }
                else { self.status = "Microphone access needed in System Settings → Privacy & Security → Microphone." }
            }
        }
    }
    func begin() {
        guard !running else { return }
        do {
            let tone = frequency
            let device = try builtInDevice(scope:kAudioDevicePropertyScopeInput)
            var rate = 0.0; var size: UInt32 = 8
            var address = AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyNominalSampleRate,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            let result = AudioObjectGetPropertyData(device,&address,0,nil,&size,&rate)
            guard result == noErr, rate > 0 else { throw NSError(domain:"Microphone rate",code:Int(result)) }
            let positioning = reader.mode == .position
            let ranging = reader.mode == .distance || positioning
            distance.reset(); position.reset()
            let rightAnalyzer = positioning ? RangeAnalyzer(rate:rate,descending:true) : nil
            let rangeAnalyzer = ranging ? RangeAnalyzer(rate:rate) : nil
            let analyzer = Analyzer(rate:rate,tone:tone)
            var samples: [Float] = []; samples.reserveCapacity(8192)
            session = UUID(); let id = session
            let e = HardwareAudio(tone:tone,amplitude:level,ranging:ranging,positioning:positioning) { [weak self] block in
                self?.analysisQueue.async { [weak self] in
                    samples.append(contentsOf:block)
                    if let ranger = rangeAnalyzer {
                        while samples.count >= ranger.n {
                            let window = Array(samples.prefix(ranger.n))
                            let result = ranger.analyze(window)
                            let right = rightAnalyzer?.analyze(window)
                            samples.removeFirst(ranger.hop)
                            DispatchQueue.main.async { [weak self] in
                                guard let self, self.session == id, self.running else { return }
                                if let right { self.position.receive(left:result,right:right) }
                                else { self.distance.receive(result) }
                                self.status=result.status
                            }
                        }
                        return
                    }
                    while samples.count >= analyzer.n {
                        let r = analyzer.analyze(Array(samples.prefix(analyzer.n)))
                        samples.removeFirst(analyzer.hop)
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, self.session == id, self.running else { return }
                            self.reading = r; self.status = r.direction
                            self.reader.consume(r,duration:Double(analyzer.hop)/rate)
                        }
                    }
                }
            }
            engine = e
            try e.start()
            running = true
            reader.startMotion()
            route = "MacBook audio • mic \(Int(e.inputRate)) Hz / speakers \(Int(e.outputRate)) Hz"
            status = "Calibrating — hands still"
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.reader.refreshPermission()
                if self.reader.usesExternalControl && !self.reader.accessibilityGranted { self.stop(); self.status = "Accessibility permission was removed."; return }
            }
        } catch {
            stop(); status = "Could not start: \(error.localizedDescription)"
        }
    }
    func stop() {
        startAttempt = UUID(); starting = false
        session = UUID(); timer?.invalidate(); timer = nil
        engine?.stop(); engine = nil
        position.reset()
        distance.reading.cm=nil; distance.reading.quality=0; distance.reading.status="Stopped · start again to measure"
        running = false; status = "Stopped — sound is off"
        reader.stopMotion()
    }
}

struct Spectrum: View {
    let reading: Reading?
    var body: some View {
        Canvas { context, size in
            for i in 0...4 {
                let y = CGFloat(i)*size.height/4
                var p = Path(); p.move(to: CGPoint(x:0,y:y)); p.addLine(to: CGPoint(x:size.width,y:y))
                context.stroke(p, with: .color(.white.opacity(0.08)), lineWidth: 1)
            }
            var center = Path(); center.move(to: CGPoint(x:size.width/2,y:0)); center.addLine(to: CGPoint(x:size.width/2,y:size.height))
            context.stroke(center, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth:1,dash:[4,4]))
            guard let r = reading else { return }
            let top = max(-30, r.carrierDB+8)
            for (values, color) in [(r.baseline, Color.gray.opacity(0.5)), (r.spectrum, Color.mint)] {
                var path = Path()
                for (i,value) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(i)/CGFloat(values.count-1)*size.width, y: CGFloat(min(1,max(0,(top-value)/75)))*size.height)
                    if i == 0 { path.move(to:point) } else { path.addLine(to:point) }
                }
                context.stroke(path, with: .color(color), lineWidth: 2)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let sonar = Sonar()
    var window: NSWindow!
    private let globalControls = GlobalControls()
    private var statusItem: NSStatusItem!
    private var subscriptions = Set<AnyCancellable>()
    private let menuState = NSMenuItem(title:"Stopped",action:nil,keyEquivalent:"")
    private let menuStart = NSMenuItem(title:"Start system-wide scrolling",action:nil,keyEquivalent:"")
    private let menuStop = NSMenuItem(title:"Stop · ⌃⌥⌘Space",action:nil,keyEquivalent:"")
    private let menuPermission = NSMenuItem(title:"Accessibility settings…",action:nil,keyEquivalent:"")
    func menuWillOpen(_ menu: NSMenu) { sonar.reader.refreshPermission(); updateStatusMenu() }
    private func updateStatusMenu() {
        guard statusItem != nil else { return }
        let permission = !sonar.reader.usesExternalControl || sonar.reader.accessibilityGranted
        if sonar.running {
            let direction = sonar.reader.mode == .scroll ? (sonar.reader.forward ? "↓" : "↑") : sonar.reader.mode.rawValue
            let hint = sonar.reader.gestureFeedback == "1 push · push again" ? " · 1" : (sonar.reader.gestureFeedback == "Direction switched" ? " ✓" : "")
            statusItem.button?.title = "Sonar \(direction)\(hint)"
            menuState.title = sonar.status.contains("Calibrating") ? "Calibrating — stay still" : (sonar.reader.mode == .gallery ? sonar.reader.gestureFeedback : "Running · \(direction) · until stopped")
        } else if sonar.starting {
            statusItem.button?.title = "Sonar …"; menuState.title = "Starting audio…"
        } else if !permission {
            statusItem.button?.title = "Sonar !"
            menuState.title = "Blocked: macOS has not granted this build access"
        } else {
            statusItem.button?.title = "Sonar ○"
            menuState.title = sonar.status
        }
        statusItem.button?.toolTip = menuState.title
        menuStart.title = permission ? "Start \(sonar.reader.mode.rawValue.lowercased())" : "Start unavailable — Accessibility access needed"
        menuStart.isEnabled = permission && !sonar.running && !sonar.starting
        menuStop.isEnabled = sonar.running || sonar.starting
        menuPermission.isHidden = permission
    }
    @objc func permissionFromMenu() { sonar.reader.openAccessibilitySettings() }

    @objc func stopFromMenu() { sonar.stop() }
    @objc func flipFromMenu() { sonar.reader.switchDirection() }
    @objc func showControls() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    @objc func startFromMenu() {
        if sonar.reader.mode != .scroll && !sonar.reader.usesExternalControl { showControls() }
        sonar.start()
        // Leave the active application available to receive scroll events.
        if sonar.reader.usesExternalControl && (sonar.starting || sonar.running) { NSApp.hide(nil) }
        updateStatusMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        globalControls.action = { [weak self] id in
            if id == 1 { self?.sonar.stop() } else { self?.sonar.reader.switchDirection() }
        }
        sonar.globalControlsReady = globalControls.install()
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.title = "Sonar ○"
        let statusMenu = NSMenu(); statusMenu.autoenablesItems = false; statusMenu.delegate = self
        menuState.isEnabled = false; statusMenu.addItem(menuState)
        statusMenu.addItem(.separator())
        menuStart.target = self; menuStart.action = #selector(startFromMenu); statusMenu.addItem(menuStart)
        menuStop.target = self; menuStop.action = #selector(stopFromMenu); statusMenu.addItem(menuStop)
        for (title,action) in [("Switch direction · ⌃⌥⌘D",#selector(flipFromMenu)),("Show controls",#selector(showControls))] {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:""); item.target = self; statusMenu.addItem(item)
        }
        menuPermission.target = self; menuPermission.action = #selector(permissionFromMenu); statusMenu.addItem(menuPermission)
        let quit = NSMenuItem(title:"Quit Sonar",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"")
        quit.target = NSApp; statusMenu.addItem(quit)
        statusItem.menu = statusMenu
        // Defer until @Published has committed its value before reading the model.
        sonar.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusMenu() } }.store(in:&subscriptions)
        sonar.reader.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusMenu() } }.store(in:&subscriptions)
        updateStatusMenu()
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
        let submenu = NSMenu(); submenu.addItem(withTitle:"Quit Sonar",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); item.submenu = submenu; NSApp.mainMenu = menu
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1060,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "Sonar"; window.delegate = self
        window.contentView = NSHostingView(rootView:ContentView(sonar:sonar))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        if CommandLine.arguments.contains("--verify-audio") {
            sonar.reader.systemWide = false
            DispatchQueue.main.asyncAfter(deadline:.now()+1) { self.sonar.start() }
            DispatchQueue.main.asyncAfter(deadline:.now()+8) {
                let report = "Running: \(self.sonar.running)\nRoute: \(self.sonar.route)\nState: \(self.sonar.status)\nFrames received: \(self.sonar.reading != nil)\nCarrier dB: \(self.sonar.reading?.carrierDB ?? -999)\nTone contrast dB: \(self.sonar.reading?.snr ?? -999)\n"
                writeDiagnostic(report, name:"audio-verification.txt")
                self.sonar.stop()
            }
        }
        if CommandLine.arguments.contains("--verify-scroll") {
            sonar.reader.systemWide = false
            DispatchQueue.main.asyncAfter(deadline:.now()+2) { [self] in
                NSApp.activate(ignoringOtherApps:true)
                window.makeKeyAndOrderFront(nil)
                guard let scroll = sonar.reader.scroller else { return }
                sonar.reader.scroll(points:300)
                let initial = scroll.contentView.bounds.origin.y
                sonar.reader.startMotion()
                // Feed the actual reader at analysis cadence, checking PDF clip movement.
                let sequence: [(String,Int)] = [("MOVING AWAY",25),("APPROACHING",25),("Still",20),
                    ("APPROACHING",6),("MOVING AWAY",6),("APPROACHING",6),("MOVING AWAY",6),
                    ("Still",35),("MOVING AWAY",25),("APPROACHING",25)]
                var phase = 0, frame = 0
                var positions = [initial]
                let initialChanges = sonar.reader.directionChanges
                var timer: Timer?
                timer = Timer.scheduledTimer(withTimeInterval:0.02,repeats:true) { [self] _ in
                    let r = Reading(spectrum:[],baseline:[],direction:sequence[phase].0,carrierDB:-30,snr:40,strength:0.004)
                    if phase == 3 && frame == 0 { sonar.reader.switchDirection() }
                    if phase < 3 || phase >= 8 { sonar.reader.consume(r,duration:0.02) }; frame += 1
                    if frame == sequence[phase].1 {
                        positions.append(scroll.contentView.bounds.origin.y)
                        phase += 1; frame = 0
                        if phase == sequence.count {
                            timer?.invalidate(); sonar.reader.stopMotion()
                            let first = positions[1]-positions[0]
                            let second = positions[9]-positions[8]
                            let returnsOK = first*(positions[2]-positions[1]) >= -0.01 && second*(positions[10]-positions[9]) >= -0.01
                            let tapsStill = abs(positions[8]-positions[3])<1
                            let switched = sonar.reader.directionChanges == initialChanges+1
                            let passed = abs(first)>5 && first*second<0 && returnsOK && tapsStill && switched
                            let report = "Active: \(NSApp.isActive)\nPositions: \(positions)\nReturn suppression: \(returnsOK)\nTap sequence stationary: \(tapsStill)\nExactly one toggle: \(switched)\nReader gesture sequence: \(passed ? "PASS" : "FAIL")\n"
                            writeDiagnostic(report, name:"scroll-verification.txt")
                            if !sonar.reader.forward { sonar.reader.switchDirection() }
                            sonar.reader.pdf.goToFirstPage(nil)
                        }
                    }
                }
            }
        }
        NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.sonar.stop(); return nil }; return event
        }
    }
    func windowWillClose(_ notification: Notification) { sonar.stop(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { sonar.stop() }
}

// Failed test expectations are ordinary process failures, never SIGTRAP crashes.
func testCheck(_ condition: @autoclosure () -> Bool,
               _ message: @autoclosure () -> String = "Expectation failed",
               file: StaticString = #fileID, line: UInt = #line) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL \(file):\(line): \(message())\n".utf8))
        exit(EXIT_FAILURE)
    }
}
if CommandLine.arguments.contains("--self-test-failure-probe") {
    testCheck(false,"Intentional clean-exit probe")
}

if CommandLine.arguments.contains("--self-test") {
    testEchoFlow()
    testPosition()
    testDistance()
    testDemoModes()
    testWaveCalibration()
    for rate in [48000.0,96000.0] {
      for (offset, expected) in [(180.0,"APPROACHING"),(-180.0,"MOVING AWAY"),(0.0,"Still / no clear motion")] {
        let a = Analyzer(rate:rate,tone:20000)
        let startMotion = Int(ceil(2.5*rate/Double(a.hop)))+4
        var result: Reading!
        for frame in 0..<(startMotion+12) {
            let samples = (0..<a.n).map { i -> Float in
                let t = Double(frame*a.hop+i)/rate
                return Float(0.05*sin(2*Double.pi*20000*t) + (frame > startMotion && offset != 0 ? 0.004*sin(2*Double.pi*(20000+offset)*t) : 0))
            }
            result = a.analyze(samples)
        }
        testCheck(result.direction == expected,"Expected \(expected), got \(result.direction)")
        print("PASS synthetic \(expected) at \(rate)")
      }
    }
    var detector = DoublePushDetector()
    var time = 0.0
    var detected = 0
    func feedPush(_ direction: String, _ frames: Int) {
        for _ in 0..<frames {
            if detector.feed(direction:direction,now:time) { detected += 1 }
            time += 0.02
        }
    }
    feedPush("APPROACHING",8); feedPush("MOVING AWAY",6)
    testCheck(detected == 0)
    feedPush("APPROACHING",8); feedPush("MOVING AWAY",6)
    testCheck(detected == 1)
    feedPush("APPROACHING",8); feedPush("MOVING AWAY",6)
    testCheck(detected == 1, "Triple push toggled twice")
    feedPush("Still",60)
    feedPush("APPROACHING",8); feedPush("Still",60)
    testCheck(detected == 1, "Single push toggled")
    feedPush("APPROACHING",30); feedPush("MOVING AWAY",6)
    feedPush("APPROACHING",30); feedPush("MOVING AWAY",6)
    testCheck(detected == 1, "Long return strokes toggled")
    feedPush("Still",60)
    feedPush("APPROACHING",8); feedPush("Mixed movement",6)
    feedPush("APPROACHING",8); feedPush("Mixed movement",6)
    testCheck(detected == 2, "Neutral reversal prevented detection")
    print("PASS passive double push, single/long pulse rejection and cooldown")
    for rate in [48000.0,96000.0] {
        let analyzer = Analyzer(rate:rate,tone:20000)
        var detector = DoublePushDetector()
        var switches = 0
        for frame in 0..<Int(4.5*rate/Double(analyzer.hop)) {
            let samples = (0..<analyzer.n).map { i -> Float in
                let t = Double(frame*analyzer.hop+i)/rate
                let pulse = (t >= 3.1 && t < 3.32) || (t >= 3.5 && t < 3.72)
                return Float(0.05*sin(2*Double.pi*20000*t)+(pulse ? 0.004*sin(2*Double.pi*20180*t) : 0))
            }
            let reading = analyzer.analyze(samples)
            if detector.feed(direction:reading.direction,now:Double(frame*analyzer.hop)/rate) { switches += 1 }
        }
        testCheck(switches == 1, "FFT double push failed at \(rate)")
        print("PASS FFT-to-gesture double push at \(rate)")
    }
    let downEvent = SystemScroll.event(pixels:12)!
    let upEvent = SystemScroll.event(pixels:-12)!
    testCheck(downEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -12)
    testCheck(upEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 12)
    print("PASS system scroll event direction and pixel encoding (not posted)")
    var continuous = ScrollMotion()
    var t = 0.0
    for _ in 0..<30 {
        continuous.feed(direction:"MOVING AWAY",strength:0.004,now:t)
        testCheck(continuous.step(dt:0.02,now:t)>0); t += 0.02
    }
    let beforeGap = continuous.velocity
    for _ in 0..<3 {
        continuous.feed(direction:"Mixed movement",strength:0,now:t)
        _ = continuous.step(dt:0.02,now:t); t += 0.02
    }
    testCheck(continuous.velocity >= beforeGap*0.95, "Brief FFT gap caused stutter")
    for _ in 0..<30 {
        continuous.feed(direction:"APPROACHING",strength:0.004,now:t)
        testCheck(continuous.step(dt:0.02,now:t)>=0); t += 0.02
    }
    continuous.feed(direction:"MOVING AWAY",strength:0.004,now:t)
    testCheck(continuous.step(dt:0.02,now:t)>0, "Return blocked next lift")
    continuous.switchDirection(now:t)
    continuous.feed(direction:"MOVING AWAY",strength:0.004,now:t)
    testCheck(continuous.step(dt:0.02,now:t)<0)
    for _ in 0..<50 { t += 0.02; _ = continuous.step(dt:0.02,now:t) }
    testCheck(continuous.velocity == 0)
    print("PASS continuous scrolling across uncertain frames, free returns, immediate next lift, manual reversal, stale stop")


} else {
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate; app.run()
}
