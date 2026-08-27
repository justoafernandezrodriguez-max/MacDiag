#!/bin/bash
# ---------------------------------------------------------------------------
#  MacDiag - motor de reparacion
#
#      bash macdiag-reparar.sh --listar
#      bash macdiag-reparar.sh --aplicar --todo
#      bash macdiag-reparar.sh --aplicar <accion> [accion...]
#      bash macdiag-reparar.sh --instantanea
#
#  LO QUE ESTE MOTOR NO HACE, Y NO ES QUE FALTE
#
#  En macOS el mantenimiento es un mercadillo, y una herramienta seria se
#  distingue por lo que se niega a hacer. Aqui no hay "reparar permisos" -se
#  quito en 2015 porque el sistema ya se protege solo-, no hay "liberar RAM"
#  -la memoria en cache es memoria bien usada-, y no se lanzan a mano los
#  scripts periodicos del sistema, que ya los lanza el sistema.
#
#  Tampoco hay equivalente de "sfc" ni de "DISM": desde Big Sur el volumen del
#  sistema va sellado y verificado, y si se rompe el sello lo que toca es
#  reinstalar macOS. Fingir que existe seria mentir.
#
#  Y hay una categoria entera que NINGUN programa puede hacer por su cuenta:
#  encender FileVault o instalar una actualizacion del sistema exigen una
#  persona delante. Esas se marcan "abrir:" y lo unico honesto es llevar al
#  usuario al sitio exacto, no fingir que se han hecho.
# ---------------------------------------------------------------------------

AQUI="$(cd "$(dirname "$0")" && pwd)"
. "$AQUI/lib-comun.sh"

export LC_ALL=C
BASE="$HOME/MacDiag"

ultimo_informe() { ls -1dt "$BASE"/INFORMES/*/ 2>/dev/null | head -1; }

# ---------------------------------------------------------------------------
#  Pedir la contrasena SOLO para la accion que la necesita
#
#  La pide el propio macOS con su dialogo de siempre, diciendo que programa la
#  pide. MacDiag no ve la contrasena ni la guarda en ningun sitio. Y es la
#  regla del proyecto: una herramienta de diagnostico que arranca pidiendo la
#  contrasena es una herramienta en la que nadie confia; se pide para ESTO y
#  diciendo para que.
# ---------------------------------------------------------------------------
con_administrador() {
    local mandato="$1"; local porque="$2"
    osascript -e "do shell script \"$mandato\" with prompt \"MacDiag necesita permiso de administrador para: $porque\" with administrator privileges" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
#  Las acciones
# ---------------------------------------------------------------------------
aplicar() {
    case "$1" in

    instantanea)
        # El equivalente del punto de restauracion de Windows. No es un
        # invento: es lo que usa el propio Time Machine, y desde Recuperacion
        # se puede volver a el.
        Paso "Punto de restauracion"
        salida="$(tmutil localsnapshot 2>&1)"
        if printf '%s' "$salida" | grep -qiE 'Created local snapshot'; then
            DiOk "Hecho: $(printf '%s' "$salida" | tr -d '\n')"
            Di "Para volver aqui: apagar, arrancar en Recuperacion y elegir esta fecha."
        else
            DiMal "No se ha podido crear la instantanea."
            DiFlojo "$salida"
            Di "Suele ser que el disco no es APFS, o que no queda sitio."
        fi
        ;;

    gatekeeper)
        Paso "Volver a encender Gatekeeper"
        if con_administrador "spctl --master-enable" "volver a encender Gatekeeper"; then
            estado="$(spctl --status 2>&1)"
            if printf '%s' "$estado" | grep -qi 'assessments enabled'; then
                DiOk "Gatekeeper encendido."
            else
                DiOjo "Se ha ejecutado, pero sigue diciendo: $estado"
            fi
        else
            DiOjo "Cancelado o sin permiso. Gatekeeper sigue como estaba."
        fi
        ;;

    launchservices)
        # Arregla los menus "Abrir con" llenos de duplicados. No borra nada:
        # reconstruye un indice que el sistema rehace solo.
        Paso "Reconstruir la lista de 'Abrir con'"
        LS="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if [ -x "$LS" ]; then
            "$LS" -kill -r -domain local -domain system -domain user >/dev/null 2>&1
            DiOk "Reconstruida. Los duplicados del menu 'Abrir con' desaparecen."
        else
            DiOjo "No esta lsregister en esta version de macOS."
        fi
        ;;

    cachesfuentes)
        Paso "Limpiar las caches de tipografias"
        if atsutil databases -removeUser >/dev/null 2>&1; then
            DiOk "Hecho. Si habia letras que salian mal, se arregla al reiniciar."
        else
            DiOjo "atsutil no ha podido con ello."
        fi
        ;;

    dns)
        Paso "Vaciar la cache de nombres (DNS)"
        if con_administrador "dscacheutil -flushcache; killall -HUP mDNSResponder" "vaciar la cache de DNS"; then
            DiOk "Cache de DNS vaciada."
        else
            DiOjo "Cancelado o sin permiso."
        fi
        ;;

    verificar-disco)
        # Verifica, NO repara. El volumen de arranque no se repara en caliente:
        # para eso esta Recuperacion, y eso lo hace una persona, no un script
        # sin nadie delante.
        Paso "Verificar el disco"
        salida="$(diskutil verifyVolume / 2>&1)"
        printf '%s\n' "$salida" | tail -6 | while read -r l; do DiFlojo "$l"; done
        if printf '%s' "$salida" | grep -qiE 'appears to be OK|parece estar bien'; then
            DiOk "El disco dice que esta bien."
        else
            DiOjo "Revisa lo de arriba. Reparar de verdad se hace desde Recuperacion, no en caliente."
        fi
        ;;

    abrir:filevault)
        Paso "FileVault"
        open "x-apple.systempreferences:com.apple.preference.security?FDE" 2>/dev/null \
            || open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension" 2>/dev/null
        Di "Te he abierto los ajustes. Esto lo tienes que encender tu: macOS no deja"
        Di "que lo haga un programa, porque hay que guardar la clave de recuperacion."
        ;;

    abrir:actualizaciones)
        Paso "Actualizaciones del sistema"
        open "x-apple.systempreferences:com.apple.preferences.softwareupdate" 2>/dev/null
        Di "Te he abierto Actualizacion de software. No las instalo yo a proposito:"
        Di "algunas reinician el equipo y eso lo decides tu."
        ;;

    abrir:timemachine)
        Paso "Time Machine"
        open "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension" 2>/dev/null \
            || open "x-apple.systempreferences:com.apple.prefs.backup" 2>/dev/null
        Di "Te he abierto Time Machine. Conecta un disco externo y elige 'Anadir disco'."
        ;;

    abrir:cortafuegos)
        Paso "Cortafuegos"
        open "x-apple.systempreferences:com.apple.preference.security?Firewall" 2>/dev/null \
            || open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension" 2>/dev/null
        Di "Te he abierto los ajustes. El interruptor es 'Firewall'."
        Di "No lo enciendo yo: puede cortar programas tuyos que esperan conexiones,"
        Di "y eso tienes que verlo tu antes."
        ;;

    abrir:compartir)
        Paso "Compartir"
        open "x-apple.systempreferences:com.apple.preferences.sharing" 2>/dev/null \
            || open "x-apple.systempreferences:com.apple.Sharing-Settings.extension" 2>/dev/null
        Di "Te he abierto Compartir. Si no usas 'Compartir pantalla', apagalo."
        Di "No lo apago yo por si estas trabajando en remoto ahora mismo: te dejaria fuera."
        ;;

    abrir:arranque)
        # No se quita nada solo, y esto NO es prudencia de mas: un elemento de
        # arranque puede ser de un programa que si se usa, y quitarlo a ciegas
        # lo rompe. Se abre la carpeta para que se vea con nombres y fechas.
        Paso "Lo que arranca solo"
        open /Library/LaunchDaemons 2>/dev/null
        Di "Te he abierto la carpeta. MacDiag NO quita nada de aqui a proposito:"
        Di "algunos son de programas que si usas, y borrar el que no toca los rompe."
        Di ""
        Di "Para quitar uno, cuando estes seguro de que no es tuyo:"
        Di "    sudo launchctl bootout system/LA-ETIQUETA"
        Di "    sudo rm '/Library/LaunchDaemons/EL-FICHERO.plist'"
        Di ""
        Di "Y mira antes a que programa apunta, porque el fichero de arranque"
        Di "suele ser solo la punta: el programa sigue en el disco."
        ;;

    abrir:almacenamiento)
        Paso "Almacenamiento"
        open "x-apple.systempreferences:com.apple.settings.Storage" 2>/dev/null \
            || open "x-apple.systempreferences:com.apple.storage" 2>/dev/null
        Di "Te he abierto Almacenamiento. En la pestana Mantenimiento de MacDiag"
        Di "tienes lo mismo pero diciendo que es cada cosa."
        ;;

    *)
        DiOjo "No se que es la accion \"$1\"."
        ;;
    esac
}

# ---------------------------------------------------------------------------
case "${1:-}" in

--instantanea)
    aplicar instantanea
    ;;

--listar)
    C="$(ultimo_informe)"
    [ -n "$C" ] && awk -F'\t' '$5!="" { printf "%s\t%s\n", $5, $3 }' "${C}hallazgos.tsv" 2>/dev/null
    ;;

--aplicar)
    shift
    if [ "${1:-}" = "--todo" ]; then
        C="$(ultimo_informe)"
        if [ -z "$C" ]; then
            DiMal "No hay ningun analisis todavia. Pulsa Analizar primero."
            exit 1
        fi
        # Lo automatico se aplica. Lo que necesita una persona se ENUMERA pero
        # no se abre: abrir cuatro paneles de Ajustes de golpe no ayuda a nadie.
        automaticas=""; manuales=""
        while IFS=$'\t' read -r gr et ti de ac; do
            [ -n "$ac" ] || continue
            case "$ac" in
                abrir:*) manuales="$manuales$ac|$ti
" ;;
                *)       automaticas="$automaticas$ac
" ;;
            esac
        done < "${C}hallazgos.tsv"

        if [ -z "$automaticas" ] && [ -z "$manuales" ]; then
            Paso "Reparar"
            Di "No hay nada que MacDiag pueda reparar de lo que ha encontrado."
            exit 0
        fi

        printf '%s' "$automaticas" | sort -u | while read -r a; do
            [ -n "$a" ] && aplicar "$a"
        done

        if [ -n "$manuales" ]; then
            Paso "Esto no lo puede hacer un programa"
            printf '%s' "$manuales" | while IFS='|' read -r a t; do
                [ -n "$t" ] && Di "- $t"
            done
            Di ""
            Di "Marcalo en la lista y pulsa 'Reparar lo seleccionado': te llevo al sitio."
        fi
    else
        for a in "$@"; do aplicar "$a"; done
    fi
    ;;

*)
    echo "Uso: macdiag-reparar.sh --listar | --aplicar --todo | --aplicar <accion>... | --instantanea"
    exit 1
    ;;
esac
exit 0
