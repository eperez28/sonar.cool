import SwiftUI

// Bistatic two-source model in a vertical plane. Assumes a centered microphone,
// speakers at (+/- span/2, 0), and both echoes coming from the same point.
// This is a testable geometry hypothesis, not a measured Mac hardware layout.
struct PlanePosition {
    let x: Double
    let height: Double
    static func solve(left:Double,right:Double,span:Double) -> PlanePosition? {
        guard left.isFinite,right.isFinite,span.isFinite,left>0,right>0,span>=10 else { return nil }
        let half=span/2, l=2*left+half, r=2*right+half
        let radius=(l*l+r*r-2*half*half)/(2*(l+r))
        let x=(l*l-2*l*radius-half*half)/(2*half)
        let heightSquared=radius*radius-x*x
        guard heightSquared>0,abs(x)<=40,heightSquared<=3600 else { return nil }
        return PlanePosition(x:x,height:sqrt(heightSquared))
    }
}
final class PositionModel: ObservableObject {
    @Published var left=RangeReading(profile:[],cm:nil,quality:0,status:"Stopped")
    @Published var right=RangeReading(profile:[],cm:nil,quality:0,status:"Stopped")
    @Published var span=24.0
    @Published var updated=0.0
    func receive(left:RangeReading,right:RangeReading) {
        self.left=left; self.right=right; updated=ProcessInfo.processInfo.systemUptime
    }
    func reset() {
        left=RangeReading(profile:[],cm:nil,quality:0,status:"Waiting for audio")
        right=left; updated=0
    }
    var point: PlanePosition? {
        guard let l=left.cm, let r=right.cm else { return nil }
        return PlanePosition.solve(left:l,right:r,span:span)
    }
}
struct PositionView: View {
    @ObservedObject var model: PositionModel
    @ObservedObject var sonar: Sonar
    @State private var showSettings = false
    var body: some View {
        TimelineView(.periodic(from:.now,by:0.1)) { _ in
            let fresh=sonar.running && ProcessInfo.processInfo.systemUptime-model.updated<0.4
            let point=fresh ? model.point : nil
            ExperimentLayout(title:"Move your palm above the keyboard.",detail:"An approximate 2D position. Both speakers need a distinct echo.") {
                HStack(spacing:24) {
                    Label("Left",systemImage:"speaker.wave.2").foregroundStyle(.secondary)
                    Text((fresh ? model.left.cm : nil).map { String(format:"≈ %.0f cm",$0) } ?? "— cm").monospacedDigit()
                    Spacer()
                    Label("Right",systemImage:"speaker.wave.2").foregroundStyle(.secondary)
                    Text((fresh ? model.right.cm : nil).map { String(format:"≈ %.0f cm",$0) } ?? "— cm").monospacedDigit()
                }
            } stage: {
                    Canvas { context,size in
                        func project(_ x:Double,_ height:Double)->CGPoint {
                            CGPoint(x:size.width/2+x/80*(size.width-50),y:size.height-35-height/60*(size.height-70))
                        }
                        for h in stride(from:0,through:60,by:10) {
                            var line=Path(); line.move(to:project(-40,Double(h))); line.addLine(to:project(40,Double(h)))
                            context.stroke(line,with:.color(.white.opacity(0.08)),lineWidth:1)
                            context.draw(Text("\(h)").font(.caption2).foregroundColor(.gray),at:CGPoint(x:14,y:project(0,Double(h)).y))
                        }
                        for x in [-model.span/2,model.span/2] {
                            let p=project(x,0)
                            context.fill(Path(roundedRect:CGRect(x:p.x-12,y:p.y-4,width:24,height:8),cornerRadius:3),with:.color(.gray))
                        }
                        context.draw(Text("L").font(.caption).foregroundColor(.gray),at:project(-model.span/2,-5))
                        context.draw(Text("R").font(.caption).foregroundColor(.gray),at:project(model.span/2,-5))
                        if let point {
                            let p=project(point.x,point.height)
                            context.fill(Path(ellipseIn:CGRect(x:p.x-9,y:p.y-9,width:18,height:18)),with:.color(.mint))
                        } else {
                            context.draw(Text("Waiting for two distinct echoes").font(.callout).foregroundColor(.gray),at:CGPoint(x:size.width/2,y:size.height/2))
                        }
                    }.frame(minHeight:180,maxHeight:.infinity).background(Color(red:0.025,green:0.035,blue:0.05),in:RoundedRectangle(cornerRadius:16))
            } actions: {
                HStack {
                    Button("Reset background") { sonar.stop(); sonar.start() }.disabled(!sonar.running)
                    Button("Settings…") { showSettings.toggle() }.popover(isPresented:$showSettings) {
                        VStack(alignment:.leading,spacing:16) {
                            Text("Position model").font(.headline)
                            Text("This estimate assumes a centered microphone.").foregroundStyle(.secondary)
                            Stepper("Speaker spacing: \(Int(model.span)) cm",value:$model.span,in:10...40,step:1)
                        }.padding(20).frame(width:340)
                    }
                    Spacer()
                    Text(point.map { String(format:"x %.0f · y %.0f cm",$0.x,$0.height) } ?? "No position estimate").font(.callout).foregroundStyle(.secondary)
                }
            } status: {
                RangeCalibrationBanner(readings:[model.left,model.right],running:sonar.running,starting:sonar.starting,fresh:fresh)
            }
        }
    }
    private func channel(_ title:String,_ reading:RangeReading,fresh:Bool)->some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.callout.bold())
            Text((fresh ? reading.cm : nil).map { String(format:"≈ %.0f cm echo range",$0) } ?? "No range lock").font(.title3.monospacedDigit())
            ProgressView(value:fresh ? reading.quality : 0).tint(.mint)
            Text(reading.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
func testPosition() {
    for x in [-8.0,0,8] {
        for h in [10.0,20,30] {
            let d=sqrt(x*x+h*h), half=12.0
            let l=(sqrt((x+half)*(x+half)+h*h)+d-half)/2
            let r=(sqrt((x-half)*(x-half)+h*h)+d-half)/2
            let p=PlanePosition.solve(left:l,right:r,span:24)
            testCheck(p != nil && abs(p!.x-x)<0.001 && abs(p!.height-h)<0.001,"Two-source planar geometry")
        }
    }
    testCheck(PlanePosition.solve(left:55,right:8,span:24)==nil,"Impossible geometry must not draw a point")
    testCheck(PlanePosition.solve(left:.nan,right:20,span:24)==nil,"Nonfinite geometry must be rejected")
    for rate in [48000.0,96000.0] {
        let left=RangeAnalyzer(rate:rate), right=RangeAnalyzer(rate:rate,descending:true)
        var l=RangeReading(profile:[],cm:nil,quality:0,status:""); var r=l
        for frame in 0..<63 {
            let samples=(0..<left.n).map { k -> Float in
                let t=Double(k+frame*left.hop)/rate-0.012
                let direct=RangePulse.sample(t)+0.8*RangePulse.sample(t-RangePulse.period/2,descending:true)
                let echoes=frame>=55 ? 0.2*RangePulse.sample(t-15*0.02/343)+0.16*RangePulse.sample(t-RangePulse.period/2-25*0.02/343,descending:true) : 0
                return Float(direct+echoes)
            }
            l=left.analyze(samples); r=right.analyze(samples)
        }
        FileHandle.standardError.write(Data("Stereo test \(rate): L \(String(describing:l.cm)) R \(String(describing:r.cm))\n".utf8))
        testCheck(l.cm != nil && abs(l.cm!-15)<=4 && r.cm != nil && abs(r.cm!-25)<=4,"Separate rising/falling chirp echoes")
    }
    print("PASS two-speaker chirp separation and conditional planar geometry")
}
