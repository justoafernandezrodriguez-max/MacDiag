// ---------------------------------------------------------------------------
//  MacDiag - pestana "Estado del equipo"
//
//  Analizar, reparar, reparar lo seleccionado y punto de restauracion.
//
//  La columna "Lo arregla" es de PCDIAG y aqui hace mas falta todavia: en macOS
//  hay cosas que NINGUN programa puede tocar por su cuenta -encender FileVault,
//  instalar una actualizacion del sistema- y lo unico honesto es llevar al
//  usuario al sitio. Sin esa distincion, alguien pulsa "Reparar", no pasa nada
//  visible, y concluye que la aplicacion no sirve.
// ---------------------------------------------------------------------------

import SwiftUI

struct VistaEstado: View {
    @ObservedObject var app: EstadoApp
    @State private var confirmarInstantanea = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // --- Los numeros de arriba -------------------------------------
            HStack(spacing: 10) {
                Kpi(numero: "\(app.informe?.criticos ?? 0)", etiqueta: "para mirar ya",
                    color: colorGravedad("CRITICO"))
                Kpi(numero: "\(app.informe?.avisos ?? 0)", etiqueta: "avisos",
                    color: colorGravedad("AVISO"))
                Kpi(numero: app.informe.map { $0.dato("disco.ocupado_pct") + " %" } ?? "-",
                    etiqueta: "del disco")
                Kpi(numero: app.informe?.dato("maq.modelo") ?? "-", etiqueta: "equipo")
                Spacer()
            }

            // --- Los botones ------------------------------------------------
            HStack(spacing: 8) {
                Button {
                    app.ejecutar("macdiag-estado.sh",
                                 titulo: "Analizando el equipo",
                                 recargarAlFinal: true)
                } label: { Label("1 - Analizar", systemImage: "magnifyingglass") }
                    .keyboardShortcut(.defaultAction)

                Button {
                    reparar(soloMarcados: false)
                } label: { Label("2 - Reparar", systemImage: "wrench.and.screwdriver") }
                    .disabled(app.informe == nil)

                Button {
                    reparar(soloMarcados: true)
                } label: { Label("Reparar lo seleccionado", systemImage: "checklist") }
                    .disabled(app.marcados.isEmpty)

                Divider().frame(height: 18)

                Button {
                    confirmarInstantanea = true
                } label: { Label("Punto de restauracion", systemImage: "clock.arrow.circlepath") }

                Spacer()
                if app.trabajando {
                    ProgressView().controlSize(.small)
                    Text(app.tarea).font(.callout).foregroundColor(.secondary)
                }
            }
            .disabled(app.trabajando)

            Divider()

            // --- Los hallazgos ----------------------------------------------
            if let inf = app.informe {
                if inf.hallazgos.isEmpty {
                    Text("De lo que se ha podido comprobar, no hay nada que senalar.")
                        .foregroundColor(.secondary).padding(.vertical, 6)
                } else {
                    Text("Lo que conviene mirar  ·  marca lo que quieras reparar")
                        .font(.callout).foregroundColor(.secondary)
                    List {
                        ForEach(ordenados(inf.hallazgos)) { h in
                            FilaHallazgo(h: h, marcado: Binding(
                                get: { app.marcados.contains(h.id) },
                                set: { si in
                                    if si { app.marcados.insert(h.id) } else { app.marcados.remove(h.id) }
                                }))
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }

                // --- Lo que NO se ha podido comprobar -----------------------
                //
                // Va en su propia lista y NUNCA mezclado con los hallazgos.
                // "Cero fallos" y "no he podido mirar" no son lo mismo, y en
                // macOS la segunda pasa a todas horas por los permisos de
                // privacidad. Juntarlas seria decir que todo esta bien cuando
                // lo que pasa es que no se ha mirado.
                // SOLO las lagunas del DIAGNOSTICO. Lo de medir carpetas es
                // mantenimiento y vive en su pestana: mezclarlos hacia que este
                // apartado -que existe para avisar de que no se han podido leer
                // cosas como los fallos del sistema- se llenara de recados
                // sobre la papelera, y el aviso que importaba se perdiera.
                let lagunas = inf.no_he_podido.filter { !$0.esDeMantenimiento }
                if !lagunas.isEmpty {
                    DisclosureGroup("No se ha podido comprobar del equipo (\(lagunas.count))") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No son fallos: son cosas que MacDiag no ha llegado a mirar, asi que no puede decir si estan bien o mal.")
                                .font(.caption).foregroundColor(.secondary)
                            ForEach(lagunas) { n in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(n.que).font(.callout).bold()
                                    Text(n.porque).font(.caption).foregroundColor(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(.top, 4)
                    }.font(.callout)
                }

                let deMedida = inf.no_he_podido.filter { $0.esDeMantenimiento }
                if !deMedida.isEmpty {
                    Text("· \(deMedida.count) carpeta(s) no se han podido medir. Eso es mantenimiento, no salud del equipo: esta en la otra pestana.")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Todavia no hay ningun analisis.").font(.title3)
                    Text("Pulsa «1 - Analizar» para empezar. Tarda menos de un minuto y solo lee: no cambia nada.")
                        .foregroundColor(.secondary)
                }.padding(.vertical, 20)
            }

            Spacer()
            Consola(lineas: app.registro)
        }
        .confirmationDialog("Crear un punto de restauracion",
                            isPresented: $confirmarInstantanea, titleVisibility: .visible) {
            Button("Crear la instantanea") {
                app.ejecutar("macdiag-reparar.sh", argumentos: ["--instantanea"],
                             titulo: "Creando el punto de restauracion")
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("""
            En un Mac esto es una INSTANTANEA APFS, que es el equivalente del punto de restauracion de Windows: guarda como esta el disco ahora para poder volver aqui desde Recuperacion.

            Ocupa poco al principio y va creciendo segun cambian los ficheros. El sistema la borra sola cuando necesita espacio.
            """)
        }
    }

    /// Lo peor arriba, siempre.
    private func ordenados(_ hs: [Hallazgo]) -> [Hallazgo] {
        let peso = ["CRITICO": 0, "AVISO": 1, "INFO": 2]
        return hs.sorted { (peso[$0.gravedad] ?? 3) < (peso[$1.gravedad] ?? 3) }
    }

    private func reparar(soloMarcados: Bool) {
        var args = ["--aplicar"]
        if soloMarcados {
            // Se manda la ACCION, no el identificador del hallazgo: el motor
            // sabe de acciones y no tiene por que saber como pinta la ventana
            // sus filas.
            let acciones = (app.informe?.hallazgos ?? [])
                .filter { app.marcados.contains($0.id) }
                .compactMap { $0.accion }
                .filter { !$0.isEmpty }
            guard !acciones.isEmpty else { return }
            args += Array(Set(acciones)).sorted()
        } else {
            args.append("--todo")
        }
        // Y al terminar se vuelve a analizar. No se tacha nada de la lista a
        // mano: se vuelve a medir y se pinta lo que salga.
        app.ejecutar("macdiag-reparar.sh", argumentos: args,
                     titulo: soloMarcados ? "Reparando lo seleccionado" : "Reparando") {
            app.marcados.removeAll()
            app.ejecutar("macdiag-estado.sh",
                         titulo: "Volviendo a analizar para comprobar",
                         recargarAlFinal: true)
        }
    }
}

struct FilaHallazgo: View {
    let h: Hallazgo
    @Binding var marcado: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $marcado).labelsHidden().toggleStyle(.checkbox)
                .disabled(!h.sePuedeReparar)
                .help(h.quienLoArregla)
            RoundedRectangle(cornerRadius: 2)
                .fill(colorGravedad(h.gravedad))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(h.etiqueta).font(.system(size: 10)).foregroundColor(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .overlay(Capsule().stroke(Color(nsColor: .separatorColor)))
                    Text(h.titulo).font(.callout).bold()
                }
                Text(h.detalle).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // La columna "Lo arregla" de PCDIAG. Sin ella, alguien pulsa
                // Reparar, no pasa nada visible, y concluye que no sirve.
                Text(h.quienLoArregla)
                    .font(.caption2)
                    .foregroundColor(h.sePuedeReparar ? colorGravedad("INFO") : .secondary.opacity(0.8))
            }
            Spacer()
        }.padding(.vertical, 4)
    }
}
