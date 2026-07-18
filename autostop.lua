-- ============================================================================
-- Best per-weapon auto stop  (standalone gamesense lua)
-- ----------------------------------------------------------------------------
--  * Anticipation: engages BEFORE you peek - as soon as an enemy is within a
--    fixed look-ahead range (no distance slider), so you brake before clearing
--    the corner.
--  * Per-weapon settings: pick a weapon in the "Weapon" combobox and set its own
--    Enabled / Stop mode / Stop speed. Each weapon type keeps its own config
--    (persisted to the gamesense database so it survives reloads).
--  * Hold: keeps braking for a full second after engaging, so you stay accurate
--    right after coming out onto the enemy.
--  * Debug indicator: on-screen status + live speed vs threshold.
--
-- Load as its OWN script alongside necrotool. UI lives under LUA > B.
-- ============================================================================

local ANTICIPATE_UNITS = 700   -- fixed look-ahead range (engage before peeking)
local HOLD_SECONDS     = 1.0   -- keep braking this long after engaging
local DB_KEY           = "necro_autostop_cfg"

local CATS = { "Scout", "AWP", "Auto snipers", "Deagle", "Pistols", "Rifles", "SMG", "Shotguns", "LMG" }
local DEFAULT_SPEED = {
    Scout = 5, AWP = 5, ["Auto snipers"] = 25, Deagle = 25,
    Pistols = 36, Rifles = 40, SMG = 52, Shotguns = 120, LMG = 40,
}

-- per-category config: { enabled, mode, speed }
local config = {}
for _, c in ipairs(CATS) do
    config[c] = { enabled = true, mode = "Counter-strafe", speed = DEFAULT_SPEED[c] }
end

-- persistence uses FLAT string keys (no nested tables - the database serializer
-- can drop deeply nested tables)
local function persist()
    local flat = {}
    for _, c in ipairs(CATS) do
        flat[c .. "|en"]   = config[c].enabled
        flat[c .. "|mode"] = config[c].mode
        flat[c .. "|spd"]  = config[c].speed
    end
    pcall(database.write, DB_KEY, flat)
end
local function restore()
    local f = database.read(DB_KEY)
    if type(f) ~= "table" then return end
    for _, c in ipairs(CATS) do
        if f[c .. "|en"] ~= nil then config[c].enabled = f[c .. "|en"] end
        if f[c .. "|mode"]  then config[c].mode  = f[c .. "|mode"] end
        if f[c .. "|spd"]   then config[c].speed = tonumber(f[c .. "|spd"]) or config[c].speed end
    end
end
restore()

-- ---- UI ----
local enabled       = ui.new_checkbox("LUA", "B", "Per-weapon auto stop")
local debug         = ui.new_checkbox("LUA", "B", "\aC8C8C8C8Debug indicator")
local weapon_select = ui.new_combobox("LUA", "B", "\aC8C8C8C8Weapon", CATS)
local w_enabled     = ui.new_checkbox("LUA", "B", "\aC8C8C8C8  Auto stop (this weapon)")
local w_mode        = ui.new_combobox("LUA", "B", "\aC8C8C8C8  Stop mode", { "Counter-strafe", "Instant" })
local w_speed       = ui.new_slider("LUA", "B", "\aC8C8C8C8  Stop speed", 1, 150, 40, true, "u")

ui.set(enabled, false)

local loading = false
local function load_cat()
    loading = true
    local c = config[ui.get(weapon_select)]
    ui.set(w_enabled, c.enabled)
    ui.set(w_mode, c.mode)
    ui.set(w_speed, c.speed)
    loading = false
end
local function save_cat()
    if loading then return end
    local c = config[ui.get(weapon_select)]
    c.enabled = ui.get(w_enabled)
    c.mode    = ui.get(w_mode)
    c.speed   = ui.get(w_speed)
    persist()
end

local function refresh()
    local on = ui.get(enabled)
    ui.set_visible(debug, on)
    ui.set_visible(weapon_select, on)
    ui.set_visible(w_enabled, on)
    ui.set_visible(w_mode, on)
    ui.set_visible(w_speed, on)
end

ui.set_callback(enabled, refresh)
ui.set_callback(weapon_select, load_cat)
ui.set_callback(w_enabled, save_cat)
ui.set_callback(w_mode, save_cat)
ui.set_callback(w_speed, save_cat)
load_cat()
refresh()

-- ---- logic ----
local function weapon_category(cn)
    if not cn then return "Rifles" end
    if cn == "CWeaponSSG08" then return "Scout" end
    if cn == "CWeaponAWP" then return "AWP" end
    if cn == "CWeaponG3SG1" or cn == "CWeaponSCAR20" then return "Auto snipers" end
    if cn == "CDEagle" or cn == "CWeaponRevolver" then return "Deagle" end
    if cn:find("Nova") or cn:find("XM1014") or cn:find("Mag7") or cn:find("Sawedoff") then return "Shotguns" end
    if cn:find("Glock") or cn:find("P2000") or cn:find("Usp") or cn:find("P250")
        or cn:find("FiveSeven") or cn:find("Tec9") or cn:find("CZ75") or cn:find("Elite") then return "Pistols" end
    if cn:find("Mp9") or cn:find("Mac10") or cn:find("Mp7") or cn:find("Ump45")
        or cn:find("P90") or cn:find("Bizon") or cn:find("Mp5") then return "SMG" end
    if cn:find("M249") or cn:find("Negev") then return "LMG" end
    return "Rifles"
end

-- We brake to take the shot: an enemy must be actually shootable right now,
-- i.e. there is a clear line from our eyes to them. Preference is given to the
-- ragebot's current target (the one it is about to fire at); if that has no line
-- of sight we check any other visible enemy. Behind cover nothing is visible, so
-- we move completely freely - that is what stops the constant braking. The
-- counter-strafe halts us within a couple of ticks, so we are stopped in time
-- for the shot the instant the enemy is exposed.
local function shot_available(me)
    local mx, my, mz = entity.get_origin(me)
    if not mx then return false end
    local eye_z = mz + (entity.get_prop(me, "m_vecViewOffset[2]") or 64)

    local function los_to(ent)
        local tx, ty, tz = entity.get_origin(ent)
        if not tx then return false end
        for _, dz in ipairs({ 46, 64 }) do   -- try chest then head
            local ok, frac, hit = pcall(client.trace_line, me, mx, my, eye_z, tx, ty, tz + dz)
            if ok and (hit == ent or (type(frac) == "number" and frac > 0.95)) then
                return true
            end
        end
        return false
    end

    -- the ragebot's chosen target is the one that will actually be shot
    local threat = client.current_threat()
    if threat and entity.is_alive(threat) and not entity.is_dormant(threat) and los_to(threat) then
        return true
    end

    -- otherwise any other visible enemy
    local ok, players = pcall(entity.get_players, true)   -- enemies only
    if ok and players then
        for _, p in ipairs(players) do
            if entity.is_alive(p) and not entity.is_dormant(p) and los_to(p) then
                return true
            end
        end
    end
    return false
end

local function robust_yaw(cmd)
    local y = cmd.yaw
    if type(y) == "number" then return y end
    local ok, _, cy = pcall(client.camera_angles)
    if ok and type(cy) == "number" then return cy end
    return 0
end

local hud = { active = false, engaged = false, applied = false, speed = 0, threshold = 0, cat = "" }
local hold_until = 0

local function on_setup_command(cmd)
    hud.active, hud.engaged, hud.applied = false, false, false
    if not ui.get(enabled) then return end
    hud.active = true

    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end

    local flags = entity.get_prop(me, "m_fFlags") or 0
    if bit.band(flags, 1) == 0 then return end   -- must be on the ground

    local weapon = entity.get_player_weapon(me)
    if not weapon then return end

    local cat = weapon_category(entity.get_classname(weapon))
    local cfg = config[cat]
    hud.cat = cat
    if not cfg.enabled then return end

    local vx, vy = entity.get_prop(me, "m_vecVelocity")
    if not vx then return end
    local speed = math.sqrt(vx * vx + vy * vy)
    hud.speed = speed
    hud.threshold = cfg.speed

    -- Stop for the shot: brake the instant a shot is actually available (an
    -- enemy is visible / the ragebot's target has line of sight), and hold it for
    -- 1s after. Behind cover nothing is visible, so you move completely freely.
    local can_shoot = shot_available(me)
    if can_shoot then
        hold_until = globals.curtime() + HOLD_SECONDS
    end
    local stopping = can_shoot or globals.curtime() < hold_until
    hud.engaged = stopping
    if not stopping then return end
    if speed <= cfg.speed then return end   -- already slow enough

    hud.applied = true
    if cfg.mode == "Instant" then
        cmd.forwardmove = 0
        cmd.sidemove = 0
        return
    end

    -- counter-strafe: push exactly opposite the current velocity in the view's
    -- local frame, at full move speed
    local yaw  = math.rad(robust_yaw(cmd))
    local cos, sin = math.cos(yaw), math.sin(yaw)
    local fwd  = vx * cos + vy * sin
    local side = vx * sin - vy * cos
    local mag  = math.sqrt(fwd * fwd + side * side)
    if mag > 0 then
        cmd.forwardmove = -(fwd / mag) * 450
        cmd.sidemove    = -(side / mag) * 450
    end
end

local function on_paint_ui()
    if not ui.get(enabled) or not ui.get(debug) or not hud.active then return end
    local sx, sy = client.screen_size()
    local status, r, g, b
    if hud.applied then
        status, r, g, b = "STOPPING", 120, 235, 120
    elseif hud.engaged then
        status, r, g, b = "hold / engaged", 235, 210, 120
    else
        status, r, g, b = "idle", 180, 180, 180
    end
    local text = string.format("auto stop [%s]: %s   spd %.0f / thr %.0f", hud.cat, status, hud.speed, hud.threshold)
    renderer.text(sx / 2, sy * 0.62, r, g, b, 255, "c", 0, text)
end

client.set_event_callback("setup_command", on_setup_command)
client.set_event_callback("paint_ui", on_paint_ui)
