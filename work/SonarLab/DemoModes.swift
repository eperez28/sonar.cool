import AppKit
import SwiftUI

// These demos classify radial motion, not hand position or finger count.
enum DemoMode: String, CaseIterable, Identifiable {
    case scroll = "Scroll", gallery = "Gallery", blocks = "Blocks", presence = "Presence", signal = "Signal", distance = "Distance", position = "Position"
    var id: String { rawValue }
    var instructions: String {
        switch self {
        case .scroll: return "Lift your hand to scroll; lower to reset. Two quick pushes reverse direction."
        case .gallery: return "Sweep your palm sideways above the keyboard to browse. Pause briefly between sweeps. If the page moves the opposite way, use Reverse directions."
        case .blocks: return "Quick push: right. Slow push: left. Pull away steadily: drop. Move two palms in opposite directions: rotate (experimental). Pause between gestures."
        case .position: return "Test independent echoes from both speakers."
        case .distance: return "Measure an experimental echo range with swept tones."
        case .signal: return "Watch the live Doppler signal as you move your hand."
        case .presence: return "Walk away from the laptop to dim this preview. Walk toward it to wake the preview. Keep the window active. This does not lock or unlock macOS."
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
        if now-lastMotion > 0.16 && (mode == .presence || direction == "BOTH") { direction = ""; return nil }
        let length = lastMotion-began
        var event: String?
        if mode == .presence {
            if length >= 0.55 { event = direction == "MOVING AWAY" ? "depart" : direction == "APPROACHING" ? "arrive" : nil }
        } else if mode == .blocks && direction == "BOTH" && length >= 0.12 {
            event = "rotate"
        } else if mode == .blocks && direction == "MOVING AWAY" && length >= 0.38 {
            event = "drop"
        } else if !direction.isEmpty && d != direction && now-lastMotion >= 0.065 {
            if length >= 0.055 && length <= 0.65 {
                if mode == .gallery {
                    event = direction == "APPROACHING" ? "next" : direction == "MOVING AWAY" ? "previous" : nil
                } else if mode == .blocks && direction == "APPROACHING" {
                    event = length < 0.24 ? "right" : "left"
                }
            }
            direction = ""
        }
        if event != nil { armed = false; direction = ""; lastAction = now; quietSince = nil }
        return event
    }
}

struct BlockCell: Hashable { var x: Int; var y: Int }
struct BlocksGame {
    static let shapes: [[BlockCell]] = [
        [.init(x:0,y:0),.init(x:1,y:0),.init(x:2,y:0),.init(x:3,y:0)],
        [.init(x:0,y:0),.init(x:1,y:0),.init(x:0,y:1),.init(x:1,y:1)],
        [.init(x:1,y:0),.init(x:0,y:1),.init(x:1,y:1),.init(x:2,y:1)],
        [.init(x:0,y:0),.init(x:0,y:1),.init(x:1,y:1),.init(x:2,y:1)],
        [.init(x:1,y:0),.init(x:2,y:0),.init(x:0,y:1),.init(x:1,y:1)]
    ]
    var settled = Set<BlockCell>()
    var shape = shapes[2]
    var x = 3, y = 0, lines = 0, pieces = 0
    var over = false
    var cells: [BlockCell] { shape.map { .init(x:$0.x+x,y:$0.y+y) } }
    func fits(_ shape: [BlockCell], x: Int, y: Int) -> Bool {
        shape.allSatisfy { let p = BlockCell(x:$0.x+x,y:$0.y+y); return p.x >= 0 && p.x < 10 && p.y >= 0 && p.y < 20 && !settled.contains(p) }
    }
    mutating func move(_ dx: Int) { if !over && fits(shape,x:x+dx,y:y) { x += dx } }
    mutating func rotate() {
        guard !over else { return }
        let rotated = shape.map { BlockCell(x:2-$0.y,y:$0.x) }
        for shift in [0,-1,1,-2,2] where fits(rotated,x:x+shift,y:y) { shape = rotated; x += shift; return }
    }
    mutating func step() {
        guard !over else { return }
        if fits(shape,x:x,y:y+1) { y += 1 } else { lock() }
    }
    mutating func drop() { guard !over else { return }; while fits(shape,x:x,y:y+1) { y += 1 }; lock() }
    mutating func lock() {
        settled.formUnion(cells)
        let full = (0..<20).filter { row in (0..<10).allSatisfy { settled.contains(.init(x:$0,y:row)) } }
        settled = Set(settled.filter { !full.contains($0.y) }.map { p in .init(x:p.x,y:p.y+full.filter { $0 > p.y }.count) })
        lines += full.count; pieces += 1
        shape = Self.shapes[pieces % Self.shapes.count]; x = 3; y = 0
        over = !fits(shape,x:x,y:y)
    }
}

final class DemoSession: ObservableObject {
    let wave = WaveCalibration()
    var galleryOutput: ((String)->Bool?)?
    @Published var feedback = "Start, stay still for 3 seconds, then try a gesture."
    @Published var inputFeedback = "Waiting for audio"
    @Published var galleryIndex = 0
    @Published var photos: [NSImage] = []
    @Published var game = BlocksGame()
    @Published var dimmed = false
    @Published var changes = 0
    @Published var gravity = false
    private var detector = DemoGestureDetector()
    private var fallTime = 0.0
    func resetInput() { wave.resetInput(); detector = DemoGestureDetector(); fallTime = 0 }
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
    func tick(_ dt: Double, mode: DemoMode) {
        guard mode == .blocks && gravity else { return }
        fallTime += dt
        if fallTime >= 0.85 { fallTime = 0; game.step() }
    }
    func perform(_ event: String, manual: Bool = true) {
        if !manual && (event == "next" || event == "previous"), let sent = galleryOutput?(event) {
            if sent { changes += 1 }
            feedback = sent ? "Chrome · \(event.capitalized) · #\(changes)" : "Chrome paused · click the gallery image, outside text fields"
            return
        }
        switch event {
        case "next": galleryIndex = (galleryIndex+1) % (photos.isEmpty ? 5 : photos.count)
        case "previous": galleryIndex = (galleryIndex+(photos.isEmpty ? 5 : photos.count)-1) % (photos.isEmpty ? 5 : photos.count)
        case "left": game.move(-1)
        case "right": game.move(1)
        case "rotate": game.rotate()
        case "drop": game.drop()
        case "depart": dimmed = true
        case "arrive": dimmed = false
        default: return
        }
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
    private let names = ["Alpine morning", "Desert dusk", "Ocean blue", "Forest light", "After hours"]
    private let icons = ["mountain.2.fill", "sun.haze.fill", "water.waves", "tree.fill", "moon.stars.fill"]
    private let colors: [Color] = [.cyan,.orange,.blue,.green,.purple]
    var body: some View {
        VStack(spacing:20) {
            if !demo.feedback.hasPrefix("Start,") { Text(demo.feedback.components(separatedBy:" · ").prefix(2).joined(separator:" · ")).font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }
            switch mode {
            case .gallery:
                Text("Sweep your palm sideways. Pause briefly between waves.").font(.callout).foregroundStyle(.secondary)
                ZStack {
                    RoundedRectangle(cornerRadius:24).fill(LinearGradient(colors:[colors[demo.galleryIndex % 5].opacity(0.7),.black],startPoint:.topLeading,endPoint:.bottomTrailing))
                    if !demo.photos.isEmpty {
                        Image(nsImage:demo.photos[demo.galleryIndex % demo.photos.count]).resizable().scaledToFit().padding(20)
                    } else {
                        VStack(spacing:24) { Image(systemName:icons[demo.galleryIndex % 5]).font(.system(size:110)); Text(names[demo.galleryIndex % 5]).font(.largeTitle) }
                    }
                }.frame(maxHeight:.infinity)
                HStack { Button("Previous") { demo.perform("previous") }; Text("\(demo.galleryIndex+1) / \(demo.photos.isEmpty ? 5 : demo.photos.count)"); Button("Next") { demo.perform("next") }; Spacer(); Button("Open images…") { demo.openPhotos() } }
            case .blocks:
                HStack(alignment:.top,spacing:24) {
                    Canvas { context,size in
                        let unit = min(size.width/10,size.height/20)
                        for row in 0..<20 { for col in 0..<10 {
                            let p = BlockCell(x:col,y:row)
                            let color: Color = demo.game.settled.contains(p) ? .cyan : demo.game.cells.contains(p) ? .mint : .white.opacity(0.055)
                            context.fill(Path(roundedRect:CGRect(x:Double(col)*unit+1,y:Double(row)*unit+1,width:unit-2,height:unit-2),cornerRadius:3),with:.color(color))
                        } }
                    }.aspectRatio(0.5,contentMode:.fit)
                    VStack(alignment:.leading,spacing:16) {
                        Text("\(demo.game.lines) lines").font(.title2)
                        Text("\(demo.game.pieces) pieces").foregroundStyle(.secondary)
                        if demo.game.over { Text("Game over").foregroundStyle(.orange) }
                        Toggle("Gravity",isOn:$demo.gravity)
                        Text("Gravity starts off so you can learn each gesture.").font(.caption).foregroundStyle(.secondary)
                        Button("New game") { demo.game = BlocksGame(); demo.resetInput() }
                    }.frame(width:140)
                }
                HStack { ForEach(["left","right","rotate","drop"],id:\.self) { event in Button(event.capitalized) { demo.perform(event) } } }
            case .presence:
                ZStack {
                    RoundedRectangle(cornerRadius:24).fill(demo.dimmed ? Color.black : Color.mint.opacity(0.12))
                    VStack(spacing:22) {
                        Image(systemName:demo.dimmed ? "moon.zzz.fill" : "sun.max.fill").font(.system(size:90))
                        Text(demo.dimmed ? "Away" : "Welcome back").font(.largeTitle.bold())
                        Text(demo.dimmed ? "Walk toward the laptop to wake this preview." : "Walk away to dim this preview.").foregroundStyle(.secondary)
                        Text("Preview only · your Mac stays unlocked").font(.caption)
                    }.padding().opacity(demo.dimmed ? 0.35 : 1)
                }.frame(maxHeight:.infinity)
                HStack { Button("Simulate away") { demo.perform("depart") }; Button("Simulate return") { demo.perform("arrive") } }
            case .scroll, .signal, .distance, .position: EmptyView()
            }
            Text(mode == .blocks ? mode.instructions : "Keep this window in front while practicing.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}

func testDemoModes() {
    var game = BlocksGame()
    for _ in 0..<20 { game.move(-1) }
    testCheck(game.cells.allSatisfy { $0.x >= 0 })
    game.rotate(); testCheck(game.fits(game.shape,x:game.x,y:game.y))
    game.drop(); testCheck(game.pieces == 1 && game.settled.count == 4)
    game = BlocksGame(); game.settled = Set((0..<10).filter { !(3...6).contains($0) }.map { BlockCell(x:$0,y:19) }); game.shape = BlocksGame.shapes[0]; game.drop()
    testCheck(game.lines == 1 && game.settled.isEmpty)
    for (mode,dir,frames,expected) in [(DemoMode.gallery,"APPROACHING",10,"next"),(.blocks,"APPROACHING",8,"right"),(.blocks,"APPROACHING",18,"left"),(.blocks,"MOVING AWAY",25,"drop"),(.presence,"MOVING AWAY",40,"depart")] {
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
    var bilateral = DemoGestureDetector(); var rotations = 0
    for frame in 0..<80 {
        let both = frame >= 40
        let r = Reading(spectrum:[],baseline:[],direction:both ? "Mixed movement" : "Still",carrierDB:0,snr:40,strength:both ? 0.004 : 0,opposedStrength:both ? 0.004 : 0)
        if bilateral.feed(r,mode:.blocks,now:Double(frame)*0.02) == "rotate" { rotations += 1 }
    }
    testCheck(rotations == 1,"Two-sided motion repeated rotation")
    let session = DemoSession(); session.photos = [NSImage(size:NSSize(width:1,height:1)),NSImage(size:NSSize(width:1,height:1))]
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
    print("PASS demo gesture timing, return suppression, block collisions and line clear")
}
