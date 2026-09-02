# ---------------------------------------------------------------------------
#  MacDiag - vigilancia: arranque, procesos y puertas abiertas
#
#  ESTO EXISTE POR UN MOTIVO CONCRETO. El 27-ago-2026, analizando el iMac donde
#  se desarrolla MacDiag, se encontro un minero de criptomonedas -xmrig- que
#  llevaba SEIS DIAS corriendo como root al 389 % de CPU. MacDiag no lo vio.
#
#  Y no lo vio de la peor manera posible: el informe decia "Demonios del
#  sistema: 4", que era un numero tranquilizador. De esos, CINCO -porque ni
#  siquiera los conto bien- eran el minero, su reinstalador camuflado de Apple,
#  y restos de otro camuflado de Google.
#
#  La leccion es la de siempre en este proyecto, aplicada a otra cosa: CONTAR NO
#  ES MIRAR. Un numero sin nombres no dice nada, y aqui ademas daba confianza.
#
#  Lo que se busca no son "virus": es lo que un programa que quiere quedarse
#  escondido tiene que hacer si o si, y que un programa honrado no hace nunca.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
#  Leer un plist de arranque
#
#  ESTO SE PAGO EN UN MACBOOK AJENO, el 2-sep-2026, y de las cuatro maneras a
#  la vez. La version anterior buscaba "ProgramArguments" y a partir de ahi se
#  llevaba la primera linea que tuviera un => ", SIN PARAR AL CERRAR EL ARRAY.
#  Cuando el array esta vacio -o tiene menos elementos de los que se piden- eso
#  no devuelve nada: devuelve el valor de LA CLAVE SIGUIENTE del plist.
#
#  Lo que salio en un MacBook de verdad, con Adobe, OneDrive y Canon puestos:
#
#    - Los dos demonios de OneDrive tienen "ProgramArguments" VACIO y un
#      "Program" bueno al lado. Se leia el "signing-identifier" de mas abajo y
#      se los declaraba CRITICOS por "apuntar a un programa que no existe".
#      Dos falsos positivos sobre software firmado por Microsoft.
#
#    - El de Adobe tiene UN argumento y un "StandardErrorPath" de /tmp debajo.
#      Se leia esa ruta como si fuera el segundo argumento y se le acusaba de
#      "arrancar algo de una carpeta de ficheros temporales". Escribir el
#      registro de errores en /tmp no es arrancar nada de /tmp.
#
#  Es la trampa de los campos vacios que se tragan el siguiente -la que ya
#  tiene su propia seccion en las pruebas- otra vez y en otro sitio. Por eso
#  ahora se lee el array como un array: se entra al abrir y SE SALE AL CERRAR.
# ---------------------------------------------------------------------------

# Un elemento de ProgramArguments por posicion: 0 es el programa, 1 el primer
# argumento. No devuelve nada si el array no llega a esa posicion, que es
# justo lo que tiene que pasar.
argv_de_plist() {
    plutil -p "$1" 2>/dev/null | awk -v q="${2:-0}" '
        /"ProgramArguments"[ \t]*=>[ \t]*\[/ { dentro = 1; n = 0; next }
        dentro && /^[ \t]*\]/              { exit }
        dentro && /^[ \t]*[0-9]+[ \t]*=>[ \t]*"/ {
            if (n == q) {
                i = index($0, "=> \"")
                v = substr($0, i + 4); sub(/".*/, "", v)
                print v; exit
            }
            n++
        }'
}

# El valor de una clave de primer nivel. Se compara la clave ENTERA, para que
# "Program" no case con "ProgramArguments" ni con la primera clave anidada que
# pase por ahi.
valor_de_clave() {
    plutil -p "$1" 2>/dev/null | awk -v clave="\"$2\"" '
        $1 == clave {
            i = index($0, "=> \"")
            if (i) { v = substr($0, i + 4); sub(/".*/, "", v); print v; exit }
        }'
}

# El programa que arranca un plist. Puede venir como ProgramArguments[0] o como
# la clave Program, y hay plists que traen las dos con el array vacio.
programa_de_plist() {
    local f="$1"; local p
    p="$(argv_de_plist "$f" 0)"
    [ -n "$p" ] || p="$(valor_de_clave "$f" Program)"
    printf '%s' "$p"
}

# El segundo argumento, que es donde suele estar el script de verdad cuando el
# primero es /bin/bash.
argumento_de_plist() {
    argv_de_plist "$1" 1
}

# La etiqueta con la que se conoce a si mismo el arranque.
etiqueta_de_plist() {
    valor_de_clave "$1" Label
}

# ---------------------------------------------------------------------------
#  Donde esta de verdad el programa de un arranque
#
#  Devuelve la ruta, o nada si no se encuentra. Y el motivo de que exista:
#  launchd acepta un mando suelto -"rm"- y lo busca en el PATH igual que la
#  Terminal. Preguntarle a un mando suelto si existe COMO FICHERO da que no, y
#  eso es lo que pasaba: un agente de Canon que lanza "rm -rf" se denunciaba
#  como un programa llamado "rm" que no existia. /bin/rm existe desde 1971.
#
#  Y no, esto no es la trampa 11 ("estar no es funcionar"). Alli la pregunta
#  era si un programa SIRVE, y para eso hay que probarlo. Aqui la pregunta es
#  si el fichero al que apunta un arranque sigue estando, que es exactamente lo
#  que command -v contesta.
# ---------------------------------------------------------------------------
ruta_de_programa() {
    local p="${1:-}"
    [ -n "$p" ] || return 0
    case "$p" in
        /*) [ -e "$p" ] && printf '%s' "$p" ;;
        *)  command -v "$p" 2>/dev/null || true ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
#  El proceso vivo de un arranque, si lo hay
#
#  Se usa para decir "ademas ahora mismo esta en marcha" y -esto es lo serio-
#  para el kill del boton de quitar arranques.
#
#  Antes era  pgrep -f "$destino", que casa por TROZO DE TEXTO contra la linea
#  de mandos entera. Con destino "rm" eso devuelve once procesos en un Mac
#  normal: theRMalmonitord, useRManagerd, theRMald, containeRManagerd... El
#  informe llego a decir que "rm" estaba EN MARCHA al 0,0 % de CPU, y lo que
#  estaba en marcha era thermalmonitord. En el reparador ese mismo PID iba a un
#  kill -9 COMO ROOT: el boton de quitar un arranque habria matado un demonio
#  del sistema. No llego a pasar porque ese boton nunca se ha llegado a pulsar.
#
#  Ahora: nombre exacto con pgrep -x, y ademas se confirma que el proceso que
#  sale es de verdad ESE fichero y no otro que se llame igual. Si el arranque
#  es un mando suelto no se puede saber cual de los "rm" del sistema es el
#  suyo, asi que no se dice nada. Callar es lo correcto cuando no se sabe.
# ---------------------------------------------------------------------------
pid_del_programa() {
    local d="${1:-}" p
    case "$d" in
        /*) : ;;
        *)  return 0 ;;
    esac
    for p in $(pgrep -x "$(basename "$d")" 2>/dev/null); do
        if [ "$(ps -p "$p" -o comm= 2>/dev/null)" = "$d" ]; then
            printf '%s' "$p"
            return 0
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
#  Por que un elemento de arranque es sospechoso
#
#  Devuelve los motivos separados por " · ", o nada si esta limpio.
#
#  Las reglas son CONSERVADORAS a proposito. En este mismo Mac hay agentes
#  legitimos que lanzan /bin/bash y node -los de es.mrfactory, que son del
#  propio usuario- y marcarlos seria justo el aviso que salta sin motivo y que
#  ensena a la gente a ignorar los avisos. Cada regla de aqui describe algo que
#  un programa honrado NO hace.
# ---------------------------------------------------------------------------
motivos_sospecha() {
    local f="$1"
    local motivos="" prog arg etiqueta base epoca

    base="$(basename "$f")"
    prog="$(programa_de_plist "$f")"
    arg="$(argumento_de_plist "$f")"
    etiqueta="$(plutil -p "$f" 2>/dev/null | awk '/"Label"/{sub(/.*=> "/,""); sub(/".*/,""); print; exit}')"

    anadir() { [ -n "$motivos" ] && motivos="$motivos · $1" || motivos="$1"; }

    # 1. Dice ser de Apple pero no esta donde Apple pone los suyos.
    #    Los de Apple viven en /System/Library/LaunchDaemons, que va en el
    #    volumen sellado. Uno en /Library que se llama "com.apple.algo" esta
    #    mintiendo sobre quien es, y eso no lo hace ningun programa honrado.
    case "$etiqueta$base" in
        com.apple.*)
            case "$f" in
                /System/*) : ;;
                *) anadir "dice ser de Apple pero no esta en las carpetas de Apple" ;;
            esac ;;
    esac

    # 2. Fecha falsificada. El 1-ene-1970 es el cero del reloj de Unix: nadie
    #    crea un fichero ese dia, se pone a proposito para no destacar cuando
    #    alguien ordena una carpeta por fecha.
    epoca="$(stat -f %m "$f" 2>/dev/null)"
    if [ -n "$epoca" ] && [ "$epoca" -lt 86400 ] 2>/dev/null; then
        anadir "tiene la fecha falsificada (1-ene-1970)"
    fi

    # 3. Arranca algo escondido o de sitio de paso. /tmp y /var/tmp son para
    #    ficheros de usar y tirar, y un punto delante esconde el fichero en el
    #    Finder. Nada que tenga que arrancar con el equipo vive ahi.
    for r in "$prog" "$arg"; do
        [ -n "$r" ] || continue
        case "$r" in
            /tmp/*|/var/tmp/*|/private/tmp/*|/private/var/tmp/*)
                anadir "arranca algo de una carpeta de ficheros temporales ($r)" ;;
        esac
        case "$(basename "$r" 2>/dev/null)" in
            .*) anadir "arranca un fichero escondido ($r)" ;;
        esac
    done

    # 4. Apunta a algo que ya no existe. Suele ser un resto: alguien quito el
    #    programa y dejo el arranque, que sigue intentandolo cada pocos
    #    segundos para siempre.
    #
    #    Se busca por ruta_de_programa y no con [ -e ] a secas porque un
    #    arranque puede nombrar un mando suelto, que vive en el PATH. Ver el
    #    comentario de esa funcion: aqui se acuso a /bin/rm de no existir.
    if [ -n "$prog" ] && [ -z "$(ruta_de_programa "$prog")" ]; then
        anadir "apunta a un programa que no existe ($prog)"
    elif [ -n "$arg" ] && [ "${prog##*/}" = "bash" ] && [ ! -e "$arg" ]; then
        anadir "apunta a un script que no existe ($arg)"
    fi

    # 5. Copia duplicada. macOS deja " 2" al copiar un fichero que ya estaba;
    #    en una carpeta de arranque eso es una instalacion hecha dos veces.
    case "$base" in
        *\ [0-9].plist) anadir "es una copia duplicada del mismo arranque" ;;
    esac

    # 6. Vive en /opt. Es una carpeta de costumbre de Linux; macOS no la usa
    #    para nada suyo. No es delito, pero merece mirarse.
    case "$prog" in
        /opt/*) anadir "el programa vive en /opt, que macOS no usa para nada suyo" ;;
    esac

    printf '%s' "$motivos"
}

# ---------------------------------------------------------------------------
#  Procesos que se estan comiendo el equipo
#
#      procesos_pesados <umbral_cpu>
#
#  Devuelve:  pcpu <TAB> pmem <TAB> comando <TAB> ruta
# ---------------------------------------------------------------------------
procesos_pesados() {
    local umbral="${1:-70}"
    ps -Aceo pid,pcpu,pmem,comm -r 2>/dev/null | awk -v u="$umbral" 'NR>1 && $2+0 >= u {
        cmd=""; for (i=4; i<=NF; i++) cmd = cmd (i>4?" ":"") $i
        printf "%s\t%s\t%s\t%s\n", $1, $2, $3, cmd
    }' | head -8
}

# La ruta de verdad de un proceso, que es lo que dice si es de fiar.
ruta_de_proceso() {
    ps -p "$1" -o comm= 2>/dev/null | head -1
}

# Cuanto lleva en marcha. Distingue "lo acabo de abrir" de "lleva tres horas".
tiempo_de_proceso() {
    ps -p "$1" -o etime= 2>/dev/null | tr -d ' ' | head -1
}

# ---------------------------------------------------------------------------
#  De donde sale un programa
#
#  Decir "knowledgeconstructiond se lleva el 98 % de la CPU" y quedarse ahi es
#  contar sin mirar: quien lo lee no sabe si eso es macOS haciendo su trabajo o
#  algo que no deberia estar. La aplicacion SI puede saberlo, y sin preguntar a
#  nadie.
#
#  El orden de las preguntas va de la respuesta mas fuerte a la mas debil:
#
#  1. Si vive en el volumen del sistema, es de Apple y ademas NO PUEDE estar
#     manipulado, porque desde Big Sur ese volumen va sellado y verificado.
#     Comprobado con df y mount en este Mac: /System, /usr/bin, /usr/libexec,
#     /usr/sbin, /sbin y /bin sirven desde "/", que monta "apfs, sealed,
#     read-only". /Applications, /Library y /usr/local NO: esos van en el
#     volumen de datos, que se escribe.
#     Es la respuesta mas fuerte y la mas barata: sale de la ruta, sin ejecutar
#     nada.
#  2. Si no, se mira quien lo firma.
#  3. Y si no lo firma nadie, eso tambien es una respuesta, y de las que
#     interesan.
#
#  Deja el resultado en dos variables en vez de devolverlo, para no tener que
#  llamar dos veces a codesign, que es lo unico caro de aqui.
# ---------------------------------------------------------------------------
PROCEDENCIA_CLASE=""
PROCEDENCIA=""
procedencia_de() {
    local r="${1:-}" firma
    PROCEDENCIA_CLASE="nosesabe"
    PROCEDENCIA="no se ha podido saber de donde sale"
    [ -n "$r" ] || return 0

    case "$r" in
        /System/*|/usr/bin/*|/usr/sbin/*|/usr/libexec/*|/sbin/*|/bin/*)
            PROCEDENCIA_CLASE="sistema"
            PROCEDENCIA="es del propio macOS: vive en el volumen del sistema, que va sellado y verificado, asi que no puede estar manipulado"
            return 0 ;;
    esac

    firma="$(codesign -dv --verbose=2 "$r" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
    if [ -n "$firma" ]; then
        PROCEDENCIA_CLASE="firmado"
        PROCEDENCIA="lo firma $firma"
    else
        PROCEDENCIA_CLASE="sinfirmar"
        PROCEDENCIA="no lleva firma de nadie, o no se ha podido comprobar"
    fi
    return 0
}
