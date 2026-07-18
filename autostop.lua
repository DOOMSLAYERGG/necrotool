-- ============================================================================
-- Best per-weapon auto stop  (standalone gamesense lua)
-- ----------------------------------------------------------------------------
-- Stops your movement when you are about to shoot, tuned per weapon: snipers and
-- the deagle demand a near-full stop, spray weapons keep some speed. Uses a real
-- counter-strafe so you go accurate within a tick.
--
--  * Anticipation: engages BEFORE the enemy becomes a live threat - as soon as
--    any enemy is within "Pre-stop range" of you.
--  * Stop speed (units): the base speed you may keep before it kicks in, in real
--    units/s, scaled per weapon.
--  * Debug indicator: shows on screen whether it is engaging + the live speed vs
--    the threshold, so you can see the sliders actually doing something.
--
-- Load as its OWN script alongside necrotool. UI lives under LUA > B.
-- ============================================================================

local enabled    = ui.new_checkbox("LUA", "B", "Per-weapon auto stop")
local mode       = ui.new_combobox("LUA", "B", "\aC8C8C8C8Stop mode", { "Counter-strafe", "Instant" })
local stop_speed = ui.new_slider("LUA", "B", "\aC8C8C8C8Stop speed", 1, 150, 40, true, "u")
local pre_range  = ui.new_slider("LUA", "B", "\aC8C8C8C8Pre-stop range", 0, 2500, 650, true, "u", 1, { [0] = "Target only" })
local debug      = ui.new_checkbox("LUA", "B", "\aC8C8C8C8Debug indicator")

ui.set(enabled, false)

local function refresh()
    local on = ui.get(enabled)
    ui.set_visible(mode, on)
    ui.set_visible(stop_speed, on)
    ui.set_visible(pre_range, on)
    ui.set_visible(debug, on)
end
ui.set_callback(enabled, refresh)
refresh()

-- per-weapon multiplier applied to the Stop-speed slider. Lower = stops harder.
local function weapon_factor(cn)
    if not cn then return 1.0 end
    if cn == "CWeaponSSG08" or cn == "CWeaponAWP" then return 0.12 end               -- snipers
    if cn == "CWeaponG3SG1" or cn == "CWeaponSCAR20" then return 0.6 end             -- auto snipers
    if cn == "CDEagle" or cn == "CWeaponRevolver" then return 0.6 end                -- heavy pistols
    if cn:find("Nova") or cn:find("XM1014") or cn:find("Mag7") or cn:find("Sawedoff") then
        return 3.0                                                                   -- shotguns
    end
    if cn:find("Glock") or cn:find("P2000") or cn:find("Usp") or cn:find("P250")
        or cn:find("FiveSeven") or cn:find("Tec9") or cn:find("CZ75") or cn:find("Elite") then
        return 0.9                                                                   -- pistols
    end
    if cn:find("Mp9") or cn:find("Mac10") or cn:find("Mp7") or cn:find("Ump45")
        or cn:find("P90") or cn:find("Bizon") or cn:find("Mp5") then
        return 1.3                                                                   -- smgs
    end
    if cn:find("M249") or cn:find("Negev") then return 1.0 end                       -- lmgs
    return 1.0                                                                       -- rifles / default
end

local function enemy_in_range(me, range)
    if range <= 0 then return false end
    local mx, my, mz = entity.get_origin(me)
    if not mx then return false end
    local ok, players = pcall(entity.get_players, true)   -- enemies only
    if not ok or not players then return false end
    local r2 = range * range
    for _, p in ipairs(players) do
        if entity.is_alive(p) then
            local ex, ey, ez = entity.get_origin(p)
            if ex then
                local dx, dy, dz = mx - ex, my - ey, mz - ez
                if (dx * dx + dy * dy + dz * dz) <= r2 then return true end
            end
        end
    end
    return false
end

-- live state for the on-screen indicator
local hud = { active = false, engaged = false, applied = false, speed = 0, threshold = 0 }

local function robust_yaw(cmd)
    local y = cmd.yaw
    if type(y) == "number" then return y end
    local ok, _, cy = pcall(client.camera_angles)
    if ok and type(cy) == "number" then return cy end
    return 0
end

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

    local vx, vy = entity.get_prop(me, "m_vecVelocity")
    if not vx then return end
    local speed = math.sqrt(vx * vx + vy * vy)
    hud.speed = speed
    hud.threshold = ui.get(stop_speed) * weapon_factor(entity.get_classname(weapon))

    -- engage on a live threat, or (anticipation) an enemy within pre-stop range
    local engage = client.current_threat() ~= nil or enemy_in_range(me, ui.get(pre_range))
    hud.engaged = engage
    if not engage then return end
    if speed <= hud.threshold then return end     -- already slow enough

    hud.applied = true
    if ui.get(mode) == "Instant" then
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
        status, r, g, b = "engaged (in range)", 235, 210, 120
    else
        status, r, g, b = "idle (no target)", 180, 180, 180
    end
    local text = string.format("auto stop: %s   spd %.0f / thr %.0f", status, hud.speed, hud.threshold)
    renderer.text(sx / 2, sy * 0.62, r, g, b, 255, "c", 0, text)
end

client.set_event_callback("setup_command", on_setup_command)
client.set_event_callback("paint_ui", on_paint_ui)
