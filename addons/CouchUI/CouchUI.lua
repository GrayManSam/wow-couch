-- CouchUI: switches the UI between two profiles automatically.
--   Couch = Easy Controller is loaded (the `couch` tool enables it when the LG TV is plugged in)
--   Desk  = Easy Controller not loaded (keyboard + mouse, Bartender4 bars)
-- Per profile: an Edit Mode layout named "Couch" / "Desk" (created once as a copy of your
-- current layout - arrange it in Edit Mode and it's remembered), chat font size, UI scale.
-- Everything is out-of-combat and pcall-guarded.
--
-- /couch              status + commands
-- /couch font 18      chat font for the current profile (12-24)
-- /couch scale 0.9    UI scale for the current profile (0.64-1.15, 'off' = game default)
-- /couch layout       re-apply this profile's Edit Mode layout
-- /couch arrange      move minimap/chat/damage meter/quests out of the way (undo: /couch arrange undo)
-- /couch macros       (re)create the utility macros
-- /couch help         controller map: every button, wheel, macro, music + voice shortcut
--                     (also: "Controls" on the Social wheel, LT + RB). Any button closes it.

local DEFAULTS = {
    Couch = { font = 18 },
    Desk  = { font = 14 },
}
local MACROS = {
    { "Mount",  134400, "#showtooltip\n/run if IsMounted() then Dismount() else C_MountJournal.SummonByID(0) end" },
    { "Hearth", 134400, "#showtooltip\n/use Hearthstone" },
    { "Reload", 134400, "/reload" },
    { "Leave",  134400, "/leavegroup" },
}

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0CouchUI|r " .. msg) end

local function isLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    return IsAddOnLoaded and IsAddOnLoaded(name)
end

local function profileName() return isLoaded("EasyController") and "Couch" or "Desk" end

local function prof()
    local p = profileName()
    CouchUIDB.profiles = CouchUIDB.profiles or {}
    CouchUIDB.profiles[p] = CouchUIDB.profiles[p] or CopyTable(DEFAULTS[p])
    return CouchUIDB.profiles[p], p
end

local function setChatFont(size)
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then pcall(FCF_SetChatWindowFontSize, nil, frame, size) end
    end
end

local function setScale(v)
    if v == "off" or v == nil then
        if v == "off" then SetCVar("useUiScale", "0") end
        return
    end
    SetCVar("useUiScale", "1")
    SetCVar("uiScale", tostring(v))
end

-- Edit Mode: find or create the layout named after the profile, then activate it.
local function applyLayout(name)
    if not (C_EditMode and C_EditMode.GetLayouts) then return end
    local ok, err = pcall(function()
        local info = C_EditMode.GetLayouts()
        local presets = 0
        if EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
            presets = #EditModePresetLayoutManager:GetCopyOfPresetLayouts()
        end
        local idx
        for i, layout in ipairs(info.layouts) do
            if layout.layoutName == name then idx = i end
        end
        if not idx then
            local src
            if info.activeLayout > presets then
                src = info.layouts[info.activeLayout - presets]
            elseif presets > 0 then
                src = EditModePresetLayoutManager:GetCopyOfPresetLayouts()[info.activeLayout]
            end
            if not src then return end
            local copy = CopyTable(src)
            copy.layoutName = name
            copy.layoutType = Enum.EditModeLayoutType.Account
            table.insert(info.layouts, copy)
            idx = #info.layouts
            C_EditMode.SaveLayouts(info)
            say("created Edit Mode layout '" .. name .. "' - arrange it once (Esc > Edit Mode).")
        end
        if info.activeLayout ~= presets + idx then
            C_EditMode.SetActiveLayout(presets + idx)
        end
    end)
    if not ok then say("couldn't switch Edit Mode layout: " .. tostring(err)) end
end

-- ---- Arrange: minimap, chat, damage meter, quest tracker out of the way -----------------
-- Written straight into this profile's Edit Mode layout (raw saved values), then ONE /reload
-- so Blizzard applies it cleanly (moving Edit Mode frames live from an addon causes taint).
-- /couch arrange      re-apply      /couch arrange undo   put the layout back as it was
local ARRANGE_VERSION = 1
local function chatSize(w, h)
    return { [0] = math.floor(w / 100), [1] = w % 100, [2] = math.floor(h / 100), [3] = h % 100 }
end
local function arrangeSpec(name)
    local S = Enum.EditModeSystem
    local couch = name == "Couch"
    local spec = {
        -- minimap: top-right corner, 80% (couch) / 70% (desk) size
        [S.Minimap] = { a = { "TOPRIGHT", "TOPRIGHT", -6, -6 },
            set = { [Enum.EditModeMinimapSetting.Size] = couch and 3 or 2 } },
        -- quest tracker: tucked under the smaller minimap, shortest height
        [S.ObjectiveTracker] = { a = { "TOPRIGHT", "TOPRIGHT", -14, couch and -205 or -185 },
            set = { [Enum.EditModeObjectiveTrackerSetting.Height] = couch and 10 or 5 } },
        -- chat: small, bottom-left corner (it fades when idle)
        [S.ChatFrame] = { a = { "BOTTOMLEFT", "BOTTOMLEFT", 10, couch and 120 or 100 },
            set = couch and chatSize(380, 140) or chatSize(340, 125) },
    }
    if S.DamageMeter and Enum.EditModeDamageMeterSetting then
        local D = Enum.EditModeDamageMeterSetting
        spec[S.DamageMeter] = { a = { "BOTTOMRIGHT", "BOTTOMRIGHT", -12, couch and 150 or 130 },
            set = {
                [D.Visibility] = Enum.DamageMeterVisibility.InCombat,  -- hidden out of combat
                [D.Style] = Enum.DamageMeterStyle.Thin,
                [D.Numbers] = Enum.DamageMeterNumbers.Compact,
                [D.FrameWidth] = (couch and 230 or 210) - 200,       -- raw = width - 200
                [D.FrameHeight] = (couch and 125 or 120) - 120,      -- raw = height - 120
                [D.BarHeight] = 18 - 15,                             -- raw = bar height - 15
                [D.Padding] = 0,
                [D.Transparency] = 80 - 50,                          -- 80% opaque
                [D.BackgroundTransparency] = 35,
                [D.TextSize] = couch and 4 or 3,                     -- 90% / 80%
            } }
    end
    return spec
end

local function setRaw(settings, setting, value)
    for _, s in ipairs(settings) do
        if s.setting == setting then s.value = value; return end
    end
    table.insert(settings, { setting = setting, value = value })
end

local function findLayout(info, name)
    for i, layout in ipairs(info.layouts) do
        if layout.layoutName == name then return layout, i end
    end
end

local function arrange(name, undo)
    if InCombatLockdown() then return say("leave combat first") end
    local ok, err = pcall(function()
        local info = C_EditMode.GetLayouts()
        local layout = findLayout(info, name)
        if not layout then return say("no '" .. name .. "' layout yet - /couch layout first") end
        CouchUIDB.arrangeBackup = CouchUIDB.arrangeBackup or {}
        if undo then
            if not CouchUIDB.arrangeBackup[name] then return say("nothing to undo") end
            layout.systems = CopyTable(CouchUIDB.arrangeBackup[name])
            CouchUIDB.arrangeBackup[name] = nil
            CouchUIDB.arranged = CouchUIDB.arranged or {}
            CouchUIDB.arranged[name] = -1          -- don't auto-arrange again
        else
            CouchUIDB.arrangeBackup[name] = CouchUIDB.arrangeBackup[name] or CopyTable(layout.systems)
            local spec, done = arrangeSpec(name), {}
            for _, sys in ipairs(layout.systems) do
                local sp = spec[sys.system]
                if sp and not done[sys.system] then
                    done[sys.system] = true
                    sys.anchorInfo = { point = sp.a[1], relativeTo = "UIParent",
                                       relativePoint = sp.a[2], offsetX = sp.a[3], offsetY = sp.a[4] }
                    sys.anchorInfo2 = nil
                    sys.isInDefaultPosition = false
                    for setting, value in pairs(sp.set) do setRaw(sys.settings, setting, value) end
                end
            end
            CouchUIDB.arranged = CouchUIDB.arranged or {}
            CouchUIDB.arranged[name] = ARRANGE_VERSION
        end
        C_EditMode.SaveLayouts(info)
        say((undo and "layout restored" or "minimap, chat, damage meter, quests rearranged") ..
            " - reloading UI in 2 s...")
        C_Timer.After(2, ReloadUI)
    end)
    if not ok then say("arrange failed: " .. tostring(err)) end
end

local function makeMacros()
    local made = 0
    for _, m in ipairs(MACROS) do
        local ok, exists = pcall(GetMacroIndexByName, m[1])
        if ok and exists == 0 and pcall(CreateMacro, m[1], m[2], m[3], false) then
            made = made + 1
        end
    end
    if made > 0 then say(made .. " macros added: Mount, Hearth, Reload, Leave.") end
end


-- ---- Desk (keyboard + mouse) binds -------------------------------------------------
-- Main bar 1-6 + Q E R F T G, Shift = bottom-left bar, Ctrl = bottom-right bar,
-- mouse side buttons + Z X C V = right bar 1. Strafe moves to A/D (hold right mouse to turn).
-- Applied once on the first Desk login; /couch binds re-applies, /couch binds undo restores.
local KEYS = { "1", "2", "3", "4", "5", "6", "Q", "E", "R", "F", "T", "G" }
local function deskBindTable()
    local t = {}
    for i, k in ipairs(KEYS) do
        t[k] = "ACTIONBUTTON" .. i
        t["SHIFT-" .. k] = "MULTIACTIONBAR1BUTTON" .. i
        t["CTRL-" .. k] = "MULTIACTIONBAR2BUTTON" .. i
    end
    local extra = { "BUTTON4", "BUTTON5", "SHIFT-BUTTON4", "SHIFT-BUTTON5", "Z", "X", "C", "V",
                    "SHIFT-Z", "SHIFT-X", "SHIFT-C", "SHIFT-V" }
    for i, k in ipairs(extra) do t[k] = "MULTIACTIONBAR3BUTTON" .. i end
    t["A"] = "STRAFELEFT"; t["D"] = "STRAFERIGHT"
    t["SHIFT-A"] = "TURNLEFT"; t["SHIFT-D"] = "TURNRIGHT"
    -- C (character pane) moves to U; P stays spellbook.
    t["`"] = "PETATTACK"; t["SHIFT-`"] = "PETFOLLOW"
    t["TAB"] = "TARGETNEARESTENEMY"; t["SHIFT-TAB"] = "TARGETPREVIOUSENEMY"
    t["U"] = "TOGGLECHARACTER0"; t["P"] = "TOGGLESPELLBOOK"
    return t
end

local function applyBinds()
    if InCombatLockdown() then return say("leave combat first") end
    local backup = {}
    for key, action in pairs(deskBindTable()) do
        backup[key] = GetBindingAction(key) or ""
        SetBinding(key, action)
    end
    CouchUIDB.bindBackup = CouchUIDB.bindBackup or backup
    SaveBindings(GetCurrentBindingSet())
    CouchUIDB.bindsApplied = true
    say("desk keybinds set: 1-6 QERFTG, Shift/Ctrl bars, mouse 4/5 + ZXCV, ` pet attack. /couch binds undo to restore.")
end

local function undoBinds()
    if InCombatLockdown() or not CouchUIDB.bindBackup then return say("nothing to undo") end
    for key, action in pairs(CouchUIDB.bindBackup) do
        if action == "" then SetBinding(key) else SetBinding(key, action) end
    end
    SaveBindings(GetCurrentBindingSet())
    CouchUIDB.bindBackup = nil
    say("previous keybinds restored")
end

-- ---- Hunter macros (per character, only for spells this character actually has) ----
local HUNTER = {
    { "PetAttack", nil, "/petattack [@mouseover,harm,nodead][]" },
    { "PetSummon", "Mend Pet", "#showtooltip\n/cast [@pet,dead] Revive Pet; [nopet] Call Pet; Mend Pet" },
    { "MisdTank", "Misdirection", "#showtooltip Misdirection\n/cast [@focus,help,nodead][@pet,exists,nodead] Misdirection" },
    { "TrapCursor", "Freezing Trap", "#showtooltip Freezing Trap\n/cast [@cursor] Freezing Trap" },
    { "MarkMO", "Hunter's Mark", "#showtooltip Hunter's Mark\n/cast [@mouseover,harm,nodead][] Hunter's Mark" },
    { "FeignDrop", "Feign Death", "#showtooltip Feign Death\n/stopattack\n/petfollow\n/cast Feign Death" },
    { "Interrupt", "Counter Shot", "#showtooltip\n/cast [@mouseover,harm,nodead][] Counter Shot" },
}

local function spellExists(name)
    if not name then return true end
    if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(name) ~= nil end
    return GetSpellInfo and GetSpellInfo(name) ~= nil
end

local function makeClassMacros()
    local _, class = UnitClass("player")
    if class ~= "HUNTER" then return end
    local made, skipped = 0, {}
    for _, m in ipairs(HUNTER) do
        if GetMacroIndexByName(m[1]) == 0 then
            if spellExists(m[2]) then
                if pcall(CreateMacro, m[1], 134400, m[3], true) then made = made + 1 end
            else
                table.insert(skipped, m[2])
            end
        end
    end
    if made > 0 then say(made .. " hunter macros added (character macros tab).") end
    if #skipped > 0 then say("not learned yet / not in Forever: " .. table.concat(skipped, ", ")) end
end

-- Forever's hunter has "Call Pet", not retail's "Call Pet 1": fix macros made before 2.3
local function fixPetMacro()
    local idx = GetMacroIndexByName("PetSummon")
    if idx and idx > 0 then
        local _, _, body = GetMacroInfo(idx)
        if body and body:find("Call Pet 1", 1, true) then
            pcall(EditMacro, idx, nil, nil, (body:gsub("Call Pet 1", "Call Pet")))
        end
    end
end

-- ---- Social wheel (couch): party / guild / inspect / trade on the controller ----------
-- An Easy Controller mini wheel named "Social" on LT + RB (that combo was set to
-- "nothing", so no button of yours moves). Hold LT + RB, aim with the right stick, let go.
-- Every action uses your CURRENT target only (pick the player with LB / assist first);
-- nothing is ever auto-targeted, so nothing goes to a stranger by accident. With no
-- player targeted the game just says so. Whisper: Easy Controller's keyboard, /w - your
-- target's name is offered first. /couch social = rebuild, /couch social off = remove.
local SOCIAL_MACROS = {
    { "SocInvite", "Spell_Holy_PrayerOfHealing", "/invite" },
    { "SocInspect", "INV_Misc_Spyglass_02", "/inspect" },
    { "SocGuild", "INV_Shirt_GuildTabard_01", "/ginvite" },
    { "SocTrade", "INV_Misc_Coin_02",
        "/run if UnitIsPlayer(\"target\") then InitiateTrade(\"target\") end" },
    { "SocFollow", "Ability_Tracking", "/follow" },
    { "SocFriend", "INV_ValentinesCard02", "/friend" },
    { "Leave", 134400, "/leavegroup" },
    { "Controls", "INV_Misc_Book_09", "/couch help" },
}
local SOCIAL_RETIRED = { "SocTarget" }   -- 2.3's auto-target macro: removed
local SOCIAL_BUTTON = { "RB", "LT" }   -- LT + RB
local SOCIAL_FALLBACK = { "L3", "RT" } -- if LT + RB is taken by something of yours

local function socialMacros()
    for _, name in ipairs(SOCIAL_RETIRED) do
        local idx = GetMacroIndexByName(name)
        if idx and idx > 0 then pcall(DeleteMacro, idx) end
    end
    for _, m in ipairs(SOCIAL_MACROS) do
        local idx = GetMacroIndexByName(m[1])
        if idx == 0 then
            if not pcall(CreateMacro, m[1], m[2], m[3], false) then
                pcall(CreateMacro, m[1], 134400, m[3], false)
            end
        elseif m[1] ~= "Leave" then
            -- ours: keep the body current (earlier versions auto-targeted)
            local _, _, body = GetMacroInfo(idx)
            if body ~= m[3] then pcall(EditMacro, idx, nil, nil, m[3]) end
        end
    end
end

local function ecSocial()
    local ck = _G.ControllerKeyboard
    if ck and ck.MyWheels and ck.Mapping and ck.db and ck.db.settings then
        for _, w in ipairs(ck.MyWheels:List()) do
            if w.couchSocial then return ck, w end
        end
        return ck
    end
end

local function bindSocial(ck, id)
    local M = ck.Mapping
    for _, b in ipairs({ SOCIAL_BUTTON, SOCIAL_FALLBACK }) do
        local input, layer = b[1], b[2]
        local inp = M.BY_ID and M.BY_ID[input]
        local cur = M:Get(input, layer)
        local rep = M:GetReplaced(input, layer)
        local action = "wheel:" .. id
        if cur == action or rep == action then return input, layer end
        -- only a button set to "nothing", or one with no function at all: never yours / the game's
        if inp and not cur then
            if rep == M.NOTHING and M:Replaceable(inp, layer) then
                M:SetReplaced(input, layer, action); return input, layer
            elseif rep == nil and M:State(inp, layer) == "free" then
                M:Set(input, layer, action); return input, layer
            end
        end
    end
end

local function setupSocial(verbose)
    if InCombatLockdown() then return say("leave combat first") end
    local ck, w = ecSocial()
    if not ck then return end
    socialMacros()
    if not w then
        local id = ck.MyWheels:Create()
        if not id then return say("Social wheel: Easy Controller has no free wheel (8 max)") end
        w = ck.MyWheels:Get(id)
        w.couchSocial = true
        CouchUIDB.socialBound = CouchUIDB.socialBound or {}
        CouchUIDB.socialBound[UnitGUID("player") or "?"] = nil
    end
    w.name = "Social"
    for i = 1, 8 do
        local m = SOCIAL_MACROS[i]
        w.slots[i] = m and ("macro:" .. m[1]) or nil
    end
    w.mini = true
    CouchUIDB.socialBound = CouchUIDB.socialBound or {}
    local key = UnitGUID("player") or "?"
    local input, layer
    if not CouchUIDB.socialBound[key] then
        input, layer = bindSocial(ck, w.id)
        CouchUIDB.socialBound[key] = true
    else
        input, layer = ck.MyWheels:Bound(w.id)
    end
    pcall(ck.MyWheels.UpdateBindingNames, ck.MyWheels)
    pcall(ck.ConsumableWheel.Fill, ck.ConsumableWheel)
    pcall(ck.Mapping.Apply, ck.Mapping)
    if ck.Paddles then pcall(ck.Paddles.Apply, ck.Paddles) end
    if verbose or input then
        say("Social wheel" .. (input and (" on " .. (layer ~= "" and layer .. " + " or "") .. input) or
            " ready (no free button - pick one in /ec map)") ..
            ": invite, inspect, guild invite, trade, follow, add friend, leave group - on your target (LB)." ..
            " Last slot = Controls (the button map).")
    end
end

local function removeSocial()
    local ck, w = ecSocial()
    if not (ck and w) then return say("no Social wheel") end
    if InCombatLockdown() then return say("leave combat first") end
    pcall(ck.MyWheels.Delete, ck.MyWheels, w.id)
    CouchUIDB.socialOff = true
    say("Social wheel removed (/couch social to bring it back)")
end

-- Easy Controller's keyboard: offer the targeted player's name first for /w
local function patchWhisperNames()
    local ck = _G.ControllerKeyboard
    if not (ck and type(ck.KnownNames) == "function") or ck.couchKnownNames then return end
    local orig = ck.KnownNames
    ck.KnownNames = function(self, ...)
        local list = orig(self, ...)
        local ok, name = pcall(function()
            if UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
                return GetUnitName("target", true)
            end
        end)
        if ok and type(name) == "string" and type(list) == "table" then
            for i = #list, 1, -1 do if list[i] == name then table.remove(list, i) end end
            table.insert(list, 1, name)
        end
        return list
    end
    ck.couchKnownNames = true
end

-- ---- Controller map (/couch help) ----------------------------------------------------
-- One screen with everything the controller does: the live Easy Controller mapping (read
-- from the addon, so it is always what the buttons really do), the wheels, what each macro
-- does, and the shortcuts handled outside the game (music = wow-music, Discord voice =
-- discord-voice, both on the Share button via the `pad` service).
local MACRO_HELP = {
    Mount = "Mount up, or dismount if mounted",
    Hearth = "Use your Hearthstone",
    Reload = "Reload the UI (fixes most addon hiccups)",
    Leave = "Leave your party / raid",
    Controls = "Show this controller map",
    SocInvite = "Invite your target to your group",
    SocInspect = "Inspect your target's gear",
    SocGuild = "Invite your target to your guild",
    SocTrade = "Open a trade with your target",
    SocFollow = "Follow your target",
    SocFriend = "Add your target as a friend",
    PetAttack = "Pet attacks your mouseover, else your target",
    PetSummon = "Pet dead: Revive Pet. No pet: Call Pet. Otherwise Mend Pet",
    MisdTank = "Misdirection on your focus, else on your pet",
    TrapCursor = "Freezing Trap where the cursor is",
    MarkMO = "Hunter's Mark on mouseover, else target",
    FeignDrop = "Stop attacking, pet follows, Feign Death",
    Interrupt = "Counter Shot on mouseover, else target",
}
local MACRO_ORDER = { "Mount", "Hearth", "Reload", "Leave", "PetAttack", "PetSummon", "MisdTank",
    "TrapCursor", "MarkMO", "FeignDrop", "Interrupt" }
local HEAD, KEY, DIM = "|cffffd100", "|cffffffff", "|cffb0b0b0"
local BUTTON_NAME = { UP = "D-pad up", DOWN = "D-pad down", LEFT = "D-pad left",
    RIGHT = "D-pad right", SELECT = "View", START = "Menu", L3 = "L-stick click",
    R3 = "R-stick click" }
local LAYER_HEAD = { [""] = "alone", LT = "hold LT +", RT = "hold RT +", LTRT = "hold LT + RT +" }

local function clip(text, n)
    text = tostring(text or "")
    if #text > n then return text:sub(1, n - 2) .. ".." end
    return text
end

-- What a button does in a layer, straight from Easy Controller (nil = nothing)
local function ecAction(M, input, layer)
    local ok, name = pcall(function()
        local action = M:GetReplaced(input.id, layer) or M:Get(input.id, layer)
        if action == M.NOTHING then return nil end
        if action then return M:ActionName(action) end
        if M.Inactive and M:Inactive(input, layer) then return nil end
        return (M:NativeInfo(input, layer))
    end)
    if ok and type(name) == "string" and name ~= "" then return name end
end

local function mapColumns()
    local ck = _G.ControllerKeyboard
    local M = ck and ck.Mapping
    if not (M and M.INPUTS and M.LAYERS) then return nil end
    local cols = { { HEAD .. "Button|r" } }
    for i, layer in ipairs(M.LAYERS) do cols[i + 1] = { HEAD .. (LAYER_HEAD[layer] or layer) .. "|r" } end
    for _, input in ipairs(M.INPUTS) do
        if not input.paddle and not input.layer then
            table.insert(cols[1], KEY .. (BUTTON_NAME[input.id] or input.id) .. "|r")
            for i, layer in ipairs(M.LAYERS) do
                local name = ecAction(M, input, layer)
                table.insert(cols[i + 1], name and clip(name, 24) or (DIM .. "-|r"))
            end
        end
    end
    return cols
end

local function wheelLines()
    local out = {}
    local ck = _G.ControllerKeyboard
    if not (ck and ck.MyWheels and ck.MyWheels.List) then return out end
    pcall(function()
        for _, w in ipairs(ck.MyWheels:List()) do
            local input, layer = ck.MyWheels:Bound(w.id)
            local where = input and ((layer and layer ~= "" and
                (layer == "LTRT" and "LT + RT + " or layer .. " + ") or "") ..
                (BUTTON_NAME[input] or input)) or "no button (/ec map)"
            table.insert(out, KEY .. where .. "|r  " .. tostring(w.name or "wheel"))
        end
    end)
    return out
end

local function helpText()
    local music = {
        HEAD .. "MUSIC  (Spotify, starts with WoW)|r",
        KEY .. "Hold Share + right stick right|r  next track",
        KEY .. "Hold Share + right stick left|r  previous track",
        KEY .. "Hold Share + right stick up / down|r  music volume",
        KEY .. "Tap Share|r  play / pause",
        DIM .. "Smart mode picks the songs: calm while exploring,|r",
        DIM .. "steady in dungeons, intense for bosses / PvP / long fights.|r",
        DIM .. "Skip = another song of the same kind.|r",
        " ",
        HEAD .. "DISCORD VOICE|r",
        KEY .. "Hold Share 1 s, let go|r  join / leave voice",
        KEY .. "Share x2|r  mute        " .. KEY .. "Share x3|r  deafen",
        " ",
        DIM .. "Share = the small middle button under View / Menu.|r",
    }
    local wheels = { HEAD .. "WHEELS  (hold, aim with right stick, let go)|r" }
    for _, l in ipairs(wheelLines()) do table.insert(wheels, l) end
    if #wheels == 1 then table.insert(wheels, DIM .. "none (desk mode)|r") end
    table.insert(wheels, " ")
    table.insert(wheels, HEAD .. "SOCIAL WHEEL  (acts on your target - pick with LB)|r")
    table.insert(wheels, "Invite, Inspect, Guild invite, Trade, Follow,")
    table.insert(wheels, "Add friend, Leave group, Controls (this page)")
    table.insert(wheels, " ")
    table.insert(wheels, HEAD .. "OUTSIDE THE GAME|r")
    table.insert(wheels, KEY .. "Hold Xbox button 1 s|r  controller as mouse on / off")
    table.insert(wheels, KEY .. "Tap View|r (on the desktop)  desktop button help")
    local macros = { HEAD .. "MACROS|r" }
    for _, name in ipairs(MACRO_ORDER) do
        local ok, idx = pcall(GetMacroIndexByName, name)
        if ok and idx and idx > 0 then
            table.insert(macros, KEY .. name .. "|r  " .. MACRO_HELP[name])
        end
    end
    table.insert(macros, " ")
    table.insert(macros, HEAD .. "COMMANDS|r")
    table.insert(macros, KEY .. "/couch help|r  this page     " .. KEY .. "/ec map|r  change buttons")
    table.insert(macros, KEY .. "/cw|r  what is on each spell wheel")
    table.insert(macros, KEY .. "/couch|r  font, scale, layout, lights")
    return music, wheels, macros
end

local helpFrame
local function buildHelp()
    local f = CreateFrame("Frame", "CouchUIHelp", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("CENTER")
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2 })
        f:SetBackdropColor(0.03, 0.03, 0.06, 0.94)
        f:SetBackdropBorderColor(0.41, 0.8, 0.94, 0.9)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.title:SetPoint("TOP", 0, -14)
    f.title:SetText("Couch controls")
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.hint:SetPoint("BOTTOM", 0, 10)
    f.hint:SetText("Any controller button or Esc closes this  -  open it again: Social wheel (LT + RB) > Controls")
    f.cols = {}
    for i = 1, 8 do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP"); fs:SetSpacing(3)
        f.cols[i] = fs
    end
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function(self) self:Hide() end)
    pcall(function()
        f:EnableGamePadButton(true)
        f:SetScript("OnGamePadButtonDown", function(self) self:Hide() end)
    end)
    table.insert(UISpecialFrames, "CouchUIHelp")          -- Esc / B closes
    f:RegisterEvent("PLAYER_REGEN_DISABLED")              -- never in the way in a fight
    f:SetScript("OnEvent", function(self) self:Hide() end)
    f:Hide()
    return f
end

local function showHelp()
    if InCombatLockdown() then return say("controller map: not during combat") end
    helpFrame = helpFrame or buildHelp()
    local f = helpFrame
    if f:IsShown() then return f:Hide() end
    local PAD, GAP = 22, 26
    local x, top = PAD, -52
    local gridH, width = 0, 0
    local cols = mapColumns()
    for i = 1, 5 do
        local fs = f.cols[i]
        fs:ClearAllPoints()
        if cols and cols[i] then
            fs:SetText(table.concat(cols[i], "\n"))
            fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, top)
            x = x + fs:GetStringWidth() + GAP
            gridH = math.max(gridH, fs:GetStringHeight())
            fs:Show()
        else
            fs:Hide()
        end
    end
    width = x
    local a, b, c = helpText()
    local y = top - (gridH > 0 and gridH + 24 or 0)
    x = PAD
    local lowH = 0
    for i, lines in ipairs({ a, b, c }) do
        local fs = f.cols[5 + i]
        fs:ClearAllPoints()
        fs:SetText(table.concat(lines, "\n"))
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        x = x + fs:GetStringWidth() + GAP + 8
        lowH = math.max(lowH, fs:GetStringHeight())
    end
    width = math.max(width, x)
    local height = -y + lowH + 44
    f:SetSize(width + PAD - GAP, height)
    local sw, sh = UIParent:GetWidth() - 40, UIParent:GetHeight() - 40
    f:SetScale(math.min(1.25, sw / f:GetWidth(), sh / height))
    f:Show()
end

-- Macro buttons on the action bars: say in the tooltip what the macro does
local function hookMacroTips()
    if not (GameTooltip and hooksecurefunc) then return end
    pcall(hooksecurefunc, GameTooltip, "SetAction", function(tip, slot)
        pcall(function()
            local kind = GetActionInfo(slot)
            if kind ~= "macro" then return end
            local text = MACRO_HELP[GetActionText(slot) or ""]
            if text then
                tip:AddLine(text, 0.41, 0.8, 0.94, true)
                tip:Show()
            end
        end)
    end)
end

local function applyAll(quiet)
    if InCombatLockdown() then return say("leave combat first") end
    local p, name = prof()
    applyLayout(name)
    setChatFont(p.font)
    setScale(p.scale)
    if not CouchUIDB.macrosMade then makeMacros(); CouchUIDB.macrosMade = true end
    local guid = UnitGUID("player")
    CouchUIDB.classMacros = CouchUIDB.classMacros or {}
    if guid and not CouchUIDB.classMacros[guid] then
        makeClassMacros(); CouchUIDB.classMacros[guid] = true
    end
    fixPetMacro()
    if name == "Desk" and not CouchUIDB.bindsApplied then applyBinds() end
    if name == "Couch" then
        patchWhisperNames()
        -- after Easy Controller and CouchWheels have set up this character's wheels
        if not CouchUIDB.socialOff then
            C_Timer.After(6, function() pcall(setupSocial, false) end)
        end
    end
    if not quiet then say(name .. " profile applied. /couch for options.") end
    CouchUIDB.arranged = CouchUIDB.arranged or {}
    local v = CouchUIDB.arranged[name]
    if v ~= -1 and (v or 0) < ARRANGE_VERSION then C_Timer.After(1, function() arrange(name) end) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    CouchUIDB = CouchUIDB or {}
    -- Combat log feeds the Govee lights (govee-wow), which only run on the TV (couch):
    -- logged only there, so desk play doesn't fill Logs/. /couch lights off to stop.
    if LoggingCombat then
        -- (2.5) logged in both profiles: the smart mode of wow-music reads it too (which
        -- songs fit what is happening). /couch lights off stops it.
        local want = CouchUIDB.combatLog ~= false
        if want ~= (LoggingCombat() and true or false) then pcall(LoggingCombat, want) end
    end
    hookMacroTips()
    local last = CouchUIDB.lastProfile
    C_Timer.After(3, function()
        applyAll(last == profileName())
        CouchUIDB.lastProfile = profileName()
    end)
end)

SLASH_COUCHUI1 = "/couch"
SlashCmdList.COUCHUI = function(input)
    local cmd, arg = strsplit(" ", strtrim(input or ""):lower(), 2)
    local p, name = prof()
    if cmd == "font" then
        local n = tonumber(arg)
        if not n or n < 12 or n > 24 then return say("font size 12-24") end
        p.font = n; setChatFont(n); say(name .. " chat font " .. n)
    elseif cmd == "scale" then
        if arg == "off" then p.scale = nil; setScale("off"); return say(name .. " UI scale: default") end
        local v = tonumber(arg)
        if not v or v < 0.64 or v > 1.15 then return say("scale 0.64-1.15 or 'off'") end
        p.scale = v; setScale(v); say(name .. " UI scale " .. v)
    elseif cmd == "layout" then applyLayout(name); say("layout '" .. name .. "' applied")
    elseif cmd == "arrange" then arrange(name, arg == "undo")
    elseif cmd == "macros" then makeMacros(); makeClassMacros()
    elseif cmd == "help" or cmd == "map" or cmd == "controls" then showHelp()
    elseif cmd == "lights" then
        CouchUIDB.combatLog = (arg ~= "off")
        pcall(LoggingCombat, CouchUIDB.combatLog)
        say("Combat log for light sync + smart music " .. (CouchUIDB.combatLog and "on" or "off"))
    elseif cmd == "binds" then if arg == "undo" then undoBinds() else applyBinds() end
    elseif cmd == "social" then
        if arg == "off" then removeSocial()
        elseif not ecSocial() then say("Social wheel needs Easy Controller (couch mode)")
        else
            CouchUIDB.socialOff = nil
            if arg == "rebind" then CouchUIDB.socialBound = {} end
            setupSocial(true)
        end
    else
        say("profile: " .. name .. " | font " .. p.font .. " | scale " .. tostring(p.scale or "default"))
        say("/couch help = controller map (buttons, wheels, macros, music + voice shortcuts)")
        say("/couch font 18 | /couch scale 0.9 | /couch scale off | /couch layout | /couch arrange [undo] | /couch macros | /couch binds [undo] | /couch social [off|rebind] | /couch lights on|off")
    end
end
