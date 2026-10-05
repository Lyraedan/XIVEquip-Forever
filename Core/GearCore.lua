-- Gear_Core.lua
local addonName, XIVEquip = ...
local Core                = {}
local Log                 = XIVEquip.Log
local Const               = XIVEquip.Const
local API                 = XIVEquip.API
XIVEquip.Gear_Core        = Core

-- Read a stat-table value by token name, trying the literal name and the
-- matching global value (whichever the client used as the key).
local function statValue(st, name)
  for _, key in ipairs(API.TokenKeys(name)) do
    local v = st and st[key]
    if type(v) == "number" then return v end
  end
  return 0
end

-- =========================
-- Socket potential tracking (per planning pass)
-- =========================

Core._socketPotential     = Core._socketPotential or {}
Core._socketPotentialSeen = Core._socketPotentialSeen or {}

function Core.ClearSocketPotential()
  Core._socketPotential = {}
  Core._socketPotentialSeen = {}
end

function Core.AddSocketPotential(key, record)
  if not key or not record then return end
  if Core._socketPotentialSeen[key] then return end
  Core._socketPotentialSeen[key] = true
  table.insert(Core._socketPotential, record)
end

function Core.GetSocketPotential()
  return Core._socketPotential or {}
end

-- =========================
-- Public constants/lookups (unchanged)
-- =========================

Core.ARMOR              = Const.ARMOR
Core.ARMOR_SLOTS        = Const.ARMOR_SLOTS
Core.JEWELRY            = Const.JEWELRY
Core.JEWELRY_SLOTS      = Const.JEWELRY_SLOTS
Core.LOWER_ILVL_ARMOR   = Const.LOWER_ILVL_ARMOR
Core.LOWER_ILVL_JEWELRY = Const.LOWER_ILVL_JEWELRY
Core.INV_BY_EQUIPLOC    = Const.INV_BY_EQUIPLOC
Core.SLOT_EQUIPLOCS     = Const.SLOT_EQUIPLOCS
Core.ITEMCLASS_ARMOR    = Const.ITEMCLASS_ARMOR
Core.SLOT_LABEL         = Const.SLOT_LABEL

local ARMOR_SLOTS       = Core.ARMOR_SLOTS

-- debugf: Core addon plumbing: debugf.
local function debugf(slotID, fmt, ...)
  if Log and Log.Debugf then
    return Log.Debugf(slotID, fmt, ...)
  end
end

function Core.itemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|Hitem:(%d+)") or link:match("item:(%d+)"))
end

function Core.GetUniqueInfo(itemID, link)
  local itemInfo = link or itemID
  local resolvedItemID = itemID or Core.itemIDFromLink(link)
  if C_Item and type(C_Item.GetItemUniqueness) == "function" then
    local ok, category, limit = pcall(C_Item.GetItemUniqueness, itemInfo)
    if ok and category and limit then
      local categoryID = tonumber(category)
      local uniqueLimit = tonumber(limit) or 0
      if categoryID and categoryID ~= 0 and uniqueLimit > 0 then
        return "category:" .. tostring(category), uniqueLimit
      end
      if categoryID == 0 and uniqueLimit > 0 and resolvedItemID then
        return "item:" .. tostring(resolvedItemID), uniqueLimit
      end
    end
  end
  if C_Item and type(C_Item.GetItemUniquenessByID) == "function" then
    local ok, isUnique, categoryName, categoryCount, categoryID = pcall(C_Item.GetItemUniquenessByID, itemInfo)
    if ok then
      local uniqueLimit = tonumber(categoryCount) or 0
      local numericCategoryID = tonumber(categoryID)
      if numericCategoryID and numericCategoryID ~= 0 and uniqueLimit > 0 then
        return "category:" .. tostring(categoryID), uniqueLimit
      end
      if isUnique then
        return "item:" .. tostring(resolvedItemID or itemInfo), uniqueLimit > 0 and uniqueLimit or 1
      end
      if numericCategoryID == 0 and uniqueLimit > 0 and resolvedItemID then
        return "item:" .. tostring(resolvedItemID), uniqueLimit
      end
      if categoryName and uniqueLimit > 0 then
        return "category:" .. tostring(categoryName), uniqueLimit
      end
    end
  end
  return nil, nil
end

local function addUniqueCount(ctx, key, limit, delta)
  if not (ctx and key) then return end
  ctx._uniqueCounts[key] = math.max(0, (ctx._uniqueCounts[key] or 0) + delta)
  if limit then
    local n = tonumber(limit) or 1
    ctx._uniqueLimits[key] = ctx._uniqueLimits[key] and math.min(ctx._uniqueLimits[key], n) or n
  end
end

function Core.EnsurePlanContext(used)
  used = used or {}
  used._uniqueCounts = used._uniqueCounts or {}
  used._uniqueLimits = used._uniqueLimits or {}
  used._equippedUniqueBySlot = used._equippedUniqueBySlot or {}
  if used._uniqueSeeded then return used end

  for _, slotID in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }) do
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slotID) or nil
    local key, limit = Core.GetUniqueInfo(Core.itemIDFromLink(link), link)
    if key then
      used._equippedUniqueBySlot[slotID] = { key = key, limit = limit }
      addUniqueCount(used, key, limit, 1)
    end
  end

  used._uniqueSeeded = true
  return used
end

function Core.UniqueAssignmentOK(used, additions, removalSlots)
  used = Core.EnsurePlanContext(used)
  local removalsByKey = {}
  for _, slotID in ipairs(removalSlots or {}) do
    local rec = used._equippedUniqueBySlot and used._equippedUniqueBySlot[slotID]
    if rec and rec.key then removalsByKey[rec.key] = (removalsByKey[rec.key] or 0) + 1 end
  end

  local counts, limits = {}, {}
  for _, item in ipairs(additions or {}) do
    local key = item and item.uniqueKey
    if key then
      counts[key] = (counts[key] or ((used._uniqueCounts[key] or 0) - (removalsByKey[key] or 0))) + 1
      limits[key] = limits[key] and math.min(limits[key], tonumber(item.uniqueLimit) or 1)
          or math.min(used._uniqueLimits[key] or math.huge, tonumber(item.uniqueLimit) or 1)
    end
  end

  for key, count in pairs(counts) do
    if count > (limits[key] or 1) then return false end
  end
  return true
end

function Core.MarkPlannedEquip(used, pick, equipped, slotID)
  used = Core.EnsurePlanContext(used)
  if pick and pick.guid then used[pick.guid] = true end

  local old = slotID and used._equippedUniqueBySlot and used._equippedUniqueBySlot[slotID]
  if old and old.key then addUniqueCount(used, old.key, old.limit, -1) end

  if pick and pick.uniqueKey and slotID then
    used._equippedUniqueBySlot[slotID] = { key = pick.uniqueKey, limit = pick.uniqueLimit }
    addUniqueCount(used, pick.uniqueKey, pick.uniqueLimit, 1)
  elseif slotID then
    used._equippedUniqueBySlot[slotID] = nil
  end
end

local function countSocketedGems(link)
  if type(link) ~= "string" then return 0 end
  local itemString = link:match("item:([-%d:]+)")
  if not itemString then return 0 end

  local fields = {}
  for part in (itemString .. ":"):gmatch("([^:]*):") do
    fields[#fields + 1] = part
  end

  local filled = 0
  for i = 3, 6 do
    local id = tonumber(fields[i] or "0") or 0
    if id > 0 then filled = filled + 1 end
  end
  return filled
end

local function countEmptySockets(link)
  local GetItemStatsCompat = API.GetItemStats
  if type(GetItemStatsCompat) ~= "function" or type(link) ~= "string" then return 0 end
  local ok, st = pcall(GetItemStatsCompat, link)
  if not ok or type(st) ~= "table" then return 0 end

  local sockets = statValue(st, "EMPTY_SOCKET_PRISMATIC")
      + statValue(st, "EMPTY_SOCKET_PRISMATIC1")
      + statValue(st, "EMPTY_SOCKET_META")
      + statValue(st, "EMPTY_SOCKET_RED")
      + statValue(st, "EMPTY_SOCKET_BLUE")
      + statValue(st, "EMPTY_SOCKET_YELLOW")

  if sockets <= 0 then return 0 end

  local empty = sockets - countSocketedGems(link)
  if empty < 0 then empty = 0 end
  return empty
end

function Core.EvaluateSlotCandidate(slotID, equipped, candidate)
  candidate = candidate or {}
  local equippedIlvl = (equipped and equipped.ilvl) or 0
  local lowerBound = Core.JEWELRY[slotID] and Core.LOWER_ILVL_JEWELRY or Core.LOWER_ILVL_ARMOR
  local ilvl = candidate.ilvl

  local passesLowerBound = (type(ilvl) == "number") and ((ilvl == 1) or ilvl >= (equippedIlvl - lowerBound))
  if not passesLowerBound then return false end

  local equippedScore = equipped and equipped.score
  local score = candidate.score
  if equippedScore == nil or type(score) ~= "number" then return true end

  local vals
  if XIVEquip and XIVEquip.Pawn and type(XIVEquip.Pawn.GetBestScaleValuesForPlayer) == "function" then
    vals = (select(1, XIVEquip.Pawn.GetBestScaleValuesForPlayer()))
  end
  if type(vals) ~= "table" or score > (equippedScore + 1e-6) then return true end

  local weights = {
    { key = "CritRating", label = "Crit" },
    { key = "HasteRating", label = "Haste" },
    { key = "MasteryRating", label = "Mastery" },
    { key = "Versatility", label = "Vers" },
  }
  local bestWeight, bestLabel = nil, nil
  for _, stat in ipairs(weights) do
    local weight = tonumber(vals[stat.key]) or 0
    if not bestWeight or weight > bestWeight then
      bestWeight, bestLabel = weight, stat.label
    end
  end
  if not bestWeight or bestWeight <= 0 then return true end

  local emptySockets = countEmptySockets(candidate.link)
  if emptySockets and emptySockets > 0 then
    local assumedGemSecondary = 10
    local potentialScore = score + (emptySockets * assumedGemSecondary * bestWeight)
    if potentialScore > (equippedScore + 1e-6) then
      local key = candidate.guid or ((candidate.link or "") .. ":" .. tostring(slotID))
      Core.AddSocketPotential(key, {
        slotID = slotID,
        slotName = Core.SLOT_LABEL[slotID] or ("Slot " .. tostring(slotID)),
        link = candidate.link,
        emptySockets = emptySockets,
        assumedAmount = assumedGemSecondary,
        assumedStat = bestLabel,
        potentialDeltaScore = (potentialScore - equippedScore),
      })
    end
  end

  return true
end

-- =========================
-- Public helpers
-- =========================

-- guarded comparer call used by planners (returns 0 on error)
-- [XIVEquip-AUTO] Core.scoreItem: Computes a score used to compare candidate items.
function Core.scoreItem(cmp, itemLoc, slotID)
  if not (cmp and cmp.ScoreItem) then return 0 end
  local ok, v = pcall(cmp.ScoreItem, itemLoc, slotID)
  return (ok and type(v) == "number") and v or 0
end

-- Core.ItemInstanceKey: Core addon plumbing: item instance key.
function Core.ItemInstanceKey(itemLoc)
  if C_Item and C_Item.GetItemGUID and itemLoc then
    local ok, guid = pcall(C_Item.GetItemGUID, itemLoc)
    if ok and guid and guid ~= "" then return guid end
  end
  local link
  if C_Item and C_Item.GetItemLink and itemLoc then
    local ok, resolved = pcall(C_Item.GetItemLink, itemLoc)
    if ok then link = resolved end
  end
  local id = link and tonumber(link:match("|Hitem:(%d+)"))
  local bag, slot = itemLoc and itemLoc.bagID, itemLoc and itemLoc.slotIndex
  return table.concat({ id or 0, bag or -1, slot or -1 }, ":")
end

-- Core.itemGUID: Core addon plumbing: item guid.
function Core.itemGUID(loc)
  if not loc then return nil end
  local target = (type(loc) == "table" and loc._raw) or loc
  if C_Item and C_Item.GetItemGUID and (type(target) == "userdata" or type(target) == "table") then
    local ok, guid = pcall(C_Item.GetItemGUID, target)
    if ok and type(guid) == "string" and guid ~= "" then return guid end
  end
  return nil
end

-- Core.getItemLevel: Core addon plumbing: get item level.
function Core.getItemLevel(link, itemLoc)
  -- 1) Prefer a real ItemLocation if present (most accurate for current ilvl)
  local target = (type(itemLoc) == "table" and itemLoc._raw) or itemLoc
  if (type(target) == "userdata" or type(target) == "table") and C_Item and C_Item.DoesItemExist then
    local okExist, exists = pcall(C_Item.DoesItemExist, target)
    if okExist and exists then
      local ok, cur = pcall(C_Item.GetCurrentItemLevel, target)
      if ok and type(cur) == "number" and cur > 0 then
        return cur
      end
    end
  end

  -- 2) Try cached API by link
  if link then
    local il = select(4, API.GetItemInfo(link)) -- item level here is 4th
    if type(il) == "number" and il > 0 then
      return il
    end

    -- 3) Fallback: detailed API (works even when not fully cached yet)
    local ok, det = pcall(API.GetDetailedItemLevelInfo, link)
    if ok and type(det) == "number" and det > 0 then
      return det
    end
  end

  return 0
end

-- Core.getItemLevelFromLink: Core addon plumbing: get item level from link.
function Core.getItemLevelFromLink(link)
  return Core.getItemLevel(link, nil)
end

-- Core.getItemLevelFromLocation: Core addon plumbing: get item level from location.
function Core.getItemLevelFromLocation(loc)
  return Core.getItemLevel(nil, loc)
end

-- Read currently equipped for a slot (unchanged logic)
-- [XIVEquip-AUTO] Core.equippedBasics: Helper for Core module.
function Core.equippedBasics(slotID, comparer)
  local loc = API.EquipmentSlotLocation(slotID)
  local link = GetInventoryItemLink and GetInventoryItemLink("player", slotID) or nil
  if not link then return nil end

  local ilvl = Core.getItemLevelFromLink(link)

  local equipLoc = link and select(9, API.GetItemInfo(link)) or nil

  -- Score against a real ItemLocation only when the constructor produced one;
  -- otherwise pass the inventory slot, which the comparer's link fallback
  -- handles.
  local scoreTarget = loc
  if type(loc) == "table" and not loc._isItemLocation then scoreTarget = slotID end
  local score = nil
  if comparer and comparer.ScoreItem then
    local ok, v = pcall(comparer.ScoreItem, scoreTarget, slotID)
    if ok and type(v) == "number" then score = v end
  end

  return { loc = loc, slot = slotID, link = link, ilvl = ilvl, score = score, equipLoc = equipLoc }
end

-- Equip a bag item into a specific slot (unchanged logic)
-- [XIVEquip-AUTO] Core.equipByBasics: Applies equipment changes (gear/weapons) for the addon.
-- skipFinalClear (optional): an unbound BOE/Warbound-Until-Equipped item
-- doesn't resolve synchronously -- the client parks it on the cursor and
-- fires EQUIP_BIND_CONFIRM (or the _REFUNDABLE/_TRADEABLE variant) while it
-- waits for the user to accept or cancel Blizzard's own popup. Clearing the
-- cursor immediately afterward -- as this function always used to,
-- unconditionally -- discards that pending state and invalidates the popup,
-- so the confirmation disappears before the user can act on it. Callers that
-- already know (via
-- whatever bind-type check they use) that the item might need confirmation
-- should pass true here, and clear the cursor themselves once the wait
-- actually resolves.
function Core.equipByBasics(pick, skipFinalClear)
  if not pick then return nil end

  local loc = pick.loc or pick.itemLoc
  local bag, slot = nil, nil
  local locType = type(loc)

  -- Our wrappers carry the coordinates directly; prefer them over the raw
  -- ItemLocation accessors (which are unreliable on Forever).
  if locType == "table" and (loc.equipmentSlot or loc.bagID ~= nil) then
    if loc.equipmentSlot then
      local inv = loc.equipmentSlot
      if pick.targetSlot and pick.targetSlot ~= inv and PickupInventoryItem and EquipCursorItem then
        ClearCursor()
        PickupInventoryItem(inv)
        EquipCursorItem(pick.targetSlot)
        if not skipFinalClear then ClearCursor() end
        return GetInventoryItemLink("player", pick.targetSlot) or pick.link
      end
      return GetInventoryItemLink("player", inv) or pick.link
    end
    bag, slot = loc.bagID, loc.slotIndex
  elseif loc and (locType == "table" or locType == "userdata") and loc.GetEquipmentSlot then
    local inv = loc:GetEquipmentSlot()
    if inv then
      if pick.targetSlot and pick.targetSlot ~= inv and PickupInventoryItem and EquipCursorItem then
        ClearCursor()
        PickupInventoryItem(inv)
        EquipCursorItem(pick.targetSlot)
        if not skipFinalClear then ClearCursor() end
        return GetInventoryItemLink("player", pick.targetSlot) or pick.link
      end
      return GetInventoryItemLink("player", inv) or pick.link
    end
    if loc.GetBagAndSlot then
      bag, slot = loc:GetBagAndSlot()
    end
  end

  if not bag then
    bag, slot = pick.bagID, pick.slotIndex
    if (bag == nil or slot == nil) and locType == "table" and loc then
      bag, slot = loc.bagID, loc.slotIndex
    end
  end
  if not bag or not slot then
    return pick.link
  end

  local invSlot = pick.targetSlot or (pick.equipLoc and Core.INV_BY_EQUIPLOC[pick.equipLoc]) or nil

  ClearCursor()
  API.PickupContainerItem(bag, slot)
  if invSlot then
    EquipCursorItem(invSlot)
  else
    EquipCursorItem()
  end
  if not skipFinalClear then ClearCursor() end

  return (invSlot and GetInventoryItemLink("player", invSlot)) or pick.link
end

-- Core.equipLocMatchesSlot: Core addon plumbing: equip loc matches slot.
function Core.equipLocMatchesSlot(equipLoc, slotID)
  local allowed = Core.SLOT_EQUIPLOCS[slotID]
  return allowed and allowed[equipLoc] or false
end

-- Core.playerArmorSubclass: Core addon plumbing: player armor subclass.
function Core.playerArmorSubclass()
  local class = select(2, UnitClass("player"))
  local map = {
    WARRIOR = 4,
    PALADIN = 4,
    DEATHKNIGHT = 4,
    HUNTER = 3,
    SHAMAN = 3,
    EVOKER = 3,
    ROGUE = 2,
    MONK = 2,
    DEMONHUNTER = 2,
    DRUID = 2,
    MAGE = 1,
    PRIEST = 1,
    WARLOCK = 1,
  }
  return map[class]
end

-- Checks if the given item is valid armor type for the player’s class
-- jewelry and cloaks are always valid
-- [XIVEquip-AUTO] Core.equipIsValidArmorType: Applies equipment changes (gear/weapons) for the addon.
function Core.equipIsValidArmorType(itemID, slotID, expectedArmorSubclass)
  if not itemID then return false end
  -- If this slot isn't restricted armor, always allow
  if not Core.ARMOR[slotID] then
    return true
  end

  local _, _, _, _, _, classID, subclassID = API.GetItemInfoInstant(itemID)
  if not classID or not subclassID then
    -- Be conservative on missing data for armor slots
    return false
  end

  if classID ~= Core.ITEMCLASS_ARMOR then
    return true -- not an armor item, don’t restrict
  end

  expectedArmorSubclass = expectedArmorSubclass or (Core.playerArmorSubclass and Core.playerArmorSubclass())
  if not expectedArmorSubclass then
    -- If we can't determine the player's proficiency, fail safe.
    return false
  end

  return subclassID == expectedArmorSubclass
end

-- =========================
-- Selection primitive
-- =========================

do
  -- Local aliases
  local equippedBasics        = Core.equippedBasics
  local equipLocMatchesSlot   = Core.equipLocMatchesSlot
  local equipIsValidArmorType = Core.equipIsValidArmorType
  local getItemLevelFromLink  = Core.getItemLevelFromLink
  local itemGUID              = Core.itemGUID
  local JEWELRY               = Core.JEWELRY
  local LOWER_ILVL_ARMOR      = Core.LOWER_ILVL_ARMOR
  local LOWER_ILVL_JEWELRY    = Core.LOWER_ILVL_JEWELRY

  local EPS                   = 1e-6

  -- Exported: Core.chooseForSlot (slot-agnostic; works for jewelry as-is)
  function Core.chooseForSlot(comparer, slotID, expectedArmorSubclass, used)
    local dbg                 = debugf
    local equipped            = equippedBasics(slotID, comparer)
    local equippedIlvl        = (equipped and equipped.ilvl) or 0
    local equippedScore       = (equipped and equipped.score) or nil
    local lowerBound          = JEWELRY[slotID] and LOWER_ILVL_JEWELRY or LOWER_ILVL_ARMOR

    -- Socket potential config (used to estimate whether an item with an empty socket could become an upgrade)
    local assumedGemSecondary = 10

    -- Determine the best (highest-weight) secondary stat for the active Pawn scale.
    -- Returns: bestWeight (number), bestLabel (string)
    local bestSecondaryWeight, bestSecondaryLabel
    do
      local vals
      if XIVEquip and XIVEquip.Pawn and type(XIVEquip.Pawn.GetBestScaleValuesForPlayer) == "function" then
        vals = (select(1, XIVEquip.Pawn.GetBestScaleValuesForPlayer()))
      end
      if type(vals) == "table" then
        local c = tonumber(vals.CritRating) or 0
        local h = tonumber(vals.HasteRating) or 0
        local m = tonumber(vals.MasteryRating) or 0
        local v = tonumber(vals.Versatility) or 0
        bestSecondaryWeight = c
        bestSecondaryLabel = "Crit"
        if h > bestSecondaryWeight then bestSecondaryWeight, bestSecondaryLabel = h, "Haste" end
        if m > bestSecondaryWeight then bestSecondaryWeight, bestSecondaryLabel = m, "Mastery" end
        if v > bestSecondaryWeight then bestSecondaryWeight, bestSecondaryLabel = v, "Vers" end
        if bestSecondaryWeight <= 0 then
          bestSecondaryWeight, bestSecondaryLabel = nil, nil
        end
      end
    end

    local GetItemStatsCompat = API.GetItemStats

    -- Count how many gems are already socketed on this specific item link.
    -- ItemString fields: itemID:enchant:gem1:gem2:gem3:gem4:...
    local function countSocketedGems(link)
      if type(link) ~= "string" then return 0 end
      local itemString = link:match("item:([-%d:]+)")
      if not itemString then return 0 end

      local fields = {}
      -- preserve empty fields
      for part in (itemString .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = part
      end

      local filled = 0
      for i = 3, 6 do -- gem1..gem4
        local id = tonumber(fields[i] or "0") or 0
        if id > 0 then filled = filled + 1 end
      end
      return filled
    end

    -- "EMPTY_SOCKET_*" stats from GetItemStats indicate the presence of sockets,
    -- not whether they are unfilled. Translate into true empty sockets by
    -- subtracting the number of already-socketed gems.
    local function countEmptySockets(link)
      if type(GetItemStatsCompat) ~= "function" or type(link) ~= "string" then return 0 end
      local ok, st = pcall(GetItemStatsCompat, link)
      if not ok or type(st) ~= "table" then return 0 end

      local sockets = statValue(st, "EMPTY_SOCKET_PRISMATIC")
          + statValue(st, "EMPTY_SOCKET_PRISMATIC1")
          + statValue(st, "EMPTY_SOCKET_META")
          + statValue(st, "EMPTY_SOCKET_RED")
          + statValue(st, "EMPTY_SOCKET_BLUE")
          + statValue(st, "EMPTY_SOCKET_YELLOW")

      if sockets <= 0 then return 0 end

      local filled = countSocketedGems(link)
      local empty = sockets - filled
      if empty < 0 then empty = 0 end
      return empty
    end

    local best = nil
    local hadPending = false

    for bag = 0, API.NumBagSlots() do
      local num = API.GetContainerNumSlots(bag) or 0
      for slot = 1, num do
        local info = API.GetContainerItemInfo(bag, slot)
        if info and info.itemID then
          local _, _, _, equipLoc, _, classID, subclassID = API.GetItemInfoInstant(info.itemID)
          if not equipLoc then
            hadPending = true
            if C_Item and C_Item.RequestLoadItemData then
              local itemLoc = API.BagSlotLocation(bag, slot)
              pcall(C_Item.RequestLoadItemData, itemLoc)
            end
          elseif equipLocMatchesSlot(equipLoc, slotID)
              and equipIsValidArmorType(info.itemID, slotID, expectedArmorSubclass)
          then
            if dbg then dbg(slotID, "consider itemID=%s equipLoc=%s", tostring(info.itemID), tostring(equipLoc)) end

            local link = info.hyperlink or API.GetContainerItemLink(bag, slot)
            -- Prefer the runtime/current item level for bag items when available (handles heirlooms)
            local itemLoc = API.BagSlotLocation(bag, slot)
            local ilvl = Core.getItemLevelFromLink(link)

            if dbg then dbg(slotID, "candidate ilvl=%s link=%s", tostring(ilvl or "nil"), tostring(link or "nil")) end

            -- Skip items the character cannot equip yet (e.g., higher level requirement)
            local reqLevel = select(5, API.GetItemInfo(link))
            if type(reqLevel) == "number" and reqLevel > UnitLevel("player") then
              if dbg then
                dbg(slotID, "skip: requires level %s (player=%s) link=%s",
                  tostring(reqLevel), tostring(UnitLevel("player")), tostring(link or "nil"))
              end
            else
              -- Treat ilvl == 1 (heirloom reported as level 1) as "unknown" and don't reject it
              local passesLowerBound = (type(ilvl) == "number") and ((ilvl == 1) or ilvl >= (equippedIlvl - lowerBound))
              if passesLowerBound then
                local guid = itemGUID(itemLoc)
                if not (used and guid and used[guid]) then
                  local score = nil
                  if itemLoc and C_Item and C_Item.RequestLoadItemData then
                    pcall(C_Item.RequestLoadItemData, itemLoc)
                  end
                  if comparer and comparer.ScoreItem then
                    local ok, v = pcall(comparer.ScoreItem, itemLoc, slotID)
                    if ok and type(v) == "number" then score = v end
                  end
                  local uniqueKey, uniqueLimit = Core.GetUniqueInfo(info.itemID, link)
                  local passesPolicy = Core.EvaluateSlotCandidate(slotID, equipped, {
                    link = link,
                    loc = itemLoc,
                    ilvl = ilvl,
                    score = score,
                    guid = guid,
                  })
                  local uniqueOK = Core.UniqueAssignmentOK(used, { { uniqueKey = uniqueKey, uniqueLimit = uniqueLimit } }, { slotID })
                  if dbg then
                    if score then
                      dbg(slotID, "scored: %s", tostring(score))
                    else
                      dbg(slotID, "skip: no score from comparer")
                    end
                  end
                  if score and passesPolicy and uniqueOK and (not best or score > best.score) then
                    if dbg then
                      dbg(slotID, "new best: score=%s ilvl=%s link=%s (prev=%s)",
                        tostring(score), tostring(ilvl), tostring(link or "nil"),
                        tostring(best and best.score or "nil"))
                    end
                    best = {
                      loc        = itemLoc,
                      guid       = guid,
                      link       = link,
                      score      = score,
                      ilvl       = ilvl,
                      equipLoc   = equipLoc,
                      targetSlot = slotID,
                      itemID     = info.itemID,
                      uniqueKey  = uniqueKey,
                      uniqueLimit = uniqueLimit,
                    }
                  end

                  -- Socket potential detection: if item has empty sockets and is not currently an upgrade,
                  -- estimate whether it could become an upgrade by adding a "baseline" gem.
                  if equippedScore ~= nil
                      and bestSecondaryWeight
                      and type(score) == "number"
                      and score <= (equippedScore + EPS)
                  then
                    local emptySockets = countEmptySockets(link)
                    if emptySockets and emptySockets > 0 then
                      local potentialDelta = emptySockets * assumedGemSecondary * bestSecondaryWeight
                      local potentialScore = score + potentialDelta
                      if potentialScore > (equippedScore + EPS) then
                        local key = guid or (link .. ":" .. tostring(slotID))
                        Core.AddSocketPotential(key, {
                          slotID = slotID,
                          slotName = Core.SLOT_LABEL[slotID] or ("Slot " .. tostring(slotID)),
                          link = link,
                          emptySockets = emptySockets,
                          assumedAmount = assumedGemSecondary,
                          assumedStat = bestSecondaryLabel,
                          potentialDeltaScore = (potentialScore - equippedScore),
                        })
                      end
                    end
                  end
                else
                  if dbg then dbg(slotID, "skip: already used guid=%s link=%s", tostring(guid), tostring(link or "nil")) end
                end
              else
                if dbg then
                  dbg(slotID, "skip: below lower bound (cand=%s, equipped=%s, bound=%s)",
                    tostring(ilvl or "nil"), tostring(equippedIlvl or "nil"), tostring(lowerBound))
                end
              end
            end -- closes the reqLevel gate
          end
        end
      end
    end


    -- Guard: only upgrade if strictly better than what’s on the character.
    if best then
      if equippedScore ~= nil then
        if best.score <= (equippedScore + EPS) then
          if dbg then
            dbg(slotID, "reject: score-not-better (best=%s, equipped=%s)",
              tostring(best.score), tostring(equippedScore))
          end
          return nil, equipped, hadPending
        end
      else
        if best.ilvl <= equippedIlvl then
          if dbg then
            dbg(slotID, "reject: ilvl-not-better (best=%s, equipped=%s)",
              tostring(best.ilvl), tostring(equippedIlvl))
          end
          return nil, equipped, hadPending
        end
      end
    else
      if dbg then dbg(slotID, "no candidate passed filters") end
    end

    return best, equipped, hadPending
  end
end

-- =========================
-- shared helper to append to plan + build a change row
-- =========================
-- [XIVEquip-AUTO] Core.appendPlanAndChange: Helper for Core module.
function Core.appendPlanAndChange(plan, changes, slotID, pick, equipped)
  -- Add to plan
  table.insert(plan, pick)

  -- Build the UI change row (exactly the same fields you’re using)
  local oldLink  = (equipped and equipped.link) or "|cff888888(None)|r"
  local newLink  = pick.link or oldLink
  local newScore = tonumber((pick and pick.score)) or 0
  local oldScore = tonumber((equipped and equipped.score)) or 0
  local newIlvl  = tonumber((pick and pick.ilvl) or 0) or 0
  local oldIlvl  = tonumber((equipped and equipped.ilvl) or 0) or 0

  local row      = {
    slot        = slotID,
    slotName    = Core.SLOT_LABEL[slotID] or ("Slot " .. slotID),
    oldLink     = oldLink,
    newLink     = newLink,
    deltaScore  = newScore - oldScore,
    deltaIlvl   = newIlvl - oldIlvl,
    newLoc      = pick.loc,
    oldLoc      = equipped and equipped.loc or nil,
    scaleValues = pick.scaleValues,
  }

  table.insert(changes, row)
  return row
end

-- try-pick helper that runs chooseForSlot, appends outputs, and marks `used`.
-- Returns pick, equipped, chosen (boolean).
-- [XIVEquip-AUTO] Core.tryChooseAppend: Helper for Core module.
function Core.tryChooseAppend(plan, changes, slotID, comparer, expectedArmorSubclass, used)
  local pick, equipped, pending = Core.chooseForSlot(comparer, slotID, expectedArmorSubclass, used)

  -- No pick: log and return
  if not pick then
    if debugf then
      debugf(slotID, "no pick; equipped ilvl=%s score=%s link=%s",
        tostring(equipped and equipped.ilvl or "nil"),
        tostring(equipped and equipped.score or "nil"),
        tostring(equipped and equipped.link or "nil"))
    end
    return nil, equipped, false, pending
  end

  -- We have a pick: log, append, mark used
  if debugf then
    debugf(slotID, "picked ilvl=%s score=%s link=%s  vs equipped ilvl=%s score=%s",
      tostring(pick.ilvl or "nil"),
      tostring(pick.score or "nil"),
      tostring(pick.link or "nil"),
      tostring(equipped and equipped.ilvl or "nil"),
      tostring(equipped and equipped.score or "nil"))
  end

  Core.appendPlanAndChange(plan, changes, slotID, pick, equipped)
  if used then Core.MarkPlannedEquip(used, pick, equipped, slotID) end
  return pick, equipped, true, pending
end

-- Resolve an item link from a wrapped location, ItemLocation, or slotID.
-- [XIVEquip-AUTO] Core.linkFromLocation: Helper for Core module.
function Core.linkFromLocation(location)
  if not location then return nil end

  -- Preferred: our wrappers carry the inventory/bag coordinates directly, so
  -- we can use the always-available inventory/container APIs and never pass a
  -- wrong-typed value to the C_Item accessors (which on Forever reject
  -- anything that isn't a real ItemLocation).
  if type(location) == "table" then
    if location.equipmentSlot and GetInventoryItemLink then
      local ok, link = pcall(GetInventoryItemLink, "player", location.equipmentSlot)
      if ok and link then return link end
    end
    if location.bagID ~= nil and location.slotIndex ~= nil and API.GetContainerItemLink then
      local ok, link = pcall(API.GetContainerItemLink, location.bagID, location.slotIndex)
      if ok and link then return link end
    end
    -- A raw ItemLocation object (not one of our wrappers): ask C_Item.
    local target = location._raw or location
    if C_Item and C_Item.GetItemLink then
      local ok, link = pcall(C_Item.GetItemLink, target)
      if ok and type(link) == "string" then return link end
    end
  end

  -- Bare equipment slot id.
  if type(location) == "number" and GetInventoryItemLink then
    local ok, link = pcall(GetInventoryItemLink, "player", location)
    if ok and link then return link end
  end

  -- Last resort: request a load and retry if we have a real ItemLocation.
  local target = (type(location) == "table" and (location._raw or location)) or location
  if C_Item and C_Item.GetItemLink and (type(target) == "userdata" or type(target) == "table") then
    if C_Item.DoesItemExist then pcall(C_Item.DoesItemExist, target) end
    if C_Item.RequestLoadItemData then pcall(C_Item.RequestLoadItemData, target) end
    local ok, link = pcall(C_Item.GetItemLink, target)
    if ok and type(link) == "string" then return link end
  end

  return nil
end
