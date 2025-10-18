# 📋 Cómo Ver los Logs del Plugin

El plugin ahora tiene logging completo activado. Los logs se guardan automáticamente en disco.

## 📍 Ubicación del Archivo de Log

### Windows

```
C:\Users\andre\AppData\Roaming\Adobe\Lightroom\Logs\PhotorekaPlugin.log
```

### Ruta Genérica Windows

```
%APPDATA%\Adobe\Lightroom\Logs\PhotorekaPlugin.log
```

### macOS

```
~/Library/Logs/Adobe/Lightroom/PhotorekaPlugin.log
```

---

## 🔍 Cómo Acceder a los Logs

### Método 1: Abrir directamente el archivo

1. **Abre el Explorador de Windows**
2. **Pega esta ruta en la barra de direcciones**:
   ```
   %APPDATA%\Adobe\Lightroom\Logs
   ```
3. **Busca el archivo**: `PhotorekaPlugin.log`
4. **Ábrelo con**: Notepad++, VS Code, o Bloc de notas

### Método 2: Desde Lightroom

1. Ve a **File → Plug-in Manager**
2. Selecciona el plugin **"Export to Photoreka"**
3. Si hay un botón **"Show Log"** o **"View Log"**, haz clic
4. Se abrirá una ventana con los logs

### Método 3: Comando rápido (PowerShell)

Abre PowerShell y ejecuta:

```powershell
notepad "$env:APPDATA\Adobe\Lightroom\Logs\PhotorekaPlugin.log"
```

O para ver en tiempo real:

```powershell
Get-Content "$env:APPDATA\Adobe\Lightroom\Logs\PhotorekaPlugin.log" -Wait -Tail 50
```

---

## 📊 Qué Información Verás

El log contiene información detallada de todo el proceso:

```
========================================
PHOTOREKA PLUGIN INICIADO
========================================
Logger configurado correctamente
Ruta del log: C:\Users\...\PhotorekaPlugin.log
========================================

ApiService cargado. API_BASE_URL: http://localhost:3333

========================================
MAIN.LUA EJECUTÁNDOSE
========================================

========================================
INICIANDO SUBIDA DE FOTOS
Total fotos: 2
Full photos: 2
Thumb photos: 2
EXIF data: 2
========================================

========================================
PROCESANDO FOTO 1 de 2
========================================
===== PROCESANDO FOTO =====
Nombre: DSCF7729.jpg
Path main: C:\Users\...\full\DSCF7729.jpg
Path thumb: C:\Users\...\thumbs\DSCF7729.jpg
PASO 1: Solicitando URLs firmadas...
Preparando request a: http://localhost:3333/api/catalog/uploadPhoto
Body JSON length: 245
Response recibida, length: 567
Status code: 200
Decodificando JSON response...
JSON decodificado OK
URLs recibidas OK
Upload URL: https://r2.cloudflare.com/...
Thumb URL: https://r2.cloudflare.com/...
PASO 2: Subiendo imagen principal...
Leyendo archivo: C:\Users\...\full\DSCF7729.jpg
Archivo leído, tamaño: 456789 bytes
Intento 1 de 3 para subir DSCF7729.jpg
Haciendo PUT a R2...
R2 Response status: 200
Upload exitoso!
Imagen principal subida OK
PASO 3: Subiendo thumbnail...
Leyendo archivo: C:\Users\...\thumbs\DSCF7729.jpg
Archivo leído, tamaño: 123456 bytes
Intento 1 de 3 para subir DSCF7729.jpg
Haciendo PUT a R2...
R2 Response status: 403
R2 error 403: Forbidden
Esperando 2 segundos antes de reintentar...
Intento 2 de 3 para subir DSCF7729.jpg
...

✗ Foto 1 FALLÓ: Failed to upload thumbnail after 3 attempts

========================================
RESUMEN DE SUBIDA
Exitosas: 0
Fallidas: 2
========================================
```

---

## 🎯 Información Clave en los Logs

El log te mostrará:

### ✅ Por cada foto:

- Nombre del archivo
- Rutas completas (main + thumb)
- Tamaño de los archivos en bytes
- URLs de subida generadas

### 🌐 Por cada request HTTP:

- URL del endpoint
- Status code de respuesta (200, 403, 500, etc.)
- Tamaño de los datos enviados/recibidos
- Mensajes de error del servidor

### 🔄 Por cada intento de subida:

- Número de intento (1, 2, 3...)
- Respuesta de R2/Cloudflare
- Tiempo de espera entre reintentos
- Razón del fallo

### 📈 Resumen final:

- Total de fotos procesadas
- Fotos exitosas
- Fotos fallidas

---

## 🐛 Identificar Problemas

### Error 401/403 - Autenticación

```
Server error 401: Unauthorized
```

**Solución**: Verifica que el `AUTH_TOKEN` en `ApiService.lua` sea correcto

### Error 404 - Endpoint no encontrado

```
Server error 404: Not Found
```

**Solución**: Verifica que `API_BASE_URL` sea correcto

### Error en subida a R2

```
R2 error 403: Forbidden
```

**Solución**: Las URLs firmadas pueden haber expirado o ser inválidas

### No hay respuesta del servidor

```
ERROR: No response from server
```

**Solución**:

- Verifica que tu API local esté corriendo
- Verifica conexión a internet
- Verifica que el puerto 3333 esté abierto

---

## 🔧 Tips para Debugging

1. **Reinicia Lightroom** después de hacer cambios en el código
2. **Borra el log anterior** antes de una nueva prueba
3. **Prueba con 1 foto** primero para logs más claros
4. **Copia el log completo** si necesitas ayuda

---

## 📝 Ejemplo de Comando para Ver Log en Tiempo Real

Si quieres ver el log mientras se ejecuta el plugin:

```powershell
# PowerShell
Get-Content "$env:APPDATA\Adobe\Lightroom\Logs\PhotorekaPlugin.log" -Wait -Tail 50
```

Esto mostrará las últimas 50 líneas y se actualizará automáticamente.

---

**Última actualización**: Octubre 2025  
**Plugin**: Photoreka Export v2.0
