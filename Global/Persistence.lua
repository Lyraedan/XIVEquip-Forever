-- Global/Persistence.lua
-- Self-contained SavedVariables workaround for WoW: Forever.
--
-- The Forever beta writes an addon's SavedVariables to disk on logout but
-- does not read them back on the next launch or /reload, so
-- `_G.XIVEquip_Settings` comes back nil and every profile/scale/preference
-- resets. Community tools (WTFix and friends) fix this externally; this
-- module is the addon's own defense so a plain install survives restarts.
--
-- The live settings table is mirrored into addon-owned console variables,
-- which the Forever client does persist and restore. On ADDON_LOADED, if the
-- SavedVariables table came back empty, it is rebuilt from those CVars before
-- Settings:Initialize() turns it into a fully-defaulted table.
--
-- Only plain data is stored: tables, numbers, strings, booleans. Functions
-- and userdata (e.g. an embedded classColor.GetHSL) are dropped, because the
-- Forever client refuses to round-trip them and a single such value would
-- otherwise poison the whole backup.
local addonName, XIVEquip = ...
XIVEquip = XIVEquip or _G.XIVEquip or {}

local P = {}
XIVEquip.Persistence = P

local CVAR_PREFIX = "xivequipdb"
local CHUNK_SIZE = 200
local SAVE_DEBOUNCE = 3

local _saveToken
local _initialized
local _lastRestoreResult = "not-run"

-- =========================
-- Serialization
-- =========================

local STRING_ESCAPES = {
  ["\\"] = "\\\\", ["\""] = "\\\"",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

-- Quote a string as a Lua literal, escaping newlines/controls so the encoded
-- payload is a single line safe to store in a console variable. NUL is
-- handled separately via %z: Lua patterns cannot contain embedded zeros.
local function quoteString(s)
  local out = tostring(s):gsub("[\\\"\n\r\t]", STRING_ESCAPES)
  out = out:gsub("%z", "\\0")
  return '"' .. out .. '"'
end

local function encodeValue(v, out)
  local t = type(v)
  if t == "nil" then
    out[#out + 1] = "nil"
  elseif t == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif t == "number" then
    if v ~= v then
      out[#out + 1] = "(0/0)"
    elseif v == math.huge then
      out[#out + 1] = "(1/0)"
    elseif v == -math.huge then
      out[#out + 1] = "(-1/0)"
    else
      out[#out + 1] = string.format("%.14g", v)
    end
  elseif t == "string" then
    out[#out + 1] = quoteString(v)
  elseif t == "table" then
    out[#out + 1] = "{"
    local n = #v
    for i = 1, n do
      encodeValue(v[i], out)
      out[#out + 1] = ","
    end
    for k, value in pairs(v) do
      local isArrayKey = type(k) == "number" and k >= 1 and k <= n and math.floor(k) == k
      if not isArrayKey then
        out[#out + 1] = "["
        encodeValue(k, out)
        out[#out + 1] = "]="
        encodeValue(value, out)
        out[#out + 1] = ","
      end
    end
    out[#out + 1] = "}"
  else
    -- Functions, userdata, threads: not persistable. Drop them.
    out[#out + 1] = "nil"
  end
end

function P.Encode(value)
  if type(value) ~= "table" then return nil end
  local out = {}
  encodeValue(value, out)
  return table.concat(out)
end

local function decodeString(text)
  if type(text) ~= "string" or text == "" then return nil end
  local loader = loadstring or load
  if type(loader) ~= "function" then return nil end
  local ok, chunk = pcall(loader, "return " .. text)
  if not ok or type(chunk) ~= "function" then return nil end
  if setfenv then pcall(setfenv, chunk, {}) end
  local okRun, value = pcall(chunk)
  if not okRun then return nil end
  return value
end

function P.Decode(text)
  local value = decodeString(text)
  if type(value) == "table" then return value end
  return nil
end

-- =========================
-- CVar transport
-- =========================

local function cvarName(index)
  return CVAR_PREFIX .. tostring(index)
end

local function hasCVarAPI()
  return (type(C_CVar) == "table" and type(C_CVar.SetCVar) == "function")
      or type(SetCVar) == "function"
end

-- Registering the name first is required: the modern client refuses to set an
-- unknown console variable, which is why a plain SetCVar on an addon-invented
-- name silently did nothing.
local function registerCVar(name, value)
  if type(C_CVar) == "table" and type(C_CVar.RegisterCVar) == "function" then
    pcall(C_CVar.RegisterCVar, name, value or "")
  end
end

local function setCVar(name, value)
  local text = tostring(value)
  if type(C_CVar) == "table" and type(C_CVar.SetCVar) == "function" then
    local ok, success = pcall(C_CVar.SetCVar, name, text)
    if ok and success then return true end
  end
  if type(SetCVar) == "function" then
    local ok = pcall(SetCVar, name, text)
    return ok
  end
  return false
end

local function getCVar(name)
  if type(C_CVar) == "table" and type(C_CVar.GetCVar) == "function" then
    local ok, value = pcall(C_CVar.GetCVar, name)
    if ok then return value end
  end
  if type(GetCVar) == "function" then
    local ok, value = pcall(GetCVar, name)
    if ok then return value end
  end
  return nil
end

local function setRegistered(name, value)
  registerCVar(name, "")
  return setCVar(name, value)
end

-- Write `data` across numbered CVars, then record the chunk count last so a
-- crash mid-write can never expose a half-updated backup as complete.
local function writeChunks(data)
  local chunkCount = math.max(1, math.ceil(#data / CHUNK_SIZE))
  local previous = tonumber(getCVar(CVAR_PREFIX .. "chunks")) or 0
  for i = 1, chunkCount do
    setRegistered(cvarName(i), data:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE))
  end
  for i = chunkCount + 1, previous do
    setRegistered(cvarName(i), "")
  end
  setRegistered(CVAR_PREFIX .. "chunks", tostring(chunkCount))
end

local function readChunks()
  local chunkCount = tonumber(getCVar(CVAR_PREFIX .. "chunks")) or 0
  if chunkCount <= 0 then return nil end
  local parts = {}
  for i = 1, chunkCount do
    local part = getCVar(cvarName(i))
    if not part or part == "" then return nil end
    parts[#parts + 1] = part
  end
  return table.concat(parts)
end

-- =========================
-- Public API
-- =========================

function P.IsAvailable()
  return hasCVarAPI()
end

function P.GetBackupChunkCount()
  return tonumber(getCVar(CVAR_PREFIX .. "chunks")) or 0
end

-- CVarInfo for the chunk-count variable, exposed so /xive compat can report
-- whether the backup is account/server stored.
function P.GetBackupCVarInfo()
  if type(C_CVar) == "table" and type(C_CVar.GetCVarInfo) == "function" then
    local ok, value, default, accountStore, charStore, locked, secure, readOnly =
        pcall(C_CVar.GetCVarInfo, CVAR_PREFIX .. "chunks")
    if ok then
      return {
        value = value, default = default,
        accountStore = accountStore, charStore = charStore,
        locked = locked, secure = secure, readOnly = readOnly,
      }
    end
  end
  return nil
end

-- True when the SavedVariables table is absent or empty (the Forever bug).
function P.IsSettingsEmpty()
  local st = _G.XIVEquip_Settings
  return type(st) ~= "table" or next(st) == nil
end

-- Rebuild _G.XIVEquip_Settings from the CVar backup when SavedVariables
-- failed to load. No-op when real SavedVariables are present.
function P.RestoreIfNeeded()
  if not P.IsSettingsEmpty() then
    _lastRestoreResult = "settings-present"
    return false, "settings-present"
  end
  local data = readChunks()
  if not data then
    _lastRestoreResult = "no-backup"
    return false, "no-backup"
  end
  local restored = P.Decode(data)
  if type(restored) ~= "table" or next(restored) == nil then
    _lastRestoreResult = "backup-invalid"
    return false, "backup-invalid"
  end
  _G.XIVEquip_Settings = restored
  _lastRestoreResult = "restored"
  if XIVEquip.Log and type(XIVEquip.Log.Info) == "function" then
    XIVEquip.Log.Info("Restored saved settings from console-variable backup.")
  end
  return true, "restored"
end

function P.GetLastRestoreResult()
  return _lastRestoreResult
end

-- Mirror the current settings table into the CVar backup.
function P.Save()
  if not P.IsAvailable() then return false, "cvar-unavailable" end
  local data = P.Encode(_G.XIVEquip_Settings)
  if not data then return false, "nothing-to-save" end
  writeChunks(data)
  return true, "saved"
end

-- Coalesce rapid save requests (settings UI edits) into one write.
function P.RequestSave()
  if _saveToken then return end
  local token = {}
  _saveToken = token
  if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
    _saveToken = nil
    P.Save()
    return
  end
  C_Timer.After(SAVE_DEBOUNCE, function()
    if _saveToken ~= token then return end
    _saveToken = nil
    P.Save()
  end)
end

-- Initialise the logout hook once. RestoreIfNeeded is called explicitly by
-- XIVEquip.lua before Settings:Initialize(), so no ADDON_LOADED work here.
function P.Initialize()
  if _initialized then return end
  _initialized = true
  local f = (type(CreateFrame) == "function") and CreateFrame("Frame") or nil
  if not f then return end
  f:RegisterEvent("PLAYER_LOGOUT")
  f:SetScript("OnEvent", function()
    P.Save()
  end)
end
