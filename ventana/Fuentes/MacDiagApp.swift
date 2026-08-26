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
    @Published var registro: [String] = []
    @Published var marcados: Set<String> = []

    func cargarUltimoInforme() {
        if let c = Motor.ultimoInforme() {
            carpetaInforme = c
            informe = Motor.leerInforme(en: c)
        }
    }

    func anotar(_ t: String) {
        registro.append(t)
        if registro.count > 400 { registro.removeFirst(registro.count - 400) }
    }

    /// Lanza un script y, al acabar, recarga el informe si se pide. Recargar
    /// es lo que hace que "reparado" se compruebe en vez de prometerse.
    func ejecutar(_ script: String,
                  argumentos: [String] = [],
                  titulo: String,
                  recargarAlFinal: Bool = false,
                  alTerminar: (() -> Void)? = nil) {
        guard !trabajando else { return }
        trabajando = true
        tarea = titulo
        registro = []
        anotar("== \(titulo)")
        Motor.lanzar(script: script, argumentos: argumentos,
                     linea: { [weak self] l in self?.anotar(l) },
                     final: { [weak self] codigo in
            guard let self else { return }
            if codigo != 0 { self.anotar("El script ha terminado con codigo \(codigo).") }
            if recargarAlFinal { self.cargarUltimoInforme() }
            self.trabajando = false
            self.tarea = ""
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

/// La consola de abajo. Existe porque un proceso que tarda un minuto sin decir
/// nada parece un programa colgado, y porque asi se ve exactamente que mando
/// se ha ejecutado.
struct Consola: View {
    let lineas: [String]
    var body: some View {
        ScrollViewReader { lector in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lineas.enumerated()), id: \.offset) { i, l in
                        Text(l)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(l.hasPrefix("==") ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }.padding(8)
            }
            .frame(height: 130)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
            .onChange(of: lineas.count) { _ in
                if let ultima = lineas.indices.last { lector.scrollTo(ultima, anchor: .bottom) }
            }
        }
    }
}
