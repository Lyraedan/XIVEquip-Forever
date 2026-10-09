-- XIVWeights/Builtin/Defaults.lua
-- Built-in build scale templates for World of Warcraft: Forever. Forever keeps
-- the vanilla class model: three talent trees per class and no selectable
-- specialization exposed to the client API, so scales are keyed by a stable
-- per-tree "build" ID (not by a Blizzard spec ID, which Forever does not
-- provide per tree).
--
-- These are source-controlled defaults, not user settings. XIVWeights.Config
-- can create editable SavedVariables copies on demand and reset those copies
-- from this table.
--
-- Stat vocabulary is Forever's: primaries, stamina, armor, spirit, attack /
-- ranged attack / spell power, bonus healing, and the unified hit / crit plus
-- the new expertise and weapon-skill ratings. Mastery and versatility do not
-- exist in Forever and are deliberately absent.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
XIVEquip.XIVWeights.Builtin = XIVEquip.XIVWeights.Builtin or {}
local XIVWeights = XIVEquip.XIVWeights

local Defaults = {}
XIVWeights.Builtin.Defaults = Defaults

Defaults.Version = 1

-- classFile -> ordered list of the class's three Forever talent trees. `id` is
-- an internal build ID (stable, never a client spec ID); `primary` is the
-- tree's dominant attribute; `priority` is a descending stat order; and
-- `weaponDps` controls how weapon damage is weighted ("withPrimary",
-- "abovePrimary", or omitted).
Defaults.Builds = {
  WARRIOR = {
    { id = 1001, name = "Arms", primary = "strength",
      priority = { "stamina", "criticalStrike", "hit", "attackPower", "expertise", "armor" }, weaponDps = "withPrimary",
      weapon = { style = "two_hand" } },
    { id = 1002, name = "Fury", primary = "strength",
      priority = { "criticalStrike", "stamina", "hit", "attackPower", "expertise" }, weaponDps = "withPrimary",
      weapon = { style = "dual_wield" } },
    { id = 1003, name = "Protection", primary = "strength",
      priority = { "stamina", "armor", "hit", "expertise", "criticalStrike" }, weaponDps = "withPrimary",
      weapon = { style = "mh_shield" } },
  },
  PALADIN = {
    { id = 1004, name = "Holy", primary = "intellect",
      priority = { "spellHealing", "spirit", "spellPower", "criticalStrike", "stamina" },
      weapon = { style = "mh_shield" } },
    { id = 1005, name = "Protection", primary = "strength",
      priority = { "stamina", "armor", "hit", "intellect", "spellPower", "expertise" }, weaponDps = "withPrimary",
      weapon = { style = "mh_shield" } },
    { id = 1006, name = "Retribution", primary = "strength",
      priority = { "criticalStrike", "stamina", "hit", "attackPower", "spellPower", "expertise" }, weaponDps = "withPrimary",
      weapon = { style = "two_hand" } },
  },
  HUNTER = {
    { id = 1007, name = "Beast Mastery", primary = "agility",
      priority = { "rangedAttackPower", "criticalStrike", "stamina", "hit" }, weaponDps = "abovePrimary",
      weapon = { style = "two_hand", ranged = "any" } },
    { id = 1008, name = "Marksmanship", primary = "agility",
      priority = { "rangedAttackPower", "criticalStrike", "hit", "stamina" }, weaponDps = "abovePrimary",
      weapon = { style = "two_hand", ranged = "any" } },
    { id = 1009, name = "Survival", primary = "agility",
      priority = { "rangedAttackPower", "criticalStrike", "hit", "stamina" }, weaponDps = "abovePrimary",
      weapon = { style = "two_hand", ranged = "any" } },
  },
  ROGUE = {
    { id = 1010, name = "Assassination", primary = "agility",
      priority = { "attackPower", "criticalStrike", "stamina", "hit", "expertise" }, weaponDps = "withPrimary",
      weapon = { style = "dual_wield" } },
    { id = 1011, name = "Combat", primary = "agility",
      priority = { "attackPower", "hit", "criticalStrike", "expertise", "stamina" }, weaponDps = "withPrimary",
      weapon = { style = "dual_wield" } },
    { id = 1012, name = "Subtlety", primary = "agility",
      priority = { "attackPower", "criticalStrike", "hit", "stamina", "expertise" }, weaponDps = "withPrimary",
      weapon = { style = "dual_wield" } },
  },
  PRIEST = {
    { id = 1013, name = "Discipline", primary = "intellect",
      priority = { "spellHealing", "spirit", "spellPower", "criticalStrike", "stamina" },
      weapon = { style = "auto" } },
    { id = 1014, name = "Holy", primary = "intellect",
      priority = { "spellHealing", "spirit", "spellPower", "criticalStrike", "stamina" },
      weapon = { style = "auto" } },
    { id = 1015, name = "Shadow", primary = "intellect",
      priority = { "spellPower", "hit", "criticalStrike", "spirit", "stamina" },
      weapon = { style = "auto" } },
  },
  SHAMAN = {
    { id = 1016, name = "Elemental", primary = "intellect",
      priority = { "spellPower", "hit", "criticalStrike", "stamina", "spirit" },
      weapon = { style = "mh_shield" } },
    { id = 1017, name = "Enhancement", primary = "agility",
      priority = { "attackPower", "strength", "criticalStrike", "hit", "expertise", "stamina" }, weaponDps = "withPrimary",
      weapon = { style = "dual_wield" } },
    { id = 1018, name = "Restoration", primary = "intellect",
      priority = { "spellHealing", "spirit", "spellPower", "criticalStrike", "stamina" },
      weapon = { style = "mh_shield" } },
  },
  MAGE = {
    { id = 1019, name = "Arcane", primary = "intellect",
      priority = { "spellPower", "spirit", "hit", "criticalStrike", "stamina" },
      weapon = { style = "auto" } },
    { id = 1020, name = "Fire", primary = "intellect",
      priority = { "spellPower", "criticalStrike", "hit", "spirit", "stamina" },
      weapon = { style = "auto" } },
    { id = 1021, name = "Frost", primary = "intellect",
      priority = { "spellPower", "hit", "criticalStrike", "spirit", "stamina" },
      weapon = { style = "auto" } },
  },
  WARLOCK = {
    { id = 1022, name = "Affliction", primary = "intellect",
      priority = { "spellPower", "hit", "stamina", "criticalStrike" },
      weapon = { style = "auto" } },
    { id = 1023, name = "Demonology", primary = "intellect",
      priority = { "spellPower", "stamina", "hit", "criticalStrike" },
      weapon = { style = "auto" } },
    { id = 1024, name = "Destruction", primary = "intellect",
      priority = { "spellPower", "criticalStrike", "hit", "stamina" },
      weapon = { style = "auto" } },
  },
  DRUID = {
    { id = 1025, name = "Balance", primary = "intellect",
      priority = { "spellPower", "hit", "criticalStrike", "spirit", "stamina" },
      weapon = { style = "auto" } },
    { id = 1026, name = "Feral Combat", primary = "agility",
      priority = { "strength", "attackPower", "criticalStrike", "stamina", "hit" }, weaponDps = "withPrimary",
      weapon = { style = "two_hand" } },
    { id = 1027, name = "Restoration", primary = "intellect",
      priority = { "spellHealing", "spirit", "spellPower", "criticalStrike", "stamina" },
      weapon = { style = "auto" } },
  },
}

local function weights(primary, priority, opts)
  local out = {}
  opts = opts or {}
  if opts.weaponDps == "abovePrimary" then
    out.weaponDps = 1.0
    out[primary] = 0.9
  elseif opts.weaponDps == "withPrimary" then
    out.weaponDps = 1.0
    out[primary] = 1.0
  else
    out[primary] = 1.0
  end
  local value = 0.5
  for _, entry in ipairs(priority or {}) do
    if type(entry) == "table" then
      for _, feature in ipairs(entry) do out[feature] = value end
    else
      out[entry] = value
    end
    value = value - 0.1
    if value < 0.1 then value = 0.1 end
  end
  return out
end

local function buildScale(classFile, def)
  return XIVWeights.NewScale({
    id = "default:build:" .. tostring(def.id),
    name = def.name,
    source = {
      kind = "xivequip-default",
      specID = def.id,
      classFile = classFile,
      defaultVersion = Defaults.Version,
    },
    weights = weights(def.primary, def.priority, { weaponDps = def.weaponDps }),
    meta = {
      specID = def.id,
      classFile = classFile,
      specName = def.name,
      primary = def.primary,
      priority = def.priority,
      weaponDpsPriority = def.weaponDps,
      defaultVersion = Defaults.Version,
      weapon = def.weapon or { style = "auto", type = "any", ranged = "any" },
    },
  })
end

Defaults.Scales = {}
Defaults.ByID = {}
for classFile, defs in pairs(Defaults.Builds) do
  for _, def in ipairs(defs) do
    Defaults.Scales[def.id] = buildScale(classFile, def)
    Defaults.ByID[def.id] = { id = def.id, name = def.name, classFile = classFile, def = def }
  end
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

function Defaults.Get(specID)
  local scale = Defaults.Scales[tonumber(specID)]
  if not scale then return nil end
  return copy(scale)
end

function Defaults.List()
  local out = {}
  for _, scaleValue in pairs(Defaults.Scales) do
    out[#out + 1] = copy(scaleValue)
  end
  table.sort(out, function(a, b)
    return tonumber(a.meta and a.meta.specID or 0) < tonumber(b.meta and b.meta.specID or 0)
  end)
  return out
end

-- Ordered build definitions for a class (each { id, name }).
function Defaults.SpecsForClass(classFile)
  return Defaults.Builds[classFile] or {}
end

function Defaults.ClassForSpec(specID)
  specID = tonumber(specID)
  local entry = specID and Defaults.ByID[specID]
  return entry and entry.classFile or nil
end

function Defaults.PrimaryForSpec(specID)
  local scaleValue = Defaults.Scales[tonumber(specID)]
  return scaleValue and scaleValue.meta and scaleValue.meta.primary or nil
end

-- The default (first) build for a class, as a { id, name } record.
function Defaults.DefaultBuildForClass(classFile)
  return (Defaults.Builds[classFile] or {})[1]
end

-- The build definition (id, name, weights config, weapon config) for a build ID.
function Defaults.BuildForID(specID)
  local entry = Defaults.ByID[tonumber(specID)]
  return entry and entry.def or nil
end

function Defaults.NameForID(specID)
  local entry = Defaults.ByID[tonumber(specID)]
  return entry and entry.name or nil
end
