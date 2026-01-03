# 📸 Photoreka Catalog - Cómo ver tus fotos analizadas

## ✨ Nuevo en esta versión

Tu plugin ahora puede **marcar automáticamente** las fotos que has analizado con Photoreka, permitiéndote ver tu "Catálogo Photoreka" directamente en Lightroom.

## 🎯 Cómo funciona

1. **Cada vez que exportas fotos** a Photoreka, el plugin las marca automáticamente con un metadato interno
2. Este metadato (`photorekaanalyzed`) te permite filtrar y ver solo las fotos analizadas
3. La mejor forma de visualizarlo es crear una **Smart Collection** que se actualiza automáticamente

## 🚀 Configuración inicial (solo una vez)

### Paso 1: Crear la Smart Collection

1. Ve al módulo **Library** en Lightroom
2. En el panel izquierdo, haz clic derecho en **"Smart Collections"**
3. Selecciona **"Create Smart Collection..."**
4. Configura:
   - **Name:** `📸 Photoreka Analyzed Photos` (o el nombre que prefieras)
   - **Match:** `all` de las siguientes reglas
   - **Rule:** `Analyzed by Photoreka` → `is` → `Yes`
5. Haz clic en **"Create"**

¡Listo! Ahora verás esta colección siempre en tu panel izquierdo.

### Paso 2: Usar la Smart Collection

**Forma rápida:**

- Ve a `Library > Plug-in Extras > Show Photoreka Catalog`
- Esto activará automáticamente tu colección (si existe)

**Forma manual:**

- Simplemente haz clic en la Smart Collection en el panel izquierdo

## 📊 Lo que verás

- **Contador en tiempo real**: La Smart Collection muestra cuántas fotos has analizado (ej: `📸 Photoreka Analyzed Photos (127)`)
- **Actualización automática**: Cada vez que analices nuevas fotos, aparecerán automáticamente en esta colección
- **Sin duplicados**: Solo muestra fotos de tu catálogo que Photoreka ha procesado

## 🔍 Filtrar dentro del catálogo Photoreka

Una vez dentro de la Smart Collection, puedes usar los filtros normales de Lightroom:

- Por fecha
- Por cámara
- Por rating
- Por keywords
- etc.

## ❓ FAQ

**¿Modifica mis archivos originales?**
No. El metadato solo existe en el catálogo de Lightroom, no toca los archivos ni el XMP.

**¿Puedo desmarcar fotos manualmente?**
Sí. En el panel de metadatos, busca "Analyzed by Photoreka" y cámbialo a "No".

**¿Qué pasa si borro la Smart Collection?**
Nada. Las fotos siguen marcadas. Puedes recrear la colección en cualquier momento siguiendo los pasos de arriba.

**¿Puedo crear múltiples Smart Collections con este metadato?**
Sí. Por ejemplo, puedes crear una que combine "Analyzed by Photoreka = Yes" + "Rating ≥ 4" para ver solo tus mejores fotos analizadas.

## 🎨 Personalización

Puedes personalizar el nombre y el ícono de tu Smart Collection:

- Haz clic derecho sobre ella → `Rename...`
- Emojis recomendados: 📸 🔍 ⭐ 🎨 📷

## 🆘 Soporte

Si la Smart Collection no aparece o tienes problemas:

1. Verifica que has analizado al menos una foto
2. Asegúrate de haber creado la regla correctamente (`Analyzed by Photoreka` → `is` → `Yes`)
3. Recarga el plugin (Archivo > Administrador de complementos > Recargar)

---

**Nota técnica:** Este sistema es completamente persistente y sobrevivirá a reinicios de Lightroom, actualizaciones del plugin, y respaldos del catálogo.
