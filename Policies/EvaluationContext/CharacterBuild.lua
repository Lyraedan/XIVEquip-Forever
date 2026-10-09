-- Policies/EvaluationContext/CharacterBuild.lua
-- Resolves the character's active Forever build (a per-character setting) and
-- weapon preferences, and exposes them to later phases. Forever has no
-- API-level per-tree specialization, so the build -- not the client spec ID --
-- is what scales and per-build preferences are keyed by. `specID` is still set
-- by CharacterIdentity from the client and is kept for API-dependent policies.
local addonName, XIVEquip = ...

XIVEquip:RegisterPolicy({
  id = "XIVEquip.character_build",
  phase = "evaluation_context",
  requires = { "character.class_file" },
  provides = { "character.build_id", "weapon.preferences" },
  apply = function(builder, runtime)
    local Config = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Config
    if not Config then return end
    if Config.ActiveBuildID then
      builder:Set("buildID", Config.ActiveBuildID(runtime))
    end
    if Config.ActiveWeaponPrefs then
      builder:Set("weaponPrefs", Config.ActiveWeaponPrefs(runtime))
    end
  end,
})
