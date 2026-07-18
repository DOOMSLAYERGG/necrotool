-- ============================================================================
-- Best per-weapon auto stop  (standalone gamesense lua)
-- ----------------------------------------------------------------------------
-- Stops your movement when you are about to shoot, tuned per weapon: snipers and
-- the deagle demand a near-full stop, spray weapons keep some speed. Uses a real
-- counter-strafe so you go accurate within a tick.
--
--  * Anticipation: engages BEFORE the enemy becomes a live threat - as soon as
--    any enemy is within "Pre-stop range" of you, so you are already stopped by
--    the time you clear the corner / peek.
--  * Stop speed (units): the base speed you are allowed to keep before the stop
--    kicks in, in real units/s. Per-weapon factors scale it (snipers stop far
--    harder than shotguns).
--
-- Load as its OWN script alongside necrotool. UI lives under LUA > B.
-- ============================================================================

local enabled    = ui.new_checkbox("LUA", "B", "Per-weapon auto stop")
local mode       = ui.new_combobox("LUA", "B", "\aC8C8C8C8Stop mode", { "Counter-strafe", "Instant" })
local stop_speed = ui.new_slider("LUA", "B", "\aC8C8C8C8Stop speed", 1, 150, 40, true, "u")
local pre_range  = ui.new_slider("LUA", "B", "\aC8C8C8C8Pre-stop range", 0, 2500, 650, true, "u", 1, { [0] = "Target only" })

ui.set(enabled, false)

local function refresh()
    local on = ui.get(enabled)
    ui.set_visible(mode, on)
    ui.set_visible(stop_speed, on)
    ui.set_visible(pre_range, on)
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

-- engage as soon as a live threat exists OR (anticipation) an enemy is within the
-- pre-stop range, so we brake before actually peeking out onto them
local function should_engage(me)
    if client.current_threat() then return true end

    local range = ui.get(pre_range)
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
                if (dx * dx + dy * dy + dz * dz) <= r2 then
                    return true
                end
            end
        end
    end
    return false
end

local function on_setup_command(cmd)
    if not ui.get(enabled) then return end

    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end

    -- only on the ground: you cannot brake mid-air
    local flags = entity.get_prop(me, "m_fFlags") or 0
    if bit.band(flags, 1) == 0 then return end

    if not should_engage(me) then return end

    local weapon = entity.get_player_weapon(me)
    if not weapon then return end

    local vx, vy = entity.get_prop(me, "m_vecVelocity")
    if not vx then return end
    local speed = math.sqrt(vx * vx + vy * vy)

    -- threshold in real units/s: slider value scaled per weapon
    local threshold = ui.get(stop_speed) * weapon_factor(entity.get_classname(weapon))
    if speed <= threshold then return end   -- already slow enough

    if ui.get(mode) == "Instant" then
        cmd.forwardmove = 0
        cmd.sidemove = 0
        return
    end

    -- counter-strafe: push exactly opposite the current velocity, in the
    -- command's local (view-relative) frame, at full move speed
    local yaw  = math.rad(cmd.yaw)
    local cos, sin = math.cos(yaw), math.sin(yaw)
    local fwd  = vx * cos + vy * sin
    local side = vx * sin - vy * cos
    local mag  = math.sqrt(fwd * fwd + side * side)
    if mag > 0 then
        cmd.forwardmove = -(fwd / mag) * 450
        cmd.sidemove    = -(side / mag) * 450
    end
end

client.set_event_callback("setup_command", on_setup_command)
