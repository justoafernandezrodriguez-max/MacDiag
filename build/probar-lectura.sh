#!/bin/bash
# ---------------------------------------------------------------------------
#  MacDiag - prueba de la lectura y del informe
#
#  Esto SI se puede ejecutar sin un Mac, y por eso existe. MacDiag se escribio
#  desde Windows, asi que la mitad del codigo -la que ejecuta mandos de macOS-
#  no se ha podido probar. La otra mitad -la que lee texto y pinta el informe-
#  es texto puro y se puede probar en cualquier sitio con bash.
#
#  Las capturas de la primera mitad estan escritas a mano imitando la salida
#  real de cada mando: demuestran que la lectura funciona SI la salida es asi,
#  no que la salida sea asi.
#
#  Las de la seccion "Lo que salio torcido en el primer Mac de verdad" son otra
#  cosa: son la salida LITERAL de un iMac18,3 con macOS 13.7.8, copiadas de la
#  carpeta "crudo" de la primera ejecucion real. Cada una es un fallo que la
#  0.1.0 tenia y que ninguna prueba escrita a mano habia cazado.
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
contiene "el informe dice que solo se probo en un Mac" "$TRABAJO/informe.html" "solo en uno"
contiene "y dice que en Apple Silicon no"              "$TRABAJO/informe.html" "chip de Apple"
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
contiene "el JSON dice donde se ha probado" "$TRABAJO/informe.json" '"probado_en_mac": true'
contiene "y dice donde NO se ha probado"    "$TRABAJO/informe.json" '"sin_probar_en": "Apple Silicon'
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
# Y la trampa volvio a morder en el primer Mac, con otro disfraz: se elegia
# "plutil" mirando si el fichero existe -[ -x /usr/bin/plutil ]-, que es
# EXACTAMENTE preguntar si esta en vez de si funciona, dos lineas debajo de
# haberlo escrito. Y ademas "plutil -lint" NO valida JSON: autodetecta property
# lists y contesta "Unexpected character { at line 1" ante un JSON perfecto.
# Resultado: 49 pruebas bien y una que decia "el JSON NO es valido" con el JSON
# impecable, igual que en Windows.
#
# Asi que ahora el validador no se elige: se EXAMINA. Cada candidato tiene que
# aprobar un JSON bueno Y suspender uno roto. El que no haga las dos cosas no
# vale, aunque exista y aunque no de error.
_bueno="$TRABAJO/_val_bueno.json"; _roto="$TRABAJO/_val_roto.json"
printf '{ "a": [1, 2], "b": "x" }\n' > "$_bueno"
printf '{ "a": 1,, }\n' > "$_roto"

# "plutil -convert" si lee JSON de entrada; se tira a /dev/null porque solo
# interesa si lo acepta. json_pp viene con el Perl de macOS. python3 va el
# ultimo porque en un Mac limpio es el anzuelo de las herramientas de Xcode.
validador_json=""; validador_nombre=""
for cand in "plutil:plutil -convert xml1 -o /dev/null" "json_pp:json_pp" "python3:python3 -c import-json"; do
    nom="${cand%%:*}"
    case "$nom" in
        plutil)  _prueba() { plutil -convert xml1 -o /dev/null "$1" >/dev/null 2>&1; } ;;
        json_pp) _prueba() { json_pp < "$1" >/dev/null 2>&1; } ;;
        python3) _prueba() { python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1; } ;;
    esac
    if _prueba "$_bueno" && ! _prueba "$_roto"; then
        validador_json="$nom"; validador_nombre="$nom"; break
    fi
done

if [ -n "$validador_json" ]; then
    case "$validador_json" in
        plutil)  _prueba() { plutil -convert xml1 -o /dev/null "$1" >/dev/null 2>&1; } ;;
        json_pp) _prueba() { json_pp < "$1" >/dev/null 2>&1; } ;;
        python3) _prueba() { python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1; } ;;
    esac
    if _prueba "$TRABAJO/informe.json"; then
        BIEN=$(( BIEN + 1 )); printf '  ok    el JSON es valido (%s)\n' "$validador_nombre"
    else
        MAL=$(( MAL + 1 )); printf '  MAL   el JSON NO es valido (%s)\n' "$validador_nombre"
    fi
    if _prueba "$TRABAJO/historial.jsonl"; then
        BIEN=$(( BIEN + 1 )); printf '  ok    la linea del historial es JSON valido\n'
    else
        MAL=$(( MAL + 1 )); printf '  MAL   la linea del historial NO es JSON valido\n'
    fi
else
    printf '  --    ningun validador ha aprobado el examen: la validez del JSON se queda SIN COMPROBAR\n'
fi
rm -f "$_bueno" "$_roto"

# ---------------------------------------------------------------------------
printf '\n== Lo que salio torcido en el primer Mac de verdad\n'
# ---------------------------------------------------------------------------
#
# ESTAS CAPTURAS NO ESTAN IMITADAS: son la salida literal de un iMac18,3 con
# macOS 13.7.8, copiada de la carpeta "crudo" de la primera ejecucion real, el
# 26-ago-2026. Por eso valen mas que todas las de arriba: las de arriba dicen
# que la lectura funciona SI la salida es asi; estas dicen que funciona con la
# salida que de verdad da un Mac.
#
# Cada una corresponde a un fallo que la 0.1.0 tenia y que solo se vio
# ejecutandola. Estan aqui para que no vuelvan.

# --- 1. Time Machine sin destino, y el mando termina BIEN --------------------
# Escrito a ciegas se supuso que "destinationinfo" fallaba cuando no hay
# destino. Termina con codigo 0. El aviso colgaba del fallo, asi que un Mac sin
# copias de seguridad no recibia el aviso de que no tenia copias de seguridad.
printf 'tmutil: No destinations configured.\n' > "$CRUDO/tm_destino.txt"
comprobar "sin destino se lee del texto, no del codigo" \
    "sin destino" "$(tm_estado_de "$CRUDO/tm_destino.txt")"

# --- 2. "latestbackup" contesta con un error, tambien con codigo 0 -----------
# Este churro se guardaba tal cual como "Ultima copia" en el informe.
printf 'Failed to mount backup destination, error: Error Domain=com.apple.backupd.ErrorDomain Code=17 "Failed to mount destination." UserInfo={NSLocalizedDescription=Failed to mount destination.}\n' > "$CRUDO/tm_ultima.txt"
comprobar "un error no se cuela como fecha de la ultima copia" \
    "" "$(tm_ultima_de "$CRUDO/tm_ultima.txt")"

# Y una copia de verdad si tiene que pasar.
printf '/Volumes/Copias/Backups.backupdb/iMac/2026-08-20-031500\n' > "$CRUDO/tm_ultima.txt"
comprobar "una copia de verdad si se lee" \
    "/Volumes/Copias/Backups.backupdb/iMac/2026-08-20-031500" "$(tm_ultima_de "$CRUDO/tm_ultima.txt")"

# Con destino configurado, que es el otro camino.
cat > "$CRUDO/tm_destino.txt" <<'FIN'
Name          : Copias
Kind          : Local
Mount Point   : /Volumes/Copias
ID            : 6A1B2C3D-4E5F-6789-ABCD-EF0123456789
FIN
comprobar "con destino se distingue de sin destino" \
    "con destino" "$(tm_estado_de "$CRUDO/tm_destino.txt")"
comprobar "y se saca el nombre del destino" \
    "Copias" "$(campo_sp "$CRUDO/tm_destino.txt" "Name")"

# Un mando que no ha contestado nada no es "no hay copias": es "no se sabe".
: > "$CRUDO/tm_destino.txt"
comprobar "callarse no es decir que no hay destino" \
    "no se sabe" "$(tm_estado_de "$CRUDO/tm_destino.txt")"

# --- 3. "du" que da un total AUNQUE le hayan vetado carpetas -----------------
# Salida literal de ~/Library/Caches en ese Mac: cuatro carpetas de privacidad
# y, aun asi, un total. Se daba por "medido" y se enseñaba la cifra corta como
# si fuera la buena.
cat > "$CRUDO/du_caches.txt" <<'FIN'
du: /Users/tecnicosplato/Library/Caches/com.apple.HomeKit: Operation not permitted
du: /Users/tecnicosplato/Library/Caches/CloudKit: Operation not permitted
du: /Users/tecnicosplato/Library/Caches/com.apple.homed: Operation not permitted
du: /Users/tecnicosplato/Library/Caches/com.apple.ap.adprivacyd: Operation not permitted
1651704	/Users/tecnicosplato/Library/Caches
FIN
comprobar "del du con errores se saca el total"      "1651704" "$(du_kb_de "$CRUDO/du_caches.txt")"
comprobar "y se cuentan las carpetas vetadas"        "4"       "$(du_vetadas_de "$CRUDO/du_caches.txt")"
comprobar "1651704 kB son 1,6 GB"                    "1.6"     "$(gb_de_kb "$(du_kb_de "$CRUDO/du_caches.txt")")"

# --- 4. "du" que no da ningun total -----------------------------------------
# La Papelera del mismo Mac. Aqui no hay cifra que enseñar, y el motivo tiene
# que hablar de la Papelera: antes decia "en Descargas suele ser...".
printf 'du: /Users/tecnicosplato/.Trash: Operation not permitted\n' > "$CRUDO/du_papelera.txt"
comprobar "sin total, no se inventa un numero" "" "$(du_kb_de "$CRUDO/du_papelera.txt")"
comprobar "y se sabe que fue por permisos"     "1" "$(du_vetadas_de "$CRUDO/du_papelera.txt")"

# --- 5. Un du limpio sigue siendo limpio ------------------------------------
printf '23120044\t/Users/tecnicosplato/Downloads\n' > "$CRUDO/du_descargas.txt"
comprobar "un du sin errores no tiene vetadas" "0"        "$(du_vetadas_de "$CRUDO/du_descargas.txt")"
comprobar "y da su total"                      "23120044" "$(du_kb_de "$CRUDO/du_descargas.txt")"

# --- 6. El df real de un Mac con volumen sellado ----------------------------
# Se comprueba con la tabla literal, incluida la linea de "map auto_home" y un
# disco externo montado, que es donde una lectura descuidada se equivoca.
cat > "$CRUDO/df_real.txt" <<'FIN'
Filesystem     1024-blocks     Used  Available Capacity iused       ifree %iused  Mounted on
/dev/disk1s4s1  1875136816  9126384 1769450340     1%  356882  4294309163    0%   /
devfs                  190      190          0   100%     658           0  100%   /dev
/dev/disk1s2    1875136816  1823180 1769450340     1%     899 17694503400    0%   /System/Volumes/Preboot
/dev/disk1s6    1875136816 34604068 1769450340     2%      34 17694503400    0%   /System/Volumes/VM
/dev/disk1s5    1875136816      408 1769450340     1%      18 17694503400    0%   /System/Volumes/Update
/dev/disk1s1    1875136816 58717976 1769450340     4%  287567 17694503400    0%   /System/Volumes/Data
map auto_home            0        0          0   100%       0           0  100%   /System/Volumes/Data/home
/dev/disk2s1       1167320   858656     308664    74%    3670  4294963609    0%   /Volumes/Claude
FIN
comprobar "df: se coge el volumen de DATOS, no la raiz sellada" \
    "1875136816 58717976 1769450340 4" "$(df_de "$CRUDO/df_real.txt" "/System/Volumes/Data")"
comprobar "df: la raiz sellada casi no ocupa, y por eso no vale" \
    "1875136816 9126384 1769450340 1" "$(df_de "$CRUDO/df_real.txt" "/")"
comprobar "df: un disco externo no se confunde con el interno" \
    "1167320 858656 308664 74" "$(df_de "$CRUDO/df_real.txt" "/Volumes/Claude")"

# --- 7. Los datos reales de este Mac se leen enteros -------------------------
cat > "$CRUDO/hw_real.txt" <<'FIN'
Hardware:

    Hardware Overview:

      Model Name: iMac
      Model Identifier: iMac18,3
      Processor Name: Quad-Core Intel Core i7
      Processor Speed: 4,2 GHz
      Number of Processors: 1
      Total Number of Cores: 4
      Memory: 16 GB
      Serial Number (system): (oculto)
      Hardware UUID: (oculto)
FIN
comprobar "un Intel no tiene Chip, tiene Processor Name" \
    "Quad-Core Intel Core i7" "$(campo_sp "$CRUDO/hw_real.txt" "Processor Name")"
comprobar "y Chip esta vacio, que es lo que dispara el respaldo" \
    "" "$(campo_sp "$CRUDO/hw_real.txt" "Chip")"
comprobar "el identificador del modelo" "iMac18,3" "$(campo_sp "$CRUDO/hw_real.txt" "Model Identifier")"

# ---------------------------------------------------------------------------
printf '\n== La columna "Lo arregla"\n'
# ---------------------------------------------------------------------------
#
# En macOS hay cosas que NINGUN programa puede hacer solo: encender FileVault o
# instalar una actualizacion exigen una persona. Si el informe no distingue eso,
# alguien pulsa "Reparar", no pasa nada visible, y concluye que no sirve. Es la
# leccion que PCDIAG pago con su columna "Lo arregla".
: > "$HALLAZGOS"
hallazgo "AVISO"   "SEGURIDAD" "FileVault esta apagado"  "detalle" "abrir:filevault"
hallazgo "AVISO"   "SEGURIDAD" "Gatekeeper desactivado"  "detalle" "gatekeeper"
hallazgo "INFO"    "ESPACIO"   "Descargas ocupa mucho"   "detalle"

comprobar "el hallazgo guarda su accion" \
    "abrir:filevault" "$(awk -F'\t' 'NR==1{print $5}' "$HALLAZGOS")"
comprobar "una accion automatica se guarda igual" \
    "gatekeeper" "$(awk -F'\t' 'NR==2{print $5}' "$HALLAZGOS")"
comprobar "un hallazgo sin arreglo deja el campo vacio" \
    "" "$(awk -F'\t' 'NR==3{print $5}' "$HALLAZGOS")"

escribir_html "$TRABAJO/acciones.html"
contiene "el informe dice cuando lo hace el usuario" "$TRABAJO/acciones.html" "Lo tienes que hacer tu"
contiene "y cuando lo hace MacDiag"                  "$TRABAJO/acciones.html" "Lo arregla MacDiag"
contiene "y cuando no lo arregla nadie"              "$TRABAJO/acciones.html" "no lo arregla un programa"

escribir_json "$TRABAJO/acciones.json"
contiene "el JSON lleva la accion"        "$TRABAJO/acciones.json" '"accion": "abrir:filevault"'
contiene "y la vacia se escribe vacia"    "$TRABAJO/acciones.json" '"accion": ""'

# Un hallazgo de cuatro campos -de una version anterior- no puede reventar la
# lectura: el quinto simplemente no esta.
printf 'AVISO\tVIEJO\tSin quinto campo\tdetalle\n' > "$HALLAZGOS"
escribir_html "$TRABAJO/viejo.html"
contiene "un hallazgo antiguo de 4 campos se sigue leyendo" "$TRABAJO/viejo.html" "Sin quinto campo"

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
