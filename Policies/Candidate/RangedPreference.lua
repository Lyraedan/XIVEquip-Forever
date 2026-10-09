-- Policies/Candidate/RangedPreference.lua
-- Restricts the ranged slot (18) to the player's chosen ranged weapon type, or
-- excludes ranged entirely when set to "none". The currently equipped ranged
-- item always stays representable (the singleton frontier keeps the current
-- state), so "none" means "don't upgrade ranged", not "unequip it".
local addonName, XIVEquip = ...

local RANGED_SUBCLASSES = {
  bow = { [2] = true },
  gun = { [3] = true },
  crossbow = { [18] = true },
  wand = { [19] = true },
}

XIVEquip:RegisterPolicy({
  id = "XIVEquip.ranged_preference",
  phase = "candidate",
  groups = { "ranged" },
  requires = { "weapon.preferences" },
  apply = function(candidate, context)
    local prefs = context and context.weaponPrefs
    local preferred = prefs and prefs.ranged
    if not preferred or preferred == "any" then return nil end
    if preferred == "none" then
      return { allow = false, reason = "ranged-disabled" }
    end

    local set = RANGED_SUBCLASSES[preferred]
    if not set then return nil end
    local equip = candidate and candidate.equip
    local subclass = equip and tonumber(equip.itemSubclassID)
    if subclass and set[subclass] then return nil end
    return { allow = false, reason = "ranged-type-mismatch" }
  end,
})
