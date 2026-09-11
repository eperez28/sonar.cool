import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
import UniformTypeIdentifiers
import CoreAudio
import CryptoKit

struct DiagnosticSampleSummary: Codable {
    var phase: String
    var status = "not_started"
    var startedAt = ""
    var durationSeconds: Double = 0
    var plannedSeconds: Double = 0
    var frequencyHz: Double = 0
    var routing: DiagnosticRoute?
    var inputCallbacks = 0
    var outputCallbacks = 0
    var inputErrors = 0
    var lastInputError: Int32 = 0
    var missingOutputBuffers = 0
    var calibrationFrames = 0
    var calibrationCarrierMin: Double?
    var calibrationCarrierMax: Double?
    var baselineChangeMaxDB: Double = 0
    var wouldScrollFrames = 0
    var wouldScrollPoints: Double = 0
    var returnStopFrames = 0
    var directionSwitches = 0
    var blocks = 0
    var samples = 0
    var analyzedFrames = 0
    var motionFrames = 0
    var carrierSum: Double = 0
    var contrastSum: Double = 0
    var maximumBlockGapMS: Double = 0
    var inputRate: Double = 0
    var outputRate: Double = 0
    var volumeState = "unknown"
    var meanCarrierDB: Double? { analyzedFrames > 0 ? carrierSum / Double(analyzedFrames) : nil }
    var meanContrastDB: Double? { analyzedFrames > 0 ? contrastSum / Double(analyzedFrames) : nil }
}

// Session-local device numbers, never device names, UIDs, or serial numbers.
struct DiagnosticRoute: Codable {
    let inputDevice: UInt32
    let outputDevice: UInt32
    let inputTransport: UInt32?
    let outputTransport: UInt32?
    let masterMuted: Bool?
    let channelMuted: [Bool?]
    let masterVolume: Float?
    let channelVolumes: [Float?]
    static func snapshot(_ audio: HardwareAudio) -> Self {
        func transport(_ id: AudioDeviceID) -> UInt32? {
            var address = AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyTransportType,mScope:kAudioObjectPropertyScopeGlobal,mElement:0)
            var value: UInt32 = 0; var size: UInt32 = 4
            return AudioObjectGetPropertyData(id,&address,0,nil,&size,&value) == noErr ? value : nil
        }
        let id = audio.outputDeviceID
        return Self(inputDevice:audio.inputDeviceID,outputDevice:id,
            inputTransport:transport(audio.inputDeviceID),outputTransport:transport(id),
            masterMuted:SpeakerVolume.read(id,kAudioDevicePropertyMute,0,initial:UInt32(0)).map{$0 != 0},
            channelMuted:[1,2].map{SpeakerVolume.read(id,kAudioDevicePropertyMute,UInt32($0),initial:UInt32(0)).map{$0 != 0}},
            masterVolume:SpeakerVolume.read(id,kAudioDevicePropertyVolumeScalar,0,initial:Float32(0)),
            channelVolumes:[1,2].map{SpeakerVolume.read(id,kAudioDevicePropertyVolumeScalar,UInt32($0),initial:Float32(0))})
    }
}

struct DiagnosticReport: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let executableSHA256: String
    let diagnosticBuild: String
    let appVersion: String
    let build: String
    let macModel: String
    let modelName: String
    let modelYear: String
    let chip: String
    let macOS: String
    let microphonePermission: String
    let accessibilityGranted: Bool
    let toneHz: Double
    let digitalAmplitude: Double
    let phases: [DiagnosticSampleSummary]
    let controlTest: String
    let result: String
    let errorCode: Int?
    let limitations: String
}

final class Diagnostics: ObservableObject {
    @Published var message = "We’ll check the sound path, then ask you to move your hand."
    @Published var remaining = 0
    @Published var movementCue = false
    @Published var stepTitle = "Check Sonar"
    @Published var testing = false
    @Published var readyForMovement = false
    @Published var report = ""
    @Published var controlTest = "not_tested"
    @Published var controlMessage = "Open a scrollable page in another app. Schedule a test, then switch to it and place your pointer over the page."
    @Published var controlPending = false
    private var controlTask: DispatchWorkItem?
    private var frequencyIndex = 0
    private var extended = false
    @Published var showExtras = false
    @Published var extraIndex = 0
    @Published var extraFinished = false
    @Published var walkthroughComplete = false
    private var frequencies: [Double] { extended ? Array(Set([tone, 18000, 19000, 20000])).sorted(by: >) : [tone] }
    private var testTone: Double { frequencies[frequencyIndex] }
    let tone: Double
    let amplitude: Double
    private var engine: HardwareAudio?
    private var timer: Timer?
    private let queue = DispatchQueue(label:"sonar.private-diagnostics")
    private var token = UUID()
    private var phase = ""
    private var phaseStart = 0.0
    private var current = DiagnosticSampleSummary(phase:"")
    private var summaries: [DiagnosticSampleSummary] = []
    init(tone: Double, amplitude: Double) { self.tone = tone; self.amplitude = amplitude }
    deinit { timer?.invalidate(); engine?.stop() }

    func start() {
        cancel(); report = ""; summaries = []; readyForMovement = false; frequencyIndex = 0; extended = false; showExtras = false; extraIndex = 0; extraFinished = false; walkthroughComplete = false; current = DiagnosticSampleSummary(phase:""); controlTest = "not_tested"
        stepTitle = "1 of 4 · Permissions"; message = "Checking microphone access. If macOS asks, choose Allow."; testing = true
        let attempt = token
        AVCaptureDevice.requestAccess(for:.audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.token == attempt else { return }
                if granted { self.begin("tone_off") }
                else { self.finish("Microphone permission is needed to run the test.") }
            }
        }
    }
    func cancel() {
        if testing && current.status == "running" {
            captureCounters(); current.status = "interrupted"; summaries.append(current)
        }
        controlTask?.cancel(); controlTask = nil; controlPending = false
        token = UUID(); timer?.invalidate(); timer = nil
        engine?.stop(); engine = nil; testing = false; remaining = 0
    }
    func begin(_ next: String) {
        cancel(); phase = next; testing = true; readyForMovement = false
        current = DiagnosticSampleSummary(phase:next)
        current.frequencyHz = next == "movement" ? tone : testTone
        let frequency = current.frequencyHz
        current.volumeState = String(describing:SpeakerVolume.current())
        movementCue = false
        stepTitle = next == "tone_off" ? "2 of 4 · Microphone" : next == "tone_on_still" ? "3 of 4 · Speakers and calibration" : next == "movement" ? "4 of 4 · Hand movement" : "Extra check · Stay still"
        remaining = next == "stability" ? 30 : next == "movement" ? 13 : 7
        message = next == "stability" ? "Keep your hands still while we check for unwanted scrolling." : next == "tone_off" ? "Keep your hands still. Checking your microphone." : next == "tone_on_still" ? "Keep your hands still. Checking the sound from your speakers." : "Hold your palm still above the keyboard. Wait for GO."
        current.status = "running"
        current.startedAt = ISO8601DateFormatter().string(from:Date())
        current.plannedSeconds = Double(remaining)
        phaseStart = ProcessInfo.processInfo.systemUptime
        let attempt = token
        var buffer: [Float] = []
        var analyzer: Analyzer?
        var previous: Double?
        var calibration = DiagnosticSampleSummary(phase:next)
        var lastBaseline: [Float] = []
        var simulatedMotion = ScrollMotion()
        var simulatedTaps = DoublePushDetector()
        var simulatedTime = 0.0
        let audio = HardwareAudio(tone:frequency,amplitude:next == "tone_off" ? 0 : amplitude) { [weak self] block in
            let time = ProcessInfo.processInfo.systemUptime
            self?.queue.async { [weak self] in
                guard let self else { return }
                // Analyze only in memory. Neither samples nor spectra enter the report.
                let gap = previous.map { max(0,(time-$0)*1000) } ?? 0
                previous = time
                buffer.append(contentsOf:block)
                var readings: [(Double,Double,Bool)] = []
                if let analyzer {
                    while buffer.count >= analyzer.n {
                        let r = analyzer.analyze(Array(buffer.prefix(analyzer.n)))
                        buffer.removeFirst(analyzer.hop)
                        let dt = Double(analyzer.hop) / analyzer.rate
                        simulatedTime += dt
                        if r.calibrationRemaining != nil {
                            // Exclude the initial tone ramp; measure later calibration variation.
                            if simulatedTime > 0.5, r.carrierDB.isFinite {
                                calibration.calibrationFrames += 1
                                let level = Double(r.carrierDB)
                                calibration.calibrationCarrierMin = min(calibration.calibrationCarrierMin ?? level, level)
                                calibration.calibrationCarrierMax = max(calibration.calibrationCarrierMax ?? level, level)
                                if lastBaseline.count == r.baseline.count, !lastBaseline.isEmpty {
                                    let delta = zip(lastBaseline,r.baseline).map { abs(Double($0-$1)) }.reduce(0,+) / Double(lastBaseline.count)
                                    if delta.isFinite { calibration.baselineChangeMaxDB = max(calibration.baselineChangeMaxDB,delta) }
                                }
                                lastBaseline = r.baseline
                            }
                        } else {
                            // Same scroll/double-push logic, simulated only: never posts events.
                            simulatedMotion.feed(direction:r.direction,strength:r.strength,now:simulatedTime)
                            if simulatedTaps.feed(direction:r.direction,now:simulatedTime) { simulatedMotion.switchDirection(now:simulatedTime) }
                            let points = simulatedMotion.step(dt:dt,now:simulatedTime)
                            if abs(points) > 0.01 { calibration.wouldScrollFrames += 1; calibration.wouldScrollPoints += abs(points) }
                            if r.direction == "APPROACHING" { calibration.returnStopFrames += 1 }
                            calibration.directionSwitches = simulatedMotion.toggles
                            readings.append((Double(r.carrierDB),Double(r.snr),r.direction == "APPROACHING" || r.direction == "MOVING AWAY"))
                        }
                    }
                } else { buffer.removeAll(keepingCapacity:true) }
                let sampleCount = block.count
                let snapshot = calibration
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.token == attempt, self.testing else { return }
                    self.current.calibrationFrames = snapshot.calibrationFrames
                    self.current.calibrationCarrierMin = snapshot.calibrationCarrierMin
                    self.current.calibrationCarrierMax = snapshot.calibrationCarrierMax
                    self.current.baselineChangeMaxDB = snapshot.baselineChangeMaxDB
                    self.current.wouldScrollFrames = snapshot.wouldScrollFrames
                    self.current.wouldScrollPoints = snapshot.wouldScrollPoints
                    self.current.returnStopFrames = snapshot.returnStopFrames
                    self.current.directionSwitches = snapshot.directionSwitches
                    self.current.blocks += 1; self.current.samples += sampleCount
                    self.current.maximumBlockGapMS = max(self.current.maximumBlockGapMS,gap)
                    for (carrier,contrast,motion) in readings where carrier.isFinite && contrast.isFinite {
                        self.current.analyzedFrames += 1
                        self.current.carrierSum += carrier; self.current.contrastSum += contrast
                        if motion { self.current.motionFrames += 1 }
                    }
                }
            }
        }
        do {
            engine = audio
            try audio.start()
            current.routing = DiagnosticRoute.snapshot(audio)
            current.inputRate = audio.inputRate; current.outputRate = audio.outputRate
            let rate = audio.inputRate
            queue.async { analyzer = Analyzer(rate:rate,tone:frequency) }
            timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
                guard let self else { return }
                self.remaining -= 1
                if self.phase == "movement" && self.remaining == 10 {
                    self.movementCue = true
                    self.message = "GO — lift and lower your palm above the keyboard. Keep repeating until the test ends."
                    NSAccessibility.post(element:NSApp.mainWindow as Any, notification:.announcementRequested,
                        userInfo:[.announcement:"Go. Lift and lower your palm above the keyboard.", .priority:NSAccessibilityPriorityLevel.high.rawValue])
                }
                if self.remaining <= 0 { self.completePhase() }
            }
        } catch {
            finish("The audio connection failed. The report contains its error code.",errorCode:(error as NSError).code)
        }
    }
    private func completePhase() {
        captureCounters()
        current.status = "completed"
        summaries.append(current)
        let completed = phase
        if showExtras && completed == "stability" { extraFinished = true }
        cancel()
        if completed == "tone_off" { begin("tone_on_still") }
        else if completed == "tone_on_still" {
            if frequencyIndex + 1 < frequencies.count { extraFinished = false; frequencyIndex += 1; begin("tone_off"); return }
            if extended { extended = false; extraFinished = true; finish(Self.result(summaries)); return }
            readyForMovement = true
            stepTitle = "Next · Move your hand"
            message = "Hold your open palm above the keyboard, facing down. When you’re ready, press the button below. Wait for GO, then lift and lower your hand."
        } else { finish(Self.result(summaries)) }
    }
    static func result(_ values: [DiagnosticSampleSummary]) -> String {
        guard values.count >= 3, values.allSatisfy({ $0.analyzedFrames > 0 }) else { return "Not enough microphone readings arrived to complete the test." }
        guard let movement = values.first(where: { $0.phase == "movement" }) else { return "Sound checks saved. The hand movement test has not been completed." }
        let stillIndex = values.firstIndex { $0.phase == "tone_on_still" && $0.frequencyHz == movement.frequencyHz } ?? 1
        let off = values[stillIndex-1], still = values[stillIndex]
        if values.contains(where: {$0.inputErrors > 0 || $0.outputCallbacks == 0 && $0.blocks > 0}) {
            return "Audio delivery reported errors or no speaker callbacks. Review the per-test counters."
        }
        let rise = (still.meanCarrierDB ?? -160) - (off.meanCarrierDB ?? -160)
        if rise < 6 || (still.meanContrastDB ?? 0) < 15 { return "Sonar’s tone was not clearly detected. Check built-in speaker volume. This alone does not identify the cause." }
        if still.wouldScrollFrames > 0 {
            return "Sonar would have scrolled during the still test. Save this report so we can investigate the unwanted scrolling."
        }
        if (still.calibrationCarrierMax ?? 0) - (still.calibrationCarrierMin ?? 0) > 12 {
            return "The sound changed during setup. Try again with your hand still, or save this report for help."
        }
        if Double(still.motionFrames)/Double(still.analyzedFrames) > 0.1 { return "The detector reported movement during the still test. The baseline may be unstable, or something moved nearby." }
        if movement.motionFrames == 0 { return "Sonar’s tone was detected, but the movement test did not register clear motion." }
        return "Sonar’s tone and movement were detected. This test does not verify control of another app."
    }
    func finish(_ result: String, errorCode: Int? = nil) {
        if testing { captureCounters(); current.status = errorCode == nil ? "interrupted" : "failed"; summaries.append(current) }
        cancel(); readyForMovement = false; movementCue = false; stepTitle = "Check complete"; message = result
        var size = 0
        sysctlbyname("hw.model",nil,&size,nil,0)
        var model = [CChar](repeating:0,count:max(1,size))
        sysctlbyname("hw.model",&model,&size,nil,0)
        let permission: String
        switch AVCaptureDevice.authorizationStatus(for:.audio) {
        case .authorized: permission = "authorized"
        case .denied: permission = "denied"
        case .restricted: permission = "restricted"
        default: permission = "notDetermined"
        }
        let generatedAt = ISO8601DateFormatter().string(from:Date())
        let digest = Bundle.main.executableURL.flatMap { try? Data(contentsOf:$0) }.map { SHA256.hash(data:$0).map { String(format:"%02x",$0) }.joined() } ?? "Unavailable"
        let summary = result.replacingOccurrences(of:" This test does not verify control of another app.",with:"") + (controlTest == "user_confirmed_scroll" ? " You confirmed scrolling worked in another app." : controlTest == "user_reported_no_scroll" ? " You reported that scrolling did not work in another app." : " Other-app scrolling has not been confirmed.")
        message = summary
        let value = DiagnosticReport(schemaVersion:4,generatedAt:generatedAt,executableSHA256:digest,diagnosticBuild:"diagnostics-4",

            appVersion:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown",
            build:Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown",
            macModel:String(cString:model),modelName:DiagnosticHardware.names[String(cString:model)] ?? "Unknown",modelYear:DiagnosticHardware.year(String(cString:model)),chip:DiagnosticHardware.chip(),macOS:ProcessInfo.processInfo.operatingSystemVersionString,
            microphonePermission:permission,accessibilityGranted:AXIsProcessTrusted(),toneHz:tone,digitalAmplitude:amplitude,
            phases:summaries,controlTest:controlTest,result:summary,errorCode:errorCode,
            limitations:"Aggregate measurements only; no raw audio, spectra, personal identifiers, paths, or window information. Device numbers are session-local Core Audio routes. Timing gaps reflect audio delivery and diagnostic processing, not proven hardware dropouts. Thresholds are provisional. Calibration variation is a warning, not proof of hand movement or contamination. Scroll decisions replay the scroll and double-push rules at FFT frame intervals without posting events; this is not exact UI-timer replay and does not validate swipe or zoom. Optional stability checks sample one session; they do not automatically test sleep/wake or all route changes. Nonzero volume is not proof of an emitted tone. This test does not measure room noise sources or automatically verify other-app control. Control results are reported by the user.")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        let details = (try? encoder.encode(value)).flatMap { String(data:$0,encoding:.utf8) } ?? "Report encoding failed."
        report = "Sonar diagnostic report\nGenerated: \(generatedAt)\nVersion: \(value.appVersion) (\(value.build)) · \(value.diagnosticBuild)\nBuild SHA-256: \(digest)\nMac: \(value.modelName)\nModel year: \(value.modelYear)\nChip: \(value.chip)\n\n\(layerSummary.joined(separator:"\n"))\n\nResult: \(summary)\n\nAdditional checks\n\(additionalSummary.joined(separator:"\n"))\n\nApp control check: \(controlTest)\nChecks saved: \(summaries.count)\n\nTechnical details for troubleshooting\n\(details)"
    }
    var additionalSummary: [String] {
        let extra = Array(summaries.dropFirst(3))
        var lines = extra.map { s in
            let name = s.phase == "stability" ? "Extended stillness" : "\(Int(s.frequencyHz)) Hz · \(s.phase == "tone_off" ? "sound off" : "sound on")"
            return "\(name): \(s.status), \(String(format:"%.1f",s.durationSeconds))s of \(Int(s.plannedSeconds))s; \(s.wouldScrollFrames) simulated scrolling frames; \(s.inputErrors) microphone errors; tone contrast \(s.meanContrastDB.map { String(format:"%.1f dB",$0) } ?? "unavailable")."
        }
        if !extra.contains(where:{$0.phase == "stability"}) { lines.append("Extended stillness: not run") }
        if !extra.contains(where:{$0.phase == "tone_on_still"}) { lines.append("Other frequencies: not run") }
        return lines
    }
    var layerSummary: [String] {
        let base = Array(summaries.prefix(3))
        let still = base.first { $0.phase == "tone_on_still" }
        let move = base.first { $0.phase == "movement" }
        let frames = base.reduce(0) { $0 + $1.analyzedFrames }
        let errors = base.reduce(0) { $0 + $1.inputErrors }
        let off = base.first { $0.phase == "tone_off" }
        let heard = still != nil && off != nil && (still!.meanCarrierDB ?? -160) - (off!.meanCarrierDB ?? -160) >= 6 && (still!.meanContrastDB ?? 0) >= 15
        return [
            "Microphone permission: \(AVCaptureDevice.authorizationStatus(for:.audio) == .authorized ? "allowed" : "unavailable")",
            "App control permission: \(AXIsProcessTrusted() ? "allowed" : "unavailable")",
            "Audio delivery: \(frames == 0 ? "no usable readings" : errors > 0 ? "errors detected" : "readings received")",
            "Speaker sound: \(heard ? "detected by microphone" : "not confirmed")",
            "Calibration: \(still == nil ? "not completed" : (still!.calibrationCarrierMax ?? 0) - (still!.calibrationCarrierMin ?? 0) > 12 ? "signal changed during setup" : "no large tone variation measured")",
            "Hand motion: \(move == nil ? "not completed" : move!.motionFrames > 0 ? "detected" : "not detected")",
            "Scroll decisions while still: \(still == nil ? "not completed" : still!.wouldScrollFrames > 0 ? "unwanted scrolling detected" : "no scrolling triggered")",
            "Other-app scrolling: \(controlTest == "not_tested" ? "optional check not run" : controlTest == "user_confirmed_scroll" ? "you confirmed it scrolled" : controlTest == "user_reported_no_scroll" ? "you reported no scrolling" : "waiting for your confirmation")"
        ]
    }
    private func captureCounters() {
        current.durationSeconds = max(0,ProcessInfo.processInfo.systemUptime-phaseStart)
        guard let audio = engine else { return }
        audio.stop()
        current.inputCallbacks = audio.inputCallbacks; current.outputCallbacks = audio.outputCallbacks
        current.inputErrors = audio.inputErrors; current.lastInputError = audio.lastInputError
        current.missingOutputBuffers = audio.missingOutputBuffers
    }
    func continueExtras() {
        if !showExtras { showExtras = true; extraIndex = 0; extraFinished = false }
        else if extraFinished { extraIndex += 1; extraFinished = false }
        if extraIndex >= 3 { showExtras = false; walkthroughComplete = true; stepTitle = "All checks complete"; return }
    }
    func finishAndSave() {
        if testing { finish(Self.result(summaries)) } else { cancel() }
        showExtras = false; walkthroughComplete = true; stepTitle = "Report complete"
        save()
    }
    func extendedCheck(stability: Bool) {
        guard !testing else { return }
        if stability { begin("stability") }
        else { extended = true; frequencyIndex = 0; begin("tone_off") }
    }
    func scheduleControlTest() {
        guard !testing, !controlPending else { return }
        guard AXIsProcessTrusted() else { controlMessage = "Accessibility access is unavailable. Enable it in System Settings, then try again."; return }
        controlPending = true; controlMessage = "Switch to your page now. One scroll will be sent in 5 seconds."
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.controlPending = false
            guard AppControlTarget.frontmost, AXIsProcessTrusted(), let event = SystemScroll.event(pixels:240) else {
                self.controlMessage = "No scroll sent. Switch to another app and try again."; return
            }
            event.post(tap:.cghidEventTap)
            self.controlTest = "event_posted_unconfirmed"
            self.controlMessage = "Did the page scroll? Choose an answer below."
            if !self.report.isEmpty { self.finish(Self.result(self.summaries)) }
        }
        controlTask = task
        DispatchQueue.main.asyncAfter(deadline:.now()+5,execute:task)
    }
    func recordControl(_ worked: Bool) {
        controlTest = worked ? "user_confirmed_scroll" : "user_reported_no_scroll"
        controlMessage = worked ? "Saved: the page scrolled." : "Saved: the page did not scroll."
        extraFinished = true
        if !report.isEmpty { finish(Self.result(summaries)) }
    }
    func save() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "Sonar-diagnostic.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try report.write(to:url,atomically:true,encoding:.utf8) }
        catch { message = "Could not save the report. Try another folder." }
    }
}

struct DiagnosticsView: View {
    @ObservedObject var sonar: Sonar
    @StateObject private var diagnostic: Diagnostics
    init(sonar: Sonar) {
        self.sonar = sonar
        _diagnostic = StateObject(wrappedValue:Diagnostics(tone:sonar.frequency,amplitude:sonar.level))
    }
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text(diagnostic.showExtras && !diagnostic.testing ? "Extra checks · Optional" : diagnostic.stepTitle).font(.title2.bold())
            if diagnostic.testing {
                Image(systemName:diagnostic.movementCue ? "arrow.up.arrow.down" : "hand.raised.fill")
                    .font(.system(size:48)).foregroundStyle(diagnostic.movementCue ? Color.green : Color.secondary)
                    .frame(maxWidth:.infinity)
                Text(diagnostic.movementCue ? "GO · Move your hand" : "Keep still")
                    .font(.title.bold()).frame(maxWidth:.infinity)
                Text(diagnostic.message).font(.body).fixedSize(horizontal:false,vertical:true)
                ProgressView(value:Double(diagnostic.remaining),total:diagnostic.movementCue ? 10 : 30)
                Text(diagnostic.movementCue ? "Keep moving · \(diagnostic.remaining)s left" : "We’ll tell you when to move.").foregroundStyle(.secondary)
                if diagnostic.showExtras { Button("Finish and save report…") { diagnostic.finishAndSave() } }
                Button("Stop test") { diagnostic.finish("Test stopped before completion."); diagnostic.movementCue = false; diagnostic.stepTitle = "Test stopped"; diagnostic.message = "You can start again when you’re ready." }
            } else if diagnostic.readyForMovement {
                Text(diagnostic.message)
                Button("I’m ready") { diagnostic.begin("movement") }.buttonStyle(.borderedProminent)
            } else if diagnostic.report.isEmpty {
                Text("We’ll check permissions, your microphone, the speaker sound, and hand movement. Follow one instruction at a time.")
                Text("Rest your hands away from the keyboard to begin.").fontWeight(.medium)
                Button("Start diagnostic test") { diagnostic.start() }.buttonStyle(.borderedProminent)
            } else if diagnostic.showExtras {
                Text("Extra check \(diagnostic.extraIndex + 1) of 3").foregroundStyle(.secondary)
                if diagnostic.extraFinished {
                    Text("Check saved to your report.").font(.headline)
                    Button(diagnostic.extraIndex == 2 ? "Finish" : "Continue") { diagnostic.continueExtras() }.buttonStyle(.borderedProminent)
                } else if diagnostic.extraIndex == 0 {
                    Text("Check for unwanted scrolling").font(.headline)
                    Text("Rest your hands away from the keyboard for 30 seconds. We’ll check whether Sonar tries to scroll on its own.")
                    Button("I’m ready") { diagnostic.extendedCheck(stability:true) }.buttonStyle(.borderedProminent)
                } else if diagnostic.extraIndex == 1 {
                    Text("Check other sound frequencies").font(.headline)
                    Text("Keep your hands still. We’ll try three sounds to see which ones your microphone picks up. This takes about 45 seconds.")
                    Button("Continue") { diagnostic.extendedCheck(stability:false) }.buttonStyle(.borderedProminent)
                } else {
                    Text("Check scrolling in another app").font(.headline)
                    Text(diagnostic.controlMessage)
                    if diagnostic.controlTest == "event_posted_unconfirmed" {
                        HStack { Button("It scrolled") { diagnostic.recordControl(true) }; Button("It didn’t scroll") { diagnostic.recordControl(false) } }
                    } else {
                        Button("I’m ready") { diagnostic.scheduleControlTest() }.buttonStyle(.borderedProminent).disabled(diagnostic.controlPending)
                    }
                }
                Button("Finish and save report…") { diagnostic.finishAndSave() }
            } else if diagnostic.walkthroughComplete {
                Image(systemName:"checkmark.circle.fill").font(.system(size:42)).foregroundStyle(.green)
                Text("Your final report is ready.").font(.title2.bold())
                Text("It includes your main test and the extra checks you completed.")
                Button("Save final report…") { diagnostic.save() }.buttonStyle(.borderedProminent)
                Text("Send the saved file to Emanuel for troubleshooting.").foregroundStyle(.secondary)
            } else {
                Text(diagnostic.message).font(.headline)
                VStack(alignment:.leading,spacing:8) {
                    ForEach(diagnostic.layerSummary,id: \.self) { Text($0).font(.callout) }
                }
                Button("Save report…") { diagnostic.save() }.buttonStyle(.borderedProminent)
                Text("Your report is ready. Save it now, or add an optional check below.").font(.callout).foregroundStyle(.secondary)
                Button("Continue with extra checks") { diagnostic.continueExtras() }.buttonStyle(.bordered)
                Button("Start a new report") { diagnostic.start() }.disabled(diagnostic.controlPending)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
        .onAppear { sonar.stop(); sonar.diagnosticsOpen = true; sonar.cancelDiagnostics = { diagnostic.cancel(); diagnostic.stepTitle = "Test stopped"; diagnostic.message = "Sound is off." } }
        .onDisappear { diagnostic.cancel(); sonar.cancelDiagnostics = nil; sonar.diagnosticsOpen = false }
    }
}

func testDiagnostics() {
    func sample(_ phase:String, _ carrier:Double, _ contrast:Double, _ motion:Int) -> DiagnosticSampleSummary {
        var s = DiagnosticSampleSummary(phase:phase)
        s.analyzedFrames = 100; s.carrierSum = carrier*100; s.contrastSum = contrast*100; s.motionFrames = motion
        return s
    }
    precondition(DiagnosticHardware.names["Mac14,9"] == "MacBook Pro (14-inch, 2023)")
    precondition(DiagnosticHardware.year("Mac14,9") == "2023")
    precondition(DiagnosticHardware.year("unrecognized") == "Unknown")
    let off = sample("tone_off",-90,2,0)
    let still = sample("tone_on_still",-50,30,0)
    let motion = sample("movement",-50,30,40)
    precondition(Diagnostics.result([]).contains("Not enough"))
    precondition(Diagnostics.result([off,off,motion]).contains("not clearly detected"))
    precondition(Diagnostics.result([off,sample("tone_on_still",-50,30,20),motion]).contains("still test"))
    precondition(Diagnostics.result([off,still,sample("movement",-50,30,0)]).contains("did not register"))
    precondition(Diagnostics.result([off,still,motion]).contains("tone and movement were detected"))
    var failed = still; failed.inputErrors = 1
    precondition(Diagnostics.result([off,failed,motion]).contains("Audio delivery"))
    var alternateOff = off; alternateOff.frequencyHz = 18000
    var alternateStill = still; alternateStill.frequencyHz = 18000
    precondition(Diagnostics.result([off,still,alternateOff,alternateStill,motion]).contains("tone and movement"))
    var phantom = still; phantom.wouldScrollFrames = 4
    precondition(Diagnostics.result([off,phantom,motion]).contains("would have scrolled"))
    var unstable = still; unstable.calibrationCarrierMin = -80; unstable.calibrationCarrierMax = -40
    precondition(Diagnostics.result([off,unstable,motion]).contains("changed during setup"))
    precondition(Diagnostics.result([off,still,motion,alternateOff,alternateStill]).contains("tone and movement"))
    let data = try! JSONEncoder().encode(motion)
    let keys = Set((try! JSONSerialization.jsonObject(with:data) as! [String:Any]).keys)
    precondition(keys == Set(["status","startedAt","durationSeconds","plannedSeconds","calibrationFrames","baselineChangeMaxDB","wouldScrollFrames","wouldScrollPoints","returnStopFrames","directionSwitches","frequencyHz","inputCallbacks","outputCallbacks","inputErrors","lastInputError","missingOutputBuffers","phase","blocks","samples","analyzedFrames","motionFrames","carrierSum","contrastSum","maximumBlockGapMS","inputRate","outputRate","volumeState"]))
    let reportCheck = Diagnostics(tone:20000,amplitude:0.008)
    reportCheck.controlTest = "user_confirmed_scroll"
    reportCheck.finish("Sonar’s tone and movement were detected. This test does not verify control of another app.")
    precondition(reportCheck.report.contains("You confirmed scrolling worked in another app."))
    precondition(reportCheck.report.contains("Generated:") && reportCheck.report.contains("Build SHA-256:"))
    precondition(reportCheck.report.contains("Extended stillness: not run"))
    print("PASS diagnostic result classification, report metadata, optional summary and aggregate-only sample schema")
}

private enum DiagnosticHardware {
    // Apple model identifiers, https://support.apple.com/en-us/108052 (2026-09-11).
    // Unknown models remain explicit; no serial-number lookup or network request.
    static let names: [String:String] = [
        "Mac17,7": "MacBook Pro (14-inch, M5 Pro or M5 Max)",
        "Mac17,9": "MacBook Pro (14-inch, M5 Pro or M5 Max)",
        "Mac17,6": "MacBook Pro (16-inch, M5 Pro or M5 Max)",
        "Mac17,8": "MacBook Pro (16-inch, M5 Pro or M5 Max)",
        "Mac17,2": "MacBook Pro (14-inch, M5)",
        "Mac16,1": "MacBook Pro (14-inch, 2024)",
        "Mac16,6": "MacBook Pro (14-inch, 2024)",
        "Mac16,8": "MacBook Pro (14-inch, 2024)",
        "Mac16,7": "MacBook Pro (16-inch, 2024)",
        "Mac16,5": "MacBook Pro (16-inch, 2024)",
        "Mac15,3": "MacBook Pro (14-inch, Nov 2023)",
        "Mac15,6": "MacBook Pro (14-inch, Nov 2023)",
        "Mac15,8": "MacBook Pro (14-inch, Nov 2023)",
        "Mac15,10": "MacBook Pro (14-inch, Nov 2023)",
        "Mac15,7": "MacBook Pro (16-inch, Nov 2023)",
        "Mac15,9": "MacBook Pro (16-inch, Nov 2023)",
        "Mac15,11": "MacBook Pro (16-inch, Nov 2023)",
        "Mac14,5": "MacBook Pro (14-inch, 2023)",
        "Mac14,9": "MacBook Pro (14-inch, 2023)",
        "Mac14,6": "MacBook Pro (16-inch, 2023)",
        "Mac14,10": "MacBook Pro (16-inch, 2023)",
        "Mac14,7": "MacBook Pro (13-inch, M2, 2022)",
        "MacBookPro18,3": "MacBook Pro (14-inch, 2021)",
        "MacBookPro18,4": "MacBook Pro (14-inch, 2021)",
        "MacBookPro18,1": "MacBook Pro (16-inch, 2021)",
        "MacBookPro18,2": "MacBook Pro (16-inch, 2021)",
        "MacBookPro17,1": "MacBook Pro (13-inch, M1, 2020)",
        "MacBookPro16,3": "MacBook Pro (13-inch, 2020, Two Thunderbolt 3 ports)",
        "MacBookPro16,2": "MacBook Pro (13-inch, 2020, Four Thunderbolt 3 ports)",
        "MacBookPro16,1": "MacBook Pro (16-inch, 2019)",
        "MacBookPro16,4": "MacBook Pro (16-inch, 2019)",
    ]
    static func chip() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string",nil,&size,nil,0) == 0, size > 0 else { return "Unknown" }
        var chars = [CChar](repeating:0,count:size)
        guard sysctlbyname("machdep.cpu.brand_string",&chars,&size,nil,0) == 0 else { return "Unknown" }
        return String(cString:chars)
    }
    static func year(_ id:String) -> String {
        if ["Mac17,7","Mac17,9","Mac17,6","Mac17,8"].contains(id) { return "2026" }
        if id == "Mac17,2" { return "2025" }
        guard let name = names[id], let range = name.range(of:"20[0-9]{2}",options:.regularExpression) else { return "Unknown" }
        return String(name[range])
    }
}
