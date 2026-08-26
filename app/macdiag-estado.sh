#!/bin/bash
# ---------------------------------------------------------------------------
#  MacDiag - motor de estado
#
#  Mira como esta este Mac y deja un informe. NO TOCA NADA: solo lee.
#
#  OJO: ESCRITO SIN PODER PROBARLO EN NINGUN MAC. Ver LEEME.txt.
#
#  Se puede lanzar solo, sin el menu:
#      bash macdiag-estado.sh
#
#  Deja todo en  ~/MacDiag/INFORMES/<fecha-hora>/ :
#      crudo/            la salida de cada mando, tal cual
#      datos.tsv         lo que la aplicacion ha entendido de esas salidas
#      hallazgos.tsv     lo que hay que mirar
#      no-he-podido.tsv  lo que NO se ha podido comprobar, y por que
#      informe.html      lo que lee una persona
#      informe.json      lo mismo para una maquina
# ---------------------------------------------------------------------------

AQUI="$(cd "$(dirname "$0")" && pwd)"
. "$AQUI/lib-comun.sh"
. "$AQUI/lib-informe.sh"

# ---------------------------------------------------------------------------
# El idioma, fijado a proposito
#
# Dos motivos, y los dos muerden en silencio:
#
#  - En un Mac configurado en español, algunos mandos contestan traducido, y
#    MacDiag busca textos como "Operation not permitted" para saber que le
#    falta un permiso. Traducido, no lo encontraria: no daria un error, daria
#    la respuesta equivocada, que es peor.
#  - El separador decimal. Con locale español, awk puede escribir "12,3" en vez
#    de "12.3", y la suma siguiente se queda en cero sin quejarse.
# ---------------------------------------------------------------------------
export LC_ALL=C

# ---------------------------------------------------------------------------
# Donde se deja todo
#
# En la raiz de la carpeta de inicio A PROPOSITO, no en ~/Documents. Documentos,
# Escritorio y Descargas estan protegidas por el sistema de privacidad y hacen
# salir un dialogo de permiso a la Terminal. La raiz del home no.
# ---------------------------------------------------------------------------
BASE="$HOME/MacDiag"
SELLO="$(date +%Y-%m-%d-%H%M%S)"
TRABAJO="$BASE/INFORMES/$SELLO"
CRUDO="$TRABAJO/crudo"
DATOS="$TRABAJO/datos.tsv"
HALLAZGOS="$TRABAJO/hallazgos.tsv"
NOPUDE="$TRABAJO/no-he-podido.tsv"
HISTORIAL="$BASE/historial.jsonl"

mkdir -p "$CRUDO" || { echo "No se ha podido crear $CRUDO"; exit 1; }
: > "$DATOS"; : > "$HALLAZGOS"; : > "$NOPUDE"; : > "$CRUDO/_MANDOS.tsv"

EMPEZO=$(date +%s)

printf '\n  %sMacDiag %s%s  -  como esta este Mac\n' "$_C_FUERTE" "$VERSION_MACDIAG" "$_C_FIN"
printf '  %sSolo lee. No borra ni cambia nada.%s\n' "$_C_GRIS" "$_C_FIN"

# ---------------------------------------------------------------------------
# Antes de nada: esto es un Mac, y de que epoca
#
# Se comprueba y se dice, no se supone. La version decide que mandos existen:
# "systemextensionsctl" es de Catalina en adelante, y los informes de fallo son
# .ips desde Monterey y .crash antes.
# ---------------------------------------------------------------------------
Paso "El sistema"

if [ "$(uname -s 2>/dev/null)" != "Darwin" ]; then
    DiMal "Esto no es un Mac: MacDiag solo funciona sobre macOS."
    exit 1
fi

capturar "sw_vers"        10 sw_vers
capturar "uname"          10 uname -a
capturar "hardware"       60 system_profiler SPHardwareDataType
capturar "cpu_intel"      10 sysctl -n machdep.cpu.brand_string
capturar "uptime"         10 uptime

VERSION_SO="$(campo_sp "$CRUDO/sw_vers.txt" "ProductVersion")"
set_dato "so.version" "$VERSION_SO"
set_dato "so.build"   "$(campo_sp "$CRUDO/sw_vers.txt" "BuildVersion")"
set_dato "so.nombre"  "$(campo_sp "$CRUDO/sw_vers.txt" "ProductName")"

MAYOR="$(printf '%s' "$VERSION_SO" | cut -d. -f1)"
MENOR="$(printf '%s' "$VERSION_SO" | cut -d. -f2)"
es_numero "$MAYOR" || MAYOR=0
es_numero "$MENOR" || MENOR=0
set_dato "so.mayor" "$MAYOR"

if [ "$MAYOR" -eq 0 ]; then
    no_pude "La version de macOS" "sw_vers no ha contestado nada que se pueda leer"
elif [ "$MAYOR" -lt 11 ] && [ "$MAYOR" -ne 10 ]; then
    no_pude "La version de macOS" "sw_vers ha contestado algo raro: $VERSION_SO"
elif [ "$MAYOR" -eq 10 ] && [ "$MENOR" -lt 15 ]; then
    hallazgo "AVISO" "SISTEMA" "Este macOS es muy antiguo ($VERSION_SO)" \
        "MacDiag esta pensado de Catalina (10.15) en adelante. Va a funcionar a medias: hay mandos que en esta version no existen, y salen en la lista de lo que no se ha podido comprobar."
fi

set_dato "meta.uptime" "$(sed -E 's/^.*up +//; s/, *[0-9]+ users?.*$//; s/, *load average.*$//' "$CRUDO/uptime.txt" 2>/dev/null | head -1)"
set_dato "maq.arquitectura" "$(uname -m 2>/dev/null)"
set_dato "maq.modelo"       "$(campo_sp "$CRUDO/hardware.txt" "Model Name")"
set_dato "maq.identificador" "$(campo_sp "$CRUDO/hardware.txt" "Model Identifier")"
set_dato "maq.memoria"      "$(campo_sp "$CRUDO/hardware.txt" "Memory")"
# "Chip" en los Apple Silicon, "Processor Name" en los Intel. El tercer intento
# solo se usa si el mando FUE BIEN: en un Apple Silicon ese sysctl no existe y
# el fichero contiene el mensaje de error, asi que copiarlo sin mirar pondria
# "sysctl: unknown oid" como nombre del procesador.
CHIP="$(campo_sp "$CRUDO/hardware.txt" "Chip")"
[ -n "$CHIP" ] || CHIP="$(campo_sp "$CRUDO/hardware.txt" "Processor Name")"
if [ -z "$CHIP" ] && salio_bien "cpu_intel"; then
    CHIP="$(head -1 "$CRUDO/cpu_intel.txt" 2>/dev/null)"
fi
set_dato "maq.chip" "$CHIP"
set_dato "maq.nucleos" "$(campo_sp "$CRUDO/hardware.txt" "Total Number of Cores")"

if ! salio_bien "hardware"; then
    no_pude "Los datos de la maquina" "system_profiler SPHardwareDataType no ha ido bien (codigo $(codigo_de hardware))"
fi

# ---------------------------------------------------------------------------
# Los discos
#
# Se enseñan DOS numeros a proposito, y hace falta explicarlo en el informe:
# en un disco APFS el espacio libre no es una sola cifra. El sistema cuenta
# como ocupado lo "purgable" -instantaneas locales, caches que soltaria si
# hiciera falta- y el Finder cuenta otra cosa. Dar un solo numero sin decir
# cual es hace que el usuario borre cosas que no hacia falta borrar.
# ---------------------------------------------------------------------------
Paso "Los discos"

capturar "df"             20 df -k
capturar "diskutil_lista" 30 diskutil list
capturar "diskutil_raiz"  30 diskutil info /
capturar "diskutil_datos" 30 diskutil info /System/Volumes/Data
capturar "diskutil_disk0" 30 diskutil info disk0
capturar "apfs"           30 diskutil apfs list
capturar "snapshots"      30 tmutil listlocalsnapshots /

# El volumen que de verdad se llena es el de DATOS. La raiz "/" en un Mac
# moderno es la instantanea sellada del sistema y casi no cambia: mirar solo
# ahi diria que el disco esta vacio con el equipo a reventar.
PUNTO="/System/Volumes/Data"
LINEA="$(df_de "$CRUDO/df.txt" "$PUNTO")"
if [ -z "$LINEA" ]; then
    PUNTO="/"
    LINEA="$(df_de "$CRUDO/df.txt" "/")"
fi

if [ -n "$LINEA" ]; then
    set -- $LINEA
    set_dato "disco.punto"    "$PUNTO"
    set_dato "disco.total_gb" "$(gb_de_kb "$1")"
    set_dato "disco.usado_gb" "$(gb_de_kb "$2")"
    set_dato "disco.libre_gb" "$(gb_de_kb "$3")"
    set_dato "disco.ocupado_pct" "$4"
else
    no_pude "La ocupacion del disco" "df no ha dado una linea que se pueda leer para $PUNTO"
fi

SMART="$(campo_sp "$CRUDO/diskutil_disk0.txt" "SMART Status")"
set_dato "disco.smart" "$SMART"

N_SNAP=$(grep -c 'com.apple.TimeMachine' "$CRUDO/snapshots.txt" 2>/dev/null || true)
es_numero "$N_SNAP" || N_SNAP=0
set_dato "disco.instantaneas" "$N_SNAP"

# ---------------------------------------------------------------------------
# La bateria
#
# Va arriba del todo en el informe de un portatil, y es lo que PCDIAG no tiene
# porque a un PC de plato enchufado a la pared no le hace falta. En el Mac de
# alguien, "tu bateria tiene 1.100 ciclos y esta marcada como Service
# Recommended" es la frase mas util que puede decir la aplicacion entera.
#
# Un Mac de sobremesa NO tiene bateria, y eso no es un fallo ni algo que no se
# haya podido comprobar: es que no la hay. Decirlo mal seria un aviso falso en
# todos los iMac y los Mac mini.
# ---------------------------------------------------------------------------
Paso "La bateria"

capturar "bateria_pmset" 20 pmset -g batt
capturar "bateria_sp"    60 system_profiler SPPowerDataType
capturar "bateria_ioreg" 30 ioreg -r -c AppleSmartBattery

HAY_BATERIA="no"
if grep -qi 'InternalBattery' "$CRUDO/bateria_pmset.txt" 2>/dev/null; then HAY_BATERIA="si"; fi
if grep -qi '"BatteryInstalled" = Yes' "$CRUDO/bateria_ioreg.txt" 2>/dev/null; then HAY_BATERIA="si"; fi
set_dato "bateria.hay" "$HAY_BATERIA"

if [ "$HAY_BATERIA" = "si" ]; then
    CICLOS="$(campo_sp "$CRUDO/bateria_sp.txt" "Cycle Count")"
    [ -n "$CICLOS" ] || CICLOS="$(campo_ioreg "$CRUDO/bateria_ioreg.txt" "CycleCount")"
    set_dato "bateria.ciclos" "$CICLOS"

    ESTADO_BAT="$(campo_sp "$CRUDO/bateria_sp.txt" "Condition")"
    set_dato "bateria.estado" "$ESTADO_BAT"

    SALUD="$(campo_sp "$CRUDO/bateria_sp.txt" "Maximum Capacity")"
    if [ -z "$SALUD" ]; then
        # Los macOS de antes no dan el porcentaje hecho: se saca de ioreg.
        MAXC="$(campo_ioreg "$CRUDO/bateria_ioreg.txt" "AppleRawMaxCapacity")"
        [ -n "$MAXC" ] || MAXC="$(campo_ioreg "$CRUDO/bateria_ioreg.txt" "MaxCapacity")"
        DISC="$(campo_ioreg "$CRUDO/bateria_ioreg.txt" "DesignCapacity")"
        if es_numero "$MAXC" && es_numero "$DISC" && [ "$DISC" -gt 0 ]; then
            SALUD="$(awk -v a="$MAXC" -v b="$DISC" 'BEGIN { printf "%d%%", (a*100)/b }')"
        fi
    fi
    set_dato "bateria.salud" "$SALUD"

    # La linea de pmset es:  " -InternalBattery-0 (id=123)\t87%; discharging; ..."
    # El porcentaje es lo que va detras del tabulador y antes del punto y coma.
    set_dato "bateria.carga" "$(awk -F';' '
        /InternalBattery/ {
            n = split($1, trozos, "\t")
            s = trozos[n]
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            print s
            exit
        }' "$CRUDO/bateria_pmset.txt" 2>/dev/null)"

    if [ -z "$CICLOS" ] && [ -z "$ESTADO_BAT" ]; then
        no_pude "El estado de la bateria" "ni system_profiler ni ioreg han dado los ciclos ni la condicion"
    fi
fi

# ---------------------------------------------------------------------------
# Memoria y temperatura
#
# "memory_pressure" NO se usa: sin argumentos informa, pero con otros PROVOCA
# presion de memoria a proposito, y no es un mando con el que jugar dentro de
# una herramienta de diagnostico. vm_stat y la del swap dicen lo mismo sin
# tocar nada.
#
# Y es "pmset -g therm", no "thermlog": el segundo se queda escuchando y no
# termina nunca.
# ---------------------------------------------------------------------------
Paso "Memoria"

capturar "vm_stat"  20 vm_stat
capturar "swap"     10 sysctl -n vm.swapusage
capturar "memtotal" 10 sysctl -n hw.memsize
capturar "termico"  20 pmset -g therm

set_dato "mem.swap" "$(head -1 "$CRUDO/swap.txt" 2>/dev/null)"

# ---------------------------------------------------------------------------
# Seguridad
# ---------------------------------------------------------------------------
Paso "Seguridad"

capturar "sip"       15 csrutil status
capturar "filevault" 20 fdesetup status
capturar "gatekeeper" 15 spctl --status

SIP="$(head -1 "$CRUDO/sip.txt" 2>/dev/null)"
set_dato "seg.sip" "$SIP"
set_dato "seg.filevault" "$(head -1 "$CRUDO/filevault.txt" 2>/dev/null)"
set_dato "seg.gatekeeper" "$(head -1 "$CRUDO/gatekeeper.txt" 2>/dev/null)"

# ---------------------------------------------------------------------------
# Cierres inesperados y panicos del sistema
#
# ESTO ES LO QUE MAS PROBABLE ES QUE NO SE PUEDA LEER, y es de lo mas valioso
# que hay. La carpeta del sistema necesita "Acceso total al disco" para la
# Terminal. Sin ese permiso NO da un error visible: da una carpeta que parece
# vacia.
#
# Por eso aqui se distingue con cuidado entre "no hay panicos" y "no he podido
# mirar". Confundirlos seria decirle a alguien que su Mac esta bien cuando lo
# que pasa es que no se ha mirado.
# ---------------------------------------------------------------------------
Paso "Cierres inesperados"

DIR_SIS="/Library/Logs/DiagnosticReports"
DIR_USU="$HOME/Library/Logs/DiagnosticReports"

capturar "fallos_sistema_ls"   20 ls -1 "$DIR_SIS"
capturar "fallos_sistema_30d"  30 find "$DIR_SIS" -maxdepth 1 -type f -mtime -30
capturar "fallos_usuario_ls"   20 ls -1 "$DIR_USU"
capturar "fallos_usuario_30d"  30 find "$DIR_USU" -maxdepth 1 -type f -mtime -30

PUEDO_LEER_FALLOS="si"
if grep -qiE 'Operation not permitted|Permission denied' "$CRUDO/fallos_sistema_ls.txt" "$CRUDO/fallos_sistema_30d.txt" 2>/dev/null; then
    PUEDO_LEER_FALLOS="no"
    no_pude "Los panicos y cierres inesperados del sistema" \
        "la carpeta $DIR_SIS necesita Acceso total al disco para la Terminal. Sin ese permiso parece vacia, asi que aqui no se dice que no haya: se dice que no se ha mirado."
fi
set_dato "fallos.puedo_leer" "$PUEDO_LEER_FALLOS"

if [ "$PUEDO_LEER_FALLOS" = "si" ]; then
    # -E y no la alternancia "\|", que es de grep de GNU: el de macOS viene de
    # BSD y ahi no esta garantizada.
    N_PANIC=$(grep -cE '\.panic$' "$CRUDO/fallos_sistema_30d.txt" 2>/dev/null || true)
    N_IPS=$(grep -cE '\.(ips|crash)$' "$CRUDO/fallos_sistema_30d.txt" 2>/dev/null || true)
    es_numero "$N_PANIC" || N_PANIC=0
    es_numero "$N_IPS" || N_IPS=0
    set_dato "fallos.panics_30d" "$N_PANIC"
    set_dato "fallos.informes_30d" "$N_IPS"
fi

N_IPS_USU=$(grep -cE '\.(ips|crash)$' "$CRUDO/fallos_usuario_30d.txt" 2>/dev/null || true)
es_numero "$N_IPS_USU" || N_IPS_USU=0
set_dato "fallos.usuario_30d" "$N_IPS_USU"

# ---------------------------------------------------------------------------
# Que se abre solo al arrancar
# ---------------------------------------------------------------------------
Paso "Lo que se abre solo"

capturar "launchctl"       30 launchctl list
capturar "agentes_sistema" 15 ls -1 /Library/LaunchAgents
capturar "demonios"        15 ls -1 /Library/LaunchDaemons
capturar "agentes_usuario" 15 ls -1 "$HOME/Library/LaunchAgents"
capturar "extensiones"     30 systemextensionsctl list

for par in "agentes_sistema:arranque.agentes_sistema" "demonios:arranque.demonios" "agentes_usuario:arranque.agentes_usuario"; do
    clave="${par%%:*}"; destino="${par##*:}"
    if salio_bien "$clave"; then
        n=$(grep -c '\.plist$' "$CRUDO/$clave.txt" 2>/dev/null || true)
        es_numero "$n" || n=0
        set_dato "$destino" "$n"
    fi
done

# ---------------------------------------------------------------------------
# Copias de seguridad
# ---------------------------------------------------------------------------
Paso "Copias de seguridad"

capturar "tm_destino" 30 tmutil destinationinfo
capturar "tm_ultima"  40 tmutil latestbackup

if salio_bien "tm_destino"; then
    set_dato "tm.destino" "$(campo_sp "$CRUDO/tm_destino.txt" "Name")"
fi
if salio_bien "tm_ultima"; then
    set_dato "tm.ultima" "$(head -1 "$CRUDO/tm_ultima.txt" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# Actualizaciones
#
# Depende de la red y puede tardar. Va con limite generoso y avisando, porque
# un minuto de silencio parece que se ha colgado.
# ---------------------------------------------------------------------------
Paso "Actualizaciones"
DiFlojo "esto consulta a Apple y puede tardar un minuto"

capturar "actualizaciones" 120 softwareupdate -l

if salio_bien "actualizaciones"; then
    if grep -qi 'No new software available' "$CRUDO/actualizaciones.txt" 2>/dev/null; then
        set_dato "act.pendientes" "0"
    else
        n=$(grep -c '^\* *Label:' "$CRUDO/actualizaciones.txt" 2>/dev/null || true)
        es_numero "$n" || n=0
        set_dato "act.pendientes" "$n"
    fi
elif [ "$(codigo_de actualizaciones)" = "124" ]; then
    no_pude "Las actualizaciones pendientes" "softwareupdate ha tardado mas de dos minutos. Suele ser la red."
else
    no_pude "Las actualizaciones pendientes" "softwareupdate ha terminado con codigo $(codigo_de actualizaciones)"
fi

# ---------------------------------------------------------------------------
# Que se podria liberar
#
# SOLO MIDE. No borra nada, y en esta version ni siquiera se ofrece a hacerlo:
# escribir codigo que borra sin poder ejecutarlo ni una vez es justo donde no
# hay que estar. Cuando haya un Mac donde probarlo, esto ya deja hecha la mitad
# del trabajo, que es saber cuanto hay y donde.
#
# "du" puede tardar mucho en carpetas grandes, asi que cada una lleva su limite
# y la que no de tiempo se dice.
# ---------------------------------------------------------------------------
Paso "Que se podria liberar"

medir_carpeta() {
    local clave="$1"; local ruta="$2"; local etiqueta="$3"
    if [ ! -d "$ruta" ]; then
        set_dato "libera.$clave.gb" "0"
        set_dato "libera.$clave.estado" "no existe"
        return
    fi
    capturar "du_$clave" 90 du -sk "$ruta"
    local kb
    kb=$(grep -E '^[0-9]+' "$CRUDO/du_$clave.txt" 2>/dev/null | tail -1 | awk '{ print $1 }')
    if es_numero "$kb"; then
        set_dato "libera.$clave.gb" "$(gb_de_kb "$kb")"
        set_dato "libera.$clave.estado" "medido"
    else
        set_dato "libera.$clave.estado" "no se ha podido medir"
        no_pude "El tamaño de $etiqueta" "du no ha dado un numero (codigo $(codigo_de "du_$clave")). En Descargas suele ser el permiso de privacidad de la Terminal."
    fi
    set_dato "libera.$clave.ruta" "$ruta"
    set_dato "libera.$clave.etiqueta" "$etiqueta"
}

medir_carpeta "papelera"   "$HOME/.Trash"                                            "la Papelera"
medir_carpeta "caches"     "$HOME/Library/Caches"                                    "las caches del usuario"
medir_carpeta "logs"       "$HOME/Library/Logs"                                      "los registros del usuario"
medir_carpeta "ios"        "$HOME/Library/Application Support/MobileSync/Backup"     "las copias de iPhone y iPad"
medir_carpeta "xcode"      "$HOME/Library/Developer/Xcode/DerivedData"               "los restos de compilacion de Xcode"
medir_carpeta "simulador"  "$HOME/Library/Developer/CoreSimulator/Devices"           "los simuladores de Xcode"
medir_carpeta "descargas"  "$HOME/Downloads"                                         "la carpeta de Descargas"

TOTAL_LIBERABLE=$(awk -F'\t' '
    $1 ~ /^libera\..*\.gb$/ { s += $2 }
    END { printf "%.1f", s+0 }
' "$DATOS" 2>/dev/null)
set_dato "libera.total_gb" "$TOTAL_LIBERABLE"

# ---------------------------------------------------------------------------
# Las reglas: que de todo esto merece que alguien lo mire
#
# Pocas y seguras. Un aviso que salta sin motivo se aprende a ignorar, y
# entonces el que importa tambien se ignora.
#
# Y ninguna regla dispara por un dato que falta: si no se ha podido mirar, va a
# la lista de "no he podido", no a la de hallazgos.
# ---------------------------------------------------------------------------
Paso "Juntandolo todo"

PCT="$(dato disco.ocupado_pct)"
if es_numero "$PCT"; then
    if [ "$PCT" -ge 90 ]; then
        hallazgo "CRITICO" "DISCO" "El disco esta al $PCT %" \
            "Por debajo del 10 % libre macOS empieza a ir peor y algunas cosas dejan de poder guardarse. Mas abajo esta lo que se podria liberar sin tocar nada tuyo."
    elif [ "$PCT" -ge 75 ]; then
        hallazgo "AVISO" "DISCO" "El disco esta al $PCT %" \
            "Todavia no molesta, pero conviene mirar lo que se podria liberar antes de que llegue al 90 %."
    fi
fi

if [ -n "$SMART" ] && [ "$SMART" != "Verified" ] && [ "$SMART" != "Not Supported" ]; then
    hallazgo "CRITICO" "DISCO" "El disco dice que su estado SMART es \"$SMART\"" \
        "SMART es el autodiagnostico del propio disco. Cualquier cosa que no sea Verified merece una copia de seguridad HOY y una revision."
fi

if [ "$(dato bateria.hay)" = "si" ]; then
    EST="$(dato bateria.estado)"
    CIC="$(dato bateria.ciclos)"
    case "$EST" in
        ""|"Normal") : ;;
        *) hallazgo "AVISO" "BATERIA" "La bateria esta marcada como \"$EST\"" \
               "Lo dice el propio sistema, no MacDiag. Con \"Service Recommended\" o \"Replace Soon\" el equipo puede apagarse antes de tiempo o bajar de velocidad al no estar enchufado." ;;
    esac
    if es_numero "$CIC" && [ "$CIC" -ge 1000 ]; then
        hallazgo "AVISO" "BATERIA" "La bateria lleva $CIC ciclos" \
            "La mayoria de los Mac estan pensados para unos 1.000 ciclos manteniendo el 80 % de su capacidad. Pasados, dura cada vez menos, y eso es normal, no una averia."
    fi
fi

case "$(dato seg.filevault)" in
    *"is Off"*) hallazgo "AVISO" "SEGURIDAD" "FileVault esta apagado" \
        "El disco no esta cifrado: quien se lleve el equipo, o el disco, puede leerlo todo sin saber tu contraseña. En un portatil es lo primero que hay que encender." ;;
esac

case "$SIP" in
    *disabled*) hallazgo "AVISO" "SEGURIDAD" "La proteccion de integridad del sistema (SIP) esta desactivada" \
        "Alguien la apago a proposito en algun momento, porque no se apaga sola. Si ya no hace falta lo que fuera, conviene volver a encenderla." ;;
esac

case "$(dato seg.gatekeeper)" in
    *disabled*) hallazgo "AVISO" "SEGURIDAD" "Gatekeeper esta desactivado" \
        "El Mac deja de comprobar de donde vienen los programas antes de abrirlos." ;;
esac

if [ "$(dato fallos.puedo_leer)" = "si" ]; then
    NP="$(dato fallos.panics_30d)"
    if es_numero "$NP" && [ "$NP" -gt 0 ]; then
        hallazgo "CRITICO" "FALLOS" "$NP reinicio(s) por fallo del sistema en los ultimos 30 dias" \
            "Un kernel panic es el equivalente del pantallazo azul: el sistema se para y reinicia solo. Los partes estan en $DIR_SIS. Si se repiten, casi nunca es una aplicacion: suele ser memoria, disco o algo conectado."
    fi
fi

AP="$(dato act.pendientes)"
if es_numero "$AP" && [ "$AP" -gt 0 ]; then
    hallazgo "AVISO" "SISTEMA" "Hay $AP actualizacion(es) de Apple sin instalar" \
        "Las de seguridad de macOS no son opcionales en la practica. Se instalan desde Ajustes del Sistema, en Actualizacion de software."
fi

# "tmutil destinationinfo" tambien termina con error cuando NO hay destino, asi
# que el codigo de salida no distingue "no hay copia" de "el mando ha fallado".
# Y son dos cosas muy distintas: la primera es un aviso para el usuario y la
# segunda es una comprobacion que no se ha hecho. Se mira el texto.
if ! salio_bien "tm_destino"; then
    if grep -qiE 'No destinations configured' "$CRUDO/tm_destino.txt" 2>/dev/null; then
        hallazgo "AVISO" "COPIAS" "Este Mac no tiene ningun destino de Time Machine" \
            "No hay copia de seguridad automatica. Un disco externo de los baratos y encenderlo es todo lo que hace falta; sin eso, un disco roto se lo lleva todo."
    else
        no_pude "Si hay copias de seguridad configuradas" \
            "tmutil destinationinfo termino con codigo $(codigo_de tm_destino) y sin decir que no haya destinos. No se sabe si hay copia o no."
    fi
fi

NS="$(dato disco.instantaneas)"
if es_numero "$NS" && [ "$NS" -gt 0 ]; then
    hallazgo "INFO" "DISCO" "Hay $NS instantanea(s) local(es) de Time Machine" \
        "Son copias que Time Machine guarda en el propio disco cuando no alcanza el externo. Ocupan sitio y el sistema las borra solo cuando le hace falta: por eso el Finder puede decir que hay menos espacio libre del que dice este informe."
fi

if [ -n "$TOTAL_LIBERABLE" ] && [ "$(awk -v t="$TOTAL_LIBERABLE" 'BEGIN { print (t>=5)?1:0 }')" = "1" ]; then
    hallazgo "INFO" "ESPACIO" "Se podrian liberar unos $TOTAL_LIBERABLE GB" \
        "Es la suma de papelera, caches, copias viejas de iPhone y restos de Xcode. MacDiag todavia NO borra nada: de momento solo te dice donde esta."
fi

# ---------------------------------------------------------------------------
# El informe
# ---------------------------------------------------------------------------
TARDO=$(( $(date +%s) - EMPEZO ))
set_dato "meta.version"  "$VERSION_MACDIAG"
set_dato "meta.fecha"    "$(date '+%Y-%m-%dT%H:%M:%S')"
set_dato "meta.tardo_s"  "$TARDO"
set_dato "meta.equipo"   "$(scutil --get ComputerName 2>/dev/null || hostname 2>/dev/null)"
set_dato "meta.carpeta"  "$TRABAJO"

escribir_html "$TRABAJO/informe.html"
escribir_json "$TRABAJO/informe.json"
anotar_historial "$HISTORIAL"

Paso "Listo"
Di "Informe:  $TRABAJO/informe.html"
DiFlojo "Capturas: $CRUDO"

C=$(cuantos_hallazgos CRITICO); A=$(cuantos_hallazgos AVISO)
NOPUDE_N=$(wc -l < "$NOPUDE" 2>/dev/null | tr -d ' ')
es_numero "$NOPUDE_N" || NOPUDE_N=0

if [ "$C" -gt 0 ]; then DiMal "$C cosa(s) para mirar ya, y $A aviso(s)."
elif [ "$A" -gt 0 ]; then DiOjo "Nada grave. $A aviso(s)."
else DiOk "Nada grave y ningun aviso."; fi
[ "$NOPUDE_N" -gt 0 ] && DiOjo "$NOPUDE_N cosa(s) NO se han podido comprobar. Estan al final del informe."

open "$TRABAJO/informe.html" 2>/dev/null || Di "Abre a mano: $TRABAJO/informe.html"
exit 0
