-- ============================================================================
-- godly.yaw  -  anti-aim builder (standalone gamesense lua)
-- ----------------------------------------------------------------------------
-- Per-state anti-aim builder with a necrotool-style navigation menu: a master
-- toggle, a list of states you click into, and each state's own settings with a
-- Back button. Each command the active state is detected (Stand / Move / Slow
-- walk / Air / Crouch) and its config is pushed into gamesense's own anti-aim
-- engine (pitch, yaw base, yaw, jitter, body yaw, freestanding) for a real
-- jitter + desync + fake-pitch + freestanding AA.
--
-- Every reference is pcall-guarded; per-state config persists to the database.
-- Load as its OWN script. UI lives under LUA > B.
-- ============================================================================

local DB_KEY = "godly_yaw_cfg"

local STATES     = { "Standing", "Moving", "Slow walk", "Air", "Crouch" }
local PITCH_OPTS = { "Off", "Down", "Up", "Default" }
local BASE_OPTS  = { "Local view", "At targets", "Away from targets" }
local STYLE_OPTS = { "Static", "Jitter", "Spin", "Random" }
local BODY_OPTS  = { "Off", "Static", "Opposite", "Jitter" }

local function default_cfg()
    return {
        enabled = true, pitch = "Down", base = "At targets", yaw_add = 0,
        style = "Jitter", range = 45, body = "Jitter", body_amt = 60, freestand = true,
    }
end

local config = {}
for _, s in ipairs(STATES) do config[s] = default_cfg() end

-- ---- persistence (flat keys) ----
local function persist()
    local flat = {}
    for _, s in ipairs(STATES) do
        local c = config[s]
        flat[s.."|en"], flat[s.."|pi"], flat[s.."|ba"] = c.enabled, c.pitch, c.base
        flat[s.."|ya"], flat[s.."|st"], flat[s.."|rg"] = c.yaw_add, c.style, c.range
        flat[s.."|bo"], flat[s.."|b2"], flat[s.."|fs"]  = c.body, c.body_amt, c.freestand
    end
    pcall(database.write, DB_KEY, flat)
end
local function restore()
    local f = database.read(DB_KEY)
    if type(f) ~= "table" then return end
    for _, s in ipairs(STATES) do
        local c = config[s]
        if f[s.."|en"] ~= nil then c.enabled = f[s.."|en"] end
        if f[s.."|pi"] then c.pitch = f[s.."|pi"] end
        if f[s.."|ba"] then c.base = f[s.."|ba"] end
        if f[s.."|ya"] then c.yaw_add = tonumber(f[s.."|ya"]) or c.yaw_add end
        if f[s.."|st"] then c.style = f[s.."|st"] end
        if f[s.."|rg"] then c.range = tonumber(f[s.."|rg"]) or c.range end
        if f[s.."|bo"] then c.body = f[s.."|bo"] end
        if f[s.."|b2"] then c.body_amt = tonumber(f[s.."|b2"]) or c.body_amt end
        if f[s.."|fs"] ~= nil then c.freestand = f[s.."|fs"] end
    end
end
restore()

-- ---- menu state ----
local focused = nil            -- which state we are editing (nil = state list)
local loading = false

-- ---- UI (necrotool-style nav) ----
local master   = ui.new_checkbox("LUA", "B", "godly.yaw")
local nav_open = ui.new_checkbox("LUA", "B", "nav open")
ui.set_visible(nav_open, false)
local nav_label = ui.new_label("LUA", "B", "\aB9BEFFFF- \aFFFFFFFFstates \aB9BEFFFF-")

local nav = {}
for _, name in ipairs(STATES) do
    nav[name] = ui.new_button("LUA", "B", "\aB9BEFFFF > \aFFFFFFFF" .. name, function()
        focused = name
        ui.set(nav_open, true)
    end)
end
local nav_back = ui.new_button("LUA", "B", "\aB9BEFFFF < \aFFFFFFFFBack", function()
    focused = nil
    ui.set(nav_open, false)
end)

local w_enabled  = ui.new_checkbox("LUA", "B", "\aFFFFFFFF  Enabled (this state)")
local w_pitch    = ui.new_combobox("LUA", "B", "\aFFFFFFFF  Pitch", PITCH_OPTS)
local w_base     = ui.new_combobox("LUA", "B", "\aFFFFFFFF  Yaw base", BASE_OPTS)
local w_yaw      = ui.new_slider("LUA", "B", "\aFFFFFFFF  Yaw add", -180, 180, 0)
local w_style    = ui.new_combobox("LUA", "B", "\aFFFFFFFF  Style", STYLE_OPTS)
local w_range    = ui.new_slider("LUA", "B", "\aFFFFFFFF  Jitter / spin", 0, 180, 45)
local w_body     = ui.new_combobox("LUA", "B", "\aFFFFFFFF  Desync (body yaw)", BODY_OPTS)
local w_body_amt = ui.new_slider("LUA", "B", "\aFFFFFFFF  Desync amount", 0, 60, 60)
local w_free     = ui.new_checkbox("LUA", "B", "\aFFFFFFFF  Freestanding")
local w_debug    = ui.new_checkbox("LUA", "B", "\aFFFFFFFF  Indicator")

local settings_elems = { w_enabled, w_pitch, w_base, w_yaw, w_style, w_range, w_body, w_body_amt, w_free }

-- push a state's stored config into the shared setting elements
local function load_focused()
    if not focused then return end
    loading = true
    local c = config[focused]
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

-- store the shared setting elements back into the focused state's config
local function save_focused()
    if loading or not focused then return end
    local c = config[focused]
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

local function update_vis()
    local on = ui.get(master)
    local open = ui.get(nav_open)

    ui.set_visible(nav_label, on and not open)
    for _, btn in pairs(nav) do ui.set_visible(btn, on and not open) end
    ui.set_visible(nav_back, on and open)

    local show_settings = on and open and focused ~= nil
    if show_settings then load_focused() end
    for _, e in ipairs(settings_elems) do ui.set_visible(e, show_settings) end
    ui.set_visible(w_debug, on and not open)
end

ui.set_callback(master, update_vis)
ui.set_callback(nav_open, update_vis)
for _, e in ipairs(settings_elems) do ui.set_callback(e, save_focused) end
update_vis()

-- ---- built-in AA references (all guarded) ----
local function ref2(cat, sub, name)
    local ok, a, b = pcall(ui.reference, cat, sub, name)
    if ok then return a, b end
    return nil
end

local aa_enabled              = ref2("AA", "Anti-aimbot angles", "Enabled")
local r_pitch                 = ref2("AA", "Anti-aimbot angles", "Pitch")
local r_yaw_base              = ref2("AA", "Anti-aimbot angles", "Yaw base")
local r_yaw_mode, r_yaw_val   = ref2("AA", "Anti-aimbot angles", "Yaw")
local r_jit_mode, r_jit_val   = ref2("AA", "Anti-aimbot angles", "Yaw jitter")
local r_body_mode, r_body_val = ref2("AA", "Anti-aimbot angles", "Body yaw")
local r_free                  = ref2("AA", "Anti-aimbot angles", "Freestanding")

local function setref(ref, ...)
    if ref then pcall(ui.set, ref, ...) end
end

local function current_state(me)
    local flags = entity.get_prop(me, "m_fFlags") or 0
    if bit.band(flags, 1) == 0 then return "Air" end
    if bit.band(flags, 2) ~= 0 then return "Crouch" end
    local vx, vy = entity.get_prop(me, "m_vecVelocity")
    local speed = vx and math.sqrt(vx * vx + vy * vy) or 0
    if speed <= 5 then return "Standing" end
    if speed < 135 then return "Slow walk" end
    return "Moving"
end

local hud = { state = "", style = "" }

local function apply(cfg)
    setref(aa_enabled, true)
    if cfg.pitch ~= "Off" then setref(r_pitch, cfg.pitch) end
    setref(r_yaw_base, cfg.base)

    if cfg.style == "Spin" then
        setref(r_yaw_mode, "Spin"); setref(r_yaw_val, cfg.range); setref(r_jit_mode, "Off")
    elseif cfg.style == "Jitter" then
        setref(r_yaw_mode, "Static"); setref(r_yaw_val, cfg.yaw_add)
        setref(r_jit_mode, "Center"); setref(r_jit_val, cfg.range)
    elseif cfg.style == "Random" then
        setref(r_yaw_mode, "Static"); setref(r_yaw_val, cfg.yaw_add)
        setref(r_jit_mode, "Random"); setref(r_jit_val, cfg.range)
    else
        setref(r_yaw_mode, "Static"); setref(r_yaw_val, cfg.yaw_add); setref(r_jit_mode, "Off")
    end

    if cfg.body == "Off" then
        setref(r_body_mode, "Off")
    else
        setref(r_body_mode, cfg.body); setref(r_body_val, cfg.body_amt)
    end

    setref(r_free, cfg.freestand)
    hud.style = cfg.style
end

local function on_setup_command()
    if not ui.get(master) then return end
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end
    local state = current_state(me)
    hud.state = state
    local cfg = config[state]
    if cfg and cfg.enabled then apply(cfg) end
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
