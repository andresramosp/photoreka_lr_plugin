-- Config.lua - Configuración centralizada del plugin
local Config = {}

-- ========================================
-- CONFIGURACIÓN PRINCIPAL
-- ========================================

-- URL base de la API de Photoreka
-- En desarrollo: 'http://localhost:3333'
-- En producción: 'https://api.photoreka.com' (o tu dominio)
-- Config.API_BASE_URL = 'http://localhost:3333'
Config.API_BASE_URL = 'https://curatorlabapi-production.up.railway.app'

-- Config.APP_BASE_URL = 'http://localhost:5173'
Config.APP_BASE_URL = 'https://app.photoreka.com'

-- URL de la API del Analyzer (normalmente la misma que API_BASE_URL)
-- Config.ANALYZER_API_BASE_URL = 'http://localhost:3333'
Config.ANALYZER_API_BASE_URL = 'https://photorekaanalyzerapi-production.up.railway.app'


-- ========================================
-- CONFIGURACIÓN DE EXPORTACIÓN
-- ========================================

-- true = usar EXIF inventados para pruebas
-- false = extraer EXIF reales de las fotos
Config.USE_MOCK_EXIF = false

-- Parámetros alineados con la compresión iterativa del frontend web.
Config.EXPORT_ENABLE_QUALITY_REDUCTION = true
Config.EXPORT_PARALLEL_VARIANTS = true
-- Lado largo anterior de la main; también fija el presupuesto de bytes del thumb.
local LEGACY_FULL_MAX_SIDE = 1500
Config.EXPORT_FULL_MAX_WIDTH = 1800
Config.EXPORT_FULL_MAX_HEIGHT = 1800
Config.EXPORT_THUMB_MAX_WIDTH = 800
Config.EXPORT_THUMB_MAX_HEIGHT = 800
Config.EXPORT_FULL_MAX_SIZE_BYTES = 512000
Config.EXPORT_THUMB_MAX_SIZE_BYTES = math.floor(
	Config.EXPORT_FULL_MAX_SIZE_BYTES *
	(Config.EXPORT_THUMB_MAX_WIDTH / LEGACY_FULL_MAX_SIDE)
)
Config.EXPORT_JPEG_QUALITY_INITIAL = 0.9
Config.EXPORT_JPEG_QUALITY_DECREMENT = 0.1
Config.EXPORT_JPEG_QUALITY_MIN = 0.1
Config.EXPORT_MAX_ATTEMPTS = 5
Config.EXPORT_SIZE_TOLERANCE_RATIO = 1.08

-- ========================================
-- SAFE SEARCH (moderación de contenido pre-exportación)
-- ========================================
-- Alineado con el frontend web (web/src/config/uploadConfig.js).
-- Antes de exportar se comprueba una muestra aleatoria del lote contra
-- Google Safe Search. Si se detecta contenido inapropiado se aborta.

-- Activa/desactiva por completo el chequeo de Safe Search. Si es false
-- se omite la moderación y se exporta directamente.
Config.SAFE_SEARCH_ENABLED = true
-- Fracción del lote que se muestrea para el chequeo (0–1).
Config.SAFE_SEARCH_SAMPLE_RATIO = 0.75
-- Número mínimo de fotos siempre muestreadas, independientemente del ratio.
Config.SAFE_SEARCH_MIN_SAMPLES = 1
-- Número máximo de fotos muestreadas por lote (el backend acepta hasta 16).
Config.SAFE_SEARCH_MAX_SAMPLES = 6
-- Las imágenes se reducen a este ancho (px) antes del chequeo (payload ligero).
Config.SAFE_SEARCH_MAX_WIDTH = 500
-- Tamaño máximo en bytes por imagen enviada al endpoint (~150 KB).
Config.SAFE_SEARCH_MAX_SIZE_BYTES = 150000

-- ========================================
-- CONFIGURACIÓN DE SUBIDA
-- ========================================

-- Número máximo de reintentos por subida fallida
Config.MAX_RETRIES = 3

-- Número de subidas simultáneas (concurrencia)
Config.CONCURRENT_UPLOADS = 5

-- ========================================
-- CONFIGURACIÓN DE LÍMITES
-- ========================================

-- Número máximo de fotos que se pueden procesar en una sola exportación
Config.MAX_PHOTOS = 5000

return Config
