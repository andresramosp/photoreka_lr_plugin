# Guía de Autenticación - Plugin de Lightroom para Photoreka

## Descripción General

El plugin ahora incluye un sistema de autenticación completo que gestiona el login de usuarios y la persistencia de tokens de forma segura usando las preferencias de Lightroom.

## Componentes

### `AuthService.lua`

Servicio principal que maneja toda la lógica de autenticación:

#### Funciones principales:

- **`AuthService.ensureAuthenticated()`**: Verifica si hay un token guardado, si no, muestra el diálogo de login
- **`AuthService.login(email, password)`**: Realiza el login contra la API
- **`AuthService.showLoginDialog()`**: Muestra el diálogo de login al usuario
- **`AuthService.getStoredToken()`**: Obtiene el token guardado en las preferencias
- **`AuthService.getStoredUserInfo()`**: Obtiene la información del usuario guardada
- **`AuthService.logout()`**: Cierra la sesión y elimina el token
- **`AuthService.showAccountDialog()`**: Muestra información de la cuenta actual

### Persistencia de datos

El plugin usa **`LrPrefs`** (preferencias de Lightroom) para guardar:

1. **Token de autenticación**: Se guarda de forma persistente y sobrevive al cierre de Lightroom
2. **Email del usuario**: Para recordar el último usuario que inició sesión
3. **Nombre del usuario**: Para mostrar información en la UI

Estos datos se guardan en las preferencias del plugin y permanecen entre sesiones.

## Flujo de autenticación

### 1. Primera vez (sin token guardado)

```
Usuario abre el plugin
    ↓
ApiService necesita hacer una petición
    ↓
ApiService llama a getAuthToken()
    ↓
AuthService.ensureAuthenticated() no encuentra token
    ↓
Se muestra el diálogo de login
    ↓
Usuario ingresa email y password
    ↓
Se envía POST a /api/auth/login
    ↓
Si es exitoso:
  - Se guarda el token en LrPrefs
  - Se guarda email y nombre del usuario
  - Se retorna el token
    ↓
ApiService usa el token para sus peticiones
```

### 2. Sesiones posteriores (con token guardado)

```
Usuario abre el plugin
    ↓
ApiService necesita hacer una petición
    ↓
ApiService llama a getAuthToken()
    ↓
AuthService.ensureAuthenticated() encuentra token en LrPrefs
    ↓
Se retorna el token inmediatamente (sin mostrar diálogo)
    ↓
ApiService usa el token para sus peticiones
```

### 3. Cerrar sesión

```
Usuario hace clic en el botón de cuenta (👤)
    ↓
Se muestra AuthService.showAccountDialog()
    ↓
Usuario ve su nombre y email
    ↓
Usuario hace clic en "Cerrar sesión"
    ↓
Se eliminan el token y datos del usuario de LrPrefs
    ↓
Próxima vez que se use el plugin, pedirá login nuevamente
```

## Integración con ApiService

`ApiService.lua` ahora usa `AuthService` para obtener el token:

```lua
local function getAuthToken()
    local token = AuthService.ensureAuthenticated()

    if not token or token == '' then
        error("No se pudo obtener el token de autenticación. El usuario canceló el login.")
    end

    return token
end
```

Este método se llama automáticamente en:

- `requestUploadUrls()`: Al solicitar URLs firmadas para subir fotos
- `triggerProcess()`: Al activar el post-procesamiento

## Interfaz de usuario

### Diálogo de Login

- Campo de **Email** (pre-rellenado si el usuario ya inició sesión antes)
- Campo de **Password** (tipo password para ocultar caracteres)
- Botón **"Iniciar sesión"** (solo habilitado si ambos campos tienen contenido)
- Botón **"Cancelar"**
- Mensaje de error (si el login falla)
- Texto informativo mostrando el último usuario que inició sesión

### Botón de Cuenta en Main.lua

En la ventana principal del plugin:

- Aparece un botón en la esquina superior derecha
- Muestra "👤 Nombre del usuario" si hay sesión activa
- Muestra "👤 Cuenta" si no hay sesión
- Al hacer clic, abre el diálogo de cuenta

### Diálogo de Cuenta

- Muestra el nombre y email del usuario actual
- Botón **"Cerrar sesión"** para terminar la sesión
- Botón **"Cancelar"** para cerrar sin cambios

## Manejo de errores

### Login fallido

Si el login falla (credenciales incorrectas, servidor no disponible, etc.):

1. Se muestra un mensaje de error con el detalle
2. Se vuelve a mostrar el diálogo de login automáticamente
3. El usuario puede reintentar o cancelar

### Token inválido

Si el token guardado ya no es válido (expiró, fue revocado, etc.):

- Actualmente el plugin usará el token guardado
- **Mejora futura**: Agregar validación de token antes de usarlo y pedir re-login si es inválido

### Usuario cancela login

Si el usuario cancela el diálogo de login:

- Se genera un error que detiene la operación
- No se ejecuta la exportación/subida de fotos

## Configuración

La configuración del plugin se centraliza en `Config.lua`. Solo necesitas configurar:

```lua
Config.API_BASE_URL = 'http://localhost:3333'  -- URL de tu API
```

Ya **NO** es necesario configurar `AUTH_TOKEN` manualmente. El token se obtiene automáticamente mediante login.

Para más detalles sobre la configuración, consulta `CONFIG_GUIDE.md`.

## Endpoint de API

El plugin consume el endpoint:

```
POST /api/auth/login
Content-Type: application/json

{
  "email": "usuario@ejemplo.com",
  "password": "contraseña"
}
```

Respuesta esperada (HTTP 200):

```json
{
  "message": "Login successful",
  "user": {
    "id": 1,
    "name": "Usuario Ejemplo",
    "email": "usuario@ejemplo.com",
    "isActive": true
  },
  "token": "oat_xxx.yyy"
}
```

Respuesta de error (HTTP 4xx):

```json
{
  "message": "Credenciales inválidas"
}
```

## Seguridad

### Almacenamiento del token

- El token se guarda en las preferencias de Lightroom (`LrPrefs`)
- Este almacenamiento es local en el equipo del usuario
- No se transmite a ningún servidor excepto en las peticiones autorizadas

### Password

- El password **nunca** se guarda localmente
- Solo se usa para el login y luego se descarta
- Se transmite por HTTPS (asegúrate de usar HTTPS en producción)

### Recomendaciones

1. **Usar HTTPS en producción**: Cambia `http://localhost:3333` a `https://tu-dominio.com`
2. **Tokens con expiración**: Considera implementar tokens JWT con tiempo de expiración
3. **Validación de token**: Agregar un endpoint para validar si el token sigue siendo válido
4. **Refresh tokens**: Implementar refresh tokens para renovar el acceso sin pedir password nuevamente

## Testing

Para probar el sistema de autenticación:

1. **Primera ejecución**:

   - Abre el plugin en Lightroom
   - Debería mostrarse el diálogo de login automáticamente
   - Ingresa tus credenciales
   - Verifica que el token se guarde correctamente

2. **Cerrar y reabrir Lightroom**:

   - El plugin debería funcionar sin pedir login nuevamente
   - Verifica que el botón de cuenta muestre tu nombre

3. **Cerrar sesión**:

   - Haz clic en el botón de cuenta
   - Cierra sesión
   - Verifica que la próxima vez pida login nuevamente

4. **Credenciales incorrectas**:
   - Ingresa un email o password incorrecto
   - Verifica que se muestre el mensaje de error
   - Verifica que se pueda reintentar

## Mejoras futuras

- [ ] Validación de token antes de cada petición importante
- [ ] Refresh token para renovar acceso sin re-login
- [ ] Opción de "Recordarme" (checkbox en el login)
- [ ] Timeout de sesión configurable
- [ ] Mejor manejo de errores de red
- [ ] Indicador visual de estado de conexión
- [ ] Modo offline con sincronización posterior
