-- Core/Command.lua
local addon, XIVEquip = ...
XIVEquip              = XIVEquip or {}
XIVEquip.Commands     = XIVEquip.Commands or {}

local C               = XIVEquip.Commands
local L               = XIVEquip.L or {}
local PREFIX          = L.AddonPrefix or "XIVEquip: "
local API             = XIVEquip.API
-- Settings: Core addon plumbing: settings.
local function Settings() return XIVEquip.Settings end

-- utils
-- [XIVEquip-AUTO] trim: Helper for Core module.
local function trim(s) return (tostring(s or ""):match("^%s*(.-)%s*$")) end
-- split1: Core addon plumbing: split 1.
local function split1(s)
  local a, b = tostring(s or ""):match("^(%S+)%s*(.*)$")
  return a and string.lower(a) or "", (b or ""):match("^%s*(.-)%s*$")
end
-- onoff_to_bool: Core addon plumbing: onoff to bool.
local function onoff_to_bool(tok)
  tok = string.lower(tostring(tok or ""))
  if tok == "on" or tok == "1" or tok == "true" then return true end
  if tok == "off" or tok == "0" or tok == "false" then return false end
  return nil
end

local function printPlan(plan, pending)
  plan = plan or {}
  print(PREFIX .. string.format("Plan: %d item%s%s",
    #plan,
    (#plan == 1 and "" or "s"),
    pending and " (item data pending)" or ""))

  for i, pick in ipairs(plan) do
    local slotID = pick and pick.targetSlot
    local slotName = (XIVEquip.Gear_Core and XIVEquip.Gear_Core.SLOT_LABEL and XIVEquip.Gear_Core.SLOT_LABEL[slotID])
        or ("Slot " .. tostring(slotID or "?"))
    print(PREFIX .. string.format("%d. %s -> %s  ilvl=%s score=%s source=%s",
      i,
      tostring(slotName),
      tostring((pick and pick.link) or "(unknown item)"),
      tostring((pick and pick.ilvl) or "nil"),
      tostring((pick and pick.score) or "nil"),
      tostring((pick and pick.source) or "nil")))
  end
end

-- help registry
local helplines = {}
-- C.Help: Core addon plumbing: help.
function C.Help(line) helplines[#helplines + 1] = line end

C.Help(" /xive plan – print the current equip plan without equipping anything")
C.Help(" /xive equip – equip recommended gear")
C.Help(" /xive status – print selected settings and active scale")

-- print_help: Core addon plumbing: print help.
local function print_help()
  print(PREFIX .. "Commands:")
  print("  /xive                            – open settings")
  print("  /xive settings                   – open settings")
  print("  /xive help                       – print this command list")
  print("  /xivequip                        – equip recommended gear")
  print("  /xive equip                      – equip recommended gear")
  print("  /xive debug on|off|toggle        – toggle debug logging")
  print("  /xive debug slot <id|clear>      – filter debug to one slot (clear = all)")
  print("  /xive startup msg on|off         – toggle login/startup message")
  print("  /xive gear msg on|off            – toggle equip/change messages")
  print("  /xive gear preview on|off        – toggle hover preview on ERG button")
  print("  /xive auto spec on|off           – auto-equip on spec change")
  print("  /xive auto sets on|off           – auto-save set on equip")
  print("  /xive status                     – print settings and active scale")
  print("  /xive plan                       – print recommended equip plan")
  for _, line in ipairs(helplines) do print("  " .. line) end
end

local function openSettings()
  if XIVEquip.UI and XIVEquip.UI.SettingsWindow and XIVEquip.UI.SettingsWindow.Open then
    XIVEquip.UI.SettingsWindow.Open()
  else
    print(PREFIX .. "Settings window not available yet.")
  end
end

-- command framework (hardened)
-- [XIVEquip-AUTO] ROUTES table holds command -> handler mappings; leaf handlers are functions(rest).
local namespaces = {} -- first token -> function(rest)
local ROUTES     = {} -- nested tables -> function(rest)

-- C.RegisterNamespace: Core addon plumbing: register namespace.
function C.RegisterNamespace(ns, fn)
  namespaces[string.lower(tostring(ns or ""))] = fn
end

-- toPath: Core addon plumbing: to path.
local function toPath(cmd)
  if type(cmd) == "string" then return { cmd } end
  if type(cmd) == "table" then return cmd end
  error("RegisterRoot expects string or table path")
end

-- NEW: promote leaf functions to table nodes when needed
local function ensureTableSlot(t, key)
  local v = t[key]
  if type(v) == "function" then
    -- keep the existing handler as the default for this node
    v = { [""] = v }
    t[key] = v
  elseif type(v) ~= "table" then
    v = {}
    t[key] = v
  end
  return v
end

-- NEW: robust register that supports both leaf + subcommands
local function register(path, fn)
  local p = toPath(path)
  local node = ROUTES
  for i = 1, (#p - 1) do
    local key = string.lower(tostring(p[i] or ""))
    if key ~= "" then
      node = ensureTableSlot(node, key)
    end
  end
  local leaf = string.lower(tostring(p[#p] or ""))
  if leaf == "" then return end
  local existing = node[leaf]
  if type(existing) == "table" then
    -- already has subcommands; store this as the default handler
    existing[""] = fn
  else
    node[leaf] = fn
  end
end

-- C.RegisterRoot: Core addon plumbing: register root.
function C.RegisterRoot(cmdOrPath, fn) register(cmdOrPath, fn) end

-- NEW: dispatcher that honors default handlers on table nodes ([""])
local function dispatch(msg)
  local tokens = {}
  for w in string.gmatch(tostring(msg or ""), "%S+") do tokens[#tokens + 1] = w end
  if #tokens == 0 then
    openSettings(); return
  end

  -- 1) namespace
  local head = string.lower(tokens[1])
  if namespaces[head] then
    local rest = table.concat(tokens, " ", 2)
    return namespaces[head](rest)
  end

  -- 2) deepest route with default-handlers ("")
  local node, fn, ix = ROUTES, nil, 0
  local candidateFn, candidateIx = nil, 0
  for i = 1, #tokens do
    local k = string.lower(tokens[i])
    local nxt = node[k]
    if type(nxt) == "function" then
      fn, ix = nxt, i; break
    elseif type(nxt) == "table" then
      node = nxt
      if type(node[""]) == "function" then
        candidateFn, candidateIx = node[""], i
      end
    else
      break
    end
  end
  if not fn and candidateFn then
    fn, ix = candidateFn, candidateIx
  end
  if not fn then
    -- also allow a single-token default at top level
    local one = ROUTES[head]
    if type(one) == "function" then fn, ix = one, 1 end
  end
  if not fn then
    print(PREFIX .. "Unknown command. Try /xive help"); return
  end

  local rest = table.concat(tokens, " ", ix + 1)
  return fn(rest)
end

-- slash bindings
SLASH_XIVE1 = "/xive"
-- SlashCmdList["XIVE"]: Core addon plumbing: slash cmd list xive.
SlashCmdList["XIVE"] = function(msg) dispatch(trim(msg)) end

-- handlers

C.RegisterRoot("help", function(_)
  print_help()
end)

C.RegisterRoot("settings", function(_)
  openSettings()
end)

-- /xive status
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("status", function(_)
  local S = Settings()
  local st = (S and S.Get and S:Get()) or _G.XIVEquip_Settings or {}
  print(PREFIX .. "Status")
  print(PREFIX .. "Settings schema: " .. tostring(st.SchemaVersion or "unknown"))
  print(PREFIX .. "Auto spec: " .. (((S and S.GetAutomation and S:GetAutomation("SpecEquip")) or false) and "ON" or "OFF"))
  print(PREFIX .. "Auto sets: " .. (((S and S.GetAutomation and S:GetAutomation("SaveSpecSet")) or false) and "ON" or "OFF"))
end)

-- /xive compat
-- Reports which Forever/Retail APIs the client exposes. The report is also
-- mirrored into the chat log and into XIVEquip_ApiProbe (a SavedVariable), so
-- it can be copied out of the game.
C.RegisterRoot("compat", function(_)
  local function has(ns, fn)
    return type(ns) == "table" and type(ns[fn]) == "function"
  end
  local lines = {}
  local function line(label, value)
    lines[#lines + 1] = string.format("%-44s %s", label, tostring(value))
  end
  local function flag(label, ok) line(label, ok and "yes" or "NO") end

  local okBuild, _, _, _, interfaceVersion = pcall(GetBuildInfo)
  line("Interface version", okBuild and interfaceVersion or "unknown")

  flag("C_SpecializationInfo.GetSpecialization", has(C_SpecializationInfo, "GetSpecialization"))
  flag("C_SpecializationInfo.GetSpecializationInfo", has(C_SpecializationInfo, "GetSpecializationInfo"))
  flag("C_Item.GetItemInfo", has(C_Item, "GetItemInfo"))
  flag("C_Item.GetItemInfoInstant", has(C_Item, "GetItemInfoInstant"))
  flag("C_Item.GetItemStats", has(C_Item, "GetItemStats"))
  flag("C_Item.GetDetailedItemLevelInfo", has(C_Item, "GetDetailedItemLevelInfo"))
  flag("C_Item.GetItemUniqueness", has(C_Item, "GetItemUniqueness"))
  flag("C_Item.GetItemGUID", has(C_Item, "GetItemGUID"))
  flag("C_Item.IsBound", has(C_Item, "IsBound"))
  flag("C_Container.GetContainerItemInfo", has(C_Container, "GetContainerItemInfo"))
  flag("C_Container.GetContainerNumSlots", has(C_Container, "GetContainerNumSlots"))
  flag("C_Container.GetContainerItemLink", has(C_Container, "GetContainerItemLink"))
  flag("C_AddOns.GetAddOnMetadata", has(C_AddOns, "GetAddOnMetadata"))
  flag("C_AddOns.GetAddOnLocalTable", has(C_AddOns, "GetAddOnLocalTable"))
  flag("C_EquipmentSet.ModifyEquipmentSet", has(C_EquipmentSet, "ModifyEquipmentSet"))
  flag("C_EquipmentSet.ModifyEquipmentSetIcon", has(C_EquipmentSet, "ModifyEquipmentSetIcon"))
  flag("C_TooltipInfo.GetHyperlink", has(C_TooltipInfo, "GetHyperlink"))
  flag("C_Timer.After", has(C_Timer, "After"))
  flag("ItemLocation.CreateFromBagAndSlot",
    type(_G.ItemLocation) == "table" and type(_G.ItemLocation.CreateFromBagAndSlot) == "function")
  flag("ItemLocation.CreateFromEquipmentSlot",
    type(_G.ItemLocation) == "table" and type(_G.ItemLocation.CreateFromEquipmentSlot) == "function")
  flag("NUM_BAG_SLOTS global", _G.NUM_BAG_SLOTS ~= nil)
  flag("INVTYPE_HEAD global", _G.INVTYPE_HEAD ~= nil)
  flag("ITEM_MOD_STRENGTH global", _G.ITEM_MOD_STRENGTH ~= nil)
  flag("EMPTY_SOCKET_RED global", _G.EMPTY_SOCKET_RED ~= nil)
  flag("Enum.ItemBind", type(Enum) == "table" and type(Enum.ItemBind) == "table")
  flag("LoggingChat", type(LoggingChat) == "function")

  local P = XIVEquip.Persistence
  if P then
    flag("CVar API available", P.IsAvailable and P.IsAvailable())
    flag("C_CVar.RegisterCVar", type(C_CVar) == "table" and type(C_CVar.RegisterCVar) == "function")
    flag("loadstring available", type(loadstring) == "function" or type(load) == "function")
    line("SavedVariables restore result",
      P.GetLastRestoreResult and P.GetLastRestoreResult() or "unknown")
    line("CVar backup chunks", tostring(P.GetBackupChunkCount and P.GetBackupChunkCount() or 0))
    local info = P.GetBackupCVarInfo and P.GetBackupCVarInfo()
    if info then
      line("Backup stored (account/char)",
        tostring(info.accountStore == true) .. "/" .. tostring(info.charStore == true))
    end
  end

  -- Scoring sanity: if the spec or the stat tokens don't resolve, every score
  -- is zero and the planner silently recommends nothing.
  local runtime = XIVEquip.Planning and XIVEquip.Planning.Runtime
      and XIVEquip.Planning.Runtime.Live and XIVEquip.Planning.Runtime.Live()
  if runtime then
    local specIndex = runtime.GetSpecialization and runtime.GetSpecialization()
    local specID, specName
    if specIndex and runtime.GetSpecializationInfo then
      specID, specName = runtime.GetSpecializationInfo(specIndex)
    end
    line("Spec index / ID / name",
      tostring(specIndex) .. " / " .. tostring(specID) .. " / " .. tostring(specName))

    -- Decode the real class spec list so we can confirm the index->ID mapping.
    local _, classFile, classID = UnitClass("player")
    line("Class", tostring(classFile) .. " (" .. tostring(classID) .. ")")
    if type(GetSpecializationInfoForClassID) == "function" and classID then
      for i = 1, 5 do
        local okS, sid, sname = pcall(GetSpecializationInfoForClassID, classID, i)
        if okS and sid then line("SpecForClass[" .. i .. "]", tostring(sid) .. " / " .. tostring(sname)) end
      end
    end

    local okScale, scale = pcall(runtime.ResolveWeights)
    line("Resolved scale", okScale and tostring(scale and (scale.id or scale.name)) or "ERROR")
    if runtime.Close then pcall(runtime.Close) end
  end

  local sampleLink = GetInventoryItemLink
      and (GetInventoryItemLink("player", 5) or GetInventoryItemLink("player", 16) or GetInventoryItemLink("player", 7))
  if sampleLink and XIVEquip.API and XIVEquip.API.GetItemStats then
    local stats = XIVEquip.API.GetItemStats(sampleLink)
    local parts = {}
    for k, v in pairs(stats or {}) do
      parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
    end
    table.sort(parts)
    line("Sample item", tostring(sampleLink))
    line("Sample stats", table.concat(parts, ", "))
  end

  -- Dump stats for the first few items (equipped + bags) that actually have
  -- stats, so the weight vocabulary can be matched to Forever's itemization.
  do
    local dumped = 0
    local function dump(link)
      if dumped >= 5 or not link then return end
      local stats = XIVEquip.API.GetItemStats(link)
      if type(stats) ~= "table" or not next(stats) then return end
      local parts = {}
      for k, v in pairs(stats) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
      table.sort(parts)
      dumped = dumped + 1
      line("Stats " .. dumped, tostring(link) .. " => " .. table.concat(parts, ", "))
    end
    for _, slotID in ipairs({ 1, 3, 5, 7, 8, 9, 10, 16 }) do
      dump(GetInventoryItemLink and GetInventoryItemLink("player", slotID))
    end
    for bag = 0, API.NumBagSlots() do
      local n = API.GetContainerNumSlots(bag) or 0
      for slot = 1, n do
        dump(API.GetContainerItemLink and API.GetContainerItemLink(bag, slot))
      end
    end
  end

  -- Candidate collection and full plan diagnostics.
  do
    local testSlot = 5
    local link5 = GetInventoryItemLink and GetInventoryItemLink("player", testSlot)
    line("GetInventoryItemLink(5)", tostring(link5))
    local wrapped = XIVEquip.API.EquipmentSlotLocation(testSlot)
    line("EquipmentSlotLocation type", type(wrapped) .. (type(wrapped) == "table" and (" raw=" .. type(wrapped._raw)) or ""))
    line("linkFromLocation(equip5)", tostring(XIVEquip.Gear_Core.linkFromLocation(wrapped)))
    -- Inventory slot survey: which slots hold what, to locate ranged/ammo.
    for slotID = 1, 20 do
      local link = GetInventoryItemLink and GetInventoryItemLink("player", slotID)
      if link then
        local id, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
        line("Equipped slot " .. slotID, tostring(id) .. " equip=" .. tostring(equipLoc) .. " " .. tostring(link))
      end
    end
    if link5 then
      local okI, id, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, link5)
      line("GetItemInfoInstant(link5)", tostring(okI) .. ":" .. tostring(id) .. ":" .. tostring(equipLoc))
    end
  end

  local okCollect, collection = pcall(XIVEquip.Evaluation.CandidateCollector.Collect)
  if okCollect and type(collection) == "table" then
    line("Candidates collected", tostring(#(collection.candidates or {})))
    -- Bag scan diagnostics: what does the container API actually report?
    do
      local bagCounts, bagItems = {}, 0
      for bag = 0, API.NumBagSlots() do
        local n = API.GetContainerNumSlots(bag) or 0
        bagCounts[#bagCounts + 1] = tostring(bag) .. ":" .. tostring(n)
      end
      line("Bag slot counts", table.concat(bagCounts, ", "))
      for bag = 0, API.NumBagSlots() do
        local n = API.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
          local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
          local link = C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
          local hasItem = C_Container and C_Container.HasContainerItem and C_Container.HasContainerItem(bag, slot)
          if link or (type(info) == "table" and next(info)) or hasItem then
            bagItems = bagItems + 1
            if bagItems <= 8 then
              local keys = {}
              if type(info) == "table" then
                for k in pairs(info) do keys[#keys + 1] = tostring(k) end
                table.sort(keys)
              end
              local id, _, _, equipLoc = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(link or info)
              line("Bag " .. bag .. "/" .. slot,
                "has=" .. tostring(hasItem) .. " link=" .. tostring(link)
                .. " id=" .. tostring(id) .. " equip=" .. tostring(equipLoc)
                .. " keys={" .. table.concat(keys, ",") .. "}")
            end
          end
        end
      end
      line("Bag occupied items", tostring(bagItems))
      -- Specifically: equippable bag items and whether the collector's prefilter
      -- would admit them.
      local equippable = 0
      for bag = 0, API.NumBagSlots() do
        local n = API.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
          local link = C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
          if link then
            local id, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
            if equipLoc then
              equippable = equippable + 1
              if equippable <= 6 then
                line("Equippable bag " .. bag .. "/" .. slot,
                  "id=" .. tostring(id) .. " equip=" .. tostring(equipLoc))
              end
            end
          end
        end
      end
      line("Equippable bag items", tostring(equippable))
      -- Reproduce the collector's exact path for the first real bag equippable.
      do
        local shown = 0
        for bag = 0, API.NumBagSlots() do
          local n = API.GetContainerNumSlots(bag) or 0
          for slot = 1, n do
            local info = API.GetContainerItemInfo and API.GetContainerItemInfo(bag, slot)
            local itemID = type(info) == "table" and (tonumber(info.itemID) or tonumber(info.id))
            if itemID then
              local id, _, _, equipLoc = C_Item.GetItemInfoInstant(info.hyperlink or itemID)
              -- equippable = a real INVTYPE_*, not the NON_EQUIP sentinel
              if equipLoc and not tostring(equipLoc):find("NON_EQUIP") then
                local wrapper = API.BagSlotLocation(bag, slot)
                line("Collector path " .. bag .. "/" .. slot,
                  "id=" .. tostring(itemID) .. " equip=" .. tostring(equipLoc)
                  .. " lfl=" .. tostring(XIVEquip.Gear_Core.linkFromLocation(wrapper))
                  .. " bag=" .. tostring(wrapper.bagID) .. " slot=" .. tostring(wrapper.slotIndex))
                shown = shown + 1
                if shown >= 3 then break end
              end
            end
          end
          if shown >= 3 then break end
        end
      end
    end
    local equipped = 0
    for _ in pairs(collection.equippedBySlot or {}) do equipped = equipped + 1 end
    line("Equipped slots found", tostring(equipped))
    line("Pending item data", tostring(collection.pending))
    local reasons = {}
    for _, u in ipairs(collection.unresolved or {}) do
      reasons[tostring(u.reason)] = (reasons[tostring(u.reason)] or 0) + 1
    end
    local rl = {}
    for k, v in pairs(reasons) do rl[#rl + 1] = k .. "=" .. v end
    table.sort(rl)
    line("Unresolved reasons", table.concat(rl, ", "))
  else
    line("Candidate collection", "ERROR " .. tostring(collection))
  end

  local okPlan, planResult = pcall(XIVEquip.Planning.Coordinator.Plan, {})
  if okPlan and type(planResult) == "table" then
    line("Plan pending", tostring(planResult.pending))
    local filled = 0
    for _, c in pairs(planResult.finalSlots or {}) do if c then filled = filled + 1 end end
    line("Final filled slots", tostring(filled))
    local fs = (planResult.diagnostics and planResult.diagnostics.groupFrontierSizes) or {}
    local fl = {}
    for k, v in pairs(fs) do fl[#fl + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(fl)
    line("Frontier sizes", table.concat(fl, ", "))
    local weights = planResult.weights
    local wl = {}
    for k, v in pairs((weights and weights.weights) or {}) do
      wl[#wl + 1] = tostring(k) .. "=" .. string.format("%.3g", tonumber(v) or 0)
    end
    table.sort(wl)
    line("Resolved weights", table.concat(wl, ", "))
  else
    line("Plan pass", "ERROR " .. tostring(planResult))
  end

  local report = {
    capturedAt = (type(date) == "function") and date("%Y-%m-%d %H:%M:%S") or nil,
    interfaceVersion = okBuild and interfaceVersion or nil,
    lines = lines,
  }
  _G.XIVEquip_ApiProbe = report

  local logging = type(LoggingChat) == "function"
  if logging then pcall(LoggingChat, true) end
  print(PREFIX .. "Compatibility probe (" .. tostring(report.capturedAt or "?") .. ")")
  for _, entry in ipairs(lines) do print(PREFIX .. entry) end
  if logging then pcall(LoggingChat, false) end
  print(PREFIX .. "Report saved to XIVEquip_ApiProbe and the chat log (Logs/WoWChatLog.txt).")
end)

-- /xive persist save|check
-- Force a CVar-backup write, or report the backup state, without logging out.
C.RegisterRoot({ "persist", "save" }, function(_)
  local P = XIVEquip.Persistence
  if not (P and P.Save) then print(PREFIX .. "Persistence not available."); return end
  local ok, reason = P.Save()
  print(PREFIX .. string.format("Backup save: %s (%s), chunks=%d",
    tostring(ok), tostring(reason), (P.GetBackupChunkCount and P.GetBackupChunkCount()) or 0))
  local info = P.GetBackupCVarInfo and P.GetBackupCVarInfo()
  if info then
    print(PREFIX .. string.format("Backup CVar stored account=%s char=%s",
      tostring(info.accountStore), tostring(info.charStore)))
  end
end)

C.RegisterRoot({ "persist", "check" }, function(_)
  local P = XIVEquip.Persistence
  if not P then print(PREFIX .. "Persistence not available."); return end
  print(PREFIX .. string.format("Restore result: %s, chunks=%d",
    tostring(P.GetLastRestoreResult and P.GetLastRestoreResult()),
    (P.GetBackupChunkCount and P.GetBackupChunkCount()) or 0))
end)

-- /xive frames
-- Dumps named child frames of the character/paperdoll frames so UI anchors
-- (e.g. the equip button) can be placed precisely.
C.RegisterRoot("frames", function(_)
  local function dump(parent, depth)
    if not parent or depth > 3 then return end
    local name = parent.GetName and parent:GetName()
    local width, height = parent.GetWidth and parent:GetWidth(), parent.GetHeight and parent:GetHeight()
    local shown = parent.IsShown and parent:IsShown()
    if name then
      print(PREFIX .. string.format("%s%s (%dx%d) shown=%s",
        string.rep("  ", depth), tostring(name), tonumber(width) or 0,
        tonumber(height) or 0, tostring(shown)))
    end
    if parent.GetChildren then
      local kids = { parent:GetChildren() }
      for _, child in ipairs(kids) do dump(child, depth + 1) end
    end
  end
  for _, key in ipairs({ "CharacterFrame", "PaperDollFrame", "CharacterFramePortrait", "EquipmentManagerFrame" }) do
    local f = _G[key]
    if f then
      print(PREFIX .. "== " .. key .. " ==")
      dump(f, 0)
    else
      print(PREFIX .. key .. ": absent")
    end
  end
end)

-- /xive plan
-- Prints the current equip plan without attempting to equip anything.
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("plan", function(rest)
  if trim(rest) ~= "" then
    print(PREFIX .. "Usage: /xive plan")
    return
  end

  local Gear = XIVEquip.Gear
  if not (Gear and Gear.PlanBest) then
    print(PREFIX .. "Planner not available.")
    return
  end

  local _, pending, plan, result, planFailure = Gear:PlanBest()
  if planFailure then
    print(PREFIX .. "Planner failed; no plan available. Check the debug log for details.")
    return
  end

  printPlan(plan, pending)
end)

-- /xive perf
-- Performs a planning pass and prints compact timing/work counters.
C.RegisterRoot("perf", function(rest)
  if trim(rest) ~= "" then
    print(PREFIX .. "Usage: /xive perf")
    return
  end

  local Perf = XIVEquip.Diagnostics and XIVEquip.Diagnostics.Perf
  local Gear = XIVEquip.Gear
  if not (Perf and Perf.New and Gear and Gear.PlanBest) then
    print(PREFIX .. "Performance diagnostics not available.")
    return
  end

  local recorder = Perf.New(true)
  local _, pending, plan, result, planFailure = Gear:PlanBest({ planner = { perf = recorder } })
  if planFailure then
    print(PREFIX .. "Planner failed; no performance report available. Check the debug log for details.")
    return
  end

  print(PREFIX .. string.format("Perf: plan produced %d item%s%s.",
    #(plan or {}),
    #(plan or {}) == 1 and "" or "s",
    pending and " (item data pending)" or ""))
  if result and result.diagnostics and result.diagnostics.scoreSource then
    print(PREFIX .. "Score source: " .. tostring(result.diagnostics.scoreSource))
  end
  for _, line in ipairs(recorder:Lines()) do
    print(PREFIX .. line)
  end
end)

-- /xive equip
C.RegisterRoot("equip", function(rest)
  if trim(rest) ~= "" then
    print(PREFIX .. "Usage: /xive equip")
    return
  end

  if XIVEquip and XIVEquip.Gear and XIVEquip.Gear.EquipBest then
    XIVEquip.Gear:EquipBest()
  else
    print(PREFIX .. "Equip routine not available.")
  end
end)

-- /xive validate
-- Saves backup.xive, unequips supported gear slots, runs recommended equip, and reports missing slots.
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("validate", function(_)
  if XIVEquip and XIVEquip.Gear and XIVEquip.Gear.ValidateNakedEquip then
    XIVEquip.Gear:ValidateNakedEquip()
  else
    print(PREFIX .. "Validation routine not available.")
  end
end)

-- /xive smoke
-- Runs in-game regression checks, then starts validation if they pass.
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("smoke", function(_)
  if not (XIVEquip and XIVEquip.Tests and XIVEquip.Tests.Run) then
    print(PREFIX .. "Regression test routine not available.")
    return
  end
  if not (XIVEquip.Gear and XIVEquip.Gear.ValidateNakedEquip) then
    print(PREFIX .. "Validation routine not available.")
    return
  end

  local ok = XIVEquip.Tests:Run()
  if ok == false then
    print(PREFIX .. "Smoke aborted: regression tests failed.")
    return
  end

  XIVEquip.Gear:ValidateNakedEquip()
end)

-- /xive debug on|off|toggle
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("debug", function(rest)
  local S = Settings()
  if not (S and S.SetDebugEnabled and S.GetDebugEnabled) then
    print(PREFIX .. "Settings not available."); return
  end
  local sub = string.lower((rest or ""):match("^(%S*)") or "")
  if sub == "on" then
    S:SetDebugEnabled(true)
  elseif sub == "off" then
    S:SetDebugEnabled(false)
  else
    S:SetDebugEnabled(not S:GetDebugEnabled())
  end
  print(PREFIX .. "Debug: " .. (S:GetDebugEnabled() and "ON" or "OFF"))
end)

-- /xive debug slot <number|clear>
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot({ "debug", "slot" }, function(rest)
  local S = Settings(); if not (S and S.SetDebugSlot) then
    print(PREFIX .. "Settings not available."); return
  end
  local r = trim(rest)
  if r == "" or r == "clear" or r == "off" then
    S:SetDebugSlot(nil); print(PREFIX .. "Debug slot filter cleared."); return
  end
  local n = tonumber(r); if n then
    S:SetDebugSlot(n); print(PREFIX .. ("Debug slot set to %d."):format(n))
  else
    print(PREFIX .. "Usage: /xive debug slot <number|clear>")
  end
end)

-- /xive startup msg on|off
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("startup", function(rest)
  local S = Settings(); if not (S and S.SetMessage) then
    print(PREFIX .. "Settings not available."); return
  end
  local tok, rest2 = split1(rest); if tok ~= "msg" then
    print(PREFIX .. "Usage: /xive startup msg on|off"); return
  end
  local onoff = onoff_to_bool(select(1, split1(rest2))); if onoff == nil then
    print(PREFIX .. "Usage: /xive startup msg on|off"); return
  end
  S:SetMessage("Login", onoff); print(PREFIX .. "Startup message: " .. (onoff and "ON" or "OFF"))
end)

-- /xive gear msg on|off   and   /xive gear preview on|off
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("gear", function(rest)
  local S = Settings(); if not (S and S.SetMessage) then
    print(PREFIX .. "Settings not available."); return
  end
  local sub, rest2 = split1(rest); local onoff = onoff_to_bool(select(1, split1(rest2)))
  if sub == "msg" then
    if onoff == nil then
      print(PREFIX .. "Usage: /xive gear msg on|off"); return
    end
    S:SetMessage("Equip", onoff); print(PREFIX .. "Equip/change messages: " .. (onoff and "ON" or "OFF"))
  elseif sub == "preview" then
    if onoff == nil then
      print(PREFIX .. "Usage: /xive gear preview on|off"); return
    end
    S:SetMessage("Preview", onoff); print(PREFIX .. "Hover preview: " .. (onoff and "ON" or "OFF"))
  else
    print(PREFIX .. "Usage: /xive gear msg on|off  |  /xive gear preview on|off")
  end
end)

-- /xive auto spec|sets on|off
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("auto", function(rest)
  local S = Settings(); if not (S and S.SetAutomation) then
    print(PREFIX .. "Settings not available."); return
  end
  local what, rest2 = split1(rest); local onoff = onoff_to_bool(select(1, split1(rest2)))
  if (what ~= "spec" and what ~= "sets") or onoff == nil then
    print(PREFIX .. "Usage: /xive auto spec on|off  |  /xive auto sets on|off"); return
  end
  S:SetAutomation(what == "spec" and "SpecEquip" or "SaveSpecSet", onoff)
  print(PREFIX .. "Auto " .. what .. ": " .. (onoff and "ON" or "OFF"))
end)

-- /xivequip
SLASH_XIVEQUIP1 = "/xivequip"
-- SlashCmdList["XIVEQUIP"]: Core addon plumbing: slash cmd list xivequip.
SlashCmdList["XIVEQUIP"] = function()
  if XIVEquip and XIVEquip.Gear and XIVEquip.Gear.EquipBest then
    XIVEquip.Gear:EquipBest()
  else
    print(PREFIX .. "Equip routine not available.")
  end
end
