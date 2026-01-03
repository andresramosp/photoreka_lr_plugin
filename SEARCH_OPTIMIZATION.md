# Optimización del Sistema de Búsqueda y Matcheo

## Problema Identificado

El sistema de búsqueda fallback se bloqueaba cuando había muchas fotos en el catálogo de Lightroom debido a:

1. **Complejidad O(m × n)**: Para cada foto del resultado de la API (m), se iteraba sobre TODAS las fotas del catálogo (n)
2. **Operaciones costosas**: Extracción de EXIF y comparaciones de fechas para cada iteración
3. **Sin optimización**: No se aprovechaba que ya sabíamos el nombre del archivo buscado

### Ejemplo del problema:

- **Catálogo**: 10,000 fotos
- **Resultados API**: 50 fotos
- **Búsqueda por uniqueId**: ~10,000 comparaciones simples ✓ RÁPIDO
- **Fallback sin optimizar**: ~500,000 comparaciones + extracciones EXIF ✗ BLOQUEO

## Soluciones Implementadas

### 1. Índice de Nombres de Archivo (Hash Table)

**Antes:**

```lua
-- Iterar TODAS las fotos para cada búsqueda: O(n)
for _, photo in ipairs(allPhotos) do
    if normalizedFileName == normalizeFileName(photo:getFormattedMetadata('fileName')) then
        -- Comparar fecha/EXIF
    end
end
```

**Después:**

```lua
-- Crear índice UNA VEZ: O(n)
fileNameIndex = buildFileNameIndex(allPhotos)  -- {fileName -> [photos]}

-- Buscar por nombre: O(1)
local candidates = fileNameIndex[normalizedFileName]
-- Solo iterar sobre candidatos (típicamente 1-5 fotos): O(k) donde k << n
```

**Mejora**: De O(m × n) a O(n + m × k), donde k es típicamente < 10

### 2. Lazy Evaluation de EXIF

Solo se extraen y comparan datos EXIF de fotos que ya coinciden en nombre de archivo.

**Antes**: Extraer EXIF de todas las fotos del catálogo
**Después**: Solo extraer EXIF de ~1-5 candidatos por foto buscada

### 3. Creación Condicional del Índice

El índice solo se crea si `Config.USE_SEARCH_FALLBACK = true`, evitando overhead innecesario.

```lua
if Config.USE_SEARCH_FALLBACK then
    fileNameIndex = buildFileNameIndex(allPhotos)
end
```

## Resultados Esperados

### Rendimiento Estimado

| Tamaño Catálogo | Resultados API | Antes (sin índice) | Después (con índice) | Mejora |
| --------------- | -------------- | ------------------ | -------------------- | ------ |
| 1,000 fotos     | 10 resultados  | ~1 segundo         | ~0.1 segundos        | 10x    |
| 10,000 fotos    | 50 resultados  | BLOQUEO (>60s)     | ~0.5 segundos        | >100x  |
| 50,000 fotos    | 100 resultados | BLOQUEO            | ~2 segundos          | >1000x |

### Estrategias de Búsqueda

1. **Por uniqueId**: O(n) - Más confiable, para fotos exportadas desde Lightroom
2. **Por fileName + fecha**: O(1 + k) - Fallback para fotos importadas de otras fuentes
3. **Por EXIF**: O(1 + k) - Último recurso cuando la fecha no coincide

## Configuración

En `Config.lua`:

```lua
-- Habilitar/deshabilitar búsqueda fallback
Config.USE_SEARCH_FALLBACK = true  -- Ahora es seguro habilitarlo
```

## Logs y Monitoreo

El sistema genera logs detallados:

```
========================================
INICIANDO BÚSQUEDA DE FOTOS CON MATCHEO MULTI-NIVEL
Total fotos a buscar: 50
========================================
Catálogo contiene 10000 fotos totales
Creando índice de nombres de archivo para optimizar búsqueda fallback...
Índice de nombres creado: 9987 fotos indexadas, 13 errores
Índice creado con 9950 nombres únicos

[1] ✓ Encontrada por uniqueId: 12345
[2] ✓ Encontrada por fileName+fecha: IMG_0001.jpg (score: 0.98)
[3] ✓ Encontrada por EXIF: IMG_0002.jpg (score: 0.85)
[4] ✗ No se pudo encontrar: fileName=IMG_0003.jpg, uniqueId=nil

========================================
RESUMEN DE BÚSQUEDA:
  - Por uniqueId: 30
  - Por fileName+fecha: 15
  - Por EXIF: 3
  - No encontradas: 2
  - TOTAL ENCONTRADAS: 48 de 50
========================================
```

## Consideraciones Técnicas

### Uso de Memoria

El índice consume ~O(n) memoria adicional, pero es despreciable comparado con el catálogo de Lightroom:

- 10,000 fotos ≈ 1-2 MB de índice
- 50,000 fotos ≈ 5-10 MB de índice

### Precisión de Matcheo

Los umbrales de score se han calibrado para balance entre precisión y recall:

- **dateScore > 0.5**: Menos de 12 horas de diferencia (evita falsos positivos)
- **exifScore > 0.7**: 70% de coincidencia en campos EXIF (alta confianza)

### Thread Safety

Todas las operaciones se ejecutan en el contexto de un solo thread de Lightroom, por lo que no hay problemas de concurrencia.

## Próximas Optimizaciones Potenciales

1. **Caché de índice**: Guardar el índice en disco para reutilizar entre sesiones
2. **Índice por fecha**: Crear índice adicional por fecha para búsquedas temporales
3. **Búsqueda fuzzy**: Permitir pequeñas diferencias en nombres de archivo
4. **Paralelización**: Procesar múltiples búsquedas en paralelo (si Lightroom SDK lo permite)

---

**Fecha de implementación**: Octubre 2025
**Versión**: 1.1.0
