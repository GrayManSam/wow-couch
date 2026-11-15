-- CouchWheels: puts every spell, ability and profession you know on Easy Controller's wheels.
--
-- Wheels (8 slots each, up to 8 wheels, Easy Controller's own limits):
--   "Abilities 1..n"  your class / spec spells, in spellbook order
--   "Professions"     professions and secondary skills (cooking, fishing, first aid...)
--   "Utility"         the General tab (hearthstone-type spells, auto attack, etc.)
-- They refill by themselves when you learn something (out of combat - a game rule).
-- Only wheels made by CouchWheels are touched; wheels you make yourself are left alone.
--
-- Buttons (set once per character; change them freely in /ec map afterwards):
--   R3 (right stick click) ... Abilities 1      R3 + LT ....... Abilities 2
--   R3 + RT ................. Abilities 3      R3 + LT + RT .. Professions
--   Any further wheels go on free L3 + trigger combos, else on Key Bindings > AddOns.
--   R3 normally pings; ping moves off R3. /cw unbind gives R3 back to the game.
--
-- /cw          what is on each wheel and which button opens it
-- /cw fill     refill now        /cw bind     set the buttons again
-- /cw unbind   give the buttons back       /cw off | on   stop / resume auto-fill

local SLOTS, MAX_WHEELS = 8, 8
local BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
local AUTO_ATTACK = 6603
local BUTTONS = { { "R3", "" }, { "R3", "LT" }, { "R3", "RT" }, { "R3", "LTRT" } }
local EXTRA_BUTTONS = { { "L3", "LT" }, { "L3", "RT" }, { "L3", "LTRT" } }
local LAYER_TEXT = { [""] = "", LT = "LT + ", RT = "RT + ", LTRT = "LT + RT + " }

local db
local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff8fd14fCouchWheels|r " .. msg) end

local function EC()
    local ck = _G.ControllerKeyboard
    if ck and ck.db and ck.db.settings and ck.MyWheels and ck.Mapping and ck.ConsumableWheel then
        return ck
    end
end

local function charKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

---------------------------------------------------------------------------
-- The spellbook
---------------------------------------------------------------------------
local function usable(item)
    return item and item.spellID and not item.isPassive and not item.isOffSpec
        and (not SPELL or item.itemType == SPELL)
end

local function collect()
    local SB = C_SpellBook
    if not (SB and SB.GetNumSpellBookSkillLines) then return nil end
    local seen, combat, profs, general = {}, {}, {}, {}
    -- CouchUI's hunter macros stand in for their spell (Hunter's Mark -> MarkMO...)
    local macroFor = _G.CouchUI_MacroForSpell
    local function add(list, item)
        if usable(item) and not seen[item.spellID] then
            seen[item.spellID] = true
            local action = "spell:" .. item.spellID
            if macroFor then
                local ok, name = pcall(macroFor, item.spellID)
                if ok and type(name) == "string" then action = "macro:" .. name end
            end
            if not seen[action] then
                seen[action] = true
                list[#list + 1] = action
            end
        end
    end
    -- Professions first, so they are not counted twice in another tab
    if GetProfessions and GetProfessionInfo then
        for _, idx in ipairs({ GetProfessions() }) do
            if idx then
                local _, _, _, _, numSpells, offset = GetProfessionInfo(idx)
                for i = 1, numSpells or 0 do
                    add(profs, SB.GetSpellBookItemInfo((offset or 0) + i, BANK))
                end
            end
        end
    end
    local lines = SB.GetNumSpellBookSkillLines() or 0
    for line = 1, lines do
        local info = SB.GetSpellBookSkillLineInfo(line)
        if info and not info.shouldHide and info.itemIndexOffset and info.numSpellBookItems then
            local target = (line == 1) and general or combat
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = SB.GetSpellBookItemInfo(i, BANK)
                if item and item.spellID == AUTO_ATTACK then
                    add(general, item)
                else
                    add(target, item)
                end
            end
        end
    end
    return combat, profs, general
end

local function chunks(list, max)
    local out = {}
    for n, action in ipairs(list) do
        if #out >= max and (n - 1) % SLOTS == 0 then break end
        local w = math.floor((n - 1) / SLOTS) + 1
        out[w] = out[w] or {}
        out[w][(n - 1) % SLOTS + 1] = action
    end
    return out
end

-- The wheels wanted: { { name, slots } }, and how many spells did not fit
local function plan()
    local combat, profs, general = collect()
    if not combat then return nil end
    local profWheels = math.min(2, math.ceil(#profs / SLOTS))
    local utilWheels = #general > 0 and 1 or 0
    local combatMax = math.max(1, MAX_WHEELS - profWheels - utilWheels)
    local wanted, dropped = {}, 0
    local c = chunks(combat, combatMax)
    for i, slots in ipairs(c) do wanted[#wanted + 1] = { name = "Abilities " .. i, slots = slots } end
    dropped = dropped + math.max(0, #combat - combatMax * SLOTS)
    local p = chunks(profs, profWheels)
    for i, slots in ipairs(p) do
        wanted[#wanted + 1] = { name = (#p > 1) and ("Professions " .. i) or "Professions", slots = slots }
    end
    dropped = dropped + math.max(0, #profs - profWheels * SLOTS)
    if utilWheels > 0 then
        wanted[#wanted + 1] = { name = "Utility", slots = chunks(general, 1)[1] }
        dropped = dropped + math.max(0, #general - SLOTS)
    end
    return wanted, dropped
end

---------------------------------------------------------------------------
-- Easy Controller's wheels
---------------------------------------------------------------------------
local function ours(w) return w.couchWheels == true end

local function sameSlots(a, b)
    for i = 1, SLOTS do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function fill(verbose)
    local ck = EC()
    if not ck then return end
    if InCombatLockdown() then db.pending = true return end
    db.pending = nil
    local wanted, dropped = plan()
    if not wanted or #wanted == 0 then return end
    local list = ck.MyWheels:List()
    local mine, used = {}, {}
    for _, w in ipairs(list) do
        used[w.id] = true
        if ours(w) then mine[#mine + 1] = w end
    end
    local changed = false
    -- Reuse our wheels in order, make new ones in free ids
    for i, want in ipairs(wanted) do
        local w = mine[i]
        if not w then
            for id = 1, MAX_WHEELS do
                if not used[id] then
                    w = { id = id, slots = {}, couchWheels = true }
                    used[id] = true
                    table.insert(list, w)
                    changed = true
                    break
                end
            end
        end
        if not w then
            dropped = dropped + #want.slots
        else
            want.id = w.id
            if w.name ~= want.name then w.name = want.name; changed = true end
            if not sameSlots(w.slots, want.slots) then
                w.slots = {}
                for s = 1, SLOTS do w.slots[s] = want.slots[s] end
                changed = true
            end
        end
    end
    -- Our wheels no longer needed (spells gone): removed with their buttons
    for i = #wanted + 1, #mine do
        pcall(ck.MyWheels.Delete, ck.MyWheels, mine[i].id)
        changed = true
    end
    if changed then
        pcall(ck.MyWheels.UpdateBindingNames, ck.MyWheels)
        pcall(ck.ConsumableWheel.Fill, ck.ConsumableWheel)
    end
    if changed or verbose then
        local names = {}
        for _, want in ipairs(wanted) do
            if want.id then names[#names + 1] = want.name .. " (" .. #want.slots .. ")" end
        end
        say("wheels ready: " .. table.concat(names, ", ") ..
            (dropped > 0 and (" |cffffaa00- " .. dropped .. " spells didn't fit (8 wheels max)|r") or ""))
    end
    return wanted
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local function isOurWheel(ck, action)
    local id = action and tonumber(action:match("^wheel:(%d+)$"))
    local w = id and ck.MyWheels:Get(id)
    return w and ours(w)
end

local function assign(ck, input, layer, action, replaceGame)
    local M = ck.Mapping
    local inp = M.BY_ID[input]
    if not inp then return false end
    local cur = M:Get(input, layer) or M:GetReplaced(input, layer)
    if cur == action then return true end
    if cur and not isOurWheel(ck, cur) then return false end   -- yours: kept
    local state = M:State(inp, layer)
    if state == "free" then
        M:Set(input, layer, action)
        return true
    elseif replaceGame and state ~= "locked" and M:Replaceable(inp, layer) then
        M:SetReplaced(input, layer, action)
        return true
    end
    return false
end

local function label(input, layer) return LAYER_TEXT[layer] .. input end

local function bind(wanted)
    local ck = EC()
    if not ck or not wanted or InCombatLockdown() then return end
    local slots = {}
    for _, b in ipairs(BUTTONS) do slots[#slots + 1] = { b[1], b[2], true } end
    for _, b in ipairs(EXTRA_BUTTONS) do slots[#slots + 1] = { b[1], b[2], false } end
    -- Professions get the 4th R3 combo; abilities fill the rest in order
    local order = {}
    for _, w in ipairs(wanted) do if w.name:find("^Abilities") and #order < 3 then order[#order + 1] = w end end
    for _, w in ipairs(wanted) do if w.name:find("^Professions") then order[#order + 1] = w break end end
    for _, w in ipairs(wanted) do
        local listed = false
        for _, o in ipairs(order) do if o == w then listed = true end end
        if not listed then order[#order + 1] = w end
    end
    local done, unbound = {}, {}
    local s = 1
    for _, w in ipairs(order) do
        local ok = false
        while w.id and not ok and s <= #slots do
            local input, layer, replace = slots[s][1], slots[s][2], slots[s][3]
            s = s + 1
            local good, res = pcall(assign, ck, input, layer, "wheel:" .. w.id, replace)
            ok = good and res
            if ok then done[#done + 1] = label(input, layer) .. " = " .. w.name end
        end
        if not ok then unbound[#unbound + 1] = w.name end
    end
    db.bound[charKey()] = true
    if #done > 0 then say("buttons: " .. table.concat(done, ", ")) end
    if #unbound > 0 then
        say("no free button for: " .. table.concat(unbound, ", ") ..
            " - pick one in /ec map (Macros list) or Esc > Key Bindings > AddOns")
    end
end

local function unbind()
    local ck = EC()
    if not ck or InCombatLockdown() then return say("leave combat first") end
    local M = ck.Mapping
    for _, b in ipairs(BUTTONS) do
        if isOurWheel(ck, M:Get(b[1], b[2])) then M:Set(b[1], b[2], nil) end
        if isOurWheel(ck, M:GetReplaced(b[1], b[2])) then M:SetReplaced(b[1], b[2], nil) end
    end
    for _, b in ipairs(EXTRA_BUTTONS) do
        if isOurWheel(ck, M:Get(b[1], b[2])) then M:Set(b[1], b[2], nil) end
    end
    db.bound[charKey()] = "off"
    say("buttons given back to the game (wheels kept)")
end

local function run(verbose)
    if not db.enabled then return end
    local wanted = fill(verbose)
    if wanted and not db.bound[charKey()] then bind(wanted) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
local queued = false
local function soon(delay)
    if queued then return end
    queued = true
    C_Timer.After(delay or 2, function()
        queued = false
        local ok, err = pcall(run)
        if not ok then say("error: " .. tostring(err)) end
    end)
end

-- For CouchUI: a macro was made or removed, the wheels follow
function CouchWheels_Refill() if db then soon(1) end end

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(f.RegisterEvent, f, "SKILL_LINES_CHANGED")
pcall(f.RegisterEvent, f, "LEARNED_SPELL_IN_SKILL_LINE")
pcall(f.RegisterEvent, f, "LEARNED_SPELL_IN_TAB")
pcall(f.RegisterEvent, f, "ACTIVE_TALENT_GROUP_CHANGED")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= "CouchWheels" then return end
        CouchWheelsDB = CouchWheelsDB or {}
        db = CouchWheelsDB
        if db.enabled == nil then db.enabled = true end
        db.bound = db.bound or {}
        return
    end
    if not db then return end
    if event == "PLAYER_REGEN_ENABLED" then
        if db.pending then soon(1) end
        return
    end
    -- Easy Controller loads the character's own settings on entering the world: after it
    soon(event == "PLAYER_ENTERING_WORLD" and 5 or 2)
end)

SLASH_COUCHWHEELS1 = "/cw"
SLASH_COUCHWHEELS2 = "/couchwheels"
SlashCmdList.COUCHWHEELS = function(input)
    local cmd = strtrim(input or ""):lower()
    if not EC() then return say("Easy Controller isn't loaded") end
    if cmd == "fill" then
        db.enabled = true
        fill(true)
    elseif cmd == "bind" then
        if InCombatLockdown() then return say("leave combat first") end
        db.bound[charKey()] = nil
        bind(fill(false))
    elseif cmd == "unbind" then
        unbind()
    elseif cmd == "off" then
        db.enabled = false
        say("auto-fill off (wheels kept). /cw on to resume")
    elseif cmd == "on" then
        db.enabled = true
        run(true)
    else
        local ck = EC()
        for _, w in ipairs(ck.MyWheels:List()) do
            if ours(w) then
                local names = {}
                for i = 1, SLOTS do
                    local id = w.slots[i] and tonumber(w.slots[i]:match("^spell:(%d+)$"))
                    local name = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                    name = name or (w.slots[i] and w.slots[i]:match("^macro:(.+)$"))
                    if name then names[#names + 1] = name end
                end
                local input, layer = ck.MyWheels:Bound(w.id)
                say("|cffffd100" .. w.name .. "|r [" .. (input and label(input, layer) or "no button") .. "]: "
                    .. table.concat(names, ", "))
            end
        end
        say("/cw fill | /cw bind | /cw unbind | /cw off | /cw on")
    end
end
