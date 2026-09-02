// ---------------------------------------------------------------------------
//  MacDiag - explorar que ocupa cada cosa dentro de un disco
//
//  Se despliega carpeta a carpeta, y cada carpeta se mide CUANDO SE ABRE, no
//  antes. Medir un disco entero por adelantado es recorrerlo entero: en el
//  MacBook de las pruebas, con 187 GB ocupados, son varios minutos con el
//  ventilador a tope, y para entonces quien lo pidio ya ha cerrado la ventana.
//
//  AQUI NO SE BORRA NADA, y es una decision, no algo que falte. Lo que se
//  quiera tirar se abre en el Finder y lo tira la persona, que ve el contexto
//  entero. Poder mandar a la papelera cualquier ruta que se pueda desplegar
//  -incluido /System o /Library- es un poder que esta aplicacion no necesita
//  tener para hacer su trabajo, y las cosas que no se pueden hacer no se
//  pueden hacer por error.
//
//  La regla de la casa aplicada aqui: una carpeta cuyo tamano NO se ha podido
//  medir entero se dice, no se ensena la cifra corta como si fuera la buena.
//  macOS veta por privacidad varias carpetas de ~/Library y "du" sigue sumando
//  lo demas tan tranquilo (trampa 15).
// ---------------------------------------------------------------------------

import SwiftUI

struct EntradaEspacio: Codable, Identifiable, Hashable {
    var id: String { ruta }
    let nombre: String
    let ruta: String
    let kb: Int
    let carpeta: Bool
}

struct NivelEspacio: Codable {
    let ruta: String
    let estado: String          // medido | parcial | sin-tiempo | no-existe
    let vetadas: Int
    let total_kb: Int
    let entradas: [EntradaEspacio]
    let cuantas: Int
    let recortada: Bool
}

/// Tamano en algo que se lea de un vistazo. En GB solo a partir de 1 GB: "0,0
/// GB" repetido veinte veces no distingue nada, que es justo lo contrario de
/// para lo que sirve esta pantalla.
func tamanoLegible(_ kb: Int) -> String {
    if kb >= 1024 * 1024 { return String(format: "%.1f GB", Double(kb) / 1024.0 / 1024.0) }
    if kb >= 1024        { return String(format: "%.0f MB", Double(kb) / 1024.0) }
    return "\(kb) KB"
}

struct VistaExplorador: View {
    let raiz: String
    @State private var nivel: NivelEspacio?
    @State private var cargando = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if cargando {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Midiendo \(raiz)…").font(.callout).foregroundColor(.secondary)
                }
            } else if let n = nivel {
                AvisoNivel(n: n)
                List {
                    ForEach(n.entradas) { e in
                        FilaExplorador(entrada: e, mayor: n.entradas.first?.kb ?? 1)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            } else {
                Text("No se ha podido mirar dentro de \(raiz).")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { cargar() }
    }

    private func cargar() {
        cargando = true
        Motor.preguntar("macdiag-espacio.sh", ["--ver", raiz], NivelEspacio.self) { n in
            nivel = n
            cargando = false
        }
    }
}

/// Lo que no se ha podido medir se dice ARRIBA, antes de la lista, no en una
/// nota al pie que nadie lee.
struct AvisoNivel: View {
    let n: NivelEspacio

    var body: some View {
        switch n.estado {
        case "parcial":
            Etiqueta(icono: "eye.slash",
                     texto: "macOS no deja mirar dentro de \(n.vetadas) carpeta(s) por privacidad. Lo que ocupen NO esta en estas cifras: los totales son un minimo.",
                     color: colorGravedad("AVISO"))
        case "sin-tiempo":
            Etiqueta(icono: "clock",
                     texto: "Ha tardado mas de un minuto y se ha cortado. Lo que sale es lo que dio tiempo a sumar, asi que no es el total.",
                     color: colorGravedad("AVISO"))
        case "no-existe":
            Etiqueta(icono: "questionmark.folder", texto: "Esa carpeta ya no esta.", color: .secondary)
        default:
            if n.recortada {
                Etiqueta(icono: "list.bullet",
                         texto: "Hay \(n.cuantas) cosas aqui dentro; se ensenan las 300 mas grandes.",
                         color: .secondary)
            }
        }
    }
}

struct Etiqueta: View {
    let icono: String; let texto: String; let color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: icono).foregroundColor(color)
            Text(texto).font(.callout).foregroundColor(.secondary)
        }
    }
}

/// Una fila. Si es carpeta se puede desplegar, y sus hijos se piden la primera
/// vez que se abre y no antes.
struct FilaExplorador: View {
    let entrada: EntradaEspacio
    let mayor: Int

    @State private var abierta = false
    @State private var nivel: NivelEspacio?
    @State private var cargando = false

    var body: some View {
        if entrada.carpeta {
            DisclosureGroup(isExpanded: $abierta) {
                if cargando {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Midiendo…").font(.callout).foregroundColor(.secondary)
                    }
                } else if let n = nivel {
                    AvisoNivel(n: n)
                    if n.entradas.isEmpty {
                        Text("Vacia.").font(.callout).foregroundColor(.secondary)
                    }
                    ForEach(n.entradas) { hijo in
                        FilaExplorador(entrada: hijo, mayor: n.entradas.first?.kb ?? 1)
                    }
                }
            } label: {
                contenido
            }
            .onChange(of: abierta) { ahora in
                if ahora && nivel == nil && !cargando { cargar() }
            }
        } else {
            contenido
        }
    }

    private var contenido: some View {
        HStack(spacing: 8) {
            Image(systemName: entrada.carpeta ? "folder" : "doc")
                .foregroundColor(.secondary)
            Text(entrada.nombre)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            // La barra compara con el hermano mas grande, no con el disco: lo
            // que se busca aqui es "cual de estas es la gorda".
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.55))
                        .frame(width: max(2, g.size.width * proporcion))
                }
            }
            .frame(width: 90, height: 8)

            Text(tamanoLegible(entrada.kb))
                .font(.callout.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 74, alignment: .trailing)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entrada.ruta)])
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Enseñarlo en el Finder. Borrar se hace ahi, no desde aqui.")
        }
    }

    private var proporcion: Double {
        guard mayor > 0 else { return 0 }
        return min(1.0, Double(entrada.kb) / Double(mayor))
    }

    private func cargar() {
        cargando = true
        Motor.preguntar("macdiag-espacio.sh", ["--ver", entrada.ruta], NivelEspacio.self) { n in
            nivel = n
            cargando = false
        }
    }
}
