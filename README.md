# MacDiag

Una aplicación suelta que dice cómo está un Mac y le hace el mantenimiento
razonable, dejando un informe y un historial. Para cualquier Mac: el portátil
de alguien, el de la oficina, el de casa.

Desde la 0.3.0 tiene **ventana propia**: se abre con doble clic y tiene tres
secciones — estado del equipo, mantenimiento e informes — con sus botones.

No hace falta instalar nada de fuera. Los motores son scripts de `bash`, que es
lo que ya trae macOS, y la ventana se compila con el `swiftc` de las Command
Line Tools (`bash ventana/construir.sh`). Sin Xcode.

**La ventana no es un motor nuevo:** lanza los mismos scripts y lee el mismo
JSON, así que todo sigue funcionando desde la Terminal igual que antes.

---

## ⚠ La 0.2.0 ya se ha ejecutado en un Mac. En uno

Probada el 26-ago-2026 en un **iMac18,3 con macOS 13.7.8 (Intel)**: terminó
entera en 25 segundos, con 37 de 39 mandos correctos, y los cuatro fallos de
lectura que aparecieron están corregidos.

**Sigue sin probarse en un Mac con chip de Apple (M1 y siguientes) y en un
portátil.** Eso segundo importa más de lo que parece: un sobremesa no tiene
batería, así que **todo el bloque de la batería —la función más útil que tiene
esta aplicación— no se ha llegado a ejecutar ni una vez.**

**Lo que no puede pasar es que estropee nada: esta versión sólo lee.** No borra,
no mueve, no cambia ningún ajuste y no pide contraseña de administrador. Los
mandos que ejecuta salen todos listados al final del propio informe.

Si la pruebas en un portátil o en un Apple Silicon, mira
[qué devolver](#si-la-pruebas-qué-hace-falta-de-vuelta).

---

## Esto NO es PCDIAG

Son dos aplicaciones distintas y no comparten ni una línea de código.

|  | PCDIAG | MacDiag |
|---|---|---|
| Para qué | los PCs de producción de un plató | cualquier Mac, sin más |
| Cómo | PowerShell y Windows Forms | `bash` y un informe en HTML |
| Se analiza solo | sí, cada sábado | no |
| Manda correo | sí, los domingos | no |
| Sube a una carpeta compartida | sí | no |
| Hay que configurarlo | sí, un kit por equipo | no, nada |

MacDiag no sube nada a ningún sitio, no manda nada por internet y no necesita
red. Todo se queda en la carpeta de inicio del propio usuario.

---

## Cómo se lanza

1. Baja el zip de la [última versión](../../releases/latest) y descomprímelo, o
   clona este repositorio.

2. Abre la Terminal (Aplicaciones → Utilidades → Terminal), escribe `bash`, un
   espacio, y **arrastra `MacDiag.command` a la ventana**: la ruta se escribe
   sola. Queda algo así:

   ```
   bash /Users/tu/Desktop/MacDiag/MacDiag.command
   ```

   Se lanza así y no con doble clic a propósito, porque resuelve dos cosas de
   golpe: los ficheros llegan sin permiso de ejecución, y lo que se descarga de
   internet queda marcado en cuarentena y macOS se niega a abrirlo desde el
   Finder. Lanzándolo con `bash` no pasa por ninguna de las dos.

3. Elige la opción **1**. Tarda entre uno y tres minutos.

Si algún día lo quieres con doble clic, entonces sí hacen falta las dos cosas:

```
chmod +x "/ruta/MacDiag/MacDiag.command"
xattr -dr com.apple.quarantine "/ruta/MacDiag"
```

---

## Qué mira

- Modelo, chip, memoria y versión de macOS
- Disco: cuánto hay, cuánto queda y qué dice el SMART del propio disco
- Batería: carga, ciclos y si el sistema la da por gastada
- FileVault, SIP y Gatekeeper
- Reinicios por fallo del sistema y cierres inesperados de aplicaciones
- Qué se abre solo al arrancar
- Time Machine y actualizaciones pendientes
- Cuánto espacio se podría liberar, y dónde está

Todo lo que **no** haya podido comprobar sale en su propio apartado del informe,
con el motivo. Nunca dice que algo está bien cuando lo que pasa es que no ha
podido mirarlo — en macOS eso ocurre a menudo, porque hay carpetas que necesitan
permisos que no merece la pena dar sólo para esto.

## Qué NO hace, y no es que falte

- **No borra nada.** Mide cuánto se podría liberar y dónde está, y ahí se para.
  El código que borra ficheros no se publica sin haberse ejecutado antes en un
  Mac de verdad.
- **No «repara permisos».** Eso desapareció de macOS en 2015; cualquier programa
  que hoy lo ofrezca está fingiendo.
- **No libera memoria RAM.** La memoria que macOS tiene en caché es memoria bien
  usada, y vaciarla hace que el equipo vaya peor el rato siguiente.
- **No toca nada del sistema.** Desde Big Sur el volumen del sistema va sellado
  y verificado: si se rompe, lo que toca es reinstalar macOS. No existe aquí
  nada parecido al `sfc` o al `DISM` de Windows.

---

## Si la pruebas, qué hace falta de vuelta

La carpeta entera de esta ejecución:

```
~/MacDiag/INFORMES/<la fecha de hoy>/
```

Dentro va el informe, lo que la aplicación entendió, y sobre todo `crudo/`, con
la salida original de cada mando. **Esa carpeta es lo que permite corregir la
lectura con datos reales sin volver a molestarte.** El número de serie y el UUID
del equipo se tapan solos antes de guardar nada.

Y si falla del todo y no llega ni a empezar, con copiar lo que salga en la
Terminal es suficiente.

---

## Para quien vaya a tocar el código

Empieza por **[docs/1.0-ESTADO.md](docs/1.0-ESTADO.md)**, que es el punto de
retomada: qué está decidido, qué está comprobado y qué no, y las trece trampas
de macOS ya anotadas.

```
app/MacDiag.command      el menú, lo único que toca el usuario
app/macdiag-estado.sh    el motor: mira el Mac y escribe el informe
app/lib-comun.sh         capturar mandos, el almacén de datos, los escapes
app/lib-informe.sh       el HTML y el JSON
build/probar-lectura.sh  50 pruebas de la lectura, que sí se han ejecutado
```

Dos cosas que conviene entender antes de cambiar nada:

- **Cada mando se guarda en crudo antes de interpretarlo.** El informe se saca
  de esos ficheros, no del mando directo. Por eso se puede arreglar la lectura
  con la salida real de otro equipo sin tenerlo delante.
- **Los motores están separados de la interfaz.** El día que MacDiag tenga una
  ventana nativa, se escribe la ventana y el diagnóstico no se toca.

Las pruebas se lanzan así, y funcionan en cualquier sitio con `bash`, también
en Windows:

```
bash build/probar-lectura.sh
```
