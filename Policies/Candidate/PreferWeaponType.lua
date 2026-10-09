-- Policies/Candidate/PreferWeaponType.lua
-- Small tie-break preference for the player's chosen weapon type (e.g. Orc
-- axe / Human sword crit). It only nudges otherwise-close weapons; it never
-- overrides a meaningful DPS/stat difference, and it never rejects a weapon --
-- proficiency and the hand-legality policies own eligibility.
local addonName, XIVEquip = ...

local TYPE_SUBCLASSES = {
  sword = { [7] = true, [8] = true },
  axe = { [0] = true, [1] = true },
  mace = { [4] = true, [5] = true },
  dagger = { [15] = true },
  staff = { [10] = true },
  polearm = { [6] = true },
  fist = { [13] = true },
  bow = { [2] = true },
  gun = { [3] = true },
  crossbow = { [18] = true },
  wand = { [19] = true },
  thrown = { [16] = true },
}

local WEAPON_CLASS = 2
local PREFERENCE_BONUS = 0.05

XIVEquip:RegisterPolicy({
  id = "XIVEquip.prefer_weapon_type",
  phase = "candidate",
  groups = { "weapons", "ranged" },
  requires = { "weapon.preferences" },
  apply = function(candidate, context)
    local prefs = context and context.weaponPrefs
    local preferred = prefs and prefs.type
    if not preferred or preferred == "any" then return nil end
    local set = TYPE_SUBCLASSES[preferred]
    if not set then return nil end

    local equip = candidate and candidate.equip
    if not equip or tonumber(equip.itemClassID) ~= WEAPON_CLASS then return nil end
    local subclass = tonumber(equip.itemSubclassID)
    if subclass and set[subclass] then
      return { scoreAdjustment = PREFERENCE_BONUS, reason = "preferred-weapon-type" }
    end
    return nil
  end,
})
