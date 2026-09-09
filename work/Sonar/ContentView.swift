import AppKit
import SwiftUI

extension DemoMode {
    var symbol: String {
        switch self { case .zoom: return "plus.magnifyingglass"; case .scroll: return "scroll"; case .gallery: return "photo.on.rectangle"; case .position: return "scope"; case .distance: return "ruler"; case .signal: return "waveform.path" }
    }
    var subtitle: String {
        switch self {
        case .zoom: return "Take a closer look by moving your hand."
        case .scroll: return "Scroll through a page without touching your Mac."
        case .gallery: return "Browse photos by moving your hand left and right."
        case .position: return "An experimental estimate from two speaker echoes."
        case .distance: return "Explore echo delay, not exact hand height."
        case .signal: return "Watch changes in the microphone signal."
        }
    }
}

struct ContentView: View {
    @State private var showHowItWorks = false
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
                        ForEach([DemoMode.scroll,.gallery,.zoom]) { mode in Label(mode.rawValue,systemImage:mode.symbol).tag(mode) }
                    }
                    Section("EXPERIMENTS") {
                        ForEach([DemoMode.signal,.distance,.position]) { mode in Label(mode.rawValue,systemImage:mode.symbol).tag(mode) }
                    }
                }.listStyle(.sidebar)
                VStack(alignment:.leading,spacing:14) {
                    Label("Built-in audio",systemImage:"speaker.wave.2").font(.caption).foregroundStyle(.secondary)
                    Button { AudioSettingsWindow.show(sonar) } label: { Label("Audio settings…",systemImage:"slider.horizontal.3") }.buttonStyle(.plain)
                    Button { showHowItWorks.toggle() } label: { Label("How it works",systemImage:"questionmark.circle") }.buttonStyle(.plain)
                        .sheet(isPresented:$showHowItWorks) {
                            VStack(spacing:0) {
                                ScrollView { HowItWorksView() }.frame(width:440,height:550)
                                Button("Done") { showHowItWorks = false }.keyboardShortcut(.defaultAction).padding(.bottom,20)
                            }
                        }
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
                    Button(sonar.running || sonar.starting ? "Stop" : "Start") {
                        if sonar.running || sonar.starting { sonar.stop() } else { sonar.start() }
                    }.buttonStyle(.borderedProminent).tint(sonar.running ? .red : .accentColor).controlSize(.large).frame(minWidth:100)
                }.padding(24)
                Divider()
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
                    SignalView(history:reader.signal,sonar:sonar)
                } else {
                    ControlModeView(sonar:sonar,reader:reader,demo:reader.demo)
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

// Shared structure for the three experimental instruments.
struct ExperimentIntro: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,minHeight:48,alignment:.leading)
    }
}
struct ExperimentStatus: View {
    let text: String
    let symbol: String
    var body: some View {
        Label(text,systemImage:symbol).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth:.infinity,alignment:.leading).padding(12)
            .background(.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
    }
}

struct ExperimentLayout<Toolbar: View, Stage: View, Actions: View, Status: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var toolbar: () -> Toolbar
    @ViewBuilder var stage: () -> Stage
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var status: () -> Status
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            toolbar().frame(height:32)
            ExperimentIntro(title:title,detail:detail)
            GeometryReader { geometry in
                stage().frame(width:geometry.size.width,height:geometry.size.height)
            }.clipped()
            actions().frame(height:32)
            status().frame(height:48)
        }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}

struct HowItWorksView: View {
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("How Sonar works").font(.title2.bold())
            Text("Your Mac plays a high-frequency tone and listens with its microphone. Moving your hand changes the reflected sound. Sonar uses those changes to recognize gestures.").foregroundStyle(.secondary)
            Divider()
            tip("Scroll", "Lift your palm to scroll. Lower it to stop. Double-tap the air—two quick downward pushes—to switch direction. Enable Air double-tap in Scroll.")
            tip("Swipe", "Hold an open hand palm-down above the keyboard. Sweep from one side to the other to move one image. Pause before returning your hand so the return is less likely to count as another swipe. Use Reverse directions if the image moves the wrong way. For Other apps, open a photo in Photos, a browser, or another viewer that supports left/right arrow keys. Keep that app in front.")
            tip("Zoom", "Hold your palm above the keyboard and push it toward the screen to enlarge the image or page. Pull back toward you to zoom back out; a faster pull should make the return faster. Practice here enlarges Yoda to 150%. Other apps sends three zoom-in steps. Pulling back reverses those steps in native apps; browsers return to 100%. The app must support Command-plus/minus zoom. Keep it in front and click outside text fields. Reverse gestures swaps push and pull.")
            Divider()
            Text("Press Start and keep still during the countdown. Use the built-in speakers and microphone. No camera is used.").font(.callout).foregroundStyle(.secondary)
            Text("Experimental: it senses sound changes, not fingers or exact hand position. Audio stays on your Mac.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width:400).fixedSize(horizontal:false,vertical:true)
    }
    private func tip(_ title:String,_ body:String) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.headline)
            Text(body).font(.callout).foregroundStyle(.secondary)
        }
    }
}
