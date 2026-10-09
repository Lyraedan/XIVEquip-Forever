-- XIVEquip.lua
local addonName, XIVEquip = ...
local L = XIVEquip.L

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

local status

local function addonVersion()
  local metadata = XIVEquip.API and XIVEquip.API.GetAddOnMetadata
  if type(metadata) ~= "function" then return nil end

  local ok, version = pcall(metadata, addonName, "Version")
  if ok and version and version ~= "" then return tostring(version) end
  return nil
end

-- message gates
-- [XIVEquip-AUTO] msgLogin: Helper for . module.
local function msgLogin(text)
  if XIVEquip.Settings and XIVEquip.Settings.GetMessage and XIVEquip.Settings:GetMessage("Login") then
    print(L.AddonPrefix .. text)
  end
end

local function currentBuildLabel()
  local Config = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Config
  local build = Config and Config.ActiveBuild and Config.ActiveBuild()
  local name = (build and build.name and build.name ~= "") and build.name or "Default"

  local scaleLabel
  local Runtime = XIVEquip.Planning and XIVEquip.Planning.Runtime
  if Runtime and Runtime.Live and Config and Config.ResolvedScaleDisplayLabel then
    local runtime = Runtime.Live()
    if runtime and runtime.ResolveWeights then
      local ok, scale = pcall(runtime.ResolveWeights)
      if runtime.Close then pcall(runtime.Close) end
      if ok and scale then
        local okLabel, label = pcall(Config.ResolvedScaleDisplayLabel, scale)
        if okLabel and label and label ~= "" then scaleLabel = label end
      end
    end
  end

  if scaleLabel then return tostring(name) .. " | " .. tostring(scaleLabel) end
  return tostring(name)
end

local function msgLoaded(buildText)
  local version = addonVersion() or "unknown"
  msgLogin(string.format(L.Loaded_Format or "Loaded v%s. Active build: %s.", version,
    tostring(buildText or "Default")))
end

-- msgError: msg error.
local function msgError(text) print(L.AddonPrefix .. text) end
-- XIVEquip.ShouldShowEquipMsgs: should show equip msgs.
function XIVEquip.ShouldShowEquipMsgs()
  return XIVEquip.Settings and XIVEquip.Settings.GetMessage and XIVEquip.Settings:GetMessage("Equip")
end

-- Callback used in XIVEquip.lua to run inline logic.
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    -- Forever does not reload SavedVariables; rebuild the settings table from
    -- the addon's own CVar backup before initialising defaults.
    if XIVEquip.Persistence then
      if XIVEquip.Persistence.Initialize then pcall(XIVEquip.Persistence.Initialize) end
      if XIVEquip.Persistence.RestoreIfNeeded then pcall(XIVEquip.Persistence.RestoreIfNeeded) end
    end
    if XIVEquip.Settings and XIVEquip.Settings.Initialize then
      XIVEquip.Settings:Initialize()
    end
  elseif event == "PLAYER_LOGIN" then
    if XIVEquip.Profiles and XIVEquip.Profiles.Config
        and XIVEquip.Profiles.Config.EnsureCurrent then
      XIVEquip.Profiles.Config.EnsureCurrent()
    end
    -- Finalize the policy registry now, not lazily on first use: every
    -- normal addon (including a third party declaring XIVEquip as a
    -- dependency and registering via C_AddOns.GetAddOnLocalTable) has had
    -- the chance to load and call RegisterPolicy by PLAYER_LOGIN. Locking
    -- here closes the registration window -- doc 15.9's "no policy
    -- discovery/resolution/mutation in the hot path" requires the arrays
    -- to already be resolved by the time anything evaluates equipment,
    -- even though nothing evaluates against them yet (Phase 3+ work).
    if XIVEquip.Policies and XIVEquip.Policies.DefaultRegistry and XIVEquip.Policies.Resolver then
      local registry = XIVEquip.Policies.DefaultRegistry
      local ok, resolvedOrErr = pcall(XIVEquip.Policies.Resolver.Finalize, registry:Pending())
      if ok then
        XIVEquip.Policies.Resolved = resolvedOrErr
      else
        print((XIVEquip.L and XIVEquip.L.AddonPrefix or "XIVEquip: ") ..
          "Policy registry finalization failed: " .. tostring(resolvedOrErr))
      end
      registry:Lock()
    end

    msgLoaded(currentBuildLabel())
  end
end)

-- Called by the UI button
-- [XIVEquip-AUTO] XIVEquip:EquipBestGear: Applies equipment changes (gear/weapons) for the addon.
function XIVEquip:EquipBestGear(opts)
  if not XIVEquip.Gear or not XIVEquip.Gear.EquipBest then
    msgError("Gear planner is not available.")
    return
  end
  XIVEquip.Gear:EquipBest(opts)
end
