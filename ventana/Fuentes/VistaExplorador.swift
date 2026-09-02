// ---------------------------------------------------------------------------
//  MacDiag - el arbol de espacio: que ocupa cada cosa, disco por disco
//
//  La forma es la de PCDIAG a proposito, porque es la que Justo ya usa y
//  reconoce: los discos son la raiz, el tamano va DELANTE del nombre y en
//  columna -asi se comparan de un vistazo sin leer- y todo se despliega en el
//  mismo sitio, sin cambiar de pantalla.
//
//  Se mide CUANDO SE ABRE una carpeta, no antes. Medir un disco entero por
//  adelantado es recorrerlo entero: en el MacBook de las pruebas, con 187 GB
//  ocupados, son varios minutos con el ventilador a tope, y para entonces
//  quien lo pidio ya ha cerrado la ventana.
//
//  AQUI NO SE BORRA NADA, y es una decision, no algo que falte. Lo que se
//  quiera tirar se abre en el Finder y lo tira la persona, que ve el contexto
//  entero. Poder mandar a la papelera cualquier ruta que se pueda desplegar
//  -incluido /System o /Library- es un poder que esta aplicacion no necesita
//  para hacer su trabajo, y lo que no se puede hacer no se puede hacer por
//  error.
//
//  Y la regla de la casa: una carpeta cuyo tamano NO se ha podido medir entera
//  se marca "(medido a medias)", igual que en PCDIAG. macOS veta por
//  privacidad varias carpetas de ~/Library y "du" sigue sumando lo demas tan
//  tranquilo (trampa 15), asi que la cifra corta parece buena si nadie avisa.
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

/// Siempre en GB y con dos decimales, como PCDIAG. Cambiar de unidad segun el
/// tamano -MB aqui, GB alla- hace mas legible cada linea suelta y arruina lo
/// unico que importa en una lista asi: poder comparar la columna de un
/// vistazo sin leer las unidades.
func gbTexto(_ kb: Int) -> String {
    String(format: "%.2f GB", Double(kb) / 1024.0 / 1024.0)
}

/// El apunte de lo que no se ha podido medir. Va pegado a la fila, no en una
/// nota al pie: quien mira una cifra tiene que ver ahi mismo si esta entera.
func apunteEstado(_ n: NivelEspacio) -> String {
    switch n.estado {
    case "parcial":    return "(medido a medias: \(n.vetadas) carpeta(s) que macOS no deja mirar)"
    case "sin-tiempo": return "(medido a medias: se acabo el minuto de limite)"
    case "no-existe":  return "(ya no esta)"
    default:           return n.recortada ? "(las 300 mas grandes de \(n.cuantas))" : ""
    }
}

// ---------------------------------------------------------------------------
//  El arbol entero: los discos son la raiz
// ---------------------------------------------------------------------------
struct ArbolEspacio: View {
    let discos: [Disco]

    var body: some View {
        List {
            ForEach(discos) { d in
                FilaDisco(disco: d)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .font(.callout)
    }
}

struct FilaDisco: View {
    let disco: Disco
    @State private var abierto = false
    @State private var nivel: NivelEspacio?
    @State private var cargando = false

    var body: some View {
        DisclosureGroup(isExpanded: $abierto) {
            CuerpoNivel(nivel: nivel, cargando: cargando)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: disco.tipo == "externo" ? "externaldrive" : "internaldrive")
                    .foregroundColor(.secondary)
                Text(disco.nombre).bold()
                Text("·").foregroundColor(.secondary)
                Text("\(disco.pct) % ocupado, \(disco.libre_gb) GB libres de \(disco.total_gb) GB")
                    .foregroundColor((Int(disco.pct) ?? 0) >= 90 ? colorGravedad("CRITICO")
                                     : (Int(disco.pct) ?? 0) >= 75 ? colorGravedad("AVISO") : .secondary)
                if let n = nivel, !apunteEstado(n).isEmpty {
                    Text(apunteEstado(n)).foregroundColor(colorGravedad("AVISO"))
                }
                Spacer()
                BotonFinder(ruta: disco.punto)
            }
            // Doble clic en cualquier nivel abre el Finder ahi mismo. El
            // contentShape hace que valga toda la fila y no solo las letras.
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { abrirEnFinder(disco.punto) }
        }
        .onChange(of: abierto) { ahora in
            if ahora && nivel == nil && !cargando { cargar() }
        }
    }

    private func cargar() {
        cargando = true
        Motor.preguntar("macdiag-espacio.sh", ["--ver", disco.punto], NivelEspacio.self) { n in
            nivel = n; cargando = false
        }
    }
}

// ---------------------------------------------------------------------------
//  Una carpeta o un fichero
// ---------------------------------------------------------------------------
struct FilaEspacio: View {
    let entrada: EntradaEspacio
    @State private var abierta = false
    @State private var nivel: NivelEspacio?
    @State private var cargando = false

    var body: some View {
        if entrada.carpeta {
            DisclosureGroup(isExpanded: $abierta) {
                CuerpoNivel(nivel: nivel, cargando: cargando)
            } label: {
                etiqueta
            }
            .onChange(of: abierta) { ahora in
                if ahora && nivel == nil && !cargando { cargar() }
            }
        } else {
            etiqueta
        }
    }

    private var etiqueta: some View {
        HStack(spacing: 8) {
            // El tamano DELANTE y en columna fija: es lo que se viene a mirar,
            // y alineado se compara sin leer.
            Text(gbTexto(entrada.kb))
                .font(.callout.monospacedDigit())
                .frame(width: 76, alignment: .trailing)
                .foregroundColor(.primary)

            Image(systemName: entrada.carpeta ? "folder.fill" : "doc")
                .foregroundColor(.secondary)
                .font(.caption)

            Text(entrada.nombre)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.secondary)

            if let n = nivel, !apunteEstado(n).isEmpty {
                Text(apunteEstado(n))
                    .font(.caption)
                    .foregroundColor(colorGravedad("AVISO"))
            }

            Spacer(minLength: 6)
            BotonFinder(ruta: entrada.ruta)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { abrirEnFinder(entrada.ruta) }
    }

    private func cargar() {
        cargando = true
        Motor.preguntar("macdiag-espacio.sh", ["--ver", entrada.ruta], NivelEspacio.self) { n in
            nivel = n; cargando = false
        }
    }
}

/// Lo que cuelga de una carpeta ya abierta. Comun al disco y a las carpetas
/// para que las dos se comporten igual, incluido lo que dicen cuando no han
/// podido medir del todo.
struct CuerpoNivel: View {
    let nivel: NivelEspacio?
    let cargando: Bool

    var body: some View {
        if cargando {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Midiendo…").foregroundColor(.secondary)
            }
        } else if let n = nivel {
            if n.entradas.isEmpty {
                Text(n.estado == "no-existe" ? "Esa carpeta ya no esta." : "Vacia.")
                    .foregroundColor(.secondary)
            }
            ForEach(n.entradas) { e in
                FilaEspacio(entrada: e)
            }
        } else {
            Text("No se ha podido mirar aqui dentro.").foregroundColor(.secondary)
        }
    }
}

/// Abrir en el Finder, que es el unico camino que ofrece el arbol para actuar
/// sobre algo, y es a proposito: borrar se hace alli, viendo el contexto.
func abrirEnFinder(_ ruta: String) {
    let u = URL(fileURLWithPath: ruta)
    var esCarpeta: ObjCBool = false
    FileManager.default.fileExists(atPath: ruta, isDirectory: &esCarpeta)
    if esCarpeta.boolValue {
        // Una carpeta se ABRE, para quedarse dentro mirando lo que hay. Con
        // activateFileViewerSelecting se abriria la carpeta padre con esta
        // marcada, que no es lo que uno espera al pedir "abreme esto".
        NSWorkspace.shared.open(u)
    } else {
        // Un fichero suelto no se puede "abrir" sin lanzarlo con su programa,
        // asi que se ensena en su carpeta, marcado.
        NSWorkspace.shared.activateFileViewerSelecting([u])
    }
}

struct BotonFinder: View {
    let ruta: String
    var body: some View {
        Button {
            abrirEnFinder(ruta)
        } label: {
            Image(systemName: "arrow.up.forward.app")
        }
        .buttonStyle(.borderless)
        .help("Abrirlo en el Finder (o doble clic en la fila). Para borrar algo se hace ahi, no desde aqui.")
    }
}
