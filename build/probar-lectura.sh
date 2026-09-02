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
# Sin arreglo se escribe un GUION, no un vacio: un campo vacio haria que bash
# se comiera el separador y corriera todo lo de detras (ver mas abajo).
comprobar "un hallazgo sin arreglo escribe el guion" \
    "-" "$(awk -F'\t' 'NR==3{print $5}' "$HALLAZGOS")"
comprobar "y al leerlo vuelve a ser vacio" \
    "" "$(sin_guion "$(awk -F'\t' 'NR==3{print $5}' "$HALLAZGOS")")"

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
printf '\n== El borrado: lo que NO se deja tocar\n'
# ---------------------------------------------------------------------------
#
# El motor de espacio puede mandar a la papelera una ruta concreta. Eso hace
# falta, pero una lista de rutas que llega de fuera y se borra sin mirar es
# justo donde un fallo tonto se convierte en un desastre. Se comprueba que se
# niega a tocar el home entero y las carpetas del sistema.
#
# No se borra nada de verdad aqui: se comprueba que se NIEGA.
ESPACIO="$RAIZ/app/macdiag-espacio.sh"
for prohibida in "$HOME" "/" "/System" "/Library" "/Applications" "/usr"; do
    salida="$(bash "$ESPACIO" --borrar-ruta "$prohibida" 2>&1)"
    if printf '%s' "$salida" | grep -q "me niego a tocar"; then
        BIEN=$(( BIEN + 1 )); printf '  ok    se niega a tocar %s\n' "$prohibida"
    else
        MAL=$(( MAL + 1 )); printf '  MAL   NO se ha negado a tocar %s\n' "$prohibida"
    fi
done

# Una ruta que no existe se dice, no se calla ni se da por hecha.
salida="$(bash "$ESPACIO" --borrar-ruta "$TRABAJO/esto-no-existe-de-verdad" 2>&1)"
if printf '%s' "$salida" | grep -q "no existe"; then
    BIEN=$(( BIEN + 1 )); printf '  ok    una ruta que no existe se dice\n'
else
    MAL=$(( MAL + 1 )); printf '  MAL   una ruta que no existe no se ha dicho\n'
fi

# ---------------------------------------------------------------------------
printf '\n== Diagnostico y mantenimiento, separados\n'
# ---------------------------------------------------------------------------
#
# "No se han podido leer los fallos del sistema" y "no se ha podido medir la
# papelera" acababan en la misma lista. La primera es una laguna en la revision
# del equipo y preocupa; la segunda no dice nada de la salud del Mac. Juntas,
# el aviso que importaba se perdia entre recados sobre carpetas.
: > "$NOPUDE"
no_pude "Los panicos del sistema" "hace falta Acceso total al disco"
no_pude "El tamano de la Papelera" "macOS no deja medirla" "mantenimiento"

comprobar "por defecto una laguna es de diagnostico" \
    "diagnostico" "$(awk -F'\t' 'NR==1{print $3}' "$NOPUDE")"
comprobar "y el mantenimiento se marca como tal" \
    "mantenimiento" "$(awk -F'\t' 'NR==2{print $3}' "$NOPUDE")"

escribir_html "$TRABAJO/separado.html"
contiene "el informe titula las lagunas del equipo"   "$TRABAJO/separado.html" "NO se ha podido comprobar del equipo"
contiene "y lo de medir va en su propio apartado"     "$TRABAJO/separado.html" "Lo que no se ha podido medir"
contiene "el panic sale como laguna del diagnostico"  "$TRABAJO/separado.html" "Los panicos del sistema"
contiene "y se explica que lo otro es mantenimiento"  "$TRABAJO/separado.html" "no salud del equipo"

escribir_json "$TRABAJO/separado.json"
contiene "el JSON lleva el ambito"            "$TRABAJO/separado.json" '"ambito": "mantenimiento"'
contiene "y el de diagnostico tambien"        "$TRABAJO/separado.json" '"ambito": "diagnostico"'

# Con SOLO cosas de mantenimiento, el apartado del equipo tiene que decir que
# esta limpio: si no, un recado sobre una carpeta parecería un fallo del Mac.
: > "$NOPUDE"
no_pude "El tamano de las caches" "permisos" "mantenimiento"
escribir_html "$TRABAJO/solo-mant.html"
contiene "solo mantenimiento deja limpio el diagnostico" "$TRABAJO/solo-mant.html" "todas las comprobaciones del equipo se han podido hacer"

# ---------------------------------------------------------------------------
printf '\n== Contar los partes de fallo, que estaba mal\n'
# ---------------------------------------------------------------------------
#
# Esta lista NO esta imitada: es la salida literal del find en un MacBook Pro
# con Sequoia 15.7.7, el 2-sep-2026, recortada. Hay 31 partes en treinta dias y
# MacDiag decia UNO, porque filtraba por (ips|crash) y en Sequoia casi todos
# son .diag. Un numero tranquilizador y falso.
#
# Y los cuatro Jetsam de "Retired" no llegaban ni a la lista, porque el find
# iba con -maxdepth 1 y esa carpeta esta un nivel mas abajo.

LISTA="$TRABAJO/fallos_reales.txt"
cat > "$LISTA" <<'FIN'
/Library/Logs/DiagnosticReports/.contents.panic
/Library/Logs/DiagnosticReports/JetsamEvent-2026-09-02-105445.ips
/Library/Logs/DiagnosticReports/Sleep Wake Failure_2026-09-01-105240_MacBook-Pro-de-Ines.diag
/Library/Logs/DiagnosticReports/knowledgeconstructiond_2026-09-02-113538_MacBook-Pro-de-Ines.cpu_resource.diag
/Library/Logs/DiagnosticReports/apfsd_2026-08-29-130316_MacBook-Pro-de-Ines.cpu_resource.diag
/Library/Logs/DiagnosticReports/disk writes_2026-09-02-100106_MacBook-Pro-de-Ines.diag
/Library/Logs/DiagnosticReports/Google Chrome_2026-08-31-123717_MacBook-Pro-de-Ines.diag
/Library/Logs/DiagnosticReports/Claude_2026-08-28-133923_MacBook-Pro-de-Ines.diag
/Library/Logs/DiagnosticReports/Retired/JetsamEvent-2026-09-01-110557.ips
/Library/Logs/DiagnosticReports/Retired/JetsamEvent-2026-08-31-115113.ips
/Library/Logs/DiagnosticReports/Retired/JetsamEvent-2026-08-29-130212.ips
/Library/Logs/DiagnosticReports/Retired/JetsamEvent-2026-08-27-203430.ips
FIN

comprobar "los reinicios del sistema se cuentan aparte"  "1"  "$(fallos_panic_de "$LISTA")"
comprobar "los Jetsam se cuentan, y los de Retired tambien" "5" "$(fallos_jetsam_de "$LISTA")"
comprobar "un .diag es un parte de fallo, no un fichero cualquiera" "6" "$(fallos_partes_de "$LISTA")"

# El reparto tiene que ser limpio: si un Jetsam se contara tambien como parte
# normal, el usuario veria el mismo problema dos veces con dos nombres.
TOTAL=$(( $(fallos_panic_de "$LISTA") + $(fallos_jetsam_de "$LISTA") + $(fallos_partes_de "$LISTA") ))
comprobar "y cada parte se cuenta UNA vez, en un solo saco" "12" "$TOTAL"

# Una lista vacia no es un fallo, y un fichero que no esta tampoco: los dos
# tienen que dar cero sin reventar. Es la prueba del caso que siempre se olvida.
: > "$TRABAJO/fallos_vacio.txt"
comprobar "una carpeta sin partes da cero"      "0" "$(fallos_partes_de "$TRABAJO/fallos_vacio.txt")"
comprobar "y un fichero que no existe, tambien" "0" "$(fallos_jetsam_de "$TRABAJO/no-existe-esto.txt")"

# ---------------------------------------------------------------------------
printf '\n== La actualizacion que lo intenta todas las noches\n'
# ---------------------------------------------------------------------------
#
# Captura literal de un MacBook con Sequoia el 2-sep-2026, recortada. El
# sistema llevaba desde el 29-ago despertandose cada madrugada a instalar la
# misma actualizacion sin conseguirlo, y MacDiag solo decia "hay 2
# actualizaciones pendientes", que es verdad y no sirve de nada.

AJ="$TRABAJO/act_ajustes.txt"
cat > "$AJ" <<'FIN'
{
    AutomaticCheckEnabled = 1;
    AutomaticDownload = 1;
    AutomaticallyInstallMacOSUpdates = 1;
    CriticalUpdateInstall = 1;
    FirstInstallTonightDateDictionary =     {
        "MSU_UPDATE_24G325_patch_15.7.2_minor" = "2025-12-01 20:19:07 +0000";
        "MSU_UPDATE_24G419_patch_15.7.3_minor" = "2026-01-16 10:15:59 +0000";
        "MSU_UPDATE_24G720_patch_15.7.7_minor" = "2026-06-26 07:08:05 +0000";
        "MSU_UPDATE_24G830_patch_15.7.9_minor" = "2026-08-29 10:03:39 +0000";
    };
    FirstOfferDateDictionary =     {
        "MSU_UPDATE_24G830_patch_15.7.9_minor" = "2026-08-24 09:55:06 +0000";
    };
    LastRecommendedUpdatesAvailable = 1;
}
FIN
comprobar "se ve que las instala solo" "si" "$(act_auto_de "$AJ")"

# LAS CUATRO ENTRADAS SON A PROPOSITO, y la primera version de esta prueba solo
# tenia una. Ese diccionario acumula una entrada por cada actualizacion que se
# ha intentado poner de noche DESDE SIEMPRE, y las viejas se quedan ahi aunque
# se instalaran sin problemas. Con una sola entrada la prueba pasaba y el
# codigo estaba mal: cogia la mas antigua y contestaba "lleva 274 dias
# intentandolo" por una actualizacion de diciembre que ya estaba puesta.
#
# La leccion es sobre las pruebas, no sobre las fechas: al recortar una captura
# real para meterla aqui se quito justo lo que rompia el codigo. Si se recorta,
# hay que dejar lo que hace el caso dificil.
#
# Los dias salen de restar a hoy, asi que la prueba no puede fijar un numero:
# se calcula con la fecha que TIENE que usar -la ultima noche, no la primera, y
# no la de la primera oferta, que es de otro diccionario-.
DIAS="$(act_dias_intentando_de "$AJ")"
ESPERADO=$(( ( $(date +%s) - $(date -j -f "%Y-%m-%d %H:%M:%S %z" "2026-08-29 10:03:39 +0000" +%s 2>/dev/null) ) / 86400 ))
comprobar "cuenta desde la ULTIMA noche, no desde una actualizacion ya instalada" "$ESPERADO" "$DIAS"

# Apagado es una respuesta, y "no lo pone en el fichero" es otra distinta.
cat > "$TRABAJO/act_apagado.txt" <<'FIN'
{
    AutomaticallyInstallMacOSUpdates = 0;
}
FIN
: > "$TRABAJO/act_mudo.txt"
comprobar "si esta apagado, se dice que esta apagado"   "no" "$(act_auto_de "$TRABAJO/act_apagado.txt")"
comprobar "y si no lo dice el fichero, no se inventa"   ""   "$(act_auto_de "$TRABAJO/act_mudo.txt")"

# Y lo importante: no haberlo intentado NUNCA no es llevar cero dias. Si esto
# devolviera 0 el aviso saltaria en cualquier Mac recien actualizado.
comprobar "no haberlo intentado nunca no es llevar cero dias" "" "$(act_dias_intentando_de "$TRABAJO/act_mudo.txt")"

# ---------------------------------------------------------------------------
printf '\n== El detector de arranques sospechosos\n'
# ---------------------------------------------------------------------------
#
# Escrito despues de que MacDiag no viera un minero de criptomonedas que
# llevaba SEIS DIAS corriendo como root en el Mac de desarrollo. El informe
# decia "Demonios del sistema: 4" y cinco de ellos eran el minero y sus restos.
# Contar no es mirar.
. "$RAIZ/app/lib-vigilancia.sh"
FALSOS="$TRABAJO/plists"; mkdir -p "$FALSOS"

# Uno que finge ser de Apple, con fecha falsificada y script escondido.
cat > "$FALSOS/com.apple.metadata.fetch.plist" <<'FIN'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.apple.metadata.fetch</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>/var/tmp/.instalador.sh</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
FIN
touch -t 197001010000 "$FALSOS/com.apple.metadata.fetch.plist" 2>/dev/null

# Uno legitimo del propio usuario, que TAMBIEN lanza /bin/bash. Este no puede
# marcarse: un aviso que salta sin motivo ensena a ignorar los avisos.
cat > "$FALSOS/es.mrfactory.copias.plist" <<'FIN'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>es.mrfactory.copias</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>/usr/bin/true</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
FIN

m_malo="$(motivos_sospecha "$FALSOS/com.apple.metadata.fetch.plist")"
m_bueno="$(motivos_sospecha "$FALSOS/es.mrfactory.copias.plist")"

if printf '%s' "$m_malo" | grep -q "dice ser de Apple"; then
    BIEN=$(( BIEN + 1 )); printf '  ok    caza al que finge ser de Apple\n'
else
    MAL=$(( MAL + 1 )); printf '  MAL   NO ha cazado al que finge ser de Apple\n'
fi
if printf '%s' "$m_malo" | grep -q "fecha falsificada"; then
    BIEN=$(( BIEN + 1 )); printf '  ok    ve la fecha falsificada de 1970\n'
else
    MAL=$(( MAL + 1 )); printf '  MAL   NO ha visto la fecha falsificada\n'
fi
if printf '%s' "$m_malo" | grep -qE "ficheros temporales|fichero escondido"; then
    BIEN=$(( BIEN + 1 )); printf '  ok    ve que arranca algo escondido en /var/tmp\n'
else
    MAL=$(( MAL + 1 )); printf '  MAL   NO ha visto el script escondido\n'
fi
comprobar "y NO marca al agente legitimo que usa bash" "" "$m_bueno"

# ---------------------------------------------------------------------------
printf '\n== Lo que salio torcido en el primer MacBook ajeno\n'
# ---------------------------------------------------------------------------
#
# Estas capturas NO estan imitadas: son la forma literal de los plists de un
# MacBook Pro de 2018 con Sequoia, Adobe, OneDrive y Canon puestos, el
# 2-sep-2026. En el iMac de desarrollo no habia software comercial de este
# tipo, asi que el detector se estreno alli con diez arranques limpios y cinco
# de un minero, y parecia que no fallaba. En cuanto vio un Mac de alguien saco
# CINCO criticos de los que CUATRO eran mentira.
#
# El fallo de raiz era uno solo: el lector entraba en "ProgramArguments" y no
# paraba al cerrar el array, asi que se llevaba el valor de la clave de al
# lado. Es la trampa de los campos vacios que se tragan el siguiente -que ya
# tiene su propia seccion mas arriba- aparecida en otro sitio.
#
# plutil -p ordena las claves alfabeticamente, y de ahi la mala suerte: detras
# de "ProgramArguments" caen justo "SpawnConstraint" y "StandardErrorPath".

# 1. OneDrive: ProgramArguments VACIO, un Program bueno, y debajo la firma.
#    Se leia "com.microsoft.OneDriveStandaloneUpdaterDaemon" como si fuera el
#    programa, y como eso no es un fichero, se declaraba roto.
cat > "$FALSOS/onedrive.plist" <<'FIN'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.microsoft.OneDriveStandaloneUpdaterDaemon</string>
<key>MachServices</key><dict><key>com.microsoft.OneDriveStandaloneUpdaterDaemon</key><true/></dict>
<key>Program</key><string>/bin/ls</string>
<key>ProgramArguments</key><array/>
<key>SpawnConstraint</key><dict>
  <key>signing-identifier</key><string>com.microsoft.OneDriveStandaloneUpdaterDaemon</string>
  <key>team-identifier</key><string>UBF8T346G9</string>
</dict>
<key>StandardErrorPath</key><string>/Library/Logs/Microsoft/OneDrive/x.log</string>
</dict></plist>
FIN
comprobar "con ProgramArguments vacio se lee el Program, no la firma de abajo" \
    "/bin/ls" "$(programa_de_plist "$FALSOS/onedrive.plist")"
comprobar "y un demonio firmado y entero no se denuncia" \
    "" "$(motivos_sospecha "$FALSOS/onedrive.plist")"

# 2. Adobe: UN argumento, y debajo un StandardErrorPath en /tmp. Escribir el
#    registro de errores en /tmp no es arrancar nada de /tmp, pero se leia esa
#    ruta como el segundo argumento y se le acusaba de eso mismo.
cat > "$FALSOS/adobe.plist" <<'FIN'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>Adobe_Genuine_Software_Integrity_Service</string>
<key>Nice</key><integer>1</integer>
<key>ProgramArguments</key><array><string>/bin/ls</string></array>
<key>RunAtLoad</key><true/>
<key>StandardErrorPath</key><string>/tmp/AlTest1.err</string>
<key>StandardOutPath</key><string>/tmp/AlTest1.out</string>
<key>StartInterval</key><integer>21600</integer>
</dict></plist>
FIN
comprobar "con un solo argumento, el segundo esta VACIO y no es la clave siguiente" \
    "" "$(argumento_de_plist "$FALSOS/adobe.plist")"
comprobar "y el registro de errores en /tmp no es arrancar algo de /tmp" \
    "" "$(motivos_sospecha "$FALSOS/adobe.plist")"

# 3. Canon: lanza "rm -rf" y "rm" es un mando suelto, no una ruta. Preguntarle
#    a un mando suelto si existe como fichero da que no, y salia un hallazgo
#    critico titulado "rm" sobre un programa que no existia. /bin/rm existe.
cat > "$FALSOS/canon-rm.plist" <<'FIN'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>jp.co.canon.ij.rp.photoservice.webinstaller</string>
<key>ProgramArguments</key><array><string>rm</string><string>-rf</string><string>mAWI</string></array>
<key>RunAtLoad</key><true/>
<key>WorkingDirectory</key><string>/var/folders/pp/x/T</string>
</dict></plist>
FIN
comprobar "un mando suelto se lee tal cual"        "rm" "$(programa_de_plist "$FALSOS/canon-rm.plist")"
comprobar "y el segundo argumento tambien"         "-rf" "$(argumento_de_plist "$FALSOS/canon-rm.plist")"
comprobar "y NO se dice que /bin/rm no exista"     "" "$(motivos_sospecha "$FALSOS/canon-rm.plist")"

# 4. Pero un mando suelto que de verdad no esta SI se denuncia. Si no, el
#    arreglo de arriba habria apagado la regla entera, que es la forma mas
#    silenciosa de romper un comprobador: dejar de comprobar.
cat > "$FALSOS/mando-fantasma.plist" <<'FIN'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>es.macdiag.mando.fantasma</string>
<key>ProgramArguments</key><array><string>estonoexistecomomando</string></array>
</dict></plist>
FIN
if printf '%s' "$(motivos_sospecha "$FALSOS/mando-fantasma.plist")" | grep -q "no existe"; then
    BIEN=$(( BIEN + 1 )); printf '  ok    un mando que NO esta en el PATH sigue denunciandose\n'
else
    MAL=$(( MAL + 1 )); printf '  MAL   ha dejado de ver un mando que no existe\n'
fi

# 5. Y el resto de verdad de aquel MacBook: Canon dejo puesto un demonio que
#    apunta a un ayudante que ya no esta. Ese hallazgo era el unico correcto de
#    los cinco y tiene que seguir saliendo.
cat > "$FALSOS/canon-resto.plist" <<'FIN'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>jp.co.canon.MasterInstaller</string>
<key>Program</key><string>/Library/PrivilegedHelperTools/jp.co.canon.NoEstaAqui</string>
<key>ProgramArguments</key><array><string>/Library/PrivilegedHelperTools/jp.co.canon.NoEstaAqui</string></array>
<key>ServiceIPC</key><integer>1</integer>
<key>Sockets</key><dict><key>MasterSocket</key><dict>
  <key>SockFamily</key><string>Unix</string>
</dict></dict>
</dict></plist>
FIN
if printf '%s' "$(motivos_sospecha "$FALSOS/canon-resto.plist")" | grep -q "no existe"; then
    BIEN=$(( BIEN + 1 )); printf '  ok    el resto que apunta a un ayudante borrado sigue saltando\n'
else
    MAL=$(( MAL + 1 )); printf '  MAL   ya no ve el resto que apunta a un programa borrado\n'
fi
comprobar "y con un solo argumento no se inventa un segundo desde Sockets" \
    "" "$(argumento_de_plist "$FALSOS/canon-resto.plist")"

# ---------------------------------------------------------------------------
printf '\n== De donde sale un programa que se come la CPU\n'
# ---------------------------------------------------------------------------
#
# "knowledgeconstructiond se lleva el 98 % de la CPU" y punto es contar sin
# mirar: quien lo lee no sabe si eso es macOS indexando o algo que sobra. La
# ruta ya lo dice, y gratis: /System va en el volumen sellado.
#
# Comprobado con df y mount en los dos Macs de pruebas: /System, /usr/bin,
# /usr/libexec, /usr/sbin, /sbin y /bin sirven desde "/", que monta sellado y
# de solo lectura. /Applications, /Library y /usr/local van en el de datos.

procedencia_de "/System/Library/PrivateFrameworks/IntelligencePlatformCore.framework/Versions/A/knowledgeconstructiond"
comprobar "un programa de /System es del sistema, y se sabe sin ejecutar nada" "sistema" "$PROCEDENCIA_CLASE"
procedencia_de "/usr/libexec/thermalmonitord"
comprobar "y uno de /usr/libexec tambien"                                     "sistema" "$PROCEDENCIA_CLASE"
procedencia_de "/bin/ls"
comprobar "y uno de /bin"                                                     "sistema" "$PROCEDENCIA_CLASE"

# /usr/local NO es del sistema aunque el nombre lo parezca: va en el volumen de
# datos, que se escribe. Darlo por sellado seria firmarle un aval a cualquier
# cosa que alguien deje ahi, y en el MacBook de las pruebas habia justo eso:
# un demonio de root escuchando en tres puertos desde /usr/local.
procedencia_de "/usr/local/codex/bin/drserver"
if [ "$PROCEDENCIA_CLASE" = "sistema" ]; then
    MAL=$(( MAL + 1 )); printf '  MAL   ha dado /usr/local por sistema, y ese volumen se escribe\n'
else
    BIEN=$(( BIEN + 1 )); printf '  ok    pero /usr/local NO es el sistema: ese volumen se escribe\n'
fi

# Sin ruta no se puede saber, y eso se dice en vez de suponer.
procedencia_de ""
comprobar "sin ruta no se inventa una procedencia" "nosesabe" "$PROCEDENCIA_CLASE"

# Un fichero que existe y no lo firma nadie: tiene que salir como tal, no como
# "no se sabe". Son cosas distintas y el aviso cambia.
printf '#!/bin/sh\ntrue\n' > "$TRABAJO/programa-pelado"
chmod +x "$TRABAJO/programa-pelado"
procedencia_de "$TRABAJO/programa-pelado"
comprobar "un programa sin firma se dice que no la lleva" "sinfirmar" "$PROCEDENCIA_CLASE"

# ---------------------------------------------------------------------------
printf '\n== De quien es el proceso que se va a matar\n'
# ---------------------------------------------------------------------------
#
# Esto no es cosmetica. El PID que sale de aqui va derecho a un kill -9 COMO
# ROOT en el boton de quitar un arranque. Antes se buscaba con pgrep -f, que
# casa por trozo de texto contra la linea de mandos entera: con "rm" devolvia
# once procesos de un Mac normal -theRMalmonitord, useRManagerd, theRMald- y el
# informe llego a decir que "rm" estaba EN MARCHA al 0,0 % de CPU cuando quien
# estaba en marcha era thermalmonitord. Quitar ese arranque habria matado un
# demonio del sistema. No llego a pasar porque ese boton nunca se ha pulsado.

comprobar "un mando suelto no se atribuye ningun proceso" "" "$(pid_del_programa rm)"
comprobar "ni un programa que no existe"                  "" "$(pid_del_programa /no/existe/de/verdad)"

# Y el caso positivo, que es el que impide que esto se quede en un comprobador
# que no salta nunca: se lanza un proceso conocido y tiene que encontrarlo.
/bin/sleep 20 &
PID_SLEEP=$!
sleep 1
comprobar "pero a un proceso de verdad SI lo encuentra, por su ruta" \
    "$PID_SLEEP" "$(pid_del_programa /bin/sleep)"
kill "$PID_SLEEP" 2>/dev/null
wait "$PID_SLEEP" 2>/dev/null

# ---------------------------------------------------------------------------
printf '\n== Los pasos, y no repetir el mismo problema\n'
# ---------------------------------------------------------------------------
#
# La primera version de la vigilancia saco SEIS criticos que en realidad eran
# tres problemas: el minero, su reinstalador duplicado y los restos de otro,
# tambien duplicados. Repetir el mismo aviso tres veces no informa mas, informa
# peor: quien lo lee no sabe si tiene tres problemas o uno.
: > "$HALLAZGOS"
hallazgo "CRITICO" "ARRANQUE" "Algo arranca solo" "detalle" "quitar-arranque:/opt/x" \
    "Primero esto | Luego lo otro | Y por ultimo esto"

comprobar "el hallazgo guarda sus pasos" \
    "Primero esto | Luego lo otro | Y por ultimo esto" "$(awk -F'\t' 'NR==1{print $6}' "$HALLAZGOS")"
comprobar "y son tres" \
    "3" "$(awk -F'\t' 'NR==1{print $6}' "$HALLAZGOS" | tr '|' '\n' | grep -c .)"

escribir_json "$TRABAJO/pasos.json"
contiene "el JSON lleva los pasos" "$TRABAJO/pasos.json" '"pasos": "Primero esto'

# Dos ficheros de arranque que apuntan AL MISMO programa son UN problema.
: > "$TRABAJO/sosp.tsv"
printf '/var/tmp/.malo.sh\t/Library/LaunchDaemons/uno.plist\tmotivo\tcom.a\n'  >> "$TRABAJO/sosp.tsv"
printf '/var/tmp/.malo.sh\t/Library/LaunchDaemons/uno 2.plist\tmotivo\tcom.a\n' >> "$TRABAJO/sosp.tsv"
printf '/opt/otro/otro\t/Library/LaunchDaemons/dos.plist\tmotivo\tcom.b\n'      >> "$TRABAJO/sosp.tsv"
comprobar "tres ficheros que son dos problemas se agrupan en dos" \
    "2" "$(cut -f1 "$TRABAJO/sosp.tsv" | sort -u | grep -c .)"
comprobar "y el que se repite cuenta sus dos ficheros" \
    "2" "$(awk -F'\t' '$1=="/var/tmp/.malo.sh"' "$TRABAJO/sosp.tsv" | grep -c .)"

# Un hallazgo de cinco campos -de la 0.4.0- se sigue leyendo sin el sexto.
printf 'AVISO\tVIEJO\tSin pasos\tdetalle\tabrir:algo\n' > "$HALLAZGOS"
escribir_html "$TRABAJO/cinco.html"
contiene "un hallazgo sin pasos se sigue leyendo" "$TRABAJO/cinco.html" "Sin pasos"

# ---------------------------------------------------------------------------
printf '\n== Los campos vacios, que en bash se tragan el siguiente\n'
# ---------------------------------------------------------------------------
#
# ESTA ES LA PRUEBA QUE HABRIA AHORRADO UNA TARDE.
#
# El tabulador es un caracter de espacio para IFS, asi que bash trata DOS
# TABULADORES SEGUIDOS COMO UNO. Con un campo vacio en medio, todo lo que viene
# detras se corre un sitio:
#
#     printf 'a\t\tc' | { IFS=$'\t' read -r x y z; }   ->  x=a  y=c  z=(vacio)
#
# Lo que paso de verdad: los hallazgos sin accion se leian con los PASOS en el
# campo de la accion, y "Reparar todo" intentaba aplicar una frase como si fuera
# un arreglo. No dio ningun error. Simplemente no reparaba.
: > "$HALLAZGOS"
hallazgo "AVISO" "TEMPERATURA" "La CPU va frenada" "detalle" "" "Quita el polvo | Mira que consume"
hallazgo "AVISO" "SEGURIDAD"   "Cortafuegos apagado" "detalle" "encender-cortafuegos" "Ajustes > Red"

IFS=$'\t' read -r g1 e1 t1 d1 a1 p1 < "$HALLAZGOS"
comprobar "sin accion, los pasos NO se cuelan en la accion" "" "$(sin_guion "$a1")"
comprobar "y los pasos siguen en su sitio" "Quita el polvo | Mira que consume" "$(sin_guion "$p1")"

a2="$(awk -F'\t' 'NR==2{print $5}' "$HALLAZGOS")"
p2="$(awk -F'\t' 'NR==2{print $6}' "$HALLAZGOS")"
comprobar "con accion, se lee la accion y no otra cosa" "encender-cortafuegos" "$a2"
comprobar "y sus pasos tambien"                         "Ajustes > Red"        "$p2"

# Todas las lineas tienen que tener los seis campos, siempre. Si alguna trae
# cinco es que se ha colado un vacio y lo de detras esta corrido.
mal=0
while IFS= read -r linea; do
    n=$(printf '%s' "$linea" | awk -F'\t' '{print NF}')
    [ "$n" -eq 6 ] || mal=$(( mal + 1 ))
done < "$HALLAZGOS"
comprobar "todas las lineas tienen los 6 campos" "0" "$mal"

# Y el informe no puede ensenar el guion, que es un apano interno.
escribir_html "$TRABAJO/guiones.html"
no_contiene "el guion interno no se ensena al usuario" "$TRABAJO/guiones.html" ">-<"
escribir_json "$TRABAJO/guiones.json"
no_contiene "ni sale en el JSON"                       "$TRABAJO/guiones.json" '"accion": "-"'

# ---------------------------------------------------------------------------
printf '\n== Un informe VACIO, que es el caso que siempre se olvida\n'
DATOS="$TRABAJO/datos2.tsv"; HALLAZGOS="$TRABAJO/hall2.tsv"; NOPUDE="$TRABAJO/nop2.tsv"
: > "$DATOS"; : > "$HALLAZGOS"; : > "$NOPUDE"
set_dato "bateria.hay" "no"
escribir_html "$TRABAJO/vacio.html"
contiene "sin hallazgos lo dice"        "$TRABAJO/vacio.html" "no hay nada que señalar"
contiene "sin bateria no es un fallo"   "$TRABAJO/vacio.html" "es de sobremesa"
contiene "sin nada que no se pudo"      "$TRABAJO/vacio.html" "todas las comprobaciones del equipo se han podido hacer"

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
