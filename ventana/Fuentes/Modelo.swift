// ---------------------------------------------------------------------------
//  MacDiag - el modelo
//
//  ESTA VENTANA NO ES UN MOTOR NUEVO. Es la misma decision que PCDIAG tomo con
//  su ventana de Windows Forms: los motores son los scripts de bash, se lanzan
//  como procesos aparte y de ellos se lee el JSON que ya generaban.
//
//  Eso importa por dos motivos:
//   - Los scripts siguen funcionando solos desde la Terminal, igual que antes.
//   - El dia que esta ventana no valga, se cambia la ventana y el diagnostico
//     no se toca. Al reves no funciona.
// ---------------------------------------------------------------------------

import Foundation

// --- Lo que escribe el motor en informe.json -------------------------------

struct Hallazgo: Codable, Identifiable, Hashable {
    var id: String { gravedad + etiqueta + titulo }
    let gravedad: String        // CRITICO | AVISO | INFO
    let etiqueta: String        // DISCO, BATERIA, SEGURIDAD...
    let titulo: String
    let detalle: String

    /// La columna "Lo arregla". Vacia = no hay nada que un programa pueda
    /// hacer; "abrir:algo" = hace falta una persona y MacDiag lleva al sitio;
    /// cualquier otra cosa = MacDiag lo hace solo.
    let accion: String?

    /// Los pasos para arreglarlo, separados por " | ". Se enseñan aunque
    /// MacDiag sepa hacerlo solo: quien usa esto tiene derecho a saber que se
    /// le va a tocar al equipo antes de pulsar el boton.
    let pasos: String?

    var listaPasos: [String] {
        (pasos ?? "").components(separatedBy: " | ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Lo que empieza por "abrir:" necesita a una persona; lo demas lo hace
    /// MacDiag solo.
    var loArreglaMacDiag: Bool { sePuedeReparar && !loHaceUnaPersona }

    var sePuedeReparar: Bool { !(accion ?? "").isEmpty }
    var loHaceUnaPersona: Bool { (accion ?? "").hasPrefix("abrir:") }

    var quienLoArregla: String {
        if !sePuedeReparar { return "Esto no lo arregla un programa: es informacion." }
        if loHaceUnaPersona { return "Lo tienes que hacer tu. MacDiag te lleva al sitio exacto." }
        return "Lo arregla MacDiag."
    }
}

struct NoPude: Codable, Identifiable, Hashable {
    var id: String { que }
    let que: String
    let porque: String

    /// "diagnostico" = laguna en la revision del equipo, preocupa.
    /// "mantenimiento" = no se ha podido medir una carpeta, no dice nada de la
    /// salud del Mac. Van en sitios distintos a proposito.
    let ambito: String?

    var esDeMantenimiento: Bool { (ambito ?? "diagnostico") == "mantenimiento" }
}

struct Mando: Codable, Identifiable, Hashable {
    var id: String { clave }
    let clave: String
    let codigo: Int
    let segundos: Int
    let mando: String
}

struct Informe: Codable {
    let app: String
    let version: String
    let criticos: Int
    let avisos: Int
    let datos: [String: String]
    let hallazgos: [Hallazgo]
    let no_he_podido: [NoPude]
    let mandos: [Mando]

    func dato(_ clave: String) -> String { datos[clave] ?? "" }
}

// --- Lanzar los scripts -----------------------------------------------------
//
// Nada de esto pide contrasena de administrador: el motor de estado solo lee.
// Si alguna accion de mantenimiento la necesita, se pide PARA ESA ACCION y
// diciendo cual es, que es la regla del proyecto.

enum Motor {

    /// La carpeta "app" con los scripts. Se busca al lado del .app y, si no,
    /// en la ruta del repositorio: asi la ventana funciona tanto empaquetada
    /// como recien compilada, sin tener que copiar nada a mano.
    static var carpetaApp: URL {
        let bundle = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("app")
        if FileManager.default.fileExists(atPath: bundle.appendingPathComponent("macdiag-estado.sh").path) {
            return bundle
        }
        let dentro = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/app")
        if FileManager.default.fileExists(atPath: dentro.appendingPathComponent("macdiag-estado.sh").path) {
            return dentro
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop/CLAUDE/MacDiag/app")
    }

    static var carpetaBase: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("MacDiag")
    }

    static var carpetaInformes: URL {
        carpetaBase.appendingPathComponent("INFORMES")
    }

    /// Ejecuta un script y va entregando cada linea segun sale, para que la
    /// ventana pueda ensenar por donde va en vez de quedarse muda un minuto.
    /// Un mando que tarda sin decir nada parece un programa colgado.
    static func lanzar(script: String,
                       argumentos: [String] = [],
                       linea: @escaping (String) -> Void,
                       final: @escaping (Int32) -> Void) {
        let proceso = Process()
        proceso.executableURL = URL(fileURLWithPath: "/bin/bash")
        proceso.arguments = [carpetaApp.appendingPathComponent(script).path] + argumentos

        let tuberia = Pipe()
        proceso.standardOutput = tuberia
        proceso.standardError = tuberia

        // El motor fija LC_ALL=C por su cuenta, pero la ventana tambien puede
        // heredar un idioma que cambie los separadores decimales.
        var entorno = ProcessInfo.processInfo.environment
        entorno["LC_ALL"] = "C"
        proceso.environment = entorno

        var resto = Data()
        tuberia.fileHandleForReading.readabilityHandler = { asa in
            let trozo = asa.availableData
            if trozo.isEmpty { return }
            resto.append(trozo)
            while let corte = resto.firstIndex(of: 0x0A) {
                let cruda = resto.subdata(in: resto.startIndex..<corte)
                resto.removeSubrange(resto.startIndex...corte)
                if var texto = String(data: cruda, encoding: .utf8) {
                    texto = texto.sinColores()
                    let limpia = texto.trimmingCharacters(in: .whitespaces)
                    if !limpia.isEmpty {
                        DispatchQueue.main.async { linea(limpia) }
                    }
                }
            }
        }

        proceso.terminationHandler = { p in
            tuberia.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { final(p.terminationStatus) }
        }

        do { try proceso.run() }
        catch { DispatchQueue.main.async { final(-1) } }
    }

    /// Ejecuta un script que contesta con un JSON por la salida, y lo
    /// descodifica. Es para las preguntas cortas -"que hay dentro de esta
    /// carpeta"- que no llevan barra de progreso ni escriben ningun fichero.
    static func preguntar<T: Decodable>(_ script: String,
                                        _ argumentos: [String],
                                        _ tipo: T.Type,
                                        listo: @escaping (T?) -> Void) {
        var salida = ""
        lanzar(script: script, argumentos: argumentos,
               linea: { salida += $0 + "\n" },
               final: { _ in
                   guard let d = salida.data(using: .utf8),
                         let v = try? JSONDecoder().decode(T.self, from: d) else {
                       listo(nil); return
                   }
                   listo(v)
               })
    }

    /// La carpeta del informe mas reciente.
    static func ultimoInforme() -> URL? {
        let fm = FileManager.default
        guard let hijos = try? fm.contentsOfDirectory(at: carpetaInformes,
                                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return nil }
        return hijos.filter { $0.hasDirectoryPath }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }.first
    }

    static func leerInforme(en carpeta: URL) -> Informe? {
        let f = carpeta.appendingPathComponent("informe.json")
        guard let d = try? Data(contentsOf: f) else { return nil }
        return try? JSONDecoder().decode(Informe.self, from: d)
    }
}

extension String {
    /// Los scripts pintan con colores ANSI para la Terminal. En una ventana
    /// esos codigos son basura, asi que se quitan.
    func sinColores() -> String {
        replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]",
                             with: "", options: .regularExpression)
    }
}
