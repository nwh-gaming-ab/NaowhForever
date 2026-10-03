local f = assert(io.open(arg[1] or "SwingTimer/NaowhForever_SwingTimer.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()

local function Compile(env)
    if setfenv then
        local chunk = assert(loadstring(source)); setfenv(chunk, env)
        return chunk
    end
    return assert(load(source, "=SwingTimer", "t", env))
end

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

-- Rank 1 of each paladin seal, with the key of its color. Written out here, apart from the module.
local SEALS = {
    { id = 20154, key = "sealRighteousnessColor", name = "Seal of Righteousness" },
    { id = 20375, key = "sealCommandColor", name = "Seal of Command" },
    { id = 21082, key = "sealCrusaderColor", name = "Seal of the Crusader" },
    { id = 20164, key = "sealJusticeColor", name = "Seal of Justice" },
    { id = 20165, key = "sealLightColor", name = "Seal of Light" },
    { id = 20166, key = "sealWisdomColor", name = "Seal of Wisdom" },
    { id = 1311649, key = "sealFuryColor", name = "Seal of Fury" },
    { id = 407798, key = "sealMartyrdomColor", name = "Seal of Martyrdom" },
}
-- Later ranks, as an index into SEALS: they carry their seal's name.
local OTHER_RANKS = {
    [21084] = 1, [20287] = 1, [20293] = 1,
    [20915] = 2, [20920] = 2,
    [20162] = 3, [20308] = 3,
    [20347] = 5, [20349] = 5,
    [20356] = 6, [20357] = 6,
    [1311656] = 7, [20423] = 7,
    [407799] = 8,
}
local SPELL_NAMES = { [20271] = "Judgement", [20467] = "Judgement of Command" }
for _, seal in ipairs(SEALS) do SPELL_NAMES[seal.id] = seal.name end
for id, index in pairs(OTHER_RANKS) do SPELL_NAMES[id] = SEALS[index].name end

-- A widget that accepts any method; the few the module's behaviour hangs on are recorded.
local function Widget(kind, log)
    local w = { kind = kind, shown = true, events = {} }
    -- Widget methods are PascalCase; lower-case keys are the module's own fields.
    setmetatable(w, { __index = function(_, k)
        if k:match("^%u") then return function() end end
    end })
    function w:RegisterEvent(e) self.events[e] = true end
    function w:RegisterUnitEvent(e, ...) self.events[e] = { ... } end
    function w:UnregisterEvent(e) self.events[e] = nil end
    function w:UnregisterAllEvents() self.events = {} end
    function w:SetScript(_, fn) self.onEvent = fn end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetShown(v) self.shown = v and true or false end
    function w:IsShown() return self.shown end
    function w:GetFrameLevel() return 1 end
    function w:SetTimerDuration(obj, _, dir) self.obj, self.dir = obj, dir end
    -- One fill texture per bar, which remembers the color it was last given.
    function w:GetStatusBarTexture() self.fill = self.fill or Widget("Texture", log); return self.fill end
    function w:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function w:CreateTexture() return Widget("Texture", log) end
    function w:CreateFontString() return Widget("FontString", log) end
    log.frames[#log.frames + 1] = w
    return w
end

-- Loads the module against a fresh session and logs in.
local function Session(settings, opts)
    opts = opts or {}
    local log = { frames = {}, bars = {}, now = 100, timers = {}, later = {}, rangeCalls = {}, auraReads = 0 }
    local defaults
    local S = {}
    local UI = {
        ModuleSettings = function(_, d)
            defaults = d
            function S.Get(k) local v = settings[k]; if v == nil then return defaults[k] end; return v end
            function S.Set(k, v) settings[k] = v end
            -- The row makers return the configs the page hands to W:DualRow.
            function S.Toggle(k, text, tooltip, on)
                local cfg = { type = "toggle", key = k, text = text, tooltip = tooltip,
                    getValue = function() return S.Get(k) end, setValue = function(v) S.Set(k, v) end }
                if on then cfg.disabled = function() return not S.Get(on) end end
                return cfg
            end
            function S.Slider(k, text) return { type = "slider", key = k, text = text } end
            function S.Dropdown(k, text) return { type = "dropdown", key = k, text = text } end
            return S
        end,
        AttachMover = function() return Widget("Mover", log) end,
        STATUS = { untested = "   UNTESTED" },
    }
    local ns = { UI = UI, THEME = { bg = { r = 0, g = 0, b = 0 },
        accent = { r = 0.2, g = 0.4, b = 0.6 }, accentSoft = { r = 0.3, g = 0.5, b = 0.7 } } }
    function ns.Apply() end
    function ns.ShowRaidReminderAnchorConfig() end
    log.unlock = function() ns.ShowRaidReminderAnchorConfig() end
    function ns.HideRaidReminderAnchorConfig() end
    log.lock = function() ns.HideRaidReminderAnchorConfig() end
    ns.Solid = function() return Widget("Texture", log) end
    ns.Border = function() return {} end
    ns.PixelInset = function(region) return region end
    ns.Font = function() return Widget("FontString", log) end
    ns.UIFontPath = function() return "font" end
    local speeds = opts.speeds or { 2.6, nil, nil }
    local env = setmetatable({
        _G = { NaowhForever = ns },
        CreateFrame = function(kind, _, parent)
            local w = Widget(kind, log)
            w.parent = parent
            if kind == "StatusBar" then log.bars[#log.bars + 1] = w end
            return w
        end,
        hooksecurefunc = function(t, name, post)
            local orig = t[name]
            t[name] = function(...) orig(...); post(...) end
        end,
        issecretvalue = function(v) return v == SECRET end,
        -- A restricted number still says it is a number; it is using it that raises an error.
        type = function(v) if v == SECRET then return "number" end return type(v) end,
        GetTime = function() return log.now end,
        GetNetStats = function() return 0, 0, 20, 60 end,
        UnitClass = function() return "Class", opts.class or "WARRIOR" end,
        UnitAttackSpeed = function(unit)
            if unit == "target" then
                if opts.targetSpeedFn then return opts.targetSpeedFn() end
                return opts.targetSpeed or 2.0
            end
            return speeds[1], speeds[2], speeds[3]
        end,
        UnitCanAttack = function() return true end,
        UnitIsDead = function() return opts.dead == true end,
        UnitIsUnit = function() return opts.onMe ~= false end,
        UnitAffectingCombat = function() return false end,
        UnitCastingInfo = function() return nil end,
        UnitChannelInfo = function() return nil end,
        IsPlayerMoving = function() return false end,
        RAID_CLASS_COLORS = opts.classColors or {},
        InCombatLockdown = function() return opts.combat == true end,
        C_Secrets = { ShouldAurasBeSecret = function() return opts.secretAuras == true end },
        C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
            assert(unit == "player" and filter == "HELPFUL", "only the player's helpful buffs")
            log.auraReads = log.auraReads + 1
            return opts.auras and opts.auras[i]
        end },
        C_Timer = {
            NewTimer = function(sec, fn)
                local t = { at = log.now + sec, fn = fn }
                function t:Cancel() self.cancelled = true end
                log.timers[#log.timers + 1] = t
                return t
            end,
            After = function(_, fn) log.later[#log.later + 1] = fn end,
        },
        C_StringUtil = { CreateNumericRuleFormatter = function()
            return { AddBreakpoint = function(self, b) self.breakpoint = b end }
        end },
        C_Spell = { GetSpellName = function(id)
            assert(id ~= SECRET, "asked for the name of a restricted spell")
            return SPELL_NAMES[id] or "Spell" .. id
        end, IsCurrentSpell = function(name) return opts.current == name end },
        C_SwingTimer = {
            EnableRangeCheck = function(t, on)
                log.range = log.range or {}; log.range[t] = on
                log.rangeCalls[#log.rangeCalls + 1] = on
            end,
            IsTargetWithinSwingRange = function() return nil end,
        },
        C_DurationUtil = {
            CreateDuration = function()
                local d = {}
                function d:SetTimeFromStart(start, dur) self.start, self.dur = start, dur end
                return d
            end,
            CreateDurationTextBinding = function()
                local b = {}
                setmetatable(b, { __index = function(_, k) if k:match("^%u") then return function() end end end })
                function b:SetEnabled(on) self.enabled = on end
                return b
            end,
        },
        Enum = {
            PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 },
            StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
            StatusBarInterpolation = { Immediate = 0 },
            NumericRuleFormatRounding = { Nearest = 0, Up = 1, Down = 2 },
        },
        UIParent = {},
        pairs = pairs,
    }, { __index = _G })
    Compile(env)()
    -- File scope makes the event frame, then the login frame; Build comes after.
    log.events, log.boot = log.frames[1], log.frames[2]
    -- Builds the Bars page against recording widgets; returns what it laid out.
    function log.BuildPage()
        local page = { headers = {}, rows = {} }
        UI.Widgets = {
            Note = function() return nil, 10 end,
            SectionHeader = function(_, _, text) page.headers[#page.headers + 1] = text; return nil, 10 end,
            Feature = function(_, _, _, cfg) page.rows[#page.rows + 1] = { cfg }; return nil, 10 end,
            DualRow = function(_, _, _, left, right) page.rows[#page.rows + 1] = { left, right }; return nil, 10 end,
        }
        page.y = ns.BuildSwingTimerPage({}, 0)
        return page
    end
    log.boot.onEvent(log.boot, "PLAYER_LOGIN")
    function log.Fire(...) log.events.onEvent(log.events, ...) end
    -- Setting changes apply on the next frame.
    function log.Flush()
        local later = log.later
        log.later = {}
        for i = 1, #later do later[i]() end
    end
    function log.Set(k, v) S.Set(k, v); log.Flush() end
    -- Runs every end-of-swing timer due by `t`.
    function log.Advance(t)
        log.now = t
        for i = 1, #log.timers do
            local tm = log.timers[i]
            if not tm.cancelled and not tm.fired and tm.at <= t then tm.fired = true; tm.fn() end
        end
    end
    function log.Live()
        local n = 0
        for i = 1, #log.timers do
            local tm = log.timers[i]
            if not tm.cancelled and not tm.fired then n = n + 1 end
        end
        return n
    end
    return S, log
end

local count = 0
local function Case(name, fn) fn(); count = count + 1; print("PASS " .. name) end

Case("off by default: nothing registered, nothing built", function()
    local _, log = Session({})
    assert(next(log.events.events) == nil)
    assert(#log.bars == 0)
end)

Case("on: the swing events are registered, the timing aids' are not", function()
    local _, log = Session({ enabled = true })
    local e = log.events.events
    assert(e.PLAYER_SWING and e.PLAYER_SWING_RANGE_UPDATE and e.UNIT_ATTACK_SPEED)
    assert(not e.UNIT_COMBAT and not e.UNIT_SPELLCAST_START and not e.PLAYER_STARTED_MOVING)
    assert(e.ACTIONBAR_UPDATE_STATE, "a warrior has queued attacks to watch")
end)

Case("a main hand swing runs its bar for the swing's duration", function()
    local _, log = Session({ enabled = true })
    log.Fire("PLAYER_SWING", 2.6, 0)
    local mh = log.bars[1]
    assert(mh.obj.start == 100 and mh.obj.dur == 2.6 and log.Live() == 1)
    log.Advance(102.7)
    assert(mh.obj.dur == 2.6, "still in the grace after the predicted end")
    log.Advance(102.9)
    assert(mh.obj.dur == 1 and log.Live() == 0, "parked once the grace runs out")
end)

Case("a mage with a wand and no off-hand weapon gets no Off Hand bar", function()
    local _, log = Session({ enabled = true }, { class = "MAGE", speeds = { 2.2, nil, 1.5 } })
    local b = log.bars
    assert(b[1].parent.shown and not b[2].parent.shown and b[3].parent.shown)
end)

Case("a restricted swing payload is ignored", function()
    local _, log = Session({ enabled = true })
    log.Fire("PLAYER_SWING", SECRET, 0)
    assert(log.bars[1].obj.dur == 1, "still parked on the idle duration")
end)

Case("the target bar never reaches the swing API's range check", function()
    local _, log = Session({ enabled = true, targetSwing = true })
    assert(log.range[0] == true and log.range.target == nil)
end)

Case("range checks are never switched off, so Blizzard's own timer keeps its flag", function()
    local _, log = Session({ enabled = true, showR = false })
    log.Set("rangeCheck", false)
    log.Set("enabled", false)
    for i = 1, #log.rangeCalls do assert(log.rangeCalls[i] == true) end
end)

Case("Unlock Mode parks a running swing so the sample stays put", function()
    local _, log = Session({ enabled = true })
    log.Fire("PLAYER_SWING", 2.6, 0)
    log.unlock()
    assert(log.Live() == 0 and log.bars[1].dir == 0, "full sample, no end timer left")
end)

Case("a restricted target speed keeps the bar and times it from the last readable one", function()
    local speed = 2.0
    local _, log = Session({ enabled = true, targetSwing = true }, { targetSpeedFn = function() return speed end })
    speed = SECRET
    log.Fire("UNIT_ATTACK_SPEED", "player")
    local tgt = log.bars[4]
    assert(tgt.parent.shown, "still shown")
    log.Fire("UNIT_COMBAT", "player", "WOUND", "", 120, 1)
    assert(tgt.obj.dur == 2.0)
end)

Case("target bar: a physical hit taken while targeted restarts it", function()
    local _, log = Session({ enabled = true, targetSwing = true })
    assert(log.events.events.UNIT_COMBAT)
    local tgt = log.bars[4]
    log.Fire("UNIT_COMBAT", "player", "WOUND", "", 120, 4)
    assert(tgt.obj.dur == 1, "a spell hit does not count")
    log.Fire("UNIT_COMBAT", "player", "DODGE", "", 0, 1)
    assert(tgt.obj.start == 100 and tgt.obj.dur == 2.0)
end)

Case("target bar: hits while the target is on someone else do not count", function()
    local _, log = Session({ enabled = true, targetSwing = true }, { onMe = false })
    log.Fire("UNIT_COMBAT", "player", "WOUND", "", 120, 1)
    assert(log.bars[4].obj.dur == 1)
end)

Case("target bar: parry haste takes 40% off, then floors at 20%", function()
    local _, log = Session({ enabled = true, targetSwing = true })
    local tgt = log.bars[4]
    log.Fire("UNIT_COMBAT", "player", "WOUND", "", 120, 1)   -- swing 100 -> 102
    log.now = 100.2
    log.Fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1)     -- 1.8 left -> 1.0
    assert(math.abs(tgt.obj.start + tgt.obj.dur - 101.2) < 1e-9)
    log.now = 100.3
    log.Fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1)     -- 0.9 left -> 0.4
    assert(math.abs(tgt.obj.start + tgt.obj.dur - 100.7) < 1e-9)
end)

Case("turning an aid off drops its events", function()
    local _, log = Session({ enabled = true, castClip = true })
    assert(log.events.events.UNIT_SPELLCAST_START)
    log.Set("castClip", false)
    assert(not log.events.events.UNIT_SPELLCAST_START)
end)

Case("the Auto Shot window registers movement for hunters only", function()
    local _, war = Session({ enabled = true, autoShotWindow = true })
    assert(not war.events.events.PLAYER_STARTED_MOVING)
    local _, hunter = Session({ enabled = true, autoShotWindow = true }, { class = "HUNTER" })
    assert(hunter.events.events.PLAYER_STARTED_MOVING)
end)

Case("turning the module off stops everything", function()
    local _, log = Session({ enabled = true })
    log.Fire("PLAYER_SWING", 2.6, 0)
    log.Set("enabled", false)
    assert(next(log.events.events) == nil and log.Live() == 0)
    assert(log.bars[1].obj.dur == 1, "the running swing is parked")
end)

Case("a weapon swap mid-swing restarts the swing at the new weapon's speed", function()
    local speeds = { 3.8, nil, nil }
    local _, log = Session({ enabled = true }, { speeds = speeds })
    log.Fire("PLAYER_SWING", 3.8, 0)
    log.now = 101
    speeds[1] = 2.6
    log.Fire("WEAPON_SLOT_CHANGED")
    local mh = log.bars[1]
    assert(mh.obj.start == 101 and mh.obj.dur == 2.6)
end)

Case("Hide When Idle hides when a target change stops the only running bar", function()
    local _, log = Session({ enabled = true, targetSwing = true, hideWhenIdle = true,
        visibility = "combat" })
    local container = log.bars[1].parent.parent
    log.Fire("PLAYER_REGEN_DISABLED")
    log.Fire("UNIT_COMBAT", "player", "WOUND", "", 120, 1)
    assert(container.shown)
    log.Fire("PLAYER_TARGET_CHANGED")
    assert(not container.shown)
end)

Case("Show Always keeps idle bars up even with Hide When Idle on", function()
    local _, log = Session({ enabled = true, hideWhenIdle = true, visibility = "always" })
    assert(log.bars[1].parent.parent.shown)
end)

Case("turning the module off during Unlock Mode takes its sample bars away", function()
    local _, log = Session({ enabled = true })
    log.unlock()
    local container = log.bars[1].parent.parent
    assert(container.shown)
    log.Set("enabled", false)
    assert(not container.shown)
end)

Case("a dead target has no Target bar", function()
    local _, log = Session({ enabled = true, targetSwing = true }, { dead = true })
    assert(not log.bars[4].parent.shown)
end)

-------------------------------------------------------------------------------
--  Paladin seals
-------------------------------------------------------------------------------
local function Fill(log, i) return log.bars[i]:GetStatusBarTexture().color end
local function Is(color, want)
    return color ~= nil and math.abs(color[1] - want.r) < 1e-9 and math.abs(color[2] - want.g) < 1e-9
        and math.abs(color[3] - want.b) < 1e-9 and color[4] == (want.a or 1)
end
local function Cast(log, id) log.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", id) end
-- Every seal in its own color, so a mix-up between two shows.
local function SealSettings(extra)
    local settings = { enabled = true, sealColors = true }
    for i, seal in ipairs(SEALS) do settings[seal.key] = { r = i / 10, g = 0.5, b = 0.25 } end
    for k, v in pairs(extra or {}) do settings[k] = v end
    return settings
end

Case("every seal has a default color of its own, and the setting is off", function()
    local S = Session({})
    assert(S.Get("sealColors") == false)
    local seen = {}
    for _, seal in ipairs(SEALS) do
        local c = S.Get(seal.key)
        assert(type(c) == "table" and c.r >= 0 and c.r <= 1 and c.g >= 0 and c.g <= 1 and c.b >= 0 and c.b <= 1, seal.key)
        local signature = ("%.2f/%.2f/%.2f"):format(c.r, c.g, c.b)
        assert(not seen[signature], seal.key .. " repeats a color")
        seen[signature] = true
    end
end)

Case("seal colors are off by default: a paladin watches no casts and reads no buffs", function()
    local S, log = Session({ enabled = true }, { class = "PALADIN", auras = { { spellId = 20154 } } })
    assert(log.events.events.UNIT_SPELLCAST_SUCCEEDED == nil)
    assert(log.auraReads == 0)
    assert(Is(Fill(log, 1), S.Get("mhColor")), "the main hand bar has its own color")
end)

Case("on: a paladin's own casts are watched, nobody else's", function()
    local _, paladin = Session(SealSettings(), { class = "PALADIN" })
    local watched = paladin.events.events.UNIT_SPELLCAST_SUCCEEDED
    assert(type(watched) == "table" and #watched == 1 and watched[1] == "player", "the player's casts")
    assert(not paladin.events.events.UNIT_SPELLCAST_START and not paladin.events.events.UNIT_AURA,
        "no cast clip events and no aura events")
    for _, class in ipairs({ "WARRIOR", "HUNTER", "MAGE" }) do
        local S, other = Session(SealSettings(), { class = class, auras = { { spellId = 20154 } } })
        assert(other.events.events.UNIT_SPELLCAST_SUCCEEDED == nil, class .. ": nothing watched")
        assert(other.auraReads == 0, class .. ": no buffs read")
        Cast(other, 20154)
        assert(Is(Fill(other, 1), S.Get("mhColor")), class .. ": the bar keeps its color")
    end
end)

Case("a seal cast colors the melee bars, whatever its rank, and not the others", function()
    for _, extra in ipairs({ {}, { castClip = true } }) do
        local opts = { class = "PALADIN" }
        local S, log = Session(SealSettings(extra), opts)
        assert(Is(Fill(log, 1), S.Get("mhColor")) and Is(Fill(log, 2), S.Get("ohColor")), "no seal yet: the weapon colors")
        for _, seal in ipairs(SEALS) do
            Cast(log, seal.id)
            local want = S.Get(seal.key)
            assert(Is(Fill(log, 1), want) and Is(Fill(log, 2), want), seal.name .. ": Main Hand and Off Hand")
            assert(Is(Fill(log, 3), S.Get("rColor")), seal.name .. ": Ranged keeps its color")
            assert(Is(Fill(log, 4), S.Get("tgtColor")), seal.name .. ": Target keeps its color")
        end
        -- A change in the settings repaints every bar, which must come out the same.
        opts.auras = { { spellId = 407798 } }
        log.Set("textSize", 12)
        local martyrdom = S.Get("sealMartyrdomColor")
        assert(Is(Fill(log, 1), martyrdom) and Is(Fill(log, 2), martyrdom), "a full repaint keeps the seal on the melee bars")
        assert(Is(Fill(log, 3), S.Get("rColor")) and Is(Fill(log, 4), S.Get("tgtColor")), "and the others their own colors")
        opts.auras = nil
        for id, index in pairs(OTHER_RANKS) do
            log.Fire("PLAYER_DEAD")
            assert(Is(Fill(log, 1), S.Get("mhColor")), "cleared before rank " .. id)
            Cast(log, id)
            assert(Is(Fill(log, 1), S.Get(SEALS[index].key)), SPELL_NAMES[id] .. " (" .. id .. ")")
        end
    end
end)

Case("other spells leave the seal alone, and a restricted spell ID is ignored", function()
    local S, log = Session(SealSettings(), { class = "PALADIN" })
    Cast(log, 20375)
    local painted = Fill(log, 1)
    Cast(log, 20375)
    assert(Fill(log, 1) == painted, "the same seal again repaints nothing")
    for _, id in ipairs({ 20271, 20467, 99999, SECRET }) do
        Cast(log, id)
        assert(Is(Fill(log, 1), S.Get("sealCommandColor")), "still Seal of Command after " .. tostring(id))
        assert(Fill(log, 1) == painted, "and nothing repainted after " .. tostring(id))
    end
end)

Case("a queued attack colors the melee bars and gives them back", function()
    local opts = { class = "WARRIOR" }
    local S, log = Session({ enabled = true }, opts)
    assert(Is(Fill(log, 1), S.Get("mhColor")))
    opts.current = "Spell78"
    log.Fire("ACTIONBAR_UPDATE_STATE")
    assert(Is(Fill(log, 1), S.Get("queueColor")) and Is(Fill(log, 2), S.Get("queueColor")), "Heroic Strike queued")
    assert(Is(Fill(log, 3), S.Get("rColor")), "Ranged is not a melee bar")
    opts.current = "Spell845"
    log.Fire("ACTIONBAR_UPDATE_STATE")
    assert(Is(Fill(log, 1), S.Get("cleaveColor")), "Cleave queued")
    opts.current = nil
    log.Fire("ACTIONBAR_UPDATE_STATE")
    assert(Is(Fill(log, 1), S.Get("mhColor")) and Is(Fill(log, 2), S.Get("ohColor")), "nothing queued")
end)

Case("a seal beats Class Colors and the theme, on the melee bars only", function()
    local pink = { r = 0.96, g = 0.55, b = 0.73 }
    local S, log = Session(SealSettings({ classColored = true }), { class = "PALADIN", classColors = { PALADIN = pink } })
    assert(Is(Fill(log, 1), pink) and Is(Fill(log, 3), pink), "no seal: class colored")
    Cast(log, 20375)
    local want = S.Get("sealCommandColor")
    assert(Is(Fill(log, 1), want) and Is(Fill(log, 2), want), "the seal on the melee bars")
    assert(Is(Fill(log, 3), pink), "Ranged keeps the class color")
    assert(Is(Fill(log, 4), S.Get("tgtColor")), "Target keeps its own")
    log.Fire("PLAYER_DEAD")
    assert(Is(Fill(log, 1), pink), "no seal again: the class color is back")

    local themed, themedLog = Session(SealSettings({ themeColors = true }), { class = "PALADIN" })
    assert(Is(Fill(themedLog, 1), { r = 0.2, g = 0.4, b = 0.6 }) and Is(Fill(themedLog, 2), { r = 0.3, g = 0.5, b = 0.7 }),
        "no seal: the theme's colors")
    Cast(themedLog, 20154)
    local seal = themed.Get("sealRighteousnessColor")
    assert(Is(Fill(themedLog, 1), seal) and Is(Fill(themedLog, 2), seal), "the seal over the theme")
    assert(Is(Fill(themedLog, 3), { r = 0.12, g = 0.24, b = 0.36 }), "Ranged keeps its deeper shade")
end)

Case("in combat a seal swap follows the casts and the buffs are not read", function()
    local opts = { class = "PALADIN", combat = true }
    local S, log = Session(SealSettings(), opts)
    assert(log.auraReads == 0, "logged in during combat: nothing read")
    Cast(log, 20154)
    assert(Is(Fill(log, 1), S.Get("sealRighteousnessColor")))
    Cast(log, 20375)
    assert(Is(Fill(log, 1), S.Get("sealCommandColor")), "the twist shows")
    log.Fire("PLAYER_ENTERING_WORLD")
    assert(log.auraReads == 0 and Is(Fill(log, 1), S.Get("sealCommandColor")), "the last cast stands")
    opts.combat = false
    opts.secretAuras = true
    log.Fire("PLAYER_REGEN_ENABLED")
    assert(log.auraReads == 0 and Is(Fill(log, 1), S.Get("sealCommandColor")), "restricted buffs out of combat: not read either")
end)

Case("out of combat the buffs are read: at login, on entering the world and when combat ends", function()
    local opts = { class = "PALADIN", auras = { { spellId = 1126 }, { spellId = SECRET }, { spellId = 20915 } } }
    local S, log = Session(SealSettings(), opts)
    assert(Is(Fill(log, 1), S.Get("sealCommandColor")), "a seal already up at login, behind a restricted buff")
    assert(log.auraReads == 3, "read down to the seal and no further")
    opts.auras = {}
    log.Fire("PLAYER_REGEN_ENABLED")
    assert(Is(Fill(log, 1), S.Get("mhColor")), "combat ended and the seal is gone: the weapon color")
    opts.auras = { { spellId = 20166 } }
    log.Fire("PLAYER_ENTERING_WORLD")
    assert(Is(Fill(log, 1), S.Get("sealWisdomColor")), "found on entering the world")
    Cast(log, 21082)
    opts.auras = { { spellId = 21082 } }
    log.Fire("PLAYER_REGEN_ENABLED")
    assert(Is(Fill(log, 1), S.Get("sealCrusaderColor")), "a seal that is still up stays")
end)

Case("dying forgets the seal", function()
    local S, log = Session(SealSettings(), { class = "PALADIN" })
    Cast(log, 20154)
    log.Fire("PLAYER_DEAD")
    assert(Is(Fill(log, 1), S.Get("mhColor")))
end)

Case("turning seal colors off drops the watch and the color; on again starts clean", function()
    local S, log = Session(SealSettings(), { class = "PALADIN" })
    Cast(log, 20375)
    log.Set("sealColors", false)
    assert(log.events.events.UNIT_SPELLCAST_SUCCEEDED == nil, "no longer watched")
    assert(Is(Fill(log, 1), S.Get("mhColor")), "the weapon color is back")
    log.Set("sealColors", true)
    assert(log.events.events.UNIT_SPELLCAST_SUCCEEDED, "watched again")
    assert(Is(Fill(log, 1), S.Get("mhColor")), "no seal is known yet")
end)

Case("switching the module off forgets the seal", function()
    local S, log = Session(SealSettings(), { class = "PALADIN", combat = true })
    Cast(log, 20154)
    log.Set("enabled", false)
    log.Set("enabled", true)
    assert(Is(Fill(log, 1), S.Get("mhColor")), "back on in combat: no seal is known")
end)

Case("a seal's color ends when its 30 seconds run out, in combat too", function()
    local S, log = Session(SealSettings(), { class = "PALADIN", combat = true })
    Cast(log, 20154)
    local start = log.now
    assert(log.Live() == 1, "one count running")
    log.Advance(start + 29.9)
    assert(Is(Fill(log, 1), S.Get("sealRighteousnessColor")), "still up at 29.9 seconds")
    log.Advance(start + 30)
    assert(Is(Fill(log, 1), S.Get("mhColor")) and Is(Fill(log, 2), S.Get("ohColor")), "gone at 30 seconds")
    assert(log.Live() == 0, "and nothing is left counting")
    Cast(log, 20375)
    assert(Is(Fill(log, 1), S.Get("sealCommandColor")), "a new seal shows again")
end)

Case("a recast or a twist starts the count again", function()
    local S, log = Session(SealSettings(), { class = "PALADIN", combat = true })
    Cast(log, 20154)
    log.Advance(120)
    Cast(log, 20154)
    log.Advance(131)
    assert(Is(Fill(log, 1), S.Get("sealRighteousnessColor")) and log.Live() == 1, "the first count is gone, the new one runs")
    log.Advance(140)
    Cast(log, 20375)
    log.Advance(155)
    assert(Is(Fill(log, 1), S.Get("sealCommandColor")), "a twist counts its own 30 seconds")
    log.Advance(170)
    assert(Is(Fill(log, 1), S.Get("mhColor")) and log.Live() == 0)
end)

Case("dying, turning the setting off or the module off stops the count", function()
    local _, log = Session(SealSettings(), { class = "PALADIN" })
    Cast(log, 20154)
    assert(log.Live() == 1)
    log.Fire("PLAYER_DEAD")
    assert(log.Live() == 0, "dying")
    Cast(log, 20154)
    log.Set("sealColors", false)
    assert(log.Live() == 0, "Color by Active Seal off")
    log.Set("sealColors", true)
    Cast(log, 20154)
    log.Set("enabled", false)
    assert(log.Live() == 0, "the module off")
end)

Case("a seal buff that can be read gives the real length and what is left", function()
    local opts = { class = "PALADIN", auras = { { spellId = 20915, duration = 34, expirationTime = 120 } } }
    local S, log = Session(SealSettings(), opts)
    assert(Is(Fill(log, 1), S.Get("sealCommandColor")), "up at login")
    log.Advance(119.9)
    assert(Is(Fill(log, 1), S.Get("sealCommandColor")), "20 seconds were left, not 30")
    log.Advance(120)
    assert(Is(Fill(log, 1), S.Get("mhColor")) and log.Live() == 0, "gone when its buff says")
    opts.combat = true
    Cast(log, 20154)
    log.Advance(153.9)
    assert(Is(Fill(log, 1), S.Get("sealRighteousnessColor")), "the next cast lasts the 34 seconds that were read")
    log.Advance(154)
    assert(Is(Fill(log, 1), S.Get("mhColor")))
end)

Case("a scan corrects the count, and a scan without the seal ends it", function()
    local opts = { class = "PALADIN" }
    local S, log = Session(SealSettings(), opts)
    Cast(log, 20154)
    log.Advance(110)
    opts.auras = { { spellId = 20154, duration = 34, expirationTime = 134 } }
    log.Fire("PLAYER_REGEN_ENABLED")
    log.Advance(133.9)
    assert(Is(Fill(log, 1), S.Get("sealRighteousnessColor")) and log.Live() == 1, "the buff said 24 seconds were left")
    log.Advance(134)
    assert(Is(Fill(log, 1), S.Get("mhColor")))
    Cast(log, 20375)
    opts.auras = {}
    log.Fire("PLAYER_REGEN_ENABLED")
    assert(Is(Fill(log, 1), S.Get("mhColor")) and log.Live() == 0, "no seal buff: the color and the count end")
end)

Case("a seal buff already past its end counts nothing", function()
    local S, log = Session(SealSettings(), { class = "PALADIN", auras = { { spellId = 20375, duration = 34, expirationTime = 90 } } })
    assert(Is(Fill(log, 1), S.Get("sealCommandColor")), "still listed, so still shown")
    assert(log.timers[#log.timers].at == log.now, "for no time at all")
    log.Advance(log.now)
    assert(Is(Fill(log, 1), S.Get("mhColor")))
end)

Case("a seal buff with no readable end leaves the count alone", function()
    local opts = { class = "PALADIN" }
    local S, log = Session(SealSettings(), opts)
    Cast(log, 20154)
    for _, aura in ipairs({ { spellId = 20154 }, { spellId = 20154, duration = SECRET, expirationTime = SECRET } }) do
        opts.auras = { aura }
        log.Fire("PLAYER_REGEN_ENABLED")
        assert(Is(Fill(log, 1), S.Get("sealRighteousnessColor")) and log.Live() == 1)
    end
    log.Advance(129.9)
    assert(Is(Fill(log, 1), S.Get("sealRighteousnessColor")), "still counting from the cast")
    log.Advance(130)
    assert(Is(Fill(log, 1), S.Get("mhColor")), "30 seconds, as before")
end)

Case("the Bars page offers the seals to a paladin only", function()
    local function Find(page, text)
        for i, row in ipairs(page.rows) do
            if row[1].text == text then return row[1], i end
        end
    end
    local S, log = Session({ enabled = true }, { class = "PALADIN" })
    local page = log.BuildPage()
    assert(page.headers[#page.headers]:find("^SEALS") and page.headers[#page.headers - 1] == "QUEUED ATTACKS", "after the queued attacks")
    local toggle, at = Find(page, "Color by Active Seal")
    assert(toggle and toggle.type == "toggle" and toggle.key == "sealColors" and toggle.getValue() == false)
    for _, word in ipairs({ "Class Colors", "Apply Theme to Bar Colours", "30 seconds", "in combat too", "out of combat" }) do
        assert(toggle.tooltip:find(word, 1, true), "the tooltip mentions " .. word)
    end
    assert(toggle.disabled() == false, "usable while the module is on")
    local names = {}
    for i = at + 1, #page.rows do
        local row = page.rows[i]
        names[#names + 1] = row[1].text .. "|" .. (row[2] and row[2].text or "")
    end
    assert(#page.rows == at + 4 and table.concat(names, ", ") == "Seal of Righteousness|Seal of Command, "
        .. "Seal of the Crusader|Seal of Justice, Seal of Light|Seal of Wisdom, Seal of Fury|Seal of Martyrdom",
        "four rows of two colors, in this order, and nothing after")
    S.Set("themeColors", true)
    for i, seal in ipairs(SEALS) do
        local row = page.rows[at + math.ceil(i / 2)]
        local picker = row[(i - 1) % 2 + 1]
        assert(picker.type == "colorpicker" and picker.text == seal.name and picker.hasAlpha == nil, seal.name)
        assert(picker.disabled(), seal.name .. ": dimmed while Color by Active Seal is off")
        local r, g, b = picker.getValue()
        local want = S.Get(seal.key)
        assert(r == want.r and g == want.g and b == want.b, seal.name .. " shows its own color")
        picker.setValue(0.11, 0.22, 0.33)
        local saved = S.Get(seal.key)
        assert(saved.r == 0.11 and saved.g == 0.22 and saved.b == 0.33, seal.name .. " is saved under its own key")
    end
    toggle.setValue(true)
    for i = at + 1, #page.rows do
        for _, picker in ipairs(page.rows[i]) do
            assert(not picker.disabled(), picker.text .. ": usable with Color by Active Seal on, whatever the theme switch")
        end
    end
    S.Set("enabled", false)
    assert(page.rows[at + 1][1].disabled() and toggle.disabled(), "and dimmed with the module off")

    local _, warrior = Session({ enabled = true }, { class = "WARRIOR" })
    local other = warrior.BuildPage()
    for _, header in ipairs(other.headers) do assert(not header:find("SEALS", 1, true), "no SEALS header") end
    assert(Find(other, "Color by Active Seal") == nil and Find(other, "Seal of Command") == nil, "no seal rows")
    assert(other.headers[#other.headers] == "QUEUED ATTACKS", "the page ends with the queued attacks")
end)

print(("%d cases passed"):format(count))
