# Audio y Bluetooth: decisiones y cosas ya probadas

Notas personales de lo que se probó en la PC principal para el problema de "cuando conecto los auriculares
Bluetooth, Windows hace cosas raras". No es código: es memoria de decisiones para no repetir pruebas fallidas.

## El problema

Al conectar auriculares/ manos libres Bluetooth:

1. Windows muestra el aviso de conexión en el monitor **primario**, que no es el que se está mirando.
2. Hay que cambiarse de pantalla, hacer clic, y volver.
3. A veces el audio no pasa solo al dispositivo nuevo, o pasa en calidad de llamada.

## Los dos perfiles del auricular (Hands-Free y A2DP)

Los auriculares Bluetooth registran **dos** endpoints de audio:

| Endpoint                    | Para qué sirve         | Calidad    |
| --------------------------- | ---------------------- | ---------- |
| `Hands-Free` (manos libres) | Micrófono / llamadas   | Baja, mono |
| A2DP (estéreo)              | Reproducción de música | Alta       |

Ejemplo real en esta PC (REDMI Buds 8 Active): `Headset (REDMI Buds 8 Active Hands-Free)` junto a su par
`Headphones (REDMI Buds 8 Active)`.

Windows puede conectar el perfil Hands-Free y dejar el estéreo de lado, o cambiar el dispositivo
por defecto a mitad de sesión.

### Solución intentada (2026-11): desactivar el servicio de manos libres

**Panel de control → Dispositivos e impresoras → clic derecho en los auriculares → Propiedades →
pestaña Servicios → destildar "Manos libres Telephony" (Hands-free Telephony).**

Efecto buscado: queda solo el endpoint A2DP, Windows no tiene a qué cambiarse y el audio sale siempre en
estéreo.

> **Estado real (2026-11-20): quedó sin efecto y NO hace falta.** Cada re-emparejamiento reinstala los
> servicios del dispositivo, así que el tilde se reactiva solo. Y el estado que hoy funciona —los auriculares
> conectan al instante y los tres endpoints están `OK`— tiene Hands-free **habilitado**. Conclusión: HFP no
> era el culpable del audio. No volver a destildarlo sin motivo; solo desordena el diagnóstico.
>
> **Corrección (2026-11-23):** esa conclusión vale sólo para el **parpadeo/trabado** de SoundSwitch. Para
> **calidad de sonido** HFP sí es el culpable: mientras el micrófono de los auriculares esté en uso, Windows
> abandona A2DP y el audio sale mono. Ver
> [Calidad pésima con los REDMI Buds 8 Active](#calidad-pésima-con-los-redmi-buds-8-active-2026-11-23).

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

### SoundSwitch (`AntoineAflalo.SoundSwitch`) — adoptado (2026-11-26)

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

### Wisp — parcialmente útil

El dock de Wisp puede mostrar `bluetooth` y `sound` como secciones de estado, y el launcher tiene comandos
`bt` (dispositivos pareados), `wifi`, `vol`, y el panel `Now`. Sirve para conectar/ver desde el monitor donde
está el mouse, sin depender del toast. **No reemplaza un switcher**: no maneja la entrada del micrófono.

> **Monitor del toast (2026-11-26).** Windows no tiene setting ni API pública para elegir en qué monitor
> aparecen las notificaciones. La vía que existía (un mod de terceros) se descartó junto con el resto de esas
> herramientas; lo que queda es hacer principal el monitor que se está usando (`Toggle-Display.cmd`).

## Protocolo de reintento de SoundSwitch

### Paso 0 — Red de seguridad (retirado)

En su momento se instaló un switcher alternativo como red, para no quedarse sin herramienta si SoundSwitch
fallaba. **Ya no existe**: SoundSwitch es el único, está en `apps/winget-apps.txt` y el alternativo pasó a
`apps/winget-remove.txt`, así que una máquina nueva arranca con la herramienta buena y sin plan B.

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

1. `winget install --id AntoineAflalo.SoundSwitch -e` → 7.4.1 instalado.
2. Notificaciones cambiadas de banner a **solo sonido**.

Detalle técnico útil: el enum `NotificationType` del proyecto es
`DefaultWindowsNotification = 0`, `SoundNotification = 1`, `NoNotification = 2`,
`CustomNotification = 3` (retirado), `ToastNotification = 4` (retirado), `BannerNotification = 5`.
El valor por defecto era **5 (banner)**. Se editó
`%APPDATA%\SoundSwitch\SoundSwitchConfiguration.json` con la app **cerrada** (si está abierta pisa el archivo
al salir, misma trampa que Wisp):

| Campo                        | Antes | Ahora | Significado |
| ---------------------------- | ----- | ----- | ----------- |
| `SwitchDeviceNotification`   | 5     | **1** | Solo sonido |
| `SwitchProfileNotification`  | 5     | **1** | Solo sonido |
| `MicrophoneMuteNotification` | 5     | **1** | Solo sonido |

`ChangeCommunications` y `SwitchForegroundProgram` ya estaban en `false`, y no hay perfiles ni reglas por app.

Actualización (2026-11-18):

- Onboarding completado (`FirstRun = false`).
- **Switcher alternativo desinstalado**: ya no hay dos compitiendo por el dispositivo por defecto.
- **SoundSwitch no tiene autostart configurado** (ni clave `Run` ni carpeta Startup). Para que la prueba sea
  real hay que activar _Start automatically with Windows_ en su configuración; si no, tras reiniciar no está
  corriendo y "parece que funciona" justamente porque no está.
- Primeras impresiones del uso diario: **sin parpadeos**. Sin banner, el overlay que se sospechaba como causa
  ya no existe.

Autostart (2026-11-20): lo que arrancaba con Windows era el switcher viejo desde `Downloads`, no SoundSwitch
(que estaba instalado sin entrada de arranque). Se sacó esa clave de `HKCU\...\Run`, se agregó
`SoundSwitch` apuntando a `%LOCALAPPDATA%\Programs\SoundSwitch\SoundSwitch.exe` y se re-exportó
`configs/startup`. Con dos switchers arrancando juntos, los dos pelean por el dispositivo por defecto.

**Veredicto (2026-11-26): se queda.** En uso diario desde el 2026-11-20 sin parpadeos ni trabas al cambiar de
dispositivo. La escalera formal (fase A: 30 cambios seguidos; fase C: una sesión de juego con un cambio en el
medio) no se corrió como tal, pero el síntoma original no volvió en seis días de uso, juegos incluidos.

### Los auriculares piden emparejarse cada vez (BTHUSB Event ID 16)

Síntoma: al conectar aparecen tres pantallas seguidas — "Add a device · Tap to set up your <modelo>",
"Pair device? · would like to pair to this Windows device. Do you want to allow this?" y
"<modelo> · Connection succeeded". O sea **pide pairing, no conexión**: el dispositivo cree que no está
vinculado.

Lo que se verificó en esta PC (2026-11-19):

| Chequeo                                           | Resultado                                                                                                                      |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Vínculo en la PC (`BTHPORT\...\Devices\<MAC>`)    | **Existe** → no se borra de este lado                                                                                          |
| `LastConnected` del dispositivo                   | 2 días antes de la última conexión real → las conexiones nuevas **no** se registran como conexión de un dispositivo emparejado |
| Perfiles PnP (A2DP, AVRCP, HFP)                   | Todos `OK` cuando está conectado                                                                                               |
| **Log `System`, proveedor `BTHUSB`, Event ID 16** | **"The mutual authentication between the local Bluetooth adapter and a device … failed"** (varias veces el mismo día)          |
| Adaptadores presentes                             | **Dos**: Realtek BT 5.0 USB (`VID_0BDA&PID_8771`, OK) e Intel Wireless BT (`CM_PROB_DISABLED`, Code 22)                        |
| Dueño del vínculo                                 | `ServicesFor00e04c239987` = serial del **Realtek** (el Intel está deshabilitado, no participa)                                 |
| Ahorro de energía del adaptador                   | **Ya desactivado** (`MSPower_DeviceEnable = False`) → no es eso                                                                |
| **Driver del adaptador**                          | **Realtek 1.6.1015.3018, del 2021-03-31** ← sospechoso principal                                                               |

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

**Resuelto (2026-11-20):** sin eventos 16 desde el 17/11, los tres endpoints de audio en `OK` (antes
`CM_PROB_PHANTOM`) y los auriculares conectan al instante. **Sin cambiar el dongle**: el mismo adaptador
Realtek sigue puesto, así que lo que lo arregló fue el **re-emparejamiento limpio del 17/11**. La lección:
antes de comprar hardware, quitar el dispositivo y emparejar de nuevo.

**Actualización (2026-11-26): el dongle sí importaba.** Después de cambiar al **TP-Link** (driver
`1.9.1038.3023`) el diálogo de "Pair device?" volvió **una sola vez** —lo esperable, la clave vive en el
adaptador viejo— y desde entonces la reconexión quedó **casi a cero**: ya no pide emparejar todo el rato.
O sea que eran dos cosas: el re-emparejamiento limpio destrabó el vínculo roto, y el adaptador con driver
moderno lo mantiene estable. La conclusión del 20/11 hay que leerla con este agregado: el re-pair era el
primer paso correcto, pero no alcanzaba a largo plazo.

### Checklist al cambiar de adaptador Bluetooth

Cambiar de dongle **rompe el emparejamiento** (la clave vive en el adaptador viejo), así que:

1. Sacar el adaptador viejo, poner el nuevo, instalar su driver.
2. Los auriculares piden pairing **una vez** más → Allow.
3. **Volver a destildar "Manos libres Telephony"** (el re-pareo reactiva los servicios).
4. Verificar que no reaparezca la falla de autenticación:

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='BTHUSB'; Id=16} -MaxEvents 5
```

5. Usar **alargue USB** y evitar los puertos 3.0 (azules): emiten ruido en 2.4 GHz y arruinan la señal.
6. Configuración → Windows Update → Actualizaciones opcionales → Controladores, por si hay un driver más nuevo.

> Ojo: **Bluetooth 5.3 no mejora el audio**. Por A2DP Windows sigue usando SBC o AAC sin importar la
> versión del adaptador; LE Audio necesita soporte del lado del auricular y del stack de Windows.

### Calidad pésima con los REDMI Buds 8 Active (2026-11-23)

Contexto: se cambió el dongle por un **TP-Link Bluetooth USB Adapter** (el driver que instala es
`1.9.1038.3023`) y se re-emparejaron los **REDMI Buds 8 Active**. El re-pareo reinstaló los servicios
Hands-Free, así que quedaron **tres endpoints activos al mismo tiempo**:

| Endpoint                                   | Perfil      | Calidad          |
| ------------------------------------------ | ----------- | ---------------- |
| `Headphones (REDMI Buds 8 Active)`         | A2DP        | estéreo, buena   |
| `Headset (REDMI Buds 8 Active Hands-Free)` | HFP         | mono, de llamada |
| `Headset (REDMI Buds 8 Active)`            | HFP (alias) | mono, de llamada |

Síntoma: el audio sonaba "pésimo" — no con ruido ni cortes, sino **mono y opaco**.

**Causa confirmada a mano:** con `Discord` corriendo y el **micrófono de los auriculares en uso**, Windows
suspende A2DP y manda la salida al endpoint Hands-Free. Es cómo funciona el stack Bluetooth de Windows, no
un bug del dongle: un radio no puede hacer A2DP (alta tasa, un sentido) y HFP (full-duplex, banda angosta) a
la vez.

**Prueba que lo cerró:** deshabilitar el micrófono activo devolvió el sonido correcto al instante, sin tocar
nada más. O sea, el problema es **el micrófono de los buds**, no el perfil de salida.

Regla: **si querés A2DP, el micrófono de los auriculares no puede estar en uso.** No hay setting que lo
evite; es física del perfil, no configuración.

Arreglo (el que quedó aplicado):

1. Panel de control → Sonido → **Grabación** → clic derecho en `Headset (REDMI Buds 8 Active)` →
   **Deshabilitar**. Al desaparecer el endpoint, Windows no tiene a dónde cambiarse.
2. Usar otro micrófono: `Microphone (HyperX SoloCast 2)` o el del `CORSAIR VIRTUOSO`.
3. En Discord: salida fija en `Headphones (REDMI Buds 8 Active)` y **entrada** en el micrófono de escritorio,
   nunca en el de los buds.
4. Después de cualquier reconexión, verificar que la salida siga en el endpoint **estéreo**.

> ⚠️ Un re-emparejamiento **recrea** el endpoint del micrófono, así que hay que volver a deshabilitarlo. Es
> el mismo patrón que "Manos libres Telephony": el re-pair reinstala servicios.
>
> Si hace falta el mic de los buds para una llamada real, hay que aceptar la calidad de llamada mientras
> dure y volver a deshabilitarlo después.

### Configuración que mantiene el emparejamiento sano

Estado exacto de la PC el 2026-11-20, con los auriculares conectando al instante. Si algún día vuelve el
diálogo de "Pair device?", comparar contra esta tabla antes de tocar hardware.

> **Desde el 2026-11-23** el adaptador es un **TP-Link** (driver `1.9.1038.3023`) y los auriculares son
> **REDMI Buds 8 Active**. Las filas de "Driver" y "Puerto USB" de abajo son del adaptador viejo: sirven
> como referencia de un estado que funcionaba, no como lo que hay hoy.

| Componente                                | Valor sano                                                                                                                                       | Cómo verificarlo                                                                                                           |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| Servicios del dispositivo (por adaptador) | `1101` SPP · `110b` A2DP Sink · `110c` AVRCP Target · `110e` AVRCP · `111e` Handsfree · `1124` HID · `fd2d`, `df21fe2c` — **todos `Instance=1`** | subclave `ServicesFor<serial-del-adaptador>` en `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<MAC>\` |
| Seguridad del vínculo                     | `SSP Paired=1`, `SSP Supported=1`, `SSP MITM Protected=0`, `IoCapability=3`                                                                      | mismos valores en esa subclave                                                                                             |
| Ahorro de energía del adaptador           | **Desactivado** (`MSPower_DeviceEnable = False`)                                                                                                 | `Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable` filtrando por `VID_0BDA`                             |
| Fast Startup (inicio rápido)              | **Desactivado** (`HiberbootEnabled = 0`)                                                                                                         | `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power`                                                              |
| Servicios de Windows                      | `bthserv` y `BTAGService` en **Manual / Running** (es lo normal: arrancan a demanda)                                                             | `Get-Service bthserv, BTAGService`                                                                                         |
| Adaptador Intel de la mother              | **Deshabilitado** (Code 22). No sirve: mala señal sin antena, y suma un radio fantasma                                                           | Administrador de dispositivos → Bluetooth                                                                                  |
| Puerto USB                                | USB 2.0 o alargue, lejos de los 3.0 (azules: emiten ruido en 2.4 GHz)                                                                            | —                                                                                                                          |
| Driver                                    | Realtek `1.6.1015.3018` (2021). **Si funciona, no lo toques**                                                                                    | Administrador de dispositivos → propiedades del adaptador                                                                  |

Reglas de oro, en orden de importancia:

1. **Si funciona, no re-emparejes.** Cada re-pair genera clave nueva y reinstala servicios: es la operación
   que más se acerca a "romper" un vínculo sano.
2. **Si vuelve el diálogo de emparejamiento, el primer paso es re-emparejar limpio** (quitar dispositivo →
   Add device). Eso destrabó esta PC la primera vez; si el ciclo **se repite seguido**, el adaptador entra en
   la ecuación: cambiar el dongle bajó la reconexión a casi cero (2026-11-26).
3. **El 5.3 del dongle no mejora el audio**: A2DP en Windows sigue en SBC/AAC. La versión no define la calidad.
4. **Para señal, el alargue USB es lo primero**; pero para el ciclo de re-emparejamiento el dongle nuevo con
   driver moderno sí cambió el resultado en esta PC. No es el 5.3: es el driver.

Chequeo de salud (30 segundos):

```powershell
# ¿volvió la falla de autenticación?
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='BTHUSB'; Id=16} -MaxEvents 5

# ¿los endpoints están vivos (OK) o fantasma (PHANTOM)?
Get-PnpDevice -PresentOnly | Where-Object FriendlyName -match 'Buds' | Select Status, Class, FriendlyName
```

> Nada de esto requiere editar el registro a mano: son valores para **leer** y comparar. El único que se
> cambia desde la UI es "Manos libres Telephony" (y ya se vio que no hace falta tocarlo).

## Resumen de estado

| Problema                             | Solución                                                                      | Estado                   |
| ------------------------------------ | ----------------------------------------------------------------------------- | ------------------------ |
| Perfil Hands-Free agarra el audio    | **Deshabilitar el micrófono de los buds** (el toggle de Telephony no alcanza) | ✅ confirmado 2026-11-23 |
| Pide emparejar y reconecta mal        | Re-pair limpio + dongle con driver moderno (TP-Link `1.9.x`)                 | ✅ casi nulo 2026-11-26  |
| Elegir salida/entrada rápido         | SoundSwitch                                                                   | ✅ adoptado 2026-11-26   |
| Dispositivo de audio incorrecto      | Sin automatización por ahora; el mic deshabilitado evita el salto             | ⏸ pendiente              |
| Toasts en el monitor equivocado      | Sin solución nativa; hacer principal el monitor en uso                        | ⚠️ sin herramienta       |
| Ver/conectar desde el monitor activo | Dock de Wisp (`bt`, panel `Now`)                                              | ✅ disponible            |

## Otras cosas vistas en el log (no relacionadas, pero para no perderlas)

- `Explorer.EXE` crasheó el 2026-11-15 17:41 y el 2026-11-16 11:30, coincidiendo con la llegada de Wisp.
  Wisp oculta la taskbar creando su propio `Shell_TrayWnd`; si los crashes se repiten, es el primer sospechoso.
- `ssn.exe` (Simple Sticky Notes) se cae seguido. App inestable, no es un problema del setup.
