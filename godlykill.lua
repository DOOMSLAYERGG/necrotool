-- ============================================================================
-- godlykill  -  powerful anti-aim builder (standalone gamesense lua)
-- ----------------------------------------------------------------------------
-- Per-state AA builder with a necrotool-style navigation menu. Each command the
-- active state is detected (Stand / Move / Slow walk / Air / Crouch) and its
-- config drives gamesense's anti-aim. The yaw jitter is computed by this script
-- itself (Center / Offset / Random / Spin / 3-way / 5-way), so the pattern is
-- fully custom on top of the cheat's desync + freestanding + fake pitch.
--
-- Extras: manual yaw directions (left / right / back hotkeys) and an on-shot
-- defensive toggle.
--
-- Load THIS file. The whole init is wrapped in pcall and reports the exact
-- failure to the gamesense console (client.error_log). UI under LUA > B; per-
-- state config persists to the database.
-- ============================================================================

local function main()
    local DB_KEY = "godlykill_cfg"

    local STATES     = { "Standing", "Moving", "Slow walk", "Air", "Crouch" }
    local PITCH_OPTS = { "Off", "Down", "Up", "Default", "Minimal" }
    local BASE_OPTS  = { "Local view", "At targets", "Away from targets" }
    local JTYPE_OPTS = { "Off", "Center", "Offset", "Random", "Spin", "3-way", "5-way" }
    local BODY_OPTS  = { "Off", "Static", "Opposite", "Jitter" }

    local function default_cfg(state)
        return {
            enabled = true,
            pitch   = "Down",
            base    = "At targets",
            yaw_add = 0,
            jtype   = (state == "Standing") and "3-way" or "Center",
            range   = 55,
            speed   = 220,     -- spin speed (deg/s)
            body    = "Jitter",
            body_amt = 60,
            free    = true,
            edge    = false,
        }
    end

    local config = {}
    for _, s in ipairs(STATES) do config[s] = default_cfg(s) end

    -- ---- persistence (flat keys, no nested tables) ----
    local F = { "en","pi","ba","ya","jt","rg","sp","bo","b2","fs","ed" }
    local function persist()
        local flat = {}
        for _, s in ipairs(STATES) do
            local c = config[s]
            flat[s.."|en"], flat[s.."|pi"], flat[s.."|ba"] = c.enabled, c.pitch, c.base
            flat[s.."|ya"], flat[s.."|jt"], flat[s.."|rg"] = c.yaw_add, c.jtype, c.range
            flat[s.."|sp"], flat[s.."|bo"], flat[s.."|b2"] = c.speed, c.body, c.body_amt
            flat[s.."|fs"], flat[s.."|ed"] = c.free, c.edge
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
            if f[s.."|jt"] then c.jtype = f[s.."|jt"] end
            if f[s.."|rg"] then c.range = tonumber(f[s.."|rg"]) or c.range end
            if f[s.."|sp"] then c.speed = tonumber(f[s.."|sp"]) or c.speed end
            if f[s.."|bo"] then c.body = f[s.."|bo"] end
            if f[s.."|b2"] then c.body_amt = tonumber(f[s.."|b2"]) or c.body_amt end
            if f[s.."|fs"] ~= nil then c.free = f[s.."|fs"] end
            if f[s.."|ed"] ~= nil then c.edge = f[s.."|ed"] end
        end
    end
    restore()

    local focused, loading, update_vis = nil, false, nil

    -- ---- UI ----
    local master   = ui.new_checkbox("LUA", "B", "godlykill")
    local nav_open = ui.new_checkbox("LUA", "B", "gk nav open")
    ui.set_visible(nav_open, false)
    local nav_label = ui.new_label("LUA", "B", "\aB9BEFFFF- \aFFFFFFFFanti-aim states \aB9BEFFFF-")

    local nav = {}
    for _, name in ipairs(STATES) do
        nav[name] = ui.new_button("LUA", "B", "\aB9BEFFFF > \aFFFFFFFF" .. name, function()
            focused = name; ui.set(nav_open, true); if update_vis then update_vis() end
        end)
    end
    local nav_back = ui.new_button("LUA", "B", "\aB9BEFFFF < \aFFFFFFFFBack", function()
        focused = nil; ui.set(nav_open, false); if update_vis then update_vis() end
    end)

    -- global (shown on the state list)
    local g_left  = ui.new_hotkey("LUA", "B", "\aFFFFFFFF  Manual left")
    local g_right = ui.new_hotkey("LUA", "B", "\aFFFFFFFF  Manual right")
    local g_back  = ui.new_hotkey("LUA", "B", "\aFFFFFFFF  Manual back")
    local g_def   = ui.new_checkbox("LUA", "B", "\aFFFFFFFF  Defensive (on shot)")
    local g_debug = ui.new_checkbox("LUA", "B", "\aFFFFFFFF  Indicator")

    -- per-state settings
    local w_en   = ui.new_checkbox("LUA", "B", "\aFFFFFFFF  Enabled (this state)")
    local w_pi   = ui.new_combobox("LUA", "B", "\aFFFFFFFF  Pitch", PITCH_OPTS)
    local w_ba   = ui.new_combobox("LUA", "B", "\aFFFFFFFF  Yaw base", BASE_OPTS)
    local w_ya   = ui.new_slider("LUA", "B", "\aFFFFFFFF  Yaw add", -180, 180, 0)
    local w_jt   = ui.new_combobox("LUA", "B", "\aFFFFFFFF  Jitter type", JTYPE_OPTS)
    local w_rg   = ui.new_slider("LUA", "B", "\aFFFFFFFF  Jitter range", 0, 180, 55)
    local w_sp   = ui.new_slider("LUA", "B", "\aFFFFFFFF  Spin speed", 20, 600, 220)
    local w_bo   = ui.new_combobox("LUA", "B", "\aFFFFFFFF  Desync (body yaw)", BODY_OPTS)
    local w_b2   = ui.new_slider("LUA", "B", "\aFFFFFFFF  Desync amount", 0, 60, 60)
    local w_fs   = ui.new_checkbox("LUA", "B", "\aFFFFFFFF  Freestanding")
    local w_ed   = ui.new_checkbox("LUA", "B", "\aFFFFFFFF  Edge yaw")

    local set_elems = { w_en, w_pi, w_ba, w_ya, w_jt, w_rg, w_sp, w_bo, w_b2, w_fs, w_ed }
    local glob_elems = { g_left, g_right, g_back, g_def, g_debug }

    local function load_focused()
        if not focused then return end
        loading = true
        local c = config[focused]
        ui.set(w_en, c.enabled); ui.set(w_pi, c.pitch); ui.set(w_ba, c.base); ui.set(w_ya, c.yaw_add)
        ui.set(w_jt, c.jtype); ui.set(w_rg, c.range); ui.set(w_sp, c.speed)
        ui.set(w_bo, c.body); ui.set(w_b2, c.body_amt); ui.set(w_fs, c.free); ui.set(w_ed, c.edge)
        loading = false
    end
    local function save_focused()
        if loading or not focused then return end
        local c = config[focused]
        c.enabled = ui.get(w_en); c.pitch = ui.get(w_pi); c.base = ui.get(w_ba); c.yaw_add = ui.get(w_ya)
        c.jtype = ui.get(w_jt); c.range = ui.get(w_rg); c.speed = ui.get(w_sp)
        c.body = ui.get(w_bo); c.body_amt = ui.get(w_b2); c.free = ui.get(w_fs); c.edge = ui.get(w_ed)
        persist()
    end

    update_vis = function()
        local on = ui.get(master)
        local open = ui.get(nav_open)
        ui.set_visible(nav_label, on and not open)
        for _, b in pairs(nav) do ui.set_visible(b, on and not open) end
        for _, e in ipairs(glob_elems) do ui.set_visible(e, on and not open) end
        ui.set_visible(nav_back, on and open)
        local show = on and open and focused ~= nil
        if show then load_focused() end
        for _, e in ipairs(set_elems) do ui.set_visible(e, show) end
    end

    ui.set_callback(master, update_vis)
    for _, e in ipairs(set_elems) do ui.set_callback(e, save_focused) end
    update_vis()

    -- ---- built-in AA references (guarded) ----
    local function ref2(cat, sub, name)
        local ok, a, b = pcall(ui.reference, cat, sub, name)
        if ok then return a, b end
        return nil
    end
    local r_en                  = ref2("AA", "Anti-aimbot angles", "Enabled")
    local r_pitch               = ref2("AA", "Anti-aimbot angles", "Pitch")
    local r_base                = ref2("AA", "Anti-aimbot angles", "Yaw base")
    local r_yaw, r_yawv         = ref2("AA", "Anti-aimbot angles", "Yaw")
    local r_jit, r_jitv         = ref2("AA", "Anti-aimbot angles", "Yaw jitter")
    local r_body, r_bodyv       = ref2("AA", "Anti-aimbot angles", "Body yaw")
    local r_free                = ref2("AA", "Anti-aimbot angles", "Freestanding")
    local r_edge                = ref2("AA", "Anti-aimbot angles", "Edge yaw")
    local r_onshot              = ref2("AA", "Other", "On shot anti-aim")

    local function setr(ref, ...) if ref then pcall(ui.set, ref, ...) end end
    local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end

    -- custom jitter offset (computed by us each command)
    local function yaw_offset(c)
        local jt, r, tc = c.jtype, c.range, globals.tickcount()
        if jt == "Center" then return (tc % 2 == 0) and 0 or r
        elseif jt == "Offset" then return (tc % 2 == 0) and -r or r
        elseif jt == "Random" then return client.random_float(-r, r)
        elseif jt == "Spin" then return ((globals.curtime() * c.speed) % 360) - 180
        elseif jt == "3-way" then local q = { -r, 0, r }; return q[(tc % 3) + 1]
        elseif jt == "5-way" then local q = { -r, -r/2, 0, r/2, r }; return q[(tc % 5) + 1]
        end
        return 0
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

    local hud = { state = "", jt = "", manual = "" }

    local function apply(c)
        setr(r_en, true)
        if c.pitch ~= "Off" then setr(r_pitch, c.pitch) end
        setr(r_free, c.free)
        setr(r_edge, c.edge)
        setr(r_onshot, ui.get(g_def) and true or false)

        -- manual override wins
        local manual = nil
        if ui.get(g_left)  then manual = -90 end
        if ui.get(g_right) then manual = 90 end
        if ui.get(g_back)  then manual = 180 end
        hud.manual = manual and ((manual == -90 and "L") or (manual == 90 and "R") or "B") or ""

        setr(r_base, c.base)
        if manual then
            setr(r_yaw, "Static"); setr(r_yawv, clamp(manual, -180, 180)); setr(r_jit, "Off")
            setr(r_body, "Static"); setr(r_bodyv, c.body_amt)
            hud.jt = "manual"
            return
        end

        -- our own yaw pattern via Static + computed value
        local off = yaw_offset(c)
        setr(r_yaw, "Static"); setr(r_yawv, clamp(c.yaw_add + off, -180, 180)); setr(r_jit, "Off")

        if c.body == "Off" then setr(r_body, "Off")
        else setr(r_body, c.body); setr(r_bodyv, c.body_amt) end
        hud.jt = c.jtype
    end

    local function on_setup_command()
        if not ui.get(master) then return end
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return end
        local st = current_state(me)
        hud.state = st
        local c = config[st]
        if c and c.enabled then apply(c) end
    end

    local function on_paint_ui()
        if not ui.get(master) or not ui.get(g_debug) then return end
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return end
        local sx, sy = client.screen_size()
        local m = hud.manual ~= "" and (" MANUAL:" .. hud.manual) or ""
        renderer.text(sx / 2, sy * 0.58, 235, 210, 120, 255, "c", 0,
            string.format("godlykill  [%s / %s]%s", hud.state, hud.jt, m))
    end

    client.set_event_callback("setup_command", on_setup_command)
    client.set_event_callback("paint_ui", on_paint_ui)
end

local ok, err = pcall(main)
if not ok then
    pcall(client.error_log, "godlykill failed to load: " .. tostring(err))
end
