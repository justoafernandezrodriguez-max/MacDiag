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
#  Modo "a fondo": con permiso de administrador
#
#      bash macdiag-estado.sh --a-fondo
#
#  Hay cosas de este Mac que NO se pueden leer sin permiso, y la mas importante
#  son los partes de fallo del sistema -los kernel panics-, que es de lo mas
#  valioso que hay para saber por que un equipo se reinicia solo.
#
#  Sin permiso no dan un error: dan una carpeta que PARECE VACIA. Por eso el
#  informe normal dice "no se ha podido mirar" en vez de "no hay fallos", y por
#  eso existe este modo: para poder mirarlo de verdad cuando alguien lo pide.
#
#  El permiso se pide UNA vez, al principio, diciendo para que es. El resto del
#  analisis sigue sin necesitarlo.
# ---------------------------------------------------------------------------
A_FONDO="no"
[ "${1:-}" = "--a-fondo" ] && A_FONDO="si"

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

if [ "$A_FONDO" = "si" ]; then
    # Con permiso se lee de verdad. Se pide aqui y solo para esto.
    DiFlojo "pidiendo permiso para leer los partes de fallo del sistema"
    if osascript -e "do shell script \"ls -1 '$DIR_SIS' > '$CRUDO/fallos_sistema_ls.txt' 2>&1; find '$DIR_SIS' -maxdepth 2 -type f -mtime -30 > '$CRUDO/fallos_sistema_30d.txt' 2>&1; chown $(id -u) '$CRUDO/fallos_sistema_ls.txt' '$CRUDO/fallos_sistema_30d.txt'\" with prompt \"MacDiag necesita permiso para leer los partes de fallo del sistema, que dicen por que se ha reiniciado solo el equipo\" with administrator privileges" >/dev/null 2>&1; then
        printf 'fallos_sistema_ls\t0\t0\tls (con permiso)\n'  >> "$CRUDO/_MANDOS.tsv"
        printf 'fallos_sistema_30d\t0\t0\tfind (con permiso)\n' >> "$CRUDO/_MANDOS.tsv"
        DiOk "leidos con permiso de administrador"
        set_dato "fallos.con_permiso" "si"
    else
        DiOjo "sin permiso: se leen como se pueda"
        capturar "fallos_sistema_ls"   20 ls -1 "$DIR_SIS"
        capturar "fallos_sistema_30d"  30 find "$DIR_SIS" -maxdepth 1 -type f -mtime -30
    fi
else
    capturar "fallos_sistema_ls"   20 ls -1 "$DIR_SIS"
    capturar "fallos_sistema_30d"  30 find "$DIR_SIS" -maxdepth 2 -type f -mtime -30
fi
capturar "fallos_usuario_ls"   20 ls -1 "$DIR_USU"
capturar "fallos_usuario_30d"  30 find "$DIR_USU" -maxdepth 1 -type f -mtime -30

PUEDO_LEER_FALLOS="si"
if grep -qiE 'Operation not permitted|Permission denied' "$CRUDO/fallos_sistema_ls.txt" "$CRUDO/fallos_sistema_30d.txt" 2>/dev/null; then
    PUEDO_LEER_FALLOS="no"
    no_pude "Los panicos y cierres inesperados del sistema" \
        "la carpeta $DIR_SIS necesita Acceso total al disco para la Terminal. Sin ese permiso parece vacia, asi que aqui no se dice que no haya: se dice que no se ha mirado."
fi
set_dato "fallos.puedo_leer" "$PUEDO_LEER_FALLOS"

# Las extensiones, que aqui se dieron por sabidas y estaban mal. La trampa 8
# decia "los partes son .ips desde Monterey y .crash antes", escrito sin un Mac
# delante. En Sequoia la mayoria son .diag: en un MacBook de verdad habia 31
# partes en treinta dias -29 .diag, 1 .panic, 1 .ips- y MacDiag contaba UNO,
# porque filtraba por (ips|crash). Un numero tranquilizador y falso, que es la
# forma en que este proyecto ya se ha equivocado dos veces.
#
# Y se contaba todo junto, que es el otro error: un parte de que se ha cerrado
# una aplicacion y un Jetsam no son lo mismo. Un Jetsam es el nucleo MATANDO
# programas porque se ha quedado sin memoria, y eso explica un "va lento" que
# el usuario no sabe nombrar. En ese MacBook hubo cinco en treinta dias.
N_JETSAM=0
if [ "$PUEDO_LEER_FALLOS" = "si" ]; then
    N_PANIC="$(fallos_panic_de  "$CRUDO/fallos_sistema_30d.txt")"
    N_JETSAM="$(fallos_jetsam_de "$CRUDO/fallos_sistema_30d.txt")"
    N_IPS="$(fallos_partes_de   "$CRUDO/fallos_sistema_30d.txt")"
    set_dato "fallos.panics_30d"   "$N_PANIC"
    set_dato "fallos.jetsam_30d"   "$N_JETSAM"
    set_dato "fallos.informes_30d" "$N_IPS"
fi

N_IPS_USU="$(fallos_partes_de "$CRUDO/fallos_usuario_30d.txt")"
set_dato "fallos.usuario_30d" "$N_IPS_USU"

# Y a los Jetsam se les mira dentro, que para eso estan. "Cinco veces" no dice
# nada; "cinco veces, y las que mas ocupaban eran Photoshop y Chrome" dice al
# usuario exactamente que tiene que dejar de abrir a la vez.
: > "$CRUDO/jetsam_procesos.txt"
N_JETSAM_LEIDOS=0
if [ "$N_JETSAM" -gt 0 ]; then
    while IFS= read -r j; do
        [ -r "$j" ] || continue
        quien="$(grep -o '"largestProcess" : "[^"]*"' "$j" 2>/dev/null | head -1 | sed 's/.*: "//; s/"$//')"
        [ -n "$quien" ] || continue
        printf '%s\n' "$quien" >> "$CRUDO/jetsam_procesos.txt"
        N_JETSAM_LEIDOS=$(( N_JETSAM_LEIDOS + 1 ))
    done < <(grep -E '/JetsamEvent[^/]*$' "$CRUDO/fallos_sistema_30d.txt" 2>/dev/null)
fi

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

# Se agrupa por el PROGRAMA al que apuntan, no por fichero.
#
# La primera version saco seis criticos que en realidad eran tres problemas: el
# minero, su reinstalador -que estaba duplicado con " 2.plist"- y los restos de
# otro, tambien duplicados. Es el mismo error de "contar no es mirar" pero al
# reves: repetir el mismo aviso tres veces no informa mas, informa peor, porque
# quien lo lee no sabe si tiene tres problemas o uno.
: > "$CRUDO/_ARRANQUE.tsv"
: > "$CRUDO/_SOSPECHOSOS.tsv"
for carpeta in /Library/LaunchDaemons /Library/LaunchAgents "$HOME/Library/LaunchAgents"; do
    [ -d "$carpeta" ] || continue
    for plist in "$carpeta"/*.plist; do
        [ -e "$plist" ] || continue
        prog="$(programa_de_plist "$plist")"
        arg="$(argumento_de_plist "$plist")"
        motivos="$(motivos_sospecha "$plist")"
        printf '%s\t%s\t%s\n' "$plist" "${prog:-?}" "$motivos" >> "$CRUDO/_ARRANQUE.tsv"
        [ -n "$motivos" ] || continue
        # El destino de verdad: si lanza bash, lo que importa es el script.
        destino="$prog"
        case "${prog##*/}" in bash|sh|zsh) [ -n "$arg" ] && destino="$arg" ;; esac
        etiq="$(etiqueta_de_plist "$plist")"
        printf '%s\t%s\t%s\t%s\n' "$destino" "$plist" "$motivos" "${etiq:-?}" >> "$CRUDO/_SOSPECHOSOS.tsv"
    done
done

N_SOSPECHOSOS=0
N_FICHEROS=0
if [ -s "$CRUDO/_SOSPECHOSOS.tsv" ]; then
    while IFS= read -r destino; do
        [ -n "$destino" ] || continue
        N_SOSPECHOSOS=$(( N_SOSPECHOSOS + 1 ))

        ficheros="$(awk -F'\t' -v d="$destino" '$1==d { print $2 }' "$CRUDO/_SOSPECHOSOS.tsv")"
        cuantos="$(printf '%s\n' "$ficheros" | grep -c .)"
        motivos="$(awk -F'\t' -v d="$destino" '$1==d { print $3; exit }' "$CRUDO/_SOSPECHOSOS.tsv")"
        etiqueta="$(awk -F'\t' -v d="$destino" '$1==d { print $4; exit }' "$CRUDO/_SOSPECHOSOS.tsv")"
        N_FICHEROS=$(( N_FICHEROS + cuantos ))

        # El nombre que se ensena. Con ruta, el del fichero: "xmrig" dice mucho
        # mas que la etiqueta que se haya puesto, que para eso se falsifica.
        # Sin ruta el programa es un mando suelto y su nombre no informa de
        # nada -un agente de Canon que lanza "rm -rf" salia titulado "rm"-, asi
        # que ahi vale mas la etiqueta, que al menos dice de quien es.
        case "$destino" in
            /*) nombre="$(basename "$destino")" ;;
            *)  nombre="$destino"
                [ -n "$etiqueta" ] && [ "$etiqueta" != "?" ] && nombre="$etiqueta" ;;
        esac
        if [ "$cuantos" -gt 1 ]; then
            titulo="\"$nombre\" arranca solo, y hay $cuantos ficheros puestos para que asi sea"
        else
            titulo="\"$nombre\" arranca solo con el equipo y no deberia"
        fi

        lista="$(printf '%s\n' "$ficheros" | sed 's|^|      |' | tr '\n' '@' | sed 's/@/. /g')"
        DiMal "$nombre  ($cuantos fichero(s) de arranque)"

        # Si ademas se esta comiendo la CPU ahora mismo, se dice AQUI y no en un
        # hallazgo aparte: es el mismo problema.
        consumo=""
        pid_vivo="$(pid_del_programa "$destino")"
        if [ -n "$pid_vivo" ]; then
            cpu_vivo="$(ps -p "$pid_vivo" -o pcpu= 2>/dev/null | tr -d ' ')"
            consumo=" Ahora mismo esta EN MARCHA y se lleva el ${cpu_vivo:-?} % de la CPU."
        fi

        hallazgo "CRITICO" "ARRANQUE" "$titulo" \
            "$motivos.$consumo Lo que lo arranca: $(printf '%s' "$ficheros" | tr '\n' ' ')" \
            "quitar-arranque:$destino" \
            "MacDiag descarga el arranque con launchctl, para que no vuelva a lanzarse | Para el programa si esta en marcha | Manda los $cuantos fichero(s) de arranque a la papelera, no los destruye | Vuelve a analizar para comprobar que ya no esta | Lo que NO hace: borrar el programa en si ($destino). Eso lo decides tu, porque puede ser de algo que uses"
    done < <(cut -f1 "$CRUDO/_SOSPECHOSOS.tsv" | sort -u)
fi
set_dato "arranque.sospechosos" "$N_SOSPECHOSOS"
set_dato "arranque.ficheros_sospechosos" "$N_FICHEROS"
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
    # Si este programa ya ha salido arriba como arranque sospechoso, NO se
    # repite: es el mismo problema visto desde otro lado, y repetirlo hace que
    # quien lo lee no sepa si tiene dos problemas o uno.
    if [ -s "$CRUDO/_SOSPECHOSOS.tsv" ] && cut -f1 "$CRUDO/_SOSPECHOSOS.tsv" | grep -qxF "$ruta"; then
        DiFlojo "$cmd: ya contado arriba, en lo que arranca solo"
        continue
    fi
    DiOjo "$cmd: $pcpu % de CPU"
    # Un proceso que se come el equipo Y ademas vive donde no debe no es un
    # programa pesado: es otra cosa. Los dos casos se dicen distinto.
    case "$ruta" in
        /opt/*|/tmp/*|/var/tmp/*|/private/tmp/*|/private/var/tmp/*)
            hallazgo "CRITICO" "PROCESOS" "\"$cmd\" se come el $pcpu % de la CPU y arranca desde $ruta" \
                "Ese sitio no es donde macOS guarda los programas. Un programa que consume asi y ademas vive en una carpeta de paso o en /opt es, casi siempre, algo que no has puesto tu: mineros de criptomonedas y similares." \
                "parar-proceso:$pid" \
                "MacDiag para el programa (necesita permiso de administrador) | Comprueba que no vuelve a arrancar solo: si vuelve, es que algo lo relanza y saldra arriba, en lo que arranca solo | Lo que NO hace: borrar el programa. Miralo tu antes en $ruta" ;;
        *)
            hallazgo "AVISO" "PROCESOS" "\"$cmd\" se esta llevando el $pcpu % de la CPU" \
                "Lleva la CPU muy cargada. Si es algo que has abierto tu -renderizar, comprimir, compilar- es normal y se pasa al terminar." \
                "" \
                "Mira si es algo que has abierto tu | Si lo es y ha terminado, cierralo desde su propia ventana | Si no sabes que es, buscalo por el nombre antes de tocar nada" ;;
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
            "Cuando se acaba la memoria, macOS tira del disco, que es mucho mas lento. Es la explicacion mas comun de que un Mac vaya a tirones sin motivo aparente." \
            "" "Cierra lo que no estes usando, sobre todo pestanas del navegador | Reinicia si lleva muchos dias encendido | Si pasa siempre, a este Mac le falta memoria para lo que le pides"
    fi
fi

# El estrangulamiento: la CPU bajando de velocidad a proposito. Otro dato que
# se capturaba y no se leia.
LIMITE_CPU="$(awk -F'= *' '/CPU_Speed_Limit/ { gsub(/[^0-9]/,"",$2); print $2; exit }' "$CRUDO/termico.txt" 2>/dev/null)"
set_dato "cpu.limite" "${LIMITE_CPU:-}"
if es_numero "$LIMITE_CPU" && [ "$LIMITE_CPU" -lt 100 ]; then
    hallazgo "AVISO" "TEMPERATURA" "La CPU esta funcionando al $LIMITE_CPU % de su velocidad" \
        "El sistema la esta frenando a proposito, y eso pasa por calor o porque algo la tiene al maximo mucho rato." \
        "" "Mira arriba que programa se esta llevando la CPU | Si es algo que has abierto tu, ciarralo al terminar | Si el equipo tiene anos, abrelo y quitale el polvo: el estrangulamiento casi siempre es calor | Si no baja con nada, los ventiladores pueden estar fallando"
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
        "encender-cortafuegos" "Ajustes del Sistema > Red > Firewall | Enciendelo | Si algun programa tuyo deja de recibir conexiones, en Opciones puedes permitirselo uno a uno"
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
        "Alguien con usuario y contrasena de este Mac puede verlo y manejarlo por la red. Si no lo usas, se apaga en Ajustes del Sistema." \
        "apagar-compartir" "Ajustes del Sistema > General > Compartir | Apaga 'Compartir pantalla' si no lo usas | Si trabajas en remoto contra este Mac, NO lo apagues: te quedarias fuera"
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
        "Son programas de este Mac esperando conexiones de fuera, no solo de si mismo. Puede estar perfectamente bien -un servidor que tu has puesto- pero conviene saber cuales son." \
        "" "La lista completa esta en la carpeta crudo, en escuchando.txt | Mira si reconoces cada programa | Los que no sean tuyos, ciarralos o desinstalalos | Encender el cortafuegos tapa los que no necesiten estar abiertos"
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
        "filevault-diferido" "Ajustes del Sistema > Privacidad y seguridad | Busca FileVault y pulsa Activar | GUARDA la clave de recuperacion donde no la pierdas: sin ella y sin tu contrasena, el disco no se abre | Cifrar tarda un rato y va en segundo plano; puedes seguir trabajando" ;;
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

    # Los Jetsam. Van aparte de los panicos y de los partes normales porque no
    # son un fallo de un programa: son el nucleo cerrando programas para poder
    # seguir. El usuario lo vive como "se me ha cerrado solo" y no lo relaciona
    # con la memoria.
    NJ="$(dato fallos.jetsam_30d)"
    if es_numero "$NJ" && [ "$NJ" -gt 0 ]; then
        # Los nombres, que es lo que convierte el numero en algo accionable.
        QUIENES=""
        if [ -s "$CRUDO/jetsam_procesos.txt" ]; then
            QUIENES="$(sort "$CRUDO/jetsam_procesos.txt" | uniq -c | sort -rn | head -3 \
                       | awk '{ n=$1; $1=""; sub(/^ +/,""); printf "%s%s (%s vez/veces)", (NR>1 ? ", " : ""), $0, n }')"
        fi
        if [ -n "$QUIENES" ]; then
            DETALLE_J="Cuando la memoria se agota, macOS cierra programas por su cuenta para poder seguir funcionando: no avisa, la aplicacion simplemente desaparece. Lo que mas ocupaba cuando paso: $QUIENES."
        else
            # Se sabe cuantos pero no cuales: se dice, no se calla.
            DETALLE_J="Cuando la memoria se agota, macOS cierra programas por su cuenta para poder seguir funcionando: no avisa, la aplicacion simplemente desaparece. No se ha podido leer por dentro cual era el programa mas grande en cada caso."
            no_pude "Que programa se estaba cerrando en cada aviso de falta de memoria" \
                "los partes estan en $DIR_SIS pero no se han podido abrir para leerlos por dentro"
        fi
        DETALLE_J="$DETALLE_J Esto no se arregla borrando ficheros: o se abren menos cosas a la vez, o al equipo le falta memoria, y en los portatiles de los ultimos anos va soldada y no se puede ampliar."
        PASOS_J="Mira si las que salen ahi son las que tienes abiertas a la vez | Cerrar pestanas del navegador es lo que mas memoria devuelve | En Monitor de Actividad, pestana Memoria, la Presion de memoria en rojo confirma que se queda corto | Si esto pasa a diario, el equipo necesita mas memoria de la que tiene"
        if [ "$NJ" -ge 3 ]; then
            hallazgo "AVISO" "MEMORIA" "El sistema ha cerrado programas $NJ veces por falta de memoria" "$DETALLE_J" "" "$PASOS_J"
        else
            hallazgo "INFO" "MEMORIA" "El sistema ha cerrado programas $NJ vez/veces por falta de memoria" "$DETALLE_J" "" "$PASOS_J"
        fi
    fi
fi

AP="$(dato act.pendientes)"
if es_numero "$AP" && [ "$AP" -gt 0 ]; then
    hallazgo "AVISO" "SISTEMA" "Hay $AP actualizacion(es) de Apple sin instalar" \
        "Las de seguridad de macOS no son opcionales en la practica." \
        "instalar-actualizaciones" "Ajustes del Sistema > General > Actualizacion de software | Instalar ahora | Algunas piden reiniciar: guarda lo que tengas abierto antes"
fi

# Las copias de seguridad, sobre el texto y no sobre el codigo de salida (ver
# arriba). Los tres estados son distintos y ninguno se puede confundir con otro:
# no hay destino es un AVISO para el usuario, no saberlo es una comprobacion que
# no se ha hecho, y tener destino pero sin copia legible tambien.
case "$TM_ESTADO" in
    "sin destino")
        hallazgo "AVISO" "COPIAS" "Este Mac no tiene ningun destino de Time Machine" \
            "No hay copia de seguridad automatica. Un disco externo de los baratos y encenderlo es todo lo que hace falta; sin eso, un disco roto se lo lleva todo." \
            "abrir:timemachine" "Conecta un disco externo (vale uno de los baratos) | Ajustes del Sistema > General > Time Machine > Anadir disco | Elige el disco y deja que haga la primera copia, que tarda | Luego se hace sola cada hora" ;;
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
