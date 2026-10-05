-- Evaluation/CandidateCollector.lua
-- Collects equipped + bag items into normalized candidates. This module is
-- intentionally boring: it resolves item links, preserves source identity,
-- reports pending/unresolved entries, and delegates all legality/scoring to
-- downstream policies and assignment solvers.
local addonName, XIVEquip = ...
XIVEquip.Evaluation = XIVEquip.Evaluation or {}
local Evaluation = XIVEquip.Evaluation

local API = XIVEquip.API

local CandidateCollector = {}
Evaluation.CandidateCollector = CandidateCollector

local DEFAULT_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
local SUPPORTED_WEAPON_EQUIPLOCS = {}
for _, name in ipairs({
  "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND",
  "INVTYPE_2HWEAPON", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT",
  "INVTYPE_THROWN", "INVTYPE_HOLDABLE", "INVTYPE_SHIELD", "INVTYPE_AMMO",
}) do
  for _, key in ipairs(API.TokenKeys(name)) do SUPPORTED_WEAPON_EQUIPLOCS[key] = true end
end

local function parseItemID(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|Hitem:(%d+)") or link:match("item:(%d+)"))
end

local function locationLink(location)
  local Core = XIVEquip.Gear_Core
  if Core and type(Core.linkFromLocation) == "function" then
    return Core.linkFromLocation(location)
  end
  if C_Item and type(C_Item.GetItemLink) == "function" then
    local ok, link = pcall(C_Item.GetItemLink, location)
    if ok and link then return link end
  end
  return nil
end

local function rawTarget(location)
  if type(location) == "table" and location._raw ~= nil then return location._raw end
  return location
end

local function itemGUID(location)
  if C_Item and type(C_Item.GetItemGUID) == "function" then
    local target = rawTarget(location)
    if type(target) == "userdata" or (type(target) == "table" and target ~= location) then
      local ok, guid = pcall(C_Item.GetItemGUID, target)
      if ok and type(guid) == "string" and guid ~= "" then return guid end
    end
  end
  return nil
end

local function requestLoad(location)
  if C_Item and type(C_Item.RequestLoadItemData) == "function" then
    local target = rawTarget(location)
    if type(target) == "userdata" or (type(target) == "table" and target ~= location) then
      pcall(C_Item.RequestLoadItemData, target)
    end
  end
end

local function locationHasItem(location)
  if C_Item and type(C_Item.DoesItemExist) == "function" then
    local target = rawTarget(location)
    if type(target) == "number" then
      return type(GetInventoryItemLink) == "function" and GetInventoryItemLink("player", target) ~= nil
    end
    local ok, exists = pcall(C_Item.DoesItemExist, target)
    if ok then return exists == true end
  end
  if type(location) == "table" and location.bagID ~= nil then
    local link = API.GetContainerItemLink and API.GetContainerItemLink(location.bagID, location.slotIndex)
    return link ~= nil
  end
  return false
end

local function canNormalize(link, itemID)
  if type(API.GetItemInfoInstant) ~= "function" then return true end
  local ok, id, _, _, equipLoc = pcall(API.GetItemInfoInstant, itemID or link)
  return ok and id ~= nil and equipLoc ~= nil
end

local function appendUnresolved(result, source, reason, link, itemID)
  result.pending = true
  source.reason = reason
  source.link = link
  source.itemID = itemID
  result.unresolved[#result.unresolved + 1] = source
end

local function supportedEquipLoc(equipLoc)
  if type(equipLoc) ~= "string" or equipLoc == "" then return false end
  local Const = XIVEquip.Const or {}
  if Const.INV_BY_EQUIPLOC and Const.INV_BY_EQUIPLOC[equipLoc] then return true end
  return SUPPORTED_WEAPON_EQUIPLOCS[equipLoc] == true
end

local function couldBeSupportedEquipment(itemID, link)
  if type(API.GetItemInfoInstant) ~= "function" then return true end
  local ok, resolvedID, _, _, equipLoc = pcall(API.GetItemInfoInstant, itemID or link)
  if not ok then return true end
  if not resolvedID then return true end
  return supportedEquipLoc(equipLoc)
end

local function collectLocation(result, location, source)
  if not location then return nil end
  local perf = result.perf
  local link = locationLink(location)
  local itemID = parseItemID(link) or source.itemID
  source.guid = source.guid or itemGUID(location)

  if not link then
    if source.kind == "equipped" and not locationHasItem(location) then return nil end
    requestLoad(location)
    appendUnresolved(result, source, "no-link", nil, itemID)
    return nil
  end

  if not canNormalize(link, itemID) then
    requestLoad(location)
    appendUnresolved(result, source, "pending-item-data", link, itemID)
    return nil
  end

  local cache = Evaluation.NormalizedItemCache
  local function normalize(candidateLink, candidateSource, normalizeOpts)
    return Evaluation.CandidateNormalizer.FromLink(candidateLink, candidateSource, normalizeOpts)
  end
  local candidate, normalizeReason
  local normalizeToken = perf and perf:Start("Normalization")
  if cache and cache.Get then
    candidate, normalizeReason = cache.Get(source.guid, link, source, normalize, { perf = perf })
  else
    candidate, normalizeReason = normalize(link, source, { perf = perf })
  end
  if perf then perf:Stop(normalizeToken) end
  if not candidate then
    requestLoad(location)
    appendUnresolved(result, source, normalizeReason or "pending-item-data", link, itemID)
    return nil
  end
  if perf then perf:Add("inventory.equipment_candidates_discovered", 1) end
  result.candidates[#result.candidates + 1] = candidate
  return candidate
end

local function equipmentLocation(slotID)
  return API.EquipmentSlotLocation(slotID)
end

local function bagLocation(bag, slot)
  return API.BagSlotLocation(bag, slot)
end

function CandidateCollector.Collect(opts)
  opts = opts or {}
  local slots = opts.slots or DEFAULT_SLOTS
  local result = { candidates = {}, equippedBySlot = {}, pending = false, unresolved = {}, perf = opts.perf }
  local perf = opts.perf
  if Evaluation.NormalizedItemCache and Evaluation.NormalizedItemCache.BeginScan then
    Evaluation.NormalizedItemCache.BeginScan()
  end

  for _, slotID in ipairs(slots) do
    if perf then perf:Add("inventory.locations_scanned", 1) end
    local loc = equipmentLocation(slotID)
    if perf and locationHasItem(loc) then perf:Add("inventory.occupied_locations", 1) end
    local candidate = collectLocation(result, loc, {
      kind = "equipped",
      slot = slotID,
      loc = loc,
      physicalID = "equip:" .. tostring(slotID),
    })
    if candidate then result.equippedBySlot[slotID] = candidate end
  end

  if type(API.GetContainerNumSlots) == "function" then
    for bag = 0, API.NumBagSlots() do
      local count = API.GetContainerNumSlots(bag) or 0
      for slot = 1, count do
        if perf then perf:Add("inventory.locations_scanned", 1) end
        local info = API.GetContainerItemInfo and API.GetContainerItemInfo(bag, slot) or nil
        -- Be tolerant of clients that return a link/value instead of a table,
        -- or a table whose itemID field is named differently.
        local itemID, hyperlink
        if type(info) == "table" then
          itemID = tonumber(info.itemID) or tonumber(info.itemId) or tonumber(info.id) or tonumber(info.item)
          hyperlink = info.hyperlink or info.itemLink or info.link
        elseif type(info) == "string" then
          hyperlink = info
        end
        hyperlink = hyperlink or API.GetContainerItemLink and API.GetContainerItemLink(bag, slot)
        if not itemID and hyperlink then
          itemID = tonumber(tostring(hyperlink):match("|Hitem:(%d+)") or tostring(hyperlink):match("item:(%d+)"))
        end
        if itemID then
          if perf then perf:Add("inventory.occupied_locations", 1) end
          if couldBeSupportedEquipment(itemID, hyperlink) then
            local loc = bagLocation(bag, slot)
            collectLocation(result, loc, {
              kind = "bag",
              bag = bag,
              slot = slot,
              loc = loc,
              itemID = itemID,
              physicalID = "bag:" .. tostring(bag) .. ":" .. tostring(slot),
            })
          end
        end
      end
    end
  end

  result.perf = nil
  return result
end
