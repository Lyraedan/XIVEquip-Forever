-- Global/Compat.lua
-- Compatibility layer for World of Warcraft: Forever (Interface 16001,
-- product wow_classic_beta). The Forever client moved the legacy bare
-- globals this addon was written against -- GetSpecialization,
-- GetSpecializationInfo, GetItemInfo/Instant, GetItemStats,
-- GetDetailedItemLevelInfo, GetContainer*, GetAddOnMetadata, IsAddOnLoaded --
-- behind their C_* namespaces, and stopped exporting the bare names.
--
-- Rather than scatter C_* calls through the codebase, every touched call site
-- goes through these wrappers. Each wrapper prefers the namespaced API and
-- falls back to the legacy global when one is still present, so the addon
-- keeps working if Blizzard re-adds an alias or if this fork is ever run on a
-- client that still has the globals.
local addonName, XIVEquip = ...
XIVEquip = XIVEquip or _G.XIVEquip or {}

local API = XIVEquip.API or {}
XIVEquip.API = API

-- nsFn(ns, name): return ns[name] if it is callable, else nil.
local function nsFn(ns, name)
  if type(ns) ~= "table" then return nil end
  local f = ns[name]
  if type(f) == "function" then return f end
  return nil
end

-- Token(name): resolve a global string constant (ITEM_MOD_*, EMPTY_SOCKET_*,
-- INVTYPE_*, ...) to the value the game APIs actually return.
--
-- The client's item APIs return these as their *literal* token names (e.g.
-- GetItemInfoInstant returns the string "INVTYPE_CHEST"). Historically the
-- global constant held that same string, so keying tables by the global worked.
-- On Forever some globals exist but with a different value, which silently
-- breaks every table keyed by them. Detect that and fall back to the literal
-- name so maps always match what the API returns.
function API.Token(name)
  local v = _G[name]
  if type(v) == "string" and v ~= "" then return v end
  return name
end

-- BothKeys(globalName): returns the literal token name and -- when the global
-- resolves to something else -- that value too, so map lookups succeed whether
-- the client hands back the literal name or the enum value.
function API.TokenKeys(name)
  local keys = { name }
  local v = _G[name]
  if v ~= nil and v ~= name then keys[#keys + 1] = v end
  return keys
end

-- SetTokens(table, globalName, value): assign `value` under every key the
-- token could arrive as.
function API.SetTokens(tbl, name, value)
  for _, key in ipairs(API.TokenKeys(name)) do tbl[key] = value end
end

-- =========================
-- Specialization
-- =========================
-- Forever's GetSpecializationInfo does NOT return a global spec ID in field 1.
-- On build 1.60.1, for a Warrior it returned:
--   1=1491 (spec-set), 2="Warrior" (name), 3="" (desc), 4=icon, 5="DAMAGER",
--   6=primaryStat, 7=pointsSpent
-- i.e. the value is dislocated and field 2 holds the class name, not the spec
-- name. The only reliable source of real global spec IDs is the class
-- enumeration (GetSpecializationInfoForClassID / GetNumSpecializationsForClassID).
--
-- XIVEquip's callers contract is unchanged from retail:
--   API.GetSpecialization() -> class-local spec index (1..n)
--   API.GetSpecializationInfo(index) -> specID, name, description, icon,
--                                        background, role
-- These wrappers translate Forever's API back onto that contract.

local function rawGetSpecialization(...)
  local f = nsFn(C_SpecializationInfo, "GetSpecialization") or _G.GetSpecialization
  if type(f) == "function" then return f(...) end
  return nil
end

local function playerClassID()
  return select(3, UnitClass("player"))
end

-- Ordered list of { id, name } real specs for a class.
local function classSpecList(classID)
  local count = 0
  local numFn = nsFn(C_SpecializationInfo, "GetNumSpecializationsForClassID")
  if numFn and classID then
    local ok, n = pcall(numFn, classID)
    if ok and tonumber(n) then count = tonumber(n) end
  end
  if count == 0 then
    local fallback = _G.GetNumSpecializations and _G.GetNumSpecializations()
    count = tonumber(fallback) or 0
  end

  local specs = {}
  local infoForClass = _G.GetSpecializationInfoForClassID
  local classInfo = nsFn(C_SpecializationInfo, "GetSpecializationInfoForClassID")
  for i = 1, count do
    local id, name
    if type(infoForClass) == "function" and classID then
      local ok, sid, sname = pcall(infoForClass, classID, i)
      if ok then id, name = sid, sname end
    end
    if not id and classInfo and classID then
      local ok, sid, sname = pcall(classInfo, classID, i)
      if ok then id, name = sid, sname end
    end
    if tonumber(id) then specs[#specs + 1] = { id = tonumber(id), name = name } end
  end
  return specs
end

-- Player's active class-local spec index. rawGetSpecialization() returns a
-- usable index on Forever (it returned 1), so prefer it; fall back to the
-- active spec group.
local function activeSpecIndex()
  local idx = tonumber(rawGetSpecialization())
  if idx and idx >= 1 then return idx end
  local groupFn = nsFn(C_SpecializationInfo, "GetActiveSpecGroup")
  if groupFn then
    local ok, grp = pcall(groupFn)
    if ok then return tonumber(grp) end
  end
  return nil
end

-- Resolve an index (or the active spec when index is nil) to a real spec ID.
-- Returns specID, name, icon, role.
local function resolveSpec(index)
  local classID = playerClassID()
  local specs = classSpecList(classID)
  local idx = tonumber(index) or activeSpecIndex()

  if idx and specs[idx] then
    return specs[idx].id, specs[idx].name, nil, nil
  end

  -- Fall back to decoding whatever the raw API returns for the active index.
  if not idx then return nil end
  local infoFn = nsFn(C_SpecializationInfo, "GetSpecializationInfo")
  if infoFn then
    local ok, rawID, rawName, _, rawIcon, rawRole = pcall(infoFn, idx)
    if ok then
      local raw = tonumber(rawID)
      local candidateIDs = {}
      for _, spec in ipairs(specs) do candidateIDs[spec.id] = spec end
      if raw and candidateIDs[raw] then
        return raw, candidateIDs[raw].name, rawIcon, rawRole
      end
      if raw and type(_G.GetSpecIDs) == "function" then
        local okIds, ids = pcall(_G.GetSpecIDs, raw)
        if okIds and type(ids) == "table" then
          for _, specID in ipairs(ids) do
            local n = tonumber(specID)
            if n and candidateIDs[n] then return n, candidateIDs[n].name, rawIcon, rawRole end
          end
        end
      end
      return raw, rawName, rawIcon, rawRole
    end
  end
  return nil
end

function API.GetSpecialization(...)
  -- Contract: class-local spec index, not a spec ID.
  return activeSpecIndex()
end

-- Normalized to the legacy return order, with a guaranteed global spec ID in
-- field 1:
--   specID, name, description, icon, background, role
function API.GetSpecializationInfo(index, ...)
  local specID, name, icon, role = resolveSpec(index == nil and nil or index)
  if specID then
    return specID, name, nil, icon, nil, role
  end
  -- Last-ditch: raw passthrough (may be a spec-set ID; callers treat an
  -- unknown ID as "no default scale").
  local namespaced = nsFn(C_SpecializationInfo, "GetSpecializationInfo")
  if namespaced then
    local rawId, rawName, description, rawIcon, rawRole, _primaryStat, _points, background = namespaced(index, ...)
    return rawId, rawName, description, rawIcon, background, rawRole
  end
  local legacy = _G.GetSpecializationInfo
  if type(legacy) == "function" then return legacy(index, ...) end
  return nil
end

function API.GetSpecializationInfoByID(specID, ...)
  local f = _G.GetSpecializationInfoByID
  if type(f) == "function" then return f(specID, ...) end
  local forID = _G.GetSpecializationInfoForSpecID
  if type(forID) == "function" then
    local id, name, description, icon, role = forID(specID, ...)
    return id, name, description, icon, nil
  end
  return nil
end

function API.IsDualWielding(...)
  local f = _G.IsDualWielding
  if type(f) == "function" then return f(...) end
  return nil
end

-- =========================
-- Item info / stats
-- =========================

function API.GetItemInfo(itemInfo)
  local f = nsFn(C_Item, "GetItemInfo") or _G.GetItemInfo
  if type(f) == "function" then return f(itemInfo) end
  return nil
end

function API.GetItemInfoInstant(itemInfo)
  local f = nsFn(C_Item, "GetItemInfoInstant") or _G.GetItemInfoInstant
  if type(f) == "function" then return f(itemInfo) end
  return nil
end

function API.GetItemStats(itemLink)
  local f = nsFn(C_Item, "GetItemStats") or _G.GetItemStats
  if type(f) == "function" then return f(itemLink) end
  return nil
end

function API.GetDetailedItemLevelInfo(itemInfo)
  local f = nsFn(C_Item, "GetDetailedItemLevelInfo") or _G.GetDetailedItemLevelInfo
  if type(f) == "function" then return f(itemInfo) end
  return nil
end

-- =========================
-- Containers / bags
-- =========================

-- Number of non-backpack bag slots. The bare NUM_BAG_SLOTS constant is not
-- exported on Forever; the classic default is 4 (container indices 0..4).
function API.NumBagSlots()
  return tonumber(_G.NUM_BAG_SLOTS) or 4
end

function API.GetContainerNumSlots(bag)
  local f = nsFn(C_Container, "GetContainerNumSlots") or _G.GetContainerNumSlots
  if type(f) == "function" then return f(bag) end
  return 0
end

function API.GetContainerItemInfo(bag, slot)
  local f = nsFn(C_Container, "GetContainerItemInfo") or _G.GetContainerItemInfo
  if type(f) == "function" then return f(bag, slot) end
  return nil
end

function API.GetContainerItemLink(bag, slot)
  local f = nsFn(C_Container, "GetContainerItemLink") or _G.GetContainerItemLink
  if type(f) == "function" then return f(bag, slot) end
  return nil
end

function API.PickupContainerItem(bag, slot)
  local f = nsFn(C_Container, "PickupContainerItem") or _G.PickupContainerItem
  if type(f) == "function" then return f(bag, slot) end
end

-- =========================
-- AddOn metadata
-- =========================

function API.GetAddOnMetadata(name, variable)
  local f = nsFn(C_AddOns, "GetAddOnMetadata") or _G.GetAddOnMetadata
  if type(f) == "function" then return f(name, variable) end
  return nil
end

function API.IsAddOnLoaded(name)
  local f = nsFn(C_AddOns, "IsAddOnLoaded")
  if f then return f(name) == true end
  local legacy = _G.IsAddOnLoaded
  if type(legacy) == "function" then return legacy(name) == true end
  return name == "Pawn" and XIVEquip.Pawn ~= nil
end

-- =========================
-- Equipment sets
-- =========================

-- C_EquipmentSet dropped ModifyEquipmentSetIcon in favor of
-- ModifyEquipmentSet(id, newName, newIcon). Preserve the name when only the
-- icon is being changed.
function API.ModifyEquipmentSetIcon(setID, icon)
  local namespacedIcon = nsFn(C_EquipmentSet, "ModifyEquipmentSetIcon")
  if namespacedIcon then return namespacedIcon(setID, icon) end

  local modify = nsFn(C_EquipmentSet, "ModifyEquipmentSet")
  if modify then
    local name
    local info = nsFn(C_EquipmentSet, "GetEquipmentSetInfo")
    if info then name = select(1, info(setID)) end
    return modify(setID, name, icon)
  end

  local legacy = _G.ModifyEquipmentSetIcon
  if type(legacy) == "function" then return legacy(setID, icon) end
end

-- =========================
-- ItemLocation constructors
-- =========================
-- The classic global ItemLocation mixin table is not documented on Forever.
-- These helpers return an ItemLocation when its constructors exist, and
-- otherwise return a shape the rest of the addon already knows how to read
-- (a raw equipment slot number, or a { bagID, slotIndex } table).

function API.EquipmentSlotLocation(slotID)
  local IL = _G.ItemLocation
  if type(IL) == "table" and type(IL.CreateFromEquipmentSlot) == "function" then
    local ok, loc = pcall(IL.CreateFromEquipmentSlot, IL, slotID)
    if ok and loc ~= nil then
      -- On Forever this may be a GUID string rather than an ItemLocation
      -- object. Wrap it so callers keep a stable { equipmentSlot = n } shape
      -- and can always recover the inventory slot.
      return setmetatable({ equipmentSlot = slotID, _raw = loc, _isItemLocation = type(loc) == "userdata" or type(loc) == "table" },
        { __tostring = function() return "ItemLocation(equip:" .. tostring(slotID) .. ")" end })
    end
  end
  return { equipmentSlot = slotID }
end

function API.BagSlotLocation(bag, slot)
  local IL = _G.ItemLocation
  if type(IL) == "table" and type(IL.CreateFromBagAndSlot) == "function" then
    local ok, loc = pcall(IL.CreateFromBagAndSlot, IL, bag, slot)
    if ok and loc ~= nil then
      return setmetatable({ bagID = bag, slotIndex = slot, _raw = loc, _isItemLocation = type(loc) == "userdata" or type(loc) == "table" },
        { __tostring = function() return "ItemLocation(bag:" .. tostring(bag) .. ":" .. tostring(slot) .. ")" end })
    end
  end
  return { bagID = bag, slotIndex = slot }
end
