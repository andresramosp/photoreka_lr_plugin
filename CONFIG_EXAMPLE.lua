-- ⚠️ EJEMPLO DE CONFIGURACIÓN - NO USES ESTE ARCHIVO DIRECTAMENTE
-- 
-- Este es un ejemplo de cómo debe verse ApiService.lua después de configurarlo.
-- NO copies este archivo, sino que EDITA el archivo ApiService.lua original.

-- ========================================
-- CONFIGURACIÓN - EDITAR ESTAS VARIABLES
-- ========================================

-- 🔑 TOKEN (OBLIGATORIO)
-- Obtén tu token desde: https://www.photoreka.com/profile
ApiService.AUTH_TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c'

-- 🌐 API URLs (cambiar solo si usas entorno de desarrollo)
ApiService.API_BASE_URL = 'https://api.photoreka.com'
ApiService.ANALYZER_API_BASE_URL = 'https://analyzer.photoreka.com'

-- Para entorno local/desarrollo:
-- ApiService.API_BASE_URL = 'http://localhost:3000'
-- ApiService.ANALYZER_API_BASE_URL = 'http://localhost:3001'

-- 📸 EXIF (para pruebas iniciales, usar mock)
ApiService.USE_MOCK_EXIF = true  -- true = EXIF inventados, false = EXIF reales

-- Después de validar que funciona con mock, cambiar a:
-- ApiService.USE_MOCK_EXIF = false

-- ========================================

-- Configuración de comportamiento (opcional)
ApiService.BATCH_SIZE = 5  -- Fotos por lote (reservado)
ApiService.MAX_RETRIES = 3  -- Reintentos por subida

-- Para conexiones lentas, aumentar reintentos:
-- ApiService.MAX_RETRIES = 5

-- ========================================
-- FIN DE CONFIGURACIÓN
-- ========================================

-- 📋 CHECKLIST ANTES DE USAR:
-- [ ] ¿Copiaste tu token real en AUTH_TOKEN?
-- [ ] ¿Las URLs de API son correctas?
-- [ ] ¿USE_MOCK_EXIF está en true para primera prueba?
-- [ ] ¿Guardaste el archivo y reiniciaste Lightroom?

-- ✅ Si respondiste SÍ a todo, ¡estás listo para probar!
