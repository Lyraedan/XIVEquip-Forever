-- Policies/Candidate/ArmorProficiency.lua
-- Armor subclass IDs (item subclass, ITEM_SUBCLASS_ARMOR_*): cloth=1,
-- leather=2, mail=3, plate=4, misc=5.
--
-- On modern Retail a class can wear exactly one armor type (its max), so this
-- used to reject anything whose subclass differed. On World of Warcraft:
-- Forever (original Azeroth) armor proficiency is a *progression*: a Warrior
-- can wear cloth/leather/mail at low level and only reaches plate later. The
-- correct rule is therefore "subclass <= the class's proficiency tier", not
-- "== tier". A nil/unknown tier stays permissive.
local addonName, XIVEquip = ...

local ARMOR_SLOTS = {
  [1] = true, [3] = true, [5] = true, [6] = true,
  [7] = true, [8] = true, [9] = true, [10] = true,
}

XIVEquip:RegisterPolicy({
  id = "XIVEquip.candidate_armor_proficiency",
  phase = "candidate",
  requires = { "character.armor_proficiency_subclass" },
  apply = function(candidate, context, policyContext)
    local slot = policyContext and policyContext.slot
    if not ARMOR_SLOTS[slot] then return nil end
    local equip = candidate and candidate.equip
    if not equip or equip.itemClassID ~= 4 then return nil end

    local maxSubclass = tonumber(context.armorProficiencySubclass)
    local subclass = tonumber(equip.itemSubclassID)
    -- Unknown metadata: allow (conservative failure). Otherwise only reject
    -- armor heavier than the class can currently wear.
    if maxSubclass and subclass and subclass <= maxSubclass then return nil end
    if not maxSubclass or not subclass then return nil end
    return { allow = false, reason = "wrong-armor-proficiency" }
  end,
})


