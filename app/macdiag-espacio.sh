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
#  La papelera, que es un caso aparte
#
#  macOS no deja medirla con "du" -contesta "Operation not permitted"- pero el
#  Finder si puede mirarla, porque el permiso lo tiene el.
#
#  Esto importa mas de lo que parece: sin preguntarle al Finder, la papelera
#  salia siempre como "no se ha podido medir", incluso estando VACIA. Y vacia y
#  no-he-podido-mirar no son lo mismo, que es la regla de la que cuelga medio
#  proyecto. Ahora se distinguen los tres casos: vacia, medida, o no se sabe.
# ---------------------------------------------------------------------------
papelera_cuantos() {
    osascript -e 'tell application "Finder" to return count of items of the trash' 2>/dev/null
}

# Devuelve:  <kilobytes>  <cuantos elementos han dado tamano>
#
# El Finder sabe lo que ocupa un FICHERO, pero de una CARPETA contesta "missing
# value": no lo calcula al vuelo. Asi que la suma puede dejarse elementos
# fuera, y entonces la cifra es un minimo y hay que decirlo. Es lo mismo que ya
# pasaba con "du" y las carpetas de privacidad: un total al que le falta un
# trozo no se presenta como si estuviera completo.
papelera_kb() {
    osascript -e 'tell application "Finder" to return size of every item of the trash' 2>/dev/null \
        | tr ',' '\n' \
        | awk '$1 ~ /^[0-9]+$/ { s += $1; n++ } END { printf "%d %d", s/1024, n+0 }'
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
#  Mandar a la papelera una carpeta o un fichero concreto
#
#      bash macdiag-espacio.sh --borrar-ruta "/ruta/de/la/cosa"
#
#  Las sugerencias de arriba son una lista cerrada a proposito, pero hace falta
#  poder senalar algo concreto: es lo que permite probar el mecanismo sin tocar
#  las carpetas del sistema, y lo que usara la ventana el dia que deje elegir
#  una carpeta a mano.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--borrar-ruta" ]; then
    shift
    Paso "Mandando a la papelera"
    n=0
    for ruta in "$@"; do
        if [ ! -e "$ruta" ]; then
            DiOjo "no existe: $ruta"
            continue
        fi
        # No se deja borrar cualquier cosa. Las carpetas de arriba del arbol y
        # las del sistema no se tocan ni por equivocacion: un fallo aqui no
        # tiene gracia ninguna.
        case "$ruta" in
            "$HOME"|"$HOME/"|/|/System*|/Library*|/usr*|/bin*|/sbin*|/Applications*)
                DiMal "me niego a tocar $ruta"; continue ;;
        esac
        tam="$(du -sh "$ruta" 2>/dev/null | awk '{print $1}')"
        if a_la_papelera "$ruta"; then
            DiOk "a la papelera: $(basename "$ruta") (${tam:-?})"
            n=$(( n + 1 ))
        else
            DiMal "no se ha podido mover: $ruta"
        fi
    done
    Di "$n elemento(s). Siguen en la papelera: se pueden sacar de ahi."
    exit 0
fi

# ---------------------------------------------------------------------------
#  Mirar QUE hay dentro de una carpeta, un nivel cada vez
#
#      bash macdiag-espacio.sh --ver "/ruta/de/la/carpeta"
#
#  Escribe en la salida un JSON con lo que hay colgando de esa carpeta y lo que
#  ocupa cada cosa, de mayor a menor. La ventana lo llama cada vez que alguien
#  despliega una carpeta.
#
#  POR QUE UN NIVEL CADA VEZ, y no el arbol entero de golpe: medir un disco
#  completo es recorrerlo entero. En el MacBook de las pruebas, con 187 GB
#  ocupados, eso son varios minutos con el ventilador a tope, y para cuando
#  termina el usuario ya ha cerrado la ventana. Midiendo solo lo que se abre,
#  cada paso tarda lo que tarda ESA carpeta y nada mas.
#
#  Tres cosas que se pagaron ya en este proyecto y que aqui vuelven a aplicar:
#
#  1. "du" imprime un total AUNQUE le falten trozos (trampa 15). Las carpetas
#     de privacidad contestan "Operation not permitted" y du sigue sumando lo
#     demas. Por eso cada linea lleva su estado: medido entero, medido en parte
#     o no se ha podido. Un numero al que le falta algo no se ensena como si
#     estuviera completo.
#  2. macOS no trae "timeout" (trampa 12), asi que se usa con_limite. Y si se
#     acaba el tiempo se DICE, en vez de ensenar lo que hubiera dado tiempo a
#     sumar, que seria un numero corto con cara de bueno.
#  3. Aqui NO se borra nada, ni se ofrece. El explorador es para mirar; lo que
#     se quiera tirar se abre en el Finder y lo hace la persona. Mandar a la
#     papelera cualquier ruta que se pueda desplegar -incluido /System- es un
#     poder que esta aplicacion no necesita tener.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--ver" ]; then
    RUTA="${2:-}"
    if [ -z "$RUTA" ] || [ ! -d "$RUTA" ]; then
        # Con TODOS los campos aunque no haya nada que contar. La ventana lo
        # descodifica en una estructura fija: si falta uno, no falla ese campo,
        # falla el JSON entero y el explorador se queda en blanco sin decir por
        # que. Es la trampa 2 -el fallo que no da error- esperando su turno.
        printf '{ "ruta": "%s", "estado": "no-existe", "vetadas": 0, "total_kb": 0, "entradas": [], "cuantas": 0, "recortada": false }\n' \
            "$(esc_json "$RUTA")"
        exit 0
    fi

    SALIDA="$(mktemp)"
    # DOS pasadas, y no una con "du -a -d 1", que es lo que uno escribe primero.
    # El du de macOS es el de BSD y su sintaxis dice  [-a | -s | -d depth]:
    # -a y -d SE EXCLUYEN. En Linux conviven y por eso se cuela. Aqui no da un
    # numero raro, da el "usage" entero y una lista vacia. Trampa 12 otra vez:
    # lo que macOS no trae -o no trae igual- que en Linux si.
    #
    #   1) las carpetas de este nivel, con lo que ocupan enteras
    #   2) los ficheros sueltos de este nivel, que es donde esta el .dmg de
    #      5 GB que uno viene buscando
    #
    # -x en las dos para no cruzar a otro disco: sin eso, mirar en "/" se mete
    # en el volumen de datos y cuenta las cosas dos veces.
    con_limite 60 du -xkd 1 "$RUTA" > "$SALIDA" 2>&1
    CODIGO=$?
    if [ "$CODIGO" != "124" ]; then
        con_limite 30 find "$RUTA" -maxdepth 1 -type f -exec du -k {} + >> "$SALIDA" 2>&1
    fi

    VETADAS="$(grep -cE 'Operation not permitted|Permission denied' "$SALIDA" 2>/dev/null || true)"
    es_numero "$VETADAS" || VETADAS=0

    if [ "$CODIGO" = "124" ]; then
        ESTADO="sin-tiempo"
    elif [ "$VETADAS" -gt 0 ]; then
        ESTADO="parcial"
    else
        ESTADO="medido"
    fi

    # La propia carpeta sale en la ultima linea de du: se aparta como total y
    # no se lista como si fuera hija de si misma.
    TOTAL_KB="$(awk -F'\t' -v r="$RUTA" '$2 == r { print $1 }' "$SALIDA" | tail -1)"
    es_numero "$TOTAL_KB" || TOTAL_KB=0

    printf '{\n'
    printf '  "ruta": "%s",\n'    "$(esc_json "$RUTA")"
    printf '  "estado": "%s",\n'  "$ESTADO"
    printf '  "vetadas": %s,\n'   "$VETADAS"
    printf '  "total_kb": %s,\n'  "$TOTAL_KB"
    printf '  "entradas": ['

    # Se cortan a 300. Una carpeta con diez mil ficheros sueltos no se lee de
    # un vistazo, que es justo para lo que sirve esto, y la ventana se atasca.
    # Si se corta se dice: "recortada" no es lo mismo que "esto es todo".
    CUANTAS=0
    PRIMERA="si"
    while IFS="$(printf '\t')" read -r kb ruta_h; do
        [ -n "$ruta_h" ] || continue
        [ "$ruta_h" = "$RUTA" ] && continue
        es_numero "$kb" || continue
        CUANTAS=$(( CUANTAS + 1 ))
        [ "$CUANTAS" -gt 300 ] && continue
        if [ -d "$ruta_h" ]; then carpeta="true"; else carpeta="false"; fi
        [ "$PRIMERA" = "si" ] && PRIMERA="no" || printf ','
        printf '\n    { "nombre": "%s", "ruta": "%s", "kb": %s, "carpeta": %s }' \
            "$(esc_json "$(basename "$ruta_h")")" "$(esc_json "$ruta_h")" "$kb" "$carpeta"
    done < <(grep -vE 'Operation not permitted|Permission denied|^du:' "$SALIDA" | sort -rn)

    printf '\n  ],\n'
    printf '  "cuantas": %s,\n' "$CUANTAS"
    if [ "$CUANTAS" -gt 300 ]; then printf '  "recortada": true\n'; else printf '  "recortada": false\n'; fi
    printf '}\n'
    rm -f "$SALIDA"
    exit 0
fi

# ---------------------------------------------------------------------------
#  Vaciar la papelera. Esto SI es definitivo, y por eso va aparte.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--vaciar-papelera" ]; then
    Paso "Vaciando la papelera"

    # PRIMERO: se puede siquiera MIRAR la papelera?
    #
    # Esto se vio probandolo: macOS protege ~/.Trash con el permiso de
    # privacidad, asi que "ls" contesta "Operation not permitted" mientras que
    # "mv" hacia dentro si funciona. Consecuencia: el bucle de abajo recorria
    # una lista vacia y esto decia tan tranquilo "0 elementos borrados", que es
    # la mentira exacta que este proyecto no se permite: no habia mirado.
    #
    # Si no se puede leer, se lo pedimos al Finder, que si tiene permiso. Y si
    # el Finder tampoco, se dice y no se finge.
    if ! ls "$HOME/.Trash" >/dev/null 2>&1; then
        DiOjo "macOS no deja a MacDiag mirar dentro de la papelera (permiso de privacidad)."
        DiFlojo "Se lo pido al Finder, que si puede."
        if osascript -e 'tell application "Finder" to empty the trash' >/dev/null 2>&1; then
            DiOk "Papelera vaciada por el Finder."
        else
            DiMal "El Finder tampoco ha podido, o se ha cancelado el permiso."
            Di ""
            Di "Dos salidas, y las dos las decides tu:"
            Di "  - Vaciarla a mano: clic derecho en la papelera del Dock."
            Di "  - O dar Acceso total al disco a MacDiag en Ajustes del Sistema >"
            Di "    Privacidad y seguridad, y volver a intentarlo."
            exit 1
        fi
    else
        n=0
        for cosa in "$HOME/.Trash"/* "$HOME/.Trash"/.??*; do
            [ -e "$cosa" ] || continue
            rm -rf "$cosa" 2>/dev/null && n=$(( n + 1 ))
        done
        DiOk "papelera del usuario: $n elemento(s) borrados"
    fi

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
        elif [ "$id" = "papelera" ]; then
            # du no ha podido; se lo preguntamos al Finder antes de rendirnos.
            n_pap="$(papelera_cuantos)"
            if [ "$n_pap" = "0" ]; then
                gb="0"; estado="vacia"
                DiOk "$titulo: vacia"
            elif es_numero "$n_pap"; then
                set -- $(papelera_kb)
                kb_pap="${1:-0}"; medidos="${2:-0}"
                if es_numero "$kb_pap" && [ "$kb_pap" -gt 0 ]; then
                    gb="$(gb_de_kb "$kb_pap")"
                    TOTAL_SEGURO="$(awk -v a="$TOTAL_SEGURO" -v b="$gb" 'BEGIN{printf "%.1f", a+b}')"
                    if [ "$medidos" -lt "$n_pap" ]; then
                        estado="medido en parte"
                        DiOjo "$titulo: $gb GB como minimo ($medidos de $n_pap elementos; del resto, que son carpetas, el Finder no sabe el tamano)"
                    else
                        estado="medido"
                        DiFlojo "$titulo: $gb GB en $n_pap elemento(s), segun el Finder"
                    fi
                else
                    estado="no se ha podido medir"
                    DiOjo "$titulo: hay $n_pap elemento(s), pero no se ha podido saber cuanto ocupan"
                fi
            else
                estado="no se ha podido medir"
                DiOjo "$titulo: no se ha podido medir (permisos de privacidad)"
            fi
        else
            estado="no se ha podido medir"
            DiOjo "$titulo: no se ha podido medir (permisos de privacidad)"
        fi
    fi
    # Lo que NO EXISTE no se ensena. Ofrecer "borrar los simuladores de Xcode"
    # en un Mac que no tiene Xcode es ruido: obliga a leer y descartar tres
    # lineas inutiles para llegar a la que importa. Si no esta, no hay nada
    # que decidir.
    if [ "$estado" = "no existe" ]; then
        continue
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
