-- AuthService.lua - Servicio de autenticación y gestión de tokens
local LrHttp = import 'LrHttp'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrFunctionContext = import 'LrFunctionContext'
local LrPrefs = import 'LrPrefs'
local LrLogger = import 'LrLogger'
local LrTasks = import 'LrTasks'

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
-- Cache de validación de sesión: true cuando el token ya fue verificado contra
-- el servidor en esta sesión. Se resetea al cambiar/borrar el token.
local _tokenValidated = false
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
    
    -- Token recién obtenido del servidor: marcarlo como validado sin HTTP extra.
    _tokenValidated = true
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
    _tokenValidated = false
    log:info("Token y datos de usuario eliminados de preferencias")
end

-- Invalida la cache de validación sin borrar el token.
-- Llamar cuando una petición API devuelve 401, para forzar re-validación.
function AuthService.invalidateToken()
    _tokenValidated = false
    log:info('Token marcado como no validado (posible 401 recibido)')
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

-- ─── Device Authorization Flow (Google / browser-based login) ────────────────

-- Crea una sesión pendiente en el backend para el flujo de login con navegador.
-- Retorna: tabla con {sessionId, expiresInSeconds} o nil en caso de error
local function createDeviceSession()
    local url = Config.API_BASE_URL .. '/api/auth_lr/create-device-session'
    local response, headers = LrHttp.post(url, '{}', {
        { field = 'Content-Type', value = 'application/json' }
    })

    if not response then
        log:error("createDeviceSession: no response from server")
        return nil
    end

    local statusCode = 200
    if headers and headers.status then
        statusCode = tonumber(headers.status) or 200
    end

    if statusCode < 200 or statusCode >= 300 then
        log:error("createDeviceSession: server error " .. tostring(statusCode))
        return nil
    end

    local ok, data = pcall(function() return JSON.decode(response) end)
    if not ok or not data or not data.sessionId then
        log:error("createDeviceSession: invalid response")
        return nil
    end

    log:info("Device session created: " .. data.sessionId)
    return data
end

-- Consulta el backend para ver si el usuario ya completó el login en el navegador.
-- Retorna: tabla con {status, token, user} o nil en caso de error de red
local function pollDeviceSession(sessionId)
    local url = Config.API_BASE_URL .. '/api/auth_lr/poll-device-session?sessionId=' .. sessionId
    local response, headers = LrHttp.get(url, {})

    if not response then
        log:warn("pollDeviceSession: no response")
        return nil
    end

    local statusCode = 200
    if headers and headers.status then
        statusCode = tonumber(headers.status) or 200
    end

    if statusCode < 200 or statusCode >= 300 then
        return nil
    end

    local ok, data = pcall(function() return JSON.decode(response) end)
    if not ok or not data then return nil end

    return data
end

-- Abre el navegador para que el usuario se autentique (Google u otro método web).
-- El plugin muestra un diálogo de espera y sondea el backend hasta obtener el token.
-- Retorna: token string o nil si el usuario cancela o hay error
function AuthService.loginWithBrowser()
    -- 1. Crear sesión pendiente
    local sessionData = createDeviceSession()
    if not sessionData then
        LrDialogs.message(
            'Connection error',
            'Could not contact the Photoreka server. Please check your internet connection.',
            'critical'
        )
        return nil
    end

    -- 2. Abrir navegador en la página de autenticación
    local loginUrl = Config.APP_BASE_URL .. '/lr-auth?session=' .. sessionData.sessionId
    log:info("Opening browser for device auth: " .. loginUrl)
    LrHttp.openUrlInBrowser(loginUrl)

    -- 3. Mostrar diálogo de espera
    local f = LrView.osFactory()
    local dialogContent = f:column {
        spacing = f:control_spacing(),

        f:row {
            fill_horizontal = 1,
            f:spacer { fill_horizontal = 1 },
            f:picture {
                value = _PLUGIN.path .. '/logo_full.png',
                height = 70,
            },
            f:spacer { fill_horizontal = 1 },
        },

        f:spacer { height = 8 },

        f:static_text {
            title = 'Sign in with Google',
            font = '<system/bold>',
        },

        f:separator { fill_horizontal = 1 },

        f:spacer { height = 8 },

        f:static_text {
            title = 'A browser window has been opened so you can sign in\nwith your Google account.\n\nOnce you have completed the sign-in, click "Done".',
            width = 360,
            height_in_lines = 4,
        },

        f:spacer { height = 6 },

        f:static_text {
            title = 'The session link expires in 10 minutes.',
            font = '<system/small>',
            text_color = LrView.kLabelColor,
        },
    }

    local result = LrDialogs.presentModalDialog({
        title = 'Browser Login',
        contents = dialogContent,
        actionVerb = 'Done',
        cancelVerb = 'Cancel',
    })

    if result ~= 'ok' then
        log:info("loginWithBrowser: user cancelled")
        return nil
    end

    -- 4. Sondear el backend (hasta 12 intentos ≈ ~12 s con latencia de red)
    log:info("loginWithBrowser: polling for token...")
    local token = nil
    for i = 1, 12 do
        local pollResult = pollDeviceSession(sessionData.sessionId)
        if pollResult then
            if pollResult.status == 'completed' then
                storeToken(pollResult.token, pollResult.user)
                token = pollResult.token
                log:info("loginWithBrowser: token received on attempt " .. tostring(i))
                break
            elseif pollResult.status == 'expired' then
                log:warn("loginWithBrowser: session expired")
                break
            end
        end
        -- Small yield between retries (only available inside LrTasks context)
        if i < 12 then
            local ok = pcall(function() LrTasks.sleep(1) end)
            if not ok then break end
        end
    end

    if not token then
        local retry = LrDialogs.confirm(
            'Login not detected',
            'The sign-in could not be confirmed. Did you complete the Google login in the browser?\n\nClick "Try Again" to check once more.',
            'Try Again',
            'Cancel'
        )
        if retry == 'ok' then
            -- One last attempt
            local pollResult = pollDeviceSession(sessionData.sessionId)
            if pollResult and pollResult.status == 'completed' then
                storeToken(pollResult.token, pollResult.user)
                token = pollResult.token
            else
                LrDialogs.message(
                    'Login failed',
                    'Could not confirm your sign-in. Please try again from the beginning.',
                    'critical'
                )
            end
        end
    end

    return token
end

-- ─────────────────────────────────────────────────────────────────────────────

-- Muestra el diálogo de login y realiza la autenticación
-- Retorna: token string o nil si el usuario cancela
function AuthService.showLoginDialog()
    -- LrTasks already imported at top of file
    
    return LrFunctionContext.callWithContext('loginDialog', function(context)
        local f = LrView.osFactory()
        local properties = LrBinding.makePropertyTable(context)
        
        -- Intentar cargar email guardado
        local storedUserInfo = AuthService.getStoredUserInfo()
        properties.email = (storedUserInfo and storedUserInfo.email) or ''
        properties.password = ''
        properties.errorMessage = ''
        properties.loginInProgress = false

        -- Track if Google login was chosen (set from inside the button action)
        local googleLoginRequested = false
        
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
            
            f:spacer { height = 8 },
            
            -- Enlace de registro
            f:row {
                fill_horizontal = 1,
                
                f:spacer { fill_horizontal = 1 },
                
                f:static_text {
                    title = "Don't have an account? ",
                    font = '<system/small>',
                },
                
                f:push_button {
                    title = 'Register on Photoreka',
                    font = '<system/small>',
                    action = function()
                        LrHttp.openUrlInBrowser(Config.APP_BASE_URL .. '/auth')
                    end,
                },
                
                f:spacer { fill_horizontal = 1 },
            },

            f:separator { fill_horizontal = 1 },

            f:spacer { height = 4 },

            -- Botón "Sign in with Google" con icono
            f:row {
                fill_horizontal = 1,

                f:spacer { fill_horizontal = 1 },

                f:picture {
                    value = _PLUGIN.path .. '/google_icon.png',
                    width = 18,
                    height = 18,
                },

                f:spacer { width = 6 },

                f:push_button {
                    title = 'Sign in with Google',
                    action = function(button)
                        googleLoginRequested = true
                        LrDialogs.stopModalWithResult(button, 'ok')
                    end,
                },

                f:spacer { fill_horizontal = 1 },
            },

            f:spacer { height = 2 },
            
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

        -- Google login button was clicked inside the dialog
        if result == 'ok' and googleLoginRequested then
            return AuthService.loginWithBrowser()
        end
        
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
-- Valida el token contra el servidor de forma silente.
-- Retorna: true si es válido, false si ha caducado o hay error de red.
local function isTokenValid(token)
    local url = Config.API_BASE_URL .. '/api/usage'
    local headers = { { field = 'Authorization', value = 'Bearer ' .. token } }
    local ok, response, responseHeaders = pcall(function()
        return LrHttp.get(url, headers)
    end)
    if not ok or not responseHeaders then
        -- Server unreachable: fail closed so the user is asked to log in again.
        -- (A reachable server that rejects the token also falls through to the
        --  status-code check below, so this branch is truly "no response at all".)
        log:warn('isTokenValid: server unreachable or no response, treating token as invalid')
        return false
    end
    local statusCode = tonumber(responseHeaders.status) or 0
    if statusCode >= 200 and statusCode < 300 then
        log:info('isTokenValid: token accepted by server (' .. tostring(statusCode) .. ')')
        return true
    end
    log:info('isTokenValid: token rejected by server (' .. tostring(statusCode) .. ')')
    return false
end

function AuthService.ensureAuthenticated()
    -- Primero intentar obtener token guardado
    local token = AuthService.getStoredToken()

    if token then
        if _tokenValidated then
            -- Ya validado en esta sesión: reutilizar sin HTTP extra.
            log:info('Token en caché, reutilizando sin re-validar')
            return token
        end

        -- Primera vez que vemos este token en la sesión: validar contra el servidor.
        if isTokenValid(token) then
            log:info('Token existente encontrado y validado')
            _tokenValidated = true
            return token
        end
        -- Token rechazado: limpiar y pedir login
        log:info('Token rechazado por el servidor, solicitando nuevo login')
        AuthService.clearStoredToken()  -- también resetea _tokenValidated
    else
        log:info('No hay token, mostrando diálogo de login')
    end

    return AuthService.showLoginDialog()
end

-- Verifica si el token actual es válido (opcional, para validación adicional)
-- Parámetros:
--   token: string del token a validar
-- Retorna: true si es válido, false si no
function AuthService.validateToken(token)
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
