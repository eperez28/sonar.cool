import SwiftUI
import Accelerate

// Short windowed chirps, separated by silence. One speaker avoids mixing two
// different source-to-hand paths. Direct arrival is the timing reference so
// independent input/output device clocks do not require host-time alignment.
enum RangePulse {
    static let duration = 0.006
    static let period = 0.060
    static let low = 18000.0
    static let high = 21000.0
    static func window(_ t:Double) -> Double {
        let edge=min(t,duration-t)
        return edge < 0.0003 ? 0.5-0.5*cos(Double.pi*max(0,edge)/0.0003) : 1
    }
    static func sample(_ time: Double, descending: Bool = false) -> Double {
        let t = time.truncatingRemainder(dividingBy:period)
        guard t >= 0, t < duration else { return 0 }
        let start = descending ? high : low
        let sweep = descending ? low-high : high-low
        let phase = 2*Double.pi*(start*t+sweep*t*t/(2*duration))
        return sin(phase)*window(t)
    }
}
struct RangeReading {
    var profile: [Double]
    var cm: Double?
    var quality: Double
    var status: String
    var candidate: Double? = nil
    var calibrating = false
    var calibrationRemaining: Double? = nil
}
final class RangeAnalyzer {
    let n = 16384
    let rate: Double
    let hop: Int
    private let forward: vDSP_DFT_Setup
    private let backward: vDSP_DFT_Setup
    private var refR: [Float]
    private var refI: [Float]
    private var baseline = [Double](repeating:0,count:61)
    private var squares = [Double](repeating:0,count:61)
    private var count = 0
    private var previous: Double?
    private var stable = 0
    init(rate: Double, descending: Bool = false) {
        self.rate=rate; hop=Int(rate*RangePulse.period)
        forward=vDSP_DFT_zop_CreateSetup(nil,16384,.FORWARD)!
        backward=vDSP_DFT_zop_CreateSetup(nil,16384,.INVERSE)!
        var r=[Float](repeating:0,count:n), i=r
        for k in 0..<Int(rate*RangePulse.duration) {
            let t=Double(k)/rate
            let start=descending ? RangePulse.high : RangePulse.low
            let sweep=descending ? RangePulse.low-RangePulse.high : RangePulse.high-RangePulse.low
            let phase=2*Double.pi*(start*t+sweep*t*t/(2*RangePulse.duration))
            let w=RangePulse.window(t)
            r[k]=Float(sin(phase)*w); i[k]=Float(-cos(phase)*w)
        }
        refR=r; refI=i
        vDSP_DFT_Execute(forward,r,i,&refR,&refI)
    }
    deinit { vDSP_DFT_DestroySetup(forward); vDSP_DFT_DestroySetup(backward) }
    func analyze(_ input: [Float]) -> RangeReading {
        guard input.count == n else {
            stable=0; previous=nil
            return RangeReading(profile:[],cm:nil,quality:0,status:"Incomplete audio frame · waiting for the next sample")
        }
        let zero=[Float](repeating:0,count:n)
        var r=zero, i=zero
        vDSP_DFT_Execute(forward,input,zero,&r,&i)
        for k in 0..<n {
            let a=r[k], b=i[k]
            r[k]=a*refR[k]+b*refI[k]; i[k]=b*refR[k]-a*refI[k]
        }
        var cr=zero, ci=zero
        vDSP_DFT_Execute(backward,r,i,&cr,&ci)
        var magnitude=[Double](repeating:0,count:n)
        for k in 0..<n { let a=Double(cr[k]); let b=Double(ci[k]); magnitude[k]=sqrt(a*a+b*b)/Double(n) }
        // Use only complete chirps with room for all echo lags after them.
        let end=n-Int(rate*(RangePulse.duration+0.006))-1
        let direct=(0..<end).max(by:{ magnitude[$0] < magnitude[$1] }) ?? 0
        let peak=magnitude[direct]
        let noise=magnitude.sorted()[n/2]
        guard peak > max(1e-5,noise*12) else {
            stable=0; previous=nil
            return RangeReading(profile:[],cm:nil,quality:0,status:"No clear direct chirp · check the audio route")
        }
        var profile=[Double](repeating:0,count:61)
        for cm in 0...60 {
            let lag=Double(cm)*0.02/343*rate
            let index=direct+Int(lag.rounded())
            profile[cm]=magnitude[index]/peak
        }
        let warmup=Int(ceil(3/RangePulse.period))
        if count < warmup {
            count += 1
            for k in 0...60 { baseline[k] += profile[k]; squares[k] += profile[k]*profile[k] }
            if count == warmup {
                for k in 0...60 { baseline[k] /= Double(warmup); squares[k] = sqrt(max(0,squares[k]/Double(warmup)-baseline[k]*baseline[k])) }
            }
            return RangeReading(profile:profile,cm:nil,quality:0,status:"Measuring empty desk · keep hands away (\(Int(ceil(Double(warmup-count)*RangePulse.period)))s)",calibrating:true,calibrationRemaining:Double(warmup-count)*RangePulse.period)
        }
        let excess=(0...60).map { max(0,profile[$0]-baseline[$0]) }
        let candidate=(8...55).max(by:{excess[$0] < excess[$1]})!
        let floor=max(0.003,max(squares[candidate]*3,Array(excess[8...60]).sorted()[26]*2))
        let ratio=excess[candidate]/floor
        let second=(8...60).filter { abs($0-candidate)>8 }.map { excess[$0] }.max() ?? 0
        guard ratio > 4, second < excess[candidate]*0.8 else {
            stable=0; previous=nil
            return RangeReading(profile:excess,cm:nil,quality:min(1,ratio/12),status:ratio > 4 ? "Multiple echoes · hold one palm still" : "Waiting for a distinct hand echo",candidate:ratio>1.5 ? Double(candidate) : nil)
        }
        let cm=Double(candidate)
        if let last=previous, abs(last-cm)<=4 { stable += 1 } else { stable=1 }
        previous=cm
        return RangeReading(profile:excess,cm:stable>=3 ? cm : nil,quality:min(1,ratio/12),status:stable>=3 ? "Stable echo · experimental estimate" : "Checking echo stability…",candidate:cm)
    }
}
struct RangeFrame {
    let time: Double
    let reading: RangeReading
}
final class DistanceModel: ObservableObject {
    @Published var reading = RangeReading(profile:[],cm:nil,quality:0,status:"Start to see live echoes")
    @Published private(set) var frames: [RangeFrame] = []
    @Published var offset: Double?
    @Published var reference = 20.0
    var distance: Double? { guard let cm=reading.cm else { return nil }; let value=cm+(offset ?? 0); return value>0 ? value : nil }
    func receive(_ value:RangeReading) {
        reading=value
        let now=ProcessInfo.processInfo.systemUptime
        frames.append(RangeFrame(time:now,reading:value))
        frames.removeAll { now-$0.time>5 }
        if frames.count>90 { frames.removeFirst(frames.count-90) }
    }
    func reset() { offset=nil; frames=[]; reading=RangeReading(profile:[],cm:nil,quality:0,status:"Start to see live echoes") }
}
struct DistanceView: View {
    @ObservedObject var model: DistanceModel
    @ObservedObject var sonar: Sonar
    @State private var showReference = false
    var body: some View {
        TimelineView(.periodic(from:.now,by:0.1)) { _ in
            let now=ProcessInfo.processInfo.systemUptime
            let fresh=sonar.running && now-(model.frames.last?.time ?? 0)<0.4
            ExperimentLayout(title:"Lift and lower your palm.",detail:"Echo range is an estimate, not your hand’s exact height.") {
                HStack {
                    Label("Echo range",systemImage:"ruler").foregroundStyle(.secondary)
                    Spacer()
                    Text((fresh ? model.distance : nil).map { String(format:"≈ %.0f cm",$0) } ?? "— cm")
                        .font(.title2.monospacedDigit())
                }
            } stage: {
                RangeLivePlot(frames:model.frames,now:now,running:sonar.running)
            } actions: {
                HStack {
                    Button("Reset background") { sonar.stop(); sonar.start() }.disabled(!sonar.running)
                    Button("Settings…") { showReference.toggle() }.sheet(isPresented:$showReference) {
                        AppSheet(title:"Distance settings",close:{ showReference = false }) {
                        VStack(alignment:.leading,spacing:16) {
                            Text("Distance reference").font(.headline)
                            Text("An optional ruler measurement adds an offset. It cannot correct room reflections.").font(.callout).foregroundStyle(.secondary)
                            Stepper("Measured height: \(Int(model.reference)) cm",value:$model.reference,in:10...50,step:5)
                            HStack {
                                Button("Use height") { if let cm=model.reading.cm { model.offset=model.reference-cm } }.disabled(!sonar.running || model.reading.cm == nil)
                                Button("Remove reference") { model.offset=nil }.disabled(model.offset == nil)
                            }
                        }
                        }
                    }
                    Spacer()
                    Label("Distinct",systemImage:"circle.fill").foregroundStyle(.mint)
                    Label("Unconfirmed",systemImage:"circle.dashed").foregroundStyle(.orange)
                }.font(.callout)
            } status: {
                RangeCalibrationBanner(readings:[model.reading],running:sonar.running,starting:sonar.starting,fresh:fresh)
            }
        }
    }
}
struct RangeLivePlot: View {
    static func validBins(_ count:Int) -> Range<Int> { 8..<max(8,min(61,count)) }
    let frames: [RangeFrame]
    let now: Double
    let running: Bool
    var body: some View {
        Canvas { context,size in
            let plot=CGRect(x:45,y:30,width:max(1,size.width-65),height:max(1,size.height-65))
            func x(_ cm:Double)->Double { plot.minX+(cm-8)/52*plot.width }
            for cm in stride(from:10,through:60,by:10) {
                let px=x(Double(cm))
                var grid=Path(); grid.move(to:CGPoint(x:px,y:plot.minY)); grid.addLine(to:CGPoint(x:px,y:plot.maxY))
                context.stroke(grid,with:.color(.white.opacity(0.10)),lineWidth:1)
                context.draw(Text("\(cm) cm").font(.caption2).foregroundColor(.gray),at:CGPoint(x:px,y:size.height-16))
            }
            context.draw(Text("NOW").font(.system(size:9,design:.monospaced)).foregroundColor(.gray),at:CGPoint(x:20,y:plot.minY))
            context.draw(Text("−5 s").font(.system(size:9,design:.monospaced)).foregroundColor(.gray),at:CGPoint(x:20,y:plot.maxY))
            let end=running ? now : (frames.last?.time ?? now)
            for frame in frames {
                let age=end-frame.time
                guard age>=0,age<=5 else { continue }
                let y=plot.minY+age/5*plot.height
                let rowHeight=max(2,RangePulse.period/5*plot.height)
                for cm in RangeLivePlot.validBins(frame.reading.profile.count) {
                    // Fixed logarithmic scale makes changing intensity meaningful across rows.
                    let energy=max(0,min(1,log1p(frame.reading.profile[cm]/0.003)/5))
                    let color=frame.reading.calibrating ? Color.gray : Color.cyan
                    let rect=CGRect(x:x(Double(cm)),y:y,width:plot.width/52+0.5,height:min(rowHeight,plot.maxY-y))
                    context.fill(Path(rect),with:.color(color.opacity(energy*0.85)))
                }
                if !frame.reading.calibrating, let cm=frame.reading.cm ?? frame.reading.candidate {
                    let point=Path(ellipseIn:CGRect(x:x(cm)-3,y:y-3,width:6,height:6))
                    if frame.reading.cm != nil { context.fill(point,with:.color(.mint)) }
                    else { context.stroke(point,with:.color(.orange.opacity(0.65)),lineWidth:1) }
                }
            }
            if frames.isEmpty {
                context.draw(Text("Live echoes will appear here").font(.callout).foregroundColor(.gray),at:CGPoint(x:size.width/2,y:size.height/2))
            }
        }.frame(minHeight:180,maxHeight:.infinity).background(Color(red:0.025,green:0.035,blue:0.05),in:RoundedRectangle(cornerRadius:16))
        .accessibilityLabel("Live echo range over the last five seconds. Solid markers are distinct echoes; outlined markers are unconfirmed.")
    }
}

func testDistance() {
    for count in [0,1,7,8,9,61,80] {
        testCheck(RangeLivePlot.validBins(count).allSatisfy { $0>=8 && $0<count && $0<61 },"Safe range plotting bins")
    }
    for rate in [48000.0,96000.0] {
        let analyzer=RangeAnalyzer(rate:rate)
        func samples(_ cm:Double?, frame:Int) -> [Float] {
            (0..<analyzer.n).map { k in
                let t=Double(k+frame*analyzer.hop)/rate-0.012
                let direct=RangePulse.sample(t)
                let echo=cm.map { 0.15*RangePulse.sample(t-$0*0.02/343) } ?? 0
                return Float(direct+echo)
            }
        }
        testCheck(analyzer.analyze([]).cm == nil,"Incomplete audio must not crash or report distance")
        var reading=analyzer.analyze([Float](repeating:0,count:analyzer.n))
        testCheck(reading.cm == nil,"Silence must not produce distance")
        for frame in 0..<55 { reading=analyzer.analyze(samples(nil,frame:frame)) }
        testCheck(reading.cm == nil,"Static baseline must not produce distance")
        for cm in [10.0,20.0,30.0] {
            for frame in 55..<62 { reading=analyzer.analyze(samples(cm,frame:frame)) }
            FileHandle.standardError.write(Data("Range test: \(rate) Hz, expected \(cm), got \(String(describing:reading.cm)), \(reading.status), quality \(reading.quality)\n".utf8))
            testCheck(reading.cm != nil && abs(reading.cm!-cm)<=4,"Synthetic echo \(cm) cm at \(rate): \(String(describing:reading.cm)) \(reading.status)")
        }
        reading=analyzer.analyze(samples(nil,frame:63))
        testCheck(reading.cm == nil,"Lost echo must clear displayed range")
        print("PASS matched chirps at \(rate): silence, static desk, 10/20/30 cm delays, lost echo")
    }
}


struct RangeCalibrationBanner: View {
    let readings: [RangeReading]
    let running: Bool
    let starting: Bool
    let fresh: Bool
    private var remaining: Double? { readings.compactMap(\.calibrationRemaining).max() }
    private var missing: Bool { !fresh || readings.contains { $0.profile.isEmpty } }
    var body: some View {
        HStack(spacing:16) {
            if starting {
                ProgressView().controlSize(.small)
                Text("Starting microphone…")
            } else if !running {
                Label("Press Start · keep your hands away during the countdown",systemImage:"hand.raised")
            } else if missing {
                ProgressView().controlSize(.small)
                Text("Waiting for clear audio · calibration paused")
            } else if let remaining {
                Text("\(max(1,Int(ceil(remaining))))").font(.system(size:24,weight:.semibold,design:.rounded)).monospacedDigit().frame(width:48)
                VStack(alignment:.leading,spacing:6) {
                    Text("Calibrating · keep hands away").font(.headline)
                    ProgressView(value:max(0,min(1,1-remaining/3))).tint(.mint)
                }
            } else {
                Label("Ready · move your hand above the keyboard",systemImage:"checkmark.circle.fill").foregroundStyle(.mint)
            }
            Spacer(minLength:0)
        }.padding(12).frame(maxWidth:.infinity,minHeight:48,maxHeight:48,alignment:.leading)
            .background(.mint.opacity(0.07),in:RoundedRectangle(cornerRadius:12))
    }
}
