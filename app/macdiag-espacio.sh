#!/bin/bash
# ---------------------------------------------------------------------------
#  MacDiag - motor de mantenimiento del espacio
#
#  Mide TODOS los discos montados y las carpetas que suelen ocupar sin que
#  nadie lo sepa, y deja un mapa en ~/MacDiag/espacio.json que lee la ventana.
#
#      bash macdiag-espacio.sh                  mide y escribe el mapa
#      bash macdiag-espacio.sh --borrar id...   manda esas cosas A LA PAPELERA
#      bash macdiag-espacio.sh --vaciar-papelera
#
#  DOS REGLAS QUE NO SE TOCAN:
#
#  1. Borrar es MANDAR A LA PAPELERA. Nunca "rm" sobre lo que elige el usuario.
#     Un programa de mantenimiento que destruye ficheros sin vuelta atras es un
#     programa en el que no se puede confiar, y aqui la vuelta atras la da el
#     propio sistema gratis. Lo unico definitivo es vaciar la papelera, y eso
#     se pide aparte y se avisa.
#
#  2. Lo que NO es basura del sistema va marcado como tuyo y no se suma al
#     total de "esto sobra". La carpeta de Descargas son ficheros del usuario:
#     se ensena porque suele ser lo mas grande, pero no se sugiere borrarla.
# ---------------------------------------------------------------------------

AQUI="$(cd "$(dirname "$0")" && pwd)"
. "$AQUI/lib-comun.sh"

export LC_ALL=C

BASE="$HOME/MacDiag"
MAPA="$BASE/espacio.json"
CRUDO="$BASE/.espacio-crudo"
mkdir -p "$CRUDO" 2>/dev/null

# ---------------------------------------------------------------------------
#  Mandar a la papelera
#
#  Se mueve a mano en vez de pedirselo al Finder con osascript: hacerlo por el
#  Finder exige el permiso de automatizacion, que saca un dialogo que la gente
#  no entiende y que si se deniega deja el mantenimiento inservible. Moviendo
#  el fichero se consigue lo mismo -queda en la papelera y se puede sacar- sin
#  pedir nada.
#
#  Si ya hay algo con ese nombre en la papelera se le pone la hora detras, que
#  es lo que hace el propio Finder. Sin eso, el segundo borrado pisa al primero.
# ---------------------------------------------------------------------------
a_la_papelera() {
    local origen="$1"
    local nombre destino
    [ -e "$origen" ] || return 1
    nombre="$(basename "$origen")"
    destino="$HOME/.Trash/$nombre"
    if [ -e "$destino" ]; then
        destino="$HOME/.Trash/$nombre $(date +%H-%M-%S)"
    fi
    mv "$origen" "$destino" 2>/dev/null
}

# Vacia el CONTENIDO de una carpeta sin borrar la carpeta.  Las de cache y
# registros tienen que seguir existiendo: el sistema las da por hechas.
contenido_a_la_papelera() {
    local carpeta="$1"; local n=0
    [ -d "$carpeta" ] || return 1
    for cosa in "$carpeta"/* "$carpeta"/.??*; do
        [ -e "$cosa" ] || continue
        a_la_papelera "$cosa" && n=$(( n + 1 ))
    done
    echo "$n"
}

# ---------------------------------------------------------------------------
#  Las carpetas candidatas
#
#  campo 1: id        (lo que manda la ventana al borrar)
#  campo 2: ruta
#  campo 3: seguro    si = basura del sistema | no = ficheros del usuario
#  campo 4: como      contenido = vaciar por dentro | entera = mover entera
#  campo 5: titulo
#  campo 6: explicacion
# ---------------------------------------------------------------------------
candidatas() {
    cat <<'LISTA'
caches	$HOME/Library/Caches	si	contenido	Caches del usuario	Ficheros temporales que las aplicaciones rehacen solas la proxima vez. Borrarlas no pierde nada tuyo; como mucho, alguna aplicacion tarda un poco mas la primera vez.
logs	$HOME/Library/Logs	si	contenido	Registros del usuario	Diarios de lo que han hecho las aplicaciones. Solo sirven para investigar un fallo concreto.
ios	$HOME/Library/Application Support/MobileSync/Backup	si	contenido	Copias de iPhone y iPad	Copias de seguridad antiguas de moviles hechas desde este Mac. Suelen ser decenas de gigas y casi nadie sabe que estan ahi. OJO: si es la unica copia de un movil que ya no tienes, no la borres.
xcode	$HOME/Library/Developer/Xcode/DerivedData	si	contenido	Restos de compilacion de Xcode	Resultados intermedios de compilar. Xcode los rehace cuando hacen falta.
simulador	$HOME/Library/Developer/CoreSimulator/Devices	si	contenido	Simuladores de Xcode	Los iPhone y iPad de mentira que usa Xcode para probar. Se vuelven a crear.
papelera	$HOME/.Trash	si	contenido	La papelera	Lo que ya mandaste a la papelera y sigue ocupando sitio. Vaciarla es definitivo.
descargas	$HOME/Downloads	no	entera	Carpeta de Descargas	Ficheros TUYOS. Se ensena porque suele ser lo mas grande que se puede vaciar a mano, pero eso lo decides tu mirando lo que hay dentro.
LISTA
}

# ---------------------------------------------------------------------------
#  Borrar lo que diga la ventana
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--borrar" ]; then
    shift
    Paso "Mandando a la papelera"
    total=0
    for id in "$@"; do
        linea="$(candidatas | awk -F'\t' -v k="$id" '$1==k')"
        if [ -z "$linea" ]; then
            DiOjo "no se que es \"$id\", me lo salto"
            continue
        fi
        ruta="$(printf '%s' "$linea" | cut -f2)"
        como="$(printf '%s' "$linea" | cut -f4)"
        titulo="$(printf '%s' "$linea" | cut -f5)"
        ruta="$(eval printf '%s' "\"$ruta\"")"

        if [ ! -e "$ruta" ]; then
            DiFlojo "$titulo: ya no existe"
            continue
        fi
        if [ "$como" = "contenido" ]; then
            n="$(contenido_a_la_papelera "$ruta")"
            es_numero "$n" || n=0
            DiOk "$titulo: $n elemento(s) a la papelera"
            total=$(( total + n ))
        else
            if a_la_papelera "$ruta"; then
                DiOk "$titulo: a la papelera"
                total=$(( total + 1 ))
            else
                DiMal "$titulo: no se ha podido mover"
            fi
        fi
    done
    Di "$total elemento(s) en total. Siguen en la papelera: nada se ha destruido."
    exit 0
fi

# ---------------------------------------------------------------------------
#  Vaciar la papelera. Esto SI es definitivo, y por eso va aparte.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--vaciar-papelera" ]; then
    Paso "Vaciando la papelera"
    n=0
    for cosa in "$HOME/.Trash"/* "$HOME/.Trash"/.??*; do
        [ -e "$cosa" ] || continue
        rm -rf "$cosa" 2>/dev/null && n=$(( n + 1 ))
    done
    DiOk "papelera del usuario: $n elemento(s) borrados"

    # Las papeleras de los discos externos son otra carpeta distinta, y es de
    # las cosas que mas sitio ocupan sin que nadie caiga.
    for v in /Volumes/*/; do
        t="$v.Trashes/$(id -u)"
        [ -d "$t" ] || continue
        m=0
        for cosa in "$t"/*; do
            [ -e "$cosa" ] || continue
            rm -rf "$cosa" 2>/dev/null && m=$(( m + 1 ))
        done
        [ "$m" -gt 0 ] && DiOk "papelera de $(basename "$v"): $m elemento(s)"
    done
    Di "Hecho. Esto no tiene vuelta atras."
    exit 0
fi

# ---------------------------------------------------------------------------
#  Medir
# ---------------------------------------------------------------------------
printf '\n  %sMacDiag %s%s  -  espacio en disco\n' "$_C_FUERTE" "$VERSION_MACDIAG" "$_C_FIN"

Paso "Los discos"
df -k > "$CRUDO/df.txt" 2>&1

# Un nombre que entienda una persona. El punto de montaje no lo es:
# "/System/Volumes/VM" no le dice nada a nadie.
nombre_de() {
    case "$1" in
        /)                        echo "Macintosh HD (sistema, sellado)" ;;
        /System/Volumes/Data)     echo "Macintosh HD - tus datos" ;;
        /System/Volumes/VM)       echo "Intercambio (memoria en disco)" ;;
        /System/Volumes/Preboot)  echo "Arranque" ;;
        /System/Volumes/Update)   echo "Actualizaciones" ;;
        /Volumes/*)               basename "$1" ;;
        *)                        echo "$1" ;;
    esac
}
tipo_de() {
    case "$1" in
        /Volumes/*)           echo "externo" ;;
        /System/Volumes/Data) echo "interno" ;;
        *)                    echo "sistema" ;;
    esac
}

DISCOS_JSON=""
primero=1
while read -r fs bloques usado libre pct resto; do
    case "$fs" in /dev/*) ;; *) continue ;; esac
    punto="$(printf '%s' "$resto" | sed -E 's/^[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+%[[:space:]]+//')"
    [ -n "$punto" ] || continue
    pct="${pct%\%}"
    n="$(nombre_de "$punto")"
    t="$(tipo_de "$punto")"
    DiFlojo "$n  ($(gb_de_kb "$usado") de $(gb_de_kb "$bloques") GB, $pct %)"
    [ "$primero" -eq 1 ] || DISCOS_JSON="$DISCOS_JSON,"
    DISCOS_JSON="$DISCOS_JSON
    { \"nombre\": \"$(esc_json "$n")\", \"punto\": \"$(esc_json "$punto")\", \"total_gb\": \"$(gb_de_kb "$bloques")\", \"usado_gb\": \"$(gb_de_kb "$usado")\", \"libre_gb\": \"$(gb_de_kb "$libre")\", \"pct\": \"$pct\", \"tipo\": \"$t\" }"
    primero=0
done < <(tail -n +2 "$CRUDO/df.txt")

Paso "Que se podria liberar"

SUG_JSON=""
primero=1
TOTAL_SEGURO=0
while IFS=$'\t' read -r id ruta seguro como titulo explica; do
    [ -n "$id" ] || continue
    ruta_real="$(eval printf '%s' "\"$ruta\"")"
    gb=""; estado="no existe"
    if [ -d "$ruta_real" ]; then
        capturar "du_$id" 90 du -sk "$ruta_real" >/dev/null 2>&1
        kb="$(du_kb_de "$CRUDO/du_$id.txt")"
        vetadas="$(du_vetadas_de "$CRUDO/du_$id.txt")"
        if es_numero "$kb"; then
            gb="$(gb_de_kb "$kb")"
            if [ "$vetadas" -gt 0 ]; then estado="medido en parte"; else estado="medido"; fi
            if [ "$seguro" = "si" ]; then
                TOTAL_SEGURO="$(awk -v a="$TOTAL_SEGURO" -v b="$gb" 'BEGIN{printf "%.1f", a+b}')"
            fi
            DiFlojo "$titulo: $gb GB"
        else
            estado="no se ha podido medir"
            DiOjo "$titulo: no se ha podido medir (permisos de privacidad)"
        fi
    fi
    [ "$primero" -eq 1 ] || SUG_JSON="$SUG_JSON,"
    SUG_JSON="$SUG_JSON
    { \"id\": \"$(esc_json "$id")\", \"titulo\": \"$(esc_json "$titulo")\", \"ruta\": \"$(esc_json "$ruta_real")\", \"gb\": \"${gb:-0}\", \"estado\": \"$(esc_json "$estado")\", \"seguro\": \"$seguro\", \"explica\": \"$(esc_json "$explica")\" }"
    primero=0
done < <(candidatas)

{
    printf '{\n'
    printf '  "discos": [%s\n  ],\n' "$DISCOS_JSON"
    printf '  "sugerencias": [%s\n  ],\n' "$SUG_JSON"
    printf '  "total_seguro_gb": "%s"\n' "$TOTAL_SEGURO"
    printf '}\n'
} > "$MAPA"

Paso "Listo"
Di "Sobran unos $TOTAL_SEGURO GB de cosas que no hacen falta."
DiFlojo "Mapa: $MAPA"
exit 0
