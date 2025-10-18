# Instrucciones de Configuración - Plugin Photoreka para Lightroom

## Variables de Configuración

Todas las variables que necesitas configurar están al **inicio del archivo `ApiService.lua`**.

### 1. Abre el archivo `ApiService.lua`

Busca las siguientes líneas al principio del archivo:

```lua
-- ========================================
-- CONFIGURACIÓN - EDITAR ESTAS VARIABLES
-- ========================================
ApiService.API_BASE_URL = 'https://api.photoreka.com'
ApiService.ANALYZER_API_BASE_URL = 'https://analyzer.photoreka.com'
ApiService.AUTH_TOKEN = ''  -- SETEAR TOKEN AQUÍ PARA PRUEBAS (sin "Bearer ")
ApiService.USE_MOCK_EXIF = true  -- true = usar EXIF inventados, false = extraer EXIF reales
-- ========================================
```

### 2. Variables a Configurar

#### **AUTH_TOKEN** ⚠️ OBLIGATORIO

- **Descripción**: Token de autenticación de Photoreka
- **Formato**: String sin el prefijo "Bearer "
- **Ejemplo**: `ApiService.AUTH_TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'`
- **⚠️ IMPORTANTE**: El plugin NO FUNCIONARÁ si no configuras este token

#### **API_BASE_URL**

- **Descripción**: URL base de la API principal de Photoreka
- **Valor por defecto**: `'https://api.photoreka.com'`
- **Cambiar solo si**: Usas un entorno de desarrollo o staging

#### **ANALYZER_API_BASE_URL**

- **Descripción**: URL del servicio de análisis de fotos
- **Valor por defecto**: `'https://analyzer.photoreka.com'`
- **Cambiar solo si**: Usas un entorno de desarrollo o staging

#### **USE_MOCK_EXIF**

- **Descripción**: Controla si usar EXIF inventados o extraer los reales de las fotos
- **Valores**:
  - `true`: Usa datos EXIF inventados (útil para pruebas rápidas)
  - `false`: Extrae los EXIF reales de cada foto (producción)
- **Valor por defecto**: `true`
- **Recomendación**: Déjalo en `true` para las primeras pruebas

---

## Configuración de Comportamiento

Estas variables también están en `ApiService.lua` y controlan el comportamiento de la subida:

```lua
ApiService.BATCH_SIZE = 5  -- Fotos por lote (no se usa actualmente, subida es secuencial)
ApiService.MAX_RETRIES = 3  -- Reintentos por subida fallida
```

### Variables de Comportamiento

#### **BATCH_SIZE**

- **Descripción**: Tamaño de lote para procesamiento (reservado para futuro)
- **Valor actual**: 5
- **Nota**: Actualmente la subida es secuencial (una por una)

#### **MAX_RETRIES**

- **Descripción**: Número de reintentos si falla la subida a Cloudflare R2
- **Valor por defecto**: 3
- **Recomendación**: Mantener en 3 o aumentar si tienes conexión inestable

---

## Pasos para Configurar

1. **Obtener tu token de Photoreka**

   - Inicia sesión en https://www.photoreka.com
   - Ve a tu perfil/configuración
   - Copia tu token de API

2. **Editar `ApiService.lua`**

   - Abre el archivo con un editor de texto
   - Busca la línea: `ApiService.AUTH_TOKEN = ''`
   - Pega tu token entre las comillas: `ApiService.AUTH_TOKEN = 'tu_token_aqui'`

3. **Guardar y cerrar**

   - Guarda el archivo
   - Reinicia Lightroom si ya estaba abierto

4. **Probar el plugin**
   - Selecciona algunas fotos en Lightroom
   - Ejecuta el plugin desde File > Plug-in Extras > Export to Photoreka
   - Verifica que las fotos se suban correctamente

---

## Flujo de Subida

El plugin sigue este proceso:

1. **Fase 1: Exportación (40%)**

   - Exporta versión principal (1500px max)
   - Exporta thumbnail (800px max)

2. **Fase 2: EXIF (10%)**

   - Extrae o genera datos EXIF de cada foto
   - Incluye: cámara, lente, configuraciones, GPS, fecha

3. **Fase 3: Subida a API (50%)**
   - Para cada foto:
     - Solicita URLs firmadas al servidor
     - Sube archivo principal a Cloudflare R2
     - Sube thumbnail a Cloudflare R2
     - Maneja reintentos automáticos
   - Al finalizar: Trigger de post-procesamiento

---

## Solución de Problemas

### Error: "AUTH_TOKEN no está configurado"

- **Causa**: No has configurado el token
- **Solución**: Edita `ApiService.lua` y setea `ApiService.AUTH_TOKEN`

### Error: "Failed to get upload URLs from server"

- **Causa**: Token inválido o servidor no responde
- **Solución**:
  - Verifica que el token sea correcto
  - Verifica que `API_BASE_URL` sea correcto
  - Comprueba tu conexión a internet

### Error: "Failed to upload after 3 attempts"

- **Causa**: Problemas de conexión con Cloudflare R2
- **Solución**:
  - Verifica tu conexión a internet
  - Aumenta `MAX_RETRIES` en `ApiService.lua`
  - Las URLs firmadas expiran rápido, intenta con menos fotos

### Algunas fotos fallan pero otras no

- **Causa**: Posiblemente archivos corruptos o muy grandes
- **Solución**:
  - Revisa las fotos que fallaron
  - Intenta re-exportarlas manualmente
  - Verifica que sean JPEGs válidos

---

## Próximos Pasos

Una vez que hayas probado con `USE_MOCK_EXIF = true` y funcione correctamente:

1. Cambia a `USE_MOCK_EXIF = false` para usar EXIF reales
2. Prueba con un lote pequeño de fotos (3-5)
3. Si funciona bien, prueba con más fotos
4. Reporta cualquier problema o error

---

## Estructura de Archivos

```
LrExport.lrplugin/
├── ApiService.lua          ← CONFIGURAR AQUÍ
├── ExifService.lua         (servicio de EXIF)
├── ExportService.lua       (servicio de exportación)
├── JSON.lua                (librería JSON)
├── Main.lua                (lógica principal)
├── Init.lua                (punto de entrada)
├── info.lua                (metadatos del plugin)
└── CONFIG_INSTRUCTIONS.md  (este archivo)
```

---

**Fecha**: Octubre 2025  
**Versión del Plugin**: 2.0  
**Soporte**: andresramosp@photoreka.com
