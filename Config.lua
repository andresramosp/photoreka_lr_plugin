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


-- URL de la API del Analyzer (normalmente la misma que API_BASE_URL)
-- Config.ANALYZER_API_BASE_URL = 'http://localhost:3333'
Config.ANALYZER_API_BASE_URL = 'https://photorekaanalyzerapi-production.up.railway.app'


-- ========================================
-- CONFIGURACIÓN DE EXPORTACIÓN
-- ========================================

-- true = usar EXIF inventados para pruebas
-- false = extraer EXIF reales de las fotos
Config.USE_MOCK_EXIF = true

-- ========================================
-- CONFIGURACIÓN DE SUBIDA
-- ========================================

-- Número máximo de reintentos por subida fallida
Config.MAX_RETRIES = 3

-- Número de subidas simultáneas (concurrencia)
Config.CONCURRENT_UPLOADS = 5

return Config
