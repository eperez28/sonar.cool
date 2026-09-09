import AppKit
import SwiftUI

struct ControlModeView: View {
    @State private var showZoomHelp = false
    @ObservedObject var sonar: Sonar
    @ObservedObject var reader: Reader
    @ObservedObject var demo: DemoSession
    private var practice: Bool { true }
    private var appName: String {
        "Other apps"
    }
    private var instruction: String {
        switch reader.mode {
        case .scroll: return reader.forward ? "Raise your hand to scroll down the page, then lower it to stop." : "Raise your hand to scroll up the page, then lower it to stop."
        case .gallery: return demo.wave.reversed ? "Move your hand to the left for the next photo, or to the right to go back." : "Move your hand to the right for the next photo, or to the left to go back."
        default: return reader.zoomReversed ? "Pull your hand toward you to zoom in. Move it toward the screen to zoom back out." : "Move your hand toward the screen to zoom in. Pull it back toward you to zoom out."
        }
    }
    private var detail: String {
        switch reader.mode {
        case .scroll:
            return reader.airTapEnabled ? "To change the scrolling direction, tap downward twice in the air without touching the keyboard." : "Double-tap is off. Use the direction button to switch up or down."
        case .gallery:
            return practice ? "Keep your hand above the keyboard with your palm facing the keys. Wait a moment before moving it back so you don’t accidentally change photos again." : "Open a photo in Photos, a browser, or another app first. If your keyboard’s arrow keys change photos, your hand can too. Wait a moment between hand movements."
        default:
            return practice ? "Hold your hand above the keyboard as you move it. The picture gets bigger, then returns to its starting size. Move your hand back faster for a quicker return." : "Open a photo or page in another app. Sonar uses its zoom-in and zoom-out shortcuts as you move your hand."
        }
    }
    private var feedback: String {
        if sonar.starting { return "Starting audio…" }
        if !sonar.running { return "Ready when you are" }
        if sonar.status.contains("Calibrating") { return sonar.status }
        switch reader.mode {
        case .scroll: return reader.action
        case .gallery: return demo.feedback.hasPrefix("Start,") ? "Ready for a swipe" : demo.feedback
        default: return reader.zoomFeedback
        }
    }
    var body: some View {
        ScreenBody {
            VStack(alignment:.leading,spacing:18) {
                Text(instruction).font(.system(size:16,weight:.medium)).fixedSize(horizontal:false,vertical:true)
                Text("Try the preview below. Switch to another app to control it with the same gesture.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if reader.mode == .zoom {
                    Button { showZoomHelp = true } label: {
                        HStack(spacing:10) {
                            Image(systemName:"play.circle.fill")
                                .font(.system(size:18)).foregroundStyle(.secondary)
                            Text("Watch the gesture").font(.system(size:13,weight:.medium))
                        }.padding(.horizontal,10).padding(.vertical,7)
                            .background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:10))
                            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Color.primary.opacity(0.1)))
                            .contentShape(RoundedRectangle(cornerRadius:10))
                    }.buttonStyle(.plain).help("Watch the push and pull gesture")
                        .sheet(isPresented:$showZoomHelp) {
                            AppSheet(title:"Push and pull to zoom",close:{ showZoomHelp = false }) {
                                VStack(alignment:.leading,spacing:20) {
                                    Text("Push toward the screen to zoom in. Pull back toward yourself to zoom out.")
                                        .font(.callout).foregroundStyle(.secondary)
                                    ZoomGesturePreview().frame(height:320).clipped().clipShape(RoundedRectangle(cornerRadius:12))
                                }
                            }
                        }
                }
                Divider()
                HStack(spacing:16) {
                    VStack(alignment:.leading,spacing:4) {
                        Text(sonar.starting || sonar.running ? feedback : "Keep your hand still for the 3-second countdown")
                            .font(.callout.weight(.medium)).fixedSize(horizontal:false,vertical:true)
                        Text(sonar.running ? "Stop anytime with ⌃⌥⌘Space" : "Then move your hand above the keyboard.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if sonar.starting { ProgressView().controlSize(.small) }

                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            HStack {
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:20)
                options
            }
            GeometryReader { space in
                let width = min(space.size.width, ScreenLayout.previewWidth)
                let height = ScreenLayout.previewHeight
                stage.frame(width:width,height:height)
                    .clipShape(RoundedRectangle(cornerRadius:12))
                    .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(.primary.opacity(0.08)))
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
            }.frame(height:ScreenLayout.previewHeight)
            HStack(spacing:10) { actions }.controlSize(.regular).frame(height:32)
            ExperimentStatus(text:feedback,symbol:sonar.running ? "waveform" : "circle.dotted")
        }
    }
    @ViewBuilder private var options: some View {
        switch reader.mode {
        case .scroll:
            Button(reader.forward ? "Direction: ↓" : "Direction: ↑") { reader.switchDirection() }
        case .gallery: WaveDirectionToggle(wave:demo.wave)
        default: Toggle("Reverse gestures",isOn:$reader.zoomReversed).toggleStyle(.switch).controlSize(.small)
        }
    }
    @ViewBuilder private var stage: some View {
        if !practice {
            ZStack {
                Color.primary.opacity(0.025)
                VStack(spacing:18) {
                    Image(systemName:reader.mode.symbol).font(.system(size:56,weight:.light)).foregroundStyle(Color.accentColor)
                    Text("Control \(appName)").font(.title2.weight(.semibold))
                    Text(reader.mode == .scroll ? "Place your mouse pointer over the area you want to scroll." : reader.mode == .gallery ? "Sonar sends arrow keys to the active image viewer." : "Sonar sends zoom shortcuts to the app you’re using.").foregroundStyle(.secondary)
                }.padding(24)
            }
        } else if reader.mode == .scroll {
            PaperView(reader:reader)
        } else {
            GeometryReader { geometry in
                ZStack {
                    Color(nsColor:.controlBackgroundColor)
                    if let photo = previewImage {
                        Image(nsImage:photo).resizable().scaledToFit()
                            .frame(width:geometry.size.width,height:geometry.size.height)
                            .scaleEffect(reader.mode == .zoom ? reader.zoomScale : 1)
                            .animation(.easeOut(duration:0.10),value:reader.zoomScale)
                    }
                }.clipped()
            }
        }
    }
    private var previewImage: NSImage? {
        if reader.mode == .gallery {
            return demo.photos.isEmpty ? nil : demo.photos[demo.galleryIndex % demo.photos.count]
        }
        guard let url = Bundle.main.url(forResource:"yoda",withExtension:"jpeg",subdirectory:"Zoom") else { return nil }
        return NSImage(contentsOf:url)
    }
    @ViewBuilder private var actions: some View {
        switch reader.mode {
        case .scroll:
            if practice {
                Button("Scroll up") { reader.scroll(points:-180) }
                Button("Scroll down") { reader.scroll(points:180) }
            }
            Spacer()
            Toggle("Air double-tap",isOn:$reader.airTapEnabled).toggleStyle(.switch).controlSize(.small)
        case .gallery:
            Button("Previous") { if practice { demo.perform("previous") } else { reader.testAppSwipe(next:false) } }
                .disabled(!practice && !reader.accessibilityGranted)
            Button("Next") { if practice { demo.perform("next") } else { reader.testAppSwipe(next:true) } }
                .disabled(!practice && !reader.accessibilityGranted)
            Spacer()
            if practice {
                Text("\(demo.galleryIndex+1) / \(demo.photos.count)").monospacedDigit().foregroundStyle(.secondary)
                Menu("Photos") {
                    Button("Open images…") { demo.openPhotos() }
                    Button("Sample photos") { demo.loadSamplePhotos() }
                }.fixedSize()
            } else { Text("Uses left / right arrow keys").font(.caption).foregroundStyle(.secondary) }
        default:
            if practice {
                Button("Zoom in") { reader.practiceZoom(3) }
                Button("Reset") { reader.practiceZoom(0) }
            }
            Spacer()
            Text(practice ? "\(Int(reader.zoomScale*100))%" : "Uses the app’s zoom shortcuts").monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

private final class ContainedGestureImageView: NSImageView {
    override var intrinsicContentSize: NSSize { NSSize(width:NSView.noIntrinsicMetric,height:NSView.noIntrinsicMetric) }
}

private struct ZoomGesturePreview: NSViewRepresentable {
    func makeNSView(context:Context) -> NSImageView {
        let view = ContainedGestureImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        if let url = Bundle.main.url(forResource:"push-pull",withExtension:"gif",subdirectory:"Zoom") {
            view.image = NSImage(contentsOf:url)
        }
        return view
    }
    func updateNSView(_ view:NSImageView,context:Context) {}
}
