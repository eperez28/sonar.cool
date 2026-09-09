import AppKit
import Carbon
import ApplicationServices

final class SystemScroll {
    private var remainder = 0.0
    func reset() { remainder = 0 }
    static func event(pixels: Int32) -> CGEvent? {
        // CGEvent positive Y means upward; our controller positive means forward/down.
        CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:-pixels,wheel2:0,wheel3:0)
    }
    func scroll(_ points: Double) {
        remainder += points
        let pixels = Int32(remainder.rounded(.towardZero))
        remainder -= Double(pixels)
        guard pixels != 0, AXIsProcessTrusted(), let event = Self.event(pixels:pixels) else { return }
        event.post(tap:.cghidEventTap)
    }
}

final class GlobalControls {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var action: ((UInt32)->Void)?
    func install() -> Bool {
        var type = EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), { _,event,context in
            guard let event, let context else { return noErr }
            var id = EventHotKeyID()
            guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id) == noErr else { return noErr }
            Unmanaged<GlobalControls>.fromOpaque(context).takeUnretainedValue().action?(id.id)
            return noErr
        },1,&type,context,&handler) == noErr else { return false }
        for (key,id) in [(UInt32(kVK_Space),UInt32(1)),(UInt32(kVK_ANSI_D),UInt32(2))] {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(key,UInt32(controlKey|optionKey|cmdKey),EventHotKeyID(signature:0x534F4E52,id:id),GetApplicationEventTarget(),0,&ref)
            guard result == noErr, let ref else { return false }
            refs.append(ref)
        }
        return true
    }
    deinit {
        for ref in refs { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class ChromeGallery {
    static var frontmost: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome" }
    static func keyEvents(next: Bool) -> [CGEvent] {
        let key = CGKeyCode(next ? kVK_RightArrow : kVK_LeftArrow)
        return [true,false].compactMap { down in
            let event = CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:down)
            event?.flags = []; return event
        }
    }
    static func send(next: Bool) -> Bool {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.google.Chrome" else { return false }
        // Avoid moving the caret in Chrome's address bar, chat, or form fields.
        var focused: CFTypeRef?
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard AXUIElementCopyAttributeValue(root,kAXFocusedUIElementAttribute as CFString,&focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = unsafeBitCast(focused,to:AXUIElement.self)
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element,kAXRoleAttribute as CFString,&role)
        if let value = role as? String, [kAXTextFieldRole,kAXTextAreaRole,kAXComboBoxRole].contains(value) { return false }
        var editable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element,kAXValueAttribute as CFString,&editable) == .success && editable.boolValue { return false }
        let events = keyEvents(next:next)
        guard events.count == 2, frontmost else { return false }
        // Use the HID keyboard route after rechecking the foreground process.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return false }
        events.forEach { $0.post(tap:.cghidEventTap) }
        return true
    }
}
