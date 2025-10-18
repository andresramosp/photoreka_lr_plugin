# Guía de Configuración del Plugin

## Archivo de Configuración Centralizada

Todo el plugin se configura desde un único archivo: **`Config.lua`**

### Ubicación

```
LrExport.lrplugin/Config.lua
```

### Variables de Configuración

#### 🌐 URLs de la API

```lua
Config.API_BASE_URL = 'http://localhost:3333'
```

- **Descripción**: URL base de la API de Photoreka
- **Desarrollo**: `http://localhost:3333`
- **Producción**: `https://api.photoreka.com` (o tu dominio)
- **Usado por**: `ApiService`, `AuthService`

```lua
Config.ANALYZER_API_BASE_URL = 'http://localhost:3333'
```

- **Descripción**: URL de la API del Analyzer
- **Nota**: Normalmente es la misma que `API_BASE_URL`
- **Usado por**: `ApiService` (para trigger de post-procesamiento)

#### 📸 Configuración de EXIF

```lua
Config.USE_MOCK_EXIF = true
```

- **Descripción**: Define si se usan datos EXIF reales o inventados
- **`true`**: Usa EXIF inventados (útil para pruebas sin fotos reales)
- **`false`**: Extrae EXIF reales de las fotos de Lightroom
- **Usado por**: `Main.lua`, `ExifService`

#### ⬆️ Configuración de Subida

```lua
Config.MAX_RETRIES = 3
```

- **Descripción**: Número máximo de reintentos por subida fallida
- **Valor por defecto**: `3`
- **Comportamiento**: Si una subida falla, se reintenta hasta este número de veces con backoff exponencial (2s, 4s, 8s)
- **Usado por**: `ApiService`

```lua
Config.CONCURRENT_UPLOADS = 5
```

- **Descripción**: Número de subidas simultáneas (límite de concurrencia)
- **Valor por defecto**: `5`
- **Comportamiento**: Controla cuántas fotos se suben en paralelo
- **Recomendaciones**:
  - Valores bajos (1-3): Más estable pero más lento
  - Valores medios (4-6): Balance entre velocidad y estabilidad
  - Valores altos (7+): Más rápido pero puede causar problemas de red/memoria
- **Usado por**: `ApiService`

## Uso en el Código

Todos los módulos que necesitan configuración importan `Config.lua`:

```lua
local Config = require 'Config'

-- Luego usan las variables así:
local url = Config.API_BASE_URL .. "/api/auth/login"
```

### Módulos que usan Config

| Módulo            | Variables que usa                                                            |
| ----------------- | ---------------------------------------------------------------------------- |
| `ApiService.lua`  | `API_BASE_URL`, `ANALYZER_API_BASE_URL`, `MAX_RETRIES`, `CONCURRENT_UPLOADS` |
| `AuthService.lua` | `API_BASE_URL`                                                               |
| `Main.lua`        | `USE_MOCK_EXIF`                                                              |

## Cambios de Configuración

### Para cambiar la URL de la API (ej: pasar a producción)

Edita `Config.lua`:

```lua
-- ANTES (desarrollo)
Config.API_BASE_URL = 'http://localhost:3333'
Config.ANALYZER_API_BASE_URL = 'http://localhost:3333'

-- DESPUÉS (producción)
Config.API_BASE_URL = 'https://api.photoreka.com'
Config.ANALYZER_API_BASE_URL = 'https://api.photoreka.com'
```

### Para usar EXIF reales en lugar de mock

Edita `Config.lua`:

```lua
-- ANTES
Config.USE_MOCK_EXIF = true

-- DESPUÉS
Config.USE_MOCK_EXIF = false
```

### Para ajustar la velocidad de subida

Edita `Config.lua`:

```lua
-- Conexión lenta o inestable
Config.CONCURRENT_UPLOADS = 2
Config.MAX_RETRIES = 5

-- Conexión rápida y estable
Config.CONCURRENT_UPLOADS = 8
Config.MAX_RETRIES = 2
```

## Ventajas de la Configuración Centralizada

✅ **Un solo lugar para configurar**: No hay que buscar en múltiples archivos  
✅ **Sin duplicación**: Las mismas variables se usan en todos los módulos  
✅ **Fácil mantenimiento**: Cambios rápidos sin tocar lógica de negocio  
✅ **Documentación clara**: Todas las opciones están en un solo archivo comentado  
✅ **Separación de responsabilidades**: Configuración separada de la implementación

## Notas Importantes

⚠️ **Autenticación**: Ya NO necesitas configurar `AUTH_TOKEN` manualmente. El plugin gestiona la autenticación automáticamente mediante login. Ver `AUTH_GUIDE.md` para más detalles.

⚠️ **HTTPS en producción**: Siempre usa HTTPS en producción para proteger las credenciales y datos de usuarios.

⚠️ **Después de cambios**: Reinicia Lightroom después de modificar `Config.lua` para que los cambios tomen efecto.
