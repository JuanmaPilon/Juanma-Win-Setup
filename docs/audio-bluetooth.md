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

| Endpoint | Para qué sirve | Calidad |
| -------- | -------------- | ------- |
| `Hands-Free` (manos libres) | Micrófono / llamadas | Baja, mono |
| A2DP (estéreo) | Reproducción de música | Alta |

Ejemplo real en esta PC: `Headset (<modelo> Hands-Free)` junto a su par `Headphones (<modelo> Stereo)`.

Windows puede conectar el perfil Hands-Free y dejar el estéreo de lado, o cambiar el dispositivo
por defecto a mitad de sesión.

### Solución aplicada (2026-11): desactivar el servicio de manos libres

**Panel de control → Dispositivos e impresoras → clic derecho en los auriculares → Propiedades →
pestaña Servicios → destildar "Manos libres Telephony" (Hands-free Telephony).**

Efecto: queda solo el endpoint A2DP. Windows ya no tiene a qué cambiarse y el audio sale siempre en estéreo.

> **Estado: aplicado y en observación.** Si en algún momento hace falta usar el micrófono de los
> auriculares para llamadas, hay que volver a tildarlo.

## Herramientas evaluadas

### SoundSwitch (`AntoineAflalo.SoundSwitch`) — descartado

Lo que ofrecía y era exactamente lo que se buscaba:

- Perfiles con triggers, incluido **Device Changed Trigger** (mantener el dispositivo aunque Windows lo cambie).
- Banner de notificación propio, always-on-top → visible en juegos, sin depender del toast de Windows.
- Triggers por aplicación, hotkeys, tray, CLI.
- Cambio de dispositivo Multimedia **y** Communications (Windows los separa).
- Proyecto maduro: 3.5k estrellas, 95 contribuidores, en Winget.

**Por qué se descartó:** al cambiar de dispositivo de audio, y sobre todo a mitad de un juego, la PC
**parpadeaba como si se reiniciaran todos los dispositivos** y quedaba trabada un momento. No era un caso
aislado, así que se desinstaló.

Hipótesis (sin confirmar): el cambio de default device vía `IPolicyConfig` fuerza una re-enumeración de
endpoints de audio; los endpoints HDMI/DisplayPort cuelgan de la GPU, así que el reset arrastra al driver de
video y se ve como un parpadeo de pantalla.

Si se quiere reintentar: probar primero sin el banner, con un solo perfil y sin triggers de aplicación, para
aislar qué parte provoca el efecto.

### AudioSwitcher — en evaluación / descartado

Portable, corría desde `Downloads`. Sólo hotkeys + tray, sin reglas automáticas. Reemplazado conceptualmente
por SoundSwitch (que se descartó). No resuelve el problema de fondo.

### Wisp — parcialmente útil

El dock de Wisp puede mostrar `bluetooth` y `sound` como secciones de estado, y el launcher tiene comandos
`bt` (dispositivos pareados), `wifi`, `vol`, y el panel `Now`. Sirve para conectar/ver desde el monitor donde
está el mouse, sin depender del toast.

### Windhawk `notifications-placement` — la única solución al monitor del toast

Mod de `m417z` (autor de Windhawk), incluido en Windhawk. Con `monitor = 0` mueve **todos los toasts**
(incluido el de Bluetooth conectado) al monitor donde está el cursor.

Actualmente el módulo Windhawk del repo está pausado porque Wisp reemplazó la taskbar, pero este mod es
independiente de la taskbar y sigue funcionando con Wisp: inyecta sólo en `explorer.exe` y
`ShellExperienceHost.exe`.

Windows no tiene ningún setting ni API pública para elegir el monitor de las notificaciones. Las alternativas
reales son este mod, o marcar como principal el monitor que se usa.

## Resumen de estado

| Problema | Solución | Estado |
| -------- | -------- | ------ |
| Perfil Hands-Free agarra el audio | Destildar "Manos libres Telephony" | ✅ aplicado, en observación |
| Dispositivo de audio incorrecto | Sin herramienta: SoundSwitch descartado por el parpadeo | ⏸ pendiente |
| Toasts en el monitor equivocado | Windhawk `notifications-placement`, `monitor = 0` | ✅ disponible |
| Ver/conectar desde el monitor activo | Dock de Wisp (`bt`, panel `Now`) | ✅ disponible |
