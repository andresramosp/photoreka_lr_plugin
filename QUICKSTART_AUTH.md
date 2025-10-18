# Inicio Rápido - Autenticación

## ¿Qué cambió?

Ya **NO necesitas** configurar manualmente el `AUTH_TOKEN` en `ApiService.lua`.

El plugin ahora te pedirá que inicies sesión la primera vez que lo uses.

## Primer uso

1. Abre el plugin en Lightroom
2. Se mostrará automáticamente un diálogo de login
3. Ingresa tu email y password de Photoreka
4. Haz clic en "Iniciar sesión"
5. ¡Listo! El token se guarda automáticamente

## Usos posteriores

El plugin recordará tu sesión. No necesitarás volver a iniciar sesión a menos que:

- Cierres sesión manualmente desde el botón de cuenta (👤)
- Desinstales el plugin
- Borres las preferencias de Lightroom

## Cerrar sesión

1. Abre el plugin
2. Haz clic en el botón de cuenta (👤 Tu Nombre) en la esquina superior derecha
3. Haz clic en "Cerrar sesión"

## Solución de problemas

### "No se pudo conectar con el servidor"

- Verifica que la API esté corriendo
- Verifica que `API_BASE_URL` en `ApiService.lua` sea correcta
- En producción, asegúrate de usar HTTPS

### "Credenciales inválidas"

- Verifica que el email y password sean correctos
- Asegúrate de que tu cuenta esté activa en Photoreka

### El plugin pide login cada vez

- Esto puede pasar si hay un problema guardando las preferencias
- Verifica los permisos de escritura en el directorio de preferencias de Lightroom
- Revisa el log para ver si hay errores

## Ver el log

Para ver detalles de lo que está pasando:

**Windows (PowerShell)**:

```powershell
.\ver-log.ps1
```

**Windows (CMD o manualmente)**:

```
type "%USERPROFILE%\Documents\PhotorekaPlugin.log"
```

El log mostrará:

- Cuando se intenta obtener un token guardado
- Cuando se muestra el diálogo de login
- Cuando se hace una petición de login
- Cuando se guarda el token
- Cuando se cierra sesión
