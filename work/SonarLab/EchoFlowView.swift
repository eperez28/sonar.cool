import SwiftUI

/// Stylized streamlines driven by measured Doppler sideband energy.
/// Geometry is artwork, not reconstructed sound paths or hand positions.
struct EchoFlowDrive {
    let strength: Double
    let direction: Double
    let bands: [Double]
    static func measure(_ frames:[SignalFrame],now:Double) -> EchoFlowDrive {
        guard let latest=frames.last, now.isFinite, latest.time.isFinite else { return .init(strength:0,direction:0,bands:[]) }
        let freshness=max(0,min(1,1-(now-latest.time)/0.5))
        let recent=frames.suffix(5)
        var low=0.0, high=0.0, weight=0.0
        var bands=[Double](repeating:0,count:24)
        for (j,frame) in recent.enumerated() {
            let w=Double(j+1); weight += w
            for (i,value) in frame.power.enumerated() where value.isFinite {
                let energy=max(0,value)
                if i<frame.power.count/2 { low += energy*w } else { high += energy*w }
                bands[min(23,i*24/max(1,frame.power.count))] += energy*w
            }
        }
        let total=(low+high)/max(1,weight)
        let strength=min(1,log1p(total*8)/3)*freshness
        return .init(strength:strength,direction:(high-low)/max(0.00001,high+low),bands:bands.map { min(1,$0/max(1,weight)*5)*freshness })
    }
}
struct EchoFlowView: View {
    let frames: [SignalFrame]
    let frozen: Bool
    @State private var gain=1.0
    var body: some View {
        VStack(spacing:12) {
            TimelineView(.animation(minimumInterval:1.0/30,paused:frozen)) { _ in
                let time=frozen ? (frames.last?.time ?? 0) : ProcessInfo.processInfo.systemUptime
                let drive=EchoFlowDrive.measure(frames,now:time)
                Canvas { context,size in
                    let energy=min(1,drive.strength*gain)
                    let live = !frames.isEmpty && (frozen || time-(frames.last?.time ?? 0)<0.5)
                    let width=min(size.width*0.34,200.0)
                    func point(_ progress:Double,_ strand:Int)->CGPoint {
                        let lane=Double(strand)/119*2-1
                        let side=lane<0 ? -1.0 : 1.0
                        let above=max(0,(progress-0.42)/0.58)
                        let bend=above*above*(3-2*above)
                        let deflection=energy*bend*(1-abs(lane)*0.35)*size.width*0.28
                        return CGPoint(x:size.width/2+lane*width/2+side*deflection,
                                       y:size.height-24-progress*(size.height-48)+energy*bend*size.height*0.18)
                    }
                    for strand in 0..<120 {
                        let seed=Double((strand*37)%121)/121
                        let color:Color = strand%8<2 ? Color(red:1,green:0.69,blue:0.32) : .cyan
                        let opacity=(live ? 0.10 : 0.025)+sqrt(energy)*0.4
                        var path=Path()
                        for step in 0...48 {
                            let p=point(Double(step)/48,strand)
                            if step==0 { path.move(to:p) } else { path.addLine(to:p) }
                        }
                        context.stroke(path,with:.color(color.opacity(opacity*0.12)),lineWidth:3)
                        context.stroke(path,with:.color(color.opacity(opacity*(0.4+seed*0.6))),lineWidth:0.7)
                        if live {
                            for head in 0..<3 {
                                let progress=(time*0.28+seed+Double(head)/3).truncatingRemainder(dividingBy:1)
                                var trail=Path()
                                for j in 0...6 {
                                    let t=max(0,progress-Double(6-j)*0.006)
                                    let p=point(t,strand)
                                    if j==0 { trail.move(to:p) } else { trail.addLine(to:p) }
                                }
                                context.stroke(trail,with:.color(color.opacity(0.25+energy*0.55)),lineWidth:1.1)
                            }
                        }
                    }
                    context.draw(Text(live ? "↑ Emitted stream · echoes drive the bend" : "Start Sonar to stream").font(.caption).foregroundColor(.white.opacity(0.5)),at:CGPoint(x:size.width/2,y:size.height-10))
                }
                .background(Color(red:0.015,green:0.026,blue:0.033))
                .clipShape(RoundedRectangle(cornerRadius:16))
            }.frame(minHeight:300,maxHeight:.infinity)
            HStack {
                Text("Response").font(.caption).foregroundStyle(.secondary)
                Slider(value:$gain,in:0.5...3).frame(width:110).accessibilityLabel("Visual response")
                Spacer()
                Text(frozen ? "Frozen · audio continues" : "Upward stream").font(.caption).foregroundStyle(.secondary)
            }
            Text("Stylized deflection · bend location is illustrative").font(.caption).foregroundStyle(.secondary)
        }
    }
}
func testEchoFlow() {
    let empty=EchoFlowDrive.measure([],now:10)
    testCheck(empty.strength==0,"No samples must produce no reaction")
    func frame(_ power:[Double])->SignalFrame {
        SignalFrame(time:10,power:power,spectrum:[],waveform:[],sampleRate:96000,firstFrequency:19400,binWidth:12,carrierDB:-20)
    }
    let toward=frame([0,0,0.1,0.2])
    let away=frame([0.2,0.1,0,0])
    testCheck(EchoFlowDrive.measure([toward],now:10).direction>0,"Approaching echo direction")
    testCheck(EchoFlowDrive.measure([away],now:10).direction<0,"Receding echo direction")
    testCheck(EchoFlowDrive.measure([toward],now:11).strength==0,"Stale audio must fade")
    testCheck(EchoFlowDrive.measure([frame([0,0,0,0])],now:10).strength==0,"Silence must not drive animation")
    print("PASS echo artwork input, direction, silence and stale-sample fade")
}
