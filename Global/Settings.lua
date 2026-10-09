-- Global/Settings.lua
local addonName, XIVEquip = ...
XIVEquip = XIVEquip or _G.XIVEquip or {}
XIVEquip.Settings = XIVEquip.Settings or {}

local S = XIVEquip.Settings
local SCHEMA_VERSION = 4
local SETTINGS_MODEL = "v2"

local function messageValue(st, key, default)
  if type(st.Messages) == "table" and st.Messages[key] ~= nil then
    return st.Messages[key] == true
  end
  return default == true
end

local function automationValue(st, canonicalKey, legacyKeys, default)
  if type(st.Automation) == "table" and st.Automation[canonicalKey] ~= nil then
    return st.Automation[canonicalKey] == true
  end

  for _, legacy in ipairs(legacyKeys or {}) do
    local scope, key = legacy[1], legacy[2]
    if scope == "root" and st[key] ~= nil then
      return st[key] == true
    end
    if scope == "automation" and type(st.Automation) == "table" and st.Automation[key] ~= nil then
      return st.Automation[key] == true
    end
  end

  return default == true
end

local function migrateDebug(st)
  local enabled = false
  local slot = nil

  if type(st.Debug) == "table" then
    enabled = st.Debug.Enabled == true
    slot = st.Debug.Slot
  elseif type(st.Debug) == "boolean" then
    enabled = st.Debug
  end

  if slot == nil and st.DebugSlot ~= nil then
    slot = st.DebugSlot
  end

  return enabled, slot
end

local function ensureXIVWeights(st)
  st.XIVWeights = type(st.XIVWeights) == "table" and st.XIVWeights or {}
  st.XIVWeights.Scales = type(st.XIVWeights.Scales) == "table" and st.XIVWeights.Scales or {}
  st.XIVWeights.Specs = type(st.XIVWeights.Specs) == "table" and st.XIVWeights.Specs or {}
  st.XIVWeights.Integrations = type(st.XIVWeights.Integrations) == "table" and st.XIVWeights.Integrations or {}
  st.XIVWeights.Integrations.Pawn = type(st.XIVWeights.Integrations.Pawn) == "table"
      and st.XIVWeights.Integrations.Pawn or {}
end

local function ensureProfiles(st, sourceVersion)
  local profiles = st.Profiles
  if type(profiles) ~= "table" or profiles.ModelVersion ~= 1 then
    st.Profiles = {
      ModelVersion = 1,
      ByClass = {},
      CharacterAssignments = {},
    }
    st.Migration = {
      SourceSchemaVersion = sourceVersion,
      SourceModel = sourceVersion > 0 and "pre-profile-v2" or "fresh",
      AutomaticDefaulted = true,
    }
  else
    profiles.ByClass = type(profiles.ByClass) == "table" and profiles.ByClass or {}
    profiles.CharacterAssignments = type(profiles.CharacterAssignments) == "table"
        and profiles.CharacterAssignments or {}
  end
end

-- Migrate character-keyed maps from the legacy "Name-Realm" form to Forever's
-- two-part "First Second" name form. Only touches keys with a single dash and
-- no space, and never overwrites an existing destination key.
local function migrateCharacterKeys(map)
  if type(map) ~= "table" then return end
  local moves = {}
  for key in pairs(map) do
    if type(key) == "string" and key:find("%-") and not key:find("%s") then
      local spaced = key:gsub("%-", " ")
      if map[spaced] == nil then moves[#moves + 1] = { from = key, to = spaced } end
    end
  end
  for _, move in ipairs(moves) do
    map[move.to] = map[move.from]
    map[move.from] = nil
  end
end

local function ensure()
  _G.XIVEquip_Settings = _G.XIVEquip_Settings or {}
  local st = _G.XIVEquip_Settings
  local sourceVersion = tonumber(st.SchemaVersion) or 0

  st.SchemaVersion = SCHEMA_VERSION
  st.SettingsModel = SETTINGS_MODEL

  st.Messages = type(st.Messages) == "table" and st.Messages or {}
  st.Messages.Login = messageValue(st, "Login", false)
  st.Messages.Equip = messageValue(st, "Equip", false)
  st.Messages.Preview = messageValue(st, "Preview", true)

  -- Automation is disabled in this fork (Forever has no spec switching), so it
  -- is forced off regardless of any previously saved value.
  st.Automation = type(st.Automation) == "table" and st.Automation or {}
  st.Automation.SpecEquip = false
  st.Automation.SaveSpecSet = false
  st.Automation.AutoSpec = nil
  st.Automation.AutoSets = nil

  local debugEnabled, debugSlot = migrateDebug(st)
  st.Debug = {
    Enabled = debugEnabled,
    Slot = debugSlot,
  }

  st.Weapons = type(st.Weapons) == "table" and st.Weapons or {}
  st.Weapons.Mode = st.Weapons.Mode or "AUTO"
  st.Weapons.Bias = st.Weapons.Bias or "AUTO"

  st.UI = type(st.UI) == "table" and st.UI or {}
  st.UI.SettingsWindow = type(st.UI.SettingsWindow) == "table" and st.UI.SettingsWindow or {}
  st.UI.Minimap = type(st.UI.Minimap) == "table" and st.UI.Minimap or {}
  if st.UI.Minimap.Hidden == nil then st.UI.Minimap.Hidden = false end
  st.UI.Minimap.Angle = tonumber(st.UI.Minimap.Angle) or 220
  st.AutoSpecMap = type(st.AutoSpecMap) == "table" and st.AutoSpecMap or {}
  st.CharacterBuilds = type(st.CharacterBuilds) == "table" and st.CharacterBuilds or {}
  st.Builds = type(st.Builds) == "table" and st.Builds or {}
  st.MacroID = st.MacroID or 0

  ensureXIVWeights(st)
  ensureProfiles(st, sourceVersion)

  -- Migrate legacy "<first>-<second>" character keys (which treated Forever's
  -- second name as a realm) to the new "<first> <second>" space form, so
  -- existing per-character profile assignments and build selections survive.
  migrateCharacterKeys(st.CharacterBuilds)
  migrateCharacterKeys(st.Profiles and st.Profiles.CharacterAssignments)

  -- Weapon preferences now live on named Builds; drop the short-lived
  -- per-character/per-build stores from earlier builds.
  st.CharacterWeapons = nil
  st.BuildWeapons = nil


  st.SelectedComparer = nil
  st.Comparer = nil
  st.AutoSpecEquip = nil
  st.AutoSpecSets = nil
  st.DebugSlot = nil
  st.PlannerMode = nil
  st.Planner = nil

  rawset(_G, "XIVEquip_Debug", st.Debug.Enabled == true)
  rawset(_G, "XIVEquip_DebugSlot", st.Debug.Slot)

  return st
end

function S:Initialize() return ensure() end

function S:Get() return ensure() end

function S:GetSchemaVersion() return ensure().SchemaVersion end

function S:SetDebugEnabled(val)
  local st = ensure()
  st.Debug.Enabled = val == true
  rawset(_G, "XIVEquip_Debug", st.Debug.Enabled)
end

function S:GetDebugEnabled() return ensure().Debug.Enabled == true end

function S:SetDebugSlot(val)
  local st = ensure()
  st.Debug.Slot = val
  rawset(_G, "XIVEquip_DebugSlot", val)
end

function S:GetDebugSlot() return ensure().Debug.Slot end

function S:SetMessage(flag, val)
  local st = ensure()
  st.Messages[flag] = val == true
end

function S:GetMessage(flag) return ensure().Messages[flag] == true end

local automationAliases = {
  AutoSpec = "SpecEquip",
  SpecEquip = "SpecEquip",
  spec = "SpecEquip",
  AutoSets = "SaveSpecSet",
  SaveSpecSet = "SaveSpecSet",
  sets = "SaveSpecSet",
}

function S:SetAutomation(flag, val)
  local key = automationAliases[flag] or flag
  local st = ensure()
  st.Automation[key] = val == true
end

function S:GetAutomation(flag)
  local key = automationAliases[flag] or flag
  return ensure().Automation[key] == true
end

function S:GetMinimapHidden()
  return ensure().UI.Minimap.Hidden == true
end

function S:SetMinimapHidden(val)
  ensure().UI.Minimap.Hidden = val == true
end

function S:GetMinimapAngle()
  return ensure().UI.Minimap.Angle
end

function S:SetMinimapAngle(angle)
  ensure().UI.Minimap.Angle = tonumber(angle) or 220
end
