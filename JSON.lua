-- JSON.lua - Librería JSON simple para Lua
-- Basada en json.lua de rxi (MIT License)

local JSON = {}

-- Caracteres especiales
local escape_char_map = {
  ["\\"] = "\\\\",
  ["\""] = "\\\"",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

local function escape_char(c)
  return escape_char_map[c] or string.format("\\u%04x", c:byte())
end

local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function encode_table(val, stack)
  local res = {}
  stack = stack or {}

  -- Detectar referencias circulares
  if stack[val] then error("circular reference") end
  stack[val] = true

  -- Determinar si es array o objeto
  local is_array = true
  local n = 0
  for k in pairs(val) do
    if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
      is_array = false
      break
    end
    n = n + 1
  end
  
  if is_array then
    -- Codificar como array
    for i = 1, n do
      table.insert(res, JSON.encode(val[i], stack))
    end
    stack[val] = nil
    return "[" .. table.concat(res, ",") .. "]"
  else
    -- Codificar como objeto
    for k, v in pairs(val) do
      if type(k) ~= "string" then
        error("invalid key type: " .. type(k))
      end
      table.insert(res, encode_string(k) .. ":" .. JSON.encode(v, stack))
    end
    stack[val] = nil
    return "{" .. table.concat(res, ",") .. "}"
  end
end

function JSON.encode(val, stack)
  local t = type(val)
  
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return val and "true" or "false"
  elseif t == "number" then
    return tostring(val)
  elseif t == "string" then
    return encode_string(val)
  elseif t == "table" then
    return encode_table(val, stack)
  else
    error("invalid type: " .. t)
  end
end

-- Decodificador simple
local function decode_error(str, idx, msg)
  error(string.format("Decode error at position %d: %s", idx, msg))
end

local function skip_whitespace(str, idx)
  while idx <= #str do
    local c = str:sub(idx, idx)
    if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then
      break
    end
    idx = idx + 1
  end
  return idx
end

local function decode_value(str, idx)
  idx = skip_whitespace(str, idx)
  local c = str:sub(idx, idx)
  
  if c == "{" then
    return decode_object(str, idx)
  elseif c == "[" then
    return decode_array(str, idx)
  elseif c == "\"" then
    return decode_string(str, idx)
  elseif c == "t" or c == "f" then
    return decode_boolean(str, idx)
  elseif c == "n" then
    return decode_null(str, idx)
  else
    return decode_number(str, idx)
  end
end

function decode_object(str, idx)
  local obj = {}
  idx = idx + 1 -- skip '{'
  
  while true do
    idx = skip_whitespace(str, idx)
    
    -- Check for end
    if str:sub(idx, idx) == "}" then
      return obj, idx + 1
    end
    
    -- Decode key
    local key
    key, idx = decode_string(str, idx)
    
    -- Skip colon
    idx = skip_whitespace(str, idx)
    if str:sub(idx, idx) ~= ":" then
      decode_error(str, idx, "expected ':'")
    end
    idx = idx + 1
    
    -- Decode value
    local val
    val, idx = decode_value(str, idx)
    obj[key] = val
    
    -- Check for comma or end
    idx = skip_whitespace(str, idx)
    local c = str:sub(idx, idx)
    if c == "}" then
      return obj, idx + 1
    elseif c == "," then
      idx = idx + 1
    else
      decode_error(str, idx, "expected ',' or '}'")
    end
  end
end

function decode_array(str, idx)
  local arr = {}
  idx = idx + 1 -- skip '['
  
  while true do
    idx = skip_whitespace(str, idx)
    
    -- Check for end
    if str:sub(idx, idx) == "]" then
      return arr, idx + 1
    end
    
    -- Decode value
    local val
    val, idx = decode_value(str, idx)
    table.insert(arr, val)
    
    -- Check for comma or end
    idx = skip_whitespace(str, idx)
    local c = str:sub(idx, idx)
    if c == "]" then
      return arr, idx + 1
    elseif c == "," then
      idx = idx + 1
    else
      decode_error(str, idx, "expected ',' or ']'")
    end
  end
end

function decode_string(str, idx)
  local s = ""
  idx = idx + 1 -- skip opening quote
  
  while true do
    local c = str:sub(idx, idx)
    if c == "" then
      decode_error(str, idx, "unexpected end of string")
    end
    
    if c == "\"" then
      return s, idx + 1
    elseif c == "\\" then
      idx = idx + 1
      c = str:sub(idx, idx)
      if c == "\"" or c == "\\" or c == "/" then
        s = s .. c
      elseif c == "b" then s = s .. "\b"
      elseif c == "f" then s = s .. "\f"
      elseif c == "n" then s = s .. "\n"
      elseif c == "r" then s = s .. "\r"
      elseif c == "t" then s = s .. "\t"
      else
        decode_error(str, idx, "invalid escape sequence")
      end
    else
      s = s .. c
    end
    idx = idx + 1
  end
end

function decode_number(str, idx)
  local s = ""
  while idx <= #str do
    local c = str:sub(idx, idx)
    if c:match("[%d%.eE%+%-]") then
      s = s .. c
      idx = idx + 1
    else
      break
    end
  end
  return tonumber(s), idx
end

function decode_boolean(str, idx)
  if str:sub(idx, idx + 3) == "true" then
    return true, idx + 4
  elseif str:sub(idx, idx + 4) == "false" then
    return false, idx + 5
  else
    decode_error(str, idx, "invalid boolean")
  end
end

function decode_null(str, idx)
  if str:sub(idx, idx + 3) == "null" then
    return nil, idx + 4
  else
    decode_error(str, idx, "invalid null")
  end
end

function JSON.decode(str)
  if type(str) ~= "string" then
    error("expected string, got " .. type(str))
  end
  local val, idx = decode_value(str, 1)
  idx = skip_whitespace(str, idx)
  if idx <= #str then
    decode_error(str, idx, "trailing garbage")
  end
  return val
end

return JSON
