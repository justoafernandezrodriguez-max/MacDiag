#!/bin/bash
# ---------------------------------------------------------------------------
#  MacDiag - motor de estado
#
#  Mira como esta este Mac y deja un informe. NO TOCA NADA: solo lee.
#
#  PROBADO en un iMac18,3 con macOS 13.7.8 (Intel) el 26-ago-2026. Sin probar
#  todavia en Apple Silicon ni en un portatil con bateria. Ver LEEME.txt.
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
. "$AQUI/lib-vigilancia.sh"
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
# QUIEN es cada cosa que arranca sola
#
# Antes esto se limitaba a CONTAR: "agentes 9, demonios 4". Un numero sin
# nombres no dice nada, y en el Mac donde se escribio MacDiag daba ademas una
# confianza que no tocaba: de esos demonios, cinco eran un minero de
# criptomonedas, su reinstalador camuflado de Apple, y restos de otro camuflado
# de Google. Llevaba seis dias corriendo y el informe decia "4".
#
# Contar no es mirar.
# ---------------------------------------------------------------------------
Paso "Quien arranca solo con el equipo"

N_SOSPECHOSOS=0
: > "$CRUDO/_ARRANQUE.tsv"
for carpeta in /Library/LaunchDaemons /Library/LaunchAgents "$HOME/Library/LaunchAgents"; do
    [ -d "$carpeta" ] || continue
    for plist in "$carpeta"/*.plist; do
        [ -e "$plist" ] || continue
        prog="$(programa_de_plist "$plist")"
        motivos="$(motivos_sospecha "$plist")"
        printf '%s\t%s\t%s\n' "$(basename "$plist")" "${prog:-?}" "$motivos" >> "$CRUDO/_ARRANQUE.tsv"
        if [ -n "$motivos" ]; then
            N_SOSPECHOSOS=$(( N_SOSPECHOSOS + 1 ))
            DiMal "$(basename "$plist"): $motivos"
            hallazgo "CRITICO" "ARRANQUE" "Arranca solo y no deberia: $(basename "$plist")" \
                "$motivos. Esta en $carpeta y lanza \"${prog:-?}\". MacDiag no lo quita solo: un elemento de arranque puede ser de algo que si usas, y quitarlo a ciegas rompe programas. Miralo, y si no es tuyo, se quita descargandolo con launchctl y borrando el fichero." \
                "abrir:arranque"
        fi
    done
done
set_dato "arranque.sospechosos" "$N_SOSPECHOSOS"
[ "$N_SOSPECHOSOS" -eq 0 ] && DiOk "nada raro en lo que arranca solo"

# ---------------------------------------------------------------------------
# Que se esta comiendo el equipo ahora mismo
# ---------------------------------------------------------------------------
Paso "Lo que mas consume"

capturar "procesos" 20 ps -Aceo pid,pcpu,pmem,comm -r
PESADOS=0
while IFS=$'\t' read -r pid pcpu pmem cmd; do
    [ -n "$pid" ] || continue
    PESADOS=$(( PESADOS + 1 ))
    ruta="$(ruta_de_proceso "$pid")"
    DiOjo "$cmd: $pcpu % de CPU"
    # Un proceso que se come el equipo Y ademas vive donde no debe no es un
    # programa pesado: es otra cosa. Los dos casos se dicen distinto.
    case "$ruta" in
        /opt/*|/tmp/*|/var/tmp/*|/private/tmp/*|/private/var/tmp/*)
            hallazgo "CRITICO" "PROCESOS" "\"$cmd\" se come el $pcpu % de la CPU y arranca desde $ruta" \
                "Ese sitio no es donde macOS guarda los programas. Un programa que consume asi y ademas vive en una carpeta de paso o en /opt es, casi siempre, algo que no has puesto tu: mineros de criptomonedas y similares. Miralo antes de nada." \
                "" ;;
        *)
            hallazgo "AVISO" "PROCESOS" "\"$cmd\" se esta llevando el $pcpu % de la CPU" \
                "Lleva la CPU muy cargada. Si es algo que has abierto tu -renderizar, comprimir, compilar- es normal y se pasa al terminar. Si no sabes que es, merece una mirada." \
                "" ;;
    esac
done < <(procesos_pesados 70)
set_dato "procesos.pesados" "$PESADOS"
[ "$PESADOS" -eq 0 ] && DiOk "nada se esta comiendo la CPU"

# ---------------------------------------------------------------------------
# Memoria de verdad: no cuanta hay, sino si falta
#
# El dato ya se capturaba desde la 0.1.0 y no lo miraba nadie. En este mismo
# Mac llego a haber 31,9 GB de intercambio usados de 33, con 16 GB de RAM: la
# explicacion exacta de "va lento" que un usuario no sabe mirar.
# ---------------------------------------------------------------------------
Paso "Memoria"

SWAP_USADO_MB="$(sed -E 's/.*used = ([0-9.]+)M.*/\1/' "$CRUDO/swap.txt" 2>/dev/null | cut -d. -f1)"
es_numero "$SWAP_USADO_MB" || SWAP_USADO_MB=""
set_dato "mem.swap_usado_mb" "${SWAP_USADO_MB:-}"
if es_numero "$SWAP_USADO_MB"; then
    if [ "$SWAP_USADO_MB" -ge 8192 ]; then
        hallazgo "AVISO" "MEMORIA" "El equipo esta usando $(( SWAP_USADO_MB / 1024 )) GB de disco como si fuera memoria" \
            "Cuando se acaba la memoria, macOS tira del disco, que es mucho mas lento. Es la explicacion mas comun de que un Mac vaya a tirones sin motivo aparente. Cerrar lo que no se este usando lo baja; si pasa siempre, es que a este equipo le falta memoria para lo que se le pide." \
            ""
    fi
fi

# El estrangulamiento: la CPU bajando de velocidad a proposito. Otro dato que
# se capturaba y no se leia.
LIMITE_CPU="$(awk -F'= *' '/CPU_Speed_Limit/ { gsub(/[^0-9]/,"",$2); print $2; exit }' "$CRUDO/termico.txt" 2>/dev/null)"
set_dato "cpu.limite" "${LIMITE_CPU:-}"
if es_numero "$LIMITE_CPU" && [ "$LIMITE_CPU" -lt 100 ]; then
    hallazgo "AVISO" "TEMPERATURA" "La CPU esta funcionando al $LIMITE_CPU % de su velocidad" \
        "El sistema la esta frenando a proposito, y eso pasa por calor o porque algo la tiene al maximo mucho rato. Si el equipo tiene polvo dentro o los ventiladores no van, se queda asi. Mira tambien lo que mas consume, mas arriba." \
        ""
fi

# ---------------------------------------------------------------------------
# Las puertas abiertas
# ---------------------------------------------------------------------------
Paso "Puertas abiertas"

capturar "cortafuegos" 15 /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
capturar "escuchando"  25 lsof -nP -iTCP -sTCP:LISTEN

if grep -qi 'disabled' "$CRUDO/cortafuegos.txt" 2>/dev/null; then
    set_dato "seg.cortafuegos" "apagado"
    hallazgo "AVISO" "SEGURIDAD" "El cortafuegos esta apagado" \
        "Sin el, cualquier programa de este Mac puede quedarse escuchando conexiones de fuera sin pedirte permiso. En un equipo que se conecta a redes que no son la de casa, conviene encenderlo." \
        "abrir:cortafuegos"
elif grep -qi 'enabled' "$CRUDO/cortafuegos.txt" 2>/dev/null; then
    set_dato "seg.cortafuegos" "encendido"
else
    no_pude "Si el cortafuegos esta encendido" "socketfilterfw no ha contestado nada que se pueda leer"
fi

# Compartir pantalla encendido es una puerta de entrada al equipo entero, y casi
# nadie recuerda haberlo dejado puesto.
if launchctl print system/com.apple.screensharing >/dev/null 2>&1; then
    set_dato "seg.pantalla_compartida" "si"
    hallazgo "AVISO" "SEGURIDAD" "Compartir pantalla esta encendido" \
        "Alguien con usuario y contrasena de este Mac puede verlo y manejarlo por la red. Si no lo usas, se apaga en Ajustes del Sistema, en General > Compartir." \
        "abrir:compartir"
else
    set_dato "seg.pantalla_compartida" "no"
fi

# Puertos escuchando en TODAS las interfaces -no solo en el propio equipo-, que
# es la diferencia entre "esto lo usa un programa mio" y "esto lo puede alcanzar
# cualquiera de la red".
N_ABIERTOS=$(awk 'NR>1 && $9 !~ /^(127\.0\.0\.1|\[::1\])/ { n++ } END { print n+0 }' "$CRUDO/escuchando.txt" 2>/dev/null)
es_numero "$N_ABIERTOS" || N_ABIERTOS=0
set_dato "seg.puertos_abiertos" "$N_ABIERTOS"
if [ "$N_ABIERTOS" -gt 0 ]; then
    hallazgo "INFO" "SEGURIDAD" "Hay $N_ABIERTOS puerto(s) abiertos a toda la red" \
        "Son programas de este Mac esperando conexiones de fuera, no solo de si mismo. Puede estar perfectamente bien -un servidor que tu has puesto- pero conviene saber cuales son. La lista entera esta en la carpeta crudo, en escuchando.txt." \
        ""
fi

# ---------------------------------------------------------------------------
# Copias de seguridad
# ---------------------------------------------------------------------------
Paso "Copias de seguridad"

capturar "tm_destino" 30 tmutil destinationinfo
capturar "tm_ultima"  40 tmutil latestbackup

# El codigo de salida de tmutil no distingue NADA, y lo que se vio al ejecutarlo
# por fin en un Mac de verdad es lo CONTRARIO de lo que se supuso al escribirlo
# a ciegas: "tmutil destinationinfo" termina con codigo 0 aunque no haya ningun
# destino configurado, y lo unico que lo dice es el texto.
#
# Eso hacia que el aviso "este Mac no tiene copia de seguridad" -que es de los
# mas utiles que da MacDiag- NO llegara a saltar nunca, porque colgaba de un
# "si el mando ha fallado". El informe se limitaba a poner "no se ha podido
# saber" en el destino. Justo el fallo que este proyecto no se permite: no se
# sabia, y si se sabia.
#
# Se mira el TEXTO, siempre, y el codigo de salida no se usa para esto.
TM_ESTADO="$(tm_estado_de "$CRUDO/tm_destino.txt")"
TM_NOMBRE="$(campo_sp "$CRUDO/tm_destino.txt" "Name")"
[ "$TM_ESTADO" = "con destino" ] && set_dato "tm.destino" "$TM_NOMBRE"
set_dato "tm.estado" "$TM_ESTADO"

# "tmutil latestbackup" tambien termina con codigo 0 escribiendo un mensaje de
# error dentro ("Failed to mount backup destination, error: Error Domain=..."),
# y ese churro se estaba guardando como si fuera la fecha de la ultima copia.
# Una copia de verdad es una RUTA: si no empieza por barra, no es una copia.
TM_ULTIMA="$(tm_ultima_de "$CRUDO/tm_ultima.txt")"
[ -n "$TM_ULTIMA" ] && set_dato "tm.ultima" "$TM_ULTIMA"

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
    local kb vetadas
    kb=$(du_kb_de "$CRUDO/du_$clave.txt")

    # Cuantas carpetas de dentro no ha dejado leer macOS. Esto se vio en la
    # primera ejecucion real: "du" sobre ~/Library/Caches termina con codigo 1
    # porque cuatro subcarpetas son de privacidad (HomeKit, CloudKit...), pero
    # IMPRIME el total igualmente. MacDiag lo daba por "medido" y enseñaba una
    # cifra corta como si fuera la buena. Un numero incompleto presentado como
    # completo es exactamente lo que este proyecto no hace.
    vetadas=$(du_vetadas_de "$CRUDO/du_$clave.txt")

    if es_numero "$kb"; then
        set_dato "libera.$clave.gb" "$(gb_de_kb "$kb")"
        if [ "$vetadas" -gt 0 ]; then
            set_dato "libera.$clave.estado" "medido en parte"
            set_dato "libera.$clave.vetadas" "$vetadas"
            no_pude "El tamaño completo de $etiqueta" \
                "se han medido $(gb_de_kb "$kb") GB, pero macOS no ha dejado entrar en $vetadas carpeta(s) de dentro por privacidad, asi que ahi puede haber mas. La cifra del informe es un minimo, no el total." \
                "mantenimiento"
        else
            set_dato "libera.$clave.estado" "medido"
        fi
    else
        set_dato "libera.$clave.estado" "no se ha podido medir"
        if [ "$vetadas" -gt 0 ]; then
            no_pude "El tamaño de $etiqueta" \
                "macOS no deja a MacDiag entrar en $ruta (permiso de privacidad). No es que este vacia: es que no se ha podido mirar. Se arregla dando Acceso total al disco a MacDiag." \
                "mantenimiento"
        else
            no_pude "El tamaño de $etiqueta" \
                "du no ha dado un numero para $ruta (termino con codigo $(codigo_de "du_$clave"))." \
                "mantenimiento"
        fi
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

# La suma se parte en dos A PROPOSITO, y el motivo salio de la primera ejecucion
# en un Mac de verdad: de los 24,7 GB que MacDiag ofrecia como "liberables",
# 23,1 eran la carpeta de Descargas. Descargas NO es basura -son ficheros del
# usuario, y ahi dentro puede estar cualquier cosa- pero se sumaba con la
# papelera y las caches bajo el titulo "que se podria liberar", y el detalle del
# hallazgo ni siquiera la mencionaba: hablaba de papelera, caches, iPhone y
# Xcode, que juntos eran el 6 % de la cifra.
#
# Un numero grande que invita a borrar lo que no habia que borrar es justo lo
# contrario de lo que hace esta aplicacion. Van separados.
TOTAL_BASURA=$(awk -F'\t' '
    $1 ~ /^libera\..*\.gb$/ && $1 != "libera.descargas.gb" { s += $2 }
    END { printf "%.1f", s+0 }
' "$DATOS" 2>/dev/null)
DESCARGAS_GB="$(dato libera.descargas.gb)"
es_numero "$(printf '%s' "${DESCARGAS_GB:-0}" | cut -d. -f1)" || DESCARGAS_GB="0"
TOTAL_LIBERABLE=$(awk -v a="$TOTAL_BASURA" -v b="${DESCARGAS_GB:-0}" 'BEGIN { printf "%.1f", a+b }')

# Si alguna carpeta no se ha podido medir entera, la suma es un minimo y hay que
# decirlo: una cifra redonda que se presenta como el total, cuando le falta un
# trozo, vuelve a ser decir que se sabe algo que no se sabe.
MEDIDA_COJA="no"
if grep -qE '^libera\..*\.estado\t(no se ha podido medir|medido en parte)$' "$DATOS" 2>/dev/null; then
    MEDIDA_COJA="si"
fi
set_dato "libera.basura_gb"  "$TOTAL_BASURA"
set_dato "libera.total_gb"   "$TOTAL_LIBERABLE"
set_dato "libera.incompleta" "$MEDIDA_COJA"

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
            "Por debajo del 10 % libre macOS empieza a ir peor y algunas cosas dejan de poder guardarse. La pestana de Mantenimiento dice cuanto se puede liberar sin tocar nada tuyo." \
            "abrir:almacenamiento"
    elif [ "$PCT" -ge 75 ]; then
        hallazgo "AVISO" "DISCO" "El disco esta al $PCT %" \
            "Todavia no molesta, pero conviene mirar lo que se podria liberar antes de que llegue al 90 %." \
            "abrir:almacenamiento"
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
        "El disco no esta cifrado: quien se lleve el equipo, o el disco, puede leerlo todo sin saber tu contraseña. En un portatil es lo primero que hay que encender." \
        "abrir:filevault" ;;
esac

case "$SIP" in
    *disabled*) hallazgo "AVISO" "SEGURIDAD" "La proteccion de integridad del sistema (SIP) esta desactivada" \
        "Alguien la apago a proposito en algun momento, porque no se apaga sola. Si ya no hace falta lo que fuera, conviene volver a encenderla." ;;
esac

case "$(dato seg.gatekeeper)" in
    *disabled*) hallazgo "AVISO" "SEGURIDAD" "Gatekeeper esta desactivado" \
        "El Mac deja de comprobar de donde vienen los programas antes de abrirlos." \
        "gatekeeper" ;;
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
        "Las de seguridad de macOS no son opcionales en la practica. MacDiag no las instala solo: eso lo tiene que hacer una persona, porque a veces piden reiniciar." \
        "abrir:actualizaciones"
fi

# Las copias de seguridad, sobre el texto y no sobre el codigo de salida (ver
# arriba). Los tres estados son distintos y ninguno se puede confundir con otro:
# no hay destino es un AVISO para el usuario, no saberlo es una comprobacion que
# no se ha hecho, y tener destino pero sin copia legible tambien.
case "$TM_ESTADO" in
    "sin destino")
        hallazgo "AVISO" "COPIAS" "Este Mac no tiene ningun destino de Time Machine" \
            "No hay copia de seguridad automatica. Un disco externo de los baratos y encenderlo es todo lo que hace falta; sin eso, un disco roto se lo lleva todo." \
            "abrir:timemachine" ;;
    "con destino")
        if [ -z "$TM_ULTIMA" ]; then
            no_pude "Cuando fue la ultima copia de Time Machine" \
                "hay un destino configurado ($TM_NOMBRE), pero tmutil no ha dado una ruta de copia: normalmente es que el disco de las copias no esta conectado. Que haya destino no quiere decir que la copia este hecha."
        fi ;;
    *)
        no_pude "Si hay copias de seguridad configuradas" \
            "tmutil destinationinfo no ha dicho ni que haya destino ni que no lo haya (termino con codigo $(codigo_de tm_destino)). No se sabe si hay copia o no." ;;
esac

NS="$(dato disco.instantaneas)"
if es_numero "$NS" && [ "$NS" -gt 0 ]; then
    hallazgo "INFO" "DISCO" "Hay $NS instantanea(s) local(es) de Time Machine" \
        "Son copias que Time Machine guarda en el propio disco cuando no alcanza el externo. Ocupan sitio y el sistema las borra solo cuando le hace falta: por eso el Finder puede decir que hay menos espacio libre del que dice este informe."
fi

# Dos hallazgos distintos, porque son dos cosas distintas: lo que sobra y lo que
# el usuario tiene guardado. Nunca se suman en la misma frase.
COLETILLA=""
[ "$MEDIDA_COJA" = "si" ] && COLETILLA=" Y es un minimo: hay carpetas que macOS no ha dejado medir enteras, asi que puede haber mas."

if [ -n "$TOTAL_BASURA" ] && [ "$(awk -v t="$TOTAL_BASURA" 'BEGIN { print (t>=5)?1:0 }')" = "1" ]; then
    hallazgo "INFO" "ESPACIO" "Sobran unos $TOTAL_BASURA GB de cosas que no hacen falta" \
        "Es la suma de la papelera, las caches, los registros, las copias viejas de iPhone y los restos de Xcode. Nada de eso es tuyo: lo genera el sistema y se rehace solo. MacDiag todavia NO borra nada, de momento solo te dice donde esta.$COLETILLA"
fi

if [ -n "$DESCARGAS_GB" ] && [ "$(awk -v t="$DESCARGAS_GB" 'BEGIN { print (t>=5)?1:0 }')" = "1" ]; then
    hallazgo "INFO" "ESPACIO" "La carpeta de Descargas ocupa $DESCARGAS_GB GB" \
        "Esto va aparte y NO cuenta como espacio liberable: son ficheros tuyos, y ahi dentro puede haber cualquier cosa. Se dice porque suele ser lo mas grande que se puede vaciar a mano, pero mirandolo antes: eso lo decides tu, no un programa."
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
