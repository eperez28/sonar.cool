import AppKit
import SwiftUI

// These demos classify radial motion, not hand position or finger count.
enum DemoMode: String, CaseIterable, Identifiable {
    case scroll = "Scroll", gallery = "Swipe", zoom = "Zoom", signal = "Signal", distance = "Distance", position = "Position"
    var id: String { rawValue }
    var instructions: String {
        switch self {
        case .zoom: return "Push to zoom in; pull to zoom back out. Reverse gestures swaps these."
        case .scroll: return "Lift your palm to scroll in the selected direction; lower it to stop. Two quick downward pushes switch direction."
        case .gallery: return "Sweep your palm sideways above the keyboard to browse. Pause briefly between sweeps. If the page moves the opposite way, use Reverse directions."
        case .position: return "Test independent echoes from both speakers."
        case .distance: return "Measure an experimental echo range with swept tones."
        case .signal: return "Watch the live Doppler signal as you move your hand."
        }
    }
}

struct DemoGestureDetector {
    var direction = ""
    var began = 0.0
    var lastMotion = 0.0
    var lastSample = -Double.infinity
    var quietSince: Double?
    var armed = false
    var lastAction = -Double.infinity
    mutating func feed(_ r: Reading, mode: DemoMode, now: Double) -> String? {
        if now-lastSample > 0.2 { direction = ""; armed = false; quietSince = nil }
        lastSample = now
        guard !r.direction.contains("Calibrating"), r.snr > 15 else {
            direction = ""; armed = false; quietSince = nil; return nil
        }
        let opposed = r.opposedStrength > 0.0003
        let d = opposed ? "BOTH" : r.direction
        let moving = d == "APPROACHING" || d == "MOVING AWAY" || d == "BOTH"
        if !moving {
            if quietSince == nil { quietSince = now }
            if now-(quietSince ?? now) >= 0.22 && now-lastAction > 0.55 { armed = true }
        } else { quietSince = nil }
        guard armed else { direction = ""; return nil }
        if direction.isEmpty && moving { direction = d; began = now; lastMotion = now }
        if d == direction { lastMotion = now }
        if now-lastMotion > 0.16 && direction == "BOTH" { direction = ""; return nil }
        let length = lastMotion-began
        var event: String?
        if !direction.isEmpty && d != direction && now-lastMotion >= 0.065 {
            if length >= 0.055 && length <= 0.65 {
                if mode == .gallery {
                    event = direction == "APPROACHING" ? "next" : direction == "MOVING AWAY" ? "previous" : nil

                }
            }
            direction = ""
        }
        if event != nil { armed = false; direction = ""; lastAction = now; quietSince = nil }
        return event
    }
}

final class DemoSession: ObservableObject {
    let wave = WaveCalibration()
    var galleryOutput: ((String)->Bool?)?
    @Published var feedback = "Start, stay still for 3 seconds, then try a gesture."
    @Published var inputFeedback = "Waiting for audio"
    @Published var galleryIndex = 0
    @Published var photos: [NSImage] = []
    init() { loadSamplePhotos() }
    func loadSamplePhotos() {
        photos = (1...5).compactMap { index in
            guard let url = Bundle.main.url(forResource:String(format:"%02d",index),withExtension:"jpg",subdirectory:"Gallery") else { return nil }
            return NSImage(contentsOf:url)
        }
        galleryIndex = 0; resetInput()
    }
    @Published var lastNavigation = "↔"
    @Published var changes = 0
    private var detector = DemoGestureDetector()
    func resetInput() { wave.resetInput(); detector = DemoGestureDetector() }
    func consume(_ r: Reading, mode: DemoMode, now: Double) {
        if mode == .gallery && wave.enabled {
            let state = r.direction.contains("Calibrating") ? "Calibrating · stay still" : "Wave control active"
            if inputFeedback != state { inputFeedback = state }
            if let event = wave.consume(r,now:now) { perform(event,manual:false) }; return
        }
        if let event = detector.feed(r,mode:mode,now:now) { perform(event,manual:false) }
        let next = r.direction.contains("Calibrating") ? "Calibrating · stay still" : !detector.armed ? "Hold still briefly to re-arm" : detector.direction.isEmpty ? "Ready for a gesture" : "Tracking: \(detector.direction.lowercased())"
        if inputFeedback != next { inputFeedback = next }
    }
    func perform(_ event: String, manual: Bool = true) {
        if !manual && (event == "next" || event == "previous"), let sent = galleryOutput?(event) {
            if sent { changes += 1; lastNavigation = event == "next" ? "→" : "←" }
            feedback = sent ? "App · \(event.capitalized) · #\(changes)" : "App paused · click the gallery image, outside text fields"
            return
        }
        switch event {
        case "next": galleryIndex = (galleryIndex+1) % (photos.isEmpty ? 5 : photos.count)
        case "previous": galleryIndex = (galleryIndex+(photos.isEmpty ? 5 : photos.count)-1) % (photos.isEmpty ? 5 : photos.count)
        default: return
        }
        lastNavigation = event == "next" ? "→" : "←"
        changes += 1
        feedback = "\(manual ? "Button" : "Gesture") · \(event.capitalized) · #\(changes)"
    }
    func openPhotos() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let loaded = panel.urls.compactMap { NSImage(contentsOf:$0) }
        if !loaded.isEmpty { photos = loaded; galleryIndex = 0 }
        resetInput()
    }
}

struct DemoPanel: View {
    @ObservedObject var demo: DemoSession
    let mode: DemoMode
    var body: some View {
        VStack(spacing:20) {
            if !demo.feedback.hasPrefix("Start,") { Text(demo.feedback.components(separatedBy:" · ").prefix(2).joined(separator:" · ")).font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }
            switch mode {
            case .gallery:
                Text("Sweep your palm sideways. Pause briefly between waves.").font(.callout).foregroundStyle(.secondary)
                ZStack {
                    RoundedRectangle(cornerRadius:16).fill(Color.black.opacity(0.95))
                    if !demo.photos.isEmpty {
                        Image(nsImage:demo.photos[demo.galleryIndex % demo.photos.count]).resizable().scaledToFit().padding(6)
                    } else {
                        Text("Open some photos to get started.").foregroundStyle(.white)
                    }
                }.frame(maxHeight:.infinity)
                HStack { Button("Previous") { demo.perform("previous") }; Text("\(demo.galleryIndex+1) / \(demo.photos.isEmpty ? 5 : demo.photos.count)"); Button("Next") { demo.perform("next") }; Spacer(); Button("Sample photos") { demo.loadSamplePhotos() }; Button("Open images…") { demo.openPhotos() } }
            case .zoom, .scroll, .signal, .distance, .position: EmptyView()
            }
            Text("Keep this window in front while practicing.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}

func testDemoModes() {
    for (mode,dir,frames,expected) in [(DemoMode.gallery,"APPROACHING",10,"next"),(.gallery,"MOVING AWAY",10,"previous")] {
        var detector = DemoGestureDetector(); var events:[String] = []; var time = 0.0
        func feed(_ d:String,_ count:Int) {
            for _ in 0..<count {
                let r = Reading(spectrum:[],baseline:[],direction:d,carrierDB:0,snr:40,strength:0.004)
                if let e = detector.feed(r,mode:mode,now:time) { events.append(e) }; time += 0.02
            }
        }
        feed("Still",40); feed(dir,frames); feed("Still",8)
        feed(dir == "APPROACHING" ? "MOVING AWAY" : "APPROACHING",20)
        testCheck(events == [expected],"Demo gesture / return suppression: \(mode) \(events)")
    }
    let session = DemoSession(); testCheck(session.photos.count == 5,"Bundled gallery photos missing"); session.photos = [NSImage(size:NSSize(width:1,height:1)),NSImage(size:NSSize(width:1,height:1))]
    session.perform("previous"); testCheck(session.galleryIndex == 1)
    session.perform("next"); testCheck(session.galleryIndex == 0)
    var delivered: [String] = []
    session.galleryOutput = { event in delivered.append(event); return true }
    session.perform("next",manual:false)
    testCheck(delivered == ["next"] && session.galleryIndex == 0,"External gallery action leaked into local gallery")
    session.galleryOutput = { _ in false }
    let countBefore = session.changes
    session.perform("previous",manual:false)
    testCheck(session.changes == countBefore,"Blocked output reported as delivered")
    print("PASS gallery gesture timing, return suppression, wraparound and external delivery")
}
