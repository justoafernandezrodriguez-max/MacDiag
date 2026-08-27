#!/bin/bash
# ---------------------------------------------------------------------------
#  MacDiag - construir la ventana
#
#  Hace MacDiag.app con swiftc, SIN Xcode. Solo hacen falta las Command Line
#  Tools, que es lo que ya trae cualquier Mac donde se haya escrito una linea
#  de codigo. El documento del proyecto daba esto por imposible ("Swift arrastra
#  Xcode"); con swiftc suelto no lo arrastra.
#
#      bash ventana/construir.sh              <- para trabajar (enlaza al repo)
#      bash ventana/construir.sh --distribuir <- copia los scripts dentro
#
#  La diferencia importa: enlazado, cualquier cambio en los scripts se nota sin
#  recompilar. Copiado, la .app se puede llevar a otro Mac entera.
# ---------------------------------------------------------------------------

set -u
export LC_ALL=C

AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$AQUI/.." && pwd)"
FUENTES="$AQUI/Fuentes"
DESTINO="$RAIZ/MacDiag.app"
VERSION="$(grep -E '^VERSION_MACDIAG=' "$RAIZ/app/lib-comun.sh" | cut -d'"' -f2)"
MODO="desarrollo"
[ "${1:-}" = "--distribuir" ] && MODO="distribuir"

echo
echo "  MacDiag $VERSION - construyendo la ventana ($MODO)"
echo

# --- Que estan las herramientas, y que RESPONDEN ---------------------------
# No se pregunta si swiftc esta: se le pide la version. Es la trampa 11 del
# proyecto, que ya ha mordido dos veces.
if ! swiftc --version >/dev/null 2>&1; then
    echo "  No hay un swiftc que funcione."
    echo "  Se instala con:  xcode-select --install"
    echo "  (son las Command Line Tools, no el Xcode entero)"
    exit 1
fi
echo "  swiftc: $(swiftc --version 2>&1 | head -1)"

rm -rf "$DESTINO"
mkdir -p "$DESTINO/Contents/MacOS" "$DESTINO/Contents/Resources"

# --- Compilar ---------------------------------------------------------------
# Se intenta universal (Intel + Apple Silicon) para que la misma .app sirva en
# los dos. Si el SDK de este Mac no puede con la otra arquitectura, se sigue
# con la de aqui y se DICE, en vez de dejar creer que vale para todos.
TMP="$(mktemp -d)"
SWIFTS=("$FUENTES"/*.swift)
COMUN=(-parse-as-library -O -swift-version 5)

compila_para() {  # arquitectura  salida
    swiftc "${COMUN[@]}" -target "$1-apple-macos13.0" -o "$2" "${SWIFTS[@]}" 2>"$TMP/err-$1"
}

UNIVERSAL="no"
if compila_para x86_64 "$TMP/mac-x86_64"; then
    if compila_para arm64 "$TMP/mac-arm64" 2>/dev/null; then
        lipo -create -output "$DESTINO/Contents/MacOS/MacDiag" "$TMP/mac-x86_64" "$TMP/mac-arm64" 2>/dev/null \
            && UNIVERSAL="si"
    fi
    if [ "$UNIVERSAL" = "no" ]; then
        cp "$TMP/mac-x86_64" "$DESTINO/Contents/MacOS/MacDiag"
    fi
else
    echo "  NO COMPILA. Lo que dice swiftc:"
    echo
    sed 's/^/      /' "$TMP/err-x86_64" | head -40
    rm -rf "$TMP"
    exit 1
fi
chmod +x "$DESTINO/Contents/MacOS/MacDiag"

# --- El Info.plist ----------------------------------------------------------
cat > "$DESTINO/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>MacDiag</string>
    <key>CFBundleDisplayName</key>       <string>MacDiag</string>
    <key>CFBundleExecutable</key>        <string>MacDiag</string>
    <key>CFBundleIdentifier</key>        <string>es.justo.macdiag</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>CFBundleIconFile</key>          <string>MacDiag</string>
</dict>
</plist>
PLIST

# --- El icono ---------------------------------------------------------------
#
# Se DIBUJA, no se guarda: icono/DibujarIcono.swift lo pinta con CoreGraphics y
# iconutil lo empaqueta. Asi el icono se cambia tocando cuatro numeros y no hay
# que meter un binario en el repositorio ni abrir ningun programa de dibujo.
ICONO="$AQUI/icono"
if [ -f "$ICONO/DibujarIcono.swift" ]; then
    if [ ! -f "$ICONO/MacDiag.icns" ] || [ "$ICONO/DibujarIcono.swift" -nt "$ICONO/MacDiag.icns" ]; then
        ( cd "$ICONO" \
          && swiftc -O -o dibujar DibujarIcono.swift 2>/dev/null \
          && ./dibujar ./MacDiag.iconset >/dev/null 2>&1 \
          && iconutil -c icns MacDiag.iconset -o MacDiag.icns 2>/dev/null )
    fi
    if [ -f "$ICONO/MacDiag.icns" ]; then
        cp "$ICONO/MacDiag.icns" "$DESTINO/Contents/Resources/MacDiag.icns"
        echo "  Icono: la D azul"
    else
        echo "  OJO: no se ha podido generar el icono; la .app saldra con el generico."
    fi
fi

# --- Los scripts, que son el motor de verdad --------------------------------
if [ "$MODO" = "distribuir" ]; then
    mkdir -p "$DESTINO/Contents/Resources/app"
    cp "$RAIZ/app/"*.sh "$RAIZ/app/"*.command "$RAIZ/app/LEEME.txt" "$DESTINO/Contents/Resources/app/" 2>/dev/null
    echo "  Scripts: copiados dentro de la .app (se puede llevar a otro Mac)"
else
    ln -s "$RAIZ/app" "$DESTINO/Contents/Resources/app"
    echo "  Scripts: enlazados a $RAIZ/app (los cambios se notan sin recompilar)"
fi

# --- Firmar, y esto NO es opcional -----------------------------------------
#
# Se pago aqui: sin firma, macOS lanza el proceso -sale hasta en la barra de
# menu- pero SwiftUI no llega a presentar la ventana. No hay error, no hay
# aviso: hay una aplicacion que "se abre" y no se ve. Es la trampa 2 del
# proyecto con otro traje: el fallo que no da error.
#
# La firma ad-hoc (-s -) no necesita cuenta de desarrollador ni certificado.
if ! codesign --force --deep --sign - "$DESTINO" 2>/dev/null; then
    echo "  OJO: no se ha podido firmar. La ventana puede no llegar a verse."
else
    echo "  Firma: ad-hoc (sin ella la ventana no aparece)"
fi

rm -rf "$TMP"

echo "  Arquitectura: $(lipo -archs "$DESTINO/Contents/MacOS/MacDiag" 2>/dev/null || echo desconocida)"
[ "$UNIVERSAL" = "no" ] && echo "  OJO: solo para esta arquitectura, no universal."
echo
echo "  Hecho:  $DESTINO"
echo
