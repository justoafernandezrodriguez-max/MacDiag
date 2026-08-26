#!/bin/bash
# ---------------------------------------------------------------------------
#  MacDiag - el menu
#
#  Esto es lo unico que toca un usuario: doble clic y elegir.
#
#  Es a proposito lo mas tonto del proyecto. Todo el trabajo esta en los
#  motores, que se pueden lanzar solos desde la Terminal; esto solo los llama.
#  Asi, el dia que MacDiag tenga una ventana de verdad, se cambia esta pieza y
#  el diagnostico no se toca. Al reves no funciona.
#
#  OJO: ESCRITO SIN PODER PROBARLO EN NINGUN MAC. Ver LEEME.txt.
# ---------------------------------------------------------------------------

AQUI="$(cd "$(dirname "$0")" && pwd)"
BASE="$HOME/MacDiag"

# --- Antes de nada, que este todo -------------------------------------------
for f in lib-comun.sh lib-informe.sh macdiag-estado.sh; do
    if [ ! -f "$AQUI/$f" ]; then
        echo "Falta $f al lado de MacDiag.command. Copia la carpeta entera, no solo este fichero."
        read -r _ 2>/dev/null
        exit 1
    fi
done

# --- Los finales de linea de Windows -----------------------------------------
#
# MacDiag se escribio en un PC. Si los ficheros llegan con finales de linea de
# Windows, bash falla con mensajes incomprensibles del tipo "$'\r': command not
# found". Se comprueba y se dice como arreglarlo, porque el mensaje de bash no
# ayuda nada.
# El retorno de carro se saca con printf y no con $'\r'. Los dos son bash
# correcto, pero el segundo depende de como llegue el fichero hasta aqui, y
# comprobarlo mal tiene un precio muy alto: si diera positivo siempre, MacDiag
# se negaria a arrancar en todos los Mac por un problema que no existe. La
# forma con printf se ha podido probar; la otra no.
CR="$(printf '\r')"
if LC_ALL=C grep -q "$CR" "$AQUI/lib-comun.sh" "$AQUI/lib-informe.sh" "$AQUI/macdiag-estado.sh" 2>/dev/null; then
    echo
    echo "  Estos ficheros tienen finales de linea de Windows y bash no los va a poder leer."
    echo "  Se arregla con esta linea, copiada tal cual en la Terminal:"
    echo
    echo "      cd \"$AQUI\" && perl -pi -e 's/\\r\$//' *.sh *.command"
    echo
    read -r _ 2>/dev/null
    exit 1
fi

. "$AQUI/lib-comun.sh"

ultimo_informe() {
    ls -1dt "$BASE"/INFORMES/*/ 2>/dev/null | head -1
}

while true; do
    printf '\n'
    printf '  %sMacDiag %s%s\n' "$_C_FUERTE" "$VERSION_MACDIAG" "$_C_FIN"
    printf '  %sVersion sin probar en ningun Mac. De momento solo mira: no borra nada.%s\n\n' "$_C_GRIS" "$_C_FIN"
    printf '    1  Mirar como esta este Mac\n'
    printf '    2  Abrir el ultimo informe\n'
    printf '    3  Ver el historial\n'
    printf '    4  Abrir la carpeta de MacDiag\n'
    printf '\n'
    printf '    %s-  Limpiar y liberar espacio: todavia no. El informe te dice cuanto hay%s\n' "$_C_GRIS" "$_C_FIN"
    printf '    %s   y donde, pero borrar no se activa hasta poder probarlo en un Mac.%s\n' "$_C_GRIS" "$_C_FIN"
    printf '\n'
    printf '    0  Salir\n\n'
    printf '  Elige: '
    read -r opcion

    case "$opcion" in
        1)
            bash "$AQUI/macdiag-estado.sh"
            printf '\n  Pulsa Intro para volver al menu. '
            read -r _
            ;;
        2)
            carpeta="$(ultimo_informe)"
            if [ -n "$carpeta" ] && [ -f "${carpeta}informe.html" ]; then
                open "${carpeta}informe.html" 2>/dev/null || echo "  Abrelo a mano: ${carpeta}informe.html"
            else
                echo "  Todavia no hay ningun informe. Elige la opcion 1."
            fi
            ;;
        3)
            if [ -f "$BASE/historial.jsonl" ]; then
                printf '\n'
                tail -20 "$BASE/historial.jsonl"
                printf '\n  Pulsa Intro. '
                read -r _
            else
                echo "  Todavia no hay historial: se escribe la primera vez que se mira el equipo."
            fi
            ;;
        4)
            mkdir -p "$BASE" 2>/dev/null
            open "$BASE" 2>/dev/null || echo "  Esta en $BASE"
            ;;
        0|q|Q|"")
            printf '\n'
            exit 0
            ;;
        *)
            echo "  No entiendo esa opcion."
            ;;
    esac
done
