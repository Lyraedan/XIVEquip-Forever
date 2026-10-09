-- XIVWeights/Config.lua
-- SavedVariables-facing configuration for native XIVWeights resolution.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
local XIVWeights = XIVEquip.XIVWeights

local Config = {}
XIVWeights.Config = Config

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

local function settings()
  if XIVEquip.Settings and XIVEquip.Settings.Get then return XIVEquip.Settings:Get() end
  _G.XIVEquip_Settings = _G.XIVEquip_Settings or {}
  return _G.XIVEquip_Settings
end

local function characterKeyFor(runtime)
  runtime = runtime or {}
  local unitName = runtime.UnitName or _G.UnitName
  local realmName = runtime.GetRealmName or _G.GetRealmName
  local name, realm
  if type(unitName) == "function" then name, realm = unitName("player") end
  if (not realm or realm == "") and type(realmName) == "function" then realm = realmName() end
  local Profiles = XIVEquip.Profiles and XIVEquip.Profiles.Config
  if Profiles and Profiles.CharacterKey then return Profiles.CharacterKey(name, realm) end
  return name and (tostring(name) .. (realm and realm ~= "" and (" " .. tostring(realm)) or "")) or nil
end

local function classFileFor(runtime)
  runtime = runtime or {}
  local unitClass = runtime.UnitClass or _G.UnitClass
  if type(unitClass) == "function" then
    local _, classFile = unitClass("player")
    return classFile
  end
  return nil
end

-- =========================
-- Builds (named, per class) + active build (per character)
-- =========================
-- A Build ties a Talent Tree, a Scale, and weapon preferences together.
-- `CharacterBuilds[characterKey]` stores the active build for the character.
-- style  : auto | two_hand | dual_wield | mh_shield | mh_offhand
-- type   : any | sword | axe | mace | dagger | staff | polearm | fist
-- ranged : any | bow | gun | crossbow | wand | none
local WEAPON_STYLES = {
  auto = true, two_hand = true, dual_wield = true, mh_shield = true, mh_offhand = true,
}
local WEAPON_TYPES = {
  any = true, sword = true, axe = true, mace = true, dagger = true,
  staff = true, polearm = true, fist = true,
}
local RANGED_TYPES = {
  any = true, bow = true, gun = true, crossbow = true, wand = true, none = true,
}
Config.WeaponStyles = WEAPON_STYLES
Config.WeaponTypes = WEAPON_TYPES
Config.RangedTypes = RANGED_TYPES

local DEFAULT_WEAPON = { style = "auto", type = "any", ranged = "any" }

local function normalizeWeapon(stored, def)
  def = def or DEFAULT_WEAPON
  local function pick(field, valid, fallback)
    local value = type(stored) == "table" and stored[field]
    if valid[value] then return value end
    if valid[def[field]] then return def[field] end
    return fallback
  end
  return {
    style = pick("style", WEAPON_STYLES, "auto"),
    type = pick("type", WEAPON_TYPES, "any"),
    ranged = pick("ranged", RANGED_TYPES, "any"),
  }
end
Config.NormalizeWeapon = normalizeWeapon

local function treeWeapon(treeID)
  local defaults = XIVWeights.Builtin and XIVWeights.Builtin.Defaults
  local def = defaults and defaults.BuildForID and defaults.BuildForID(treeID)
  return def and def.weapon or nil
end

local function buildsStore(classFile)
  classFile = classFile and string.upper(tostring(classFile)) or nil
  if not classFile then return nil end
  local st = settings()
  st.Builds = type(st.Builds) == "table" and st.Builds or {}
  local store = type(st.Builds[classFile]) == "table" and st.Builds[classFile] or nil
  if not store then
    store = { Items = {} }
    st.Builds[classFile] = store
  end
  store.Items = type(store.Items) == "table" and store.Items or {}
  return store
end

-- Ensure a class has a default build for each of its talent trees.
function Config.EnsureClassBuilds(classFile)
  local store = buildsStore(classFile)
  if not store then return nil end
  local defaults = XIVWeights.Builtin and XIVWeights.Builtin.Defaults
  for _, tree in ipairs((defaults and defaults.SpecsForClass(classFile)) or {}) do
    local id = "tree:" .. tostring(tree.id)
    if store.Items[id] == nil then
      store.Items[id] = {
        id = id,
        name = tree.name or ("Tree " .. tostring(tree.id)),
        treeID = tree.id,
        scaleID = nil,
        weapon = normalizeWeapon(tree.weapon, DEFAULT_WEAPON),
      }
    end
  end
  return store
end

function Config.ListBuilds(classFile)
  local store = Config.EnsureClassBuilds(classFile)
  local out = {}
  if not store then return out end
  for _, build in pairs(store.Items) do out[#out + 1] = build end
  table.sort(out, function(a, b)
    local at, bt = tonumber(a.treeID) or 0, tonumber(b.treeID) or 0
    if at ~= bt then return at < bt end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end

function Config.GetBuild(classFile, buildID)
  local store = Config.EnsureClassBuilds(classFile)
  return store and buildID and store.Items[buildID] or nil
end

function Config.FindBuild(buildID)
  local st = settings()
  st.Builds = type(st.Builds) == "table" and st.Builds or {}
  for _, store in pairs(st.Builds) do
    if type(store) == "table" and type(store.Items) == "table" and store.Items[buildID] then
      return store.Items[buildID]
    end
  end
  return nil
end

function Config.CreateBuild(classFile, name, treeID)
  local store = Config.EnsureClassBuilds(classFile)
  if not store then return nil end
  local defaults = XIVWeights.Builtin and XIVWeights.Builtin.Defaults
  treeID = tonumber(treeID)
  if not treeID then
    local first = defaults and defaults.DefaultBuildForClass(classFile)
    treeID = first and first.id
  end
  if not (defaults and treeID and defaults.ByID[treeID]) then return nil end
  store._seq = (store._seq or 0) + 1
  local id = "build:" .. tostring(treeID) .. ":" .. tostring(store._seq)
  local def = defaults.BuildForID and defaults.BuildForID(treeID)
  local build = {
    id = id,
    name = tostring(name or (def and def.name) or "Build"),
    treeID = treeID,
    scaleID = nil,
    weapon = normalizeWeapon(def and def.weapon, DEFAULT_WEAPON),
  }
  store.Items[id] = build
  return build
end

function Config.RenameBuild(classFile, buildID, name)
  local build = Config.GetBuild(classFile, buildID)
  if not build then return false end
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return false end
  build.name = name
  return true
end

function Config.DeleteBuild(classFile, buildID)
  local store = Config.EnsureClassBuilds(classFile)
  if not (store and store.Items[buildID]) then return false end
  store.Items[buildID] = nil
  local st = settings()
  st.CharacterBuilds = type(st.CharacterBuilds) == "table" and st.CharacterBuilds or {}
  for key, id in pairs(st.CharacterBuilds) do
    if id == buildID then st.CharacterBuilds[key] = nil end
  end
  return true
end

function Config.SetBuildTree(classFile, buildID, treeID)
  local build = Config.GetBuild(classFile, buildID)
  local defaults = XIVWeights.Builtin and XIVWeights.Builtin.Defaults
  treeID = tonumber(treeID)
  if not (build and treeID and defaults and defaults.ByID[treeID]) then return false end
  build.treeID = treeID
  return true
end

function Config.SetBuildScale(classFile, buildID, scaleID)
  local build = Config.GetBuild(classFile, buildID)
  if not build then return false end
  build.scaleID = scaleID
  return true
end

function Config.SetBuildWeaponPref(classFile, buildID, field, value)
  local build = Config.GetBuild(classFile, buildID)
  if not build then return false end
  build.weapon = type(build.weapon) == "table" and build.weapon or {}
  build.weapon[field] = value
  local UI = XIVEquip.UI
  if UI and type(UI.ClearPreviewCache) == "function" then UI.ClearPreviewCache() end
  return true
end

-- The active build record for the character, defaulting to the class's first
-- tree.
function Config.ActiveBuild(runtime)
  local classFile = classFileFor(runtime)
  if not classFile then return nil end
  local store = Config.EnsureClassBuilds(classFile)
  if not store then return nil end
  local st = settings()
  st.CharacterBuilds = type(st.CharacterBuilds) == "table" and st.CharacterBuilds or {}
  local key = characterKeyFor(runtime)
  local stored = key and st.CharacterBuilds[key]
  -- Migrate the earlier numeric (talent-tree id) value to a build id.
  if type(stored) == "number" then
    local id = "tree:" .. tostring(stored)
    if store.Items[id] then
      stored = id
      if key then st.CharacterBuilds[key] = id end
    end
  end
  if type(stored) == "string" and store.Items[stored] then return store.Items[stored] end
  local defaults = XIVWeights.Builtin and XIVWeights.Builtin.Defaults
  local firstTree = defaults and defaults.DefaultBuildForClass(classFile)
  local build = firstTree and store.Items["tree:" .. tostring(firstTree.id)] or next(store.Items)
  if build and key then st.CharacterBuilds[key] = build.id end
  return build
end

-- Talent-tree id of the active build (used for scale + profile resolution).
function Config.ActiveBuildID(runtime)
  local build = Config.ActiveBuild(runtime)
  return build and tonumber(build.treeID) or nil
end

function Config.SetActiveBuildID(buildID, runtime)
  local build = Config.FindBuild(buildID)
  if not build then return false end
  local st = settings()
  st.CharacterBuilds = type(st.CharacterBuilds) == "table" and st.CharacterBuilds or {}
  local key = characterKeyFor(runtime)
  if not key then return false end
  st.CharacterBuilds[key] = build.id
  local UI = XIVEquip.UI
  if UI and type(UI.ClearPreviewCache) == "function" then UI.ClearPreviewCache() end
  return true
end

-- Weapon preferences for the character's active build.
function Config.ActiveWeaponPrefs(runtime)
  local build = Config.ActiveBuild(runtime)
  if not build then return normalizeWeapon(nil, nil) end
  return normalizeWeapon(build.weapon, treeWeapon(build.treeID))
end

local function profilesConfig()
  return XIVEquip.Profiles and XIVEquip.Profiles.Config
end

local function integrationsRegistry()
  return XIVEquip.Integrations and XIVEquip.Integrations.Registry
end

local function invalidatePreview()
  local UI = XIVEquip.UI
  if UI and type(UI.ClearPreviewCache) == "function" then UI.ClearPreviewCache() end
end

local function weightsSettings()
  local st = settings()
  st.XIVWeights = type(st.XIVWeights) == "table" and st.XIVWeights or {}
  st.XIVWeights.Scales = type(st.XIVWeights.Scales) == "table" and st.XIVWeights.Scales or {}
  st.XIVWeights.Specs = type(st.XIVWeights.Specs) == "table" and st.XIVWeights.Specs or {}
  st.XIVWeights.SelectedScales = type(st.XIVWeights.SelectedScales) == "table" and st.XIVWeights.SelectedScales or {}
  st.XIVWeights.Integrations = type(st.XIVWeights.Integrations) == "table" and st.XIVWeights.Integrations or {}
  st.XIVWeights.Integrations.Pawn = type(st.XIVWeights.Integrations.Pawn) == "table" and st.XIVWeights.Integrations.Pawn or {}
  return st.XIVWeights
end

-- The last scale the user had selected in the Scales editor for a build, so it
-- survives logout/reload.
function Config.GetSelectedScaleID(buildID)
  local xw = weightsSettings()
  return xw.SelectedScales[tonumber(buildID)]
end

function Config.SetSelectedScaleID(buildID, scaleID)
  local key = tonumber(buildID)
  if not key then return end
  local xw = weightsSettings()
  xw.SelectedScales[key] = scaleID
end

local function generatedID(specID)
  return "spec:" .. tostring(specID)
end

local function normalizeProvider(provider)
  local key = string.lower(tostring(provider or "default"))
  if key == "xivequip" or key == "default" or key == "builtin" then return "default" end
  if key == "manual" then return "manual" end
  if key == "pawn" then return "pawn" end
  return "default"
end

local function normalizeScale(scale)
  scale = copy(scale)
  scale.weights = scale.weights or {}
  scale.meta = scale.meta or {}
  return XIVWeights.NewScale(scale)
end

local function builtinForSpec(specID)
  return XIVWeights.Builtin and XIVWeights.Builtin.Defaults and XIVWeights.Builtin.Defaults.Get(tonumber(specID))
end

function Config.SpecName(specID)
  local default = builtinForSpec(specID)
  return default and default.meta and default.meta.specName or default and default.name or nil
end

local function scaleName(scale, fallback)
  if not scale then return fallback end
  return scale.name or (scale.meta and scale.meta.specName) or fallback
end

function Config.ScaleDisplayName(scaleOrID, fallback)
  if type(scaleOrID) == "table" then return scaleName(scaleOrID, fallback) end
  if type(scaleOrID) == "string" then
    local scale = Config.Repository():Get(scaleOrID)
    return scaleName(scale, fallback or scaleOrID)
  end
  return fallback
end

function Config.ResolvedScaleSourceLabel(scale)
  if scale and scale.resolution then
    local resolution = scale.resolution
    local label = tostring(resolution.sourceLabel or "Default")
    local scaleLabel = tostring(resolution.scaleLabel or scaleName(scale, "current spec"))
    if resolution.fallback then label = label .. " (Fallback)" end
    return label .. ": " .. scaleLabel
  end
  local source = scale and scale.source or {}
  local specName = scaleName(scale, source.specID and Config.SpecName(source.specID) or nil)
  if source.kind == "pawn" then return "Pawn: " .. tostring(scaleName(scale, source.key or "selected scale")) end
  if source.kind == "xivequip-default" then return "Built-in default: " .. tostring(specName or "current spec") end
  if source.kind == "xivequip-default-copy" then return "Custom spec scale: " .. tostring(specName or "current spec") end
  if source.kind == "manual" then return "Manual scale: " .. tostring(scaleName(scale, scale and scale.id or "selected scale")) end
  if source.kind == "empty" then return "No weights" end
  return "XIVWeights"
end

function Config.ResolvedScaleDisplayLabel(scale)
  local resolution = scale and scale.resolution or {}
  local sourceLabel = tostring(resolution.sourceLabel or "Default")
  local scaleLabel = tostring(resolution.scaleLabel or scaleName(scale, "current specialization"))
  if sourceLabel == "Custom" and resolution.defaultCopy == true then
    scaleLabel = "Default (" .. scaleLabel .. ")"
  end
  return sourceLabel .. " | " .. scaleLabel
end

function Config.SelectionDisplay(specID, selection, pawnEntries)
  selection = selection or Config.GetSpecSelection(specID)
  local provider = normalizeProvider(selection and selection.provider)
  local specName = Config.SpecName(specID) or ("Spec " .. tostring(specID or "unknown"))

  if provider == "default" then
    local default = builtinForSpec(specID)
    return "Built-in default", scaleName(default, specName)
  end

  if provider == "pawn" then
    local selected = selection and selection.scale
    for _, entry in ipairs(pawnEntries or {}) do
      if entry and (entry.key == selected or entry.name == selected) then
        return "Pawn", tostring(entry.name or entry.key)
      end
    end
    return "Pawn", tostring(selected or "selected scale")
  end

  local scaleID = selection and selection.scale or generatedID(specID)
  return "Manual scale", Config.ScaleDisplayName(scaleID, specName)
end

function Config.GeneratedScaleID(specID)
  return generatedID(specID)
end

function Config.CreateSpecScale(specID)
  local default = XIVWeights.Builtin and XIVWeights.Builtin.Defaults and XIVWeights.Builtin.Defaults.Get(specID)
  if not default then return nil, "missing-default" end
  local scale = normalizeScale(default)
  scale.id = generatedID(specID)
  scale.name = (scale.meta and scale.meta.specName) or scale.name or ("Spec " .. tostring(specID))
  scale.source = {
    kind = "xivequip-default-copy",
    specID = tonumber(specID),
    defaultID = default.id,
    defaultVersion = default.meta and default.meta.defaultVersion,
  }
  scale.meta = scale.meta or {}
  scale.meta.specID = tonumber(specID)
  scale.meta.tiedToSpecID = tonumber(specID)
  scale.meta.generatedFromDefaultID = default.id
  scale.meta.generatedFromDefaultVersion = default.meta and default.meta.defaultVersion
  scale.meta.userEditable = true
  return scale
end

function Config.EnsureSpecScale(specID)
  local xw = weightsSettings()
  local id = generatedID(specID)
  if type(xw.Scales[id]) == "table" then return normalizeScale(xw.Scales[id]) end
  local scale, reason = Config.CreateSpecScale(specID)
  if not scale then return nil, reason end
  xw.Scales[id] = scale
  return scale
end

function Config.EnsureClassSpecScales(classFile)
  local defaults = XIVWeights.Builtin and XIVWeights.Builtin.Defaults
  local specs = defaults and defaults.SpecsForClass(classFile) or {}
  local out = {}
  for _, spec in ipairs(specs) do
    local scale = Config.EnsureSpecScale(spec.id)
    if scale then out[#out + 1] = scale end
  end
  return out
end

function Config.ResetSpecScale(specID)
  local xw = weightsSettings()
  local scale, reason = Config.CreateSpecScale(specID)
  if not scale then return nil, reason end
  xw.Scales[scale.id] = scale
  xw.Specs[tonumber(specID)] = { provider = "manual", scale = scale.id }
  invalidatePreview()
  return scale
end

function Config.Repository()
  return XIVWeights.Repository.New(weightsSettings().Scales)
end

function Config.GetSpecSelection(specID)
  local xw = weightsSettings()
  local key = tonumber(specID)
  local sel = type(xw.Specs[key]) == "table" and xw.Specs[key] or nil
  if not sel then
    sel = { provider = "default", scale = nil }
    xw.Specs[key] = sel
  end
  sel.provider = normalizeProvider(sel.provider)
  if sel.provider == "manual" and not sel.scale then sel.scale = generatedID(key) end
  return sel
end

function Config.SetSpecSelection(specID, provider, scaleID)
  local xw = weightsSettings()
  local key = tonumber(specID)
  xw.Specs[key] = {
    provider = normalizeProvider(provider),
    scale = scaleID,
  }
  invalidatePreview()
end

function Config.GetScaleSpecID(scale)
  if type(scale) ~= "table" then return nil end
  local meta = type(scale.meta) == "table" and scale.meta or {}
  local source = type(scale.source) == "table" and scale.source or {}
  return tonumber(meta.specID or meta.tiedToSpecID or source.specID)
end

local function normalizeProfileIntegration(provider)
  local value = tostring(provider or "pawn")
  if value == "" then return "pawn" end
  return value
end

function Config.GetProfileSelection(specID, runtime)
  local Profiles = profilesConfig()
  if not Profiles then return nil, nil end

  local profile, context = Profiles.GetForSpec(specID, runtime)
  if not profile then return nil, context end

  if profile.automatic ~= false then
    return {
      provider = "automatic",
      scale = nil,
      mode = "automatic",
      profile = profile,
    }, context
  end

  local manual = type(profile.manual) == "table" and profile.manual or {}
  local mode = string.lower(tostring(manual.mode or "default"))
  if mode == "custom" then
    local overrides = type(manual.customOverrides) == "table" and manual.customOverrides or {}
    local selected = overrides[tonumber(specID)]
    if selected and not Config.IsCustomScale(Config.Repository():Get(selected)) then selected = nil end
    return {
      provider = selected and "manual" or "default",
      scale = selected,
      mode = "custom",
      profile = profile,
    }, context
  end

  if mode == "integration" then
    local integration = type(manual.integration) == "table" and manual.integration or {}
    local overrides = type(integration.overrides) == "table" and integration.overrides or {}
    return {
      provider = normalizeProfileIntegration(integration.provider or "pawn"),
      scale = overrides[tonumber(specID)],
      mode = "integration",
      profile = profile,
    }, context
  end

  return {
    provider = "default",
    scale = nil,
    mode = "default",
    profile = profile,
  }, context
end

function Config.ListIntegrations()
  local registry = integrationsRegistry()
  return registry and registry:List() or {}
end

function Config.SaveScale(scale)
  assert(scale and scale.id, "XIVWeights.Config.SaveScale requires a scale id")
  local sourceKind = scale.source and scale.source.kind
  if sourceKind == "manual" or sourceKind == "xivequip-default-copy" then
    local specID = Config.GetScaleSpecID(scale)
    if not specID then return nil, "scale-spec-required" end
    scale.meta = scale.meta or {}
    scale.meta.specID = specID
  end
  local repo = Config.Repository()
  local saved, reason = repo:Save(normalizeScale(scale))
  if saved then invalidatePreview() end
  return saved, reason
end

function Config.DeleteScale(id)
  local deleted = Config.Repository():Delete(id)
  if deleted and XIVEquip.Profiles and XIVEquip.Profiles.Config
      and XIVEquip.Profiles.Config.ClearCustomScaleReferences then
    XIVEquip.Profiles.Config.ClearCustomScaleReferences(id)
  end
  if deleted then invalidatePreview() end
  return deleted
end

function Config.CreateManualScale(id, name, weights, specID)
  specID = tonumber(specID)
  if not specID then return nil, "spec-required" end
  local default = builtinForSpec(specID)
  if not default then return nil, "unknown-spec" end
  weights = weights or copy(default.weights)
  local scale = XIVWeights.NewScale({
    id = id,
    name = name,
    source = { kind = "manual" },
    weights = weights,
    meta = {
      userEditable = true,
      specID = specID,
      classFile = default and default.meta and default.meta.classFile or nil,
      specName = default and default.meta and default.meta.specName or nil,
      -- Start from the build's recommended weapon loadout so a new scale
      -- carries sensible weapon preferences.
      weapon = default and default.meta and default.meta.weapon or nil,
    },
  })
  local ok, err = Config.ValidateAuthoredWeights(scale)
  if not ok then return nil, err end
  return Config.SaveScale(scale)
end

function Config.DuplicateScale(sourceID, newID, newName)
  local source = Config.Repository():Get(sourceID)
  if not source then return nil, "Source scale not found." end
  local specID = Config.GetScaleSpecID(source)
  if not specID then return nil, "Source scale has no specialization owner." end
  local copyScale = copy(source)
  copyScale.id = newID
  copyScale.name = newName
  copyScale.source = { kind = "manual", duplicatedFrom = sourceID }
  copyScale.meta = copyScale.meta or {}
  copyScale.meta.userEditable = true
  copyScale.meta.duplicatedFrom = sourceID
  copyScale.meta.specID = specID
  return Config.SaveScale(copyScale)
end

function Config.NewManualScaleSeed(specID)
  local default = builtinForSpec(specID)
  if default and default.weights then return copy(default.weights) end
  local defaults = XIVWeights.Builtin and XIVWeights.Builtin.Defaults
  local primary = defaults and defaults.PrimaryForSpec and defaults.PrimaryForSpec(specID) or nil
  primary = primary or "strength"
  return { [primary] = 1.0 }
end

function Config.IsCustomScale(scale)
  if type(scale) ~= "table" then return false end
  local source = type(scale.source) == "table" and scale.source or {}
  return source.kind == "manual"
end

function Config.ListManualScales()
  local out = {}
  for _, scale in ipairs(Config.Repository():List()) do
    if Config.IsCustomScale(scale) then out[#out + 1] = scale end
  end
  return out
end

local function resolveSelection(specID, sel, runtime)
  local provider = sel.provider
  local scale

  if provider == "default" then
    local defaultProvider = XIVWeights.Providers.Default.New(Config)
    local ok, resolved = pcall(function() return defaultProvider:Resolve(nil, { specID = specID }) end)
    if ok and resolved then scale = resolved end
  elseif provider == "pawn" then
    local pawnProvider = runtime and runtime.PawnProvider and runtime.PawnProvider()
    if pawnProvider then
      local ok, resolved = pcall(function() return pawnProvider:Resolve(sel.scale, { specID = specID }) end)
      if ok and resolved then scale = resolved end
    end
  else
    local repo = Config.Repository()
    local manualProvider = XIVWeights.Providers.Manual.New(repo)
    local id = sel.scale
    id = id or generatedID(specID)
    local ok, resolved = pcall(function() return manualProvider:Resolve(id, { specID = specID }) end)
    if ok and resolved then scale = resolved end
  end

  return scale
end

function Config.ResolveResultForSpec(specID, runtime)
  local profileSelection, context = Config.GetProfileSelection(specID, runtime)
  local sel = profileSelection or Config.GetSpecSelection(specID)
  local configuredSelection = copy(sel)
  local fallback = false
  local fallbackReason
  local scale

  local integrationEntry
  if sel.provider == "automatic" then
    local registry = integrationsRegistry()
    if registry then
      local automaticEntry
      scale, automaticEntry = registry:ResolveAutomatic({ specID = specID, runtime = runtime })
      integrationEntry = type(automaticEntry) == "table" and automaticEntry or nil
    else
      local pawnProvider = runtime and runtime.PawnProvider and runtime.PawnProvider()
      if pawnProvider then
        local ok, resolved = pcall(function() return pawnProvider:Resolve(nil, { specID = specID }) end)
        if ok and resolved then scale = resolved end
      end
    end
    if not scale then
      -- Default is the final legitimate member of Automatic's hierarchy.
      -- Reaching it is normal and must not create a warning state.
      fallback = false
      fallbackReason = nil
      sel = { provider = "default", scale = nil, mode = "automatic", profile = sel.profile }
    end
  end

  if sel.mode == "integration" and not scale then
    local registry = integrationsRegistry()
    if registry then
      local requestedScale = sel.scale
      local resolved, reason, entry = registry:Resolve(sel.provider, {
        specID = specID,
        runtime = runtime,
      }, requestedScale)
      scale = resolved
      fallbackReason = reason
      integrationEntry = scale and entry or nil
      if not scale and requestedScale then
        local recommended, recommendedReason, recommendedEntry = registry:Resolve(sel.provider, {
          specID = specID,
          runtime = runtime,
        }, nil)
        if recommended then
          scale = recommended
          integrationEntry = recommendedEntry
          fallback = true
          sel = {
            provider = sel.provider,
            scale = nil,
            mode = "integration",
            profile = sel.profile,
          }
        else
          fallbackReason = recommendedReason or fallbackReason
        end
      end
    end
    if not scale then
      fallback = true
      fallbackReason = fallbackReason or "integration-unavailable"
      -- Keep the configured Integration in the profile. The effective
      -- selection becomes Default so an external key can never resolve
      -- accidentally through the manual-scale provider.
      sel = {
        provider = "default",
        scale = nil,
        mode = "integration",
        profile = sel.profile,
      }
    end
  end

  if not scale then scale = resolveSelection(specID, sel, runtime) end

  local sourceKind = "default"
  local sourceLabel = "Default"
  if not scale then
    scale = XIVWeights.Builtin and XIVWeights.Builtin.Defaults and XIVWeights.Builtin.Defaults.Get(specID)
    fallback = true
    fallbackReason = fallbackReason or "scale-unavailable"
  end
  if not scale then
    scale = XIVWeights.NewScale({ id = "fallback:empty", source = { kind = "empty" }, weights = {} })
    fallback = true
    fallbackReason = fallbackReason or "no-default-scale"
    sourceKind = "default"
    sourceLabel = "Default"
  end

  -- Resolve the source label after fallback selection so automatic default
  -- resolution is visible to callers instead of inheriting a nil label.
  if integrationEntry then
    sourceKind = "integration"
    sourceLabel = integrationEntry.label or integrationEntry.id
  elseif scale and scale.source and scale.source.kind == "pawn" then
    sourceKind = "integration"
    sourceLabel = "Pawn"
  elseif scale and scale.source and scale.source.kind == "manual" then
    sourceKind = "custom"
    sourceLabel = "Custom"
  elseif scale and scale.source and scale.source.kind == "xivequip-default-copy" then
    sourceKind = "custom"
    sourceLabel = "Custom"
  end

  local default = XIVWeights.Builtin and XIVWeights.Builtin.Defaults and XIVWeights.Builtin.Defaults.Get(specID)
  local effective = XIVWeights.Resolver.Resolve(scale, default)
  effective.resolution = {
    sourceKind = sourceKind,
    sourceLabel = sourceLabel,
    scaleLabel = scaleName(scale, Config.SpecName(specID) or "current spec"),
    automatic = sel.mode == "automatic",
    fallback = fallback,
    fallbackReason = fallbackReason,
    automaticResolution = sel.mode == "automatic" and sourceKind or nil,
    profileID = sel.profile and sel.profile.id or nil,
    configuredProvider = configuredSelection and configuredSelection.provider,
    configuredMode = configuredSelection and configuredSelection.mode,
    defaultCopy = scale and scale.source and scale.source.kind == "xivequip-default-copy",
  }
  return {
    scale = effective,
    profile = sel.profile,
    selection = sel,
    configuredSelection = configuredSelection,
    context = context,
    fallback = fallback,
    fallbackReason = fallbackReason,
  }
end

function Config.ResolveForSpec(specID, runtime)
  return Config.ResolveResultForSpec(specID, runtime).scale
end

function Config.ValidateAuthoredWeights(scale)
  if type(scale) ~= "table" then return false, "Scale is required." end
  if tostring(scale.name or ""):match("^%s*$") then return false, "Scale name is required." end
  local weights = scale.weights
  if type(weights) ~= "table" then return false, "Scale weights are required." end

  local hasOne = false
  for _, feature in ipairs(XIVWeights.FEATURES or {}) do
    local raw = weights[feature]
    if raw ~= nil then
      local value = tonumber(raw)
      if not value or value < 0 or value > 1 then
        return false, "Weight for " .. tostring(feature) .. " must be between 0 and 1."
      end
      if value == 1 then hasOne = true end
    end
  end
  if not hasOne then return false, "At least one top weight must be exactly 1.0." end
  return true
end
