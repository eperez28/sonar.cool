import SwiftUI

struct SignalFrame {
    let time: Double
    let power: [Double]
    let spectrum: [Float]
    let waveform: [Float]
    let sampleRate: Double
    let firstFrequency: Double
    let binWidth: Double
    let carrierDB: Float
}
final class SignalHistory: ObservableObject {
    @Published private(set) var frames: [SignalFrame] = []
    func append(_ reading: Reading, now: Double) {
        guard now-(frames.last?.time ?? -.infinity) >= 0.055 else { return }
        guard !reading.spectrum.isEmpty, reading.spectrum.count == reading.baseline.count else { return }
        let center = reading.spectrum.count/2
        // Positive power above the measured baseline, relative to carrier power.
        let carrier = pow(10,Double(reading.carrierDB)/10)
        let values = reading.spectrum.indices.map { i -> Double in
            guard abs(i-center) >= 3 else { return 0 }
            let residual = max(0,pow(10,Double(reading.spectrum[i])/10)-2*pow(10,Double(reading.baseline[i])/10))
            return min(1,log1p(residual/max(carrier,1e-12)/0.0001)/8)
        }
        frames.append(SignalFrame(time:now,power:values,spectrum:reading.spectrum,waveform:reading.waveform,sampleRate:reading.sampleRate,firstFrequency:reading.firstFrequency,binWidth:reading.binWidth,carrierDB:reading.carrierDB))
        frames.removeAll { now-$0.time > 5 }
        if frames.count > 90 { frames.removeFirst(frames.count-90) }
    }
    func clear() { frames = [] }
}

struct SignalView: View {
    @ObservedObject var history: SignalHistory
    @ObservedObject var sonar: Sonar
    @State private var style = "Flow"
    private var points: Bool { style == "Points" }
    @State private var height = 1.8
    @State private var zoom = 1.0
    @State private var yaw = -0.25
    @State private var tilt = 0.65
    @State private var dragStart: CGSize?
    @State private var frozen: [SignalFrame]?
    private var visible: [SignalFrame] { frozen ?? history.frames }
    var body: some View {
        ExperimentLayout(title:"Move your hand and watch the signal.",detail:style == "Flow" ? "An illustration driven by sound changes, not measured sound paths." : "Sound changes over time, not a map of your hand’s position.") {
            HStack(spacing:12) {
                Picker("View",selection:$style) { Text("Flow").tag("Flow"); Text("Audio").tag("Audio"); Text("Surface").tag("Surface"); Text("Points").tag("Points") }.pickerStyle(.segmented).frame(width:285)
                Spacer()
            }
        } stage: {
            VStack(spacing:12) {
            if style == "Flow" {
                EchoFlowView(frames:visible,frozen:frozen != nil)
            } else if style == "Audio" {
                AudioSignalView(frames:visible, frozen:frozen != nil)
            } else {
            HStack(spacing:18) {
                Label("Moving away",systemImage:"arrow.down.left").foregroundStyle(.cyan)
                Label("Moving toward",systemImage:"arrow.up.right").foregroundStyle(.orange)
                Spacer()
                Text(frozen == nil ? "Last 5 seconds" : "Display paused · audio continues")
            }.font(.caption)
            Canvas { context,size in
                let frames = visible
                func project(_ x:Double,_ age:Double,_ z:Double) -> CGPoint {
                    let u = (x-0.5)*1.35, v = (age-0.5)*0.8
                    let horizontal = u*cos(yaw)-v*sin(yaw)
                    let depth = u*sin(yaw)+v*cos(yaw)
                    let scale = min(size.width*0.62,size.height*0.65)*zoom
                    return CGPoint(x:size.width/2+horizontal*scale,y:size.height*0.52-depth*scale*tilt-z*scale*0.50*height)
                }
                func color(_ x:Double) -> Color { x < 0.5 ? .cyan : .orange }
                // Sparse neutral grid keeps low-energy noise from filling the surface.
                for depth in 0...5 {
                    var line=Path(); line.move(to:project(0,Double(depth)/5,0)); line.addLine(to:project(1,Double(depth)/5,0))
                    context.stroke(line,with:.color(.white.opacity(0.09)),lineWidth:1)
                }
                for x in [0.0,0.25,0.5,0.75,1.0] {
                    var line=Path(); line.move(to:project(x,0,0)); line.addLine(to:project(x,1,0))
                    context.stroke(line,with:.color(.white.opacity(x == 0.5 ? 0.23 : 0.09)),style:StrokeStyle(lineWidth:1,dash:x == 0.5 ? [3,4] : []))
                }
                let latest=frames.last?.time ?? 0
                for frame in frames {
                    let age=min(1,(latest-frame.time)/5)
                    let values=frame.power
                    for i in values.indices {
                        let x=Double(i)/Double(max(1,values.count-1)), value=values[i]
                        let point=project(x,age,value)
                        let opacity = min(1,0.3+value*4)*(1-age*0.65)
                        if points {
                            if value > 0.012 {
                                let diameter=min(5,2+value*10)
                                context.fill(Path(ellipseIn:CGRect(x:point.x-diameter/2,y:point.y-diameter/2,width:diameter,height:diameter)),with:.color(color(x).opacity(opacity)))
                            }
                        } else if i > 0 && max(value,values[i-1]) > 0.012 {
                            let previous=project(Double(i-1)/Double(max(1,values.count-1)),age,values[i-1])
                            var line=Path(); line.move(to:previous); line.addLine(to:point)
                            context.stroke(line,with:.color(color(x).opacity(opacity)),lineWidth:age < 0.06 ? 2.5 : 1.3)
                            var fill=Path(); fill.move(to:project(Double(i-1)/Double(max(1,values.count-1)),age,0)); fill.addLine(to:previous); fill.addLine(to:point); fill.addLine(to:project(x,age,0)); fill.closeSubpath()
                            context.fill(fill,with:.color(color(x).opacity(0.025*(1-age))))
                        }
                    }
                }
                context.draw(Text("≈ −600 Hz").font(.caption).foregroundColor(.cyan),at:project(0,0,-0.08))
                context.draw(Text("Now · 0 Hz").font(.caption).foregroundColor(.white.opacity(0.6)),at:project(0.5,0,-0.08))
                context.draw(Text("≈ +600 Hz").font(.caption).foregroundColor(.orange),at:project(1,0,-0.08))
                context.draw(Text("5 seconds ago").font(.caption).foregroundColor(.white.opacity(0.5)),at:project(0.5,1,-0.07))
            }
            .background(Color(red:0.035,green:0.045,blue:0.065))
            .clipShape(RoundedRectangle(cornerRadius:16))
            .overlay(alignment:.topLeading) {
                Text(visible.isEmpty ? "Start Sonar, then move your hand" : "Drag to rotate").font(.caption).foregroundStyle(.white.opacity(0.55)).padding(16).allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:2).onChanged { value in
                if dragStart == nil { dragStart = CGSize(width:yaw,height:tilt) }
                yaw = max(-0.8,min(0.8,Double(dragStart?.width ?? CGFloat(yaw))+Double(value.translation.width)/400))
                tilt = max(0.25,min(1.0,Double(dragStart?.height ?? CGFloat(tilt))-Double(value.translation.height)/300))
            }.onEnded { _ in dragStart = nil })
            .frame(minHeight:100)
            HStack(spacing:14) {
                Text("Height").font(.caption)
                Slider(value:$height,in:0.5...4).frame(width:100).accessibilityLabel("Signal height")
                Text("Zoom").font(.caption)
                Slider(value:$zoom,in:0.65...1.35).frame(width:100).accessibilityLabel("View zoom")
                Spacer()
                Button("Reset view") { yaw = -0.25; tilt = 0.65; zoom = 1; height = 1.8 }
            }
            }
            }
        } actions: {
            HStack {
                Button(frozen == nil ? "Freeze" : "Resume") { frozen = frozen == nil ? history.frames : nil }.disabled(visible.isEmpty && frozen == nil)
                Button("Clear") { frozen = nil; history.clear() }
                Spacer()
                Text(frozen != nil ? "Display frozen" : sonar.running ? "Live" : "Stopped").font(.caption).foregroundStyle(.secondary)
            }.frame(height:32)
        } status: {
            ExperimentStatus(text:frozen != nil ? "Display frozen · Resume to see new samples" : sonar.starting ? "Starting microphone…" : sonar.running ? sonar.status : "Press Start, then move your hand above the keyboard",symbol:frozen != nil ? "pause.circle" : "waveform")
        }
    }
}
