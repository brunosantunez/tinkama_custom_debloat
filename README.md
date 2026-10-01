# Tinkama Custom Debloat

Herramienta PowerShell 5.1 + WPF para aplicar una optimizacion repetible en equipos con Windows 10 y Windows 11.

## Ejecucion remota

Abre Windows PowerShell como administrador y ejecuta:

```powershell
irm https://raw.githubusercontent.com/brunosantunez/tinkama_custom_debloat/main/Install.ps1 | iex
```

El instalador descarga la rama `main` desde GitHub, valida los archivos principales y abre la interfaz. No requiere alojamiento adicional.

## Uso

1. Ejecuta `Run.cmd`.
2. Acepta la elevacion de administrador.
3. Elige `Basica segura`, `Taller completo` o selecciona acciones manualmente.
4. Revisa la previsualizacion y pulsa `Aplicar seleccion`.

Antes de cada aplicacion se crea obligatoriamente un punto de restauracion llamado `Revertir cambios - Tinkama Custom Debloat`. La creacion tiene un limite de 120 segundos; si Windows no la completa, el proceso se detiene sin aplicar ajustes y la interfaz vuelve a responder.

La aplicacion solicita elevacion normal de administrador y usa Windows PowerShell 5.1 nativo en modo STA. Antes de abrir la interfaz pregunta si puede preparar los scripts para el proceso actual; el boton `Herramientas > Preparar scripts` permite repetir esa preparacion. No desactiva UAC, Microsoft Defender ni cambia la politica de ejecucion permanente. Las directivas de grupo restrictivas se informan como error y no se alteran.

Los errores del proceso permanecen en `Restaurar y registro`. La pestana `Depuracion` reune cada cambio no efectuado con su instruccion, comando y motivo, incluidos paquetes ausentes, advertencias y errores. El informe se puede copiar desde la interfaz y tambien queda guardado como `debug-report.txt` dentro del respaldo de la sesion; no se transmite por Internet automaticamente. Las solicitudes, resultados y archivos `stderr.log` quedan en `%ProgramData%\TinkamaCustomDebloat\Requests`; los errores de arranque se guardan en `%LOCALAPPDATA%\TinkamaCustomDebloat\Logs`.

El registro se actualiza en vivo y muestra el identificador, patron, paquete, ruta o servicio de cada operacion. Una vez creado el punto de restauracion y guardado el inventario, un elemento incompatible se omite y el resto continua; la sesion termina como `CompletedWithWarnings`. El mensaje `Paquete no instalado; no requiere cambios` es informativo y significa que esa aplicacion ya no estaba presente. Los fallos de preparacion o del punto de restauracion siguen deteniendo el proceso antes de aplicar ajustes.

## Perfiles

- `Basica segura`: privacidad, sugerencias, busqueda web, notificaciones, acceso remoto, dispositivos moviles, drivers por Windows Update, Game Bar, plan de energia y limpieza. Conserva componentes con impacto funcional alto.
- `Taller completo`: agrega hibernacion, almacenamiento reservado, OneDrive, IA, aplicaciones incluidas con Windows, Xbox completo y servicios opcionales relacionados.
- `Captura agresiva`: reproduce los servicios no esenciales de la captura. Puede desactivar impresion, camara, busqueda, mandos, hotspot y actualizaciones de Edge. Requiere una confirmacion adicional.

`Display Policy Service` y `Group Policy Client` estan protegidos. Windows Defender, Windows Update, BITS, Microsoft Store, App Installer, Windows Security, el shell y sus runtimes tambien quedan fuera del alcance.

El asistente de concentracion no se modifica escribiendo datos binarios internos de `CloudStore`: ese formato cambia entre versiones y no ofrece una politica estable comun a Windows 10 y 11. El perfil ya desactiva las notificaciones globales solicitadas.

En Windows 11, los tres perfiles habilitan el menu contextual completo de Windows 10. El cambio es por usuario, requiere reiniciar el Explorador o la sesion y la restauracion interna devuelve el estado anterior.

La reversion interna restaura valores de registro, servicios y el plan de energia desde la ultima sesion. No recupera aplicaciones eliminadas ni temporales borrados. El boton `Abrir Restaurar sistema` ofrece una recuperacion adicional del sistema, pero no sustituye un respaldo de archivos ni garantiza reinstalar todos los paquetes.

El proyecto toma como referencia los enfoques publicos de [WinUtil](https://github.com/ChrisTitusTech/winutil), [Win11Debloat](https://github.com/Raphire/Win11Debloat) y [FPSBoostPro](https://github.com/itechfever/FPSBoostPro). La implementacion de este repositorio es independiente y mantiene sus propias listas de seguridad.
