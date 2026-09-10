import CoreAudio
import Foundation

struct SpeakerVolume {
    enum State: Equatable { case ready, silent, unknown }
    static func classify(muted: Bool?, volumes: [Float32?]) -> State {
        if muted == true { return .silent }
        if volumes.contains(where: { ($0 ?? 0) > 0 }) { return .ready }
        if !volumes.isEmpty && volumes.allSatisfy({ $0 != nil && $0! == 0 }) { return .silent }
        return .unknown
    }
    static func read<T>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                        _ element: AudioObjectPropertyElement, initial: T) -> T? {
        var address = AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioDevicePropertyScopeOutput,mElement:element)
        var value = initial; var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectHasProperty(device,&address),
              AudioObjectGetPropertyData(device,&address,0,nil,&size,&value) == noErr else { return nil }
        return value
    }
    static func current() -> State {
        guard let device = try? builtInDevice(scope:kAudioDevicePropertyScopeOutput) else { return .unknown }
        let mute = read(device,kAudioDevicePropertyMute,0,initial:UInt32(0)).map { $0 != 0 }
        if mute == true { return .silent }
        if let master = read(device,kAudioDevicePropertyVolumeScalar,0,initial:Float32(0)) {
            return classify(muted:mute,volumes:[master])
        }
        // Built-in stereo devices may expose independent channel volume instead of a master.
        let channels: [Float32?] = [1,2].map { channel in
            if read(device,kAudioDevicePropertyMute,UInt32(channel),initial:UInt32(0)) == 1 { return 0 }
            return read(device,kAudioDevicePropertyVolumeScalar,UInt32(channel),initial:Float32(0))
        }
        return classify(muted:mute,volumes:channels)
    }
}

func testSpeakerVolume() {
    precondition(SpeakerVolume.classify(muted:true,volumes:[0.5]) == .silent)
    precondition(SpeakerVolume.classify(muted:false,volumes:[0,0]) == .silent)
    precondition(SpeakerVolume.classify(muted:false,volumes:[0,0.0625]) == .ready)
    precondition(SpeakerVolume.classify(muted:nil,volumes:[nil,nil]) == .unknown)
    precondition(SpeakerVolume.classify(muted:false,volumes:[0,nil]) == .unknown)
    print("Speaker volume checks passed")
}
