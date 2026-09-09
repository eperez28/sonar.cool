import Foundation
import AudioToolbox
import CoreAudio

// Independent AUHAL endpoints: a microphone-only device cannot be assigned
// to an audio unit whose speaker output is also enabled.
final class HardwareAudio {
    var input: AudioUnit?
    var output: AudioUnit?
    var inputRate = 0.0
    var outputRate = 0.0
    var phase = 0.0
    var elapsed = 0.0
    let positioning: Bool
    let ranging: Bool
    let tone: Double
    let amplitude: Double
    let buffer = UnsafeMutablePointer<Float>.allocate(capacity: 16384)
    let receive: ([Float]) -> Void
    init(tone: Double, amplitude: Double, ranging: Bool = false, positioning: Bool = false, receive: @escaping ([Float]) -> Void) {
        self.positioning = positioning; self.ranging = ranging; self.tone = tone; self.amplitude = amplitude; self.receive = receive
    }
    deinit { stop(); buffer.deallocate() }
    func check(_ code: OSStatus, _ step: String) throws {
        if code != noErr { throw NSError(domain:"Sonar audio",code:Int(code),userInfo:[NSLocalizedDescriptionKey:"\(step) failed (\(code))"]) }
    }
    func makeUnit() throws -> AudioUnit {
        var desc = AudioComponentDescription(componentType:kAudioUnitType_Output,componentSubType:kAudioUnitSubType_HALOutput,componentManufacturer:kAudioUnitManufacturer_Apple,componentFlags:0,componentFlagsMask:0)
        guard let c = AudioComponentFindNext(nil,&desc) else { throw NSError(domain:"AUHAL unavailable",code:1) }
        var unit: AudioUnit?
        try check(AudioComponentInstanceNew(c,&unit),"Create hardware connection")
        return unit!
    }
    func rate(_ device: AudioDeviceID) throws -> Double {
        var value = 0.0; var size: UInt32 = 8
        var address = AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyNominalSampleRate,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(device,&address,0,nil,&size,&value),"Read sample rate")
        return value
    }
    func start() throws {
        var inDevice = try builtInDevice(scope:kAudioDevicePropertyScopeInput)
        var outDevice = try builtInDevice(scope:kAudioDevicePropertyScopeOutput)
        inputRate = try rate(inDevice); outputRate = try rate(outDevice)
        guard min(inputRate,outputRate)>(ranging ? RangePulse.high : tone)*2+1000 else {
            throw NSError(domain:"Sonar",code:1,userInfo:[NSLocalizedDescriptionKey:"Built-in audio sample rate is too low for this tone."])
        }
        input = try makeUnit(); output = try makeUnit()
        let i = input!, o = output!
        var on: UInt32 = 1; var off: UInt32 = 0
        try check(AudioUnitSetProperty(i,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Input,1,&on,4),"Enable microphone")
        try check(AudioUnitSetProperty(i,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Output,0,&off,4),"Disable output on microphone connection")
        try check(AudioUnitSetProperty(i,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&inDevice,4),"Select built-in microphone")
        try check(AudioUnitSetProperty(o,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Input,1,&off,4),"Disable input on speaker connection")
        try check(AudioUnitSetProperty(o,kAudioOutputUnitProperty_EnableIO,kAudioUnitScope_Output,0,&on,4),"Enable speakers")
        try check(AudioUnitSetProperty(o,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&outDevice,4),"Select built-in speakers")
        var inf = AudioStreamBasicDescription(mSampleRate:inputRate,mFormatID:kAudioFormatLinearPCM,mFormatFlags:kAudioFormatFlagsNativeFloatPacked,mBytesPerPacket:4,mFramesPerPacket:1,mBytesPerFrame:4,mChannelsPerFrame:1,mBitsPerChannel:32,mReserved:0)
        var outf = AudioStreamBasicDescription(mSampleRate:outputRate,mFormatID:kAudioFormatLinearPCM,mFormatFlags:kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,mBytesPerPacket:4,mFramesPerPacket:1,mBytesPerFrame:4,mChannelsPerFrame:2,mBitsPerChannel:32,mReserved:0)
        try check(AudioUnitSetProperty(i,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Output,1,&inf,UInt32(MemoryLayout.size(ofValue:inf))),"Set microphone format")
        try check(AudioUnitSetProperty(o,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&outf,UInt32(MemoryLayout.size(ofValue:outf))),"Set speaker format")
        var micCallback = AURenderCallbackStruct(inputProc: { ref, flags, time, _, count, _ in
            let owner = Unmanaged<HardwareAudio>.fromOpaque(ref).takeUnretainedValue()
            guard count <= 16384, let unit = owner.input else { return kAudio_ParamError }
            var list = AudioBufferList(mNumberBuffers:1,mBuffers:AudioBuffer(mNumberChannels:1,mDataByteSize:count*4,mData:UnsafeMutableRawPointer(owner.buffer)))
            let result = AudioUnitRender(unit,flags,time,1,count,&list)
            if result == noErr { owner.receive(Array(UnsafeBufferPointer(start:owner.buffer,count:Int(count)))) }
            return result
        },inputProcRefCon:Unmanaged.passUnretained(self).toOpaque())
        var speakerCallback = AURenderCallbackStruct(inputProc: { ref, _, _, _, count, data in
            let owner = Unmanaged<HardwareAudio>.fromOpaque(ref).takeUnretainedValue()
            guard let data = data else { return noErr }
            let list = UnsafeMutableAudioBufferListPointer(data)
            for frame in 0..<Int(count) {
                let envelope = min(1,owner.elapsed/0.15)
                let value = Float((owner.ranging ? RangePulse.sample(owner.elapsed) : sin(owner.phase))*owner.amplitude*envelope)
                owner.phase += 2*Double.pi*owner.tone/owner.outputRate
                if owner.phase > 2*Double.pi { owner.phase -= 2*Double.pi }
                owner.elapsed += 1/owner.outputRate
                var channel = 0
                for b in list {
                    guard let p = b.mData?.assumingMemoryBound(to:Float.self) else { continue }
                    for c in 0..<Int(b.mNumberChannels) { if owner.positioning && channel > 0 {
                            p[frame*Int(b.mNumberChannels)+c] = Float(RangePulse.sample(owner.elapsed-1/owner.outputRate-RangePulse.period/2,descending:true)*owner.amplitude*envelope)
                        } else { p[frame*Int(b.mNumberChannels)+c] = owner.ranging && channel > 0 ? 0 : value }
                        channel += 1 }
                }
            }
            return noErr
        },inputProcRefCon:Unmanaged.passUnretained(self).toOpaque())
        try check(AudioUnitSetProperty(i,kAudioOutputUnitProperty_SetInputCallback,kAudioUnitScope_Global,0,&micCallback,UInt32(MemoryLayout.size(ofValue:micCallback))),"Install microphone callback")
        try check(AudioUnitSetProperty(o,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&speakerCallback,UInt32(MemoryLayout.size(ofValue:speakerCallback))),"Install tone callback")
        try check(AudioUnitInitialize(i),"Initialize microphone")
        try check(AudioUnitInitialize(o),"Initialize speakers")
        try check(AudioOutputUnitStart(i),"Start microphone")
        try check(AudioOutputUnitStart(o),"Start speakers")
    }
    func stop() {
        for unit in [input,output].compactMap({$0}) {
            AudioOutputUnitStop(unit); AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit)
        }
        input = nil; output = nil
    }
}
