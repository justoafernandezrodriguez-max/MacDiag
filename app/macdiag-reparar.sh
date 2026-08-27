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
NECESITA_REINICIO="no"

ultimo_informe() { ls -1dt "$BASE"/INFORMES/*/ 2>/dev/null | head -1; }
CRUDO_SOSP="$(ultimo_informe)crudo/_SOSPECHOSOS.tsv"

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
# ---------------------------------------------------------------------------
#  La cola de cosas que necesitan administrador
#
#  Se APUNTAN y se ejecutan TODAS DE UNA VEZ al final, en una sola peticion de
#  contrasena. Pedirla cinco veces seguidas para cinco arreglos es como enseñar
#  a alguien a teclear su contrasena sin leer lo que se la pide, que es
#  exactamente la costumbre que aprovecha el software que no deberia estar ahi.
#
#  MacDiag NO ve la contrasena en ningun momento: la pide macOS con su propio
#  dialogo y ejecuta el mandato ya con permisos.
# ---------------------------------------------------------------------------
COLA_ROOT=""
COLA_QUE=""

encolar_root() {   # <mandato>  <para que>
    [ -n "$COLA_ROOT" ] && COLA_ROOT="$COLA_ROOT; $1" || COLA_ROOT="$1"
    [ -n "$COLA_QUE" ] && COLA_QUE="$COLA_QUE, $2" || COLA_QUE="$2"
}

vaciar_cola_root() {
    [ -n "$COLA_ROOT" ] || return 0
    Paso "Permiso de administrador"
    Di "Hace falta para: $COLA_QUE."
    Di "Lo pide macOS con su ventana; MacDiag no ve la contrasena."
    local escapado
    escapado="$(printf '%s' "$COLA_ROOT" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    if osascript -e "do shell script \"$escapado\" with prompt \"MacDiag necesita permiso de administrador para: $COLA_QUE\" with administrator privileges" >/dev/null 2>&1; then
        DiOk "Hecho."
        COLA_ROOT=""; COLA_QUE=""
        return 0
    else
        DiOjo "Cancelado o sin permiso. No se ha cambiado nada de eso."
        COLA_ROOT=""; COLA_QUE=""
        return 1
    fi
}

aplicar() {
    case "$1" in

    quitar-arranque:*)
        # Quitar un arranque son TRES cosas, y en este orden: descargarlo para
        # que launchd no lo relance, parar el programa si esta vivo, y mandar
        # los ficheros a la papelera. Si se borra el fichero sin descargarlo,
        # launchd puede seguir con el en memoria hasta el proximo reinicio y
        # parece que no ha servido de nada.
        #
        # NO se borra el programa en si: puede ser de algo que el usuario use.
        destino="${1#quitar-arranque:}"
        Paso "Quitar de el arranque: $(basename "$destino")"
        if [ ! -s "$CRUDO_SOSP" ]; then
            DiOjo "No hay analisis reciente. Pulsa Analizar primero."
            return
        fi
        n=0
        while IFS=$'\t' read -r dest plist motivos etiq; do
            [ "$dest" = "$destino" ] || continue
            n=$(( n + 1 ))
            Di "- $(basename "$plist")"
            case "$plist" in
                "$HOME"/*) dominio="gui/$(id -u)" ;;
                *)         dominio="system" ;;
            esac
            encolar_root "launchctl bootout $dominio '$plist' 2>/dev/null || true" "quitar $etiq del arranque"
            encolar_root "mv '$plist' '$HOME/.Trash/' 2>/dev/null || true" "mandar su fichero a la papelera"
        done < "$CRUDO_SOSP"
        if [ "$n" -eq 0 ]; then
            DiOjo "Ya no esta en la lista: puede que se haya quitado antes."
            return
        fi
        pid_vivo="$(pgrep -f "$destino" 2>/dev/null | head -1)"
        [ -n "$pid_vivo" ] && encolar_root "kill -9 $pid_vivo 2>/dev/null || true" "parar el programa"
        DiFlojo "El programa en si ($destino) NO se borra: eso lo decides tu."
        ;;

    parar-proceso:*)
        pid="${1#parar-proceso:}"
        Paso "Parar el proceso $pid"
        if kill -0 "$pid" 2>/dev/null; then
            encolar_root "kill -9 $pid 2>/dev/null || true" "parar el proceso $pid"
        else
            DiFlojo "Ese proceso ya no esta en marcha."
        fi
        ;;

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

    encender-cortafuegos)
        Paso "Encender el cortafuegos"
        encolar_root "/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on >/dev/null" "encender el cortafuegos"
        Di "Si despues algun programa tuyo deja de recibir conexiones, en"
        Di "Ajustes > Red > Firewall > Opciones se le puede permitir uno a uno."
        ;;

    apagar-compartir)
        # OJO: si alguien esta trabajando contra este Mac en remoto, esto le
        # deja fuera. Por eso se avisa aunque se haga solo.
        Paso "Apagar Compartir pantalla"
        Di "AVISO: si ahora mismo hay alguien conectado en remoto a este Mac,"
        Di "se va a quedar fuera al aplicarse."
        encolar_root "launchctl disable system/com.apple.screensharing" "apagar Compartir pantalla"
        encolar_root "launchctl bootout system/com.apple.screensharing 2>/dev/null || true" "cerrar la sesion de pantalla compartida"
        ;;

    instalar-actualizaciones)
        # Puede tardar mucho y puede pedir reiniciar. Se instala igualmente y
        # se AVISA de que hay que reiniciar; reiniciar no lo hace MacDiag, lo
        # hace el usuario cuando le venga bien.
        Paso "Instalar las actualizaciones de Apple"
        Di "Esto puede tardar bastante y descarga de internet. No cierres la ventana."
        encolar_root "softwareupdate -i -a >/dev/null 2>&1 || true" "instalar las actualizaciones del sistema"
        NECESITA_REINICIO="si"
        ;;

    filevault-diferido)
        # "-defer" es lo unico honesto que se puede automatizar: macOS pide la
        # contrasena y ensena la clave de recuperacion al siguiente inicio de
        # sesion. Activarlo del todo a ciegas dejaria la clave de recuperacion
        # en un fichero, y esa clave es lo unico que salva el disco si se
        # olvida la contrasena.
        Paso "Preparar FileVault"
        encolar_root "fdesetup enable -defer /var/root/.fv-defer.plist >/dev/null 2>&1 || true" "dejar FileVault listo para activarse"
        Di "Se activara al cerrar y volver a iniciar sesion: macOS te pedira la"
        Di "contrasena y TE ENSENARA LA CLAVE DE RECUPERACION. Apuntala: sin ella"
        Di "y sin tu contrasena, el disco no se abre. Ni Apple puede."
        NECESITA_REINICIO="si"
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
    [ -n "$C" ] && awk -F'\t' '$5!="" && $5!="-" { printf "%s\t%s\n", $5, $3 }' "${C}hallazgos.tsv" 2>/dev/null
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
        # SEIS campos, no cinco. Esto se pago: al anadir los pasos, el fichero
        # paso a tener un campo mas y aqui se seguian leyendo cinco, asi que la
        # accion se llevaba los pasos pegados detras:
        #
        #     quitar-arranque:/opt/xmrig/xmrig<TAB>MacDiag descarga el arranque...
        #
        # Ese destino no coincidia con nada y "Reparar todo" NO REPARABA. Y los
        # hallazgos sin accion heredaban los pasos como si fueran una, asi que
        # se intentaba aplicar una frase.
        #
        # No dio ningun error: los arreglos simplemente no pasaban. Es la trampa
        # 2 otra vez -el fallo que no da error- y la razon de que exista la
        # prueba que cuenta los campos.
        while IFS=$'\t' read -r gr et ti de ac pasos; do
            ac="$(sin_guion "$ac")"; pasos="$(sin_guion "$pasos")"
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

        vaciar_cola_root

        # Reiniciar NO lo hace MacDiag. Se dice y lo decide el usuario: un
        # programa que reinicia el equipo por su cuenta se lleva por delante lo
        # que estuvieras haciendo.
        if [ "$NECESITA_REINICIO" = "si" ]; then
            Paso "Falta reiniciar"
            Di "Algo de lo aplicado no termina hasta que reinicies."
            Di "MacDiag no reinicia solo a proposito: hazlo tu cuando te venga bien."
        fi

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
        vaciar_cola_root
    fi
    ;;

*)
    echo "Uso: macdiag-reparar.sh --listar | --aplicar --todo | --aplicar <accion>... | --instantanea"
    exit 1
    ;;
esac
exit 0
