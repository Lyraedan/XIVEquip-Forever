-- Policies/EvaluationContext/ClassSpecWeaponCapabilities.lua
-- Resolves the eight weapon-hand capability flags for the active build plus the
-- character's Weapon Preference, then applies Forever's Dual Wield ability
-- gate.
--
-- Forever keeps vanilla's weapon model: a class's weapon *proficiency* is
-- trained (and checked by the proficiency policy via C_PlayerInfo.CanUseItem),
-- while Dual Wield is a separate trained ability. This policy expresses which
-- hand combinations the planner may consider; the proficiency policy and the
-- dual-wield gate below do the actual filtering.
local addonName, XIVEquip = ...

-- style -> capability flags. `auto` is permissive and relies on the
-- proficiency policy to drop anything the character cannot actually use.
local STYLE_FLAGS = {
  auto = { allow2H = true, allowMH1H = true, allowDualWield = true, allowOffhandWeapon = true, allowShield = true, allowHoldable = true },
  two_hand = { allow2H = true },
  dual_wield = { allowMH1H = true, allowDualWield = true, allowOffhandWeapon = true },
  mh_shield = { allowMH1H = true, allowShield = true },
  mh_offhand = { allowMH1H = true, allowOffhandWeapon = true, allowHoldable = true },
}

local function flagsForStyle(style)
  return STYLE_FLAGS[style] or STYLE_FLAGS.auto
end

-- True when the character can put a weapon in the offhand; false when the
-- client says they cannot; nil when the client exposes no way to tell (in
-- which case the gate stays out of the way rather than blocking everyone).
-- Dual Wield is trained (Warrior level 20, Rogue, Enhancement Shaman talent),
-- so a low-level character reports false even though the class eventually can.
-- IsDualWielding is checked first so a character mid-dual-wield always passes.
local function canDualWield()
  local available = false
  if type(IsDualWielding) == "function" then
    available = true
    local ok, value = pcall(IsDualWielding)
    if ok and value == true then return true end
  end
  if type(CanDualWield) == "function" then
    available = true
    local ok, value = pcall(CanDualWield)
    if ok and value == true then return true end
  end
  if available then return false end
  return nil
end

XIVEquip:RegisterPolicy({
  id = "XIVEquip.class_spec_weapon_capabilities",
  phase = "evaluation_context",
  requires = { "character.build_id", "weapon.preferences" },
  provides = {
    "capability.XIVEquip.allow_two_hand",
    "capability.XIVEquip.allow_dual_wield",
    "capability.XIVEquip.allow_offhand_weapon",
    "capability.XIVEquip.allow_shield",
    "capability.XIVEquip.allow_holdable",
    "capability.XIVEquip.allow_main_hand_one_hand",
    "capability.XIVEquip.titan_grip",
    "capability.XIVEquip.require_shield",
  },
  apply = function(builder, runtime)
    local prefs = builder:Get("weaponPrefs") or {}
    local flags = flagsForStyle(prefs.style)

    local P = {
      allow2H = flags.allow2H == true,
      allowMH1H = flags.allowMH1H == true,
      allowDualWield = flags.allowDualWield == true,
      allowOffhandWeapon = flags.allowOffhandWeapon == true,
      allowShield = flags.allowShield == true,
      allowHoldable = flags.allowHoldable == true,
      -- Titan's Grip does not exist in Forever's vanilla model.
      allowTitanGrip = false,
      -- A style is a preference, not a hard requirement: allow_shield lets the
      -- planner use a shield when one is available while still permitting an
      -- empty offhand when it is not.
      requireShield = false,
    }

    if canDualWield() == false then
      P.allowDualWield = false
      P.allowOffhandWeapon = false
      P.allowTitanGrip = false
    end

    builder:SetCapability("XIVEquip.allow_two_hand", P.allow2H)
    builder:SetCapability("XIVEquip.allow_dual_wield", P.allowDualWield)
    builder:SetCapability("XIVEquip.allow_offhand_weapon", P.allowOffhandWeapon)
    builder:SetCapability("XIVEquip.allow_shield", P.allowShield)
    builder:SetCapability("XIVEquip.allow_holdable", P.allowHoldable)
    builder:SetCapability("XIVEquip.allow_main_hand_one_hand", P.allowMH1H)
    builder:SetCapability("XIVEquip.titan_grip", P.allowTitanGrip)
    builder:SetCapability("XIVEquip.require_shield", P.requireShield)
  end,
})
