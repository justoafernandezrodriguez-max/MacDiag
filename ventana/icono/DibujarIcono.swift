// ---------------------------------------------------------------------------
//  MacDiag - el icono
//
//  Una "D" azul tecnologica, dibujada con CoreGraphics y sin depender de
//  ningun programa de dibujo: se compila con el swiftc que ya trae el Mac y
//  escupe el .iconset entero, que iconutil convierte en .icns.
//
//  Se dibuja en vez de guardarse como imagen a proposito: asi el icono se
//  puede cambiar tocando cuatro numeros, y no hace falta abrir nada ni
//  guardar un binario en el repositorio.
// ---------------------------------------------------------------------------

import AppKit
import CoreGraphics

func dibujar(lado: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(lado), pixelsHigh: Int(lado),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let u = lado / 1024.0          // todo se mide en unidades de 1024

    // --- El fondo: squircle azul, como los iconos del sistema --------------
    let margen = 40 * u
    let caja = CGRect(x: margen, y: margen, width: lado - margen*2, height: lado - margen*2)
    let radio = caja.width * 0.225
    let fondo = CGPath(roundedRect: caja, cornerWidth: radio, cornerHeight: radio, transform: nil)

    ctx.saveGState()
    ctx.addPath(fondo); ctx.clip()
    let espacio = CGColorSpaceCreateDeviceRGB()
    // De azul noche a cian electrico: la gama "tecnologica" sin caer en el
    // azul corporativo plano.
    let degradado = CGGradient(colorsSpace: espacio, colors: [
        CGColor(srgbRed: 0.043, green: 0.145, blue: 0.353, alpha: 1),
        CGColor(srgbRed: 0.043, green: 0.412, blue: 0.831, alpha: 1),
        CGColor(srgbRed: 0.129, green: 0.749, blue: 0.949, alpha: 1)
    ] as CFArray, locations: [0.0, 0.62, 1.0])!
    ctx.drawLinearGradient(degradado,
                           start: CGPoint(x: caja.minX, y: caja.maxY),
                           end:   CGPoint(x: caja.maxX, y: caja.minY),
                           options: [])

    // --- Rejilla de circuito, muy tenue ------------------------------------
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07))
    ctx.setLineWidth(max(1, 3*u))
    var y = caja.minY + 60*u
    while y < caja.maxY { ctx.move(to: CGPoint(x: caja.minX, y: y)); ctx.addLine(to: CGPoint(x: caja.maxX, y: y)); y += 76*u }
    var x = caja.minX + 60*u
    while x < caja.maxX { ctx.move(to: CGPoint(x: x, y: caja.minY)); ctx.addLine(to: CGPoint(x: x, y: caja.maxY)); x += 76*u }
    ctx.strokePath()
    ctx.restoreGState()

    // --- La D ---------------------------------------------------------------
    //
    // Se construye a mano en vez de con una tipografia: asi es la misma en
    // cualquier Mac -no depende de que fuentes haya instaladas- y permite el
    // corte de circuito del lomo, que es lo que la hace "tecnologica" y no
    // una letra cualquiera puesta encima de un cuadrado azul.
    let grosor  = 108 * u
    let izq     = 312 * u
    let arriba  = 250 * u
    let abajo   = 774 * u
    let derecha = 736 * u
    let alto    = abajo - arriba

    let d = CGMutablePath()
    // Contorno exterior
    d.move(to: CGPoint(x: izq, y: arriba))
    d.addLine(to: CGPoint(x: izq + 150*u, y: arriba))
    d.addCurve(to: CGPoint(x: derecha, y: arriba + alto/2),
               control1: CGPoint(x: derecha - 40*u, y: arriba),
               control2: CGPoint(x: derecha, y: arriba + alto*0.18))
    d.addCurve(to: CGPoint(x: izq + 150*u, y: abajo),
               control1: CGPoint(x: derecha, y: abajo - alto*0.18),
               control2: CGPoint(x: derecha - 40*u, y: abajo))
    d.addLine(to: CGPoint(x: izq, y: abajo))
    d.closeSubpath()
    // Hueco interior
    d.move(to: CGPoint(x: izq + grosor, y: arriba + grosor))
    d.addLine(to: CGPoint(x: izq + 150*u, y: arriba + grosor))
    d.addCurve(to: CGPoint(x: derecha - grosor, y: arriba + alto/2),
               control1: CGPoint(x: derecha - grosor - 10*u, y: arriba + grosor),
               control2: CGPoint(x: derecha - grosor, y: arriba + alto*0.30))
    d.addCurve(to: CGPoint(x: izq + 150*u, y: abajo - grosor),
               control1: CGPoint(x: derecha - grosor, y: abajo - alto*0.30),
               control2: CGPoint(x: derecha - grosor - 10*u, y: abajo - grosor))
    d.addLine(to: CGPoint(x: izq + grosor, y: abajo - grosor))
    d.closeSubpath()

    // Sombra para que despegue del fondo
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6*u), blur: 26*u,
                  color: CGColor(srgbRed: 0, green: 0.05, blue: 0.15, alpha: 0.45))
    ctx.addPath(d); ctx.setFillColor(.white); ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    // --- El corte de circuito en el lomo ------------------------------------
    // Dos ranuras que parten el lomo vertical y dejan ver el fondo: es el
    // detalle que convierte la letra en algo tecnico.
    ctx.setBlendMode(.clear)
    for fr in [0.34, 0.62] {
        let yy = arriba + alto*CGFloat(fr)
        ctx.fill(CGRect(x: izq - 4*u, y: yy, width: grosor + 8*u, height: 34*u))
    }
    ctx.setBlendMode(.normal)

    // --- Nodos: los puntos de conexion --------------------------------------
    ctx.setFillColor(CGColor(srgbRed: 0.51, green: 0.94, blue: 1.0, alpha: 1))
    for fr in [0.34, 0.62] {
        let yy = arriba + alto*CGFloat(fr) + 17*u
        ctx.fillEllipse(in: CGRect(x: izq - 30*u, y: yy - 13*u, width: 26*u, height: 26*u))
    }
    // Pista que sale hacia la izquierda desde el nodo de arriba
    ctx.setStrokeColor(CGColor(srgbRed: 0.51, green: 0.94, blue: 1.0, alpha: 0.9))
    ctx.setLineWidth(11*u); ctx.setLineCap(.round)
    let yn = arriba + alto*0.34 + 17*u
    ctx.move(to: CGPoint(x: izq - 30*u, y: yn))
    ctx.addLine(to: CGPoint(x: izq - 96*u, y: yn))
    ctx.addLine(to: CGPoint(x: izq - 96*u, y: yn + 74*u))
    ctx.strokePath()
    ctx.fillEllipse(in: CGRect(x: izq - 109*u, y: yn + 61*u, width: 26*u, height: 26*u))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// --- Escribir el iconset ----------------------------------------------------
let destino = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./MacDiag.iconset"
try? FileManager.default.createDirectory(atPath: destino, withIntermediateDirectories: true)

let piezas: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (nombre, lado) in piezas {
    let rep = dibujar(lado: lado)
    if let datos = rep.representation(using: .png, properties: [:]) {
        try? datos.write(to: URL(fileURLWithPath: "\(destino)/\(nombre).png"))
    }
}
print("iconset escrito en \(destino)")
