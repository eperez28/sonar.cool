import SwiftUI

/// Audio snapshots share the bounded, in-memory Signal history and freeze state.
struct AudioSignalView: View {
    let frames: [SignalFrame]
    let frozen: Bool
    private let background = Color(red:0.025,green:0.035,blue:0.055)
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("Spectrogram").font(.headline)
                Spacer()
                Text(frozen ? "Display paused · audio continues" : "Last 5 seconds").foregroundStyle(.secondary)
            }.font(.caption)
            Text("The steady line is the tone. Hand movement spreads energy above and below it.")
                .font(.caption).foregroundStyle(.secondary)
            Canvas { context,size in
                let plot = CGRect(x:62,y:12,width:max(1,size.width-76),height:max(1,size.height-38))
                if let last = frames.last {
                    let reference = Double(last.carrierDB)
                    for (index,frame) in frames.enumerated() {
                        let start = max(0,1-(last.time-frame.time)/5)
                        let end = index+1 < frames.count ? max(start,1-(last.time-frames[index+1].time)/5) : 1
                        let width = max(1,(end-start)*plot.width)
                        for (bin,db) in frame.spectrum.enumerated() {
                            let value = max(0,min(1,(Double(db)-reference+65)/70))
                            let color = Color(hue:0.69-value*0.56,saturation:0.9,brightness:0.06+0.94*value)
                            let cellHeight = plot.height/Double(max(1,frame.spectrum.count))
                            let rect = CGRect(x:plot.minX+start*plot.width,y:plot.maxY-Double(bin+1)*cellHeight,width:width,height:cellHeight+0.5)
                            context.fill(Path(rect),with:.color(color))
                        }
                    }
                    for fraction in [0.0,0.5,1.0] {
                        let hz = last.firstFrequency + fraction*Double(max(0,last.spectrum.count-1))*last.binWidth
                        let y = plot.maxY-fraction*plot.height
                        context.draw(Text(String(format:"%.2f kHz",hz/1000)).font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.7)),at:CGPoint(x:29,y:y))
                    }
                } else {
                    context.draw(Text("Start Sonar to see the microphone signal").font(.callout).foregroundColor(.white.opacity(0.55)),at:CGPoint(x:size.width/2,y:size.height/2))
                }
                context.draw(Text("5 seconds ago").font(.caption2).foregroundColor(.gray),at:CGPoint(x:plot.minX+40,y:size.height-10))
                context.draw(Text("Now").font(.caption2).foregroundColor(.gray),at:CGPoint(x:plot.maxX-14,y:size.height-10))
            }.background(background).clipShape(RoundedRectangle(cornerRadius:12)).frame(minHeight:180)
            HStack {
                Text("Quiet").foregroundStyle(.secondary)
                LinearGradient(colors:[Color(hue:0.69,saturation:0.9,brightness:0.1),.blue,.cyan,.green,.yellow],startPoint:.leading,endPoint:.trailing).frame(width:100,height:6).clipShape(Capsule())
                Text("Strong").foregroundStyle(.secondary)
                Spacer()
                Text("Frequency detail around the Sonar tone").foregroundStyle(.secondary)
            }.font(.caption2)
            HStack {
                Text("Microphone waveform").font(.headline)
                Spacer()
                if let last = frames.last, last.sampleRate > 0 {
                    Text(String(format:"Latest %.1f ms · auto scale",Double(last.waveform.count)/last.sampleRate*1000)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Canvas { context,size in
                var zero = Path(); zero.move(to:CGPoint(x:0,y:size.height/2)); zero.addLine(to:CGPoint(x:size.width,y:size.height/2))
                context.stroke(zero,with:.color(.white.opacity(0.15)),lineWidth:1)
                guard let samples = frames.last?.waveform, samples.count > 1 else { return }
                let peak = max(0.00001,Double(samples.map { abs($0) }.max() ?? 0))
                var path = Path()
                for (index,sample) in samples.enumerated() {
                    let point = CGPoint(x:Double(index)/Double(samples.count-1)*size.width,y:size.height/2-Double(sample)/peak*size.height*0.4)
                    if index == 0 { path.move(to:point) } else { path.addLine(to:point) }
                }
                context.stroke(path,with:.color(.cyan),lineWidth:1)
            }.padding(12).frame(height:100).background(background).clipShape(RoundedRectangle(cornerRadius:12))
            Text("Waveform includes all captured microphone audio. Spectrogram brightness is relative to the tone; neither view measures sound pressure. Audio stays in memory.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}
