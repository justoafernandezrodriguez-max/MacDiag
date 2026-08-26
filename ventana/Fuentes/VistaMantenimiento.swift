// ---------------------------------------------------------------------------
//  MacDiag - pestana "Mantenimiento"
//
//  Analisis del espacio de todos los discos, sugerencias de borrado, borrar lo
//  seleccionado y vaciar la papelera.
//
//  Regla que no se negocia y que viene del documento del proyecto: lo que se
//  borra va a la PAPELERA, no se destruye. Y lo que no es basura del sistema
//  -la carpeta de Descargas, por ejemplo- no se marca solo ni se suma al total
//  de "esto sobra": son ficheros del usuario y eso lo decide el.
// ---------------------------------------------------------------------------

import SwiftUI

struct Disco: Codable, Identifiable, Hashable {
    var id: String { punto }
    let nombre: String
    let punto: String
    let total_gb: String
    let usado_gb: String
    let libre_gb: String
    let pct: String
    let tipo: String        // interno | externo | sistema
}

struct Sugerencia: Codable, Identifiable, Hashable {
    let id: String
    let titulo: String
    let ruta: String
    let gb: String
    let estado: String      // medido | medido en parte | no se ha podido medir | no existe
    let seguro: String      // si = basura del sistema, no = ficheros del usuario
    let explica: String
}

struct MapaEspacio: Codable {
    let discos: [Disco]
    let sugerencias: [Sugerencia]
    let total_seguro_gb: String
}

struct VistaMantenimiento: View {
    @ObservedObject var app: EstadoApp
    @State private var mapa: MapaEspacio?
    @State private var marcadas: Set<String> = []
    @State private var confirmarBorrado = false
    @State private var confirmarPapelera = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 8) {
                Button {
                    app.ejecutar("macdiag-espacio.sh", titulo: "Midiendo todos los discos") {
                        cargarMapa()
                    }
                } label: { Label("Analizar el espacio", systemImage: "chart.pie") }
                    .keyboardShortcut(.defaultAction)

                Button {
                    confirmarBorrado = true
                } label: { Label("Borrar lo seleccionado", systemImage: "trash") }
                    .disabled(marcadas.isEmpty)

                Button {
                    confirmarPapelera = true
                } label: { Label("Vaciar la papelera", systemImage: "trash.slash") }

                Spacer()
                if app.trabajando {
                    ProgressView().controlSize(.small)
                    Text(app.tarea).font(.callout).foregroundColor(.secondary)
                }
            }
            .disabled(app.trabajando)

            if let m = mapa {
                // --- Los discos ---------------------------------------------
                Text("Los discos").font(.callout).foregroundColor(.secondary)
                Table(m.discos) {
                    TableColumn("Disco") { d in
                        HStack(spacing: 5) {
                            Image(systemName: d.tipo == "externo" ? "externaldrive" : "internaldrive")
                                .foregroundColor(.secondary)
                            Text(d.nombre)
                        }
                    }
                    TableColumn("Punto de montaje", value: \.punto)
                    TableColumn("Capacidad") { d in Text("\(d.total_gb) GB") }
                    TableColumn("Ocupado") { d in Text("\(d.usado_gb) GB") }
                    TableColumn("Libre") { d in Text("\(d.libre_gb) GB") }
                    TableColumn("%") { d in
                        Text("\(d.pct) %")
                            .foregroundColor((Int(d.pct) ?? 0) >= 90 ? colorGravedad("CRITICO")
                                             : (Int(d.pct) ?? 0) >= 75 ? colorGravedad("AVISO") : .primary)
                    }
                }
                .frame(height: 132)

                // --- Las sugerencias ----------------------------------------
                HStack {
                    Text("Sugerencias de borrado").font(.callout).foregroundColor(.secondary)
                    Spacer()
                    Text("marcado: \(gbMarcados(), specifier: "%.1f") GB")
                        .font(.callout).foregroundColor(.secondary)
                }
                List {
                    ForEach(m.sugerencias) { s in
                        FilaSugerencia(s: s, marcada: Binding(
                            get: { marcadas.contains(s.id) },
                            set: { si in if si { marcadas.insert(s.id) } else { marcadas.remove(s.id) } }
                        ))
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))

            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Todavia no se ha medido nada.").font(.title3)
                    Text("Pulsa «Analizar el espacio». Mide todos los discos montados y las carpetas que suelen ocupar sin que nadie lo sepa. Solo mide: no borra nada por su cuenta.")
                        .foregroundColor(.secondary)
                }.padding(.vertical, 20)
                Spacer()
            }

            Consola(lineas: app.registro)
        }
        .onAppear { cargarMapa() }
        .confirmationDialog("Mandar a la papelera lo marcado",
                            isPresented: $confirmarBorrado, titleVisibility: .visible) {
            Button("Mandar a la papelera", role: .destructive) {
                app.ejecutar("macdiag-espacio.sh",
                             argumentos: ["--borrar"] + marcadas.sorted(),
                             titulo: "Mandando a la papelera") {
                    marcadas.removeAll(); cargarMapa()
                }
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("""
            Se van a mandar A LA PAPELERA \(String(format: "%.1f", gbMarcados())) GB en \(marcadas.count) sitio(s).

            No se destruye nada: queda en la papelera y se puede sacar de ahi hasta que la vacies. Si has marcado algo que no era basura del sistema, este es el momento de repasarlo.
            """)
        }
        .confirmationDialog("Vaciar la papelera",
                            isPresented: $confirmarPapelera, titleVisibility: .visible) {
            Button("Vaciar la papelera", role: .destructive) {
                app.ejecutar("macdiag-espacio.sh", argumentos: ["--vaciar-papelera"],
                             titulo: "Vaciando la papelera") { cargarMapa() }
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Esto SI es definitivo: lo que hay en la papelera deja de poder recuperarse. Incluye las papeleras de los discos externos que esten conectados.")
        }
    }

    private func gbMarcados() -> Double {
        guard let m = mapa else { return 0 }
        return m.sugerencias.filter { marcadas.contains($0.id) }
                            .compactMap { Double($0.gb) }.reduce(0, +)
    }

    private func cargarMapa() {
        let f = Motor.carpetaBase.appendingPathComponent("espacio.json")
        guard let d = try? Data(contentsOf: f) else { return }
        mapa = try? JSONDecoder().decode(MapaEspacio.self, from: d)
    }
}

struct FilaSugerencia: View {
    let s: Sugerencia
    @Binding var marcada: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $marcada).labelsHidden().toggleStyle(.checkbox)
                .disabled(s.estado == "no existe" || s.estado == "no se ha podido medir")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(s.titulo).font(.callout).bold()
                    if s.seguro != "si" {
                        // La marca que evita el error caro: que alguien borre
                        // sus propios ficheros creyendo que eran basura.
                        Text("TUYO").font(.system(size: 9)).bold()
                            .foregroundColor(colorGravedad("AVISO"))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(Capsule().stroke(colorGravedad("AVISO")))
                    }
                    Spacer()
                    if s.estado == "medido" || s.estado == "medido en parte" {
                        Text("\(s.gb) GB").font(.callout).monospacedDigit()
                            + Text(s.estado == "medido en parte" ? "  (como minimo)" : "")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Text(s.estado).font(.caption).italic().foregroundColor(colorGravedad("AVISO"))
                    }
                }
                Text(s.explica).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(s.ruta).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary.opacity(0.7))
            }
        }.padding(.vertical, 4)
    }
}
