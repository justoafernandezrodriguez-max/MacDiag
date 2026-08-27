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
#  El programa que arranca un plist
# ---------------------------------------------------------------------------
programa_de_plist() {
    local f="$1"; local p
    p="$(plutil -p "$f" 2>/dev/null | awk '/"ProgramArguments"/{d=1} d && /=> "/{sub(/.*=> "/,""); sub(/".*/,""); print; exit}')"
    [ -n "$p" ] || p="$(plutil -p "$f" 2>/dev/null | awk '/"Program"/{sub(/.*=> "/,""); sub(/".*/,""); print; exit}')"
    printf '%s' "$p"
}

# El segundo argumento, que es donde suele estar el script de verdad cuando el
# primero es /bin/bash.
argumento_de_plist() {
    plutil -p "$1" 2>/dev/null | awk '/"ProgramArguments"/{d=1;n=0} d && /=> "/{n++; if(n==2){sub(/.*=> "/,""); sub(/".*/,""); print; exit}}'
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
    if [ -n "$prog" ] && [ ! -e "$prog" ]; then
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
