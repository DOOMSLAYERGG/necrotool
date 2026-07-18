-- ============================================================================
-- Best per-weapon auto stop  (standalone gamesense lua)
-- ----------------------------------------------------------------------------
-- Stops your movement the moment you are about to shoot, tuned per weapon:
-- snipers / deagle demand a near-full stop, spray weapons are allowed to keep a
-- bit of speed (their moving accuracy is fine). Uses a real counter-strafe so
-- you go accurate within a tick or two instead of coasting on friction.
--
-- Load it as its OWN script alongside necrotool. Its UI lives under LUA > B.
-- ============================================================================

local enabled       = ui.new_checkbox("LUA", "B", "Per-weapon auto stop")
local mode          = ui.new_combobox("LUA", "B", "\aC8C8C8C8Stop mode", { "Counter-strafe", "Instant" })
local require_threat= ui.new_checkbox("LUA", "B", "\aC8C8C8C8Only with a target")
local tighten       = ui.new_slider("LUA", "B", "\aC8C8C8C8Tightness", 50, 150, 100, true, "%")

ui.set(enabled, false)
ui.set(require_threat, true)

local function refresh()
    local on = ui.get(enabled)
    ui.set_visible(mode, on)
    ui.set_visible(require_threat, on)
    ui.set_visible(tighten, on)
end
ui.set_callback(enabled, refresh)
refresh()

-- Speed (units/s) at or below which this weapon class is "accurate enough", so
-- there is no point killing your movement. Above it, we counter-strafe to a
-- stop. The Tightness slider scales these (lower % = stop sooner / harder).
local WEAPON_STOP_SPEED = {
    -- snipers: must be dead stopped
    CWeaponSSG08 = 5,  CWeaponAWP = 5,
    -- auto snipers
    CWeaponG3SG1 = 45, CWeaponSCAR20 = 45,
    -- heavy pistols
    CDEagle = 34, CWeaponRevolver = 34,
}

local function stop_speed_for(classname)
    if not classname then return 90 end
    local direct = WEAPON_STOP_SPEED[classname]
    if direct then return direct end

    -- category matches by substring for everything else
    if classname:find("Nova") or classname:find("XM1014")
        or classname:find("Mag7") or classname:find("Sawedoff") then
        return 170                         -- shotguns: accurate on the move
    end
    if classname:find("Glock") or classname:find("P2000") or classname:find("Usp")
        or classname:find("P250") or classname:find("FiveSeven") or classname:find("Tec9")
        or classname:find("CZ75") or classname:find("Elite") then
        return 70                          -- pistols
    end
    if classname:find("Mp9") or classname:find("Mac10") or classname:find("Mp7")
        or classname:find("Ump45") or classname:find("P90") or classname:find("Bizon")
        or classname:find("Mp5") then
        return 110                         -- smgs
    end
    if classname:find("M249") or classname:find("Negev") then
        return 90                          -- lmgs
    end
    return 90                              -- rifles / default
end

local function on_setup_command(cmd)
    if not ui.get(enabled) then return end

    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end

    -- only on the ground: you cannot brake mid-air
    local flags = entity.get_prop(me, "m_fFlags") or 0
    if bit.band(flags, 1) == 0 then return end

    -- only bother when we are actually about to engage
    if ui.get(require_threat) and not client.current_threat() then return end

    local weapon = entity.get_player_weapon(me)
    if not weapon then return end

    local vx, vy = entity.get_prop(me, "m_vecVelocity")
    if not vx then return end
    local speed = math.sqrt(vx * vx + vy * vy)

    -- per-weapon threshold, scaled by the Tightness slider (100% = as listed)
    local threshold = stop_speed_for(entity.get_classname(weapon)) * (ui.get(tighten) / 100)
    if speed <= threshold then return end   -- already accurate enough

    if ui.get(mode) == "Instant" then
        cmd.forwardmove = 0
        cmd.sidemove = 0
        return
    end

    -- counter-strafe: push exactly opposite to the current velocity, in the
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
