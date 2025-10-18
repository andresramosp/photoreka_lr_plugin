# Resumen: Centralización de Configuración

## ✅ Cambios Realizados

Se ha creado un archivo de configuración centralizada (`Config.lua`) que elimina la duplicación de variables en múltiples archivos.

## 📋 Antes vs Después

### ❌ ANTES (configuración distribuida)

Variables duplicadas en varios archivos:

- `ApiService.lua`:

  ```lua
  ApiService.API_BASE_URL = 'http://localhost:3333'
  ApiService.ANALYZER_API_BASE_URL = 'http://localhost:3333'
  ApiService.AUTH_TOKEN = 'token_hardcoded'
  ApiService.USE_MOCK_EXIF = true
  ApiService.MAX_RETRIES = 3
  ApiService.CONCURRENT_UPLOADS = 5
  ```

- `AuthService.lua`:
  ```lua
  AuthService.API_BASE_URL = nil  -- Se configuraba desde ApiService
  ```

**Problemas:**

- Duplicación de variables
- Configuración en múltiples lugares
- Difícil mantenimiento
- Riesgo de inconsistencias

### ✅ DESPUÉS (configuración centralizada)

**Un solo archivo de configuración: `Config.lua`**

```lua
local Config = {}

Config.API_BASE_URL = 'http://localhost:3333'
Config.ANALYZER_API_BASE_URL = 'http://localhost:3333'
Config.USE_MOCK_EXIF = true
Config.MAX_RETRIES = 3
Config.CONCURRENT_UPLOADS = 5

return Config
```

**Todos los módulos importan Config:**

- `ApiService.lua`: `local Config = require 'Config'`
- `AuthService.lua`: `local Config = require 'Config'`
- `Main.lua`: `local Config = require 'Config'`

**Ventajas:**

- ✅ Un solo lugar para configurar
- ✅ Sin duplicación
- ✅ Fácil de encontrar y modificar
- ✅ Consistencia garantizada

## 🗂️ Archivos Nuevos/Modificados

### Nuevo: `Config.lua`

Archivo de configuración centralizada con todas las variables del plugin.

### Modificados:

1. **`ApiService.lua`**

   - Importa `Config` en lugar de definir variables propias
   - Usa `Config.API_BASE_URL`, `Config.MAX_RETRIES`, etc.
   - Eliminada configuración de `AuthService.API_BASE_URL`

2. **`AuthService.lua`**

   - Importa `Config` en lugar de recibir URL desde ApiService
   - Usa `Config.API_BASE_URL` directamente
   - Eliminada variable `AuthService.API_BASE_URL`

3. **`Main.lua`**
   - Importa `Config`
   - Usa `Config.USE_MOCK_EXIF` en lugar de `ApiService.USE_MOCK_EXIF`

### Documentación Nueva:

- **`CONFIG_GUIDE.md`**: Guía completa de configuración
- **`CENTRALIZED_CONFIG.md`**: Este archivo (resumen)

### Documentación Actualizada:

- **`README.md`**: Referencias al nuevo sistema
- **`AUTH_GUIDE.md`**: Actualizado para mencionar Config.lua

## 🎯 Cómo Usar la Nueva Configuración

### Para cambiar la URL de la API:

**Edita solo `Config.lua`:**

```lua
-- Cambiar de desarrollo a producción
Config.API_BASE_URL = 'https://api.photoreka.com'
Config.ANALYZER_API_BASE_URL = 'https://api.photoreka.com'
```

### Para ajustar el comportamiento de subida:

**Edita solo `Config.lua`:**

```lua
-- Conexión lenta
Config.CONCURRENT_UPLOADS = 2
Config.MAX_RETRIES = 5

-- Conexión rápida
Config.CONCURRENT_UPLOADS = 8
Config.MAX_RETRIES = 2
```

### Para cambiar entre EXIF mock y real:

**Edita solo `Config.lua`:**

```lua
-- Pruebas sin fotos reales
Config.USE_MOCK_EXIF = true

-- Producción con EXIF real
Config.USE_MOCK_EXIF = false
```

## 📊 Mapa de Dependencias

```
Config.lua (configuración centralizada)
    ↓
    ├─→ ApiService.lua
    │   - API_BASE_URL
    │   - ANALYZER_API_BASE_URL
    │   - MAX_RETRIES
    │   - CONCURRENT_UPLOADS
    │
    ├─→ AuthService.lua
    │   - API_BASE_URL
    │
    └─→ Main.lua
        - USE_MOCK_EXIF
```

## 🔒 Nota sobre AUTH_TOKEN

**Ya NO existe `AUTH_TOKEN` en la configuración.**

El sistema de autenticación ahora funciona con login interactivo:

1. El usuario inicia sesión la primera vez
2. El token se guarda en las preferencias de Lightroom
3. El token se reutiliza automáticamente en sesiones posteriores

Ver `AUTH_GUIDE.md` para más detalles.

## 📝 Checklist de Migración

Si estabas usando el sistema antiguo:

- [x] ✅ Variables movidas a `Config.lua`
- [x] ✅ `ApiService.lua` actualizado
- [x] ✅ `AuthService.lua` actualizado
- [x] ✅ `Main.lua` actualizado
- [x] ✅ Documentación actualizada
- [ ] ⚠️ **Acción requerida**: Revisa `Config.lua` y ajusta las URLs para tu entorno
- [ ] ⚠️ **Acción requerida**: Reinicia Lightroom para que los cambios tomen efecto

## 🎉 Resultado

Ahora tienes:

- ✨ Un solo lugar para toda la configuración
- 🧹 Código más limpio y organizado
- 🚀 Más fácil de mantener y actualizar
- 📚 Mejor documentación
- 🔐 Sistema de autenticación robusto
