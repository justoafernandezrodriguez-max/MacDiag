// ---------------------------------------------------------------------------
//  MacDiag - pestana "Informes e historial"
//
//  El historial existe para lo unico que un informe suelto no puede decir: si
//  esto va a mejor o a peor.
// ---------------------------------------------------------------------------

import SwiftUI
import AppKit

struct LineaHistorial: Identifiable {
    let id = UUID()
    let fecha: String
    let version: String
    let criticos: String
    let avisos: String
    let discoPct: String
    let liberableGb: String
    let carpeta: String
}

struct VistaInformes: View {
    @ObservedObject var app: EstadoApp
    @State private var informes: [URL] = []
    @State private var historial: [LineaHistorial] = []
    @State private var elegido: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 8) {
                Button {
                    if let c = elegido ?? Motor.ultimoInforme() { abrirInforme(c) }
                } label: { Label("Abrir el informe", systemImage: "safari") }
                    .disabled(informes.isEmpty)
                    .keyboardShortcut(.defaultAction)

                Button {
                    NSWorkspace.shared.open(Motor.carpetaBase)
                } label: { Label("Abrir la carpeta de MacDiag", systemImage: "folder") }

                Button { recargar() } label: { Label("Actualizar", systemImage: "arrow.clockwise") }
                Spacer()
            }

            Text("Informes guardados").font(.callout).foregroundColor(.secondary)
            List(informes, id: \.self, selection: $elegido) { c in
                HStack {
                    Image(systemName: "doc.text").foregroundColor(.secondary)
                    Text(c.lastPathComponent)
                    Spacer()
                    Button("Abrir") { abrirInforme(c) }.buttonStyle(.link)
                    Button("Ver la carpeta") { NSWorkspace.shared.open(c) }.buttonStyle(.link)
                }
            }
            .frame(height: 150)

            Text("Historial  ·  una linea por cada vez que se ha mirado el equipo")
                .font(.callout).foregroundColor(.secondary)
            // Aviso que hace falta de verdad: los numeros de dos versiones
            // distintas NO son comparables. Cuando MacDiag aprende a mirar algo
            // nuevo, los criticos suben de golpe y parece que el equipo ha
            // empeorado, cuando lo que ha cambiado es la herramienta.
            if versionesDistintas > 1 {
                Text("Ojo: aqui hay \(versionesDistintas) versiones distintas de MacDiag. Los numeros entre versiones NO se pueden comparar: cuando MacDiag aprende a mirar algo nuevo, los criticos suben aunque el equipo este igual.")
                    .font(.caption).foregroundColor(colorGravedad("AVISO"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Table(historial) {
                TableColumn("Fecha") { l in Text(l.fecha.replacingOccurrences(of: "T", with: "  ")) }
                TableColumn("Version", value: \.version)
                TableColumn("Criticos") { l in
                    Text(l.criticos).foregroundColor(l.criticos == "0" ? .primary : colorGravedad("CRITICO"))
                }
                TableColumn("Avisos") { l in
                    Text(l.avisos).foregroundColor(l.avisos == "0" ? .primary : colorGravedad("AVISO"))
                }
                TableColumn("Disco") { l in Text(l.discoPct + " %") }
                TableColumn("Sobra") { l in Text(l.liberableGb + " GB") }
            }
        }
        .onAppear { recargar() }
    }

    /// Cuantas versiones distintas de MacDiag hay en el historial.
    private var versionesDistintas: Int {
        Set(historial.map { $0.version }.filter { !$0.isEmpty }).count
    }

    private func abrirInforme(_ carpeta: URL) {
        let html = carpeta.appendingPathComponent("informe.html")
        if FileManager.default.fileExists(atPath: html.path) {
            NSWorkspace.shared.open(html)
        } else {
            NSWorkspace.shared.open(carpeta)
        }
    }

    private func recargar() {
        let fm = FileManager.default
        informes = ((try? fm.contentsOfDirectory(at: Motor.carpetaInformes,
                                                 includingPropertiesForKeys: nil,
                                                 options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        // El historial es JSONL: una linea por ejecucion, en un fichero que
        // solo crece. Se lee al reves para que lo ultimo quede arriba.
        historial = []
        let f = Motor.carpetaBase.appendingPathComponent("historial.jsonl")
        guard let texto = try? String(contentsOf: f, encoding: .utf8) else { return }
        for linea in texto.split(separator: "\n").reversed() {
            guard let d = linea.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            historial.append(LineaHistorial(
                fecha:       o["fecha"]        as? String ?? "",
                version:     o["version"]      as? String ?? "",
                criticos:    "\(o["criticos"]  ?? "")",
                avisos:      "\(o["avisos"]    ?? "")",
                discoPct:    o["disco_pct"]    as? String ?? "",
                liberableGb: o["liberable_gb"] as? String ?? "",
                carpeta:     o["carpeta"]      as? String ?? ""))
        }
    }
}
