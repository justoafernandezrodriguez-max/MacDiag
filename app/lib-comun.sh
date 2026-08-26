# ---------------------------------------------------------------------------
#  MacDiag - utilidades comunes
#
#  Se carga con punto:  . "$AQUI/lib-comun.sh"
#
#  YA SE HA EJECUTADO EN UN MAC: un iMac18,3 con macOS 13.7.8, Intel, el
#  26-ago-2026. Sigue SIN probarse en Apple Silicon y en un portatil con
#  bateria. Ver LEEME.txt.
#
#  Todo lo que hay aqui esta pensado para que un mando que falle sea un DATO y
#  no el final del informe. Esa apuesta salio bien: en la primera ejecucion real
#  fallaron dos mandos y el informe se termino igual.
#
#  Bash 3.2, que es el que trae macOS desde siempre y el que va a seguir
#  trayendo. Nada de bash 4: ni arrays asociativos, ni ${var^^}, ni readarray.
#  Y nada de "set -e": aqui los fallos se recogen, no abortan.
# ---------------------------------------------------------------------------

# La version va en UN solo sitio, y este es el sitio. Es la leccion de PCDIAG:
# el dia que el numero vive en tres ficheros, se actualizan dos.
VERSION_MACDIAG="0.2.0"

# ---------------------------------------------------------------------------
# Decir cosas por pantalla
# ---------------------------------------------------------------------------
_C_ROJO=$'\033[31m'; _C_VERDE=$'\033[32m'; _C_AMBAR=$'\033[33m'
_C_GRIS=$'\033[90m'; _C_FIN=$'\033[0m'; _C_FUERTE=$'\033[1m'

Di()    { printf '  %s\n' "$1"; }
DiOk()  { printf '  %s%s%s\n' "$_C_VERDE" "$1" "$_C_FIN"; }
DiMal() { printf '  %s%s%s\n' "$_C_ROJO" "$1" "$_C_FIN"; }
DiOjo() { printf '  %s%s%s\n' "$_C_AMBAR" "$1" "$_C_FIN"; }
DiFlojo(){ printf '  %s%s%s\n' "$_C_GRIS" "$1" "$_C_FIN"; }
Paso()  { printf '\n%s== %s%s\n' "$_C_FUERTE" "$1" "$_C_FIN"; }

# ---------------------------------------------------------------------------
# Ejecutar con limite de tiempo
#
# macOS NO trae "timeout": es de las coreutils de GNU y aqui no existe. Y hace
# falta de verdad, porque hay mandos del sistema que tardan lo que quieren:
# "system_profiler" completo son decenas de segundos, "softwareupdate -l"
# depende de la red, y "du" sobre una carpeta enorme puede irse a minutos.
#
# Sin esto, un solo mando lento deja la aplicacion colgada sin decir por que,
# que es la peor forma de fallar: el usuario piensa que se ha roto.
#
# Se vigila cada 0,2 s en vez de cada segundo porque con veinticinco mandos,
# esperar un segundo a cada uno son veinticinco segundos regalados.
# ---------------------------------------------------------------------------
con_limite() {
    local seg="$1"; shift
    "$@" &
    local pid=$!
    local vueltas=0
    local tope=$(( seg * 5 ))
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$vueltas" -ge "$tope" ]; then
            kill -TERM "$pid" 2>/dev/null
            sleep 1
            kill -KILL "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
        sleep 0.2
        vueltas=$(( vueltas + 1 ))
    done
    wait "$pid"
    return $?
}

# ---------------------------------------------------------------------------
# Tapar lo que identifica a la maquina
#
# Las capturas en crudo se hacen para poder mandarlas a otra persona y que
# arregle la lectura. El numero de serie y el UUID no hacen falta para nada de
# eso, asi que no viajan. Lo que si viaja es todo lo demas, entero: recortar
# una captura "por si acaso" es quedarse sin la prueba justo cuando hace falta.
# ---------------------------------------------------------------------------
limpiar_identificadores() {
    sed -E \
        -e 's/^([[:space:]]*(Serial Number( \(system\))?|Hardware UUID|Provisioning UDID|UDID)[[:space:]]*:).*$/\1 (oculto)/' \
        -e 's/("(Serial|BatterySerialNumber|IOPlatformSerialNumber|IOPlatformUUID)"[[:space:]]*=[[:space:]]*).*$/\1"(oculto)"/'
}

# ---------------------------------------------------------------------------
# Capturar un mando
#
# ESTA ES LA PIEZA IMPORTANTE DEL PROYECTO, y lo es por como se ha escrito
# esto: sin un Mac delante. La salida cruda de cada mando se guarda en su
# fichero ANTES de interpretarla, y el informe se saca de esos ficheros.
#
# Con eso, quien lo pruebe manda la carpeta y se puede arreglar la lectura con
# la salida REAL de su equipo, sin volver a pedirle nada. Interpretar el mando
# al vuelo y no guardar nada obligaria a una ronda de preguntas por cada campo
# que saliera torcido.
#
#   capturar <clave> <segundos> <mando...>
#
# Devuelve el codigo de salida del mando. 124 significa que se acabo el tiempo.
# Nunca aborta: un mando que no existe en esta version de macOS es informacion.
# ---------------------------------------------------------------------------
capturar() {
    local clave="$1"; local limite="$2"; shift 2
    local destino="$CRUDO/$clave.txt"
    local t0 t1 rc
    t0=$(date +%s)
    con_limite "$limite" "$@" > "$destino.parcial" 2>&1
    rc=$?
    t1=$(date +%s)

    if limpiar_identificadores < "$destino.parcial" > "$destino" 2>/dev/null; then
        rm -f "$destino.parcial"
    else
        mv "$destino.parcial" "$destino" 2>/dev/null
    fi

    printf '%s\t%s\t%s\t%s\n' "$clave" "$rc" "$(( t1 - t0 ))" "$*" >> "$CRUDO/_MANDOS.tsv"

    case "$rc" in
        0)   DiFlojo "$clave" ;;
        124) DiOjo   "$clave: se acabo el tiempo ($limite s)" ;;
        127) DiFlojo "$clave: ese mando no existe en este macOS" ;;
        *)   DiOjo   "$clave: termino con codigo $rc" ;;
    esac
    return $rc
}

# Si una captura salio bien. Se pregunta por la tabla, no por el fichero: un
# fichero vacio puede ser un mando que fue bien y no tenia nada que decir.
salio_bien() {
    [ -f "$CRUDO/_MANDOS.tsv" ] || return 1
    awk -F'\t' -v k="$1" '$1==k && $2=="0" { ok=1 } END { exit ok?0:1 }' "$CRUDO/_MANDOS.tsv"
}

codigo_de() {
    awk -F'\t' -v k="$1" '$1==k { c=$2 } END { if (c=="") c="?"; print c }' "$CRUDO/_MANDOS.tsv" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Los datos: una tabla clave / valor en un fichero
#
# En bash 3.2 no hay arrays asociativos, asi que el almacen es un TSV. Ademas
# resulta que es mejor: queda en la carpeta del informe, se puede abrir con
# cualquier cosa, y quien pruebe esto puede mandarlo tal cual para ver que ha
# entendido la aplicacion de su Mac.
#
# Si una clave se escribe dos veces, manda la ultima.
# ---------------------------------------------------------------------------
set_dato() {
    local clave="$1"; shift
    local valor="$*"
    valor=$(printf '%s' "$valor" | tr '\t\n\r' '   ' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    printf '%s\t%s\n' "$clave" "$valor" >> "$DATOS"
}

dato() {
    [ -f "$DATOS" ] || return 1
    awk -F'\t' -v k="$1" '$1==k { v=$2 } END { if (v!="") print v }' "$DATOS"
}

hay_dato() {
    local v
    v=$(dato "$1")
    [ -n "$v" ]
}

# Los datos sin repetir y en el orden en que se escribieron por primera vez.
datos_ordenados() {
    [ -f "$DATOS" ] || return 0
    awk -F'\t' '
        { v[$1]=$2; if (!($1 in visto)) { visto[$1]=1; orden[++n]=$1 } }
        END { for (i=1; i<=n; i++) printf "%s\t%s\n", orden[i], v[orden[i]] }
    ' "$DATOS"
}

# ---------------------------------------------------------------------------
# Los hallazgos y lo que no se ha podido mirar
#
# Van en dos listas distintas A PROPOSITO, y es la regla de PCDIAG que mas
# falta hace aqui: "cero panics" y "no he podido mirar los panics" NO son lo
# mismo, y en macOS la segunda va a pasar a todas horas por los permisos de
# privacidad. Meterlas en el mismo saco haria que la aplicacion dijera que
# todo esta bien cuando lo que pasa es que no ha podido mirar.
# ---------------------------------------------------------------------------
hallazgo() {   # gravedad(CRITICO|AVISO|INFO)  etiqueta  titulo  detalle
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$HALLAZGOS"
}

no_pude() {    # que  por-que
    printf '%s\t%s\n' "$1" "$2" >> "$NOPUDE"
}

cuantos_hallazgos() {
    [ -f "$HALLAZGOS" ] || { echo 0; return; }
    awk -F'\t' -v g="$1" '$1==g { n++ } END { print n+0 }' "$HALLAZGOS"
}

# ---------------------------------------------------------------------------
# Leer valores de las capturas
# ---------------------------------------------------------------------------

# De cualquier salida con forma "Clave: valor", que en macOS son casi todas:
# system_profiler, sw_vers, diskutil y tmutil la usan.
#
# Se parte por el PRIMER dos puntos y se recortan los espacios de los dos
# lados, en vez de comparar el principio de la linea. Hace falta: system_profiler
# sangra las claves, sw_vers pone un tabulador detras del colon y tmutil alinea
# los dos puntos con espacios ("Name          : Copias"). Comparando el texto
# tal cual, no acertaria ninguno de los tres.
campo_sp() {
    local f="$1"; local clave="$2"
    [ -f "$f" ] || return 1
    awk -v k="$clave" '
        {
            p = index($0, ":")
            if (p > 0) {
                izq = substr($0, 1, p - 1)
                der = substr($0, p + 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", izq)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", der)
                if (izq == k) { print der; exit }
            }
        }' "$f"
}

# De una salida de "ioreg":   "    \"CycleCount\" = 245"
campo_ioreg() {
    local f="$1"; local clave="$2"
    [ -f "$f" ] || return 1
    grep -o "\"$clave\" = [^,}]*" "$f" 2>/dev/null | head -1 | sed -E 's/^[^=]*= *//' | tr -d '"' | sed -E 's/[[:space:]]+$//'
}

# De "tmutil destinationinfo":  "sin destino" | "con destino" | "no se sabe"
#
# El codigo de salida NO sirve para esto, y la primera ejecucion en un Mac de
# verdad lo dejo claro: en Ventura el mando termina con codigo 0 tanto si hay
# destino como si no hay ninguno. Escrito a ciegas se supuso lo contrario -que
# fallaba en los dos casos- y el resultado fue que el aviso "este Mac no tiene
# copia de seguridad" no saltaba nunca. Solo el texto lo dice.
#
# Esta aqui, y no dentro del motor, para que se pueda probar con una captura y
# sin un Mac delante.
tm_estado_de() {
    local f="$1"
    [ -f "$f" ] || { echo "no se sabe"; return; }
    if grep -qiE 'No destinations configured' "$f" 2>/dev/null; then
        echo "sin destino"
    elif [ -n "$(campo_sp "$f" "Name")" ]; then
        echo "con destino"
    else
        echo "no se sabe"
    fi
}

# De "tmutil latestbackup": la ruta de la ultima copia, o nada.
#
# Tambien termina con codigo 0 escribiendo un error dentro ("Failed to mount
# backup destination, error: Error Domain=..."), y ese churro se guardaba como
# si fuera la fecha de la ultima copia. Una copia de verdad es una RUTA.
tm_ultima_de() {
    local f="$1"; local linea
    [ -f "$f" ] || return 0
    linea="$(head -1 "$f" 2>/dev/null)"
    case "$linea" in
        /*) printf '%s' "$linea" ;;
    esac
}

# De "du -sk": el total en kilobytes, si es que lo ha dado.
du_kb_de() {
    [ -f "$1" ] || return 0
    grep -E '^[0-9]+' "$1" 2>/dev/null | tail -1 | awk '{ print $1 }'
}

# De "du -sk": cuantas carpetas de dentro no ha dejado leer macOS.
#
# Hace falta porque "du" puede terminar con codigo 1 por unas cuantas carpetas
# de privacidad y AUN ASI imprimir un total. Ese total es un minimo, no la
# cifra: darlo por bueno es enseñar un numero corto como si fuera el completo.
du_vetadas_de() {
    local n
    [ -f "$1" ] || { echo 0; return; }
    n=$(grep -cE 'Operation not permitted|Permission denied' "$1" 2>/dev/null || true)
    es_numero "$n" || n=0
    echo "$n"
}

# De una salida de "df -k", buscando por punto de montaje (que es el ultimo
# campo). Devuelve: total_kb usado_kb libre_kb porcentaje
df_de() {
    local f="$1"; local punto="$2"
    [ -f "$f" ] || return 1
    awk -v p="$punto" 'NR>1 && $NF==p { gsub(/%/,"",$5); print $2, $3, $4, $5; exit }' "$f"
}

# ---------------------------------------------------------------------------
# Numeros
# ---------------------------------------------------------------------------
gb_de_kb() {   # kilobytes -> "12,3"
    [ -n "$1" ] || { echo ""; return; }
    printf '%s' "$1" | awk '{ printf "%.1f", $1/1048576 }'
}

es_numero() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# Texto para meterlo en sitios
# ---------------------------------------------------------------------------
esc_html() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

esc_json() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n\r\t'
}
