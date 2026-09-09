import AppKit
import SwiftUI

extension DemoMode {
    var symbol: String {
        switch self { case .scroll: return "scroll"; case .gallery: return "photo.on.rectangle"; case .position: return "scope"; case .distance: return "ruler"; case .signal: return "waveform.path" }
    }
    var subtitle: String {
        switch self {
        case .scroll: return "Read with a lift of your hand."
        case .gallery: return "Browse images with a wave."
        case .position: return "Experimental two-speaker positioning."
        case .distance: return "Explore acoustic distance measurement."
        case .signal: return "See the sound your hand reflects."
        }
    }
}

struct ContentView: View {
    @ObservedObject var sonar: Sonar
    @ObservedObject var reader: Reader
    init(sonar: Sonar) { self.sonar = sonar; reader = sonar.reader }
    private var selection: Binding<DemoMode?> {
        Binding(get:{ reader.mode },set:{ mode in
            guard let mode, mode != reader.mode else { return }
            sonar.stop(); reader.mode = mode
        })
    }
    private var isExternal: Bool { reader.usesExternalControl }
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:10) {
                    if let url = Bundle.main.url(forResource:"SonarMark",withExtension:"png"), let mark = NSImage(contentsOf:url) {
                        Image(nsImage:mark).resizable().scaledToFit().frame(width:36,height:36).clipShape(RoundedRectangle(cornerRadius:8))
                    }
                    Text("Sonar").font(.system(size:20,weight:.semibold))
                }.padding(22)
                List(selection:selection) {
                    Section("CONTROLS") {
                        ForEach([DemoMode.scroll,.gallery]) { mode in Label(mode.rawValue,systemImage:mode.symbol).tag(mode) }
                    }
                    Section("EXPERIMENTS") {
                        ForEach([DemoMode.signal,.distance,.position]) { mode in Label(mode.rawValue,systemImage:mode.symbol).tag(mode) }
                    }
                }.listStyle(.sidebar)
                VStack(alignment:.leading,spacing:14) {
                    Label("Built-in audio",systemImage:"speaker.wave.2").font(.caption).foregroundStyle(.secondary)
                    Button { AudioSettingsWindow.show(sonar) } label: { Label("Audio settings…",systemImage:"slider.horizontal.3") }.buttonStyle(.plain)
                    Text("Stop anywhere  ⌃⌥⌘Space").font(.system(size:10)).foregroundStyle(.secondary)
                }.padding(20)
            }.frame(width:195).background(.regularMaterial)
            Divider()
            VStack(spacing:0) {
                HStack(alignment:.center) {
                    VStack(alignment:.leading,spacing:4) {
                        Text(reader.mode.rawValue).font(.system(size:26,weight:.semibold))
                        Text(reader.mode.subtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing:7) {
                        Circle().fill(sonar.running ? Color.mint : Color.secondary.opacity(0.5)).frame(width:6,height:6)
                        Text(sonar.starting ? "Starting" : sonar.running ? ((sonar.status.contains("Calibrating") || sonar.status.contains("Measuring empty desk")) ? "Calibrating" : "Active") : "Stopped").font(.callout)
                    }.foregroundStyle(.secondary)
                    if reader.mode != .distance || sonar.running || sonar.starting {
                    Button(sonar.running || sonar.starting ? "Stop" : "Start") {
                        if sonar.running || sonar.starting { sonar.stop() } else { sonar.start() }
                    }.buttonStyle(.borderedProminent).tint(sonar.running ? .red : .accentColor).controlSize(.large).frame(minWidth:78)
                    }
                }.padding(24)
                Divider()
                HStack {
                    if reader.mode == .gallery {
                        Picker("Control",selection:$reader.chromeGallery) { Text("Chrome").tag(true); Text("Practice here").tag(false) }.pickerStyle(.segmented).frame(width:260)
                        Spacer()
                        WaveDirectionToggle(wave:reader.demo.wave)
                    } else if reader.mode == .scroll {
                        Picker("Control",selection:$reader.systemWide) { Text("Other apps").tag(true); Text("Practice here").tag(false) }.pickerStyle(.segmented).frame(width:260)
                        Spacer()
                        Button(reader.forward ? "Direction: Down ↓" : "Direction: Up ↑") { reader.switchDirection() }
                    } else {
                        Label((reader.mode == .signal || reader.mode == .distance) ? "Live measurements" : "Practice in this window",systemImage:"macwindow").foregroundStyle(.secondary)
                        Spacer()
                    }
                }.padding(.horizontal,24).padding(.vertical,16)
                if isExternal && !reader.accessibilityGranted {
                    HStack { Text("Allow Accessibility access to control other apps."); Spacer(); Button("Open Settings") { reader.openAccessibilitySettings() } }.padding(16).background(.orange.opacity(0.12))
                }
                if !sonar.running && !sonar.starting && sonar.status != "Ready — sound is off" && sonar.status != "Stopped — sound is off" {
                    Text(sonar.status).foregroundStyle(.orange).padding(.horizontal,24).fixedSize(horizontal:false,vertical:true)
                }
                if reader.mode == .position {
                    PositionView(model:sonar.position,sonar:sonar)
                } else if reader.mode == .distance {
                    DistanceView(model:sonar.distance,sonar:sonar)
                } else if reader.mode == .signal {
                    SignalView(history:reader.signal)
                } else if isExternal {
                    ExternalControlView(sonar:sonar,reader:reader,demo:reader.demo)
                } else if reader.mode == .scroll {
                    VStack(spacing:12) {
                        Text("Lift to scroll. Lower your hand to reset. Two quick pushes reverse direction.").font(.callout).foregroundStyle(.secondary)
                        PaperView(reader:reader).clipShape(RoundedRectangle(cornerRadius:12))
                    }.padding(24)
                } else {
                    DemoPanel(demo:reader.demo,mode:reader.mode)
                }
                HStack {
                    Text(sonar.running ? "Runs until you stop it." : "Start, then keep still for 3 seconds.")
                    Spacer()
                    Text("Audio stays on your Mac.")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,24).padding(.vertical,14)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(minWidth:860,minHeight:620)
        .onExitCommand { sonar.stop() }
    }
}

struct WaveDirectionToggle: View {
    @ObservedObject var wave: WaveCalibration
    var body: some View { Toggle("Reverse directions",isOn:$wave.reversed).toggleStyle(.switch).controlSize(.small) }
}

struct ExternalControlView: View {
    @ObservedObject var sonar: Sonar
    @ObservedObject var reader: Reader
    @ObservedObject var demo: DemoSession
    private var gallery: Bool { reader.mode == .gallery }
    private var feedback: String {
        if !sonar.running { return "Ready when you are" }
        if sonar.status.contains("Calibrating") { return "Hold still for a moment" }
        if gallery {
            if demo.feedback.hasPrefix("Chrome ·") { return demo.feedback.components(separatedBy:" · ").prefix(2).joined(separator:" · ") }
            if demo.feedback.hasPrefix("Chrome paused") { return "Click the gallery image to continue" }
            return "Ready for a wave"
        }
        return reader.action
    }
    var body: some View {
        VStack(spacing:22) {
            Spacer(minLength:8)
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.08)).frame(width:120,height:120)
                Image(systemName:gallery ? "hand.wave" : "hand.raised").font(.system(size:52,weight:.light)).foregroundStyle(Color.accentColor)
            }
            VStack(spacing:10) {
                Text(gallery ? "Your gallery is in Chrome" : "Scroll in your favorite app").font(.system(size:25,weight:.semibold))
                Text(gallery ? "Open an image, click it, then sweep your palm sideways." : "Point at the area to scroll. Lift your hand; lower it to reset.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth:410).fixedSize(horizontal:false,vertical:true)
            }
            if gallery {
                HStack(spacing:12) {
                    Button { reader.testChrome(next:false) } label: { Label("Previous",systemImage:"arrow.left") }
                    Button { reader.testChrome(next:true) } label: { Label("Next",systemImage:"arrow.right") }
                }.controlSize(.large).disabled(!reader.accessibilityGranted)
                Text("Buttons test Chrome. The gallery must support ← and → keys.").font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle("Double push to reverse",isOn:$reader.airTapEnabled).toggleStyle(.switch).fixedSize()
            }
            Spacer(minLength:8)
            Label(feedback,systemImage:sonar.running ? "waveform" : "circle.dotted").font(.callout).foregroundStyle(.secondary)
                .padding(14).frame(maxWidth:.infinity).background(.quaternary.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius:12))
        }.padding(28).frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}

final class AudioSettingsWindow {
    private static var window: NSWindow?
    static func show(_ sonar: Sonar) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let panel = NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:500),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        panel.title = "Audio Settings"; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView:AudioSettingsView(sonar:sonar))
        window = panel; panel.center(); panel.makeKeyAndOrderFront(nil)
    }
}

struct AudioSettingsView: View {
    @ObservedObject var sonar: Sonar
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("Audio & signal").font(.title2.bold())
            Text("Use the built-in speakers and microphone. Stop Sonar before changing the tone.").foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Picker("Frequency",selection:$sonar.frequency) { ForEach([18000.0,19000.0,20000.0,21000.0],id:\.self) { Text("\(Int($0/1000)) kHz").tag($0) } }.disabled(sonar.running || sonar.starting)
            VStack(alignment:.leading) {
                Text("Signal level · \(String(format:"%.1f",sonar.level*100))%")
                Slider(value:$sonar.level,in:0.002...0.04).disabled(sonar.running || sonar.starting)
            }
            Spectrum(reading:sonar.reading).frame(height:95).background(Color.black.opacity(0.8)).clipShape(RoundedRectangle(cornerRadius:8))
            Text(sonar.status).font(.caption)
            Text(sonar.route).font(.caption).foregroundStyle(.secondary)
            Text("Experimental. Stop if the tone is audible or uncomfortable. Microphone audio is not saved.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(24).frame(width:440)
    }
}
