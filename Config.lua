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
Config.EXPORT_FULL_MAX_WIDTH = 1500
Config.EXPORT_FULL_MAX_HEIGHT = 1500
Config.EXPORT_THUMB_MAX_WIDTH = 800
Config.EXPORT_THUMB_MAX_HEIGHT = 800
Config.EXPORT_FULL_MAX_SIZE_BYTES = 512000
Config.EXPORT_THUMB_MAX_SIZE_BYTES = math.floor(
	Config.EXPORT_FULL_MAX_SIZE_BYTES *
	(Config.EXPORT_THUMB_MAX_WIDTH / Config.EXPORT_FULL_MAX_WIDTH)
)
Config.EXPORT_JPEG_QUALITY_INITIAL = 0.9
Config.EXPORT_JPEG_QUALITY_DECREMENT = 0.1
Config.EXPORT_JPEG_QUALITY_MIN = 0.1
Config.EXPORT_MAX_ATTEMPTS = 5
Config.EXPORT_SIZE_TOLERANCE_RATIO = 1.08

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
