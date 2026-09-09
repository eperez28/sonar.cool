import AppKit

// Standard Dock tile geometry; the supplied artwork remains unchanged.
let args = CommandLine.arguments
 guard args.count == 3, let artwork = NSImage(contentsOfFile: args[1]) else { exit(1) }
let pixels = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
let tile = NSRect(x:100,y:100,width:824,height:824)
let outline = NSBezierPath(roundedRect:tile,xRadius:185,yRadius:185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width:0,height:-9); shadow.set()
NSColor.white.setFill(); outline.fill()
NSGraphicsContext.restoreGraphicsState()
outline.addClip()
artwork.draw(in:tile,from:.zero,operation:.sourceOver,fraction:1)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:args[2]))
