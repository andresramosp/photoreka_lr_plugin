-- AuthService.lua - Servicio de autenticación y gestión de tokens
local LrHttp = import 'LrHttp'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrFunctionContext = import 'LrFunctionContext'
local LrPrefs = import 'LrPrefs'
local LrLogger = import 'LrLogger'

local JSON = require 'JSON'
local Config = require 'Config'

local AuthService = {}

-- Configurar logger
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

-- Clave para almacenar el token en preferencias
local TOKEN_PREF_KEY = 'photoreka_auth_token'
local USER_EMAIL_PREF_KEY = 'photoreka_user_email'
local USER_NAME_PREF_KEY = 'photoreka_user_name'

log:info("AuthService cargado")

-- Obtiene el token almacenado en las preferencias
-- Retorna: token string o nil si no existe
function AuthService.getStoredToken()
    local prefs = LrPrefs.prefsForPlugin()
    local token = prefs[TOKEN_PREF_KEY]
    
    if token and token ~= '' then
        log:info("Token encontrado en preferencias")
        return token
    end
    
    log:info("No hay token almacenado")
    return nil
end

-- Guarda el token y datos del usuario en las preferencias
-- Parámetros:
--   token: string del token
--   userData: tabla con {email, name}
local function storeToken(token, userData)
    local prefs = LrPrefs.prefsForPlugin()
    prefs[TOKEN_PREF_KEY] = token
    
    if userData then
        prefs[USER_EMAIL_PREF_KEY] = userData.email
        prefs[USER_NAME_PREF_KEY] = userData.name
    end
    
    log:info("Token y datos de usuario guardados en preferencias")
end

-- Obtiene información del usuario almacenada
-- Retorna: tabla con {email, name} o nil
function AuthService.getStoredUserInfo()
    local prefs = LrPrefs.prefsForPlugin()
    local email = prefs[USER_EMAIL_PREF_KEY]
    local name = prefs[USER_NAME_PREF_KEY]
    
    if email then
        return {
            email = email,
            name = name
        }
    end
    
    return nil
end

-- Elimina el token y datos del usuario de las preferencias
function AuthService.clearStoredToken()
    local prefs = LrPrefs.prefsForPlugin()
    prefs[TOKEN_PREF_KEY] = nil
    prefs[USER_EMAIL_PREF_KEY] = nil
    prefs[USER_NAME_PREF_KEY] = nil
    
    log:info("Token y datos de usuario eliminados de preferencias")
end

-- Realiza el login contra la API
-- Parámetros:
--   email: string
--   password: string
-- Retorna: tabla con {success = true/false, token = string, user = {...}, error = string}
function AuthService.login(email, password)
    if not Config.API_BASE_URL then
        log:error("API_BASE_URL no está configurada")
        return {
            success = false,
            error = "API_BASE_URL no está configurada"
        }
    end
    
    local url = Config.API_BASE_URL .. "/api/auth/login"
    
    local payload = {
        email = email,
        password = password
    }
    
    log:info("Intentando login para: " .. email)
    
    local headers = {
        { field = "Content-Type", value = "application/json" }
    }
    
    local body = JSON.encode(payload)
    local response, responseHeaders = LrHttp.post(url, body, headers)
    
    if not response then
        log:error("No response from server")
        return {
            success = false,
            error = "No se pudo conectar con el servidor"
        }
    end
    
    -- Verificar código de estado
    local statusCode = 200
    if responseHeaders and responseHeaders.status then
        statusCode = tonumber(responseHeaders.status)
        log:info("Login response status: " .. tostring(statusCode))
    end
    
    if statusCode < 200 or statusCode >= 300 then
        log:error("Login failed with status " .. tostring(statusCode))
        
        -- Intentar decodificar el mensaje de error
        local errorMessage = "Credenciales inválidas"
        local success, errorData = pcall(function()
            return JSON.decode(response)
        end)
        
        if success and errorData and errorData.message then
            errorMessage = errorData.message
        end
        
        return {
            success = false,
            error = errorMessage
        }
    end
    
    -- Decodificar respuesta exitosa
    local success, responseData = pcall(function()
        return JSON.decode(response)
    end)
    
    if not success then
        log:error("Failed to decode login response")
        return {
            success = false,
            error = "Respuesta inválida del servidor"
        }
    end
    
    if not responseData.token then
        log:error("No token in response")
        return {
            success = false,
            error = "El servidor no devolvió un token válido"
        }
    end
    
    log:info("Login exitoso para: " .. email)
    
    -- Guardar token y datos del usuario
    storeToken(responseData.token, {
        email = responseData.user.email,
        name = responseData.user.name
    })
    
    return {
        success = true,
        token = responseData.token,
        user = responseData.user
    }
end

-- Muestra el diálogo de login y realiza la autenticación
-- Retorna: token string o nil si el usuario cancela
function AuthService.showLoginDialog()
    local LrTasks = import 'LrTasks'
    
    return LrFunctionContext.callWithContext('loginDialog', function(context)
        local f = LrView.osFactory()
        local properties = LrBinding.makePropertyTable(context)
        
        -- Intentar cargar email guardado
        local storedUserInfo = AuthService.getStoredUserInfo()
        properties.email = (storedUserInfo and storedUserInfo.email) or ''
        properties.password = ''
        properties.errorMessage = ''
        properties.loginInProgress = false
        
        local dialogContent = f:column {
            bind_to_object = properties,  -- CLAVE: enlazar el dialog a properties
            spacing = f:control_spacing(),
            
            -- Logo grande centrado
            f:row {
                fill_horizontal = 1,
                
                f:spacer { fill_horizontal = 1 },
                
                f:picture {
                    value = _PLUGIN.path .. '/logo_full.png',
                    height = 80
                },
                
                f:spacer { fill_horizontal = 1 },
            },
            
            f:spacer { height = 2 },
            
            f:static_text {
                title = 'Sign in to Photoreka',
                font = '<system/bold>',
            },
            
            f:separator { fill_horizontal = 1 },
            
            f:spacer { height = 8 },
            
            f:row {
                fill_horizontal = 1,
                
                f:spacer { fill_horizontal = 1 },
                
                f:column {
                    spacing = f:control_spacing(),
                    
                    f:row {
                        spacing = f:label_spacing(),
                        
                        f:static_text {
                            title = 'Email:',
                            alignment = 'right',
                            width = LrView.share('label_width'),
                        },
                        
                        f:edit_field {
                            value = LrView.bind('email'),
                            width_in_chars = 30,
                            immediate = true,
                            enabled = LrView.bind {
                                key = 'loginInProgress',
                                transform = function(value) return not value end,
                            },
                        },
                    },
                    
                    f:row {
                        spacing = f:label_spacing(),
                        
                        f:static_text {
                            title = 'Password:',
                            alignment = 'right',
                            width = LrView.share('label_width'),
                        },
                        
                        f:password_field {
                            value = LrView.bind('password'),
                            width_in_chars = 30,
                            immediate = true,
                            enabled = LrView.bind {
                                key = 'loginInProgress',
                                transform = function(value) return not value end,
                            },
                        },
                    },
                },
                
                f:spacer { fill_horizontal = 1 },
            },
            
            -- Mensaje de error
            f:row {
                visible = LrView.bind {
                    key = 'errorMessage',
                    transform = function(value, fromTable)
                        return value and value ~= ''
                    end,
                },
                
                f:static_text {
                    title = LrView.bind('errorMessage'),
                    text_color = LrView.kRedColor,
                    font = '<system/small>',
                    width = 400,
                    height_in_lines = 2,
                    fill_horizontal = 1,
                },
            },
            
           
            
            -- Info de usuario guardado
            f:row {
                visible = storedUserInfo ~= nil,
                
                f:static_text {
                    title = storedUserInfo and string.format('Usuario anterior: %s', storedUserInfo.name or storedUserInfo.email) or '',
                    font = '<system/small>',
                    text_color = LrView.kLabelColor,
                },
            },
        }
        
        local result = LrDialogs.presentModalDialog({
            title = 'Photoreka Login',
            contents = dialogContent,
            actionVerb = 'Login',
            cancelVerb = 'Cancel',
            save_frame = 'loginDialog',
            actionBinding = {
                enabled = LrView.bind {
                    keys = { 'email', 'password', 'loginInProgress' },
                    operation = function(binder, values, fromTable)
                        return values.email and values.email ~= '' 
                            and values.password and values.password ~= ''
                            and not values.loginInProgress
                    end,
                },
            },
        })
        
        if result == 'ok' then
            -- El diálogo se cerró con OK, hacer login ahora con los valores que tenemos
            local email = properties.email
            local password = properties.password
            
            log:info("Diálogo cerrado, intentando login con: [" .. tostring(email) .. "]")
            log:info("Password length: " .. tostring(password and #password or 0))
            
            local loginResult = AuthService.login(email, password)
            
            if loginResult.success then
                log:info("Login exitoso")
                return loginResult.token
            else
                -- Mostrar error y volver a intentar
                log:error("Login falló: " .. tostring(loginResult.error))
                LrDialogs.message(
                    'Error de autenticación',
                    loginResult.error or 'Credenciales inválidas',
                    'critical'
                )
                -- Volver a mostrar el diálogo
                return AuthService.showLoginDialog()
            end
        end
        
        log:info("Usuario canceló el login")
        return nil
    end)
end

-- Valida si hay un token disponible, si no, muestra el diálogo de login
-- Retorna: token string o nil si el usuario cancela
function AuthService.ensureAuthenticated()
    -- Primero intentar obtener token guardado
    local token = AuthService.getStoredToken()
    
    if token then
        log:info("Token existente encontrado")
        return token
    end
    
    log:info("No hay token, mostrando diálogo de login")
    
    -- Si no hay token, mostrar diálogo de login
    return AuthService.showLoginDialog()
end

-- Verifica si el token actual es válido (opcional, para validación adicional)
-- Esta función podría expandirse para hacer una validación real contra el servidor
-- Parámetros:
--   token: string del token a validar
-- Retorna: true si es válido, false si no
function AuthService.validateToken(token)
    -- Por ahora solo verificamos que exista y no esté vacío
    -- Podrías agregar una llamada al servidor para validar el token
    return token and token ~= ''
end

-- Cierra la sesión actual (elimina token y datos del usuario)
function AuthService.logout()
    AuthService.clearStoredToken()
    log:info("Sesión cerrada")
end

-- Muestra un diálogo con información del usuario y opción de cerrar sesión
-- Retorna: true si el usuario cerró sesión, false si canceló
function AuthService.showAccountDialog()
    return LrFunctionContext.callWithContext('accountDialog', function(context)
        local userInfo = AuthService.getStoredUserInfo()
        
        if not userInfo then
            LrDialogs.message(
                'No active session',
                'There is no authenticated user.',
                'info'
            )
            return false
        end
        
        local f = LrView.osFactory()
        
        local dialogContent = f:column {
            spacing = f:control_spacing(),
            
            -- Logo pequeño
            f:row {
                fill_horizontal = 1,
                
                f:picture {
                    value = _PLUGIN.path .. '/logo_full.png',
                    height = 100,
                },
            },
            
            f:spacer { height = 10 },
            
            f:static_text {
                title = 'Photoreka Account',
                font = '<system/bold>',
            },
            
            f:separator { fill_horizontal = 1 },
            
            f:spacer { height = 10 },
            
            f:row {
                spacing = f:label_spacing(),
                
                f:static_text {
                    title = 'User:',
                    alignment = 'right',
                    width = 80,
                },
                
                f:static_text {
                    title = userInfo.name or 'N/A',
                    font = '<system/bold>',
                },
            },
            
            f:row {
                spacing = f:label_spacing(),
                
                f:static_text {
                    title = 'Email:',
                    alignment = 'right',
                    width = 80,
                },
                
                f:static_text {
                    title = userInfo.email or 'N/A',
                },
            },
            

        }
        
        local result = LrDialogs.presentModalDialog({
            title = 'Account',
            contents = dialogContent,
            actionVerb = 'Logout',
            cancelVerb = 'Cancel',
        })
        
        if result == 'ok' then
            AuthService.logout()
            LrDialogs.message(
                 'Session closed',
                 'You have successfully logged out.',
                 'info'
            )
            return true
        end
        
        return false
    end)
end

return AuthService
