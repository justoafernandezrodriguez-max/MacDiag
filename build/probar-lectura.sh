#!/bin/bash
# ---------------------------------------------------------------------------
#  MacDiag - prueba de la lectura y del informe
#
#  Esto SI se puede ejecutar sin un Mac, y por eso existe. MacDiag se escribio
#  desde Windows, asi que la mitad del codigo -la que ejecuta mandos de macOS-
#  no se ha podido probar. La otra mitad -la que lee texto y pinta el informe-
#  es texto puro y se puede probar en cualquier sitio con bash.
#
#  Las capturas de aqui abajo estan escritas a mano imitando la salida real de
#  cada mando. Eso quiere decir que esta prueba demuestra que la lectura
#  funciona SI la salida es asi; no demuestra que la salida sea asi. Lo segundo
#  solo lo dice un Mac.
#
#      bash build/probar-lectura.sh
# ---------------------------------------------------------------------------

export LC_ALL=C

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
. "$RAIZ/app/lib-comun.sh"
. "$RAIZ/app/lib-informe.sh"

BIEN=0; MAL=0

comprobar() {   # nombre  esperado  obtenido
    if [ "$2" = "$3" ]; then
        BIEN=$(( BIEN + 1 ))
        printf '  ok    %s\n' "$1"
    else
        MAL=$(( MAL + 1 ))
        printf '  MAL   %s\n        esperaba: [%s]\n        ha dado : [%s]\n' "$1" "$2" "$3"
    fi
}

contiene() {    # nombre  fichero  texto
    if grep -qF "$3" "$2" 2>/dev/null; then
        BIEN=$(( BIEN + 1 )); printf '  ok    %s\n' "$1"
    else
        MAL=$(( MAL + 1 )); printf '  MAL   %s (no aparece: %s)\n' "$1" "$3"
    fi
}

no_contiene() {
    if grep -qF "$3" "$2" 2>/dev/null; then
        MAL=$(( MAL + 1 )); printf '  MAL   %s (aparece y no deberia: %s)\n' "$1" "$3"
    else
        BIEN=$(( BIEN + 1 )); printf '  ok    %s\n' "$1"
    fi
}

TRABAJO="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/macdiag-prueba-$$")"
mkdir -p "$TRABAJO"
CRUDO="$TRABAJO/crudo"; mkdir -p "$CRUDO"
DATOS="$TRABAJO/datos.tsv"
HALLAZGOS="$TRABAJO/hallazgos.tsv"
NOPUDE="$TRABAJO/no-he-podido.tsv"
: > "$DATOS"; : > "$HALLAZGOS"; : > "$NOPUDE"

# ---------------------------------------------------------------------------
# Las capturas de mentira
# ---------------------------------------------------------------------------

# sw_vers separa con TABULADOR detras del colon.
printf 'ProductName:\tmacOS\nProductVersion:\t15.3\nBuildVersion:\t24D60\n' > "$CRUDO/sw_vers.txt"

# system_profiler sangra las claves con espacios.
cat > "$CRUDO/hardware.txt" <<'FIN'
Hardware:

    Hardware Overview:

      Model Name: MacBook Pro
      Model Identifier: Mac15,3
      Chip: Apple M3
      Total Number of Cores: 8 (4 performance and 4 efficiency)
      Memory: 16 GB
      Serial Number (system): (oculto)
      Hardware UUID: (oculto)
FIN

# tmutil alinea los dos puntos con espacios: "Name          : Copias"
cat > "$CRUDO/tm_destino.txt" <<'FIN'
====================================================
Name          : Copias de Justo
Kind          : Local
Mount Point   : /Volumes/Copias
ID            : 11111111-2222-3333-4444-555555555555
FIN

# df -k, con el volumen de datos separado de la raiz sellada. Es el caso que
# importa: mirando solo "/" un Mac lleno parece vacio.
cat > "$CRUDO/df.txt" <<'FIN'
Filesystem   1024-blocks      Used Available Capacity iused ifree %iused  Mounted on
/dev/disk3s1s1 971350180  10485760 104857600    10%  400000  10000   80%   /
devfs                402       402         0   100%     696     0  100%   /dev
/dev/disk3s5   971350180 838860800 104857600    89% 3000000 20000   99%   /System/Volumes/Data
map auto_home          0         0         0   100%       0     0  100%   /System/Volumes/Data/home
FIN

cat > "$CRUDO/bateria_pmset.txt" <<'FIN'
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=12345678)	87%; discharging; 3:21 remaining present: true
FIN

cat > "$CRUDO/bateria_ioreg.txt" <<'FIN'
+-o AppleSmartBattery  <class AppleSmartBattery, id 0x100000456>
    {
      "BatteryInstalled" = Yes
      "CycleCount" = 1043
      "DesignCapacity" = 8694
      "AppleRawMaxCapacity" = 7128
      "Serial" = "(oculto)"
    }
FIN

cat > "$CRUDO/diskutil_disk0.txt" <<'FIN'
   Device Identifier:        disk0
   Device / Media Name:      APPLE SSD AP1024
   SMART Status:             Verified
FIN

printf 'du_papelera\t0\t2\tdu -sk /Users/justo/.Trash\nfallos_sistema_ls\t1\t0\tls -1 /Library/Logs/DiagnosticReports\n' > "$CRUDO/_MANDOS.tsv"

# ---------------------------------------------------------------------------
printf '\n== Leer "clave: valor", que en macOS tiene tres formas distintas\n'
comprobar "sw_vers con tabulador"        "15.3"          "$(campo_sp "$CRUDO/sw_vers.txt" "ProductVersion")"
comprobar "system_profiler sangrado"     "MacBook Pro"   "$(campo_sp "$CRUDO/hardware.txt" "Model Name")"
comprobar "system_profiler, chip"        "Apple M3"      "$(campo_sp "$CRUDO/hardware.txt" "Chip")"
comprobar "tmutil con colon alineado"    "Copias de Justo" "$(campo_sp "$CRUDO/tm_destino.txt" "Name")"
comprobar "diskutil, SMART"              "Verified"      "$(campo_sp "$CRUDO/diskutil_disk0.txt" "SMART Status")"
comprobar "una clave que no esta"        ""              "$(campo_sp "$CRUDO/hardware.txt" "No Existe")"
comprobar "un fichero que no esta"       ""              "$(campo_sp "$CRUDO/no-existe.txt" "Chip")"
# "Model Name" y "Model Identifier" empiezan igual: el que no compare la clave
# entera devuelve la primera de las dos para las dos.
comprobar "claves que empiezan igual"    "Mac15,3"       "$(campo_sp "$CRUDO/hardware.txt" "Model Identifier")"

printf '\n== Leer ioreg\n'
comprobar "ciclos de la bateria"         "1043"          "$(campo_ioreg "$CRUDO/bateria_ioreg.txt" "CycleCount")"
comprobar "capacidad de diseño"          "8694"          "$(campo_ioreg "$CRUDO/bateria_ioreg.txt" "DesignCapacity")"
comprobar "un campo que no esta"         ""              "$(campo_ioreg "$CRUDO/bateria_ioreg.txt" "NoExiste")"

printf '\n== Leer df, que es donde esta la trampa del volumen sellado\n'
comprobar "el volumen de datos"          "971350180 838860800 104857600 89" "$(df_de "$CRUDO/df.txt" "/System/Volumes/Data")"
comprobar "la raiz sellada, aparte"      "971350180 10485760 104857600 10"  "$(df_de "$CRUDO/df.txt" "/")"
comprobar "un punto que no existe"       ""              "$(df_de "$CRUDO/df.txt" "/Volumes/Nada")"

printf '\n== Numeros\n'
comprobar "kb a GB"                      "800.0"         "$(gb_de_kb 838860800)"
comprobar "kb a GB, cero"                "0.0"           "$(gb_de_kb 0)"
comprobar "kb a GB, sin dato"            ""              "$(gb_de_kb "")"
comprobar "es_numero con texto"          "no"            "$(if es_numero "12a"; then echo si; else echo no; fi)"
comprobar "es_numero con vacio"          "no"            "$(if es_numero ""; then echo si; else echo no; fi)"
comprobar "es_numero con 0"              "si"            "$(if es_numero "0"; then echo si; else echo no; fi)"

printf '\n== El almacen de datos\n'
set_dato "prueba.uno" "primero"
set_dato "prueba.uno" "segundo"
comprobar "manda el ultimo valor"        "segundo"       "$(dato prueba.uno)"
set_dato "prueba.sucio" "con	tabulador
y salto"
comprobar "el valor se limpia"           "con tabulador y salto" "$(dato prueba.sucio)"
comprobar "una clave que no existe"      ""              "$(dato prueba.nada)"
comprobar "datos_ordenados no repite"    "1"             "$(datos_ordenados | grep -c '^prueba.uno	')"

printf '\n== Contar hallazgos con cero, uno y dos\n'
comprobar "cero criticos"                "0"             "$(cuantos_hallazgos CRITICO)"
hallazgo "CRITICO" "DISCO" "Uno" "detalle uno"
comprobar "un critico"                   "1"             "$(cuantos_hallazgos CRITICO)"
hallazgo "CRITICO" "FALLOS" "Dos" "detalle dos"
hallazgo "AVISO" "BATERIA" "Un aviso" "detalle tres"
comprobar "dos criticos"                 "2"             "$(cuantos_hallazgos CRITICO)"
comprobar "un aviso"                     "1"             "$(cuantos_hallazgos AVISO)"
comprobar "cero informativos"            "0"             "$(cuantos_hallazgos INFO)"

printf '\n== Texto que se mete en sitios\n'
comprobar "html: los signos"             "&amp;&lt;&gt;&quot;"  "$(esc_html '&<>"')"
comprobar "json: comilla"                'dice \"hola\"'        "$(esc_json 'dice "hola"')"
comprobar "json: barra"                  'C:\\\\ruta'           "$(esc_json 'C:\\ruta')"

# ---------------------------------------------------------------------------
printf '\n== El informe entero\n'
set_dato "meta.equipo"  "Mac de Justo"
set_dato "meta.fecha"   "2026-08-25T21:00:00"
set_dato "meta.tardo_s" "94"
set_dato "meta.carpeta" "$TRABAJO"
set_dato "maq.modelo"   "MacBook Pro"
set_dato "maq.chip"     "Apple M3"
set_dato "so.version"   "15.3"
set_dato "disco.punto"  "/System/Volumes/Data"
set_dato "disco.ocupado_pct" "89"
set_dato "disco.total_gb" "926.3"
set_dato "bateria.hay"  "si"
set_dato "bateria.ciclos" "1043"
set_dato "libera.total_gb" "42.7"
set_dato "libera.papelera.etiqueta" "la Papelera"
set_dato "libera.papelera.estado"   "medido"
set_dato "libera.papelera.gb"       "3.2"
set_dato "libera.descargas.etiqueta" "la carpeta de Descargas"
set_dato "libera.descargas.estado"   "no se ha podido medir"
no_pude "Los panicos del sistema" "hace falta Acceso total al disco"

escribir_html "$TRABAJO/informe.html"
escribir_json "$TRABAJO/informe.json"
anotar_historial "$TRABAJO/historial.jsonl"

contiene    "el HTML se ha escrito"          "$TRABAJO/informe.html" "<title>MacDiag"
contiene    "sale el aviso de sin probar"    "$TRABAJO/informe.html" "no se ha podido probar en ningun Mac"
contiene    "sale el nombre del equipo"      "$TRABAJO/informe.html" "Mac de Justo"
contiene    "sale un hallazgo critico"       "$TRABAJO/informe.html" "detalle uno"
contiene    "sale lo que no se ha podido"    "$TRABAJO/informe.html" "Acceso total al disco"
contiene    "un dato que falta se dice"      "$TRABAJO/informe.html" "no se ha podido saber"
contiene    "la carpeta medida sale con GB"  "$TRABAJO/informe.html" "3.2 GB"
contiene    "la que no se pudo medir, no"    "$TRABAJO/informe.html" "no se ha podido medir"
no_contiene "no quedan huecos sin rellenar"  "$TRABAJO/informe.html" '%s'

# El orden importa: lo peor arriba. El primer hallazgo del HTML tiene que ser
# un CRITICO aunque el AVISO se haya añadido en medio.
PRIMER=$(grep -o 'class="h [A-Z]*"' "$TRABAJO/informe.html" | head -1 | sed 's/.*h //; s/"//')
comprobar "el primer hallazgo es critico" "CRITICO" "$PRIMER"

contiene "el JSON se ha escrito"        "$TRABAJO/informe.json" '"app": "MacDiag"'
contiene "el JSON dice que no se probo" "$TRABAJO/informe.json" '"sin_probar_en_mac": true'
contiene "el JSON lleva los hallazgos"  "$TRABAJO/informe.json" '"gravedad": "CRITICO"'
contiene "el historial se ha escrito"   "$TRABAJO/historial.jsonl" '"equipo": "Mac de Justo"'

# --- Que el JSON sea valido de verdad ---------------------------------------
#
# Ojo con "command -v", que aqui ya mintio una vez: en Windows existe un
# python3.exe de pega -el atajo de la tienda de Microsoft- que "command -v"
# encuentra y que al ejecutarse no hace nada y devuelve error. La prueba decia
# entonces "el JSON NO es valido" cuando el JSON estaba perfecto.
#
# La leccion es la de siempre: no preguntar si un programa ESTA, sino si
# FUNCIONA. Y si no hay ninguno, decir que no se ha comprobado en vez de dar
# por buena la comprobacion.
#
# En un Mac siempre hay plutil, asi que alli esto no se salta nunca.
validador_json=""
if plutil -lint /dev/null >/dev/null 2>&1 || [ -x /usr/bin/plutil ]; then
    validador_json="plutil"
elif python3 -c "pass" >/dev/null 2>&1; then
    validador_json="python3"
elif python -c "pass" >/dev/null 2>&1; then
    validador_json="python"
fi

case "$validador_json" in
    plutil)
        if plutil -lint "$TRABAJO/informe.json" >/dev/null 2>&1; then
            BIEN=$(( BIEN + 1 )); printf '  ok    el JSON es valido (plutil)\n'
        else
            MAL=$(( MAL + 1 )); printf '  MAL   el JSON NO es valido (plutil)\n'
        fi ;;
    python3|python)
        if "$validador_json" -c "import json,sys; json.load(open(sys.argv[1]))" "$TRABAJO/informe.json" >/dev/null 2>&1; then
            BIEN=$(( BIEN + 1 )); printf '  ok    el JSON es valido (%s)\n' "$validador_json"
        else
            MAL=$(( MAL + 1 )); printf '  MAL   el JSON NO es valido (%s)\n' "$validador_json"
        fi ;;
    *)
        printf '  --    sin plutil ni python que funcione: la validez del JSON se queda SIN COMPROBAR\n' ;;
esac

# ---------------------------------------------------------------------------
printf '\n== Un informe VACIO, que es el caso que siempre se olvida\n'
DATOS="$TRABAJO/datos2.tsv"; HALLAZGOS="$TRABAJO/hall2.tsv"; NOPUDE="$TRABAJO/nop2.tsv"
: > "$DATOS"; : > "$HALLAZGOS"; : > "$NOPUDE"
set_dato "bateria.hay" "no"
escribir_html "$TRABAJO/vacio.html"
contiene "sin hallazgos lo dice"        "$TRABAJO/vacio.html" "no hay nada que señalar"
contiene "sin bateria no es un fallo"   "$TRABAJO/vacio.html" "es de sobremesa"
contiene "sin nada que no se pudo"      "$TRABAJO/vacio.html" "todas las comprobaciones se han podido hacer"

# ---------------------------------------------------------------------------
printf '\n'
if [ "$MAL" -eq 0 ]; then
    printf '  %s%s pruebas, todas bien.%s\n\n' "$_C_VERDE" "$BIEN" "$_C_FIN"
    rm -rf "$TRABAJO"
    exit 0
else
    printf '  %s%s bien, %s MAL.%s\n' "$_C_ROJO" "$BIEN" "$MAL" "$_C_FIN"
    printf '  Lo que ha quedado esta en: %s\n\n' "$TRABAJO"
    exit 1
fi
