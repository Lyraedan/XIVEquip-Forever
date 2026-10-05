local addonName, XIVEquip = ...
XIVEquip                  = XIVEquip or {}
local Const               = {}
XIVEquip.Const            = Const
local API                 = XIVEquip.API

-- Fill `tbl[k] = value` for every key a token might arrive under (literal
-- name, plus the global value when it differs).
local function setTok(tbl, name, value)
  for _, key in ipairs(API.TokenKeys(name)) do tbl[key] = value end
end

Const.ARMOR_SLOTS         = { 1, 3, 5, 6, 7, 8, 9, 10 } -- just real armor
Const.JEWELRY_SLOTS       = { 2, 11, 12, 13, 14, 15 }   -- neck, rings, trinkets, back

Const.ARMOR               = {
  [1]  = true, -- Head
  [3]  = true, -- Shoulder
  [5]  = true, -- Chest
  [6]  = true, -- Waist
  [7]  = true, -- Legs
  [8]  = true, -- Feet
  [9]  = true, -- Wrist
  [10] = true, -- Hands
}

Const.JEWELRY             = {
  [2]  = true, -- Neck
  [11] = true, -- Ring 1
  [12] = true, -- Ring 2
  [13] = true, -- Trinket 1
  [14] = true, -- Trinket 2
  [15] = true, -- Back (yeah, it's not jewelry, but it fits here because it's not typed by armor class)
}

Const.LOWER_ILVL_ARMOR    = 20
Const.LOWER_ILVL_JEWELRY  = 80

Const.INV_BY_EQUIPLOC     = {}
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_HEAD", 1)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_NECK", 2)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_SHOULDER", 3)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_BODY", 4)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_CHEST", 5)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_ROBE", 5)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_WAIST", 6)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_LEGS", 7)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_FEET", 8)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_WRIST", 9)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_HAND", 10)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_FINGER", 11)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_TRINKET", 13)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_CLOAK", 15)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_HOLDABLE", 17)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_SHIELD", 17)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_RANGED", 18)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_RANGEDRIGHT", 18)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_THROWN", 18)
setTok(Const.INV_BY_EQUIPLOC, "INVTYPE_AMMO", 19)

Const.SLOT_EQUIPLOCS      = {
  [1] = {}, [2] = {}, [3] = {}, [5] = {}, [6] = {}, [7] = {}, [8] = {},
  [9] = {}, [10] = {}, [11] = {}, [12] = {}, [13] = {}, [14] = {}, [15] = {},
  [18] = {}, [19] = {},
}
setTok(Const.SLOT_EQUIPLOCS[1], "INVTYPE_HEAD", true)
setTok(Const.SLOT_EQUIPLOCS[2], "INVTYPE_NECK", true)
setTok(Const.SLOT_EQUIPLOCS[3], "INVTYPE_SHOULDER", true)
setTok(Const.SLOT_EQUIPLOCS[5], "INVTYPE_CHEST", true)
setTok(Const.SLOT_EQUIPLOCS[5], "INVTYPE_ROBE", true)
setTok(Const.SLOT_EQUIPLOCS[6], "INVTYPE_WAIST", true)
setTok(Const.SLOT_EQUIPLOCS[7], "INVTYPE_LEGS", true)
setTok(Const.SLOT_EQUIPLOCS[8], "INVTYPE_FEET", true)
setTok(Const.SLOT_EQUIPLOCS[9], "INVTYPE_WRIST", true)
setTok(Const.SLOT_EQUIPLOCS[10], "INVTYPE_HAND", true)
setTok(Const.SLOT_EQUIPLOCS[11], "INVTYPE_FINGER", true)
setTok(Const.SLOT_EQUIPLOCS[12], "INVTYPE_FINGER", true)
setTok(Const.SLOT_EQUIPLOCS[13], "INVTYPE_TRINKET", true)
setTok(Const.SLOT_EQUIPLOCS[14], "INVTYPE_TRINKET", true)
setTok(Const.SLOT_EQUIPLOCS[15], "INVTYPE_CLOAK", true)
setTok(Const.SLOT_EQUIPLOCS[18], "INVTYPE_RANGED", true)
setTok(Const.SLOT_EQUIPLOCS[18], "INVTYPE_RANGEDRIGHT", true)
setTok(Const.SLOT_EQUIPLOCS[18], "INVTYPE_THROWN", true)
-- Ammo (Classic). It is a stackable with a damage-per-second stat; scoring it
-- like a weapon's DPS lets the planner pick the best ammo in bags.
setTok(Const.SLOT_EQUIPLOCS[19], "INVTYPE_AMMO", true)

Const.ITEMCLASS_ARMOR     = 4

Const.SLOT_LABEL          = {
  [1] = "Head",
  [2] = "Neck",
  [3] = "Shoulder",
  [5] = "Chest",
  [6] = "Waist",
  [7] = "Legs",
  [8] = "Feet",
  [9] = "Wrist",
  [10] = "Hands",
  [11] = "Ring 1",
  [12] = "Ring 2",
  [13] = "Trinket 1",
  [14] = "Trinket 2",
  [15] = "Back",
  [16] = "Main Hand",
  [17] = "Off Hand",
  [18] = "Ranged",
  [19] = "Ammo",
}
