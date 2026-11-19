# Audio y Bluetooth: decisiones y cosas ya probadas

Notas personales de lo que se probó en la PC principal para el problema de "cuando conecto los auriculares
Bluetooth, Windows hace cosas raras". No es código: es memoria de decisiones para no repetir pruebas fallidas.

## El problema

Al conectar auriculares/ manos libres Bluetooth:

1. Windows muestra el aviso de conexión en el monitor **primario**, que no es el que se está mirando.
2. Hay que cambiarse de pantalla, hacer clic, y volver.
3. A veces el audio no pasa solo al dispositivo nuevo, o pasa en calidad de llamada.

## Causa raíz: el perfil Hands-Free (HFP)

Los auriculares Bluetooth registran **dos** endpoints de audio:

| Endpoint                    | Para qué sirve         | Calidad    |
| --------------------------- | ---------------------- | ---------- |
| `Hands-Free` (manos libres) | Micrófono / llamadas   | Baja, mono |
| A2DP (estéreo)              | Reproducción de música | Alta       |

Ejemplo real en esta PC: `Headset (<modelo> Hands-Free)` junto a su par `Headphones (<modelo> Stereo)`.

Windows puede conectar el perfil Hands-Free y dejar el estéreo de lado, o cambiar el dispositivo
por defecto a mitad de sesión.

### Solución aplicada (2026-11): desactivar el servicio de manos libres

**Panel de control → Dispositivos e impresoras → clic derecho en los auriculares → Propiedades →
pestaña Servicios → destildar "Manos libres Telephony" (Hands-free Telephony).**

Efecto: queda solo el endpoint A2DP. Windows ya no tiene a qué cambiarse y el audio sale siempre en estéreo.

> **Estado: aplicado y en observación.** Si en algún momento hace falta usar el micrófono de los
> auriculares para llamadas, hay que volver a tildarlo.

## Evidencia: qué dice el registro de eventos

Revisado el 2026-11-16 sobre el log `System`, que cubre desde 2026-04-08 (todo el período en que se usó
SoundSwitch la primera vez):

| Chequeo                                          | Resultado |
| ------------------------------------------------ | --------- |
| `TDR` / evento 4101 (driver de video reseteado)  | 0 eventos |
| Reinicios de `Audiosrv` / `AudioEndpointBuilder` | 0 eventos |
| Crashes de SoundSwitch en el log `Application`   | 0 eventos |

El parpadeo **no dejó ninguna huella en el log**. Eso descarta las explicaciones "graves": el driver de video
nunca se cayó y los servicios de audio nunca se reiniciaron. Si "todos los dispositivos dejaran de funcionar
de golpe" fuera real a nivel driver, habría un 4101 sí o sí.

**Hipótesis corregida (la anterior era incorrecta):** no es re-enumeración de endpoints arrastrando al driver
de video. Es un problema de **composición de pantalla**: el banner de notificación de SoundSwitch es una
ventana always-on-top translúcida, y dibujarla sobre un juego en fullscreen exclusivo provoca parpadeo y
hitch en DWM. Es el único componente que se puede apagar sin perder nada útil.

## Herramientas evaluadas

### SoundSwitch (`AntoineAflalo.SoundSwitch`) — reintento en curso (2026-11)

Lo que ofrece y por qué sigue siendo la mejor opción en features:

- Perfiles con triggers, incluido **Device Changed Trigger** (mantener el dispositivo aunque Windows lo cambie).
- Triggers por aplicación y por ventana (rutear Spotify a parlantes y juegos al headset).
- Hotkeys, tray, CLI, cambio de dispositivo Multimedia **y** Communications.
- Proyecto maduro: 3.5k estrellas, 95 contribuidores, GPL-3.0, en Winget.

**Primer intento (2026-10/11): descartado.** Al cambiar de dispositivo, sobre todo a mitad de un juego, la PC
parpadeaba como si se reiniciaran todos los dispositivos y quedaba trabada un momento.

**Motivo del reintento:** la evidencia del log (ver arriba) indica que el problema es el overlay y no el audio,
y el overlay se puede desactivar. Si con la configuración de mínimo riesgo no vuelve a pasar, se queda.
El protocolo completo está más abajo: [Protocolo de reintento](#protocolo-de-reintento-de-soundswitch).

### AudioSwitcher (`FortyOneLtd.AudioSwitcher`) — herramienta actual y red de seguridad

Portable, Ms-PL, de 2018 y sin mantenimiento, pero **funciona y no cuelga nada**. Hace exactamente lo que
hace falta para el problema real: elegir salida **y entrada** con hotkeys por dispositivo (no ciclado) y un
icono en la bandeja.

Está en Winget y es **el mismo binario** que se venía usando a mano (`1.8.0.142`, Forty One Ltd.). El paquete
es de tipo `portable`, así que se instala en `%LOCALAPPDATA%\Microsoft\WinGet\Packages\...` en vez de
`Downloads`, que era una ruta no portable.

No tiene reglas automáticas ni perfiles. Es el plan B si SoundSwitch falla otra vez.

> Si se queda SoundSwitch, AudioSwitcher se desinstala (o se deja dormido sin autostart) para no tener dos
> switchers peleando por el mismo default device.

### Wisp — parcialmente útil

El dock de Wisp puede mostrar `bluetooth` y `sound` como secciones de estado, y el launcher tiene comandos
`bt` (dispositivos pareados), `wifi`, `vol`, y el panel `Now`. Sirve para conectar/ver desde el monitor donde
está el mouse, sin depender del toast. **No reemplaza un switcher**: no maneja la entrada del micrófono.

### Windhawk `notifications-placement` — la única solución al monitor del toast

Mod de `m417z` (autor de Windhawk), incluido en Windhawk. Con `monitor = 0` mueve **todos los toasts**
(incluido el de Bluetooth conectado) al monitor donde está el cursor.

Actualmente el módulo Windhawk del repo está pausado porque Wisp reemplazó la taskbar, pero este mod es
independiente de la taskbar y sigue funcionando con Wisp: inyecta sólo en `explorer.exe` y
`ShellExperienceHost.exe`.

Windows no tiene ningún setting ni API pública para elegir el monitor de las notificaciones. Las alternativas
reales son este mod, o marcar como principal el monitor que se usa.

## Protocolo de reintento de SoundSwitch

### Paso 0 — Red de seguridad, antes de instalar nada

```powershell
winget install --id FortyOneLtd.AudioSwitcher -e
```

Así nunca se queda sin herramienta para salida/entrada. SoundSwitch se instala después.

### Paso 1 — Configuración de mínimo riesgo

| Ajuste                         | Valor              | Por qué                                |
| ------------------------------ | ------------------ | -------------------------------------- |
| **Notifications**              | **Sound only**     | Sospechoso #1: el banner es el overlay |
| Communication device switching | OFF                | Dispara callbacks a Discord y juegos   |
| Device Changed Triggers        | OFF                | Watchdog que pelea con Windows         |
| App / Window triggers          | OFF                | Loops de monitoreo de foco             |
| Auto-updater                   | Notify             | Que no se actualice a mitad del test   |
| Perfiles                       | Uno, solo playback | Menos superficie                       |

### Paso 2 — Escalera de pruebas y criterio de corte

| Fase | Qué se hace                                                   | Si falla                                    |
| ---- | ------------------------------------------------------------- | ------------------------------------------- |
| A    | 15 min: 30 cambios de dispositivo seguidos, en escritorio     | Es el cambio en sí → abandonar              |
| B    | 1 día de uso normal, sin juegos                               | Es del uso diario → abandonar               |
| C    | Una sesión de juego con un cambio en el medio                 | Vuelve el blink → abandonar definitivamente |
| D    | Opcional: habilitar **un** trigger (device changed, 1 device) | Rompe → volver a config de C                |

La fase A es la clave: separa "cambiar el dispositivo rompe algo" de "el overlay rompe algo".

### Paso 3 — Diagnóstico si explota (30 segundos)

```powershell
# ¿se cayó el driver de video?
Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101} -MaxEvents 5

# ¿se reiniciaron los servicios de audio?
Get-WinEvent -LogName System -MaxEvents 300 | Where-Object Message -match 'Audiosrv|AudioEndpointBuilder'
```

| Resultado              | Conclusión                                  |
| ---------------------- | ------------------------------------------- |
| Evento 4101            | Overlay vs fullscreen → culpable el banner  |
| Reinicio de `Audiosrv` | Problema de la API de cambio de dispositivo |
| Nada (como la 1ª vez)  | DWM / compositor → otra vez el banner       |

### Paso 4 — Kill switch

SoundSwitch no instala driver, así que matarlo es seguro:

```powershell
Stop-Process -Name SoundSwitch -Force
Restart-Service Audiosrv, AudioEndpointBuilder -Force   # sólo si el audio quedó mudo
```

No hace falta reiniciar la PC ni desinstalar de urgencia.

### Estado del reintento (2026-11-16)

Hecho:

1. `winget install --id FortyOneLtd.AudioSwitcher -e` → red de seguridad instalada.
2. `winget install --id AntoineAflalo.SoundSwitch -e` → 7.4.1 instalado.
3. Notificaciones cambiadas de banner a **solo sonido**.

Detalle técnico útil: el enum `NotificationType` del proyecto es
`DefaultWindowsNotification = 0`, `SoundNotification = 1`, `NoNotification = 2`,
`CustomNotification = 3` (retirado), `ToastNotification = 4` (retirado), `BannerNotification = 5`.
El valor por defecto era **5 (banner)**. Se editó
`%APPDATA%\SoundSwitch\SoundSwitchConfiguration.json` con la app **cerrada** (si está abierta pisa el archivo
al salir, misma trampa que Windhawk y Wisp):

| Campo                        | Antes | Ahora | Significado |
| ---------------------------- | ----- | ----- | ----------- |
| `SwitchDeviceNotification`   | 5     | **1** | Solo sonido |
| `SwitchProfileNotification`  | 5     | **1** | Solo sonido |
| `MicrophoneMuteNotification` | 5     | **1** | Solo sonido |

`ChangeCommunications` y `SwitchForegroundProgram` ya estaban en `false`, y no hay perfiles ni reglas por app.

Actualización (2026-11-18):

- Onboarding completado (`FirstRun = false`).
- **AudioSwitcher desinstalado**: ya no hay dos switchers compitiendo por el dispositivo por defecto.
- **SoundSwitch no tiene autostart configurado** (ni clave `Run` ni carpeta Startup). Para que la prueba sea
  real hay que activar _Start automatically with Windows_ en su configuración; si no, tras reiniciar no está
  corriendo y "parece que funciona" justamente porque no está.
- Primeras impresiones del uso diario: **sin parpadeos**. Sin banner, el overlay que se sospechaba como causa
  ya no existe.

**Falta**: correr la escalera de pruebas (fase A: 30 cambios seguidos en escritorio; fase C: una sesión de
juego con un cambio en el medio). El veredicto se escribe acá cuando esté.

### Los auriculares piden emparejarse cada vez (BTHUSB Event ID 16)

Síntoma: al conectar aparecen tres pantallas seguidas — "Add a device · Tap to set up your <modelo>",
"Pair device? · would like to pair to this Windows device. Do you want to allow this?" y
"<modelo> · Connection succeeded". O sea **pide pairing, no conexión**: el dispositivo cree que no está
vinculado.

Lo que se verificó en esta PC (2026-11-19):

| Chequeo | Resultado |
| ------- | --------- |
| Vínculo en la PC (`BTHPORT\...\Devices\<MAC>`) | **Existe** → no se borra de este lado |
| `LastConnected` del dispositivo | 2 días antes de la última conexión real → las conexiones nuevas **no** se registran como conexión de un dispositivo emparejado |
| Perfiles PnP (A2DP, AVRCP, HFP) | Todos `OK` cuando está conectado |
| **Log `System`, proveedor `BTHUSB`, Event ID 16** | **"The mutual authentication between the local Bluetooth adapter and a device … failed"** (varias veces el mismo día) |
| Adaptadores presentes | **Dos**: Realtek BT 5.0 USB (`VID_0BDA&PID_8771`, OK) e Intel Wireless BT (`CM_PROB_DISABLED`, Code 22) |
| Dueño del vínculo | `ServicesFor00e04c239987` = serial del **Realtek** (el Intel está deshabilitado, no participa) |
| Ahorro de energía del adaptador | **Ya desactivado** (`MSPower_DeviceEnable = False`) → no es eso |
| **Driver del adaptador** | **Realtek 1.6.1015.3018, del 2021-03-31** ← sospechoso principal |

Diagnóstico: la clave de enlace guardada **no coincide** con la del auricular, la autenticación mutua falla
(evento 16) y el dispositivo vuelve a modo emparejamiento. Con un driver de 2021 en un dongle Realtek, la
pérdida/corrupción de claves es un problema conocido.

> **Efecto colateral importante:** cada re-emparejamiento reinstala los servicios del dispositivo, así que el
> tilde de "Manos libres Telephony" **se vuelve a activar solo**. Eso explica por qué los perfiles Hands-Free
> aparecían `OK` sin que se los hubiera reactivado a mano. Mientras dure el ciclo de re-emparejamiento, ese
> ajuste no se sostiene.

Plan, en orden:

1. **Actualizar el driver del adaptador** — Configuración → Windows Update → Actualizaciones opcionales →
   Controladores. Si no aparece nada, buscar el driver Realtek del chip del dongle.
2. **Alternativa mejor:** probar el adaptador **Intel** de la mother (está deshabilitado). Si tiene antena
   conectada es un radio mejor y con driver actual.
3. **Re-emparejar limpio una vez** después del cambio de driver, y volver a destildar Hands-free.
4. Si el evento 16 vuelve con driver nuevo, el problema es el dongle → reemplazarlo.

## Resumen de estado

| Problema                             | Solución                                                   | Estado                      |
| ------------------------------------ | ---------------------------------------------------------- | --------------------------- |
| Perfil Hands-Free agarra el audio    | Destildar "Manos libres Telephony"                         | ✅ aplicado, en observación |
| Elegir salida/entrada rápido         | SoundSwitch (en reintento) o AudioSwitcher (red)           | 🔄 reintento en curso       |
| Dispositivo de audio incorrecto      | Sin automatización por ahora; el toggle HFP ataca la causa | ⏸ pendiente                 |
| Toasts en el monitor equivocado      | Windhawk `notifications-placement`, `monitor = 0`          | ✅ disponible               |
| Ver/conectar desde el monitor activo | Dock de Wisp (`bt`, panel `Now`)                           | ✅ disponible               |

## Otras cosas vistas en el log (no relacionadas, pero para no perderlas)

- `Explorer.EXE` crasheó el 2026-11-15 17:41 y el 2026-11-16 11:30, coincidiendo con la llegada de Wisp.
  Wisp oculta la taskbar creando su propio `Shell_TrayWnd`; si los crashes se repiten, es el primer sospechoso.
- `ssn.exe` (Simple Sticky Notes) se cae seguido. App inestable, no es un problema del setup.
