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
        case .distance: return "Explore experimental echo-delay estimates."
        case .signal: return "Watch changes in the microphone signal."
        }
    }
}

struct ContentView: View {
    @State private var showHowItWorks = false
    @State private var showAudioSettings = false
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
                    Button { showAudioSettings = true } label: { Label("Audio settings…",systemImage:"slider.horizontal.3") }.buttonStyle(.plain)
                    Button { showHowItWorks.toggle() } label: { Label("How it works",systemImage:"questionmark.circle") }.buttonStyle(.plain)
                        .sheet(isPresented:$showHowItWorks) {
                            AppSheet(title:"How Sonar works",close:{ showHowItWorks = false }) { HowItWorksView() }
                        }
                    Color.clear.frame(height:0).sheet(isPresented:$showAudioSettings) {
                        AppSheet(title:"Audio settings",close:{ showAudioSettings = false }) { AudioSettingsView(sonar:sonar) }
                    }
                    Text("Stop anywhere  ⌃⌥⌘Space").font(.system(size:10)).foregroundStyle(.secondary)
                }.padding(20)
            }.frame(width:195).background(.regularMaterial)
            Divider()
            VStack(spacing:0) {
                HStack(alignment:.center,spacing:20) {
                    Button {
                        if sonar.running || sonar.starting { sonar.stop() } else { sonar.start() }
                    } label: {
                        Label(sonar.running || sonar.starting ? "Stop" : "Start",systemImage:sonar.running || sonar.starting ? "stop.fill" : "play.fill")
                            .font(.system(size:17,weight:.semibold)).frame(minWidth:110,minHeight:30)
                    }.buttonStyle(.borderedProminent).tint(sonar.running || sonar.starting ? .red : .accentColor).controlSize(.large)
                    VStack(alignment:.leading,spacing:4) {
                        Text(reader.mode.rawValue).font(.system(size:26,weight:.semibold))
                        Text(reader.mode.subtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing:7) {
                        Circle().fill(sonar.running ? Color.mint : Color.secondary.opacity(0.5)).frame(width:6,height:6)
                        Text(sonar.starting ? "Starting" : sonar.running ? ((sonar.status.contains("Calibrating") || sonar.status.contains("Measuring empty desk")) ? "Calibrating" : "Active") : "Stopped").font(.callout)
                    }.foregroundStyle(.secondary)

                }.padding(.horizontal,ScreenLayout.inset).padding(.vertical,24).frame(maxWidth:ScreenLayout.width).frame(maxWidth:.infinity)
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
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

// Shared structure for the three experimental instruments.
struct ExperimentIntro: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.system(size:16,weight:.medium))
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

enum ScreenLayout {
    static let width: CGFloat = 880
    static let previewHeight: CGFloat = 320
    static let spacing: CGFloat = 24
    static let inset: CGFloat = 32
}

struct ScreenBody<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:ScreenLayout.spacing) { content() }
                .padding(ScreenLayout.inset)
                .frame(maxWidth:ScreenLayout.width)
                .frame(maxWidth:.infinity,alignment:.top)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
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
        ScreenBody {
            ExperimentIntro(title:title,detail:detail)
            toolbar().frame(minHeight:32)
            GeometryReader { geometry in
                stage().frame(width:geometry.size.width,height:geometry.size.height)
            }.frame(height:ScreenLayout.previewHeight).clipped()
            actions().frame(height:32)
            status().frame(height:48)
        }
    }
}

struct HowItWorksView: View {
    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            tip("Sound and movement", "Sonar plays a steady tone through your Mac’s speakers. Your hand reflects it back to the microphone. Moving toward the Mac raises the reflected frequency; moving away lowers it. This Doppler shift lets Sonar detect movement.")
            tip("Start", "Choose a control and press Start. Keep still for the three-second countdown, then move your palm above the keyboard. Practice in Sonar or switch to the app you want to control.")
            tip("Scroll", "Lift your palm to scroll and lower it to stop. Enable Air double-tap to change direction with two quick downward pushes.")
            tip("Swipe", "Sweep sideways to change photos. Pause before returning your hand. Reverse directions swaps the mapping. External viewers need left/right arrow-key support.")
            tip("Zoom", "Push toward the screen to zoom in and pull back to zoom out. Reverse gestures swaps the mapping. External apps need Command-plus/minus support; browsers return to 100%.")
            tip("Sound and privacy", "Use the built-in speakers and microphone. Stop if the tone feels uncomfortable, and use it away from pets. Audio is processed locally. This is an experiment in progress.")
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func tip(_ title:String,_ body:String) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(.headline)
            Text(body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}

struct AppSheet<Content: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text(title).font(.system(size:20,weight:.semibold))
                Spacer()
                Button(action:close) { Image(systemName:"xmark").font(.system(size:13,weight:.semibold)).frame(width:30,height:30) }
                    .buttonStyle(.borderless).accessibilityLabel("Close \(title)")
            }.padding(.horizontal,24).padding(.vertical,16)
            Divider()
            ScrollView { content().padding(24).frame(maxWidth:.infinity,alignment:.leading) }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
            Divider()
            HStack { Spacer(); Button("Done",action:close).buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.cancelAction) }.padding(16)
        }.frame(width:500,height:560).background(Color(nsColor:.windowBackgroundColor))
    }
}
