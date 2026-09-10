import AppKit

// Finder background: icons are positioned separately by dmg_settings.py.
let image = NSImage(size:NSSize(width:660,height:400))
image.lockFocus()
NSColor(calibratedWhite:0.98,alpha:1).setFill()
NSBezierPath(rect:NSRect(x:0,y:0,width:660,height:400)).fill()
func text(_ value:String, y:CGFloat, size:CGFloat, color:NSColor, weight:NSFont.Weight = .regular) {
    let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color]
    let width = (value as NSString).size(withAttributes:attributes).width
    (value as NSString).draw(at:NSPoint(x:(660-width)/2,y:y),withAttributes:attributes)
}
text("Install Sonar",y:321,size:28,color:NSColor(calibratedWhite:0.12,alpha:1),weight:.semibold)
text("Drag Sonar into Applications",y:289,size:16,color:NSColor(calibratedWhite:0.42,alpha:1))
let arrow = NSBezierPath()
arrow.move(to:NSPoint(x:302,y:200)); arrow.line(to:NSPoint(x:356,y:200))
arrow.move(to:NSPoint(x:345,y:211)); arrow.line(to:NSPoint(x:356,y:200)); arrow.line(to:NSPoint(x:345,y:189))
arrow.lineWidth=3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(calibratedWhite:0.65,alpha:1).setStroke(); arrow.stroke()
text("Then open Sonar from Applications. You’re ready to wave.",y:44,size:13,color:NSColor(calibratedWhite:0.46,alpha:1))
image.unlockFocus()
let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
