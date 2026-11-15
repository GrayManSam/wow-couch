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
-- /couch macros       (re)create the macros and put them on the bar buttons + wheels
-- /couch macros undo  bar buttons and wheels back to the plain spells
-- /couch help         controller map: every button, wheel, macro, music + voice shortcut
--                     (also: "Controls" on the Social wheel). Any button closes it.

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
-- (2.7) The set from Leaku's Forever hunter guide + the two the user sent (Hunter's Mark +
-- pet attack + Auto Shot, pet recall + Feign Death). { name, spell needed, body, options }:
--   swap  = spells this macro stands in for: wherever one of them sits on a bar button
--           (keyboard bars and the controller's LT / RT layers) or on a CouchWheels spell
--           wheel, the macro takes its place
--   wheel = no spell of its own: goes on the "Hunter" wheel
--   desk  = aims at the mouse cursor: only swapped in at the desk, never on the controller
--   old   = bodies earlier versions wrote (still ours: brought up to date)
-- In order of importance: the character macro list is short, the last ones may not fit.
--   button = no spell of its own and wanted in a fight: goes on the first empty controller
--            button of the LT, RT, LT + RT layers (once; move it freely in /ec map)
--   build  = the body depends on what is in the bags (potion, pet food): rewritten when
--            the bags change, out of combat
local MO = "[@mouseover,harm,nodead][] "
local bagItem   -- defined below: the item of a kind in the bags (or the last one seen)
local HUNTER = {
    -- From the combat log (62% of the damage dealt in melee, 15 "target too close"): one
    -- button for both ranges. Up close Raptor Strike lands, at range Arcane Shot + Auto Shot.
    { "Fight", "Raptor Strike",
        "#showtooltip\n/startattack\n/cast Raptor Strike\n/cast Arcane Shot\n/cast !Auto Shot",
        { button = true, old = { "#showtooltip\n/startattack\n/cast Raptor Strike\n/cast Arcane Shot\n/cast !Auto Shot\n/run UIErrorsFrame:Clear()" }, help = "One button for any range: Raptor Strike up close, Arcane + Auto Shot from afar" } },
    -- From the combat log (5 deaths, 1 potion): everything that heals, on one button
    { "Panic", nil, "",
        { button = true, quiet = true, help = "Emergency: Infusion of Wind + your healing potion",
          build = function()
              local lines = { "#showtooltip" }
              if C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo("Infusion of Wind") then
                  lines[#lines + 1] = "/cast Infusion of Wind"
              end
              local potion = bagItem("healthPotion")
              if potion then lines[#lines + 1] = "/use item:" .. potion end
              return #lines > 1 and table.concat(lines, "\n") or nil
          end } },
    { "PetAttack", nil, "/petattack " .. MO .. "\n/cast Dash\n/cast Dive\n/cast Charge",
        { icon = "Ability_Druid_FerociousBite", wheel = true, assist = true,
          old = { "/petattack [@mouseover,harm,nodead][]" },
          help = "Pet attacks your mouseover, else your target (with Dash / Dive / Charge)" } },
    { "PetRecall", "Call Pet", "/petpassive\n/cast Dash\n/cast Dive\n/petfollow",
        { icon = "Spell_Nature_Spiritwolf", wheel = true,
          help = "Pet stops and runs back to you (passive until the next PetAttack)" } },
    { "PetSummon", "Call Pet",
        "#showtooltip\n/cast [mod:alt] Revive Pet; [@pet,dead] Revive Pet; [nopet] Call Pet; Mend Pet",
        { wheel = true, swap = { "Mend Pet", "Call Pet" },
          old = { "#showtooltip\n/cast [@pet,dead] Revive Pet; [nopet] Call Pet; Mend Pet",
                  "#showtooltip\n/cast [@pet,dead] Revive Pet; [nopet] Call Pet 1; Mend Pet" },
          help = "Pet dead: Revive Pet. No pet: Call Pet. Otherwise Mend Pet" } },
    { "MarkMO", "Hunter's Mark",
        "#showtooltip Hunter's Mark\n/cast " .. MO .. "Hunter's Mark\n/petattack " .. MO .. "\n/cast !Auto Shot",
        { swap = { "Hunter's Mark" },
          old = { "#showtooltip Hunter's Mark\n/cast [@mouseover,harm,nodead][] Hunter's Mark" },
          help = "Hunter's Mark, send the pet, start Auto Shot" } },
    { "FeignDrop", "Feign Death",
        "#showtooltip Feign Death\n/petpassive\n/petfollow\n/stopattack\n/stopcasting\n/cast [combat] Feign Death",
        { swap = { "Feign Death" },
          old = { "#showtooltip Feign Death\n/stopattack\n/petfollow\n/cast Feign Death" },
          help = "In a fight: pet back, stop attacking, Feign Death" } },
    { "Melee", "Raptor Strike", "#showtooltip\n/cast Raptor Strike\n/cast Mongoose Bite",
        { swap = { "Raptor Strike" }, help = "Raptor Strike + Mongoose Bite on one button" } },
    { "Shoot", "Auto Shot", "#showtooltip Auto Shot\n/startattack\n/cast !Auto Shot",
        { swap = { "Auto Shot" }, help = "Auto Shot at range, sword swings up close (never 'too close')" } },
    { "FeedPet", "Feed Pet", "",
        { wheel = true, quiet = true, swap = { "Feed Pet" }, help = "Feed the pet with the food in your bags",
          build = function()
              local food = bagItem("food")
              return "#showtooltip Feed Pet\n/cast [pet,nodead] Feed Pet" ..
                  (food and ("\n/use [pet,nodead] item:" .. food) or "")
          end } },
    { "PetMove", "Call Pet", "/petmoveto",
        { icon = "Ability_Hunter_BeastCall", wheel = true, help = "Tell the pet where to stand" } },
    { "Track", "Track Beasts",
        "/run local c=UnitCreatureType(\"target\")if c then for i=1,C_Minimap.GetNumTrackingTypes()do " ..
        "local t=C_Minimap.GetTrackingInfo(i)if t.name:find(c,1,true)then C_Minimap.SetTracking(i,true)break end end end",
        { icon = "Ability_Tracking", wheel = true, help = "Track your target's kind (beast, humanoid...)" } },
    { "Stings", "Serpent Sting",
        "#showtooltip\n/cast [mod:alt] Viper Sting; [mod:ctrl] Scorpid Sting; Serpent Sting",
        { swap = { "Serpent Sting" }, help = "Serpent Sting. Keyboard: Alt = Viper, Ctrl = Scorpid" } },
    { "Cooldowns", "Rapid Fire",
        "#showtooltip Rapid Fire\n/cast Rapid Fire\n/cast Elune's Light\n/cast Blood Fury\n/cast Berserking\n/cast Bestial Wrath\n/use 13",
        { swap = { "Rapid Fire" }, help = "Rapid Fire + racial + Bestial Wrath + first trinket" } },
    { "Scatter", "Scatter Shot", "#showtooltip Scatter Shot\n/petpassive\n/petfollow\n/cast " .. MO .. "Scatter Shot",
        { swap = { "Scatter Shot" }, help = "Pet back (so it doesn't break it), then Scatter Shot" } },
    { "Tranq", "Tranquilizing Shot",
        "#showtooltip Tranquilizing Shot\n/cast [@mouseover,harm,nodead][@focus,harm,nodead][] Tranquilizing Shot",
        { swap = { "Tranquilizing Shot" }, help = "Tranquilizing Shot on mouseover, else focus, else target" } },
    { "SetFocus", "Tranquilizing Shot", "/focus " .. MO,
        { icon = "Ability_Hunter_SniperShot", wheel = true, help = "Make your target the focus (for Tranq)" } },
    { "Deter", "Deterrence", "#showtooltip Deterrence\n/cast Deterrence\n/cast Aspect of the Monkey",
        { swap = { "Deterrence" }, help = "Deterrence + Aspect of the Monkey" } },
    { "CancelRun", "Aspect of the Cheetah", "/cancelaura Aspect of the Cheetah\n/cancelaura Aspect of the Pack",
        { icon = "Ability_Mount_JungleTiger", wheel = true, help = "Drop Cheetah / Pack (no more daze)" } },
    { "ScareBeast", "Scare Beast", "#showtooltip Scare Beast\n/cast " .. MO .. "Scare Beast",
        { swap = { "Scare Beast" }, help = "Scare Beast on mouseover, else target" } },
    { "EagleEye", "Eagle Eye", "#showtooltip Eagle Eye\n/cast !Eagle Eye",
        { swap = { "Eagle Eye" }, help = "Eagle Eye, can be cast again while looking" } },
    { "Flare", "Flare", "#showtooltip Flare\n/cast [@cursor] Flare",
        { swap = { "Flare" }, desk = true, help = "Flare at the mouse cursor" } },
    { "Volley", "Volley", "#showtooltip Volley\n/cast [@cursor] Volley",
        { swap = { "Volley" }, desk = true, help = "Volley at the mouse cursor" } },
    { "TrapCursor", "Freezing Trap", "#showtooltip Freezing Trap\n/cast [@cursor] Freezing Trap",
        { swap = { "Freezing Trap" }, desk = true, help = "Freezing Trap where the cursor is" } },
    { "Cheetah", "Aspect of the Cheetah", "#showtooltip\n/cast [mod:alt] Aspect of the Pack; Aspect of the Cheetah",
        { help = "Aspect of the Cheetah. Keyboard: Alt = Pack" } },
    { "Hawk", "Aspect of the Hawk", "#showtooltip\n/cast [mod:alt] Aspect of the Beast; Aspect of the Hawk",
        { help = "Aspect of the Hawk. Keyboard: Alt = Beast" } },
    { "MisdTank", "Misdirection", "#showtooltip Misdirection\n/cast [@focus,help,nodead][@pet,exists,nodead] Misdirection",
        { swap = { "Misdirection" }, help = "Misdirection on your focus, else on your pet" } },
    { "Interrupt", "Counter Shot", "#showtooltip\n/cast " .. MO .. "Counter Shot",
        { swap = { "Counter Shot" }, help = "Counter Shot on mouseover, else target" } },
}

local function spellExists(name)
    if not name then return true end
    if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(name) ~= nil end
    return GetSpellInfo and GetSpellInfo(name) ~= nil
end

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
end

local function isHunter()
    local _, class = UnitClass("player")
    return class == "HUNTER"
end

local function trim(text) return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Per character: which macros were made (name -> the body written) and which bar slots
-- were given a macro (slot -> the spell that was there)
local function hunterState()
    local guid = UnitGUID("player") or "?"
    CouchUIDB.classMade = CouchUIDB.classMade or {}
    CouchUIDB.classMade[guid] = CouchUIDB.classMade[guid] or {}
    CouchUIDB.placed = CouchUIDB.placed or {}
    CouchUIDB.placed[guid] = CouchUIDB.placed[guid] or { slots = {} }
    CouchUIDB.placed[guid].slots = CouchUIDB.placed[guid].slots or {}
    return CouchUIDB.classMade[guid], CouchUIDB.placed[guid]
end

-- An item of the bags by kind ("food", "healthPotion"): Easy Controller's own sorting when
-- it is loaded, else by what using the item does. The last one seen is kept, so a macro
-- doesn't lose its line when the last potion is drunk.
local function itemKind(id)
    -- a healing potion by what it casts (Easy Controller reads the tooltip, which can
    -- still be empty right after a login)
    local use = C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(id)
    if type(use) == "string" and use:find("Healing Potion", 1, true) then return "healthPotion" end
    local ck = _G.ControllerKeyboard
    if ck and ck.ConsumableWheel and ck.ConsumableWheel.Category then
        local ok, cat = pcall(ck.ConsumableWheel.Category, id)
        if ok then return cat end
    end
    local spell = C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(id)
    if spell == "Food" then return "food" end
    if type(spell) == "string" and spell:find("Healing Potion", 1, true) then return "healthPotion" end
end

bagItem = function(kind)
    local _, placed = hunterState()
    placed.items = placed.items or {}
    local best, bestLevel
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local id = C_Container.GetContainerItemID(bag, slot)
                if id and itemKind(id) == kind then
                    local get = C_Item.GetItemInfo or GetItemInfo
                    local _, _, _, level, minLevel = get(id)
                    if (minLevel or 0) <= (UnitLevel("player") or 0) and (not best or (level or 0) > bestLevel) then
                        best, bestLevel = id, level or 0
                    end
                end
            end
        end
    end
    if best then placed.items[kind] = best end
    return best or placed.items[kind]
end

local function macroBody(m)
    local body, o = m[3], m[4]
    if o.build then
        local ok, built = pcall(o.build)
        return ok and built or nil
    end
    -- PetRecall / FeignDrop leave the pet passive: the attack macros wake it up again
    if o.assist and _G.SLASH_PET_ASSIST1 then body = "/petassist\n" .. body end
    return body
end

-- Checked at every login and whenever a spell is learned, so a macro appears as soon as its
-- spell does. Each macro is made once per character: delete one and it stays gone, edit one
-- and it stays yours (/couch macros brings deleted ones back).
local function makeClassMacros(verbose)
    if not isHunter() or InCombatLockdown() then return end
    local done = hunterState()
    local made, skipped, full = {}, {}, false
    for _, m in ipairs(HUNTER) do
        local name, need, body, o = m[1], m[2], macroBody(m), m[4]
        local idx = GetMacroIndexByName(name)
        if not body then
            -- nothing to put in it yet (no potion ever seen...)
        elseif idx ~= 0 then
            local _, _, cur = GetMacroInfo(idx)
            cur = trim(cur)
            local ours = type(done[name]) == "string" and cur == trim(done[name])
            for _, old in ipairs(o.old or {}) do if cur == trim(old) then ours = true end end
            if cur == trim(body) then
                done[name] = body
            elseif ours then
                if pcall(EditMacro, idx, nil, nil, body) then
                    done[name] = body
                    if not o.quiet then table.insert(made, name) end
                end
            else
                done[name] = done[name] or true          -- edited by the player: left alone
            end
        elseif verbose or not done[name] then
            if not spellExists(need) then
                table.insert(skipped, need)
            elseif not full then
                if not pcall(CreateMacro, name, o.icon or 134400, body, true) or GetMacroIndexByName(name) == 0 then
                    pcall(CreateMacro, name, 134400, body, true)
                end
                if GetMacroIndexByName(name) ~= 0 then
                    done[name] = body
                    table.insert(made, name)
                else
                    full = true
                end
            end
        end
    end
    if #made > 0 then
        say("hunter macro" .. (#made > 1 and "s" or "") .. " ready (character macros tab): " ..
            table.concat(made, ", "))
    end
    if full then say("|cffffaa00the character macro list is full - some hunter macros were left out|r") end
    if verbose and #skipped > 0 then
        local seen, list = {}, {}
        for _, n in ipairs(skipped) do if not seen[n] then seen[n] = true; table.insert(list, n) end end
        say("waiting for spells not learned yet / not in Forever: " .. table.concat(list, ", "))
    end
    return #made
end

-- spell name -> the macro that stands in for it (only macros that exist)
local function swapMap()
    local map = {}
    if not isHunter() or not CouchUIDB then return map end
    local _, placed = hunterState()
    if placed.off then return map end
    local desk = not isLoaded("EasyController")
    for _, m in ipairs(HUNTER) do
        local o = m[4]
        if o.swap and (desk or not o.desk) and GetMacroIndexByName(m[1]) ~= 0 then
            for _, spell in ipairs(o.swap) do map[spell] = map[spell] or m[1] end
        end
    end
    return map
end

-- For CouchWheels: the macro to show on a spell wheel in place of this spell, or nil
function CouchUI_MacroForSpell(spellID)
    local name = spellID and spellName(spellID)
    return name and swapMap()[name] or nil
end

local function isOurMacro(name)
    for _, m in ipairs(HUNTER) do if m[1] == name then return true end end
    return false
end

-- Bar buttons: every slot that holds a spell one of the macros stands in for gets the macro
-- (the same button, so nothing to relearn). A slot the player put the spell back on is left.
local function placeMacros(verbose)
    if not isHunter() or InCombatLockdown() then return end
    local _, placed = hunterState()
    local map = swapMap()
    if not next(map) then return end
    local ck = _G.ControllerKeyboard
    local M = ck and ck.Mapping
    local names, count = {}, 0
    for slot = 1, 300 do
        local ok, kind, id = pcall(GetActionInfo, slot)
        local spell = ok and kind == "spell" and id and spellName(id)
        local macro = spell and map[spell]
        local was = placed.slots[slot]
        if macro and not (was and was.name == spell) then
            local kept = M and M.SlotKept and select(2, pcall(M.SlotKept, M, slot))
            if not kept then
                ClearCursor()
                PickupMacro(macro)
                if GetCursorInfo() then
                    PlaceAction(slot)
                    ClearCursor()
                    if GetActionInfo(slot) == "macro" then
                        placed.slots[slot] = { id = id, name = spell }
                        count = count + 1
                        if not names[macro] then names[macro] = true; table.insert(names, macro) end
                    end
                end
            end
        end
    end
    if count > 0 then
        say(count .. " bar button" .. (count > 1 and "s now use" or " now uses") .. " your macros: " ..
            table.concat(names, ", ") .. "  (/couch macros undo puts the plain spells back)")
    elseif verbose then
        say("bar buttons: nothing to change")
    end
    return count
end

-- The macros with no spell of their own that belong in a fight (Fight, Panic): each on the
-- first empty controller button, once. Empty = a bar slot of a layer with nothing in it
-- and nothing of Easy Controller's on that button.
local FREE_ORDER = { "Y", "X", "B", "UP", "RIGHT", "DOWN", "LEFT", "A" }
local function placeButtons(verbose)
    if not isHunter() or InCombatLockdown() then return end
    local ck = _G.ControllerKeyboard
    local M = ck and ck.Mapping
    if not (M and M.BY_ID and M.NativeSlot and M.SlotAction) then return end
    local _, placed = hunterState()
    if placed.off then return end
    placed.buttons = placed.buttons or {}
    for _, m in ipairs(HUNTER) do
        local name = m[1]
        if m[4].button and not placed.buttons[name] and GetMacroIndexByName(name) ~= 0 then
            local where
            for _, layer in ipairs({ "LT", "RT", "LTRT" }) do
                for _, id in ipairs(FREE_ORDER) do
                    local inp = M.BY_ID[id]
                    local ok, slot = pcall(M.NativeSlot, M, inp, layer)
                    if ok and type(slot) == "number" and not M:Get(id, layer) and not M:GetReplaced(id, layer)
                        and not select(2, pcall(M.SlotAction, M, slot)) and not GetActionInfo(slot) then
                        ClearCursor()
                        PickupMacro(name)
                        if GetCursorInfo() then PlaceAction(slot) end
                        ClearCursor()
                        if GetActionInfo(slot) == "macro" then
                            where = (layer == "LTRT" and "LT + RT" or layer) .. " + " .. id
                            placed.buttons[name] = slot
                        end
                    end
                    if where then break end
                end
                if where then break end
            end
            if where then
                say("|cffffd100" .. name .. "|r is on |cffffffff" .. where .. "|r - " .. (m[4].help or ""))
            elseif verbose then
                say(name .. ": no empty controller button - put it on one in /ec map (Macros)")
            end
        end
    end
end

local function undoPlaced()
    if InCombatLockdown() then return say("leave combat first") end
    local _, placed = hunterState()
    local count = 0
    for slot, was in pairs(placed.slots) do
        local kind = GetActionInfo(slot)
        if kind == "macro" and isOurMacro(GetActionText(slot) or "") and was.id then
            ClearCursor()
            local pickup = C_Spell and C_Spell.PickupSpell or PickupSpell
            pcall(pickup, was.id)
            if GetCursorInfo() then PlaceAction(slot); count = count + 1 end
            ClearCursor()
        end
    end
    for name, slot in pairs(placed.buttons or {}) do
        if GetActionInfo(slot) == "macro" and GetActionText(slot) == name then
            ClearCursor(); PickupAction(slot); ClearCursor()
        end
    end
    placed.slots, placed.buttons = {}, nil
    placed.off = true
    if _G.CouchWheels_Refill then pcall(_G.CouchWheels_Refill) end
    say(count .. " bar buttons back to the plain spells; wheels too. /couch macros turns the macros on again.")
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
    -- (2.12) /ginvite is blocked in macros on Forever: the target's own menu (Guild Invite)
    { "SocGuild", "INV_Shirt_GuildTabard_01", "/click CouchRecruitMenu" },
    -- (2.11) was a /run InitiateTrade script: Forever blocks it ("macro script has been
    -- blocked"). The game's own /trade does the same.
    { "SocTrade", "INV_Misc_Coin_02", "/trade" },
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
    -- (2.10) no longer on LT + RB: see fixSocial
    for _, b in ipairs({}) do
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
        verbose = true                      -- said once, when it gets its button
    else
        input, layer = ck.MyWheels:Bound(w.id)
    end
    pcall(ck.MyWheels.UpdateBindingNames, ck.MyWheels)
    pcall(ck.ConsumableWheel.Fill, ck.ConsumableWheel)
    pcall(ck.Mapping.Apply, ck.Mapping)
    if ck.Paddles then pcall(ck.Paddles.Apply, ck.Paddles) end
    if verbose then
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

-- ---- Hunter wheel (couch): the macros with no spell of their own (pet attack / recall /
-- summon / move, tracking, focus...). Made once there is something to put on it; goes on
-- the first free combo of R3 + LT + RT, L3 + LT, L3 + RT, L3 + LT + RT (change: /ec map).
local HUNTER_BUTTONS = { { "R3", "LTRT", true }, { "L3", "LT" }, { "L3", "RT" }, { "L3", "LTRT" } }

-- Put a wheel on the first usable button of a list { input, layer, mayReplace }: a button
-- with no function at all, or (mayReplace) one of the game's that holds nothing - an empty
-- bar slot, a function Easy Controller lets go. Never a button with something of yours.
local function bindWheel(ck, id, buttons)
    local M = ck.Mapping
    local action = "wheel:" .. id
    for _, b in ipairs(buttons) do
        local inp = M.BY_ID and M.BY_ID[b[1]]
        local cur, replaced = M:Get(b[1], b[2]), M:GetReplaced(b[1], b[2])
        if cur == action or replaced == action then return b[1], b[2] end
        if inp and not cur and not replaced then
            local ok, state = pcall(M.State, M, inp, b[2])
            local slot = inp.bar and select(2, pcall(M.NativeSlot, M, inp, b[2]))
            local holds = type(slot) == "number" and select(2, pcall(M.SlotAction, M, slot))
            if ok and state == "free" then
                M:Set(b[1], b[2], action)
                return b[1], b[2]
            elseif ok and b[3] and state ~= "locked" and not holds and M:Replaceable(inp, b[2]) then
                M:SetReplaced(b[1], b[2], action)
                return b[1], b[2]
            end
        end
    end
end
local COMBO = { [""] = "", LT = "LT + ", RT = "RT + ", LTRT = "LT + RT + " }
local function setupHunterWheel(verbose)
    if not isHunter() or InCombatLockdown() then return end
    local ck = ecSocial()
    if not ck then return end
    local _, placed = hunterState()
    local slots = {}
    for _, m in ipairs(HUNTER) do
        if m[4].wheel and #slots < 8 and GetMacroIndexByName(m[1]) ~= 0 then
            slots[#slots + 1] = "macro:" .. m[1]
        end
    end
    local w
    for _, x in ipairs(ck.MyWheels:List()) do if x.couchHunter then w = x end end
    if #slots == 0 or placed.wheelOff then return end
    local changed = false
    if not w then
        local id = ck.MyWheels:Create()
        if not id then
            if verbose then say("Hunter wheel: Easy Controller has no free wheel (8 max)") end
            return
        end
        w = ck.MyWheels:Get(id)
        w.couchHunter = true
        placed.wheelBound = nil
        changed = true
    end
    if w.name ~= "Hunter" then w.name = "Hunter"; changed = true end
    for i = 1, 8 do
        if w.slots[i] ~= slots[i] then w.slots[i] = slots[i]; changed = true end
    end
    local input, layer
    if not placed.wheelBound then
        input, layer = bindWheel(ck, w.id, HUNTER_BUTTONS)
        placed.wheelBound = true
        changed = true
    else
        input, layer = ck.MyWheels:Bound(w.id)
    end
    if changed then
        pcall(ck.MyWheels.UpdateBindingNames, ck.MyWheels)
        pcall(ck.ConsumableWheel.Fill, ck.ConsumableWheel)
        pcall(ck.Mapping.Apply, ck.Mapping)
        if ck.Paddles then pcall(ck.Paddles.Apply, ck.Paddles) end
    end
    if changed or verbose then
        local names = {}
        for _, a in ipairs(slots) do names[#names + 1] = a:match("^macro:(.+)$") end
        say("Hunter wheel" .. (input and (" on " .. (COMBO[layer or ""] or "") .. input) or
            " has no button yet - pick one in /ec map") .. ": " .. table.concat(names, ", "))
    end
end

-- (2.10) The Social wheel sat on LT + RB. Easy Controller can only read LT + RB when RB
-- alone is taken away from the game ("nothing"), which switched off RB's enemy targeting.
-- RB goes back to the game; the wheel moves to LT + RT + D-pad left (next to Emotes).
local SOCIAL_BUTTONS = { { "LEFT", "LTRT", true }, { "UP", "LTRT", true }, { "DOWN", "LTRT", true },
    { "X", "LTRT", true }, { "Y", "LTRT", true } }
local function fixSocial()
    if InCombatLockdown() then return end
    local ck, w = ecSocial()
    if not ck then return end
    local M = ck.Mapping
    local changed = false
    local input, layer
    if w then input, layer = ck.MyWheels:Bound(w.id) end
    if input == "RB" then
        M:SetReplaced("RB", layer, nil)
        input, changed = nil, true
    end
    if M:GetReplaced("RB", "") == M.NOTHING then
        M:SetReplaced("RB", "", nil)
        changed = true
    end
    local key = UnitGUID("player") or "?"
    CouchUIDB.socialMoved = CouchUIDB.socialMoved or {}
    if w and not input and not CouchUIDB.socialMoved[key] then
        input, layer = bindWheel(ck, w.id, SOCIAL_BUTTONS)
        CouchUIDB.socialMoved[key] = true
        if input then
            changed = true
            say("Social wheel is now on " .. (COMBO[layer or ""] or "") .. "D-pad " .. input:lower() ..
                " - RB is the game's enemy targeting again")
        else
            say("Social wheel has no button - pick one in /ec map. RB is the game's enemy targeting again")
        end
    end
    if changed then
        pcall(ck.MyWheels.UpdateBindingNames, ck.MyWheels)
        pcall(ck.ConsumableWheel.Fill, ck.ConsumableWheel)
        pcall(M.Apply, M)
        if ck.Paddles then pcall(ck.Paddles.Apply, ck.Paddles) end
    end
end

-- ---- Emote wheel (couch): the emote row of the 2005 WoW keyboard, on the controller.
-- Account macros (any character), a wheel named "Emotes" on LT + RT + D-pad right (D-pad
-- right alone = the chat phrases), else a free L3 combo. /couch emotes [off].
local EMOTES = {
    { "EmApplaud", "INV_Misc_Bell_01", "/applaud" },
    { "EmCheer", "Ability_Warrior_BattleShout", "/cheer" },
    { "EmLaugh", "Spell_Holy_MindSooth", "/laugh" },
    { "EmSalute", "Ability_Warrior_DefensiveStance", "/salute" },
    { "EmWave", "INV_Misc_Flower_02", "/wave" },
    { "EmBow", "Spell_Holy_SealOfWisdom", "/bow" },
    { "EmKneel", "Spell_Holy_PrayerOfFortitude", "/kneel" },
    { "EmRoar", "Ability_Druid_ChallangingRoar", "/roar" },
}
local EMOTE_BUTTONS = { { "RIGHT", "LTRT", true }, { "L3", "LTRT" }, { "L3", "RT" }, { "L3", "LT" } }
local function setupEmotes(verbose)
    if InCombatLockdown() then return end
    local ck = ecSocial()
    if not ck or CouchUIDB.emotesOff then return end
    local slots = {}
    for _, m in ipairs(EMOTES) do
        if GetMacroIndexByName(m[1]) == 0 and not (CouchUIDB.emotesMade and CouchUIDB.emotesMade[m[1]]) then
            if not pcall(CreateMacro, m[1], m[2], m[3], false) or GetMacroIndexByName(m[1]) == 0 then
                pcall(CreateMacro, m[1], 134400, m[3], false)
            end
            CouchUIDB.emotesMade = CouchUIDB.emotesMade or {}
            CouchUIDB.emotesMade[m[1]] = true
        end
        if GetMacroIndexByName(m[1]) ~= 0 then slots[#slots + 1] = "macro:" .. m[1] end
    end
    if #slots == 0 then return end
    local w
    for _, x in ipairs(ck.MyWheels:List()) do if x.couchEmotes then w = x end end
    local changed = false
    local key = UnitGUID("player") or "?"
    CouchUIDB.emotesBound = CouchUIDB.emotesBound or {}
    if not w then
        local id = ck.MyWheels:Create()
        if not id then
            if verbose then say("Emote wheel: Easy Controller has no free wheel (8 max)") end
            return
        end
        w = ck.MyWheels:Get(id)
        w.couchEmotes = true
        CouchUIDB.emotesBound[key] = nil
        changed = true
    end
    if w.name ~= "Emotes" then w.name = "Emotes"; changed = true end
    for i = 1, 8 do
        if w.slots[i] ~= slots[i] then w.slots[i] = slots[i]; changed = true end
    end
    local input, layer
    if not CouchUIDB.emotesBound[key] then
        input, layer = bindWheel(ck, w.id, EMOTE_BUTTONS)
        CouchUIDB.emotesBound[key] = true
        changed = true
    else
        input, layer = ck.MyWheels:Bound(w.id)
    end
    if changed then
        pcall(ck.MyWheels.UpdateBindingNames, ck.MyWheels)
        pcall(ck.ConsumableWheel.Fill, ck.ConsumableWheel)
        pcall(ck.Mapping.Apply, ck.Mapping)
        if ck.Paddles then pcall(ck.Paddles.Apply, ck.Paddles) end
    end
    if changed or verbose then
        say("Emote wheel" .. (input and (" on " .. (COMBO[layer or ""] or "") .. input) or
            " has no button yet - pick one in /ec map") ..
            ": applaud, cheer, laugh, salute, wave, bow, kneel, roar")
    end
end

local function removeEmotes()
    if InCombatLockdown() then return say("leave combat first") end
    local ck = ecSocial()
    if ck then
        for _, x in ipairs(ck.MyWheels:List()) do
            if x.couchEmotes then pcall(ck.MyWheels.Delete, ck.MyWheels, x.id) break end
        end
    end
    CouchUIDB.emotesOff = true
    say("Emote wheel removed, its macros kept (/couch emotes to bring it back)")
end

-- Everything the hunter macros need, in order: made, put on the bar buttons, on the spell
-- wheels (CouchWheels) and on the Hunter wheel. Out of combat only (a game rule).
local function hunterMacros(verbose)
    if not isHunter() or InCombatLockdown() then return end
    makeClassMacros(verbose)
    placeMacros(verbose)
    placeButtons(verbose)
    if _G.CouchWheels_Refill then pcall(_G.CouchWheels_Refill) end
    setupHunterWheel(verbose)
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
    SocGuild = "Your target's menu (pick Guild Invite)",
    SocTrade = "Open a trade with your target",
    SocFollow = "Follow your target",
    SocFriend = "Add your target as a friend",
    QuestItem = "Uses the item of your current quest (the one you just looted, else the nearest quest's)",
    Recruit = "Targets the next player near you with no guild and opens their menu (Guild Invite)",
}
local MACRO_ORDER = { "Mount", "Hearth", "Reload", "Leave" }
for _, m in ipairs(HUNTER) do
    MACRO_HELP[m[1]] = m[4].help
    table.insert(MACRO_ORDER, m[1])
end
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
    table.insert(wheels, HEAD .. "EMOTE WHEEL|r")
    table.insert(wheels, "Applaud, Cheer, Laugh, Salute, Wave, Bow, Kneel, Roar")
    table.insert(wheels, " ")
    table.insert(wheels, HEAD .. "HUNTER WHEEL|r")
    table.insert(wheels, "Pet attack / recall / summon / move, tracking")
    table.insert(wheels, " ")
    table.insert(wheels, HEAD .. "OUTSIDE THE GAME|r")
    table.insert(wheels, KEY .. "Hold Xbox button 1 s|r  controller as mouse on / off")
    table.insert(wheels, KEY .. "Tap View|r (on the desktop)  desktop button help")
    local macros = { HEAD .. "MACROS|r" }
    for _, name in ipairs(MACRO_ORDER) do
        local ok, idx = pcall(GetMacroIndexByName, name)
        if ok and idx and idx > 0 then
            table.insert(macros, KEY .. name .. "|r  " .. clip(MACRO_HELP[name], 52))
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
    f.hint:SetText("Any controller button or Esc closes this  -  open it again: Social wheel > Controls")
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

-- ---- Recruit (2.11): one button press = one guild invite to the next player near you ----
-- who has no guild. CouchUI watches the players around you (target, mouseover, LB's soft
-- friend target, nameplates) and people talking in /say, /yell and General/Trade, skips
-- anyone in a guild or already asked (remembered for good), and keeps the "Recruit" macro
-- pointed at the newest one: its body is `/ginvite Name`, run by the game itself (an addon
-- calling the invite directly would be blocked). Each press asks one person; nothing is
-- ever sent on its own. On LT + D-pad right (couch). /couch recruit = stats + who is next.
-- (2.12) WoW Forever blocks /ginvite in macros ("A macro script has been blocked"): the
-- invite itself has to come from the game's own UI. So the macro now targets the player and
-- opens the game's player menu (secure "togglemenu" button, /click) - pick Guild Invite there.
local RECRUIT, RECRUIT_ICON = "Recruit", "INV_Misc_Note_02"
local RECRUIT_BUTTON = { "RIGHT", "LT" }      -- LT + D-pad right: empty
local RECRUIT_UNITS = { "target", "mouseover", "softfriend", "softinteract", "focus" }
local nearby = {}           -- name -> GetTime() last seen
local fromChat = {}         -- name -> true: heard in chat, guild unknown
local recruitDirty = true      -- rewrite the macro once at login (older bodies used /ginvite)

local function recruitDB()
    CouchUIDB.recruit = CouchUIDB.recruit or {}
    local r = CouchUIDB.recruit
    if not r.v215 then r.done, r.v212, r.v215 = {}, true, true end  -- earlier "asked" never went out   -- 2.11's "asked" were blocked: none went out
    r.done, r.placed = r.done or {}, r.placed or {}
    r.invited, r.joined, r.declined = r.invited or 0, r.joined or 0, r.declined or 0
    return r
end

local function shortName(n)
    if not n or n == "" then return end
    return Ambiguate and Ambiguate(n, "none") or n
end

local function addCandidate(n, chat)
    n = shortName(n)
    if not n or n == UnitName("player") or recruitDB().done[n] then return end
    if chat then
        if not nearby[n] then fromChat[n] = true end
    else
        fromChat[n] = nil                       -- seen in person: no guild for sure
    end
    if not nearby[n] then recruitDirty = true end
    nearby[n] = GetTime()
end

local function considerUnit(unit)
    if not (UnitExists(unit) and UnitIsPlayer(unit)) or UnitIsUnit(unit, "player") then return end
    if not UnitIsFriend("player", unit) then return end
    local n = shortName(GetUnitName(unit, true))
    if GetGuildInfo(unit) then                  -- has a guild: never asked
        if n and nearby[n] then nearby[n] = nil; recruitDirty = true end
        return
    end
    addCandidate(n, false)
end

local function recruitPick()
    local now, best, bestT, left = GetTime(), nil, -1, 0
    local done = recruitDB().done
    for n, t in pairs(nearby) do
        -- (2.13) only players seen around you in the last minute: /target only finds them
        if done[n] or fromChat[n] or now - t > 60 then
            nearby[n], fromChat[n] = nil, nil
        else
            left = left + 1
            if t > bestT then best, bestT = n, t end
        end
    end
    return best, left
end

local function recruitBody(n)
    -- (2.15) the macro only targets the player. The invite itself is typed by the `pad`
    -- service on the PC: it sees LT + D-pad right on the controller and types "/ginvite" +
    -- Enter (real key presses: a typed /ginvite works on Forever, from a macro or an addon it
    -- is blocked). /ginvite with no name invites the target.
    if n then
        return "/cleartarget\n/target " .. n .. "\n/couch recruit sent " .. n
    end
    return "/couch recruit sent"      -- nobody new: your own target (LB) gets the invite
end

-- the game's own player menu for your target, opened by a secure button (never addon code)
local function recruitMenuButton()
    if _G.CouchRecruitMenu or InCombatLockdown() then return end
    local b = CreateFrame("Button", "CouchRecruitMenu", UIParent, "SecureActionButtonTemplate")
    b:SetAttribute("type", "togglemenu")
    b:SetAttribute("unit", "target")
    b:RegisterForClicks("AnyUp")
    b:SetSize(1, 1)
    b:SetPoint("CENTER")
end

local function recruitUpdate()
    if InCombatLockdown() then return end        -- macros cannot be edited in a fight
    recruitDirty = false
    local idx = GetMacroIndexByName(RECRUIT)
    if not idx or idx == 0 then return end
    local body = recruitBody((recruitPick()))
    local _, _, cur = GetMacroInfo(idx)
    if trim(cur) ~= body then pcall(EditMacro, idx, nil, nil, body) end
end

local function recruitHasRights()
    if not IsInGuild() then say("Recruit: you are not in a guild"); return false end
    if CanGuildInvite and not CanGuildInvite() then
        say("Recruit: your guild rank is not allowed to invite"); return false
    end
    return true
end

-- (2.14) Forever blocks /ginvite from macros but not typed in the chat box (tested: the
-- server answered "not found", no popup). So the button puts "/ginvite Name" in the chat
-- box and you press A (Send). Nothing is sent without that press.
local function openChat(text)
    local open = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
    open(text)
end

local recruitPending
local function recruitGo(test)
    if test then openChat("/ginvite Zzqxnobody"); return end
    local n, left = recruitPick()
    if not n then
        say("Recruit: nobody new nearby - walk past some players")
        return
    end
    nearby[n] = nil
    recruitDB().done[n] = time()
    recruitPending = n
    openChat("/ginvite " .. n)
    say("Recruit: press |cffffffffA (Send)|r to invite |cffffffff" .. n .. "|r" ..
        (left > 1 and (" (" .. (left - 1) .. " more nearby)") or ""))
end

local function recruitSent(n)
    n = shortName(n)
    if not n or n == "" then
        local _, left = recruitPick()
        if UnitIsPlayer("target") and not UnitIsUnit("target", "player") and not GetGuildInfo("target") then
            say("Recruit: inviting your target |cffffffff" .. (GetUnitName("target", true) or "?") .. "|r")
            if _G.CouchLights_Recruit then pcall(_G.CouchLights_Recruit) end
        elseif not UnitExists("target") and left == 0 then
            say("Recruit: nobody new nearby - walk past some players (or target one with LB)")
        elseif UnitIsPlayer("target") and GetGuildInfo("target") then
            say("Recruit: " .. (UnitName("target") or "?") .. " is already in a guild")
        end
        recruitHasRights()
        return
    end
    nearby[n], fromChat[n] = nil, nil
    if not (UnitExists("target") and shortName(GetUnitName("target", true)) == n) then
        say("Recruit: " .. n .. " walked out of range - press again for the next one")
    else
        recruitDB().done[n] = time()
        if _G.CouchLights_Recruit then pcall(_G.CouchLights_Recruit) end   -- PC types /ginvite
        local _, left = recruitPick()
        say("Recruit: inviting |cffffffff" .. n .. "|r" ..
            (left > 0 and (" (" .. left .. " more nearby)") or ""))
        recruitHasRights()
    end
    C_Timer.After(0.3, recruitUpdate)            -- after the macro has finished running
end

local function msgPattern(fmt)
    if type(fmt) ~= "string" then return end
    return "^" .. fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"
end

local function recruitStats()
    local r = recruitDB()
    local nextName, left = recruitPick()
    say(("Recruit: %d asked, %d joined, %d declined. Next: %s (%d nearby)"):format(
        r.invited, r.joined, r.declined, nextName or "nobody yet", left))
    say("Press |cffffffffLT + D-pad right|r to ask the next one. /couch recruit plates = show " ..
        "friendly nameplates (finds many more players), /couch recruit reset = forget who was asked")
end

local function placeRecruit(verbose)
    if InCombatLockdown() then return end
    recruitMenuButton()
    local r0 = recruitDB()
    if not r0.platesOn then                      -- friendly nameplates: Recruit sees everyone around
        r0.platesOn = true
        pcall(SetCVar, "nameplateShowFriends", 1)
    end
    if GetMacroIndexByName(RECRUIT) == 0 then
        if not pcall(CreateMacro, RECRUIT, RECRUIT_ICON, recruitBody(nil), false) then
            pcall(CreateMacro, RECRUIT, 134400, recruitBody(nil), false)
        end
        if GetMacroIndexByName(RECRUIT) == 0 then return say("Recruit: no room for another macro") end
    end
    local ck = _G.ControllerKeyboard
    local M = ck and ck.Mapping
    if not (M and M.BY_ID and M.NativeSlot) then return end
    local r, key = recruitDB(), UnitGUID("player") or "?"
    local input, layer = RECRUIT_BUTTON[1], RECRUIT_BUTTON[2]
    local ok, slot = pcall(M.NativeSlot, M, M.BY_ID[input], layer)
    if not (ok and type(slot) == "number") then return end
    local kind = GetActionInfo(slot)
    if kind == "macro" and GetActionText(slot) == RECRUIT then r.placed[key] = slot; return end
    if r.placed[key] and not verbose then return end  -- you moved it: left alone
    if kind or M:Get(input, layer) or M:GetReplaced(input, layer) then
        return say("Recruit: LT + D-pad right is taken - put the Recruit macro on a button in /ec map")
    end
    ClearCursor(); PickupMacro(RECRUIT)
    if GetCursorInfo() then PlaceAction(slot) end
    ClearCursor()
    recruitUpdate()
    if GetActionInfo(slot) == "macro" then
        r.placed[key] = slot
        say("|cffffd100Recruit|r is on |cffffffffLT + D-pad right|r - each press asks the next player " ..
            "near you who has no guild. /couch recruit for stats")
    end
end

local function watchRecruit()
    local fr = CreateFrame("Frame")
    local pats = {
        invited = msgPattern(_G.ERR_GUILD_INVITE_S), joined = msgPattern(_G.ERR_GUILD_JOIN_S),
        declined = msgPattern(_G.ERR_GUILD_DECLINE_S), inguild = msgPattern(_G.ERR_ALREADY_IN_GUILD_S),
        pending = msgPattern(_G.ERR_ALREADY_INVITED_TO_GUILD_S),
        missing = msgPattern(_G.ERR_GUILD_PLAYER_NOT_FOUND_S),
    }
    for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
        "PLAYER_SOFT_FRIEND_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED", "CHAT_MSG_SAY", "CHAT_MSG_YELL",
        "CHAT_MSG_CHANNEL", "CHAT_MSG_SYSTEM", "PLAYER_REGEN_ENABLED" }) do
        pcall(fr.RegisterEvent, fr, ev)
    end
    fr:SetScript("OnEvent", function(_, ev, a1, a2)
        pcall(function()
            if ev == "NAME_PLATE_UNIT_ADDED" then considerUnit(a1)
            elseif ev == "UPDATE_MOUSEOVER_UNIT" then considerUnit("mouseover")
            elseif ev == "PLAYER_TARGET_CHANGED" then considerUnit("target")
            elseif ev == "PLAYER_SOFT_FRIEND_CHANGED" then considerUnit("softfriend")
            elseif ev == "PLAYER_SOFT_INTERACT_CHANGED" then considerUnit("softinteract")
            elseif ev == "PLAYER_REGEN_ENABLED" then recruitDirty = true
            elseif ev == "CHAT_MSG_SYSTEM" then
                local r = recruitDB()
                for kind, p in pairs(pats) do
                    local n = p and a1:match(p)
                    if n then
                        n = shortName(n)
                        if kind == "invited" then r.invited = r.invited + 1
                        elseif kind == "joined" then if r.done[n] then r.joined = r.joined + 1 end
                        elseif kind == "declined" then r.declined = r.declined + 1 end
                        if kind ~= "joined" then r.done[n] = r.done[n] or time() end
                        nearby[n], recruitDirty = nil, true
                    end
                end
            elseif a2 and not nearby[shortName(a2) or ""] then  -- chat: someone talking nearby
                -- (2.13) chat speakers are often far away: not used
            end
        end)
    end)
    C_Timer.NewTicker(2, function()
        pcall(function()
            for _, u in ipairs(RECRUIT_UNITS) do considerUnit(u) end
            if C_NamePlate and C_NamePlate.GetNamePlates then
                for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
                    if plate.namePlateUnitToken then considerUnit(plate.namePlateUnitToken) end
                end
            end
            if recruitDirty then recruitUpdate() end
        end)
    end)
end

-- ---- Auto bag sort (2.16): the game's own "Clean Up Bags" (C_Container.SortBags), run by
-- itself when you CLOSE your bags after something in them changed - never while you look at
-- them, never in a fight, and not while a vendor / bank / mailbox / trade / auction house is
-- open. Bags you set to "Ignore Clean Up" stay as they are. /couch sort [on|off|now]
local sortDirty, sortBusyUntil, bagsWereOpen, busyFrames = false, 0, false, 0
local function bagsOpen()
    if IsAnyBagOpen then
        local ok, open = pcall(IsAnyBagOpen)
        if ok then return open end
    end
    local combined = _G.ContainerFrameCombinedBags
    return combined and combined:IsShown() or false
end
local SORT_BUSY = { "MerchantFrame", "BankFrame", "MailFrame", "TradeFrame", "AuctionHouseFrame",
    "GuildBankFrame", "AccountBankPanel" }
local function sortBlocked()
    if InCombatLockdown() or GetCursorInfo() then return true end
    for _, name in ipairs(SORT_BUSY) do
        local fr = _G[name]
        if fr and fr.IsShown and fr:IsShown() then return true end
    end
    return false
end
local function sortBags(verbose)
    if not (C_Container and C_Container.SortBags) then
        return verbose and say("bag sort: not available in this client")
    end
    if sortBlocked() then return verbose and say("bag sort: not now (fight / vendor / bank / item on cursor)") end
    sortDirty = false
    sortBusyUntil = GetTime() + 6                  -- the sort's own item moves are not "changes"
    local ok, err = pcall(C_Container.SortBags)
    if not ok then say("bag sort failed: " .. tostring(err))
    elseif verbose then say("bags sorted") end
end
local function watchBags()
    local fr = CreateFrame("Frame")
    fr:RegisterEvent("BAG_UPDATE_DELAYED")
    fr:SetScript("OnEvent", function()
        if GetTime() > sortBusyUntil then sortDirty = true end
    end)
    C_Timer.NewTicker(1, function()
        if CouchUIDB.bagSort == false then return end
        local open = bagsOpen()
        if bagsWereOpen and not open and sortDirty then
            C_Timer.After(0.5, function()
                if not bagsOpen() and not sortBlocked() then sortBags(false) end
            end)
        end
        bagsWereOpen = open
    end)
end

-- ---- Quest item button (2.17): the usable item of a quest (the one you normally click in
-- the quest tracker or dig out of your bags) on ONE fixed controller button. A macro
-- "QuestItem" (`/use item:ID`) sits on the first empty controller button; its item is the one
-- you just looted for a quest, else the one of the quest closest to you. Updated out of
-- combat (macros cannot change in a fight - the button keeps its item until then).
-- /couch questitem = which item and which button.
local QITEM, QITEM_ICON = "QuestItem", "INV_Misc_QuestionMark"
local qPinned, qPinnedUntil, qBagSeen, qCurrent = nil, 0, nil, nil

local function questItemList()
    local list, seen = {}, {}
    local function add(id, dist)
        if id and not seen[id] and (C_Item.GetItemCount and C_Item.GetItemCount(id) or GetItemCount(id)) > 0 then
            seen[id] = true
            table.insert(list, { id = id, d = dist })
        end
    end
    local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and GetQuestLogSpecialItemInfo then
            local link, _, _, showDone = GetQuestLogSpecialItemInfo(i)
            local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
            if link and (showDone or not done) then
                local d
                if C_QuestLog.GetDistanceSqToQuest then
                    local ok, dsq = pcall(C_QuestLog.GetDistanceSqToQuest, info.questID)
                    d = ok and type(dsq) == "number" and dsq or nil
                end
                add(tonumber(link:match("item:(%d+)")), d or 1e12)
            end
        end
    end
    -- items marked "Quest" in your bags that have a Use: (some are not in the quest log)
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and not seen[id] then
                local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
                if classID == 12 and C_Item.GetItemSpell(id) then add(id, 1e13) end
            end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    return list
end

local function questItemBags()       -- new quest items since last look: they get the button
    local now = {}
    for _, it in ipairs(questItemList()) do now[it.id] = true end
    if qBagSeen then
        for id in pairs(now) do
            if not qBagSeen[id] then qPinned, qPinnedUntil = id, GetTime() + 600 end
        end
    end
    qBagSeen = now
end

local function questItemPick()
    local list = questItemList()
    if qPinned and GetTime() < qPinnedUntil then
        for _, it in ipairs(list) do if it.id == qPinned then return qPinned, #list end end
    end
    return list[1] and list[1].id, #list
end

local function questItemBody(id)
    if id then return "#showtooltip\n/use item:" .. id end
    return "#showtooltip\n/couch questitem"
end

local qWhere
local function questItemPlace()
    if InCombatLockdown() then return end
    if GetMacroIndexByName(QITEM) == 0 then
        if not pcall(CreateMacro, QITEM, QITEM_ICON, questItemBody(nil), false) then
            pcall(CreateMacro, QITEM, 134400, questItemBody(nil), false)
        end
        if GetMacroIndexByName(QITEM) == 0 then return end
    end
    local ck = _G.ControllerKeyboard
    local M = ck and ck.Mapping
    if not (M and M.BY_ID and M.NativeSlot and M.SlotAction) then return end
    CouchUIDB.questItemSlot = CouchUIDB.questItemSlot or {}
    local key = UnitGUID("player") or "?"
    local have = CouchUIDB.questItemSlot[key]
    if have then
        if GetActionInfo(have.slot) == "macro" and GetActionText(have.slot) == QITEM then
            qWhere = have.where
            return
        end
        if have.moved then return end      -- you took it off: left alone (/couch questitem place)
    end
    for _, layer in ipairs({ "LT", "RT", "LTRT" }) do
        for _, id in ipairs({ "Y", "X", "B", "UP", "RIGHT", "DOWN", "LEFT", "A" }) do
            local ok, slot = pcall(M.NativeSlot, M, M.BY_ID[id], layer)
            if ok and type(slot) == "number" and not M:Get(id, layer) and not M:GetReplaced(id, layer)
                and not select(2, pcall(M.SlotAction, M, slot)) and not GetActionInfo(slot) then
                ClearCursor(); PickupMacro(QITEM)
                if GetCursorInfo() then PlaceAction(slot) end
                ClearCursor()
                if GetActionInfo(slot) == "macro" then
                    qWhere = (layer == "LTRT" and "LT + RT" or layer) .. " + " ..
                        (({ UP = "D-pad up", DOWN = "D-pad down", LEFT = "D-pad left", RIGHT = "D-pad right" })[id] or id)
                    CouchUIDB.questItemSlot[key] = { slot = slot, where = qWhere }
                    say("|cffffd100Quest item|r button is on |cffffffff" .. qWhere ..
                        "|r - it always holds the item for your current quest")
                    return
                end
            end
        end
    end
    say("Quest item: no empty controller button - put the QuestItem macro on one in /ec map")
end

local function questItemUpdate(verbose)
    if InCombatLockdown() then return end
    local idx = GetMacroIndexByName(QITEM)
    if not idx or idx == 0 then return end
    local id, count = questItemPick()
    local body = questItemBody(id)
    local _, _, cur = GetMacroInfo(idx)
    if trim(cur) ~= body then pcall(EditMacro, idx, nil, nil, body) end
    if id ~= qCurrent and id then
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or ("item " .. id)
        say("Quest item ready: |cffffffff" .. tostring(name) .. "|r" ..
            (qWhere and (" on |cffffffff" .. qWhere .. "|r") or "") ..
            (count > 1 and (" (" .. count .. " quest items: newest looted first, else nearest quest)") or ""))
    elseif verbose then
        say(id and ("Quest item: " .. tostring(C_Item.GetItemNameByID(id) or id) .. (qWhere and (" on " .. qWhere) or ""))
            or "Quest item: none right now")
    end
    qCurrent = id
end

local function watchQuestItems()
    local fr = CreateFrame("Frame")
    fr:RegisterEvent("BAG_UPDATE_DELAYED")
    fr:RegisterEvent("QUEST_LOG_UPDATE")
    fr:RegisterEvent("PLAYER_REGEN_ENABLED")
    local queued = false
    fr:SetScript("OnEvent", function(_, ev)
        if ev == "BAG_UPDATE_DELAYED" then pcall(questItemBags) end
        if queued then return end
        queued = true
        C_Timer.After(1, function() queued = false; pcall(questItemUpdate, false) end)
    end)
    C_Timer.NewTicker(5, function() pcall(questItemUpdate, false) end)  -- walking to another quest
end

local function applyAll(quiet)
    if InCombatLockdown() then return say("leave combat first") end
    local p, name = prof()
    applyLayout(name)
    setChatFont(p.font)
    setScale(p.scale)
    if not CouchUIDB.macrosMade then makeMacros(); CouchUIDB.macrosMade = true end
    fixPetMacro()
    if name == "Desk" and not CouchUIDB.bindsApplied then applyBinds() end
    if name == "Couch" then
        patchWhisperNames()
        -- after Easy Controller and CouchWheels have set up this character's wheels
        if not CouchUIDB.socialOff then
            C_Timer.After(6, function() pcall(setupSocial, false) end)
        end
    end
    -- after Easy Controller, CouchWheels and the Social wheel are in place
    C_Timer.After(name == "Couch" and 8 or 1, function()
        local ok, err = pcall(hunterMacros, false)
        if not ok then say("hunter macros: " .. tostring(err)) end
        ok, err = pcall(fixSocial)
        if not ok then say("social wheel: " .. tostring(err)) end
        ok, err = pcall(setupEmotes, false)
        if not ok then say("emote wheel: " .. tostring(err)) end
        ok, err = pcall(placeRecruit, false)
        if not ok then say("recruit: " .. tostring(err)) end
        ok, err = pcall(questItemPlace)
        if not ok then say("quest item: " .. tostring(err)) end
        pcall(questItemBags)
        pcall(questItemUpdate, false)
    end)
    if not quiet then say(name .. " profile applied. /couch for options.") end
    CouchUIDB.arranged = CouchUIDB.arranged or {}
    local v = CouchUIDB.arranged[name]
    if v ~= -1 and (v or 0) < ARRANGE_VERSION then C_Timer.After(1, function() arrange(name) end) end
end

-- ---- Raptor Strike is ready again: a short buzz in the controller (couch, in a fight) ---
-- From the combat log: Raptor Strike pressed 15 times while still cooling down.
-- /couch rumble off | on
local function watchRaptor()
    local r = CreateFrame("Frame")
    local pending = 0
    r:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    r:SetScript("OnEvent", function(_, _, unit, _, spellID)
        pcall(function()
            if unit ~= "player" or CouchUIDB.raptorRumble == false then return end
            local ck = _G.ControllerKeyboard
            if not (ck and ck.Vibration and ck.Vibration.Play) then return end
            if spellName(spellID) ~= "Raptor Strike" then return end
            local ms = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID) or 0
            if not ms or ms < 1500 then ms = 6000 end
            pending = pending + 1
            local mine = pending
            C_Timer.After(ms / 1000, function()
                if mine == pending and InCombatLockdown() and CouchUIDB.raptorRumble ~= false then
                    pcall(ck.Vibration.Play, ck.Vibration, "tick", 1)
                end
            end)
        end)
    end)
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
    if isHunter() then pcall(watchRaptor) end
    pcall(recruitMenuButton)
    pcall(watchRecruit)
    pcall(watchBags)
    pcall(watchQuestItems)
    -- 2026-11-15: a stray click (screen control) unticked Secure Ability Toggle: put it back once
    if not CouchUIDB.satFixed then
        CouchUIDB.satFixed = true
        pcall(SetCVar, "secureAbilityToggle", "1")
    end
    -- (2.12) which function does Forever block? Printed in chat + kept in CouchUIDB.blocked
    pcall(SetCVar, "taintLog", "1")
    local bl = CreateFrame("Frame")
    for _, ev in ipairs({ "MACRO_ACTION_BLOCKED", "ADDON_ACTION_BLOCKED", "MACRO_ACTION_FORBIDDEN",
        "ADDON_ACTION_FORBIDDEN" }) do pcall(bl.RegisterEvent, bl, ev) end
    bl:SetScript("OnEvent", function(_, ev, who, func)
        CouchUIDB.blocked = CouchUIDB.blocked or {}
        table.insert(CouchUIDB.blocked, date("%H:%M:%S") .. " " .. ev .. " " .. tostring(who) ..
            " " .. tostring(func))
        while #CouchUIDB.blocked > 30 do table.remove(CouchUIDB.blocked, 1) end
        say("|cffff6060blocked:|r " .. tostring(func) .. "  (" .. ev:lower() .. ", " .. tostring(who) .. ")")
    end)
    -- a newly learned spell may unlock one of the hunter macros
    local queued = false
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("SPELLS_CHANGED")
    watch:RegisterEvent("PLAYER_REGEN_ENABLED")
    watch:RegisterEvent("BAG_UPDATE_DELAYED")           -- a potion / pet food picked up
    watch:SetScript("OnEvent", function()
        if queued then return end
        queued = true
        C_Timer.After(4, function() queued = false; pcall(hunterMacros, false) end)
    end)
    local last = CouchUIDB.lastProfile
    C_Timer.After(3, function()
        applyAll(last == profileName())
        CouchUIDB.lastProfile = profileName()
    end)
end)

SLASH_COUCHUI1 = "/couch"
SlashCmdList.COUCHUI = function(input)
    local raw = strtrim(input or "")
    if raw:lower() == "recruit go" or raw:lower() == "recruit test" then
        return recruitGo(raw:lower() == "recruit test")
    end
    if raw:lower():find("^recruit sent") then          -- from the Recruit macro: name as typed
        return recruitSent(strtrim(raw:sub(13)))
    end
    local cmd, arg = strsplit(" ", raw:lower(), 2)
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
    elseif cmd == "macros" then
        if arg == "undo" then return undoPlaced() end
        if InCombatLockdown() then return say("leave combat first") end
        makeMacros()
        if isHunter() then
            local _, placed = hunterState()
            placed.off, placed.wheelOff = nil, nil
            local ok, err = pcall(hunterMacros, true)
            if not ok then say("hunter macros: " .. tostring(err)) end
        end
    elseif cmd == "help" or cmd == "map" or cmd == "controls" then showHelp()
    elseif cmd == "lights" then
        CouchUIDB.combatLog = (arg ~= "off")
        pcall(LoggingCombat, CouchUIDB.combatLog)
        say("Combat log for light sync + smart music " .. (CouchUIDB.combatLog and "on" or "off"))
    elseif cmd == "binds" then if arg == "undo" then undoBinds() else applyBinds() end
    elseif cmd == "rumble" then
        CouchUIDB.raptorRumble = (arg ~= "off")
        say("Raptor Strike ready buzz " .. (CouchUIDB.raptorRumble and "on" or "off"))
    elseif cmd == "emotes" then
        if arg == "off" then return removeEmotes() end
        if not ecSocial() then return say("Emote wheel needs Easy Controller (couch mode)") end
        CouchUIDB.emotesOff = nil
        if arg == "rebind" then CouchUIDB.emotesBound = {} end
        setupEmotes(true)
    elseif cmd == "questitem" then
        if arg == "place" then
            CouchUIDB.questItemSlot = CouchUIDB.questItemSlot or {}
            CouchUIDB.questItemSlot[UnitGUID("player") or "?"] = nil
            questItemPlace()
        end
        questItemUpdate(true)
    elseif cmd == "sort" then
        if arg == "off" then CouchUIDB.bagSort = false; say("auto bag sort off (/couch sort now still sorts)")
        elseif arg == "on" then CouchUIDB.bagSort = true; say("auto bag sort on: bags sort themselves when you close them")
        else sortBags(true) end
    elseif cmd == "recruit" then
        if arg == "reset" then
            local r = recruitDB(); r.done = {}; recruitDirty = true
            say("Recruit: forgot who was asked")
        elseif arg == "plates" or arg == "plates on" or arg == "plates off" then
            if InCombatLockdown() then return say("leave combat first") end
            local on = arg ~= "plates off" and not (arg == "plates" and GetCVarBool("nameplateShowFriends"))
            SetCVar("nameplateShowFriends", on and 1 or 0)
            say("friendly nameplates " .. (on and "on (Recruit finds more players)" or "off"))
        else
            placeRecruit(true)
            recruitUpdate()
            recruitStats()
        end
    elseif cmd == "social" then
        if arg == "off" then removeSocial()
        elseif not ecSocial() then say("Social wheel needs Easy Controller (couch mode)")
        else
            CouchUIDB.socialOff = nil
            if arg == "rebind" then CouchUIDB.socialMoved = {} end
            setupSocial(true)
            fixSocial()
        end
    else
        say("profile: " .. name .. " | font " .. p.font .. " | scale " .. tostring(p.scale or "default"))
        say("/couch help = controller map (buttons, wheels, macros, music + voice shortcuts)")
        say("/couch font 18 | /couch scale 0.9 | /couch scale off | /couch layout | /couch arrange [undo] | /couch macros [undo] | /couch binds [undo] | /couch social [off|rebind] | /couch emotes [off|rebind] | /couch recruit [plates|reset] | /couch sort [on|off|now] | /couch questitem [place] | /couch rumble on|off | /couch lights on|off")
    end
end
