# ---------------------------------------------------------------------------
#  MacDiag - el informe
#
#  Pinta el HTML que lee una persona y el JSON que lee una maquina, los dos a
#  partir de datos.tsv y hallazgos.tsv. No mira el sistema: para cuando esto
#  corre, todo lo que hay que saber ya esta en esos dos ficheros.
#
#  Esa separacion es la de PCDIAG -motores por un lado, informe por otro- y es
#  lo que permitira poner una ventana de verdad mas adelante sin tocar el
#  diagnostico.
#
#  PROBADO en un iMac Intel con macOS 13.7.8. Ver LEEME.txt.
# ---------------------------------------------------------------------------

# Una fila de la tabla. Si el dato no esta, se dice que no se sabe: una celda
# vacia se lee como "cero" o como "bien", y casi nunca es ninguna de las dos.
fila_html() {
    local etiqueta="$1"; local clave="$2"; local sufijo="$3"
    local v
    v="$(dato "$clave")"
    if [ -z "$v" ]; then
        printf '<tr><th>%s</th><td class="nose">no se ha podido saber</td></tr>\n' "$(esc_html "$etiqueta")"
    else
        printf '<tr><th>%s</th><td>%s%s</td></tr>\n' "$(esc_html "$etiqueta")" "$(esc_html "$v")" "$sufijo"
    fi
}

escribir_html() {
    local salida="$1"
    local nC nA nI
    nC=$(cuantos_hallazgos CRITICO); nA=$(cuantos_hallazgos AVISO); nI=$(cuantos_hallazgos INFO)

    {
cat <<'CABECERA'
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MacDiag - como esta este Mac</title>
<style>
:root { --tinta:#1d1d1f; --flojo:#6e6e73; --linea:#d2d2d7; --fondo:#f5f5f7;
        --caja:#ffffff; --rojo:#c1272d; --ambar:#9a6700; --azul:#0b6bcb; --verde:#1a7f37; }
* { box-sizing:border-box; }
body { margin:0; padding:0 16px 64px; background:var(--fondo); color:var(--tinta);
       font:16px/1.55 -apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",Arial,sans-serif; }
.hoja { max-width:900px; margin:0 auto; }
header { padding:36px 0 12px; }
h1 { font-size:26px; margin:0 0 4px; letter-spacing:-.02em; }
.sub { color:var(--flojo); font-size:14px; }
h2 { font-size:19px; margin:34px 0 10px; letter-spacing:-.01em; }
.kpis { display:flex; flex-wrap:wrap; gap:10px; margin:18px 0 6px; }
.kpi { background:var(--caja); border:1px solid var(--linea); border-radius:12px;
       padding:14px 18px; min-width:120px; flex:1; }
.kpi .n { font-size:30px; font-weight:600; line-height:1.1; }
.kpi .l { font-size:12px; color:var(--flojo); text-transform:uppercase; letter-spacing:.04em; }
.kpi.c .n { color:var(--rojo); } .kpi.a .n { color:var(--ambar); } .kpi.o .n { color:var(--azul); }
.h { background:var(--caja); border:1px solid var(--linea); border-left-width:5px;
     border-radius:10px; padding:14px 16px; margin:10px 0; }
.h.CRITICO { border-left-color:var(--rojo); }
.h.AVISO   { border-left-color:var(--ambar); }
.h.INFO    { border-left-color:var(--azul); }
.h b { display:block; margin-bottom:4px; }
.h p { margin:0; color:var(--flojo); font-size:14px; }
.tag { display:inline-block; font-size:11px; letter-spacing:.06em; color:var(--flojo);
       border:1px solid var(--linea); border-radius:20px; padding:1px 9px; margin-right:8px; }
table { width:100%; border-collapse:collapse; background:var(--caja);
        border:1px solid var(--linea); border-radius:10px; overflow:hidden; }
th,td { text-align:left; padding:9px 14px; border-bottom:1px solid var(--linea); font-size:14px; vertical-align:top; }
th { width:38%; font-weight:500; color:var(--flojo); }
tr:last-child th, tr:last-child td { border-bottom:none; }
.nose { color:var(--ambar); font-style:italic; }
.nota { color:var(--flojo); font-size:14px; }
.aviso-grande { background:#fff8e5; border:1px solid #e6cf8b; border-radius:10px;
                padding:14px 16px; margin:18px 0; font-size:14px; }
.tabla-scroll { overflow-x:auto; }
code { font:13px/1.4 ui-monospace,SFMono-Regular,Menlo,monospace; }
footer { margin-top:44px; color:var(--flojo); font-size:12px; }
</style>
</head>
<body><div class="hoja">
CABECERA

        printf '<header><h1>Como esta este Mac</h1><div class="sub">%s &middot; %s &middot; MacDiag %s</div></header>\n' \
            "$(esc_html "$(dato meta.equipo)")" \
            "$(esc_html "$(dato meta.fecha)" | sed 's/T/ /')" \
            "$(esc_html "$VERSION_MACDIAG")"

cat <<'CAJA'
<div class="aviso-grande"><b>Esta version ya se ha ejecutado en un Mac, pero solo en uno.</b>
Se probo en un iMac con procesador Intel y macOS 13.7.8. <b>No</b> se ha probado todavia en un Mac
con chip de Apple (M1 y siguientes) ni en un portatil, asi que la bateria y algun dato pueden salir
mal leidos ahi. Lo que <b>no</b> puede pasar es que cambie nada: esta version solo lee. Si algo se
ve raro, la carpeta <code>crudo</code> que hay al lado de este informe lleva la salida original de
cada mando y sirve para arreglarlo.</div>
CAJA

        printf '<div class="kpis">'
        printf '<div class="kpi c"><div class="n">%s</div><div class="l">para mirar ya</div></div>' "$nC"
        printf '<div class="kpi a"><div class="n">%s</div><div class="l">avisos</div></div>' "$nA"
        printf '<div class="kpi o"><div class="n">%s</div><div class="l">%% del disco</div></div>' "$(dato disco.ocupado_pct)"
        # El numero gordo es SOLO lo que sobra de verdad. Sumarle Descargas -que
        # son ficheros del usuario- convertia este KPI en una invitacion a borrar
        # lo que no habia que borrar.
        _lib="$(dato libera.basura_gb)"; [ -n "$_lib" ] || _lib="$(dato libera.total_gb)"
        printf '<div class="kpi o"><div class="n">%s</div><div class="l">GB que sobran</div></div>' "$_lib"
        printf '</div>\n'

        # --- Hallazgos, los peores arriba -----------------------------------
        if [ -s "$HALLAZGOS" ]; then
            printf '<h2>Lo que conviene mirar</h2>\n'
            for g in CRITICO AVISO INFO; do
                while IFS=$'\t' read -r gr et ti de; do
                    [ "$gr" = "$g" ] || continue
                    printf '<div class="h %s"><b><span class="tag">%s</span>%s</b><p>%s</p></div>\n' \
                        "$gr" "$(esc_html "$et")" "$(esc_html "$ti")" "$(esc_html "$de")"
                done < "$HALLAZGOS"
            done
        else
            printf '<h2>Lo que conviene mirar</h2>\n<p class="nota">Nada. De lo que se ha podido comprobar, no hay nada que señalar.</p>\n'
        fi

        # --- El equipo ------------------------------------------------------
        printf '<h2>El equipo</h2>\n<table>\n'
        fila_html "Nombre"          "meta.equipo"
        fila_html "Modelo"          "maq.modelo"
        fila_html "Identificador"   "maq.identificador"
        fila_html "Chip"            "maq.chip"
        fila_html "Nucleos"         "maq.nucleos"
        fila_html "Arquitectura"    "maq.arquitectura"
        fila_html "Memoria"         "maq.memoria"
        fila_html "macOS"           "so.version"
        fila_html "Compilacion"     "so.build"
        fila_html "Encendido desde" "meta.uptime"
        printf '</table>\n'

        # --- Disco ----------------------------------------------------------
        printf '<h2>El disco</h2>\n<table>\n'
        fila_html "Volumen medido"     "disco.punto"
        fila_html "Capacidad"          "disco.total_gb" " GB"
        fila_html "Ocupado"            "disco.usado_gb" " GB"
        fila_html "Libre"              "disco.libre_gb" " GB"
        fila_html "Porcentaje ocupado" "disco.ocupado_pct" " %"
        fila_html "Estado SMART"       "disco.smart"
        fila_html "Instantaneas locales de Time Machine" "disco.instantaneas"
        printf '</table>\n'
        printf '<p class="nota">El espacio libre de un disco APFS no es un solo numero: el Finder puede decir una cifra distinta de esta porque cuenta aparte lo &laquo;purgable&raquo; -instantaneas y caches que el sistema soltaria si hiciera falta-. Aqui se enseña lo que dice <code>df</code>, que es lo que de verdad hay disponible ahora mismo.</p>\n'

        # --- Bateria --------------------------------------------------------
        if [ "$(dato bateria.hay)" = "si" ]; then
            printf '<h2>La bateria</h2>\n<table>\n'
            fila_html "Carga ahora"   "bateria.carga"
            fila_html "Ciclos"        "bateria.ciclos"
            fila_html "Estado"        "bateria.estado"
            fila_html "Capacidad maxima" "bateria.salud"
            printf '</table>\n'
        else
            printf '<h2>La bateria</h2>\n<p class="nota">Este Mac no tiene bateria: es de sobremesa. No es que no se haya podido mirar.</p>\n'
        fi

        # --- Seguridad y copias ---------------------------------------------
        printf '<h2>Seguridad y copias</h2>\n<table>\n'
        fila_html "FileVault (cifrado del disco)" "seg.filevault"
        fila_html "SIP (integridad del sistema)"  "seg.sip"
        fila_html "Gatekeeper"                    "seg.gatekeeper"
        # "No hay ningun destino" es un dato, no una casilla vacia. Antes esta fila
        # decia "no se ha podido saber" en un Mac SIN copias configuradas, que es
        # justo el equipo al que hay que avisarle.
        case "$(dato tm.estado)" in
            "sin destino")
                printf '<tr><th>Destino de Time Machine</th><td>no hay ninguno configurado</td></tr>\n'
                printf '<tr><th>Ultima copia</th><td>no hay copias: no hay donde hacerlas</td></tr>\n' ;;
            "con destino")
                fila_html "Destino de Time Machine" "tm.destino"
                fila_html "Ultima copia"            "tm.ultima" ;;
            *)
                printf '<tr><th>Destino de Time Machine</th><td class="nose">no se ha podido saber</td></tr>\n'
                printf '<tr><th>Ultima copia</th><td class="nose">no se ha podido saber</td></tr>\n' ;;
        esac
        fila_html "Actualizaciones pendientes"    "act.pendientes"
        printf '</table>\n'

        # --- Fallos ----------------------------------------------------------
        printf '<h2>Cierres inesperados</h2>\n'
        if [ "$(dato fallos.puedo_leer)" = "si" ]; then
            printf '<table>\n'
            fila_html "Reinicios por fallo del sistema (30 dias)" "fallos.panics_30d"
            fila_html "Partes de fallo del sistema (30 dias)"     "fallos.informes_30d"
            fila_html "Partes de fallo de tus aplicaciones (30 dias)" "fallos.usuario_30d"
            printf '</table>\n'
        else
            printf '<p class="nota">No se ha podido mirar la carpeta del sistema. Esto <b>no</b> quiere decir que no haya fallos: quiere decir que no se sabe. Esta explicado al final.</p>\n'
        fi

        # --- Arranque --------------------------------------------------------
        printf '<h2>Lo que se abre solo al arrancar</h2>\n<table>\n'
        fila_html "Agentes del sistema"   "arranque.agentes_sistema"
        fila_html "Demonios del sistema"  "arranque.demonios"
        fila_html "Agentes tuyos"         "arranque.agentes_usuario"
        printf '</table>\n'
        printf '<p class="nota">MacDiag no quita nada de aqui: lo cuenta. Un elemento de arranque que sobra lo quita quien sepa de quien es.</p>\n'

        # --- Espacio ---------------------------------------------------------
        printf '<h2>Que se podria liberar</h2>\n<table>\n'
        # Descargas NO va en esta lista: va en su propia tabla, debajo y con su
        # explicacion. Mezclarlas hacia que 23 GB de ficheros del usuario
        # aparecieran como si fueran basura del sistema.
        for c in papelera caches logs ios xcode simulador; do
            et="$(dato "libera.$c.etiqueta")"
            [ -n "$et" ] || continue
            es="$(dato "libera.$c.estado")"
            case "$es" in
                "medido")
                    printf '<tr><th>%s</th><td>%s GB</td></tr>\n' "$(esc_html "$et")" "$(esc_html "$(dato "libera.$c.gb")")" ;;
                "medido en parte")
                    printf '<tr><th>%s</th><td>%s GB <span class="nose">como minimo: macOS no ha dejado medir %s carpeta(s) de dentro</span></td></tr>\n' \
                        "$(esc_html "$et")" "$(esc_html "$(dato "libera.$c.gb")")" "$(esc_html "$(dato "libera.$c.vetadas")")" ;;
                *)
                    printf '<tr><th>%s</th><td class="nose">%s</td></tr>\n' "$(esc_html "$et")" "$(esc_html "$es")" ;;
            esac
        done
        printf '</table>\n'
        printf '<p class="nota"><b>MacDiag todavia no borra nada.</b> Esta version solo mide, y es a proposito: el codigo que borra ficheros no se publica hasta haberlo ejecutado en varios Mac, y de momento solo se ha probado en uno.</p>\n'

        # --- Descargas, aparte y con su aviso -------------------------------
        _des="$(dato libera.descargas.estado)"
        if [ -n "$_des" ]; then
            printf '<h2>Tu carpeta de Descargas</h2>\n<table>\n'
            if [ "$_des" = "medido" ] || [ "$_des" = "medido en parte" ]; then
                printf '<tr><th>Ocupa</th><td>%s GB</td></tr>\n' "$(esc_html "$(dato libera.descargas.gb)")"
            else
                printf '<tr><th>Ocupa</th><td class="nose">%s</td></tr>\n' "$(esc_html "$_des")"
            fi
            printf '</table>\n'
            printf '<p class="nota">Va <b>aparte</b> y no cuenta como espacio liberable, a proposito: son ficheros tuyos y no basura del sistema. Suele ser de lo mas grande que se puede vaciar a mano, pero mirando antes lo que hay. Eso lo decides tu, no un programa.</p>\n'
        fi

        # --- Lo que no se ha podido mirar ------------------------------------
        printf '<h2>Lo que NO se ha podido comprobar</h2>\n'
        if [ -s "$NOPUDE" ]; then
            printf '<p class="nota">Esto no es una lista de fallos del Mac: es lo que MacDiag no ha llegado a ver. Callarselo seria decir que todo esta bien.</p>\n'
            while IFS=$'\t' read -r que porque; do
                [ -n "$que" ] || continue
                printf '<div class="h AVISO"><b>%s</b><p>%s</p></div>\n' "$(esc_html "$que")" "$(esc_html "$porque")"
            done < "$NOPUDE"
        else
            printf '<p class="nota">Nada: todas las comprobaciones se han podido hacer.</p>\n'
        fi

        # --- Los mandos ------------------------------------------------------
        printf '<h2>Los mandos que se han ejecutado</h2>\n'
        printf '<p class="nota">Todos son de solo lectura y ninguno necesita contraseña de administrador. Estan aqui para que se pueda comprobar que MacDiag no hace nada raro, y porque el codigo de salida dice donde arreglarlo.</p>\n'
        printf '<div class="tabla-scroll"><table>\n<tr><th>Mando</th><td><b>Codigo</b></td></tr>\n'
        while IFS=$'\t' read -r clave rc seg linea; do
            [ -n "$clave" ] || continue
            if [ "$rc" = "0" ]; then est="bien"; else est="codigo $rc"; fi
            printf '<tr><th><code>%s</code></th><td>%s, %ss</td></tr>\n' \
                "$(esc_html "$linea")" "$est" "$(esc_html "$seg")"
        done < "$CRUDO/_MANDOS.tsv"
        printf '</table></div>\n'

        printf '<footer>MacDiag %s &middot; %s &middot; tardo %s s &middot; carpeta: <code>%s</code></footer>\n' \
            "$(esc_html "$VERSION_MACDIAG")" "$(esc_html "$(dato meta.fecha)")" \
            "$(esc_html "$(dato meta.tardo_s)")" "$(esc_html "$(dato meta.carpeta)")"
        printf '</div></body></html>\n'
    } > "$salida"
}

# ---------------------------------------------------------------------------
# El JSON
#
# Aqui NO hay que respetar ningun esquema de nadie: MacDiag no sube a ninguna
# carpeta compartida y no tiene que encajar con PCDIAG. Es para que el propio
# historial pueda comparar una semana con otra.
# ---------------------------------------------------------------------------
escribir_json() {
    local salida="$1"
    {
        printf '{\n'
        printf '  "app": "MacDiag",\n'
        printf '  "version": "%s",\n' "$(esc_json "$VERSION_MACDIAG")"
        printf '  "probado_en_mac": true,\n'
        printf '  "probado_en": "iMac18,3 - macOS 13.7.8 - Intel x86_64",\n'
        printf '  "sin_probar_en": "Apple Silicon, portatiles con bateria",\n'
        printf '  "criticos": %s,\n' "$(cuantos_hallazgos CRITICO)"
        printf '  "avisos": %s,\n'   "$(cuantos_hallazgos AVISO)"

        printf '  "datos": {\n'
        local primera=1
        while IFS=$'\t' read -r k v; do
            [ -n "$k" ] || continue
            [ "$primera" -eq 1 ] || printf ',\n'
            printf '    "%s": "%s"' "$(esc_json "$k")" "$(esc_json "$v")"
            primera=0
        done < <(datos_ordenados)
        printf '\n  },\n'

        printf '  "hallazgos": [\n'
        primera=1
        if [ -s "$HALLAZGOS" ]; then
            while IFS=$'\t' read -r gr et ti de; do
                [ -n "$gr" ] || continue
                [ "$primera" -eq 1 ] || printf ',\n'
                printf '    { "gravedad": "%s", "etiqueta": "%s", "titulo": "%s", "detalle": "%s" }' \
                    "$(esc_json "$gr")" "$(esc_json "$et")" "$(esc_json "$ti")" "$(esc_json "$de")"
                primera=0
            done < "$HALLAZGOS"
        fi
        printf '\n  ],\n'

        printf '  "no_he_podido": [\n'
        primera=1
        if [ -s "$NOPUDE" ]; then
            while IFS=$'\t' read -r que porque; do
                [ -n "$que" ] || continue
                [ "$primera" -eq 1 ] || printf ',\n'
                printf '    { "que": "%s", "porque": "%s" }' "$(esc_json "$que")" "$(esc_json "$porque")"
                primera=0
            done < "$NOPUDE"
        fi
        printf '\n  ],\n'

        printf '  "mandos": [\n'
        primera=1
        while IFS=$'\t' read -r clave rc seg linea; do
            [ -n "$clave" ] || continue
            [ "$primera" -eq 1 ] || printf ',\n'
            printf '    { "clave": "%s", "codigo": %s, "segundos": %s, "mando": "%s" }' \
                "$(esc_json "$clave")" "${rc:-0}" "${seg:-0}" "$(esc_json "$linea")"
            primera=0
        done < "$CRUDO/_MANDOS.tsv"
        printf '\n  ]\n'
        printf '}\n'
    } > "$salida"
}

# ---------------------------------------------------------------------------
# El historial
#
# Una linea por ejecucion, en un fichero que solo crece. Sirve para lo unico
# que un informe suelto no puede decir: si esto va a mejor o a peor.
# ---------------------------------------------------------------------------
anotar_historial() {
    local fichero="$1"
    mkdir -p "$(dirname "$fichero")" 2>/dev/null
    # "liberable_gb" es SOLO lo que sobra de verdad. Si le sumara la carpeta de
    # Descargas, la serie del historial subiria y bajaria con lo que el usuario
    # se descarga, que no tiene nada que ver con si el Mac esta mejor o peor.
    # Descargas va en su propio campo para poder mirarla aparte.
    printf '{ "fecha": "%s", "version": "%s", "equipo": "%s", "criticos": %s, "avisos": %s, "disco_pct": "%s", "liberable_gb": "%s", "descargas_gb": "%s", "medida_incompleta": "%s", "carpeta": "%s" }\n' \
        "$(esc_json "$(dato meta.fecha)")" \
        "$(esc_json "$VERSION_MACDIAG")" \
        "$(esc_json "$(dato meta.equipo)")" \
        "$(cuantos_hallazgos CRITICO)" \
        "$(cuantos_hallazgos AVISO)" \
        "$(esc_json "$(dato disco.ocupado_pct)")" \
        "$(esc_json "$(dato libera.basura_gb)")" \
        "$(esc_json "$(dato libera.descargas.gb)")" \
        "$(esc_json "$(dato libera.incompleta)")" \
        "$(esc_json "$(dato meta.carpeta)")" \
        >> "$fichero"
}
