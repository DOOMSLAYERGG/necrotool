-- ============================================================================
-- godly.yaw  -  anti-aim builder (standalone gamesense lua)
-- ----------------------------------------------------------------------------
-- A per-state anti-aim builder. Pick a state in the "State" combobox and set its
-- own pitch / yaw base / yaw / style / jitter / desync (body yaw) / freestanding.
-- Each command the active state is detected (Stand / Move / Slow walk / Air /
-- Crouch) and its config is pushed into gamesense's own anti-aim engine, so the
-- result is a real, hard-to-hit AA (jitter + desync + fake pitch + freestanding).
--
-- This does NOT reimplement the cheat's math - it drives the built-in AA
-- references, which is the reliable way to build anti-aims from lua. Every
-- reference is pcall'd so a missing one on a given build just disables that
-- knob instead of breaking the script.
--
-- Load as its OWN script. UI lives under LUA > B. Per-state config persists to
-- the gamesense database.
-- ============================================================================

local DB_KEY = "godly_yaw_cfg"

local STATES = { "Global", "Standing", "Moving", "Slow walk", "Air", "Crouch" }

-- option lists (mapped to gamesense's own AA combobox values via pcall(ui.set))
local PITCH_OPTS = { "Off", "Down", "Up", "Default" }
local BASE_OPTS  = { "Local view", "At targets", "Away from targets" }
local STYLE_OPTS = { "Static", "Jitter", "Spin", "Random" }
local BODY_OPTS  = { "Off", "Static", "Opposite", "Jitter" }

-- default per-state config
local function default_cfg(state)
    return {
        enabled = state ~= "Global",
        pitch   = "Down",
        base    = "At targets",
        yaw_add = (state == "Air" and 0) or 0,
        style   = (state == "Standing" and "Jitter") or "Jitter",
        range   = 45,
        body    = "Jitter",
        body_amt = 60,
        freestand = true,
    }
end

local config = {}
for _, s in ipairs(STATES) do config[s] = default_cfg(s) end

-- ---- persistence (flat keys; nested tables can be dropped by the db) ----
local function persist()
    local flat = {}
    for _, s in ipairs(STATES) do
        local c = config[s]
        flat[s.."|en"]   = c.enabled
        flat[s.."|pi"]   = c.pitch
        flat[s.."|ba"]   = c.base
        flat[s.."|ya"]   = c.yaw_add
        flat[s.."|st"]   = c.style
        flat[s.."|rg"]   = c.range
        flat[s.."|bo"]   = c.body
        flat[s.."|ba2"]  = c.body_amt
        flat[s.."|fs"]   = c.freestand
    end
    pcall(database.write, DB_KEY, flat)
end
local function restore()
    local f = database.read(DB_KEY)
    if type(f) ~= "table" then return end
    for _, s in ipairs(STATES) do
        local c = config[s]
        if f[s.."|en"] ~= nil then c.enabled = f[s.."|en"] end
        if f[s.."|pi"]  then c.pitch    = f[s.."|pi"] end
        if f[s.."|ba"]  then c.base     = f[s.."|ba"] end
        if f[s.."|ya"]  then c.yaw_add  = tonumber(f[s.."|ya"]) or c.yaw_add end
        if f[s.."|st"]  then c.style    = f[s.."|st"] end
        if f[s.."|rg"]  then c.range    = tonumber(f[s.."|rg"]) or c.range end
        if f[s.."|bo"]  then c.body     = f[s.."|bo"] end
        if f[s.."|ba2"] then c.body_amt = tonumber(f[s.."|ba2"]) or c.body_amt end
        if f[s.."|fs"] ~= nil then c.freestand = f[s.."|fs"] end
    end
end
restore()

-- ---- UI ----
local master     = ui.new_checkbox("LUA", "B", "godly.yaw")
local state_sel  = ui.new_combobox("LUA", "B", "\aC8C8C8C8State", STATES)
local w_enabled  = ui.new_checkbox("LUA", "B", "\aC8C8C8C8  Enabled (this state)")
local w_pitch    = ui.new_combobox("LUA", "B", "\aC8C8C8C8  Pitch", PITCH_OPTS)
local w_base     = ui.new_combobox("LUA", "B", "\aC8C8C8C8  Yaw base", BASE_OPTS)
local w_yaw      = ui.new_slider("LUA", "B", "\aC8C8C8C8  Yaw add", -180, 180, 0, true, "\176")
local w_style    = ui.new_combobox("LUA", "B", "\aC8C8C8C8  Style", STYLE_OPTS)
local w_range    = ui.new_slider("LUA", "B", "\aC8C8C8C8  Jitter / spin", 0, 180, 45, true, "\176")
local w_body     = ui.new_combobox("LUA", "B", "\aC8C8C8C8  Desync (body yaw)", BODY_OPTS)
local w_body_amt = ui.new_slider("LUA", "B", "\aC8C8C8C8  Desync amount", 0, 60, 60, true, "\176")
local w_free     = ui.new_checkbox("LUA", "B", "\aC8C8C8C8  Freestanding")
local w_debug    = ui.new_checkbox("LUA", "B", "\aC8C8C8C8Indicator")

ui.set(master, false)

local loading = false
local function load_state()
    loading = true
    local c = config[ui.get(state_sel)]
    ui.set(w_enabled, c.enabled)
    ui.set(w_pitch, c.pitch)
    ui.set(w_base, c.base)
    ui.set(w_yaw, c.yaw_add)
    ui.set(w_style, c.style)
    ui.set(w_range, c.range)
    ui.set(w_body, c.body)
    ui.set(w_body_amt, c.body_amt)
    ui.set(w_free, c.freestand)
    loading = false
end
local function save_state()
    if loading then return end
    local c = config[ui.get(state_sel)]
    c.enabled  = ui.get(w_enabled)
    c.pitch    = ui.get(w_pitch)
    c.base     = ui.get(w_base)
    c.yaw_add  = ui.get(w_yaw)
    c.style    = ui.get(w_style)
    c.range    = ui.get(w_range)
    c.body     = ui.get(w_body)
    c.body_amt = ui.get(w_body_amt)
    c.freestand = ui.get(w_free)
    persist()
end

local function refresh()
    local on = ui.get(master)
    for _, e in ipairs({ state_sel, w_enabled, w_pitch, w_base, w_yaw, w_style, w_range, w_body, w_body_amt, w_free, w_debug }) do
        ui.set_visible(e, on)
    end
end

ui.set_callback(master, refresh)
ui.set_callback(state_sel, load_state)
for _, e in ipairs({ w_enabled, w_pitch, w_base, w_yaw, w_style, w_range, w_body, w_body_amt, w_free }) do
    ui.set_callback(e, save_state)
end
load_state()
refresh()

-- ---- built-in AA references (all guarded) ----
local function ref2(cat, sub, name)
    local ok, a, b = pcall(ui.reference, cat, sub, name)
    if ok then return a, b end
    return nil
end

local aa_enabled            = ref2("AA", "Anti-aimbot angles", "Enabled")
local r_pitch               = ref2("AA", "Anti-aimbot angles", "Pitch")
local r_yaw_base            = ref2("AA", "Anti-aimbot angles", "Yaw base")
local r_yaw_mode, r_yaw_val = ref2("AA", "Anti-aimbot angles", "Yaw")
local r_jit_mode, r_jit_val = ref2("AA", "Anti-aimbot angles", "Yaw jitter")
local r_body_mode, r_body_val = ref2("AA", "Anti-aimbot angles", "Body yaw")
local r_free                = ref2("AA", "Anti-aimbot angles", "Freestanding")

local function s(ref, ...)
    if ref then pcall(ui.set, ref, ...) end
end

-- ---- state detection ----
local function current_state(me)
    local flags = entity.get_prop(me, "m_fFlags") or 0
    local on_ground = bit.band(flags, 1) == 1
    if not on_ground then return "Air" end
    if bit.band(flags, 2) ~= 0 then return "Crouch" end   -- FL_DUCKING

    local vx, vy = entity.get_prop(me, "m_vecVelocity")
    local speed = vx and math.sqrt(vx * vx + vy * vy) or 0
    if speed <= 5 then return "Standing" end
    if speed < 135 then return "Slow walk" end
    return "Moving"
end

local hud = { state = "", style = "" }

local function apply(cfg)
    s(aa_enabled, true)

    -- pitch
    if cfg.pitch ~= "Off" then s(r_pitch, cfg.pitch) end

    -- yaw base + add
    s(r_yaw_base, cfg.base)

    -- style -> gamesense yaw / jitter modes
    if cfg.style == "Spin" then
        s(r_yaw_mode, "Spin")
        s(r_yaw_val, cfg.range)
        s(r_jit_mode, "Off")
    elseif cfg.style == "Jitter" then
        s(r_yaw_mode, "Static")
        s(r_yaw_val, cfg.yaw_add)
        s(r_jit_mode, "Center")
        s(r_jit_val, cfg.range)
    elseif cfg.style == "Random" then
        s(r_yaw_mode, "Static")
        s(r_yaw_val, cfg.yaw_add)
        s(r_jit_mode, "Random")
        s(r_jit_val, cfg.range)
    else -- Static
        s(r_yaw_mode, "Static")
        s(r_yaw_val, cfg.yaw_add)
        s(r_jit_mode, "Off")
    end

    -- desync / body yaw
    if cfg.body == "Off" then
        s(r_body_mode, "Off")
    else
        s(r_body_mode, cfg.body)
        s(r_body_val, cfg.body_amt)
    end

    -- freestanding (r_free may be checkbox[+hotkey]; setting the first works)
    s(r_free, cfg.freestand)

    hud.style = cfg.style
end

local function on_setup_command()
    if not ui.get(master) then return end

    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end

    local state = current_state(me)
    hud.state = state

    -- the state's own config, else fall back to Global
    local cfg = config[state]
    if not cfg.enabled then cfg = config["Global"] end
    if not cfg.enabled then return end

    apply(cfg)
end

local function on_paint_ui()
    if not ui.get(master) or not ui.get(w_debug) then return end
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end
    local sx, sy = client.screen_size()
    renderer.text(sx / 2, sy * 0.58, 235, 210, 120, 255, "c", 0,
        string.format("godly.yaw  [%s / %s]", hud.state, hud.style))
end

client.set_event_callback("setup_command", on_setup_command)
client.set_event_callback("paint_ui", on_paint_ui)
