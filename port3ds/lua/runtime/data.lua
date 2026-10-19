-- Game data access: master tables (Resources.Load), localized text, and ES3 save files.
local core = require("runtime.core")
local List = core.List
local classes = core.classes

local data = { lang = "es" }
local masters, texts

local LANG_SUFFIX = { "Jp", "JP", "En", "EN", "Cn", "Ch", "Ko", "Tw", "Vn", "VN", "Fr", "It", "Ge", "Sp", "Ru" }
-- LanguageType value used by the game code for each port language
data.LANG_ENUM = { es = "SP", en = "EN", ja = "JP" }

function data.load(lang)
  data.lang = lang or data.lang
  masters = masters or require("data.masters")
  texts = dofile(sys.data .. "text/" .. data.lang .. ".lua")
  data.masters_cache = {}
end

function data.text(tbl, field, id)
  local t = texts[tbl]
  local f = t and t[field]
  return f and f[id]
end

-- "BodySp" / "OmoteBodyJp" ... -> base field name, or nil
local function split_lang(k)
  for _, s in ipairs(LANG_SUFFIX) do
    if #k > #s and k:sub(-#s) == s then
      local base = k:sub(1, -#s - 1)
      if base:sub(-1):match("%l") or base == "" then return base end
    end
  end
end

local function make_param(tbl, row)
  local id = tostring(row.Id or row.StatusType or "")
  return setmetatable({}, {
    __index = function(_, k)
      local v = row[k]
      if v ~= nil then return v end
      local base = split_lang(k)
      if base then return data.text(tbl, base, id) or "" end
      return nil
    end,
  })
end

function data.master(name)
  local cached = data.masters_cache[name]
  if cached then return cached end
  local rows = masters[name]
  if not rows then return nil end
  local l = List.new()
  for _, r in ipairs(rows) do l:Add(make_param(name, r)) end
  data.masters_cache[name] = l
  return l
end

-- ScriptableObject assets exported by build_assets.py (so step), enum ints converted by schema
local schemas
local function convert(v, typeKey)
  local sc = schemas[typeKey]
  if not sc or type(v) ~= "table" then return v end
  for field, kind in pairs(sc) do
    local x = v[field]
    if x ~= nil then
      local k, t = kind:match("^(%a+):(.+)$")
      if k == "E" then v[field] = ENUMN(t, x)
      elseif k == "LE" then local l = List.new(); for _, e in ipairs(x) do l:Add(ENUMN(t, e)) end v[field] = l
      elseif k == "LC" then local l = List.new(); for _, e in ipairs(x) do l:Add(convert(e, t)) end v[field] = l
      elseif k == "C" then v[field] = convert(x, t) end
    end
  end
  return v
end

function data.scriptable(typeName, name)
  local path = sys.data .. "data/so/" .. name .. ".lua"
  if not sys.exists(path) then return nil end
  schemas = schemas or require("schemas")
  local raw = dofile(path)
  -- lists without schema still need List semantics (.Count, :Find...)
  for k, v in pairs(raw) do
    if type(v) == "table" and v[1] ~= nil and not (schemas[typeName] and schemas[typeName][k]) then
      local l = List.new(); for _, e in ipairs(v) do l:Add(e) end raw[k] = l
    end
  end
  return convert(raw, typeName)
end

-- Resources.Load<T>(path)
Resources = {}
classes.Resources = Resources
function Resources.Load(typeName, path)
  if typeName == "Sprite" or typeName == "Texture2D" then
    return { __sprite = path:match("([^/]+)$"), name = path:match("([^/]+)$") }
  end
  if typeName == "VideoClip" then return { __video = path:match("([^/]+)$") } end
  local key = path:match("([^/]+)$")
  if key == "statuses" then
    return { StatusList = data.master("statuses") or List.new() }
  end
  local so = not typeName:match("Master$") and data.scriptable(typeName, key)
  if so then return so end
  local param = data.master(key)
  if param then
    local obj = { param = param }
    if key == "MobComment" then obj = setmetatable(obj, { __index = function(_, k) return param end }) end
    return obj
  end
  LOG_ONCE("res:" .. path, "Resources.Load missing:", typeName, path)
  return NULL
end
function Resources.LoadAll() return List.new() end
function Resources.UnloadUnusedAssets() end

-- ------------------------------------------------------------------ serialization (ES3)
local function ser(v, out, depth)
  local t = type(v)
  if t == "nil" or v == NULL then out[#out + 1] = "nil"
  elseif t == "boolean" or t == "number" then out[#out + 1] = tostring(v)
  elseif t == "string" then out[#out + 1] = string.format("%q", v)
  elseif t == "table" then
    if depth > 12 then out[#out + 1] = "nil"; return end
    local mt = getmetatable(v)
    local name = mt and (mt.__name or rawget(mt, "__name"))
    if mt == core.RP then
      out[#out + 1] = "RP("; ser(rawget(v, "_v"), out, depth + 1); out[#out + 1] = ")"
    elseif mt == List then
      out[#out + 1] = "L{"
      for i = 1, v.n do ser(v.items[i], out, depth + 1); out[#out + 1] = "," end
      out[#out + 1] = "}"
    elseif mt == core.RC then
      out[#out + 1] = "L{"
      for i = 1, v.list.n do ser(v.list.items[i], out, depth + 1); out[#out + 1] = "," end
      out[#out + 1] = "}"
    else
      out[#out + 1] = name and ("O(" .. string.format("%q", name) .. ",{") or "{"
      for k, x in pairs(v) do
        if type(k) == "string" and type(x) ~= "function" and k:sub(1, 2) ~= "__" then
          out[#out + 1] = "[" .. string.format("%q", k) .. "]="
          ser(x, out, depth + 1)
          out[#out + 1] = ","
        end
      end
      out[#out + 1] = name and "})" or "}"
    end
  else
    out[#out + 1] = "nil"
  end
end

function data.serialize(v)
  local out = {}
  ser(v, out, 0)
  return table.concat(out)
end

local load_env = {
  RP = function(v) return core.RP.new(v) end,
  L = function(t) local l = List.new(); for _, x in ipairs(t) do l:Add(x) end return l end,
  O = function(name, fields)
    local C = classes[name] or core.resolve(name)
    if C and C ~= NULL and C.__mt then return setmetatable(fields, C.__mt) end
    return fields
  end,
}

function data.deserialize(s)
  local fn = load("return " .. s, "save", "t", load_env)
  if not fn then return nil end
  local ok, v = pcall(fn)
  return ok and v or nil
end

local SAVE_DIR = "sdmc:/3ds/needy3ds/save/"
local es3_cache = {}

local function es3_path(file)
  file = file or "SaveFile.es3"
  return SAVE_DIR .. file:gsub("[/\\]", "_")
end

local function es3_file(file)
  local p = es3_path(file)
  if es3_cache[p] then return es3_cache[p] end
  local t = {}
  local s = sys.read(p)
  if s then t = data.deserialize(s) or {} end
  es3_cache[p] = t
  return t
end

local function es3_flush(file)
  sys.mkdir("sdmc:/3ds/needy3ds")
  sys.mkdir(SAVE_DIR)
  sys.write(es3_path(file), data.serialize(es3_file(file)))
end

ES3 = {}
classes.ES3 = ES3
function ES3.Save(key, value, file)
  es3_file(file)[key] = value
  es3_flush(file)
end
-- ES3.Load<T>(key, file[, default]): cs2lua passes the generic type name first
function ES3.Load(typeName, key, file, default)
  local v = es3_file(file)[key]
  if v == nil then return default end
  return v
end
function ES3.KeyExists(key, file) return es3_file(file)[key] ~= nil end
function ES3.FileExists(file) return sys.exists(es3_path(file)) end
function ES3.DeleteFile(file)
  local p = es3_path(file)
  es3_cache[p] = nil
  sys.remove(p)
end

return data
