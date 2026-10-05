-- Policies/Candidate/Proficiency.lua
-- Rejects candidates the player's class cannot actually use yet. This matters
-- most for weapons: on World of Warcraft: Forever (original Azeroth) weapon
-- skills and armor proficiency are learned, so a legal-looking weapon (e.g. a
-- 2H axe on a level-8 Warrior who has not trained Axes) can be planned and
-- then fail to equip with "You do not have the required proficiency for that
-- item."
--
-- C_PlayerInfo.CanUseItem is the authoritative gate the client itself uses.
-- A nil/failed result is treated as permissive (allow), matching the
-- conservative-failure rule for candidate policies: a false rejection is worse
-- than an occasional item the player can simply Avoidlist.
local addonName, XIVEquip = ...

XIVEquip:RegisterPolicy({
  id = "XIVEquip.candidate_proficiency",
  phase = "candidate",
  apply = function(candidate)
    local itemID = candidate and tonumber(candidate.itemID)
    if not itemID then return nil end

    -- Prefer the explicit proficiency API.
    local canUse = C_PlayerInfo and C_PlayerInfo.CanUseItem
    if type(canUse) == "function" then
      local ok, usable = pcall(canUse, itemID)
      if ok and usable == false then
        return { allow = false, reason = "no-proficiency" }
      end
      if ok then return nil end
    end

    -- Fallback: IsUsableItem also returns false for items the player cannot
    -- use (though it additionally accounts for mana; we only reject on a
    -- definite false, never on the noMana flag).
    local isUsable = C_Item and C_Item.IsUsableItem
    if type(isUsable) == "function" and candidate.link then
      local ok, usable = pcall(isUsable, candidate.link)
      if ok and usable == false then
        return { allow = false, reason = "not-usable" }
      end
    end

    return nil
  end,
})
