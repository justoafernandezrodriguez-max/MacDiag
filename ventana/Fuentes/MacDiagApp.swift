// ---------------------------------------------------------------------------
//  MacDiag - la ventana
//
//  Tres secciones, como se pidio: estado del equipo, mantenimiento, e informes
//  e historial.
//
//  Se hereda de PCDIAG una decision que alli costo aprender y conviene no
//  volver a discutir: DESPUES DE REPARAR SE VUELVE A MEDIR. No se tacha de la
//  lista lo que se acaba de aplicar, se vuelve a analizar y se pinta lo que
//  salga. Si un problema sigue ahi, sigue apareciendo. Asi "reparado" deja de
//  ser una promesa y pasa a ser una comprobacion.
// ---------------------------------------------------------------------------

import SwiftUI

@main
struct MacDiagApp: App {
    var body: some Scene {
        WindowGroup("MacDiag - como esta este Mac") {
            VentanaPrincipal()
                .frame(minWidth: 940, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
    }
}

struct VentanaPrincipal: View {
    @StateObject private var estado = EstadoApp()

    var body: some View {
        TabView {
            VistaEstado(app: estado)
                .tabItem { Label("Estado del equipo", systemImage: "stethoscope") }
            VistaMantenimiento(app: estado)
                .tabItem { Label("Mantenimiento", systemImage: "internaldrive") }
            VistaInformes(app: estado)
                .tabItem { Label("Informes e historial", systemImage: "doc.text") }
        }
        .padding(14)
        .disabled(estado.trabajando)
        .overlay { if estado.trabajando { Trabajando(app: estado) } }
        .onAppear { estado.cargarUltimoInforme() }
    }
}

// ---------------------------------------------------------------------------
//  El estado que comparten las tres pestanas
// ---------------------------------------------------------------------------
final class EstadoApp: ObservableObject {
    @Published var informe: Informe?
    @Published var carpetaInforme: URL?
    @Published var trabajando = false
    @Published var tarea = ""
    @Published var ultimaLinea = ""
    @Published var marcados: Set<String> = []

    func cargarUltimoInforme() {
        if let c = Motor.ultimoInforme() {
            carpetaInforme = c
            informe = Motor.leerInforme(en: c)
        }
    }

    /// Solo se guarda la ultima linea, para el renglon pequeño del velo. El
    /// detalle completo esta en la carpeta "crudo" del informe.
    func anotar(_ t: String) {
        ultimaLinea = t.hasPrefix("==") ? String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) : t
    }

    /// Lanza un script y, al acabar, recarga el informe si se pide. Recargar
    /// es lo que hace que "reparado" se compruebe en vez de prometerse.
    func ejecutar(_ script: String,
                  argumentos: [String] = [],
                  titulo: String,
                  recargarAlFinal: Bool = false,
                  alTerminar: (() -> Void)? = nil) {
        guard !trabajando else { return }
        withAnimation(.easeInOut(duration: 0.2)) { trabajando = true }
        tarea = titulo
        ultimaLinea = ""
        Motor.lanzar(script: script, argumentos: argumentos,
                     linea: { [weak self] l in self?.anotar(l) },
                     final: { [weak self] codigo in
            guard let self else { return }
            if codigo != 0 { self.anotar("El script ha terminado con codigo \(codigo).") }
            if recargarAlFinal { self.cargarUltimoInforme() }
            withAnimation(.easeInOut(duration: 0.25)) { self.trabajando = false }
            self.tarea = ""; self.ultimaLinea = ""
            alTerminar?()
        })
    }
}

// ---------------------------------------------------------------------------
//  Piezas sueltas que usan las tres pestanas
// ---------------------------------------------------------------------------

/// El color de una gravedad. Los mismos del informe HTML, para que quien vea
/// los dos no tenga que aprender dos codigos de colores.
func colorGravedad(_ g: String) -> Color {
    switch g {
    case "CRITICO": return Color(red: 0.76, green: 0.15, blue: 0.18)
    case "AVISO":   return Color(red: 0.60, green: 0.40, blue: 0.00)
    default:        return Color(red: 0.04, green: 0.42, blue: 0.80)
    }
}

struct Kpi: View {
    let numero: String
    let etiqueta: String
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(numero).font(.system(size: 28, weight: .semibold)).foregroundColor(color)
            Text(etiqueta.uppercased()).font(.system(size: 10)).foregroundColor(.secondary)
        }
        .frame(minWidth: 96, alignment: .leading)
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
    }
}

/// El velo de "estoy trabajando".
///
/// Antes aqui habia una consola que escupia cada linea del script. Servia para
/// que no pareciera colgado, pero a quien usa la aplicacion le da igual como se
/// llama el mando numero catorce: lo unico que necesita saber es que esta
/// pasando algo y que no se ha roto.
///
/// El detalle tecnico no se pierde: sigue entero en la carpeta "crudo" del
/// informe, y ahi es donde tiene sentido buscarlo.
struct Trabajando: View {
    @ObservedObject var app: EstadoApp
    @State private var latido = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 4)
                        .frame(width: 58, height: 58)
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(
                            LinearGradient(colors: [colorGravedad("INFO"), colorGravedad("INFO").opacity(0.25)],
                                           startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 58, height: 58)
                        .rotationEffect(.degrees(latido ? 360 : 0))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: latido)
                }
                Text(app.tarea.isEmpty ? "Trabajando" : app.tarea)
                    .font(.title3)
                Text(app.ultimaLinea.isEmpty ? "un momento" : app.ultimaLinea)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 380)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .animation(.easeInOut(duration: 0.2), value: app.ultimaLinea)
            }
            .padding(34)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .windowBackgroundColor).opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(nsColor: .separatorColor)))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        }
        .transition(.opacity)
        .onAppear { latido = true }
    }
}
