import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Usage:
//   swift render.swift preview <outdir>            -> a/b/c at 512px
//   swift render.swift emit <concept> <px> <path>  -> one PNG at <px>
let cs = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r/255), CGFloat(g/255), CGFloat(b/255), CGFloat(a)])!
}
func rr(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// All drawing assumes a 1024x1024 canvas, origin bottom-left.
func draw(_ ctx: CGContext, concept: String) {
    let bgRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bgRadius: CGFloat = 185

    // ---- background gradient
    ctx.saveGState()
    ctx.addPath(rr(bgRect, bgRadius)); ctx.clip()
    let top: CGColor, bot: CGColor
    switch concept {
    case "b": top = rgb(70, 80, 100); bot = rgb(24, 27, 36)       // graphite
    case "c": top = rgb(235, 52, 48);  bot = rgb(150, 10, 10)     // launchpad red
    default:  top = rgb(96, 108, 222); bot = rgb(38, 36, 116)     // indigo
    }
    let bg = CGGradient(colorsSpace: cs, colors: [top, bot] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // top sheen
    let sheen = CGGradient(colorsSpace: cs, colors: [rgb(255,255,255,0.20), rgb(255,255,255,0)] as CFArray, locations: [0,1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 540), options: [])
    ctx.restoreGState()

    // ---- chip geometry
    let cx: CGFloat = 512, cy: CGFloat = 512
    let bodySide: CGFloat = 372
    let bodyRect = CGRect(x: cx - bodySide/2, y: cy - bodySide/2, width: bodySide, height: bodySide)
    let bodyRadius: CGFloat = 42

    let pinCount = 5
    let pinLong: CGFloat = 62
    let pinThick: CGFloat = 26
    let pinRadius: CGFloat = 8
    let pinInset: CGFloat = 50

    func pinRects(_ edge: String) -> [CGRect] {
        var out: [CGRect] = []
        let usable = bodySide - 2*pinInset
        for i in 0..<pinCount {
            let t = pinCount == 1 ? 0.5 : CGFloat(i)/CGFloat(pinCount-1)
            let p = pinInset + usable*t
            switch edge {
            case "top":    out.append(CGRect(x: bodyRect.minX + p - pinThick/2, y: bodyRect.maxY - 8, width: pinThick, height: pinLong))
            case "bottom": out.append(CGRect(x: bodyRect.minX + p - pinThick/2, y: bodyRect.minY - pinLong + 8, width: pinThick, height: pinLong))
            case "left":   out.append(CGRect(x: bodyRect.minX - pinLong + 8, y: bodyRect.minY + p - pinThick/2, width: pinLong, height: pinThick))
            case "right":  out.append(CGRect(x: bodyRect.maxX - 8, y: bodyRect.minY + p - pinThick/2, width: pinLong, height: pinThick))
            default: break
            }
        }
        return out
    }

    // ---- pins
    let pinColor = concept == "c" ? rgb(255,255,255,0.95) : rgb(232, 196, 96)
    ctx.saveGState()
    if concept != "c" {
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: rgb(0,0,0,0.4))
    }
    ctx.setFillColor(pinColor)
    for edge in ["top","bottom","left","right"] {
        for r in pinRects(edge) { ctx.addPath(rr(r, pinRadius)); ctx.fillPath() }
    }
    ctx.restoreGState()

    // ---- body
    if concept == "c" {
        // line-art chip outline on red
        ctx.saveGState()
        ctx.setStrokeColor(rgb(255,255,255,0.95))
        ctx.setLineWidth(22)
        ctx.addPath(rr(bodyRect, bodyRadius)); ctx.strokePath()
        ctx.restoreGState()
    } else {
        // shadow pass
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 44, color: rgb(0,0,0,0.5))
        ctx.setFillColor(rgb(20, 22, 28))
        ctx.addPath(rr(bodyRect, bodyRadius)); ctx.fillPath()
        ctx.restoreGState()
        // gradient face
        ctx.saveGState()
        ctx.addPath(rr(bodyRect, bodyRadius)); ctx.clip()
        let face = CGGradient(colorsSpace: cs, colors: [rgb(60, 64, 76), rgb(26, 28, 35)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(face, start: CGPoint(x: cx, y: bodyRect.maxY), end: CGPoint(x: cx, y: bodyRect.minY), options: [])
        ctx.restoreGState()
        // inner top highlight
        ctx.saveGState()
        ctx.setStrokeColor(rgb(255,255,255,0.12))
        ctx.setLineWidth(3)
        ctx.addPath(rr(bodyRect.insetBy(dx: 12, dy: 12), bodyRadius-8)); ctx.strokePath()
        ctx.restoreGState()
    }

    // ---- centerpiece per concept
    switch concept {
    case "b":
        // </> code glyph
        ctx.saveGState()
        ctx.setStrokeColor(rgb(150, 214, 255))
        ctx.setLineWidth(26)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let h: CGFloat = 70
        func chevron(centerX: CGFloat, opensRight: Bool) {
            let w: CGFloat = 52
            let tip = opensRight ? centerX - w/2 : centerX + w/2
            let back = opensRight ? centerX + w/2 : centerX - w/2
            ctx.move(to: CGPoint(x: back, y: cy + h))
            ctx.addLine(to: CGPoint(x: tip, y: cy))
            ctx.addLine(to: CGPoint(x: back, y: cy - h))
            ctx.strokePath()
        }
        chevron(centerX: cx - 118, opensRight: true)   // <
        chevron(centerX: cx + 118, opensRight: false)  // >
        // slash
        ctx.move(to: CGPoint(x: cx - 30, y: cy - h))
        ctx.addLine(to: CGPoint(x: cx + 30, y: cy + h))
        ctx.strokePath()
        ctx.restoreGState()
    case "c":
        // glowing green LED at the die center
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 60, color: rgb(120, 255, 120, 0.95))
        ctx.setFillColor(rgb(120, 255, 120))
        let r: CGFloat = 70
        ctx.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2*r, height: 2*r)); ctx.fillPath()
        ctx.restoreGState()
        ctx.setFillColor(rgb(220, 255, 220))
        let hr: CGFloat = 26
        ctx.addEllipse(in: CGRect(x: cx - hr - 12, y: cy + 8, width: 2*hr, height: 2*hr)); ctx.fillPath()
    default:
        // pin-1 indicator dot + faint die square
        ctx.setStrokeColor(rgb(255,255,255,0.10))
        ctx.setLineWidth(3)
        ctx.addPath(rr(bodyRect.insetBy(dx: 70, dy: 70), 18)); ctx.strokePath()
        ctx.setFillColor(rgb(232, 196, 96))
        let d: CGFloat = 26
        ctx.addEllipse(in: CGRect(x: bodyRect.minX + 44, y: bodyRect.maxY - 44 - d, width: d, height: d)); ctx.fillPath()
    }
}

func renderImage(concept: String, px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(px) / 1024.0
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    draw(ctx, concept: concept)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "preview"
switch mode {
case "preview":
    let dir = args.count > 2 ? args[2] : "/tmp/iconsrc"
    for c in ["a","b","c"] {
        writePNG(renderImage(concept: c, px: 512), to: "\(dir)/icon_\(c).png")
        print("wrote \(dir)/icon_\(c).png")
    }
case "emit":
    let concept = args[2]; let px = Int(args[3])!; let path = args[4]
    writePNG(renderImage(concept: concept, px: px), to: path)
    print("wrote \(path) @\(px)px")
default:
    FileHandle.standardError.write("unknown mode\n".data(using: .utf8)!)
    exit(1)
}
