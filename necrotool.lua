local ffi = require 'ffi'
local images = require 'gamesense/images'

local easing = require 'gamesense/easing'

local cvars = {
    mat_ambient_light_r = cvar.mat_ambient_light_r,
    mat_ambient_light_g = cvar.mat_ambient_light_g,
    mat_ambient_light_b = cvar.mat_ambient_light_b,
    r_modelAmbientMin = cvar.r_modelAmbientMin,
    sv_skyname = cvar.sv_skyname,
    r_3dsky = cvar.r_3dsky,
    viewmodel_fov = cvar.viewmodel_fov,
    viewmodel_offset_x = cvar.viewmodel_offset_x,
    viewmodel_offset_y = cvar.viewmodel_offset_y,
    viewmodel_offset_z = cvar.viewmodel_offset_z
}

local state = {
    bloom_default = nil,
    exposure_min_default = nil,
    exposure_max_default = nil,
    bloom_prev = nil,
    exposure_prev = nil,
    model_brightness_prev = nil,
    wall_color_prev = nil,
    default_skyname = nil
}

-- ^^
-- join t.me/femclub0
-- ^^

local dragging_fn = function(name, base_x, base_y)
    local res = 10000
    local screen_x, screen_y = client.screen_size()
    local x_slider = ui.new_slider("LUA", "A", name .. " x position", 0, res, base_x / screen_x * res)
    local y_slider = ui.new_slider("LUA", "A", name .. " y position", 0, res, base_y / screen_y * res)
    ui.set_visible(x_slider, false)
    ui.set_visible(y_slider, false)
    
    local dragging = false
    local offset_x, offset_y = 0, 0
    local last_mouse_x, last_mouse_y = 0, 0
    local prev_mouse_down = false
    
    return {
        get = function()
            local screen_x, screen_y = client.screen_size()
            return ui.get(x_slider) / res * screen_x, ui.get(y_slider) / res * screen_y
        end,
        set = function(x, y)
            local screen_x, screen_y = client.screen_size()
            ui.set(x_slider, x / screen_x * res)
            ui.set(y_slider, y / screen_y * res)
        end,
        drag = function(w, h)
            local x, y = ui.get(x_slider) / res * screen_x, ui.get(y_slider) / res * screen_y
            local mouse_x, mouse_y = ui.mouse_position()
            local is_menu_open = ui.is_menu_open()
            local mouse_down = client.key_state(0x01)
            local just_pressed = mouse_down and not prev_mouse_down
            prev_mouse_down = mouse_down
            
            if is_menu_open then
                -- захватываем драг только в момент нажатия (rising edge), а не пока кнопка
                -- просто зажата — иначе клик, начатый на меню чита, "подхватывается" картинкой,
                -- если курсор потом проходит над её областью
                if just_pressed and mouse_x >= x and mouse_x <= x + w and mouse_y >= y and mouse_y <= y + h then
                    dragging = true
                    offset_x = mouse_x - x
                    offset_y = mouse_y - y
                end
                
                if not mouse_down then
                    dragging = false
                end
                
                if dragging then
                    local new_x = mouse_x - offset_x
                    local new_y = mouse_y - offset_y
                    local screen_x, screen_y = client.screen_size()
                    new_x = math.max(0, math.min(screen_x - w, new_x))
                    new_y = math.max(0, math.min(screen_y - h, new_y))
                    ui.set(x_slider, new_x / screen_x * res)
                    ui.set(y_slider, new_y / screen_y * res)
                    return new_x, new_y
                end
            else
                dragging = false
            end
            
            return x, y
        end
    }
end

local function vmt_entry(instance, index, type)
    return ffi.cast(type, (ffi.cast("void***", instance)[0])[index])
end

local function vmt_bind(module, interface, index, typestring)
    local instance = client.create_interface(module, interface) or error("invalid interface")
    local success, typeof = pcall(ffi.typeof, typestring)
    if not success then
        error(typeof, 2)
    end
    local fnptr = vmt_entry(instance, index, typeof) or error("invalid vtable")
    return function(...)
        return fnptr(instance, ...)
    end
end

local function bind_signature(module, interface, signature, typestring)
    local interface_ptr = client.create_interface(module, interface) or error("invalid interface", 2)
    local instance = client.find_signature(module, signature) or error("invalid signature", 2)
    local success, typeof = pcall(ffi.typeof, typestring)
    if not success then
        error(typeof, 2)
    end
    local fnptr = ffi.cast(typeof, instance) or error("invalid typecast", 2)
    return function(...)
        return fnptr(interface_ptr, ...)
    end
end

local native = {
    Surface_PlaySound = vmt_bind("vguimatsurface.dll", "VGUI_Surface031", 82, "void(__thiscall*)(void*, const char*)"),
    char_buffer = ffi.typeof("char[?]"),
    int_ptr = ffi.typeof("int[1]"),
    current_directory = bind_signature("filesystem_stdio.dll", "VFileSystem017", "\x55\x8B\xEC\x56\x8B\x75\x08\x56\xFF\x75\x0C", "bool(__thiscall*)(void*, char*, int)"),
    add_to_searchpath = bind_signature("filesystem_stdio.dll", "VFileSystem017", "\x55\x8B\xEC\x81\xEC\xCC\xCC\xCC\xCC\x8B\x55\x08\x53\x56\x57", "void(__thiscall*)(void*, const char*, const char*, int)"),
    find_first = bind_signature("filesystem_stdio.dll", "VFileSystem017", "\x55\x8B\xEC\x6A\x00\xFF\x75\x10\xFF\x75\x0C\xFF\x75\x08\xE8\xCC\xCC\xCC\xCC\x5D", "const char*(__thiscall*)(void*, const char*, const char*, int*)"),
    find_next = bind_signature("filesystem_stdio.dll", "VFileSystem017", "\x55\x8B\xEC\x83\xEC\x0C\x53\x8B\xD9\x8B\x0D\xCC\xCC\xCC\xCC", "const char*(__thiscall*)(void*, int)"),
    find_close = bind_signature("filesystem_stdio.dll", "VFileSystem017", "\x55\x8B\xEC\x53\x8B\x5D\x08\x85", "void(__thiscall*)(void*, int)"),
    find_is_directory = bind_signature("filesystem_stdio.dll", "VFileSystem017", "\x55\x8B\xEC\x0F\xB7\x45\x08", "bool(__thiscall*)(void*, int)")
}
local char_buffer, int_ptr = native.char_buffer, native.int_ptr
local current_directory, add_to_searchpath = native.current_directory, native.add_to_searchpath
local find_first, find_next, find_close, find_is_directory = native.find_first, native.find_next, native.find_close, native.find_is_directory
local native_Surface_PlaySound = native.Surface_PlaySound

local load_name_sky
do
    local load_name_sky_address = client.find_signature("engine.dll", "\x55\x8B\xEC\x81\xEC\xCC\xCC\xCC\xCC\x56\x57\x8B\xF9\xC7\x45") or error("signature for load_name_sky is outdated")
    load_name_sky = ffi.cast(ffi.typeof("void(__fastcall*)(const char*)"), load_name_sky_address)
end

local console_color = {
    engine_client = ffi.cast(ffi.typeof('void***'), client.create_interface('engine.dll', 'VEngineClient014')),
    mats = {}
}
console_color.is_visible = ffi.cast(ffi.typeof('bool(__thiscall*)(void*)'), console_color.engine_client[0][11])


do
    local material_names = { 'vgui_white', 'vgui/hud/800corner1', 'vgui/hud/800corner2', 'vgui/hud/800corner3', 'vgui/hud/800corner4' }
    for _, name in ipairs(material_names) do
        console_color.mats[#console_color.mats + 1] = materialsystem.find_material(name)
    end
end

local function collect_death_sounds()
    local files = {}
    local file_handle = int_ptr()
    local file = find_first("*", "UWUHOOK", file_handle)
    while file ~= nil do
        local file_name = ffi.string(file)
        if find_is_directory(file_handle[0]) == false and (file_name:find(".mp3") or file_name:find(".wav")) then
            local display_name = file_name:gsub("_", " "):gsub(".mp3", ""):gsub(".wav", "")
            files[#files+1] = {name = display_name, file = "uwuhook/" .. file_name}
        end
        file = find_next(file_handle[0])
    end
    find_close(file_handle[0])
    return files
end

local function collect_kill_images()
    local files = {}
    local file_handle = int_ptr()
    local file = find_first("*", "UWUKILL", file_handle)
    while file ~= nil do
        local file_name = ffi.string(file)
        if find_is_directory(file_handle[0]) == false and file_name:find(".png") then
            local display_name = file_name:gsub("_", " "):gsub(".png", "")
            files[#files+1] = {name = display_name, file = file_name}
        end
        file = find_next(file_handle[0])
    end
    find_close(file_handle[0])
    return files
end

local skybox_list = {
    ["Tibet"] = "cs_tibet",
    ["Baggage"] = "cs_baggage_skybox_",
    ["Monastery"] = "embassy",
    ["Italy"] = "italy",
    ["Aztec"] = "jungle",
    ["Vertigo"] = "office",
    ["Daylight"] = "sky_cs15_daylight01_hdr",
    ["Daylight (2)"] = "vertigoblue_hdr",
    ["Clouds"] = "sky_cs15_daylight02_hdr",
    ["Clouds (2)"] = "vertigo",
    ["Gray"] = "sky_day02_05_hdr",
    ["Clear"] = "nukeblank",
    ["Canals"] = "sky_venice",
    ["Cobblestone"] = "sky_cs15_daylight03_hdr",
    ["Assault"] = "sky_cs15_daylight04_hdr",
    ["Clouds (Dark)"] = "sky_csgo_cloudy01",
    ["Night"] = "sky_csgo_night02",
    ["Night (2)"] = "sky_csgo_night02b",
    ["Night (Flat)"] = "sky_csgo_night_flat",
    ["Dusty"] = "sky_dust",
    ["Rainy"] = "vietnam",
}

local function collect_custom_skyboxes()
    local files = {}
    local file_handle = int_ptr()
    local file = find_first("*", "XGAME", file_handle)
    while file ~= nil do
        local file_name = ffi.string(file)
        if find_is_directory(file_handle[0]) == false and (file_name:find("dn.vtf")) then
            files[#files+1] = file_name:sub(1, -7)
        end
        file = find_next(file_handle[0])
    end
    find_close(file_handle[0])
    return files
end

local function normalize_skybox_name(name)
    local first_letter = name:sub(1, 1)
    local rest = name:sub(2)
    name = "Custom: ".. first_letter:upper() .. rest
    if name:find("_") then
        name = name:gsub("_", " ")
    end
    if name:find(".vtf") then
        name = name:gsub(".vtf", "")
    end
    return name
end

local function collect_skyboxes()
    local skybox_path = char_buffer(192)
    current_directory(skybox_path, ffi.sizeof(skybox_path))
    skybox_path = string.format("%s\\csgo\\materials\\skybox", ffi.string(skybox_path))
    add_to_searchpath(skybox_path, "XGAME", 0)
    
    local custom_skyboxes = collect_custom_skyboxes()
    
    for i = 1, #custom_skyboxes do
        local file_name = custom_skyboxes[i]
        local normalized_name = normalize_skybox_name(file_name)
        if not skybox_list[normalized_name] then
            skybox_list[normalized_name] = file_name
        end
    end
    
    local skybox_names = {}
    for k, v in pairs(skybox_list) do
        skybox_names[#skybox_names+1] = k
    end
    table.sort(skybox_names)
    return skybox_names
end

local skybox_names = collect_skyboxes()

local current_path = char_buffer(128)
current_directory(current_path, ffi.sizeof(current_path))
current_path = string.format("%s\\csgo\\sound\\uwuhook", ffi.string(current_path))
add_to_searchpath(current_path, "UWUHOOK", 0)

local current_path2 = char_buffer(128)
current_directory(current_path2, ffi.sizeof(current_path2))
current_path2 = string.format("%s\\csgo\\materials\\panorama\\images\\icons\\equipment\\uwukill", ffi.string(current_path2))
add_to_searchpath(current_path2, "UWUKILL", 0)

local media = {
    death_sounds = collect_death_sounds(),
    death_sound_names = {},
    death_sound_files = {},
    kill_images = collect_kill_images(),
    kill_image_names = {"Random"},
    kill_image_files = {}
}

for i = 1, #media.death_sounds do
    media.death_sound_names[i] = media.death_sounds[i].name
    media.death_sound_files[media.death_sounds[i].name] = media.death_sounds[i].file
end

if #media.death_sound_names == 0 then
    media.death_sound_names[1] = "No sounds found"
    media.death_sound_files["No sounds found"] = nil
end

for i = 1, #media.kill_images do
    media.kill_image_names[i + 1] = media.kill_images[i].name
    media.kill_image_files[media.kill_images[i].name] = media.kill_images[i].file
end

if #media.kill_images == 0 then
    media.kill_image_names[2] = "No images found"
end

local UI = {}
UI.enabled = ui.new_checkbox("LUA", "A", "\aFFFFFFFF necrotool")
UI.tab = ui.new_combobox("LUA", "A", "\aFFFFFFFF  Tab", {"Visuals", "World", "Changer", "Misc", "Autobuy", "Trashtalk", "Config"})

-- ===== Menu navigation buttons (Infinix-style) =====
-- One button per tab: clicking it jumps straight to that tab's settings by
-- setting the Tab combobox and refreshing visibility. Stored on the UI table
-- and built in a do-block so no new chunk-level locals are added.
UI.nav_label = ui.new_label("LUA", "A", "\aFFFFFFFF  \aB9BEFFFF― \aFFFFFFFFmenu \aB9BEFFFF―")
-- internal drill-down state: false = show the nav menu, true = show a section
UI.nav_open = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  nav open")
ui.set_visible(UI.nav_open, false)
UI.nav = {}
do
    local nav_tabs = {"Visuals", "World", "Changer", "Misc", "Autobuy", "Trashtalk", "Config"}
    for _, name in ipairs(nav_tabs) do
        UI.nav[name] = ui.new_button("LUA", "A", "\aB9BEFFFF » \aFFFFFFFF" .. name, function()
            ui.set(UI.tab, name)
            ui.set(UI.nav_open, true)          -- expand into the section
            if UI._update_visibility then UI._update_visibility() end
        end)
    end
end
UI.nav_back = ui.new_button("LUA", "A", "\aB9BEFFFF « \aFFFFFFFFBack", function()
    ui.set(UI.nav_open, false)                 -- collapse back to the menu
    if UI._update_visibility then UI._update_visibility() end
end)

UI.notifications = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Notifications")
UI.notify_types = ui.new_multiselect("LUA", "A", "\aFFFFFFFF    Types", {
    "Hit", "Miss", "Hurt", "Death"
})
UI.notify_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style", {
    "New", "New black", "Old"
})
UI.notify_size = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Size", {
    "Small", "Medium", "Big"
})
UI.notify_limit = ui.new_slider("LUA", "A", "\aFFFFFFFF    Max Notifications", 1, 20, 5)
UI.notify_duration = ui.new_slider("LUA", "A", "\aFFFFFFFF    Duration", 1, 10, 4, true, "s")
UI.kill_image = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  render image")
UI.kill_image_select = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Image", media.kill_image_names)
UI.kill_image_alpha = ui.new_slider("LUA", "A", "\aFFFFFFFF    Transparency", 0, 255, 200)
UI.kill_image_duration = ui.new_slider("LUA", "A", "\aFFFFFFFF    Duration\nkill_image", 0, 1000, 30, true, "s", 0.1, {[0] = "Inf"})
UI.kill_image_no_repeat = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    Don't repeat images")
UI.kill_image_size = ui.new_slider("LUA", "A", "\aFFFFFFFF    Size", 20, 1500, 400)

UI.hit_effect = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Hit effect")
UI.hit_effect_color = ui.new_color_picker("LUA", "A", "\aFFFFFFFF  Hit effect", 255, 255, 255, 255)
UI.hit_effect_color2 = ui.new_color_picker("LUA", "A", "\aFFFFFFFF    Style\nhit_effect", 255, 255, 255, 255)
UI.hit_effect_color3 = ui.new_color_picker("LUA", "A", "\aFFFFFFFF    Style 3\nhit_effect", 255, 255, 255, 255)
UI.hit_effect_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\nhit_effect", {"Solid", "2-color", "3-color", "Rainbow", "Confetti"})
UI.hit_effect_particle = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Particle\nhit_effect", {"Circle", "Snowflake", "Shard", "Glyph"})
UI.hit_effect_size = ui.new_slider("LUA", "A", "\aFFFFFFFF    Size\nhit_effect", 1, 100, 30, true, "", 0.1)
UI.hit_effect_amount = ui.new_slider("LUA", "A", "\aFFFFFFFF    Amount\nhit_effect", 1, 100, 12)
UI.hit_effect_duration = ui.new_slider("LUA", "A", "\aFFFFFFFF    Duration\nhit_effect", 1, 50, 8, true, "s", 0.1)
UI.hit_effect_radius = ui.new_slider("LUA", "A", "\aFFFFFFFF    Radius\nhit_effect", 1, 100, 50)
UI.hit_effect_glow = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    Glow\nhit_effect")
UI.hit_effect_glow_thick = ui.new_slider("LUA", "A", "\aFFFFFFFF    Glow thickness\nhit_effect", 1, 100, 40, true, "", 0.1)
UI.hit_effect_anim = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Animation\nhit_effect", {"None", "Pulse"})

UI.healthbar = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Custom healthbar")
UI.healthbar_color_full = ui.new_color_picker("LUA", "A", "\aFFFFFFFF  Custom healthbar", 142, 214, 77, 255)
UI.healthbar_color_empty = ui.new_color_picker("LUA", "A", "\aFFFFFFFF    Empty health\nhealthbar", 244, 48, 87, 255)
UI.healthbar_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\nhealthbar", {"Solid", "Gradient", "Rainbow"})

UI.scope = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Scope lines")
UI.scope_color = ui.new_color_picker("LUA", "A", "\aFFFFFFFF  Scope lines", 255, 255, 255, 255)
UI.scope_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\nscope", {"Classic", "Dotted", "Dual color", "Rainbow"})
UI.scope_color2 = ui.new_color_picker("LUA", "A", "\aFFFFFFFF    Style\nscope", 255, 255, 255, 255)
UI.scope_thickness = ui.new_slider("LUA", "A", "\aFFFFFFFF    Thickness\nscope", 1, 5, 1)
UI.scope_length = ui.new_slider("LUA", "A", "\aFFFFFFFF    Length\nscope", 10, 500, 190)
UI.scope_gap = ui.new_slider("LUA", "A", "\aFFFFFFFF    Gap\nscope", 0, 500, 15)
UI.scope_fade = ui.new_slider("LUA", "A", "\aFFFFFFFF    Fade speed\nscope", 3, 20, 12)
UI.scope_glow = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    Glow\nscope")
UI.scope_remove_lines = ui.new_multiselect("LUA", "A", "\aFFFFFFFF    Remove lines", {"Up", "Down", "Left", "Right"})

UI.tracers = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Bullet tracers")
UI.tracers_color = ui.new_color_picker("LUA", "A", "\aFFFFFFFF  Bullet tracers", 255, 255, 255, 255)
UI.tracers_color2 = ui.new_color_picker("LUA", "A", "\aFFFFFFFF    Style\ntracers", 255, 255, 255, 255)
UI.tracers_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\ntracers", {"Solid", "Gradient", "Rainbow"})
UI.tracers_duration = ui.new_slider("LUA", "A", "\aFFFFFFFF    Duration\ntracers", 1, 10, 3, true, "s")
UI.tracers_thickness = ui.new_slider("LUA", "A", "\aFFFFFFFF    Thickness\ntracers", 1, 10, 1)
UI.tracers_glow = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    Glow\ntracers")
UI.tracers_glow_intensity = ui.new_slider("LUA", "A", "\aFFFFFFFF    Glow intensity", 1, 5, 2)
UI.tracers_anim = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Animation\ntracers", {"None", "Shrink", "Pulse", "Fade out"})
UI.tracers_limit = ui.new_slider("LUA", "A", "\aFFFFFFFF    Max tracers", 1, 30, 10)

UI.trails = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Movement trails")
UI.trails_color = ui.new_color_picker("LUA", "A", "\aFFFFFFFF  Movement trails", 255, 255, 255, 255)
UI.trails_color2 = ui.new_color_picker("LUA", "A", "\aFFFFFFFF    Style\ntrails", 255, 255, 255, 255)
UI.trails_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\ntrails", {"Solid", "Gradient", "Rainbow"})
UI.trails_duration = ui.new_slider("LUA", "A", "\aFFFFFFFF    Duration\ntrails", 1, 50, 30, true, "s", 0.1)
UI.trails_thickness = ui.new_slider("LUA", "A", "\aFFFFFFFF    Thickness\ntrails", 1, 50, 20, true, "", 0.1)
UI.trails_glow = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    Glow\ntrails")
UI.trails_glow_thickness = ui.new_slider("LUA", "A", "\aFFFFFFFF    Glow thickness\ntrails", 1, 100, 30, true, "", 0.1)
UI.trails_anim = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Animation\ntrails", {"None", "Fade out", "Wave"})

UI.grenade_trail = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Grenade trail")
UI.grenade_trail_color = ui.new_color_picker("LUA", "A", "\aFFFFFFFF  Grenade trail", 255, 255, 255, 255)
UI.grenade_trail_color2 = ui.new_color_picker("LUA", "A", "\aFFFFFFFF    Style\ngrenade_trail", 255, 255, 255, 255)
UI.grenade_trail_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\ngrenade_trail", {"Solid", "Gradient", "Rainbow"})
UI.grenade_trail_thickness = ui.new_slider("LUA", "A", "\aFFFFFFFF    Thickness\ngrenade_trail", 1, 10, 2)
UI.grenade_trail_duration = ui.new_slider("LUA", "A", "\aFFFFFFFF    Duration\ngrenade_trail", 1, 100, 30, true, "s", 0.1)
UI.grenade_trail_glow = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    Glow\ngrenade_trail")
UI.grenade_trail_glow_intensity = ui.new_slider("LUA", "A", "\aFFFFFFFF    Glow intensity\ngrenade_trail", 1, 5, 2)

UI.fog = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Fog")
UI.fog_color = ui.new_color_picker("LUA", "A", "\aFFFFFFFF  Fog", 255, 255, 255, 255)
UI.fog_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\nfog", {"Custom", "Rainbow"})
UI.fog_start = ui.new_slider("LUA", "A", "\aFFFFFFFF    Fog start", 0, 5000, 100)
UI.fog_end = ui.new_slider("LUA", "A", "\aFFFFFFFF    Fog end", 0, 10000, 1000)
UI.fog_density = ui.new_slider("LUA", "A", "\aFFFFFFFF    Fog density", 0, 100, 50)
UI.fog_rainbow_speed = ui.new_slider("LUA", "A", "\aFFFFFFFF    Rainbow speed\nfog", 1, 10, 3)
UI.wall_color = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Wall color")
UI.wall_color_picker = ui.new_color_picker("LUA", "A", "\aFFFFFFFF  Wall color", 255, 255, 255, 255)
UI.wall_color_picker2 = ui.new_color_picker("LUA", "A", "\aFFFFFFFF    Style\nwall_color", 255, 255, 255, 255)
UI.wall_color_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\nwall_color", {"Solid", "Gradient", "Rainbow", "Pulse"})
UI.bloom = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Bloom")
UI.bloom_scale = ui.new_slider("LUA", "A", "\aFFFFFFFF    Bloom scale", 1, 500, 100, true, "", 0.01)
UI.exposure = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Auto exposure")
UI.exposure_value = ui.new_slider("LUA", "A", "\aFFFFFFFF    Exposure value", 1, 2000, 689, true, "", 0.001)
UI.model_brightness = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Model brightness")
UI.model_brightness_value = ui.new_slider("LUA", "A", "\aFFFFFFFF    Brightness value", 0, 1000, 175, true, "", 0.05)
UI.smooth_animation = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Smooth local animation")
UI.smooth_camera = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Smooth camera movement")
UI.smooth_camera_pitch_speed = ui.new_slider("LUA", "A", "\aFFFFFFFF    Pitch speed", 1, 100, 15, true, "%", 0.1)
UI.smooth_camera_yaw_speed = ui.new_slider("LUA", "A", "\aFFFFFFFF    Yaw speed", 1, 100, 20, true, "%", 0.1)
UI.smooth_camera_extrapolation = ui.new_slider("LUA", "A", "\aFFFFFFFF    Extrapolation", 0, 150, 50, true, "ms", 1, {[0] = "Off"})
UI.smooth_camera_velocity_filter = ui.new_slider("LUA", "A", "\aFFFFFFFF    Velocity filtering", 0, 100, 30, true, "%", 0.1)
UI.smooth_camera_prediction_clamp = ui.new_slider("LUA", "A", "\aFFFFFFFF    Prediction clamp", 1, 90, 45, true, "°", 1)
UI.smooth_camera_easing = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Easing", {"Linear", "Exponential", "Smoothstep", "Sigmoid"})
UI.smooth_camera_dynamic_fov = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    Dynamic FOV")
UI.smooth_camera_fov_intensity = ui.new_slider("LUA", "A", "\aFFFFFFFF    FOV intensity", 0, 30, 10, true, "°", 1)
UI.smooth_camera_roll = ui.new_slider("LUA", "A", "\aFFFFFFFF    Camera roll", -45, 45, 0, true, "°", 1)

UI.clantag = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Clantag")
UI.clantag_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\nclantag", {"V2", "V1"})
UI.watermark = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Watermark")
UI.watermark_name = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Name", {"necroptosis.red", "winston.red", "mood.blue", "sp!dusttale.red"})
UI.watermark_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\nwatermark", {"Lavender", "Windows", "Black", "Pink"})
UI.watermark_color = ui.new_color_picker("LUA", "A", "\aFFFFFFFF    Border color\nwatermark", 255, 255, 255, 255)
UI.watermark_avatar = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    Steam avatar")
UI.watermark_setup = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    Show setup watermark")
UI.watermark_setup_elems = ui.new_multiselect("LUA", "A", "\aFFFFFFFF      Setup elements", {"FPS", "Ping", "Loss", "Var", "Timeout"})
UI.spectators = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Spectators")
UI.spectators_size = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Size\nspectators", {"Small", "Medium"})
UI.spectators_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\nspectators", {"Classic"})
UI.spectators_anim = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Animation\nspectators", {"None", "Moving", "Moving title", "Bouncy"})
UI.spectators_color = ui.new_color_picker("LUA", "A", "\aFFFFFFFF    Color\nspectators", 255, 255, 255, 255)
UI.keybinds = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Keybinds")
UI.keybinds_size = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Size\nkeybinds", {"Small", "Medium", "Big"})
UI.keybinds_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\nkeybinds", {"Classic", "Windows", "Lavender"})
UI.keybinds_anim = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Animation\nkeybinds", {"None", "Moving", "Moving title", "Bouncy"})
UI.keybinds_color = ui.new_color_picker("LUA", "A", "\aFFFFFFFF    Color\nkeybinds", 255, 255, 255, 255)
UI.indicators = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Indicators")
UI.indicators_size = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Size\nindicators", {"Small", "Medium", "Big"})
UI.indicators_features = ui.new_multiselect("LUA", "A", "\aFFFFFFFF    Features", {
    "Force safe point", "Force body aim", "Ping spike", "Double tap", "Duck peek assist", "Freestanding", "On shot anti-aim", "Minimum damage override"
})
UI.indicators_color = ui.new_color_picker("LUA", "A", "\aFFFFFFFF    Color\nindicators", 255, 255, 255, 255)
UI.miss_log = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Miss log")
UI.first_person_nade = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  First person on nade")
UI.fps_boost = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  FPS Boost")
UI.fps_boost_options = ui.new_multiselect("LUA", "A", "\aFFFFFFFF    Options", {
    "Disable Dynamic Lighting", "Disable Dynamic Shadows", "Disable First-Person Tracers",
    "Disable Ragdolls", "Disable Eye Gloss", "Disable Eye Movement", "Enable Multi-Core Rendering",
    "Force Preload", "Remove FPS Cap", "Disable Muzzle Flash Light", "Reduce Breakable Object Impact"
})
UI.warmup_divider = ui.new_label("LUA", "A", "\aFFFFFFFF  ────────────────────")
UI.warmup_warning = ui.new_label("LUA", "A", "\aFFD700FF  only local server")
UI.warmup_helper = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Warmup Assistant")

-- Forward declaration (функция определяется ниже, но используется в callback выше по коду)
local handle_warmup_assistant
local restore_warmup_defaults
local apply_fps_boost

local aspect_ratio = {
    screen_width = nil,
    screen_height = nil,
    table = {},
    steps = 200
}

local function setup_aspect_ratio()
    local screen_width, screen_height = client.screen_size()
    aspect_ratio.screen_width, aspect_ratio.screen_height = screen_width, screen_height
    
    local function gcd(m, n)
        while m ~= 0 do
            m, n = math.fmod(n, m), m
        end
        return n
    end
    
    local multiplier = 0.01
    for i = 1, aspect_ratio.steps do
        local i2 = (aspect_ratio.steps - i) * multiplier
        local divisor = gcd(screen_width * i2, screen_height)
        if screen_width * i2 / divisor < 100 or i2 == 1 then
            aspect_ratio.table[i] = screen_width * i2 / divisor .. ":" .. screen_height / divisor
        end
    end
end

setup_aspect_ratio()

local csgo_weapons = require 'gamesense/csgo_weapons'

local weapons = {
    primary = {
        "-", "AWP", "SCAR20/G3SG1", "Scout", "M4/AK47", "Famas/Galil", "Aug/SG553", 
        "M249", "Negev", "Mag7/SawedOff", "Nova", "XM1014", "MP9/Mac10", "UMP45", "PPBizon", "MP7"
    },
    secondary = {
        "-", "CZ75/Tec9/FiveSeven", "P250", "Deagle/Revolver", "Dualies"
    },
    grenade_types = {
        "HE Grenade", "Molotov", "Smoke", "Flash", "Flash", "Decoy"
    },
    utility_types = {
        "Armor", "Helmet", "Zeus", "Defuser"
    },
    prices = {},
    buy_commands = {}
}

weapons.prices = {
    ["-"] = 0,
    AWP = csgo_weapons.weapon_awp.in_game_price,
    ["SCAR20/G3SG1"] = csgo_weapons.weapon_scar20.in_game_price,
    Scout = csgo_weapons.weapon_ssg08.in_game_price,
    ["M4/AK47"] = csgo_weapons.weapon_m4a1.in_game_price,
    ["Famas/Galil"] = csgo_weapons.weapon_famas.in_game_price,
    ["Aug/SG553"] = csgo_weapons.weapon_aug.in_game_price,
    M249 = csgo_weapons.weapon_m249.in_game_price,
    Negev = csgo_weapons.weapon_negev.in_game_price,
    ["Mag7/SawedOff"] = csgo_weapons.weapon_mag7.in_game_price,
    Nova = csgo_weapons.weapon_nova.in_game_price,
    XM1014 = csgo_weapons.weapon_xm1014.in_game_price,
    ["MP9/Mac10"] = csgo_weapons.weapon_mp9.in_game_price,
    UMP45 = csgo_weapons.weapon_ump45.in_game_price,
    PPBizon = csgo_weapons.weapon_bizon.in_game_price,
    MP7 = csgo_weapons.weapon_mp7.in_game_price,
    ["CZ75/Tec9/FiveSeven"] = csgo_weapons.weapon_tec9.in_game_price,
    P250 = csgo_weapons.weapon_p250.in_game_price,
    ["Deagle/Revolver"] = csgo_weapons.weapon_deagle.in_game_price,
    Dualies = csgo_weapons.weapon_elite.in_game_price,
    ["HE Grenade"] = csgo_weapons.weapon_hegrenade.in_game_price,
    Molotov = csgo_weapons.weapon_molotov.in_game_price,
    Smoke = csgo_weapons.weapon_smokegrenade.in_game_price,
    Flash = csgo_weapons.weapon_flashbang.in_game_price,
    Decoy = csgo_weapons.weapon_decoy.in_game_price,
    Armor = csgo_weapons.item_kevlar.in_game_price,
    Helmet = csgo_weapons.item_assaultsuit.in_game_price,
    Zeus = csgo_weapons.weapon_taser.in_game_price,
    Defuser = csgo_weapons.item_cutters.in_game_price
}

weapons.buy_commands = {
    Smoke = "buy smokegrenade",
    Molotov = "buy molotov",
    ["HE Grenade"] = "buy hegrenade",
    Dualies = "buy elite",
    ["Deagle/Revolver"] = "buy deagle",
    P250 = "buy p250",
    ["CZ75/Tec9/FiveSeven"] = "buy tec9",
    MP7 = "buy mp7",
    PPBizon = "buy bizon",
    UMP45 = "buy ump45",
    ["MP9/Mac10"] = "buy mp9",
    XM1014 = "buy xm1014",
    Nova = "buy nova",
    ["Mag7/SawedOff"] = "buy mag7",
    Negev = "buy negev",
    M249 = "buy m249",
    ["Aug/SG553"] = "buy aug",
    ["Famas/Galil"] = "buy famas",
    ["M4/AK47"] = "buy m4a1",
    Scout = "buy ssg08",
    ["SCAR20/G3SG1"] = "buy scar20",
    AWP = "buy awp",
    ["-"] = "",
    Defuser = "buy defuser",
    Zeus = "buy taser 34",
    Helmet = "buy vesthelm",
    Armor = "buy vest",
    Decoy = "buy decoy",
    Flash = "buy flashbang"
}

UI.autobuy_enabled = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Automatic purchase")
UI.autobuy_primary = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Primary", weapons.primary)
UI.autobuy_secondary = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Secondary", weapons.secondary)
UI.autobuy_grenades = ui.new_multiselect("LUA", "A", "\aFFFFFFFF    Grenades", weapons.grenade_types)
UI.autobuy_utilities = ui.new_multiselect("LUA", "A", "\aFFFFFFFF    Utilities", weapons.utility_types)
UI.autobuy_cost_based = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    Cost based")
UI.autobuy_balance = ui.new_slider("LUA", "A", "\aFFFFFFFF    Balance override", 0, 16000, 0, true, "$", 1, {[0] = "Auto"})
UI.autobuy_backup_primary = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Backup Primary", weapons.primary)
UI.autobuy_backup_secondary = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Backup Secondary", weapons.secondary)
UI.autobuy_backup_grenades = ui.new_multiselect("LUA", "A", "\aFFFFFFFF    Backup Grenades", weapons.grenade_types)
UI.autobuy_backup_utilities = ui.new_multiselect("LUA", "A", "\aFFFFFFFF    Backup Utilities", weapons.utility_types)


local trashtalk_default_phrases = {
    {text = "1", messages = {}, on_kill = true, on_death = false, delay = 0.5},
    {text = "ебать хуесосу везет", messages = {}, on_kill = false, on_death = true, delay = 1.2},
    {text = "ez $name", messages = {}, on_kill = true, on_death = false, delay = 0.1},
    {text = "$name дс сын бляди", messages = {}, on_kill = false, on_death = true, delay = 0.9},
    {text = "лучшая луа - тгк femclub0", messages = {}, on_kill = true, on_death = false, delay = 0.1},
    {text = "жирный пидор $name", messages = {"$name пидорасищеее", "$name трахал тебя btw чмо"}, on_kill = true, on_death = true, delay = 1.3},
    {text = "1", messages = {"1", "1"}, on_kill = true, on_death = false, delay = 0.7},
    {text = "$name еще один бомж ебанный", messages = {"уродище которое нихуя не может", "у долбаеба на лаки залетает сидит радуется"}, on_kill = false, on_death = true, delay = 2.4},
    {text = "потаскуха ебанная $name", messages = {"1x1 вывезешь?", "$name алло ублюдина 1x1 идешь?"}, on_kill = false, on_death = true, delay = 2.1},
    {text = "выебал пидораса 1", messages = {"изи пизда"}, on_kill = true, on_death = false, delay = 1.3}
}

local trashtalk = {
    phrases = {},
    selected_index = 1,
    kill_pool = {},
    death_pool = {}
}


local function load_trashtalk_phrases()
    local saved = database.read("uwu_trashtalk_phrases")
    if saved and type(saved) == "table" and #saved > 0 then
        trashtalk.phrases = saved
    else
        
        for i = 1, #trashtalk_default_phrases do
            trashtalk.phrases[i] = trashtalk_default_phrases[i]
        end
    end
end


local function save_trashtalk_phrases()
    database.write("uwu_trashtalk_phrases", trashtalk.phrases)
end


load_trashtalk_phrases()

UI.trashtalk_enabled = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Trashtalk")
UI.trashtalk_list = ui.new_listbox("LUA", "A", "\aFFFFFFFF    Phrases", {})
UI.trashtalk_add = ui.new_button("LUA", "A", "\aFFFFFFFF    Add phrase", function() end)
UI.trashtalk_remove = ui.new_button("LUA", "A", "\aFFFFFFFF    Remove phrase", function() end)
UI.trashtalk_edit = ui.new_button("LUA", "A", "\aFFFFFFFF    Edit phrase", function() end)
UI.trashtalk_reset = ui.new_button("LUA", "A", "\aFFFFFFFF    Reset to default", function() end)
UI.trashtalk_no_repeat = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    Don't repeat phrases")
UI.trashtalk_phrase_text = ui.new_textbox("LUA", "A", "\aFFFFFFFF    Message")
UI.trashtalk_phrase_text2 = ui.new_textbox("LUA", "A", "\aFFFFFFFF    Message 2")
UI.trashtalk_phrase_text3 = ui.new_textbox("LUA", "A", "\aFFFFFFFF    Message 3")
UI.trashtalk_russian_label = ui.new_label("LUA", "A", "\aFFFFFFFF    For Russian: Edit uwu_hook.lua")
UI.trashtalk_name_label = ui.new_label("LUA", "A", "\aFFFFFFFF    Use $name to insert player names")
UI.trashtalk_on_kill = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    On kill")
UI.trashtalk_on_death = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    On death")
UI.trashtalk_delay = ui.new_slider("LUA", "A", "\aFFFFFFFF    Delay", 0, 50, 5, true, "s", 0.1)
UI.trashtalk_add_message = ui.new_button("LUA", "A", "\aFFFFFFFF    New message", function() end)
UI.trashtalk_remove_message = ui.new_button("LUA", "A", "\aFFFFFFFF    Remove message", function() end)
UI.trashtalk_save = ui.new_button("LUA", "A", "\aFFFFFFFF    Save", function() end)
UI.trashtalk_cancel = ui.new_button("LUA", "A", "\aFFFFFFFF    Cancel", function() end)

local trashtalk_state = {
    editing = false,
    edit_index = nil,
    message_count = 1
}


local config_system = {
    configs = {},
    selected_name = ""
}


local function load_config_list()
    local saved = database.read("uwu_config_list")
    if saved and type(saved) == "table" then
        config_system.configs = saved
    else
        config_system.configs = {}
    end
end


local function save_config_list()
    database.write("uwu_config_list", config_system.configs)
end

load_config_list()

UI.config_name = ui.new_textbox("LUA", "A", "\aFFFFFFFF  Config name")
UI.config_list = ui.new_listbox("LUA", "A", "\aFFFFFFFF  Saved configs", {})
UI.config_save = ui.new_button("LUA", "A", "\aFFFFFFFF  Save config", function() end)
UI.config_load = ui.new_button("LUA", "A", "\aFFFFFFFF  Load config", function() end)
UI.config_delete = ui.new_button("LUA", "A", "\aFFFFFFFF  Delete config", function() end)
UI.config_export = ui.new_button("LUA", "A", "\aFFFFFFFF  Export to clipboard", function() end)
UI.config_import = ui.new_button("LUA", "A", "\aFFFFFFFF  Import from clipboard", function() end)
UI.config_status = ui.new_label("LUA", "A", " ")

local trashtalk_state = {
    editing = false,
    edit_index = nil,
    message_count = 1
}

local function update_trashtalk_list()
    local list_items = {}
    for i = 1, #trashtalk.phrases do
        local phrase = trashtalk.phrases[i]
        local prefix = ""
        if phrase.on_kill and phrase.on_death then
            prefix = "[K+D] "
        elseif phrase.on_kill then
            prefix = "[K] "
        elseif phrase.on_death then
            prefix = "[D] "
        end
        list_items[i] = prefix .. phrase.text:sub(1, 40)
    end
    ui.update(UI.trashtalk_list, list_items)
end

local function collect_custom_models()
    local models = {}
    local file_handle = int_ptr()
    local file = find_first("*", "CUSTOMMODEL", file_handle)
    while file ~= nil do
        local file_name = ffi.string(file)
        if find_is_directory(file_handle[0]) == true and file_name ~= "." and file_name ~= ".." then
            local subfolder_handle = int_ptr()
            local subfolder_file = find_first(file_name .. "/*", "CUSTOMMODEL", subfolder_handle)
            while subfolder_file ~= nil do
                local subfolder_file_name = ffi.string(subfolder_file)
                if find_is_directory(subfolder_handle[0]) == false and subfolder_file_name:find(".mdl") then
                    local lower_name = subfolder_file_name:lower()
                    if not lower_name:find("arms") and not lower_name:find("sleeve") and not lower_name:find("hand") and not lower_name:find("bas%.res") then
                        local model_path = "models/player/custom_player/" .. file_name .. "/" .. subfolder_file_name
                        local display_name = subfolder_file_name:gsub(".mdl", ""):gsub("_", " ")
                        local first_letter = display_name:sub(1, 1)
                        local rest = display_name:sub(2)
                        display_name = first_letter:upper() .. rest
                        models[display_name] = model_path
                    end
                elseif find_is_directory(subfolder_handle[0]) == true and subfolder_file_name ~= "." and subfolder_file_name ~= ".." then
                    local subsubfolder_handle = int_ptr()
                    local subsubfolder_file = find_first(file_name .. "/" .. subfolder_file_name .. "/*", "CUSTOMMODEL", subsubfolder_handle)
                    while subsubfolder_file ~= nil do
                        local subsubfolder_file_name = ffi.string(subsubfolder_file)
                        if find_is_directory(subsubfolder_handle[0]) == false and subsubfolder_file_name:find(".mdl") then
                            local lower_name = subsubfolder_file_name:lower()
                            if not lower_name:find("arms") and not lower_name:find("sleeve") and not lower_name:find("hand") and not lower_name:find("bas%.res") then
                                local model_path = "models/player/custom_player/" .. file_name .. "/" .. subfolder_file_name .. "/" .. subsubfolder_file_name
                                local display_name = subsubfolder_file_name:gsub(".mdl", ""):gsub("_", " ")
                                local first_letter = display_name:sub(1, 1)
                                local rest = display_name:sub(2)
                                display_name = first_letter:upper() .. rest
                                models[display_name] = model_path
                            end
                        end
                        subsubfolder_file = find_next(subsubfolder_handle[0])
                    end
                    find_close(subsubfolder_handle[0])
                end
                subfolder_file = find_next(subfolder_handle[0])
            end
            find_close(subfolder_handle[0])
        elseif find_is_directory(file_handle[0]) == false and file_name:find(".mdl") then
            local lower_name = file_name:lower()
            if not lower_name:find("arms") and not lower_name:find("sleeve") and not lower_name:find("hand") and not lower_name:find("bas%.res") then
                local model_path = "models/player/custom_player/" .. file_name
                local display_name = file_name:gsub(".mdl", ""):gsub("_", " ")
                local first_letter = display_name:sub(1, 1)
                local rest = display_name:sub(2)
                display_name = first_letter:upper() .. rest
                models[display_name] = model_path
            end
        end
        file = find_next(file_handle[0])
    end
    find_close(file_handle[0])
    return models
end

local custom_model_path = char_buffer(192)
current_directory(custom_model_path, ffi.sizeof(custom_model_path))
custom_model_path = string.format("%s\\csgo\\models\\player\\custom_player", ffi.string(custom_model_path))
add_to_searchpath(custom_model_path, "CUSTOMMODEL", 0)

local models = {
    auto_t = collect_custom_models(),
    auto_ct = collect_custom_models(),
    t_player = {
        ["None"] = "",
        ["mika"] = "models/player/custom_player/nuclearsilo/blue_archive/mika/mika_v2.mdl",
        ["jinx"] = "models/player/custom_player/kolka/Arcane_Jinx/arcane_jinx.mdl",
        ["dva"] = "models/player/custom_player/killzonegaming/dva/dva.mdl",
        ["hatsunenightmare"] = "models/player/custom_player/maoling/vocaloid/hatsune_miku/monsterko/nightmare/miku_nightmare.mdl", 
        ["hutao"] = "models/player/custom_player/toppiofficial/genshin/rework/hutao.mdl",
    },
    ct_player = {
        ["None"] = "",
        ["mika"] = "models/player/custom_player/nuclearsilo/blue_archive/mika/mika_v2.mdl",
        ["jinx"] = "models/player/custom_player/kolka/Arcane_Jinx/arcane_jinx.mdl",
        ["dva"] = "models/player/custom_player/killzonegaming/dva/dva.mdl",
        ["hatsunenightmare"] = "models/player/custom_player/maoling/vocaloid/hatsune_miku/monsterko/nightmare/miku_nightmare.mdl", 
        ["hutao"] = "models/player/custom_player/toppiofficial/genshin/rework/hutao.mdl",
    }
}

models.auto_t["None"] = ""
models.auto_ct["None"] = ""

local function get_model_names(models_table)
    local names = {}
    for k, v in pairs(models_table) do
        table.insert(names, k)
    end
    table.sort(names, function(a, b)
        if a == "None" then return true end
        if b == "None" then return false end
        return a < b
    end)
    return names
end

models.names_t = get_model_names(models.t_player)
models.names_ct = get_model_names(models.ct_player)
models.auto_names_t = get_model_names(models.auto_t)
models.auto_names_ct = get_model_names(models.auto_ct)

UI.model_changer = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Model changer")
UI.model_changer_mode = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Mode", {"Manual", "Auto"})
UI.model_changer_ct = ui.new_combobox("LUA", "A", "\aFFFFFFFF    CT Model", models.names_ct)
UI.model_changer_t = ui.new_combobox("LUA", "A", "\aFFFFFFFF    T Model", models.names_t)
UI.model_changer_ct_auto = ui.new_combobox("LUA", "A", "\aFFFFFFFF    CT Model\nauto", models.auto_names_ct)
UI.model_changer_t_auto = ui.new_combobox("LUA", "A", "\aFFFFFFFF    T Model\nauto", models.auto_names_t)

local hit_sounds = {
    names = {"Wood stop", "Wood strain", "Wood plank impact", "Warning"},
    files = {
        ["Wood stop"] = "doors/wood_stop1.wav",
        ["Wood strain"] = "physics/wood/wood_strain7.wav",
        ["Wood plank impact"] = "physics/wood/wood_plank_impact_hard4.wav",
        ["Warning"] = "resource/warning.wav"
    }
}

local function collect_hit_sound_files()
    local file_handle = int_ptr()
    local file = find_first("*", "XGAME", file_handle)
    while file ~= nil do
        local file_name = ffi.string(file)
        if find_is_directory(file_handle[0]) == false and (file_name:find(".mp3") or file_name:find(".wav")) then
            local display_name = file_name:gsub("_", " "):gsub(".mp3", ""):gsub(".wav", "")
            hit_sounds.names[#hit_sounds.names+1] = display_name
            hit_sounds.files[display_name] = string.format("hitsounds/%s", file_name)
        end
        file = find_next(file_handle[0])
    end
    find_close(file_handle[0])
end

local current_path_hitsound = char_buffer(128)
current_directory(current_path_hitsound, ffi.sizeof(current_path_hitsound))
current_path_hitsound = string.format("%s\\csgo\\sound\\hitsounds", ffi.string(current_path_hitsound))
add_to_searchpath(current_path_hitsound, "XGAME", 0)
collect_hit_sound_files()

UI.hit_sound = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Hit sound")
UI.hit_sound_head = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Head shot sound", hit_sounds.names)
UI.hit_sound_body = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Body shot sound", hit_sounds.names)
UI.hit_sound_volume = ui.new_slider("LUA", "A", "\aFFFFFFFF    Volume\nhit_sound", 1, 100, 1, true, "%")

UI.death_sound = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Death sound")
UI.death_sound_select = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Sound", media.death_sound_names)
UI.death_sound_volume = ui.new_slider("LUA", "A", "\aFFFFFFFF    Volume", 1, 10, 5)

UI.viewmodel_changer = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Viewmodel changer")
UI.viewmodel_fov = ui.new_slider("LUA", "A", "\aFFFFFFFF    FOV", -1800, 1800, 680, true, "", 0.1)
UI.viewmodel_x = ui.new_slider("LUA", "A", "\aFFFFFFFF    X", -1800, 1800, 25, true, "", 0.1)
UI.viewmodel_y = ui.new_slider("LUA", "A", "\aFFFFFFFF    Y", -1800, 1800, 0, true, "", 0.1)
UI.viewmodel_z = ui.new_slider("LUA", "A", "\aFFFFFFFF    Z", -1800, 1800, -15, true, "", 0.1)

UI.console_color = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Console color")
UI.console_color_picker = ui.new_color_picker("LUA", "A", "\aFFFFFFFF  Console color", 81, 81, 81, 210)

UI.aspect_ratio_enabled = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Aspect ratio")
UI.aspect_ratio = ui.new_slider("LUA", "A", "\aFFFFFFFF    Aspect ratio", 0, aspect_ratio.steps - 1, aspect_ratio.steps / 2, true, "%", 1, aspect_ratio.table)

UI.thirdperson_distance = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Thirdperson distance")
UI.thirdperson_distance_value = ui.new_slider("LUA", "A", "\aFFFFFFFF    Distance", 30, 200, 150)

UI.fov_override_enabled = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  FOV override")
UI.fov_override = ui.new_slider("LUA", "A", "\aFFFFFFFF    FOV", 1, 170, 90, true, "°", 1)

UI.skybox = ui.new_checkbox("LUA", "A", "\aFFFFFFFF  Skybox changer")
UI.skybox_list = ui.new_listbox("LUA", "A", "\aFFFFFFFF    Skybox", skybox_names)
UI.skybox_color = ui.new_color_picker("LUA", "A", "\aFFFFFFFF  Skybox changer", 255, 255, 255, 255)
UI.skybox_style = ui.new_combobox("LUA", "A", "\aFFFFFFFF    Style\nskybox", {"Custom", "Rainbow"})
UI.skybox_brightness = ui.new_slider("LUA", "A", "\aFFFFFFFF    Brightness\nskybox", 10, 500, 100, true, "%", 0.1)
UI.skybox_color_strength = ui.new_slider("LUA", "A", "\aFFFFFFFF    Color strength\nskybox", 0, 200, 100, true, "%", 0.1)
UI.skybox_remove_3d = ui.new_checkbox("LUA", "A", "\aFFFFFFFF    Remove 3D sky")


local autobuy_state = {
    primary_buy_cmd = "",
    backup_buy_cmd = "",
    primary_cost = 0,
    purchased = false,
    in_buyzone = false,
    grenade_cache = {},
    backup_grenade_cache = {}
}

local function limit_grenades(ref, cache_key)
    local grenades = ui.get(ref)
    if #grenades > 4 then
        ui.set(ref, autobuy_state[cache_key])
    else
        autobuy_state[cache_key] = grenades
    end
end

local function update_autobuy_commands()
    autobuy_state.primary_cost = 0
    
    local secondary = ui.get(UI.autobuy_secondary)
    if secondary then
        autobuy_state.primary_cost = autobuy_state.primary_cost + (weapons.prices[secondary] or 0)
    end
    
    local utilities = ui.get(UI.autobuy_utilities) or {}
    for i = 1, #utilities do
        local util = utilities[i]
        if util then
            autobuy_state.primary_cost = autobuy_state.primary_cost + (weapons.prices[util] or 0)
        end
    end
    
    local primary = ui.get(UI.autobuy_primary)
    if primary then
        autobuy_state.primary_cost = autobuy_state.primary_cost + (weapons.prices[primary] or 0)
    end
    
    local grenades = ui.get(UI.autobuy_grenades) or {}
    for i = 1, #grenades do
        local nade = grenades[i]
        if nade then
            autobuy_state.primary_cost = autobuy_state.primary_cost + (weapons.prices[nade] or 0)
        end
    end
end

local function update_visibility_changer()
    local enabled = ui.get(UI.enabled) and ui.get(UI.nav_open)
    local is_changer = enabled and ui.get(UI.tab) == "Changer"
    
    ui.set_visible(UI.model_changer, is_changer)
    
    local model_changer_enabled = ui.get(UI.model_changer)
    local model_mode = ui.get(UI.model_changer_mode)
    ui.set_visible(UI.model_changer_mode, is_changer and model_changer_enabled)
    ui.set_visible(UI.model_changer_ct, is_changer and model_changer_enabled and model_mode == "Manual")
    ui.set_visible(UI.model_changer_t, is_changer and model_changer_enabled and model_mode == "Manual")
    ui.set_visible(UI.model_changer_ct_auto, is_changer and model_changer_enabled and model_mode == "Auto")
    ui.set_visible(UI.model_changer_t_auto, is_changer and model_changer_enabled and model_mode == "Auto")
    
    ui.set_visible(UI.hit_sound, is_changer)
    local hit_sound_enabled = ui.get(UI.hit_sound)
    ui.set_visible(UI.hit_sound_head, is_changer and hit_sound_enabled)
    ui.set_visible(UI.hit_sound_body, is_changer and hit_sound_enabled)
    ui.set_visible(UI.hit_sound_volume, is_changer and hit_sound_enabled)
    
    ui.set_visible(UI.death_sound, is_changer)
    local death_sound_enabled = ui.get(UI.death_sound)
    ui.set_visible(UI.death_sound_select, is_changer and death_sound_enabled)
    ui.set_visible(UI.death_sound_volume, is_changer and death_sound_enabled)
    
    ui.set_visible(UI.viewmodel_changer, is_changer)
    local viewmodel_enabled = ui.get(UI.viewmodel_changer)
    ui.set_visible(UI.viewmodel_fov, is_changer and viewmodel_enabled)
    ui.set_visible(UI.viewmodel_x, is_changer and viewmodel_enabled)
    ui.set_visible(UI.viewmodel_y, is_changer and viewmodel_enabled)
    ui.set_visible(UI.viewmodel_z, is_changer and viewmodel_enabled)
    
    ui.set_visible(UI.console_color, is_changer)
    ui.set_visible(UI.console_color_picker, is_changer and ui.get(UI.console_color))
    
    ui.set_visible(UI.aspect_ratio_enabled, is_changer)
    local aspect_ratio_enabled = ui.get(UI.aspect_ratio_enabled)
    ui.set_visible(UI.aspect_ratio, is_changer and aspect_ratio_enabled)
    
    ui.set_visible(UI.thirdperson_distance, is_changer)
    local thirdperson_enabled = ui.get(UI.thirdperson_distance)
    ui.set_visible(UI.thirdperson_distance_value, is_changer and thirdperson_enabled)
    
    ui.set_visible(UI.skybox, is_changer)
    local skybox_enabled = ui.get(UI.skybox)
    local skybox_style = ui.get(UI.skybox_style)
    ui.set_visible(UI.skybox_list, is_changer and skybox_enabled)
    ui.set_visible(UI.skybox_color, is_changer and skybox_enabled and skybox_style == "Custom")
    ui.set_visible(UI.skybox_style, is_changer and skybox_enabled)
    ui.set_visible(UI.skybox_brightness, is_changer and skybox_enabled)
    ui.set_visible(UI.skybox_color_strength, is_changer and skybox_enabled)
    ui.set_visible(UI.skybox_remove_3d, is_changer and skybox_enabled)
    
    ui.set_visible(UI.fov_override_enabled, is_changer)
    local fov_override_enabled = ui.get(UI.fov_override_enabled)
    ui.set_visible(UI.fov_override, is_changer and fov_override_enabled)
end

local function update_visibility_trashtalk()
    local enabled = ui.get(UI.enabled) and ui.get(UI.nav_open)
    local is_trashtalk = enabled and ui.get(UI.tab) == "Trashtalk"
    
    ui.set_visible(UI.trashtalk_enabled, is_trashtalk)
    
    local trashtalk_enabled = ui.get(UI.trashtalk_enabled)
    local show_trashtalk = is_trashtalk and trashtalk_enabled
    
    ui.set_visible(UI.trashtalk_list, show_trashtalk and not trashtalk_state.editing)
    ui.set_visible(UI.trashtalk_add, show_trashtalk and not trashtalk_state.editing)
    ui.set_visible(UI.trashtalk_remove, show_trashtalk and not trashtalk_state.editing)
    ui.set_visible(UI.trashtalk_edit, show_trashtalk and not trashtalk_state.editing)
    ui.set_visible(UI.trashtalk_reset, show_trashtalk and not trashtalk_state.editing)
    ui.set_visible(UI.trashtalk_no_repeat, show_trashtalk and not trashtalk_state.editing)
    
    ui.set_visible(UI.trashtalk_phrase_text, show_trashtalk and trashtalk_state.editing)
    ui.set_visible(UI.trashtalk_phrase_text2, show_trashtalk and trashtalk_state.editing and trashtalk_state.message_count >= 2)
    ui.set_visible(UI.trashtalk_phrase_text3, show_trashtalk and trashtalk_state.editing and trashtalk_state.message_count >= 3)
    ui.set_visible(UI.trashtalk_russian_label, show_trashtalk and trashtalk_state.editing)
    ui.set_visible(UI.trashtalk_name_label, show_trashtalk and trashtalk_state.editing)
    ui.set_visible(UI.trashtalk_on_kill, show_trashtalk and trashtalk_state.editing)
    ui.set_visible(UI.trashtalk_on_death, show_trashtalk and trashtalk_state.editing)
    ui.set_visible(UI.trashtalk_delay, show_trashtalk and trashtalk_state.editing)
    ui.set_visible(UI.trashtalk_add_message, show_trashtalk and trashtalk_state.editing and trashtalk_state.message_count < 3)
    ui.set_visible(UI.trashtalk_remove_message, show_trashtalk and trashtalk_state.editing and trashtalk_state.message_count > 1)
    ui.set_visible(UI.trashtalk_save, show_trashtalk and trashtalk_state.editing)
    ui.set_visible(UI.trashtalk_cancel, show_trashtalk and trashtalk_state.editing)
end

local function update_visibility_config()
    local enabled = ui.get(UI.enabled) and ui.get(UI.nav_open)
    local is_config = enabled and ui.get(UI.tab) == "Config"
    
    ui.set_visible(UI.config_name, is_config)
    ui.set_visible(UI.config_list, is_config)
    ui.set_visible(UI.config_save, is_config)
    ui.set_visible(UI.config_load, is_config)
    ui.set_visible(UI.config_delete, is_config)
    ui.set_visible(UI.config_export, is_config)
    ui.set_visible(UI.config_import, is_config)
    ui.set_visible(UI.config_status, is_config)
end

local function update_visibility_autobuy()
    local enabled = ui.get(UI.enabled) and ui.get(UI.nav_open)
    local is_autobuy = enabled and ui.get(UI.tab) == "Autobuy"
    
    ui.set_visible(UI.autobuy_enabled, is_autobuy)
    
    local autobuy_enabled = ui.get(UI.autobuy_enabled)
    local show_autobuy_opts = is_autobuy and autobuy_enabled
    
    ui.set_visible(UI.autobuy_primary, show_autobuy_opts)
    ui.set_visible(UI.autobuy_secondary, show_autobuy_opts)
    ui.set_visible(UI.autobuy_grenades, show_autobuy_opts)
    ui.set_visible(UI.autobuy_utilities, show_autobuy_opts)
    ui.set_visible(UI.autobuy_cost_based, show_autobuy_opts)
    
    local cost_based = ui.get(UI.autobuy_cost_based)
    local show_backup = show_autobuy_opts and cost_based
    
    ui.set_visible(UI.autobuy_balance, show_backup)
    ui.set_visible(UI.autobuy_backup_primary, show_backup)
    ui.set_visible(UI.autobuy_backup_secondary, show_backup)
    ui.set_visible(UI.autobuy_backup_grenades, show_backup)
    ui.set_visible(UI.autobuy_backup_utilities, show_backup)
end

local function update_visibility_visuals()
    local enabled = ui.get(UI.enabled) and ui.get(UI.nav_open)
    local is_visuals = enabled and ui.get(UI.tab) == "Visuals"
    
    ui.set_visible(UI.notifications, is_visuals)
    local notif_enabled = ui.get(UI.notifications)
    local show_notify_opts = is_visuals and notif_enabled
    ui.set_visible(UI.notify_types, show_notify_opts)
    ui.set_visible(UI.notify_style, show_notify_opts)
    ui.set_visible(UI.notify_size, show_notify_opts)
    ui.set_visible(UI.notify_limit, show_notify_opts)
    ui.set_visible(UI.notify_duration, show_notify_opts)
    
    ui.set_visible(UI.kill_image, is_visuals)
    local kill_image_enabled = ui.get(UI.kill_image)
    local show_kill_image_opts = is_visuals and kill_image_enabled
    ui.set_visible(UI.kill_image_select, show_kill_image_opts)
    ui.set_visible(UI.kill_image_alpha, show_kill_image_opts)
    ui.set_visible(UI.kill_image_duration, show_kill_image_opts)
    ui.set_visible(UI.kill_image_no_repeat, show_kill_image_opts)
    ui.set_visible(UI.kill_image_size, show_kill_image_opts)
    
    ui.set_visible(UI.healthbar, is_visuals)
    local healthbar_enabled = ui.get(UI.healthbar)
    local show_healthbar_opts = is_visuals and healthbar_enabled
    local healthbar_style = ui.get(UI.healthbar_style)
    ui.set_visible(UI.healthbar_color_full, show_healthbar_opts)
    ui.set_visible(UI.healthbar_color_empty, show_healthbar_opts and healthbar_style == "Gradient")
    ui.set_visible(UI.healthbar_style, show_healthbar_opts)
end

local function update_visibility_hit_effect()
    local enabled = ui.get(UI.enabled) and ui.get(UI.nav_open)
    local is_visuals = enabled and ui.get(UI.tab) == "Visuals"
    
    ui.set_visible(UI.hit_effect, is_visuals)
    ui.set_visible(UI.hit_effect_color, is_visuals)
    local show_hit_effect_opts = is_visuals and ui.get(UI.hit_effect)
    ui.set_visible(UI.hit_effect_style, show_hit_effect_opts)
    local hit_style = ui.get(UI.hit_effect_style)
    ui.set_visible(UI.hit_effect_color2, show_hit_effect_opts and (hit_style == "2-color" or hit_style == "3-color"))
    ui.set_visible(UI.hit_effect_color3, show_hit_effect_opts and hit_style == "3-color")
    ui.set_visible(UI.hit_effect_particle, show_hit_effect_opts)
    ui.set_visible(UI.hit_effect_size, show_hit_effect_opts)
    ui.set_visible(UI.hit_effect_amount, show_hit_effect_opts)
    ui.set_visible(UI.hit_effect_duration, show_hit_effect_opts)
    ui.set_visible(UI.hit_effect_radius, show_hit_effect_opts)
    ui.set_visible(UI.hit_effect_glow, show_hit_effect_opts)
    ui.set_visible(UI.hit_effect_glow_thick, show_hit_effect_opts and ui.get(UI.hit_effect_glow))
    ui.set_visible(UI.hit_effect_anim, show_hit_effect_opts)
end

local function update_visibility_fog_scope()
    local enabled = ui.get(UI.enabled) and ui.get(UI.nav_open)
    local is_visuals = enabled and ui.get(UI.tab) == "Visuals"
    
    ui.set_visible(UI.scope, is_visuals)
    ui.set_visible(UI.scope_color, is_visuals)
    local scope_enabled = ui.get(UI.scope)
    local show_scope_opts = is_visuals and scope_enabled
    local scope_style_val = ui.get(UI.scope_style)
    ui.set_visible(UI.scope_color, is_visuals and scope_style_val ~= "Rainbow")
    ui.set_visible(UI.scope_style, show_scope_opts)
    ui.set_visible(UI.scope_color2, show_scope_opts and scope_style_val == "Dual color")
    ui.set_visible(UI.scope_thickness, show_scope_opts)
    ui.set_visible(UI.scope_length, show_scope_opts)
    ui.set_visible(UI.scope_gap, show_scope_opts)
    ui.set_visible(UI.scope_fade, show_scope_opts)
    ui.set_visible(UI.scope_glow, show_scope_opts)
    ui.set_visible(UI.scope_remove_lines, show_scope_opts)
end

local function update_visibility_tracers_trails()
    local enabled = ui.get(UI.enabled) and ui.get(UI.nav_open)
    local is_visuals = enabled and ui.get(UI.tab) == "Visuals"
    
    ui.set_visible(UI.tracers, is_visuals)
    ui.set_visible(UI.tracers_color, is_visuals)
    local tracers_enabled = ui.get(UI.tracers)
    local show_tracers_opts = is_visuals and tracers_enabled
    ui.set_visible(UI.tracers_style, show_tracers_opts)
    ui.set_visible(UI.tracers_color2, show_tracers_opts and (ui.get(UI.tracers_style) == "Gradient"))
    ui.set_visible(UI.tracers_duration, show_tracers_opts)
    ui.set_visible(UI.tracers_thickness, show_tracers_opts)
    ui.set_visible(UI.tracers_glow, show_tracers_opts)
    ui.set_visible(UI.tracers_glow_intensity, show_tracers_opts and ui.get(UI.tracers_glow))
    ui.set_visible(UI.tracers_anim, show_tracers_opts)
    ui.set_visible(UI.tracers_limit, show_tracers_opts)
    
    ui.set_visible(UI.trails, is_visuals)
    ui.set_visible(UI.trails_color, is_visuals)
    local show_trails_opts = is_visuals and ui.get(UI.trails)
    ui.set_visible(UI.trails_style, show_trails_opts)
    ui.set_visible(UI.trails_color2, show_trails_opts and (ui.get(UI.trails_style) == "Gradient"))
    ui.set_visible(UI.trails_duration, show_trails_opts)
    ui.set_visible(UI.trails_thickness, show_trails_opts)
    ui.set_visible(UI.trails_glow, show_trails_opts)
    ui.set_visible(UI.trails_glow_thickness, show_trails_opts and ui.get(UI.trails_glow))
    ui.set_visible(UI.trails_anim, show_trails_opts)
    
    ui.set_visible(UI.grenade_trail, is_visuals)
    ui.set_visible(UI.grenade_trail_color, is_visuals)
    local show_grenade_trail_opts = is_visuals and ui.get(UI.grenade_trail)
    ui.set_visible(UI.grenade_trail_style, show_grenade_trail_opts)
    ui.set_visible(UI.grenade_trail_color2, show_grenade_trail_opts and ui.get(UI.grenade_trail_style) == "Gradient")
    ui.set_visible(UI.grenade_trail_thickness, show_grenade_trail_opts)
    ui.set_visible(UI.grenade_trail_duration, show_grenade_trail_opts)
    ui.set_visible(UI.grenade_trail_glow, show_grenade_trail_opts)
    ui.set_visible(UI.grenade_trail_glow_intensity, show_grenade_trail_opts and ui.get(UI.grenade_trail_glow))
end

local function update_visibility_misc()
    local enabled = ui.get(UI.enabled) and ui.get(UI.nav_open)
    local is_misc = enabled and ui.get(UI.tab) == "Misc"

    ui.set_visible(UI.clantag, is_misc)
    ui.set_visible(UI.watermark, is_misc)
    ui.set_visible(UI.spectators, is_misc)
    ui.set_visible(UI.keybinds, is_misc)
    ui.set_visible(UI.indicators, is_misc)
    
    local clantag_enabled = ui.get(UI.clantag)
    local watermark_enabled = ui.get(UI.watermark)
    local spectators_enabled = ui.get(UI.spectators)
    local keybinds_enabled = ui.get(UI.keybinds)
    local indicators_enabled = ui.get(UI.indicators)
    
    ui.set_visible(UI.watermark_name, is_misc and watermark_enabled)
    ui.set_visible(UI.watermark_style, is_misc and watermark_enabled)
    ui.set_visible(UI.watermark_color, is_misc and watermark_enabled)
    ui.set_visible(UI.watermark_avatar, is_misc and watermark_enabled)
    ui.set_visible(UI.watermark_setup, is_misc and watermark_enabled)
    ui.set_visible(UI.watermark_setup_elems, is_misc and watermark_enabled and ui.get(UI.watermark_setup))
    ui.set_visible(UI.spectators_size, is_misc and spectators_enabled)
    ui.set_visible(UI.spectators_style, is_misc and spectators_enabled)
    ui.set_visible(UI.spectators_anim, is_misc and spectators_enabled)
    ui.set_visible(UI.spectators_color, is_misc and spectators_enabled)
    ui.set_visible(UI.keybinds_size, is_misc and keybinds_enabled)
    ui.set_visible(UI.keybinds_style, is_misc and keybinds_enabled)
    ui.set_visible(UI.keybinds_anim, is_misc and keybinds_enabled)
    ui.set_visible(UI.keybinds_color, is_misc and keybinds_enabled)
    ui.set_visible(UI.indicators_size, is_misc and indicators_enabled)
    ui.set_visible(UI.indicators_features, is_misc and indicators_enabled)
    ui.set_visible(UI.indicators_color, is_misc and indicators_enabled)
    ui.set_visible(UI.miss_log, is_misc)
    ui.set_visible(UI.first_person_nade, is_misc)
    ui.set_visible(UI.warmup_divider, is_misc)
    ui.set_visible(UI.warmup_warning, is_misc)
    ui.set_visible(UI.warmup_helper, is_misc)
    
    local fps_boost_enabled = ui.get(UI.fps_boost)
    ui.set_visible(UI.fps_boost, is_misc)
    ui.set_visible(UI.fps_boost_options, is_misc and fps_boost_enabled)
    
    local show_clantag_opts = is_misc and clantag_enabled
    ui.set_visible(UI.clantag_style, show_clantag_opts)
end

local function update_visibility_world()
    local enabled = ui.get(UI.enabled) and ui.get(UI.nav_open)
    local is_world = enabled and ui.get(UI.tab) == "World"
    
    ui.set_visible(UI.fog, is_world)
    ui.set_visible(UI.fog_color, is_world)
    local fog_enabled = ui.get(UI.fog)
    local show_fog_opts = is_world and fog_enabled
    local fog_is_rainbow = ui.get(UI.fog_style) == "Rainbow"
    ui.set_visible(UI.fog_color, is_world and fog_enabled and not fog_is_rainbow)
    ui.set_visible(UI.fog_style, show_fog_opts)
    ui.set_visible(UI.fog_start, show_fog_opts)
    ui.set_visible(UI.fog_end, show_fog_opts)
    ui.set_visible(UI.fog_density, show_fog_opts)
    ui.set_visible(UI.fog_rainbow_speed, show_fog_opts and fog_is_rainbow)
    
    ui.set_visible(UI.wall_color, is_world)
    local wall_color_enabled = ui.get(UI.wall_color)
    local wall_color_style = ui.get(UI.wall_color_style)
    ui.set_visible(UI.wall_color_picker, is_world and wall_color_enabled)
    ui.set_visible(UI.wall_color_style, is_world and wall_color_enabled)
    ui.set_visible(UI.wall_color_picker2, is_world and wall_color_enabled and wall_color_style == "Gradient")
    
    ui.set_visible(UI.bloom, is_world)
    ui.set_visible(UI.bloom_scale, is_world and ui.get(UI.bloom))
    
    ui.set_visible(UI.exposure, is_world)
    ui.set_visible(UI.exposure_value, is_world and ui.get(UI.exposure))
    
    ui.set_visible(UI.model_brightness, is_world)
    ui.set_visible(UI.model_brightness_value, is_world and ui.get(UI.model_brightness))
    
    ui.set_visible(UI.smooth_animation, is_world)
    
    ui.set_visible(UI.smooth_camera, is_world)
    local smooth_camera_enabled = ui.get(UI.smooth_camera)
    ui.set_visible(UI.smooth_camera_pitch_speed, is_world and smooth_camera_enabled)
    ui.set_visible(UI.smooth_camera_yaw_speed, is_world and smooth_camera_enabled)
    ui.set_visible(UI.smooth_camera_extrapolation, is_world and smooth_camera_enabled)
    ui.set_visible(UI.smooth_camera_velocity_filter, is_world and smooth_camera_enabled)
    ui.set_visible(UI.smooth_camera_prediction_clamp, is_world and smooth_camera_enabled)
    ui.set_visible(UI.smooth_camera_easing, is_world and smooth_camera_enabled)
    ui.set_visible(UI.smooth_camera_dynamic_fov, is_world and smooth_camera_enabled)
    local dynamic_fov_enabled = ui.get(UI.smooth_camera_dynamic_fov)
    ui.set_visible(UI.smooth_camera_fov_intensity, is_world and smooth_camera_enabled and dynamic_fov_enabled)
    ui.set_visible(UI.smooth_camera_roll, is_world and smooth_camera_enabled)
end

local function update_visibility()
    local enabled = ui.get(UI.enabled)
    local open = ui.get(UI.nav_open)
    -- Tab combobox stays hidden (state holder only); the nav buttons drive it
    ui.set_visible(UI.tab, false)
    -- closed: show the nav menu (label + buttons); open: show the section + Back
    ui.set_visible(UI.nav_label, enabled and not open)
    for _, btn in pairs(UI.nav) do
        ui.set_visible(btn, enabled and not open)
    end
    ui.set_visible(UI.nav_back, enabled and open)
    update_visibility_visuals()
    update_visibility_hit_effect()
    update_visibility_fog_scope()
    update_visibility_tracers_trails()
    update_visibility_world()
    update_visibility_misc()
    update_visibility_autobuy()
    update_visibility_changer()
    update_visibility_trashtalk()
    update_visibility_config()
end

-- expose for the nav button callbacks (defined earlier, before this function)
UI._update_visibility = update_visibility

ui.set_callback(UI.enabled, update_visibility)
ui.set_callback(UI.tab, update_visibility)
ui.set_callback(UI.notifications, update_visibility)
ui.set_callback(UI.healthbar, update_visibility)
ui.set_callback(UI.healthbar_style, update_visibility)
ui.set_callback(UI.clantag, update_visibility)
ui.set_callback(UI.watermark, update_visibility)
ui.set_callback(UI.watermark_setup, update_visibility)
ui.set_callback(UI.death_sound, update_visibility)
ui.set_callback(UI.kill_image, update_visibility)
ui.set_callback(UI.hit_effect, update_visibility)
ui.set_callback(UI.hit_effect_style, update_visibility)
ui.set_callback(UI.hit_effect_glow, update_visibility)
ui.set_callback(UI.scope, function() update_visibility() end)
ui.set_callback(UI.scope_style, update_visibility)
ui.set_callback(UI.tracers, function() update_visibility() end)
ui.set_callback(UI.tracers_style, update_visibility)
ui.set_callback(UI.tracers_glow, update_visibility)
ui.set_callback(UI.trails, update_visibility)
ui.set_callback(UI.trails_style, update_visibility)
ui.set_callback(UI.trails_glow, update_visibility)
ui.set_callback(UI.grenade_trail, update_visibility)
ui.set_callback(UI.grenade_trail_style, update_visibility)
ui.set_callback(UI.grenade_trail_glow, update_visibility)
ui.set_callback(UI.spectators, update_visibility)
ui.set_callback(UI.keybinds, update_visibility)
ui.set_callback(UI.indicators, update_visibility)
ui.set_callback(UI.warmup_helper, function()
    if ui.get(UI.warmup_helper) then
        handle_warmup_assistant()
    else
        restore_warmup_defaults()
    end
    update_visibility()
end)
ui.set_callback(UI.fps_boost, function()
    apply_fps_boost()
    update_visibility()
end)
ui.set_callback(UI.fps_boost_options, function()
    apply_fps_boost()
end)
ui.set_callback(UI.fog, update_visibility)
ui.set_callback(UI.fog_style, update_visibility)
ui.set_callback(UI.wall_color, update_visibility)
ui.set_callback(UI.wall_color_style, update_visibility)
ui.set_callback(UI.bloom, update_visibility)
ui.set_callback(UI.exposure, update_visibility)
ui.set_callback(UI.model_brightness, update_visibility)
ui.set_callback(UI.smooth_camera, update_visibility)
ui.set_callback(UI.smooth_camera_dynamic_fov, update_visibility)
ui.set_callback(UI.thirdperson_distance, update_visibility)
ui.set_callback(UI.autobuy_enabled, update_visibility)
ui.set_callback(UI.autobuy_cost_based, update_visibility)
ui.set_callback(UI.autobuy_grenades, function()
    limit_grenades(UI.autobuy_grenades, "grenade_cache")
    update_autobuy_commands()
end)
ui.set_callback(UI.autobuy_backup_grenades, function()
    limit_grenades(UI.autobuy_backup_grenades, "backup_grenade_cache")
end)
ui.set_callback(UI.autobuy_primary, update_autobuy_commands)
ui.set_callback(UI.autobuy_secondary, update_autobuy_commands)
ui.set_callback(UI.autobuy_utilities, update_autobuy_commands)
ui.set_callback(UI.autobuy_backup_primary, update_autobuy_commands)
ui.set_callback(UI.autobuy_backup_secondary, update_autobuy_commands)
ui.set_callback(UI.autobuy_backup_utilities, update_autobuy_commands)
ui.set_callback(UI.model_changer, update_visibility)
ui.set_callback(UI.model_changer_mode, update_visibility)
ui.set_callback(UI.hit_sound, update_visibility)
ui.set_callback(UI.death_sound, update_visibility)
ui.set_callback(UI.viewmodel_changer, update_visibility)
ui.set_callback(UI.console_color, update_visibility)
ui.set_callback(UI.aspect_ratio_enabled, update_visibility)
ui.set_callback(UI.trashtalk_enabled, update_visibility)


ui.set_callback(UI.trashtalk_add, function()
    trashtalk_state.editing = true
    trashtalk_state.edit_index = nil
    trashtalk_state.message_count = 1
    ui.set(UI.trashtalk_phrase_text, "")
    ui.set(UI.trashtalk_phrase_text2, "")
    ui.set(UI.trashtalk_phrase_text3, "")
    ui.set(UI.trashtalk_on_kill, true)
    ui.set(UI.trashtalk_on_death, false)
    ui.set(UI.trashtalk_delay, 5)
    update_visibility()
end)

ui.set_callback(UI.trashtalk_edit, function()
    local selected = ui.get(UI.trashtalk_list) + 1
    if selected > 0 and selected <= #trashtalk.phrases then
        trashtalk_state.editing = true
        trashtalk_state.edit_index = selected
        local phrase = trashtalk.phrases[selected]
        ui.set(UI.trashtalk_phrase_text, phrase.text)
        ui.set(UI.trashtalk_phrase_text2, phrase.messages[1] or "")
        ui.set(UI.trashtalk_phrase_text3, phrase.messages[2] or "")
        ui.set(UI.trashtalk_on_kill, phrase.on_kill)
        ui.set(UI.trashtalk_on_death, phrase.on_death)
        ui.set(UI.trashtalk_delay, (phrase.delay or 0.5) * 10)
        
        trashtalk_state.message_count = 1
        if phrase.messages and #phrase.messages > 0 then
            trashtalk_state.message_count = #phrase.messages + 1
        end
        
        update_visibility()
    end
end)

ui.set_callback(UI.trashtalk_remove, function()
    local selected = ui.get(UI.trashtalk_list) + 1
    if selected > 0 and selected <= #trashtalk.phrases then
        table.remove(trashtalk.phrases, selected)
        save_trashtalk_phrases()
        update_trashtalk_list()
    end
end)

ui.set_callback(UI.trashtalk_reset, function()
    trashtalk.phrases = {}
    for i = 1, #trashtalk_default_phrases do
        local default_messages = {}
        for j = 1, #trashtalk_default_phrases[i].messages do
            default_messages[j] = trashtalk_default_phrases[i].messages[j]
        end
        
        trashtalk.phrases[i] = {
            text = trashtalk_default_phrases[i].text,
            messages = default_messages,
            on_kill = trashtalk_default_phrases[i].on_kill,
            on_death = trashtalk_default_phrases[i].on_death,
            delay = trashtalk_default_phrases[i].delay
        }
    end
    trashtalk.kill_pool = {}
    trashtalk.death_pool = {}
    save_trashtalk_phrases()
    update_trashtalk_list()
end)

ui.set_callback(UI.trashtalk_add_message, function()
    if trashtalk_state.message_count < 3 then
        trashtalk_state.message_count = trashtalk_state.message_count + 1
        update_visibility()
    end
end)

ui.set_callback(UI.trashtalk_remove_message, function()
    if trashtalk_state.message_count > 1 then
        
        if trashtalk_state.message_count == 3 then
            ui.set(UI.trashtalk_phrase_text3, "")
        elseif trashtalk_state.message_count == 2 then
            ui.set(UI.trashtalk_phrase_text2, "")
        end
        trashtalk_state.message_count = trashtalk_state.message_count - 1
        update_visibility()
    end
end)

ui.set_callback(UI.trashtalk_save, function()
    local text = ui.get(UI.trashtalk_phrase_text)
    if text ~= "" then
        local messages = {}
        
        if trashtalk_state.message_count >= 2 then
            local text2 = ui.get(UI.trashtalk_phrase_text2)
            if text2 ~= "" then
                messages[#messages + 1] = text2
            end
        end
        
        if trashtalk_state.message_count >= 3 then
            local text3 = ui.get(UI.trashtalk_phrase_text3)
            if text3 ~= "" then
                messages[#messages + 1] = text3
            end
        end
        
        local phrase = {
            text = text,
            messages = messages,
            on_kill = ui.get(UI.trashtalk_on_kill),
            on_death = ui.get(UI.trashtalk_on_death),
            delay = ui.get(UI.trashtalk_delay) * 0.1
        }
        
        if trashtalk_state.edit_index then
            trashtalk.phrases[trashtalk_state.edit_index] = phrase
        else
            trashtalk.phrases[#trashtalk.phrases + 1] = phrase
        end
        
        save_trashtalk_phrases()
        update_trashtalk_list()
    end
    trashtalk_state.editing = false
    trashtalk_state.edit_index = nil
    trashtalk_state.message_count = 1
    update_visibility()
end)

ui.set_callback(UI.trashtalk_cancel, function()
    trashtalk_state.editing = false
    trashtalk_state.edit_index = nil
    trashtalk_state.message_count = 1
    update_visibility()
end)

update_trashtalk_list()
update_visibility()


local base64 = require("gamesense/base64")
local clipboard_lib = require("gamesense/clipboard")

-- ===== startup sound: download an mp3 from GitHub, save it to csgo/sound and
-- play it on load (same idea as kittyhook's GitHub file loader / rinnegan's
-- startup sound). Wrapped in a do-block so no chunk-level locals are added. =====
do
    local SOUND_FILE = "8559825291_1.mp3"
    -- readfile / writefile are rooted at the game root, so csgo/sound/<file>
    -- maps to  ...\csgo legacy\csgo\sound\<file>
    local SOUND_DISK = "csgo/sound/" .. SOUND_FILE
    -- Surface_PlaySound is rooted at csgo/sound, so it just needs the file name
    local SOUND_PLAY = SOUND_FILE
    -- raw GitHub URL (github.com/.../blob/<ref>/<path>  ->  raw.githubusercontent.com/.../<ref>/<path>)
    local SOUND_URL  = "https://raw.githubusercontent.com/DOOMSLAYERGG/necrotool/claude/necrotool-keybind-style-sbmkhz/content/" .. SOUND_FILE

    local http_ok, http = pcall(require, "gamesense/http")
    if not http_ok then http = nil end

    local function play()
        pcall(native_Surface_PlaySound, SOUND_PLAY)
    end

    local function have_file()
        local ok, data = pcall(readfile, SOUND_DISK)
        return ok and data ~= nil and #data > 0
    end

    if have_file() then
        -- already downloaded on a previous launch -> just play it
        play()
    elseif http then
        -- fetch from GitHub, write it into csgo/sound, then play
        http.get(SOUND_URL, function(success, response)
            if success and response and response.body and #response.body > 0
                and (response.status == nil or response.status == 200) then
                pcall(writefile, SOUND_DISK, response.body)
                play()
            end
        end)
    end
end

local function update_config_list()
    local names = {}
    for i = 1, #config_system.configs do
        names[i] = config_system.configs[i]
    end
    ui.update(UI.config_list, names)
end

local function serialize_value(v, depth)
    depth = depth or 0
    if depth > 10 then return "nil" end 
    
    if type(v) == "table" then
        local items = {}
        for k, val in pairs(v) do
            items[#items + 1] = tostring(k) .. ":" .. serialize_value(val, depth + 1)
        end
        return "{" .. table.concat(items, ",") .. "}"
    elseif type(v) == "boolean" then
        return v and "true" or "false"
    elseif type(v) == "number" then
        return "n" .. tostring(v)
    elseif type(v) == "string" then
        return "s" .. v
    else
        return "nil"
    end
end

local function deserialize_value(str)
    if not str or str == "" or str == "nil" then
        return nil
    end
    
    if str == "true" then
        return true
    elseif str == "false" then
        return false
    elseif str:sub(1, 1) == "n" then
        return tonumber(str:sub(2))
    elseif str:sub(1, 1) == "s" then
        return str:sub(2)
    elseif str:sub(1, 1) == "{" and str:sub(-1) == "}" then
        local result = {}
        local content = str:sub(2, -2)
        if content ~= "" then
            local depth = 0
            local current = ""
            local items = {}
            
            for i = 1, #content do
                local char = content:sub(i, i)
                if char == "{" then
                    depth = depth + 1
                    current = current .. char
                elseif char == "}" then
                    depth = depth - 1
                    current = current .. char
                elseif char == "," and depth == 0 then
                    items[#items + 1] = current
                    current = ""
                else
                    current = current .. char
                end
            end
            
            if current ~= "" then
                items[#items + 1] = current
            end
            
            for _, item in ipairs(items) do
                local key, val = item:match("([^:]+):(.+)")
                if key and val then
                    local num_key = tonumber(key)
                    result[num_key or key] = deserialize_value(val)
                end
            end
        end
        return result
    end
    
    return str
end

local function serialize_table(tbl)
    local result = {}
    for k, v in pairs(tbl) do
        result[#result + 1] = tostring(k) .. "=" .. serialize_value(v)
    end
    return table.concat(result, "|")
end

local function deserialize_table(str)
    if not str or str == "" then return {} end
    
    local result = {}
    local depth = 0
    local current = ""
    local pairs_list = {}
    
    for i = 1, #str do
        local char = str:sub(i, i)
        if char == "{" then
            depth = depth + 1
            current = current .. char
        elseif char == "}" then
            depth = depth - 1
            current = current .. char
        elseif char == "|" and depth == 0 then
            pairs_list[#pairs_list + 1] = current
            current = ""
        else
            current = current .. char
        end
    end
    
    if current ~= "" then
        pairs_list[#pairs_list + 1] = current
    end
    
    for _, pair in ipairs(pairs_list) do
        local key, val = pair:match("([^=]+)=(.+)")
        if key and val then
            result[key] = deserialize_value(val)
        end
    end
    
    return result
end

local function get_all_settings()
    local settings = {}
    
    for key, ref in pairs(UI) do
        if key ~= "config_name" and key ~= "config_list" and key ~= "config_save" and 
           key ~= "config_load" and key ~= "config_delete" and key ~= "config_export" and 
           key ~= "config_import" and key ~= "tab" then
            
            local success, r, g, b, a = pcall(ui.get, ref)
            if success then
                -- Автоопределение color picker по СИГНАТУРЕ возврата (4 числа),
                -- а не по жёстко прописанному списку имён. Это гарантирует, что
                -- ЛЮБОЙ новый color picker, добавленный в будущем, будет сохраняться
                -- автоматически, без необходимости вручную дописывать его в список.
                if type(r) == "number" and type(g) == "number" and type(b) == "number" and type(a) == "number" then
                    settings[key] = {r, g, b, a}
                else
                    settings[key] = r
                end
            end
        end
    end
    
    
    settings.trashtalk_phrases = trashtalk.phrases
    
    return settings
end

local function apply_settings(settings)
    if not settings then return false end
    
    for key, value in pairs(settings) do
        if key == "trashtalk_phrases" then
            trashtalk.phrases = value
            trashtalk.kill_pool = {}
            trashtalk.death_pool = {}
            save_trashtalk_phrases()
            update_trashtalk_list()
        elseif UI[key] then
            
            if type(value) == "table" then
                local is_color = true
                local count = 0
                for i = 1, 4 do
                    if type(value[i]) ~= "number" then
                        is_color = false
                        break
                    end
                    count = count + 1
                end
                
                if is_color and count == 4 then
                    pcall(ui.set, UI[key], value[1], value[2], value[3], value[4])
                else
                    -- Мультиселекты в разных сборках gamesense принимают либо таблицу
                    -- целиком, либо распакованный список аргументов. Пробуем оба варианта,
                    -- чтобы значение реально применилось независимо от точной сигнатуры API.
                    local ok = pcall(ui.set, UI[key], value)
                    if not ok then
                        pcall(ui.set, UI[key], table.unpack(value))
                    end
                end
            else
                pcall(ui.set, UI[key], value)
            end
        end
    end
    
    return true
end

ui.set_callback(UI.config_save, function()
    local name = ui.get(UI.config_name)
    if name == "" then
        return
    end
    
    local settings = get_all_settings()
    database.write("uwu_config_" .. name, settings)
    
    
    local exists = false
    for i = 1, #config_system.configs do
        if config_system.configs[i] == name then
            exists = true
            break
        end
    end
    
    if not exists then
        config_system.configs[#config_system.configs + 1] = name
        save_config_list()
    end
    
    update_config_list()
    ui.set(UI.config_status, "\aFFFFFFFF  ♡ Config saved")
end)

ui.set_callback(UI.config_load, function()
    local selected = ui.get(UI.config_list) + 1
    if selected < 1 or selected > #config_system.configs then
        return
    end
    
    local name = config_system.configs[selected]
    local settings = database.read("uwu_config_" .. name)
    
    if not settings then
        return
    end
    
    apply_settings(settings)
    update_visibility()
    ui.set(UI.config_status, "\aFFFFFFFF  ♡ Config loaded")
end)

ui.set_callback(UI.config_delete, function()
    local selected = ui.get(UI.config_list) + 1
    if selected < 1 or selected > #config_system.configs then
        return
    end
    
    local name = config_system.configs[selected]
    table.remove(config_system.configs, selected)
    save_config_list()
    update_config_list()
    ui.set(UI.config_status, "\aFFFFFFFF  ♡ Config deleted")
end)

ui.set_callback(UI.config_export, function()
    local settings = get_all_settings()
    local serialized = serialize_table(settings)
    local encoded = base64.encode(serialized, "base64")
    clipboard_lib.set(encoded)
    ui.set(UI.config_status, "\aFFFFFFFF  ♡ Copied to clipboard")
end)

ui.set_callback(UI.config_import, function()
    local clipboard_text = clipboard_lib.get()
    
    if not clipboard_text or clipboard_text == "" then
        return
    end
    
    local success, decoded = pcall(base64.decode, clipboard_text, "base64")
    
    if not success or not decoded then
        return
    end
    
    local settings = deserialize_table(decoded)
    apply_settings(settings)
    update_visibility()
    ui.set(UI.config_status, "\aFFFFFFFF  ♡ Imported from clipboard")
end)

update_config_list()

local function hsv_to_rgb(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v*255, t*255, p*255
    elseif i == 1 then return q*255, v*255, p*255
    elseif i == 2 then return p*255, v*255, t*255
    elseif i == 3 then return p*255, q*255, v*255
    elseif i == 4 then return t*255, p*255, v*255
    else return v*255, p*255, q*255 end
end

local rainbow_hue = 0

-- ===== startup intro image =====
-- Downloads content/intro.png from GitHub into csgo/materials
-- (…\csgo legacy\csgo\materials) and shows it as the intro. The image is drawn
-- at its native pixel size (only downscaled if it would not fit the screen,
-- never upscaled) so it is never degraded in quality.
local intro_animation = {
    active     = true,
    spawn      = globals.realtime(),  -- when the script loaded (download timeout)
    start_time = nil,                 -- set once the image is decoded and ready
    duration   = 3.0,
    image      = nil,
    img_w      = 0,
    img_h      = 0
}

do
    local http_ok, http = pcall(require, "gamesense/http")
    if not http_ok then http = nil end

    local INTRO_FILE = "intro.png"
    -- writefile / readfile are rooted at the game root, so csgo/materials/<file>
    -- maps to  ...\csgo legacy\csgo\materials\<file>
    local INTRO_DISK = "csgo/materials/" .. INTRO_FILE
    local INTRO_URL  = "https://raw.githubusercontent.com/DOOMSLAYERGG/necrotool/claude/necrotool-keybind-style-sbmkhz/content/" .. INTRO_FILE

    local function set_image(bytes)
        if not bytes or #bytes == 0 then
            intro_animation.active = false
            return
        end
        -- read the native resolution straight from the PNG IHDR header so we can
        -- draw it 1:1 (no scaling -> no quality loss)
        if #bytes >= 24 then
            local function u32(o)
                return bytes:byte(o) * 16777216 + bytes:byte(o + 1) * 65536
                     + bytes:byte(o + 2) * 256 + bytes:byte(o + 3)
            end
            intro_animation.img_w = u32(17)
            intro_animation.img_h = u32(21)
        end
        local ok, img = pcall(images.load_png, bytes)
        if ok and img then
            intro_animation.image = img
            intro_animation.start_time = globals.realtime()
        else
            intro_animation.active = false
        end
    end

    local ok, data = pcall(readfile, INTRO_DISK)
    if ok and data and #data > 0 then
        set_image(data)                                 -- already on disk
    elseif http then
        http.get(INTRO_URL, function(success, response)
            if success and response and response.body and #response.body > 0
                and (response.status == nil or response.status == 200) then
                pcall(writefile, INTRO_DISK, response.body)
                set_image(response.body)
            else
                intro_animation.active = false
            end
        end)
    else
        intro_animation.active = false                  -- no http library, nothing to show
    end
end

local function draw_intro_animation()
    if not intro_animation.active then return end

    -- still downloading / decoding: wait, but never block paint forever
    if not intro_animation.image or not intro_animation.start_time then
        if globals.realtime() - intro_animation.spawn > 6.0 then
            intro_animation.active = false
        end
        return
    end

    local elapsed = globals.realtime() - intro_animation.start_time
    if elapsed > intro_animation.duration then
        intro_animation.active = false
        return
    end

    local screen_x, screen_y = client.screen_size()

    -- fade in over 0.4s, fade out over the last 0.5s
    local fade = 1
    if elapsed < 0.4 then
        fade = elapsed / 0.4
    elseif elapsed > intro_animation.duration - 0.5 then
        fade = (intro_animation.duration - elapsed) / 0.5
    end
    if fade < 0 then fade = 0 elseif fade > 1 then fade = 1 end

    -- dark backdrop
    renderer.rectangle(0, 0, screen_x, screen_y, 5, 3, 10, 220 * fade)

    -- a bit smaller than native; fit within ~72% of the screen and cap at 0.85
    -- so it always downscales (never upscales -> no quality loss)
    local w, h = intro_animation.img_w, intro_animation.img_h
    if w <= 0 or h <= 0 then w, h = 512, 512 end
    local max_w, max_h = screen_x * 0.42, screen_y * 0.42
    local scale = math.min(max_w / w, max_h / h, 0.5)
    local dw, dh = math.floor(w * scale + 0.5), math.floor(h * scale + 0.5)
    local x = math.floor((screen_x - dw) / 2)
    local y = math.floor((screen_y - dh) / 2)

    -- intro.png has ~115px of transparent padding top & bottom (canvas 360px,
    -- visible content only rows 115..244), so hug the glow to the VISIBLE
    -- content box, not the full canvas, otherwise it floats far above/below it.
    local cx = x
    local cw = dw
    local cy = y + math.floor(dh * (115 / 360) + 0.5)
    local ch = math.max(1, math.floor(dh * (130 / 360) + 0.5))

    -- animated soft glow hugging the content border, colour taken from
    -- intro.png's palette. It "breathes" (pulsing intensity/spread) and gently
    -- shimmers between the image's two palette purples (172,62,228 <-> 203,151,216).
    local gtime = globals.realtime()
    local pulse = 0.5 + 0.5 * math.sin(gtime * 3.0)          -- breathing 0..1
    local mix   = 0.5 + 0.5 * math.sin(gtime * 1.4)          -- colour shimmer 0..1
    local GR = math.floor(172 + (203 - 172) * mix)
    local GG = math.floor( 62 + (151 -  62) * mix)
    local GB = math.floor(228 + (216 - 228) * mix)

    -- tight soft halo: short spread with a quadratic falloff so most of the
    -- brightness sits right against the content border
    local glow_layers = 18
    local glow_spread = 2.1 + 0.6 * pulse                    -- medium, breathing reach
    local glow_th = glow_spread + 1.5
    local halo_a = (110 + 90 * pulse) * fade                 -- clearly visible
    for i = glow_layers, 1, -1 do
        local s = i * glow_spread
        local t = i / glow_layers
        local a = halo_a * (1 - t) * (1 - t)
        local rx, ry = cx - s, cy - s
        local rw, rh = cw + s * 2, ch + s * 2
        renderer.rectangle(rx, ry, rw, glow_th, GR, GG, GB, a)                                   -- top
        renderer.rectangle(rx, ry + rh - glow_th, rw, glow_th, GR, GG, GB, a)                    -- bottom
        renderer.rectangle(rx, ry + glow_th, glow_th, rh - glow_th * 2, GR, GG, GB, a)           -- left
        renderer.rectangle(rx + rw - glow_th, ry + glow_th, glow_th, rh - glow_th * 2, GR, GG, GB, a) -- right
    end

    -- crisp bright rim right on the content border (pulses with the breathing)
    local rim_a = math.min(255, (150 + 95 * pulse) * fade)
    renderer.rectangle(cx - 1, cy - 1, cw + 2, 2, GR, GG, GB, rim_a)             -- top
    renderer.rectangle(cx - 1, cy + ch - 1, cw + 2, 2, GR, GG, GB, rim_a)        -- bottom
    renderer.rectangle(cx - 1, cy + 1, 2, ch - 2, GR, GG, GB, rim_a)            -- left
    renderer.rectangle(cx + cw - 1, cy + 1, 2, ch - 2, GR, GG, GB, rim_a)       -- right

    pcall(function()
        intro_animation.image:draw(x, y, dw, dh, 255, 255, 255, math.floor(255 * fade), false, "f")
    end)
end

local c_entity = require 'gamesense/entity'

local smooth_animation = {
    anim_data = {
        layers = {},
        server_anim_states = {},
        last_spawn_time = 0
    }
}

for i = 0, 15 do
    smooth_animation.anim_data.layers[i] = { cycle = 0, weight = 0 }
end

local smooth_camera = {
    last_pitch = 0,
    last_yaw = 0,
    last_target_pitch = 0,
    last_target_yaw = 0,
    pitch_velocity = 0,
    yaw_velocity = 0,
    filtered_pitch_velocity = 0,
    filtered_yaw_velocity = 0,
    last_time = 0,
    base_fov = 90,
    current_fov = 90,
    initialized = false
}

local sqrt = math.sqrt
local min = math.min
local max = math.max

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function smooth_animation_setup_command(cmd)
    if not ui.get(UI.enabled) or not ui.get(UI.smooth_animation) then
        return
    end
    
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then
        return
    end
    
    local spawn_time = entity.get_prop(me, "m_flSpawnTime")
    if smooth_animation.anim_data.last_spawn_time ~= spawn_time then
        smooth_animation.anim_data.server_anim_states = {}
        smooth_animation.anim_data.last_spawn_time = spawn_time
    end
    
    local self_index = c_entity.new(me)
    local anim_state = self_index:get_anim_state()
    if not anim_state then return end
    
    local sim_time = globals.curtime()
    
    local vel_x, vel_y = entity.get_prop(me, "m_vecVelocity")
    local velocity = sqrt(vel_x * vel_x + vel_y * vel_y)
    local duck_amount = entity.get_prop(me, "m_flDuckAmount")
    local ducking = entity.get_prop(me, "m_bDucking") == 1
    local on_ground = bit.band(entity.get_prop(me, "m_fFlags"), 1) == 1
    local current_weapon = entity.get_player_weapon(me)
    
    if velocity < 0.1 then
        velocity = 0
    end
    
    local server_state = {
        time = sim_time,
        layers = {},
        velocity = velocity,
        duck_amount = duck_amount,
        ducking = ducking,
        on_ground = on_ground,
        weapon = current_weapon,
    }
    
    for layer_idx = 0, 15 do
        local layer = self_index:get_anim_overlay(layer_idx)
        if layer then
            server_state.layers[layer_idx] = {
                cycle = layer.cycle,
                weight = layer.weight,
            }
        end
    end
    
    table.insert(smooth_animation.anim_data.server_anim_states, server_state)
    
    local current_time = globals.curtime()
    while #smooth_animation.anim_data.server_anim_states > 0 and current_time - smooth_animation.anim_data.server_anim_states[1].time > 0.5 do
        table.remove(smooth_animation.anim_data.server_anim_states, 1)
    end
    
    if #smooth_animation.anim_data.server_anim_states > 32 then
        table.remove(smooth_animation.anim_data.server_anim_states, 1)
    end
end

local function smooth_animation_pre_render()
    if not ui.get(UI.enabled) or not ui.get(UI.smooth_animation) then
        return
    end
    
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then
        return
    end
    
    local self_index = c_entity.new(me)
    local anim_state = self_index:get_anim_state()
    if not anim_state then return end
    
    local interpolation_delay = 0.1
    local current_time = globals.curtime() - interpolation_delay
    local server_states = smooth_animation.anim_data.server_anim_states
    
    if #server_states < 2 then
        return
    end
    
    local state1, state2
    for i = #server_states - 1, 1, -1 do
        if server_states[i].time <= current_time and server_states[i+1].time >= current_time then
            state1 = server_states[i]
            state2 = server_states[i+1]
            break
        end
    end
    
    if not state1 or not state2 then
        state1 = server_states[#server_states - 1]
        state2 = server_states[#server_states]
    end
    
    local delta = state2.time - state1.time
    if delta <= 0 then
        return
    end
    
    local t = (current_time - state1.time) / delta
    t = max(0, min(1, t))
    
    if state1.velocity and state2.velocity and math.abs(state2.velocity - state1.velocity) > 250 then
        smooth_animation.anim_data.server_anim_states = {}
        return
    end
    
    local overlays = {}
    for i = 0, 15 do
        overlays[i] = self_index:get_anim_overlay(i)
    end
    
    for layer_idx = 0, 15 do
        local layer = overlays[layer_idx]
        if layer and state1.layers[layer_idx] and state2.layers[layer_idx] then
            local cycle1 = state1.layers[layer_idx].cycle
            local cycle2 = state2.layers[layer_idx].cycle
            local weight1 = state1.layers[layer_idx].weight
            local weight2 = state2.layers[layer_idx].weight
            
            if math.abs(cycle2 - cycle1) > 0.5 then
                if cycle2 > cycle1 then
                    cycle1 = cycle1 + 1
                else
                    cycle2 = cycle2 + 1
                end
            end
            
            if (layer_idx == 1 or layer_idx == 2) and state1.weapon ~= state2.weapon then
                layer.cycle = cycle2 % 1
                layer.weight = weight2
            else
                layer.cycle = (lerp(cycle1, cycle2, t)) % 1
                layer.weight = lerp(weight1, weight2, t)
            end
            
            layer.weight = max(0, min(1, layer.weight))
        end
    end
end

local function normalize_angle(angle)
    while angle > 180 do
        angle = angle - 360
    end
    while angle < -180 do
        angle = angle + 360
    end
    return angle
end

local function angle_diff(a, b)
    local delta = (a - b) % 360
    if delta > 180 then delta = delta - 360 end
    return delta
end

local function lerp_angle(current, target, t)
    return current + angle_diff(target, current) * t
end

local function apply_easing(t, easing_type)
    if easing_type == "Linear" then
        return t
    elseif easing_type == "Exponential" then
        return 1 - math.exp(-t * 5)
    elseif easing_type == "Smoothstep" then
        return t * t * (3 - 2 * t)
    elseif easing_type == "Sigmoid" then
        return 1 / (1 + math.exp(-10 * (t - 0.5)))
    end
    return t
end

local function clamp_prediction(value, max_change)
    if value > max_change then
        return max_change
    elseif value < -max_change then
        return -max_change
    end
    return value
end

local function smooth_camera_movement(view)
    if not ui.get(UI.enabled) or not ui.get(UI.smooth_camera) then
        smooth_camera.initialized = false
        return
    end
    
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then
        smooth_camera.initialized = false
        return
    end
    
    local pitch = view.pitch
    local yaw = view.yaw
    local current_time = globals.curtime()
    
    if not smooth_camera.initialized then
        smooth_camera.last_pitch = pitch
        smooth_camera.last_yaw = yaw
        smooth_camera.last_target_pitch = pitch
        smooth_camera.last_target_yaw = yaw
        smooth_camera.pitch_velocity = 0
        smooth_camera.yaw_velocity = 0
        smooth_camera.filtered_pitch_velocity = 0
        smooth_camera.filtered_yaw_velocity = 0
        smooth_camera.last_time = current_time
        smooth_camera.base_fov = view.fov
        smooth_camera.current_fov = view.fov
        smooth_camera.initialized = true
        return
    end
    
    local dt = current_time - smooth_camera.last_time
    
    if dt <= 0 or dt > 0.5 then
        smooth_camera.last_target_pitch = pitch
        smooth_camera.last_target_yaw = yaw
        smooth_camera.pitch_velocity = 0
        smooth_camera.yaw_velocity = 0
        smooth_camera.filtered_pitch_velocity = 0
        smooth_camera.filtered_yaw_velocity = 0
        smooth_camera.last_time = current_time
        smooth_camera.last_pitch = pitch
        smooth_camera.last_yaw = yaw
        return
    end
    
    local pitch_diff = pitch - smooth_camera.last_target_pitch
    local yaw_diff = angle_diff(yaw, smooth_camera.last_target_yaw)
    
    smooth_camera.pitch_velocity = pitch_diff / dt
    smooth_camera.yaw_velocity = yaw_diff / dt
    
    local velocity_filter = ui.get(UI.smooth_camera_velocity_filter) * 0.01
    smooth_camera.filtered_pitch_velocity = smooth_camera.filtered_pitch_velocity + (smooth_camera.pitch_velocity - smooth_camera.filtered_pitch_velocity) * (1 - velocity_filter)
    smooth_camera.filtered_yaw_velocity = smooth_camera.filtered_yaw_velocity + (smooth_camera.yaw_velocity - smooth_camera.filtered_yaw_velocity) * (1 - velocity_filter)
    
    smooth_camera.last_target_pitch = pitch
    smooth_camera.last_target_yaw = yaw
    smooth_camera.last_time = current_time
    
    local extrapolation_ms = ui.get(UI.smooth_camera_extrapolation)
    local prediction_time = extrapolation_ms / 1000.0
    
    local predicted_pitch = pitch
    local predicted_yaw = yaw
    
    if extrapolation_ms > 0 then
        local pitch_prediction = smooth_camera.filtered_pitch_velocity * prediction_time
        local yaw_prediction = smooth_camera.filtered_yaw_velocity * prediction_time
        
        local prediction_clamp = ui.get(UI.smooth_camera_prediction_clamp)
        pitch_prediction = clamp_prediction(pitch_prediction, prediction_clamp)
        yaw_prediction = clamp_prediction(yaw_prediction, prediction_clamp)
        
        predicted_pitch = pitch + pitch_prediction
        predicted_yaw = yaw + yaw_prediction
    end
    
    local pitch_speed = ui.get(UI.smooth_camera_pitch_speed) * 0.01
    local yaw_speed = ui.get(UI.smooth_camera_yaw_speed) * 0.01
    
    local easing_type = ui.get(UI.smooth_camera_easing)
    pitch_speed = apply_easing(pitch_speed, easing_type)
    yaw_speed = apply_easing(yaw_speed, easing_type)
    
    local velocity_magnitude = math.sqrt(smooth_camera.filtered_pitch_velocity * smooth_camera.filtered_pitch_velocity + smooth_camera.filtered_yaw_velocity * smooth_camera.filtered_yaw_velocity)
    
    if velocity_magnitude > 100 then
        local adaptive_factor = math.min(1.5, 1 + (velocity_magnitude - 100) / 500)
        pitch_speed = pitch_speed * adaptive_factor
        yaw_speed = yaw_speed * adaptive_factor
    elseif velocity_magnitude < 10 then
        pitch_speed = pitch_speed * 0.5
        yaw_speed = yaw_speed * 0.5
    end
    
    smooth_camera.last_pitch = smooth_camera.last_pitch + (predicted_pitch - smooth_camera.last_pitch) * pitch_speed
    smooth_camera.last_yaw = lerp_angle(smooth_camera.last_yaw, predicted_yaw, yaw_speed)
    
    view.yaw = smooth_camera.last_yaw
    view.pitch = math.max(-89, math.min(89, smooth_camera.last_pitch))
    
    if ui.get(UI.smooth_camera_dynamic_fov) then
        local fov_intensity = ui.get(UI.smooth_camera_fov_intensity)
        local target_fov = smooth_camera.base_fov + (velocity_magnitude / 500) * fov_intensity
        target_fov = math.min(smooth_camera.base_fov + fov_intensity, target_fov)
        smooth_camera.current_fov = smooth_camera.current_fov + (target_fov - smooth_camera.current_fov) * 0.1
        view.fov = smooth_camera.current_fov
    end
    
    local roll = ui.get(UI.smooth_camera_roll)
    if roll ~= 0 then
        view.roll = roll
    end
end

local function apply_changer_view_settings(view)
    if not ui.get(UI.enabled) then
        return
    end
    
    if ui.get(UI.fov_override_enabled) then
        view.fov = ui.get(UI.fov_override)
    end
end

local function override_view_handler(view)
    smooth_camera_movement(view)
    apply_changer_view_settings(view)
end

local function handle_fog()
    if not ui.get(UI.fog) or not ui.get(UI.enabled) then
        client.set_cvar('fog_override', '0')
        return
    end
    
    client.set_cvar('fog_override', '1')
    
    local fog_style = ui.get(UI.fog_style)
    local r, g, b
    
    if fog_style == "Rainbow" then
        r, g, b = hsv_to_rgb(rainbow_hue, 0.8, 1.0)
    else
        r, g, b = ui.get(UI.fog_color)
    end
    
    client.set_cvar('fog_color', string.format('%d %d %d', r, g, b))
    client.set_cvar('fog_start', ui.get(UI.fog_start))
    client.set_cvar('fog_end', ui.get(UI.fog_end))
    client.set_cvar('fog_maxdensity', ui.get(UI.fog_density) / 100)
end

ui.set_callback(UI.fog_style, function()
    update_visibility()
    handle_fog()
end)
ui.set_callback(UI.fog, function()
    update_visibility()
    handle_fog()
end)
ui.set_callback(UI.fog_color, handle_fog)
ui.set_callback(UI.fog_start, handle_fog)
ui.set_callback(UI.fog_end, handle_fog)
ui.set_callback(UI.fog_density, handle_fog)
ui.set_callback(UI.enabled, function()
    update_visibility()
    handle_fog()
end)

client.set_event_callback("shutdown", function()
    client.set_cvar('fog_override', '0')
    if state.default_skyname ~= nil then
        load_name_sky(state.default_skyname)
    end
end)

handle_fog()

local function update_skybox()
    if state.default_skyname == nil then
        state.default_skyname = cvars.sv_skyname:get_string()
    end
    
    if not ui.get(UI.skybox) or not ui.get(UI.enabled) then
        load_name_sky(state.default_skyname)
        return
    end
    
    local name = skybox_names[ui.get(UI.skybox_list) + 1]
    load_name_sky(skybox_list[name])
end

local function update_skybox_color()
    local enabled = ui.get(UI.skybox) and ui.get(UI.enabled)
    
    if entity.get_local_player() == nil then return end
    
    if enabled then
        local skybox_style = ui.get(UI.skybox_style)
        local brightness = ui.get(UI.skybox_brightness) * 0.01
        local color_strength = ui.get(UI.skybox_color_strength) * 0.01
        
        local r, g, b, a
        
        if skybox_style == "Rainbow" then
            r, g, b = hsv_to_rgb(rainbow_hue, 0.7, 1.0)
            a = 255
        else
            r, g, b, a = ui.get(UI.skybox_color)
        end
        
        local final_r = (r * color_strength) * brightness
        local final_g = (g * color_strength) * brightness
        local final_b = (b * color_strength) * brightness
        
        final_r = math.min(255, final_r)
        final_g = math.min(255, final_g)
        final_b = math.min(255, final_b)
        
        local skybox_materials = materialsystem.find_materials("skybox/")
        for i=1, #skybox_materials do
            skybox_materials[i]:color_modulate(final_r, final_g, final_b)
            skybox_materials[i]:alpha_modulate(a)
        end
    else
        local skybox_materials = materialsystem.find_materials("skybox/")
        for i=1, #skybox_materials do
            skybox_materials[i]:color_modulate(255, 255, 255)
            skybox_materials[i]:alpha_modulate(255)
        end
    end
end

ui.set_callback(UI.skybox, function()
    update_visibility()
    update_skybox()
    update_skybox_color()
end)
ui.set_callback(UI.skybox_list, update_skybox)
ui.set_callback(UI.skybox_style, function()
    update_visibility()
    update_skybox_color()
end)
ui.set_callback(UI.skybox_color, update_skybox_color)
ui.set_callback(UI.skybox_brightness, update_skybox_color)
ui.set_callback(UI.skybox_color_strength, update_skybox_color)
ui.set_callback(UI.skybox_remove_3d, function()
    local remove_3d = ui.get(UI.skybox_remove_3d)
    cvars.r_3dsky:set_raw_int(remove_3d and 0 or 1)
end)

ui.set_callback(UI.fov_override_enabled, update_visibility)

client.set_event_callback("player_connect_full", function(event)
    if client.userid_to_entindex(event.userid) == entity.get_local_player() then
        state.default_skyname = nil
        update_skybox()
        update_skybox_color()
    end
end)

update_skybox()
update_skybox_color()

local notifications = {}
local notification_colors = {
    hit = {255, 182, 220, 255},
    miss = {255, 150, 180, 255},
    damage = {255, 200, 230, 255},
    hurt = {255, 140, 200, 255},
    death = {255, 100, 150, 255},
    background = {15, 10, 15, 230},
    border = {255, 120, 220, 255},
    accent1 = {255, 182, 220, 255},
    accent2 = {202, 70, 205, 255}
}

local function add_notification(text, type_name, duration)
    local limit = ui.get(UI.notify_limit)
    local dur = duration or ui.get(UI.notify_duration)
    if #notifications >= limit then
        table.remove(notifications, 1)
    end
    table.insert(notifications, {
        text = text,
        type = type_name or "hit",
        time = globals.realtime(),
        duration = dur,
        alpha = 0,
        y_offset = 0,
        glow_alpha = 0
    })
end

local function contains(tbl, val)
    for i = 1, #tbl do
        if tbl[i] == val then
            return true
        end
    end
    return false
end

local function draw_notifications()
    if not ui.get(UI.enabled) or not ui.get(UI.notifications) then return end
    
    local style = ui.get(UI.notify_style)
    local size = ui.get(UI.notify_size)
    local screen_x, screen_y = client.screen_size()
    
    local size_mult = 1.0
    local spacing = 40
    if size == "Small" then
        size_mult = 0.85
        spacing = 32
    elseif size == "Big" then
        size_mult = 1.2
        spacing = 60
    end
    
    for i = #notifications, 1, -1 do
        local notif = notifications[i]
        local time_alive = globals.realtime() - notif.time
        if time_alive > notif.duration then
            table.remove(notifications, i)
        end
    end
    
    if #notifications == 0 then return end
    
    if style == "Old" then
        local start_y = screen_y - 100
        
        local font_flags = "c"
        if size == "Medium" then font_flags = "bc"
        elseif size == "Big" then font_flags = "+bc" end
        
        for i = 1, #notifications do
            local notif = notifications[i]
            local time_alive = globals.realtime() - notif.time
            
            if time_alive < 0.2 then
                notif.alpha = (time_alive / 0.2) * 255
            elseif time_alive > notif.duration - 0.4 then
                notif.alpha = ((notif.duration - time_alive) / 0.4) * 255
            else
                notif.alpha = 255
            end
            
            local target_y = start_y - (i - 1) * spacing
            notif.y_offset = notif.y_offset + (target_y - notif.y_offset) * globals.frametime() * 12
            
            local color = notification_colors[notif.type] or notification_colors.hit
            local text_w, text_h = renderer.measure_text(font_flags, notif.text)
            local time_offset = globals.realtime() * 2
            
            local slide_x = screen_x / 2
            
            local bar_w = text_w + 20
            local bar_x = slide_x - bar_w / 2
            renderer.gradient(bar_x, notif.y_offset + text_h + 2, bar_w / 2, 2,
                color[1], color[2], color[3], notif.alpha,
                notification_colors.accent2[1], notification_colors.accent2[2], notification_colors.accent2[3], notif.alpha, true)
            renderer.gradient(bar_x + bar_w / 2, notif.y_offset + text_h + 2, bar_w / 2, 2,
                notification_colors.accent2[1], notification_colors.accent2[2], notification_colors.accent2[3], notif.alpha,
                color[1], color[2], color[3], notif.alpha, true)
            
            renderer.text(slide_x + 1, notif.y_offset + 1,
                color[1], color[2], color[3], notif.alpha * 0.25, font_flags, 0, notif.text)
            renderer.text(slide_x - 1, notif.y_offset - 1,
                color[1], color[2], color[3], notif.alpha * 0.15, font_flags, 0, notif.text)
            
            renderer.text(slide_x + 1, notif.y_offset + 1, 0, 0, 0, notif.alpha * 0.8, font_flags, 0, notif.text)
            
            renderer.text(slide_x, notif.y_offset, color[1], color[2], color[3], notif.alpha, font_flags, 0, notif.text)
        end
        
    elseif style == "New black" then
        local font_flags = "c"
        if size == "Medium" then
            font_flags = "bc"
        elseif size == "Big" then
            font_flags = "+bc"
        end
        
        local pad_x = 20
        local pad_y = 10
        if size == "Medium" then
            pad_x = 30
            pad_y = 14
        elseif size == "Big" then
            pad_x = 40
            pad_y = 18
        end

        local sample_w, sample_h = renderer.measure_text(font_flags, "A")
        local box_height = sample_h + pad_y * 2
        local actual_spacing = box_height + 12
        
        local start_y = screen_y / 2 + 200
        
        for i = 1, #notifications do
            local notif = notifications[i]
            local time_alive = globals.realtime() - notif.time
            
            if time_alive < 0.3 then
                local progress = time_alive / 0.3
                notif.alpha = progress * 255
                notif.glow_alpha = progress * 100
            elseif time_alive > notif.duration - 0.5 then
                local progress = (notif.duration - time_alive) / 0.5
                notif.alpha = progress * 255
                notif.glow_alpha = progress * 100
            else
                notif.alpha = 255
                notif.glow_alpha = 100
            end
            
            local target_y = start_y - (i - 1) * actual_spacing
            notif.y_offset = notif.y_offset + (target_y - notif.y_offset) * globals.frametime() * 12
            
            local color = notification_colors[notif.type] or notification_colors.hit
            local text_w, text_h = renderer.measure_text(font_flags, notif.text)
            
            local box_w = text_w + pad_x * 2
            local box_h = text_h + pad_y * 2
            local box_x = screen_x / 2 - box_w / 2
            local box_y = notif.y_offset
            
            for j = 1, 3 do
                local g = j * 2
                renderer.rectangle(box_x - g, box_y - g, box_w + g * 2, box_h + g * 2,
                    color[1], color[2], color[3], notif.glow_alpha / (j * 2))
            end
            
            renderer.rectangle(box_x, box_y, box_w, box_h,
                notification_colors.background[1], notification_colors.background[2], 
                notification_colors.background[3], notif.alpha * 0.9)
            
            renderer.gradient(box_x, box_y, box_w / 2, 2,
                notification_colors.accent1[1], notification_colors.accent1[2], notification_colors.accent1[3], notif.alpha,
                notification_colors.accent2[1], notification_colors.accent2[2], notification_colors.accent2[3], notif.alpha, true)
            renderer.gradient(box_x + box_w / 2, box_y, box_w / 2, 2,
                notification_colors.accent2[1], notification_colors.accent2[2], notification_colors.accent2[3], notif.alpha,
                notification_colors.accent1[1], notification_colors.accent1[2], notification_colors.accent1[3], notif.alpha, true)
            
            renderer.gradient(box_x, box_y + box_h - 2, box_w / 2, 2,
                notification_colors.accent1[1], notification_colors.accent1[2], notification_colors.accent1[3], notif.alpha * 0.6,
                notification_colors.accent2[1], notification_colors.accent2[2], notification_colors.accent2[3], notif.alpha * 0.6, true)
            renderer.gradient(box_x + box_w / 2, box_y + box_h - 2, box_w / 2, 2,
                notification_colors.accent2[1], notification_colors.accent2[2], notification_colors.accent2[3], notif.alpha * 0.6,
                notification_colors.accent1[1], notification_colors.accent1[2], notification_colors.accent1[3], notif.alpha * 0.6, true)
            
            renderer.rectangle(box_x, box_y, 2, box_h,
                notification_colors.border[1], notification_colors.border[2], notification_colors.border[3], notif.alpha)
            renderer.rectangle(box_x + box_w - 2, box_y, 2, box_h,
                notification_colors.border[1], notification_colors.border[2], notification_colors.border[3], notif.alpha)
            
            renderer.gradient(box_x + 2, box_y + 3, box_w - 4, 1,
                255, 255, 255, notif.alpha * 0.3, 255, 255, 255, 0, false)
            
            local text_y = box_y + pad_y
            renderer.text(screen_x / 2 + 1, text_y + 1, 0, 0, 0, notif.alpha * 0.8, font_flags, 0, notif.text)
            renderer.text(screen_x / 2, text_y, color[1], color[2], color[3], notif.alpha, font_flags, 0, notif.text)
        end
    else
        local font_flags = "c"
        if size == "Medium" then
            font_flags = "bc"
        elseif size == "Big" then
            font_flags = "+bc"
        end
        
        local pad_x = 20
        local pad_y = 10
        if size == "Medium" then
            pad_x = 30
            pad_y = 14
        elseif size == "Big" then
            pad_x = 40
            pad_y = 18
        end

        local sample_w, sample_h = renderer.measure_text(font_flags, "A")
        local box_height = sample_h + pad_y * 2
        local actual_spacing = box_height + 12
        
        local start_y = screen_y / 2 + 200
        
        for i = 1, #notifications do
            local notif = notifications[i]
            local time_alive = globals.realtime() - notif.time
            
            if time_alive < 0.3 then
                local progress = time_alive / 0.3
                notif.alpha = progress * 255
                notif.glow_alpha = progress * 100
            elseif time_alive > notif.duration - 0.5 then
                local progress = (notif.duration - time_alive) / 0.5
                notif.alpha = progress * 255
                notif.glow_alpha = progress * 100
            else
                notif.alpha = 255
                notif.glow_alpha = 100
            end
            
            local target_y = start_y - (i - 1) * actual_spacing
            notif.y_offset = notif.y_offset + (target_y - notif.y_offset) * globals.frametime() * 12
            
            local color = notification_colors[notif.type] or notification_colors.hit
            local text_w, text_h = renderer.measure_text(font_flags, notif.text)
            
            local box_w = text_w + pad_x * 2
            local box_h = text_h + pad_y * 2
            local box_x = screen_x / 2 - box_w / 2
            local box_y = notif.y_offset
            
            renderer.rectangle(box_x, box_y, box_w, box_h, 10, 8, 15, notif.alpha * 0.6)
            
            for j = 1, 2 do
                local glow_size = j * 1.5
                local glow_a = (30 / j) * (notif.alpha / 255)
                renderer.rectangle(box_x - glow_size, box_y - glow_size, 
                    box_w + glow_size * 2, box_h + glow_size * 2,
                    color[1], color[2], color[3], glow_a)
            end
            
            renderer.gradient(box_x, box_y, box_w / 2, 2,
                notification_colors.accent1[1], notification_colors.accent1[2], notification_colors.accent1[3], notif.alpha,
                notification_colors.accent2[1], notification_colors.accent2[2], notification_colors.accent2[3], notif.alpha, true)
            renderer.gradient(box_x + box_w / 2, box_y, box_w / 2, 2,
                notification_colors.accent2[1], notification_colors.accent2[2], notification_colors.accent2[3], notif.alpha,
                notification_colors.accent1[1], notification_colors.accent1[2], notification_colors.accent1[3], notif.alpha, true)
            
            renderer.gradient(box_x, box_y + box_h - 1, box_w / 2, 1,
                notification_colors.accent1[1], notification_colors.accent1[2], notification_colors.accent1[3], notif.alpha * 0.4,
                notification_colors.accent2[1], notification_colors.accent2[2], notification_colors.accent2[3], notif.alpha * 0.4, true)
            renderer.gradient(box_x + box_w / 2, box_y + box_h - 1, box_w / 2, 1,
                notification_colors.accent2[1], notification_colors.accent2[2], notification_colors.accent2[3], notif.alpha * 0.4,
                notification_colors.accent1[1], notification_colors.accent1[2], notification_colors.accent1[3], notif.alpha * 0.4, true)
            
            renderer.gradient(box_x + 2, box_y + 3, box_w - 4, 1,
                255, 255, 255, notif.alpha * 0.2, 255, 255, 255, 0, false)
            
            local text_y = box_y + pad_y
            renderer.text(screen_x / 2 + 1, text_y + 1, 0, 0, 0, notif.alpha * 0.8, font_flags, 0, notif.text)
            renderer.text(screen_x / 2, text_y, color[1], color[2], color[3], notif.alpha, font_flags, 0, notif.text)
        end
    end
end

local clantags = {
    ["v1"] = {
        "w", "wi", "win", "wins", "winst", "winsto", "winston", "winston.", 
        "winston.r", "winston.re", "winston.red", "winston.red", "winston.red", 
        "winston.re", "winston.r", "winston.", "winston", "winsto", 
        "winst", "wins", "win", "wi", "w", " ", " ", " ", " ", 
    },
    ["v2"] = {
        "w", "wi", "win", "wins", "winst", "winsto", "winston", "winston.", 
        "winston.r", "winston.re", "winston.red", "winston.red", "winston.red", 
        "winston.re", "winston.r", "winston.", "winston", "winsto", 
        "winst", "wins", "win", "wi", "w", " ", " ", " ", " ",
    }
}

local clantag_index = 1
local last_clantag_time = globals.realtime()
local last_tag = ""

local function set_clantag(tag)
    if tag and tag ~= last_tag then
        client.set_clan_tag(tag)
        last_tag = tag
    end
end

local function update_clantag()
    if not ui.get(UI.enabled) or not ui.get(UI.clantag) then
        set_clantag("")
        return
    end
    
    local style = ui.get(UI.clantag_style)
    local tag_set = clantags[string.lower(style)] or clantags["v1"]
    
    local interval = string.lower(style) == "v2" and 0.12 or 0.2
    
    if globals.realtime() - last_clantag_time >= interval then
        set_clantag(tag_set[clantag_index])
        clantag_index = clantag_index + 1
        if clantag_index > #tag_set then
            clantag_index = 1
        end
        last_clantag_time = globals.realtime()
    end
end

local watermark_alpha = 0
local watermark_glow_pulse = 0
local watermark_text_wave = 0

local function draw_watermark()
    if not ui.get(UI.enabled) or not ui.get(UI.watermark) then
        watermark_alpha = 0
        return
    end
    
    watermark_alpha = watermark_alpha + (255 - watermark_alpha) * globals.frametime() * 5
    
    watermark_glow_pulse = watermark_glow_pulse + globals.frametime() * 2.5
    watermark_text_wave = watermark_text_wave + globals.frametime() * 4
    
    local glow_intensity = math.abs(math.sin(watermark_glow_pulse)) * 120 + 80
    local wave_offset = math.sin(watermark_text_wave) * 2
    
    local sys_time = { client.system_time() }
    local time_str = string.format("%02d:%02d:%02d", sys_time[1], sys_time[2], sys_time[3])
    
    local latency_str = ""
    if entity.get_local_player() ~= nil then
        local latency = client.latency() * 1000
        latency_str = string.format(" | %.1fms", latency)
    end
    
    local uwu_text = ui.get(UI.watermark_name)
    local info_text = string.format(" | %s%s", time_str, latency_str)

    -- setup watermark: append connection / performance stats (EmberLash port).
    -- Built before measuring so every style's box sizes to include it.
    local setup_tail = ""
    if ui.get(UI.watermark_setup) then
        setup_tail = UI.setup.build(ui.get(UI.watermark_setup_elems))
        info_text = info_text .. setup_tail
    end

    local screen_x, screen_y = client.screen_size()

    local uwu_w, uwu_h = renderer.measure_text("b", uwu_text)
    local info_w, info_h = renderer.measure_text("", info_text)
    
    local total_w = uwu_w + info_w + 30
    local box_h = math.max(uwu_h, info_h) + 16
    local box_x = screen_x - total_w - 15
    local box_y = 10
    
    local time_offset = globals.realtime() * 0.8
    
    local wc_r, wc_g, wc_b, wc_a = ui.get(UI.watermark_color)
    local P_R, P_G, P_B = wc_r, wc_g, wc_b
    local A_R, A_G, A_B = wc_r, wc_g, wc_b
    
    local style = ui.get(UI.watermark_style)

    -- Steam avatar sits in its own box next to the watermark (per-style frame)
    local show_avatar = ui.get(UI.watermark_avatar)
    if show_avatar then
        UI.avatar.ensure()
    end

    -- Lavender style: one-to-one look of the lavender_solus watermark
    if style == "Lavender" then
        -- split the name at its first dot so the suffix (".red"/".blue"/…) is
        -- accent-coloured, mirroring lavender's "GameSense.pub" highlight
        local base, suffix = uwu_text, ""
        local dot = uwu_text:find("%.")
        if dot then
            base = uwu_text:sub(1, dot - 1)
            suffix = uwu_text:sub(dot)
        end

        local lav_str = base
            .. UI.lav.colour(suffix, P_R, P_G, P_B)
            .. " | " .. UI.lav.colour(time_str, P_R, P_G, P_B)
            .. latency_str
            .. setup_tail

        local mw, mh = renderer.measure_text("", lav_str)
        local lav_w = mw + 10
        local lav_h = 25
        local lav_x = screen_x - lav_w - 15
        local lav_y = 10

        UI.lav.rounded_rectangle(lav_x, lav_y, lav_w, lav_h, 19, 19, 19, watermark_alpha, 5)
        UI.lav.rectangle_outline(lav_x, lav_y, lav_w, lav_h, 32, 32, 32, watermark_alpha, 2, 3)
        UI.lav.fade_rect(lav_x - 1, lav_y, lav_w + 2, lav_h, 5, P_R, P_G, P_B, watermark_alpha, 190, lav_h * 2)

        renderer.text(lav_x + 5, lav_y + (lav_h - mh) / 2, 226, 226, 226, watermark_alpha, "", 0, lav_str)

        if show_avatar then
            UI.avatar.draw_box("Lavender", lav_x, lav_y, lav_h, P_R, P_G, P_B, watermark_alpha)
        end
        return
    end

    -- Windows style: emberfix multi-panel look (matches the Windows keybind style)
    if style == "Windows" then
        -- name in bold white, dynamic info (time / latency) in the accent colour
        local win_uwu_w, win_uwu_h = renderer.measure_text("b", uwu_text)
        local win_info_w, win_info_h = renderer.measure_text("", info_text)

        local win_w = win_uwu_w + win_info_w + 28
        local win_h = math.max(win_uwu_h, win_info_h) + 12
        local win_x = screen_x - win_w - 15
        local win_y = 10

        UI.win_interface(win_x, win_y, win_w, win_h, P_R, P_G, P_B, watermark_alpha)

        local win_text_y = win_y + (win_h - win_uwu_h) / 2
        local win_uwu_x = win_x + 12
        local win_info_x = win_uwu_x + win_uwu_w

        -- name (white with drop shadow)
        renderer.text(win_uwu_x + 1, win_text_y + 1, 0, 0, 0, watermark_alpha * 0.5, "b", 0, uwu_text)
        renderer.text(win_uwu_x, win_text_y, 255, 255, 255, watermark_alpha, "b", 0, uwu_text)

        -- info (accent with drop shadow)
        renderer.text(win_info_x + 1, win_text_y + 1, 0, 0, 0, watermark_alpha * 0.5, "", 0, info_text)
        renderer.text(win_info_x, win_text_y, P_R, P_G, P_B, watermark_alpha, "", 0, info_text)

        if show_avatar then
            UI.avatar.draw_box("Windows", win_x, win_y, win_h, P_R, P_G, P_B, watermark_alpha)
        end
        return
    end

    if style == "Black" then
        for i = 1, 2 do
            local glow_size = i * 2
            local glow_a = (glow_intensity / (i * 4)) * (watermark_alpha / 255)
            renderer.rectangle(box_x - glow_size, box_y - glow_size, 
                total_w + glow_size * 2, box_h + glow_size * 2,
                P_R, P_G, P_B, glow_a)
        end
        
        renderer.rectangle(box_x, box_y, total_w, box_h, 20, 15, 20, watermark_alpha * 0.85)
        
        renderer.gradient(box_x, box_y, total_w / 2, 2,
            P_R, P_G, P_B, watermark_alpha * 0.9,
            A_R, A_G, A_B, watermark_alpha * 0.9, true)
        renderer.gradient(box_x + total_w / 2, box_y, total_w / 2, 2,
            A_R, A_G, A_B, watermark_alpha * 0.9,
            P_R, P_G, P_B, watermark_alpha * 0.9, true)
        
        renderer.gradient(box_x, box_y + box_h - 2, total_w / 2, 2,
            P_R, P_G, P_B, watermark_alpha * 0.7,
            A_R, A_G, A_B, watermark_alpha * 0.7, true)
        renderer.gradient(box_x + total_w / 2, box_y + box_h - 2, total_w / 2, 2,
            A_R, A_G, A_B, watermark_alpha * 0.7,
            P_R, P_G, P_B, watermark_alpha * 0.7, true)
        
        local border_alpha = watermark_alpha * (0.8 + math.sin(watermark_glow_pulse * 1.5) * 0.2)
        renderer.rectangle(box_x, box_y, 2, box_h, P_R, P_G, P_B, border_alpha)
        renderer.rectangle(box_x + total_w - 2, box_y, 2, box_h, P_R, P_G, P_B, border_alpha)
        
        renderer.gradient(box_x + 2, box_y + 3, total_w - 4, 1,
            255, 255, 255, watermark_alpha * 0.3, 255, 255, 255, 0, false)
    else
        for i = 1, 2 do
            local glow_size = i * 1.5
            local glow_a = (30 / i) * (watermark_alpha / 255)
            renderer.rectangle(box_x - glow_size, box_y - glow_size, 
                total_w + glow_size * 2, box_h + glow_size * 2,
                P_R, P_G, P_B, glow_a)
        end
        
        renderer.rectangle(box_x, box_y, total_w, box_h, 10, 8, 15, watermark_alpha * 0.6)
        
        renderer.gradient(box_x, box_y, total_w / 2, 2,
            P_R, P_G, P_B, watermark_alpha,
            A_R, A_G, A_B, watermark_alpha, true)
        renderer.gradient(box_x + total_w / 2, box_y, total_w / 2, 2,
            A_R, A_G, A_B, watermark_alpha,
            P_R, P_G, P_B, watermark_alpha, true)
        
        renderer.gradient(box_x, box_y + box_h - 1, total_w / 2, 1,
            P_R, P_G, P_B, watermark_alpha * 0.4,
            A_R, A_G, A_B, watermark_alpha * 0.4, true)
        renderer.gradient(box_x + total_w / 2, box_y + box_h - 1, total_w / 2, 1,
            A_R, A_G, A_B, watermark_alpha * 0.4,
            P_R, P_G, P_B, watermark_alpha * 0.4, true)
        
        renderer.gradient(box_x + 2, box_y + 3, total_w - 4, 1,
            255, 255, 255, watermark_alpha * 0.2, 255, 255, 255, 0, false)
    end
    
    local text_y = box_y + (box_h - uwu_h) / 2 + wave_offset
    local uwu_x = box_x + 15
    local info_x = uwu_x + uwu_w
    
    for i = 1, 5 do
        local glow_offset = i * 0.8
        local glow_a = (glow_intensity / (i * 0.8)) * (watermark_alpha / 255)
        local angle = time_offset * 2 + i
        local gx = math.cos(angle) * glow_offset
        local gy = math.sin(angle) * glow_offset
        renderer.text(uwu_x + gx, text_y + gy, 255, 255, 255, glow_a, "b", 0, uwu_text)
    end
    renderer.text(uwu_x + 1, text_y + 1, 0, 0, 0, watermark_alpha * 0.9, "b", 0, uwu_text)
    
    renderer.text(uwu_x, text_y, 255, 255, 255, watermark_alpha, "b", 0, uwu_text)
    
    for i = 1, 2 do
        local info_glow = i * 0.5
        renderer.text(info_x + info_glow, text_y + info_glow, 
            255, 255, 255, watermark_alpha * 0.3 / i, "", 0, info_text)
    end
    renderer.text(info_x + 1, text_y + 1, 0, 0, 0, watermark_alpha * 0.8, "", 0, info_text)
    renderer.text(info_x, text_y, 255, 255, 255, watermark_alpha, "", 0, info_text)
    
    local sparkle_time = globals.realtime() * 2.5
    for i = 1, 4 do
        local sparkle_offset = (sparkle_time + i * 1.57) % 6.28
        local orbit_radius = (total_w / 2 + 15) + math.sin(sparkle_time + i) * 5
        local sparkle_x = box_x + total_w / 2 + math.cos(sparkle_offset) * orbit_radius
        local sparkle_y = box_y + box_h / 2 + math.sin(sparkle_offset) * (box_h / 2 + 8)
        local sparkle_alpha = (math.abs(math.sin(sparkle_time * 1.5 + i)) * 0.6 + 0.4) * watermark_alpha
        
        local sparkle_size = 2 + math.sin(sparkle_time * 2 + i) * 0.5
        renderer.circle(sparkle_x, sparkle_y, 255, 200, 255, sparkle_alpha * 0.3, sparkle_size + 2, 0, 1)
        renderer.circle(sparkle_x, sparkle_y, 255, 182, 220, sparkle_alpha, sparkle_size, 0, 1)
    end

    -- avatar box for the Black / Pink styles (Lavender & Windows return earlier)
    if show_avatar then
        UI.avatar.draw_box(style, box_x, box_y, box_h, P_R, P_G, P_B, watermark_alpha)
    end
end

local kill_image_state = {
    active = false,
    start_time = 0,
    current_image = nil,
    image_pool = {},
    last_image = nil,
    from_checkbox = false
}

local kill_image_init_x, kill_image_init_y = client.screen_size()
local kill_image_drag = dragging_fn("uwu_kill_image", kill_image_init_x / 2 - 200, kill_image_init_y / 2 - 200)

local function get_random_kill_image()
    if #media.kill_images == 0 then return nil end
    
    local no_repeat = ui.get(UI.kill_image_no_repeat)
    
    if no_repeat then
        if #kill_image_state.image_pool == 0 then
            for i = 1, #media.kill_images do
                kill_image_state.image_pool[i] = media.kill_images[i]
            end
            
            if kill_image_state.last_image then
                for i = #kill_image_state.image_pool, 1, -1 do
                    if kill_image_state.image_pool[i].file == kill_image_state.last_image then
                        table.remove(kill_image_state.image_pool, i)
                        break
                    end
                end
            end
        end
        
        if #kill_image_state.image_pool > 0 then
            local idx = math.random(1, #kill_image_state.image_pool)
            local selected = kill_image_state.image_pool[idx]
            table.remove(kill_image_state.image_pool, idx)
            kill_image_state.last_image = selected.file
            return selected.file
        end
    else
        local idx = math.random(1, #media.kill_images)
        return media.kill_images[idx].file
    end
    
    return nil
end

local function show_kill_image(from_checkbox)
    if not ui.get(UI.enabled) or not ui.get(UI.kill_image) then return end
    if #media.kill_images == 0 then return end
    
    local selected = ui.get(UI.kill_image_select)
    local image_file
    
    if selected == "Random" then
        image_file = get_random_kill_image()
    else
        image_file = media.kill_image_files[selected]
    end
    
    if image_file then
        kill_image_state.active = true
        kill_image_state.start_time = globals.realtime()
        kill_image_state.current_image = image_file
        kill_image_state.from_checkbox = from_checkbox == true
    end
end

local function draw_kill_image()
    local enabled = ui.get(UI.enabled) and ui.get(UI.kill_image)

    -- чекбокс выключили — гасим
    if not enabled then
        if kill_image_state.active and kill_image_state.from_checkbox then
            kill_image_state.active = false
            kill_image_state.current_image = nil
            kill_image_state.from_checkbox = false
        end
        return
    end

    -- чекбокс включён, но картинка не запущена — запускаем сразу
    if not kill_image_state.active then
        show_kill_image(true)
        return
    end

    local elapsed = globals.realtime() - kill_image_state.start_time
    local duration_raw = ui.get(UI.kill_image_duration)
    local duration = duration_raw / 10
    local infinite = duration_raw == 0

    if not infinite and elapsed > duration then
        kill_image_state.active = false
        kill_image_state.current_image = nil
        -- если запущена из чекбокса — крутим следующую сразу
        if kill_image_state.from_checkbox then
            show_kill_image(true)
        end
        return
    end

    if not kill_image_state.current_image then return end

    local file_data = readfile("csgo/materials/panorama/images/icons/equipment/uwukill/" .. kill_image_state.current_image)
    if not file_data then return end

    local png = images.load_png(file_data)
    if not png then return end

    local base_alpha = ui.get(UI.kill_image_alpha)
    local alpha = base_alpha
    local animation = "None"

    local fade_time = duration * 0.3

    if not infinite then
        if animation == "Fade in & out" then
            if elapsed < fade_time then
                alpha = base_alpha * (elapsed / fade_time)
            elseif elapsed > duration - fade_time then
                alpha = base_alpha * ((duration - elapsed) / fade_time)
            end
        elseif animation == "Fade in" then
            if elapsed < fade_time then
                alpha = base_alpha * (elapsed / fade_time)
            end
        elseif animation == "Fade out" then
            if elapsed > duration - fade_time then
                alpha = base_alpha * ((duration - elapsed) / fade_time)
            end
        end
    else
        if animation == "Fade in" or animation == "Fade in & out" then
            local fi = math.min(elapsed / 0.3, 1)
            alpha = base_alpha * fi
        end
    end

    local box_w = ui.get(UI.kill_image_size)
    local box_h = box_w
    local box_x, box_y = kill_image_drag.drag(box_w, box_h)

    png:draw(box_x, box_y, box_w, box_h, 255, 255, 255, alpha, true, "f")
end

local function on_aim_hit(e)
    if not ui.get(UI.enabled) or not ui.get(UI.notifications) then return end
    if not contains(ui.get(UI.notify_types), "Hit") then return end
    
    local name = entity.get_player_name(e.target)
    local hitgroup = ({"generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg"})[e.hitgroup + 1] or "body"
    local health = entity.get_prop(e.target, 'm_iHealth') or 0
    
    local emoji = ":3"
    if e.damage >= 100 then
        emoji = "^w^"
    elseif hitgroup == "head" then
        emoji = "uwu"
    end
    
    add_notification(string.format("%s Hit %s in %s for %d dmg (%d hp)", emoji, name, hitgroup, e.damage, health), "hit")
end

local function on_aim_miss(e)
    if not ui.get(UI.enabled) then return end
    
    local name = entity.get_player_name(e.target)
    local hitgroup = ({"generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg"})[e.hitgroup + 1] or "body"
    local reason = e.reason == "?" and "resolver" or e.reason
    
    if ui.get(UI.miss_log) then
        local hours, minutes, seconds = client.system_time()
        local timestamp = string.format("%02d:%02d:%02d", hours, minutes, seconds)
        
        local sad_emojis = {";-;", "T_T", ">_<", ":'(", "QwQ", "uwu", "owo"}
        local emoji = sad_emojis[math.random(1, #sad_emojis)]
        
        local info_parts = {}
        
        local x, y, z = entity.get_prop(e.target, "m_vecOrigin")
        if x and y and z then
            local me = entity.get_local_player()
            if me then
                local my_x, my_y, my_z = entity.get_prop(me, "m_vecOrigin")
                if my_x and my_y and my_z then
                    local distance = math.sqrt((x - my_x)^2 + (y - my_y)^2 + (z - my_z)^2)
                    table.insert(info_parts, string.format("pos: %.0f,%.0f,%.0f", x, y, z))
                    table.insert(info_parts, string.format("dist: %.0fu", distance))
                end
            end
        end
        
        if e.backtrack and e.backtrack > 0 then
            table.insert(info_parts, string.format("bt: %dt", e.backtrack))
        end
        
        local health = entity.get_prop(e.target, "m_iHealth")
        if health then
            table.insert(info_parts, string.format("hp: %d", health))
        end
        
        local vx, vy, vz = entity.get_prop(e.target, "m_vecVelocity")
        if vx and vy then
            local velocity = math.sqrt(vx*vx + vy*vy)
            table.insert(info_parts, string.format("vel: %.0f", velocity))
        end
        
        local flags = entity.get_prop(e.target, "m_fFlags")
        if flags then
            local flag_str = {}
            if bit.band(flags, 1) == 0 then
                table.insert(flag_str, "air")
            end
            if bit.band(flags, 2) ~= 0 then
                table.insert(flag_str, "duck")
            end
            if vx and vy and math.sqrt(vx*vx + vy*vy) > 5 then
                table.insert(flag_str, "move")
            end
            if #flag_str > 0 then
                table.insert(info_parts, table.concat(flag_str, "/"))
            end
        end
        
        local me = entity.get_local_player()
        if me then
            local weapon = entity.get_player_weapon(me)
            if weapon then
                local weapon_name = entity.get_classname(weapon)
                if weapon_name then
                    weapon_name = weapon_name:gsub("CWeapon", ""):gsub("weapon_", "")
                    table.insert(info_parts, weapon_name)
                end
            end
        end
        
        local mindmg_ref = ui.reference("RAGE", "Aimbot", "Minimum damage")
        if mindmg_ref then
            local mindmg = ui.get(mindmg_ref)
            table.insert(info_parts, string.format("mindmg: %d", mindmg))
        end
        
        local info_str = #info_parts > 0 and (" | " .. table.concat(info_parts, " | ")) or ""
        
        client.color_log(255, 120, 220, string.format("[%s] [uwu.hook] ", timestamp))
        client.color_log(255, 182, 220, string.format("%s Missed %s in %s ", emoji, name, hitgroup))
        client.color_log(255, 150, 200, string.format("(%s, %d%%hc%s)", reason, e.hit_chance or 0, info_str))
    end
    
    if not ui.get(UI.notifications) then return end
    if not contains(ui.get(UI.notify_types), "Miss") then return end
    
    local sad_emojis = {";-;", "T_T", ">_<", ":'(", "QwQ"}
    local emoji = sad_emojis[math.random(1, #sad_emojis)]
    
    add_notification(string.format("%s Missed %s in %s due to %s", emoji, name, hitgroup, reason), "miss")
end

local hit_effect_particles = {}

local function spawn_hit_particle(x, y, z, vx, vy, vz, r, g, b, size, life, ptype)
    hit_effect_particles[#hit_effect_particles + 1] = {
        x = x, y = y, z = z,
        vx = vx, vy = vy, vz = vz,
        r = r, g = g, b = b,
        size = size,
        life = life,
        max_life = life,
        type = ptype,
        spawn_time = globals.curtime()
    }
end

local function create_hit_effect_burst(x, y, z, style, color_r, color_g, color_b, color2_r, color2_g, color2_b, color3_r, color3_g, color3_b, amount, size, duration, radius, anim)
    local count = amount
    local radius_multiplier = radius / 50
    
    for i = 1, count do
        local angle1 = math.random() * math.pi * 2
        local angle2 = (math.random() - 0.5) * math.pi
        
        local base_speed = 2 + math.random() * 3
        local speed = base_speed * radius_multiplier
        
        local vx = math.cos(angle1) * math.cos(angle2) * speed
        local vy = math.sin(angle2) * speed
        local vz = math.sin(angle1) * math.cos(angle2) * speed
        
        local r, g, b = color_r, color_g, color_b
        
        if style == "Confetti" then
            r = math.random(100, 255)
            g = math.random(100, 255)
            b = math.random(100, 255)
        elseif style == "2-color" then
            local t = i / count
            r = color_r + (color2_r - color_r) * t
            g = color_g + (color2_g - color_g) * t
            b = color_b + (color2_b - color_b) * t
        elseif style == "3-color" then
            local t = i / count
            if t < 0.5 then
                local t2 = t * 2
                r = color_r + (color2_r - color_r) * t2
                g = color_g + (color2_g - color_g) * t2
                b = color_b + (color2_b - color_b) * t2
            else
                local t2 = (t - 0.5) * 2
                r = color2_r + (color3_r - color2_r) * t2
                g = color2_g + (color3_g - color2_g) * t2
                b = color2_b + (color3_b - color2_b) * t2
            end
        elseif style == "Rainbow" then
            local hue = (i / count) % 1.0
            r, g, b = hsv_to_rgb(hue, 0.8, 1.0)
        end
        
        local particle_size = size + math.random() * 1
        local particle_life = duration + math.random() * 0.2
        
        spawn_hit_particle(x, y, z, vx, vy, vz, r, g, b, particle_size, particle_life, style)
    end
end

local function update_hit_particles()
    local dt = globals.frametime()
    
    for i = #hit_effect_particles, 1, -1 do
        local p = hit_effect_particles[i]
        
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(hit_effect_particles, i)
        else
            p.x = p.x + p.vx * dt * 60
            p.y = p.y + p.vy * dt * 60
            p.z = p.z + p.vz * dt * 60
            
            if p.type == "Confetti" then
                p.vy = p.vy - 0.15
            else
                p.vy = p.vy - 0.08
            end
            
            p.vx = p.vx * 0.97
            p.vz = p.vz * 0.97
        end
    end
end

local function draw_star(x, y, size, r, g, b, a)
    renderer.line(x - size, y, x + size, y, r, g, b, a)
    renderer.line(x, y - size, x, y + size, r, g, b, a)
    renderer.line(x - size * 0.7, y - size * 0.7, x + size * 0.7, y + size * 0.7, r, g, b, a)
    renderer.line(x - size * 0.7, y + size * 0.7, x + size * 0.7, y - size * 0.7, r, g, b, a)
end

local function draw_shard(x, y, size, r, g, b, a, time)
    local rot = time * 5
    local x1 = x + math.cos(rot) * size
    local y1 = y + math.sin(rot) * size
    local x2 = x + math.cos(rot + 2) * size
    local y2 = y + math.sin(rot + 2) * size
    local x3 = x + math.cos(rot + 4) * size
    local y3 = y + math.sin(rot + 4) * size
    renderer.triangle(x1, y1, x2, y2, x3, y3, r, g, b, a)
end

local function draw_glyph(x, y, size, r, g, b, a)
    local glyphs = {"*", "✦", "✧", "✹", "✶", "✷"}
    local glyph = glyphs[math.random(1, #glyphs)]
    local font_flag = "c"
    if size > 4 then
        font_flag = "bc"
    end
    if size > 6 then
        font_flag = "+bc"
    end
    renderer.text(x, y, r, g, b, a, font_flag, 0, glyph)
end

local function draw_hit_particles()
    if not ui.get(UI.enabled) or not ui.get(UI.hit_effect) then return end
    
    local cur_time = globals.curtime()
    local glow_enabled = ui.get(UI.hit_effect_glow)
    local glow_thick = ui.get(UI.hit_effect_glow_thick) / 10
    local anim = ui.get(UI.hit_effect_anim)
    local particle_shape = ui.get(UI.hit_effect_particle)
    
    for _, p in ipairs(hit_effect_particles) do
        local sx, sy = renderer.world_to_screen(p.x, p.y, p.z)
        if sx and sy then
            local life_frac = p.life / p.max_life
            local alpha = life_frac * 255
            
            if anim == "Pulse" then
                local pulse = math.abs(math.sin((cur_time - p.spawn_time) * 8))
                alpha = alpha * (0.5 + pulse * 0.5)
            end
            
            local size = p.size
            
            if glow_enabled then
                renderer.circle(sx, sy, p.r, p.g, p.b, alpha * 0.3, size + glow_thick, 0, 1)
                renderer.circle(sx, sy, p.r, p.g, p.b, alpha * 0.15, size + glow_thick * 1.5, 0, 1)
            end
            
            if particle_shape == "Circle" then
                renderer.circle(sx, sy, p.r, p.g, p.b, alpha, size, 0, 1)
            elseif particle_shape == "Snowflake" then
                draw_star(sx, sy, size, p.r, p.g, p.b, alpha)
            elseif particle_shape == "Shard" then
                draw_shard(sx, sy, size, p.r, p.g, p.b, alpha, cur_time - p.spawn_time)
            elseif particle_shape == "Glyph" then
                draw_glyph(sx, sy, size, p.r, p.g, p.b, alpha)
            end
        end
    end
end

local function on_player_hurt(e)
    local attacker = client.userid_to_entindex(e.attacker)
    local victim = client.userid_to_entindex(e.userid)
    local local_player = entity.get_local_player()
    
    if ui.get(UI.enabled) and ui.get(UI.hit_sound) and attacker == local_player and victim ~= local_player then
        local sound_name = e.hitgroup == 1 and ui.get(UI.hit_sound_head) or ui.get(UI.hit_sound_body)
        local sound_file = hit_sounds.files[sound_name]
        if sound_file then
            local volume = ui.get(UI.hit_sound_volume)
            for i = 1, volume do
                native_Surface_PlaySound(sound_file)
            end
        end
    end
    
    if ui.get(UI.enabled) and ui.get(UI.notifications) then
        if victim == local_player and attacker ~= local_player and contains(ui.get(UI.notify_types), "Hurt") then
            local attacker_name = entity.get_player_name(attacker)
            local hitgroup = ({"generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg"})[e.hitgroup + 1] or "body"
            
            local hurt_emojis = {"ouchie >_<", "nuu ;w;", "owie T_T", "meanie >:("}
            local emoji = hurt_emojis[math.random(1, #hurt_emojis)]
            
            add_notification(string.format("%s %s hit you in %s for %d dmg", emoji, attacker_name, hitgroup, e.dmg_health), "hurt")
        end
    end
    
    if ui.get(UI.enabled) and ui.get(UI.hit_effect) and attacker == local_player and victim ~= local_player then
        local r, g, b, a = ui.get(UI.hit_effect_color)
        local r2, g2, b2 = ui.get(UI.hit_effect_color2)
        local r3, g3, b3 = ui.get(UI.hit_effect_color3)
        local style = ui.get(UI.hit_effect_style)
        local size = ui.get(UI.hit_effect_size) / 10
        local amount = ui.get(UI.hit_effect_amount)
        local duration = ui.get(UI.hit_effect_duration) / 10
        local radius = ui.get(UI.hit_effect_radius)
        local anim = ui.get(UI.hit_effect_anim)
        
        local hitbox = e.hitgroup or 6
        local x, y, z = entity.hitbox_position(victim, hitbox)
        if x then
            create_hit_effect_burst(x, y, z, style, r, g, b, r2, g2, b2, r3, g3, b3, amount, size, duration, radius, anim)
        end
    end
end

local function on_player_death(e)
    local victim = client.userid_to_entindex(e.userid)
    local attacker = client.userid_to_entindex(e.attacker)
    local local_player = entity.get_local_player()
    
    
    if ui.get(UI.enabled) and ui.get(UI.trashtalk_enabled) then
        local is_kill = attacker == local_player and victim ~= local_player
        local is_death = victim == local_player and attacker ~= local_player
        local no_repeat = ui.get(UI.trashtalk_no_repeat)
        local selected_phrase = nil
        
        if is_kill then
            
            if no_repeat then
                
                if #trashtalk.kill_pool == 0 then
                    for i = 1, #trashtalk.phrases do
                        if trashtalk.phrases[i].on_kill then
                            trashtalk.kill_pool[#trashtalk.kill_pool + 1] = trashtalk.phrases[i]
                        end
                    end
                end
                
                
                if #trashtalk.kill_pool > 0 then
                    local idx = math.random(1, #trashtalk.kill_pool)
                    selected_phrase = trashtalk.kill_pool[idx]
                    table.remove(trashtalk.kill_pool, idx)
                end
            else
                
                local valid_phrases = {}
                for i = 1, #trashtalk.phrases do
                    if trashtalk.phrases[i].on_kill then
                        valid_phrases[#valid_phrases + 1] = trashtalk.phrases[i]
                    end
                end
                if #valid_phrases > 0 then
                    selected_phrase = valid_phrases[math.random(1, #valid_phrases)]
                end
            end
        elseif is_death then
            
            if no_repeat then
                
                if #trashtalk.death_pool == 0 then
                    for i = 1, #trashtalk.phrases do
                        if trashtalk.phrases[i].on_death then
                            trashtalk.death_pool[#trashtalk.death_pool + 1] = trashtalk.phrases[i]
                        end
                    end
                end
                
                
                if #trashtalk.death_pool > 0 then
                    local idx = math.random(1, #trashtalk.death_pool)
                    selected_phrase = trashtalk.death_pool[idx]
                    table.remove(trashtalk.death_pool, idx)
                end
            else
                
                local valid_phrases = {}
                for i = 1, #trashtalk.phrases do
                    if trashtalk.phrases[i].on_death then
                        valid_phrases[#valid_phrases + 1] = trashtalk.phrases[i]
                    end
                end
                if #valid_phrases > 0 then
                    selected_phrase = valid_phrases[math.random(1, #valid_phrases)]
                end
            end
        end
        
        if selected_phrase then
            local delay = selected_phrase.delay or 0.5
            local target_name = ""
            
            if is_kill then
                target_name = entity.get_player_name(victim)
            elseif is_death then
                target_name = entity.get_player_name(attacker)
            end
            
            
            local phrase_text = selected_phrase.text:gsub("$name", target_name)
            client.delay_call(delay, function()
                client.exec("say " .. phrase_text)
            end)
            
            
            if selected_phrase.messages and #selected_phrase.messages > 0 then
                for i = 1, #selected_phrase.messages do
                    local msg_text = selected_phrase.messages[i]
                    local msg_delay = delay * (i + 1)  
                    
                    
                    local function send_message(message)
                        return function()
                            local formatted_msg = message:gsub("$name", target_name)
                            client.exec("say " .. formatted_msg)
                        end
                    end
                    
                    client.delay_call(msg_delay, send_message(msg_text))
                end
            end
        end
    end
    
    if attacker == local_player and victim ~= local_player then
        show_kill_image()
    end
    
    if victim == local_player then
        if ui.get(UI.enabled) and ui.get(UI.notifications) and contains(ui.get(UI.notify_types), "Death") then
            local attacker_name = entity.get_player_name(attacker)
            
            local death_emojis = {"rip x_x", "ded ;-;", "nooo T^T", "respawning... >.>", "oopsie x.x"}
            local emoji = death_emojis[math.random(1, #death_emojis)]
            
            if attacker == local_player then
                add_notification(string.format("%s You died", emoji), "death")
            else
                add_notification(string.format("%s Killed by %s", emoji, attacker_name), "death")
            end
        end
        
        if ui.get(UI.enabled) and ui.get(UI.death_sound) then
            local sound_name = ui.get(UI.death_sound_select)
            local sound_file = media.death_sound_files[sound_name]
            if sound_file then
                local volume = ui.get(UI.death_sound_volume)
                for i = 1, volume do
                    native_Surface_PlaySound(sound_file)
                end
            end
        end
    end
end

local mindmg_refs = {ui.reference("RAGE", "Aimbot", "Minimum damage override")}
local keybind_refs = {
    {name = "Double tap", ref = {ui.reference("RAGE", "Aimbot", "Double tap")}},
    {name = "On shot anti-aim", ref = {ui.reference("AA", "Other", "On shot anti-aim")}},
    {name = "Minimum damage", ref = mindmg_refs, show_value = true},
    {name = "Quick peek assist", ref = {ui.reference("RAGE", "Other", "Quick peek assist")}},
    {name = "Force body aim", ref = ui.reference("RAGE", "Aimbot", "Force body aim")},
    {name = "Force safe point", ref = ui.reference("RAGE", "Aimbot", "Force safe point")},
    {name = "Fake duck", ref = ui.reference("RAGE", "Other", "Duck peek assist")},
    {name = "Freestanding", ref = {ui.reference("AA", "Anti-aimbot angles", "Freestanding")}},
    {name = "Ping spike", ref = {ui.reference("MISC", "Miscellaneous", "Ping spike")}},
}

local keybind_modes = {"holding", "toggled", "disabled"}

local spectators_alpha = 0
local keybinds_alpha = 0
local spectator_item_anims = {}
local keybind_item_anims = {}
local screen_x, screen_y = client.screen_size()
local spectators_drag = dragging_fn("uwu_spectators", screen_x / 2 - 200, screen_y / 2 - 100)
local keybinds_drag = dragging_fn("uwu_keybinds", screen_x / 2 + 50, screen_y / 2 - 100)

local function get_spectators()
    local me = entity.get_local_player()
    if not me then return {} end
    
    local spectators = {}
    local observing = me
    
    for i = 1, globals.maxplayers() do
        if entity.get_classname(i) == "CCSPlayer" then
            local obs_mode = entity.get_prop(i, "m_iObserverMode")
            local obs_target = entity.get_prop(i, "m_hObserverTarget")
            
            if obs_target and obs_target <= 64 and not entity.is_alive(i) and (obs_mode == 4 or obs_mode == 5) then
                if i == me then
                    observing = obs_target
                end
            end
        end
    end
    
    for i = 1, globals.maxplayers() do
        if entity.get_classname(i) == "CCSPlayer" then
            local obs_mode = entity.get_prop(i, "m_iObserverMode")
            local obs_target = entity.get_prop(i, "m_hObserverTarget")
            
            if obs_target == observing and obs_target <= 64 and not entity.is_alive(i) and (obs_mode == 4 or obs_mode == 5) then
                if i ~= me then
                    table.insert(spectators, {
                        idx = i,
                        name = entity.get_player_name(i)
                    })
                end
            end
        end
    end
    
    return spectators
end

local function draw_spectators()
    if not ui.get(UI.enabled) or not ui.get(UI.spectators) then
        spectators_alpha = 0
        spectator_item_anims = {}
        return
    end
    
    local spectators = get_spectators()
    local screen_x, screen_y = client.screen_size()
    
    local P_R, P_G, P_B = ui.get(UI.spectators_color)
    
    local size = ui.get(UI.spectators_size)
    local style = ui.get(UI.spectators_style)
    local anim_mode = ui.get(UI.spectators_anim)
    local scale = size == "Small" and 0.85 or 1.0
    local font = size == "Small" and "-" or ""
    
    local title = "spectators"
    
    local base_w = 130
    local item_h = size == "Small" and 16 or 14
    local title_h = size == "Small" and 20 or 18
    local box_w = base_w * scale
    local box_h = (title_h + (#spectators * item_h)) * scale
    local box_x, box_y = spectators_drag.get()
    
    box_x, box_y = spectators_drag.drag(box_w, box_h)
    
    local target_alpha = (#spectators > 0 or ui.is_menu_open()) and 255 or 0
    spectators_alpha = spectators_alpha + (target_alpha - spectators_alpha) * globals.frametime() * 8
    
    if spectators_alpha < 1 then return end
    
    local time = globals.realtime()
    local pulse = math.abs(math.sin(time * 2)) * 0.4 + 0.6
    local title_wave = 0
    
    if anim_mode == "Moving" then
    elseif anim_mode == "Moving title" then
        title_wave = math.sin(time * 3) * 3
    end
    
    if style == "Modern" then
        local gradient_shift = (math.sin(time * 1.5) + 1) / 2
        
        local color1_r = P_R + (202 - P_R) * gradient_shift
        local color1_g = P_G + (70 - P_G) * gradient_shift
        local color1_b = P_B + (205 - P_B) * gradient_shift
        
        local color2_r = 202 + (P_R - 202) * gradient_shift
        local color2_g = 70 + (P_G - 70) * gradient_shift
        local color2_b = 205 + (P_B - 205) * gradient_shift
        
        renderer.rectangle(box_x, box_y, box_w, box_h, 10, 8, 15, spectators_alpha * 0.6)
        
        for i = 1, 2 do
            local glow_size = i * 1.5
            local glow_a = (30 / i) * (spectators_alpha / 255)
            renderer.rectangle(box_x - glow_size, box_y - glow_size, 
                box_w + glow_size * 2, box_h + glow_size * 2,
                P_R, P_G, P_B, glow_a)
        end
        
        renderer.gradient(box_x, box_y, box_w / 2, 2,
            color1_r, color1_g, color1_b, spectators_alpha * pulse,
            color2_r, color2_g, color2_b, spectators_alpha * pulse, true)
        renderer.gradient(box_x + box_w / 2, box_y, box_w / 2, 2,
            color2_r, color2_g, color2_b, spectators_alpha * pulse,
            color1_r, color1_g, color1_b, spectators_alpha * pulse, true)
        
        renderer.gradient(box_x, box_y + box_h - 1, box_w / 2, 1,
            P_R, P_G, P_B, spectators_alpha * 0.4,
            202, 70, 205, spectators_alpha * 0.4, true)
        renderer.gradient(box_x + box_w / 2, box_y + box_h - 1, box_w / 2, 1,
            202, 70, 205, spectators_alpha * 0.4,
            P_R, P_G, P_B, spectators_alpha * 0.4, true)
        
        renderer.gradient(box_x + 2, box_y + 3, box_w - 4, 1,
            255, 255, 255, spectators_alpha * 0.2, 255, 255, 255, 0, false)
        
        local title_y = box_y + (title_h * scale) / 2
        renderer.text(box_x + box_w / 2 + 1, title_y, 0, 0, 0, spectators_alpha * 0.6, "c" .. font, 0, title)
        renderer.text(box_x + box_w / 2 + title_wave, title_y - 1, P_R, P_G, P_B, spectators_alpha, "c" .. font, 0, title)
    elseif style == "Modern black" then
        local gradient_shift = (math.sin(time * 1.5) + 1) / 2
        
        local color1_r = P_R + (202 - P_R) * gradient_shift
        local color1_g = P_G + (70 - P_G) * gradient_shift
        local color1_b = P_B + (205 - P_B) * gradient_shift
        
        local color2_r = 202 + (P_R - 202) * gradient_shift
        local color2_g = 70 + (P_G - 70) * gradient_shift
        local color2_b = 205 + (P_B - 205) * gradient_shift
        
        renderer.rectangle(box_x, box_y, box_w, box_h, 15, 10, 20, spectators_alpha * 0.95)
        
        renderer.gradient(box_x, box_y, box_w / 2, 2,
            color1_r, color1_g, color1_b, spectators_alpha * pulse,
            color2_r, color2_g, color2_b, spectators_alpha * pulse, true)
        renderer.gradient(box_x + box_w / 2, box_y, box_w / 2, 2,
            color2_r, color2_g, color2_b, spectators_alpha * pulse,
            color1_r, color1_g, color1_b, spectators_alpha * pulse, true)
        
        renderer.rectangle(box_x, box_y + box_h - 1, box_w, 1, P_R, P_G, P_B, spectators_alpha * 0.3)
        
        local title_y = box_y + (title_h * scale) / 2
        renderer.text(box_x + box_w / 2 + 1, title_y, 0, 0, 0, spectators_alpha * 0.6, "c" .. font, 0, title)
        renderer.text(box_x + box_w / 2 + title_wave, title_y - 1, P_R, P_G, P_B, spectators_alpha, "c" .. font, 0, title)
    else
        renderer.text(box_x + box_w / 2 + 1, box_y + 1, 0, 0, 0, spectators_alpha * 0.4, "c" .. font, 0, title)
        renderer.text(box_x + box_w / 2 + title_wave, box_y, P_R, P_G, P_B, spectators_alpha, "c" .. font, 0, title)
        
        local line_y = box_y + (title_h * scale) - 4
        renderer.gradient(box_x, line_y, box_w / 2, 1,
            P_R, P_G, P_B, spectators_alpha * 0.8,
            202, 70, 205, spectators_alpha * 0.8, true)
        renderer.gradient(box_x + box_w / 2, line_y, box_w / 2, 1,
            202, 70, 205, spectators_alpha * 0.8,
            P_R, P_G, P_B, spectators_alpha * 0.8, true)
    end
    
    local y_offset = box_y + (title_h * scale)
    for i, spec in ipairs(spectators) do
        if not spectator_item_anims[spec.name] then
            spectator_item_anims[spec.name] = {alpha = 0, slide = -20}
        end
        
        local anim = spectator_item_anims[spec.name]
        anim.alpha = anim.alpha + (255 - anim.alpha) * globals.frametime() * 10
        anim.slide = anim.slide + (0 - anim.slide) * globals.frametime() * 12
        
        local item_alpha = (spectators_alpha / 255) * anim.alpha
        local hover_wave = 0
        local bounce_offset = 0
        
        if anim_mode == "Moving" then
            hover_wave = math.sin(time * 4 + i) * 2
        elseif anim_mode == "Bouncy" then
            bounce_offset = math.abs(math.sin(time * 3 + i * 0.5)) * 3
        end
        
        local text_x = box_x + 8 + anim.slide + hover_wave
        local text_y = y_offset - bounce_offset
        
        if style == "Modern" or style == "Modern black" then
            renderer.text(text_x + 1, text_y + 1, 0, 0, 0, item_alpha * 0.5, font, 0, spec.name)
            renderer.text(text_x, text_y, 255, 200, 230, item_alpha, font, 0, spec.name)
            
            local dot_x = box_x + 4 + anim.slide
            local dot_pulse = math.abs(math.sin(time * 3 + i * 0.5)) * 0.5 + 0.5
            renderer.circle(dot_x, text_y + 4, P_R, P_G, P_B, item_alpha * dot_pulse, 1.5, 0, 1)
        else
            renderer.text(box_x + 1, text_y + 1, 0, 0, 0, item_alpha * 0.3, font, 0, spec.name)
            renderer.text(box_x, text_y, 255, 200, 230, item_alpha, font, 0, spec.name)
        end
        
        y_offset = y_offset + (item_h * scale)
    end
    
    for name, anim in pairs(spectator_item_anims) do
        local found = false
        for _, spec in ipairs(spectators) do
            if spec.name == name then
                found = true
                break
            end
        end
        if not found then
            anim.alpha = anim.alpha - globals.frametime() * 800
            anim.slide = anim.slide - globals.frametime() * 60
            if anim.alpha <= 0 then
                spectator_item_anims[name] = nil
            end
        end
    end
    
    local items_to_render = {}
    for name, anim in pairs(spectator_item_anims) do
        local found = false
        for _, spec in ipairs(spectators) do
            if spec.name == name then
                found = true
                break
            end
        end
        if not found and anim.alpha > 0 then
            table.insert(items_to_render, {name = name, anim = anim})
        end
    end
    
    for i, item in ipairs(items_to_render) do
        local anim = item.anim
        local item_alpha = (spectators_alpha / 255) * anim.alpha
        local y_pos = box_y + (title_h * scale) + (#spectators + i - 1) * (item_h * scale)
        
        if style == "Modern" or style == "Modern black" then
            renderer.text(box_x + 8 + anim.slide + 1, y_pos + 1, 0, 0, 0, item_alpha * 0.5, font, 0, item.name)
            renderer.text(box_x + 8 + anim.slide, y_pos, 255, 200, 230, item_alpha, font, 0, item.name)
            
            local dot_x = box_x + 4 + anim.slide
            renderer.circle(dot_x, y_pos + 4, P_R, P_G, P_B, item_alpha * 0.5, 1.5, 0, 1)
        else
            renderer.text(box_x + 1, y_pos + 1, 0, 0, 0, item_alpha * 0.3, font, 0, item.name)
            renderer.text(box_x, y_pos, 255, 200, 230, item_alpha, font, 0, item.name)
        end
    end
    
    if style == "Modern" or style == "Modern black" then
        local corner_time = time * 4
        for i = 1, 3 do
            local corner_x = box_x + box_w - 4 - (i * 3)
            local corner_y = box_y + 6
            local corner_alpha = (math.abs(math.sin(corner_time + i)) * 0.6 + 0.4) * spectators_alpha
            renderer.circle(corner_x, corner_y, P_R, P_G, P_B, corner_alpha * 0.8, 1, 0, 1)
        end
    end
end

-- ===== Windows-style helpers (стиль окон из emberfix) =====
-- Закруглённый залитый прямоугольник (углы через renderer.circle, как в emberfix)
local function win_rounded_rect(x, y, w, h, rounding, r, g, b, a)
    if a <= 0 then return end
    rounding = math.min(rounding, w / 2, h / 2)
    y = y + rounding
    -- четыре угловых сектора
    renderer.circle(x + rounding, y, r, g, b, a, rounding, 180, 0.25)
    renderer.circle(x + w - rounding, y, r, g, b, a, rounding, 90, 0.25)
    renderer.circle(x + rounding, y + h - rounding * 2, r, g, b, a, rounding, 270, 0.25)
    renderer.circle(x + w - rounding, y + h - rounding * 2, r, g, b, a, rounding, 0, 0.25)
    -- заливка
    renderer.rectangle(x + rounding, y, w - rounding * 2, h - rounding * 2, r, g, b, a)
    renderer.rectangle(x + rounding, y - rounding, w - rounding * 2, rounding, r, g, b, a)
    renderer.rectangle(x + rounding, y + h - rounding * 2, w - rounding * 2, rounding, r, g, b, a)
    renderer.rectangle(x, y, rounding, h - rounding * 2, r, g, b, a)
    renderer.rectangle(x + w - rounding, y, rounding, h - rounding * 2, r, g, b, a)
end

-- Обводка периметра (без circle_outline - его нет в API этой сборки).
-- Углы слегка прямые, но при радиусе 4 это визуально незаметно.
local function win_rounded_outline(x, y, w, h, rounding, thickness, r, g, b, a)
    if a <= 0 then return end
    rounding = math.min(rounding, w / 2, h / 2)
    -- верх / низ (с отступом на скругление)
    renderer.rectangle(x + rounding, y, w - rounding * 2, thickness, r, g, b, a)
    renderer.rectangle(x + rounding, y + h - thickness, w - rounding * 2, thickness, r, g, b, a)
    -- лево / право (с отступом на скругление)
    renderer.rectangle(x, y + rounding, thickness, h - rounding * 2, r, g, b, a)
    renderer.rectangle(x + w - thickness, y + rounding, thickness, h - rounding * 2, r, g, b, a)
    -- скошенные уголки (маленькие отрезки, имитируют скругление)
    for i = 0, rounding - 1 do
        local off = rounding - i
        -- верхний левый
        renderer.rectangle(x + i, y + off, thickness, thickness, r, g, b, a)
        -- верхний правый
        renderer.rectangle(x + w - thickness - i, y + off, thickness, thickness, r, g, b, a)
        -- нижний левый
        renderer.rectangle(x + i, y + h - off - thickness, thickness, thickness, r, g, b, a)
        -- нижний правый
        renderer.rectangle(x + w - thickness - i, y + h - off - thickness, thickness, thickness, r, g, b, a)
    end
end

-- Боковые акцентные полосы (вертикальный градиент к прозрачному по краям окна)
-- Стыкуются с прямой вертикальной частью обводки (начинается на y+rounding)
local function win_side_bars(x, y, w, h, r, g, b, a)
    if a <= 0 then return end
    local rounding = 4
    local bar_y = math.floor(y + rounding)
    local bar_h = math.floor(h - rounding * 2)
    -- левая: цвет сверху -> прозрачный снизу, вплотную к внутренней обводке
    renderer.gradient(math.floor(x + 3), bar_y, 2, bar_h, r, g, b, a, r, g, b, 0, false)
    -- правая: прозрачный сверху -> цвет снизу
    renderer.gradient(math.floor(x + w - 5), bar_y, 2, bar_h, r, g, b, 0, r, g, b, a, false)
end

-- Полное окно в стиле emberfix multi panel: фон + боковые полосы + тройная обводка
local function win_create_interface(x, y, w, h, r, g, b, a)
    x, y = math.floor(x), math.floor(y)
    -- фон
    win_rounded_rect(x, y, w, h, 4, 25, 25, 25, a)
    -- боковые акцентные полосы (side = 'left + right', как в multi panel)
    win_side_bars(x, y, w, h, r, g, b, a)
    -- тройная обводка (как create_interface в emberfix)
    win_rounded_outline(x, y, w, h, 4, 1, 12, 12, 12, a)
    win_rounded_outline(x + 1, y + 1, w - 2, h - 2, 4, 1, 60, 60, 60, a)
    win_rounded_outline(x + 2, y + 2, w - 4, h - 4, 4, 1, 40, 40, 40, a)
end

-- expose the window drawer on the UI table so functions defined earlier in the
-- file (e.g. draw_watermark) can reach it — these win_* helpers are locals
-- declared here and would otherwise be out of scope above.
UI.win_interface = win_create_interface
-- ===== end Windows-style helpers =====

-- ===== Lavender-style keybinds (one-to-one port of lavender_solus.lua) =====
-- Everything lives on the existing UI table so no extra chunk-level locals are
-- introduced (the main chunk is right at Lua's 200 local limit).
UI.lav = {
    -- bind modes mirror lavender's bind_mode list (index = hotkey mode + 1)
    modes = {"always on", "holding", "toggled", "off hotkey"},
    width = 0,
    opacity = 0,
    height = 23,
    padding = 20,
    title = "keybinds",
    binds = {}
}

function UI.lav.inverse_lerp(a, b, weight)
    return (weight - a) / (b - a)
end

-- wrap a substring in an accent colour and reset to lavender's light-grey (CDCDCDFF)
function UI.lav.colour(text, r, g, b, a)
    return string.format("\a%02x%02x%02x%02x%s\aCDCDCDFF",
        math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5),
        math.floor((a or 255) + 0.5), text)
end

function UI.lav.rectangle_outline(x, y, w, h, r, g, b, a, thickness, radius)
    if thickness == nil or thickness < 1 then thickness = 1 end
    if radius == nil or radius < 0 then radius = 0 end

    local limit = math.min(w * 0.5, h * 0.5) * 0.5
    thickness = math.min(limit / 0.5, thickness)

    local offset = 0
    if radius >= thickness then
        radius = math.min(limit + (limit - thickness), radius)
        offset = radius + thickness
    end

    if radius == 0 then
        renderer.rectangle(x + offset - 1, y, w - offset * 2 + 2, thickness, r, g, b, a)
        renderer.rectangle(x + offset - 1, y + h, w - offset * 2 + 2, -thickness, r, g, b, a)
    else
        renderer.rectangle(x + offset, y, w - offset * 2, thickness, r, g, b, a)
        renderer.rectangle(x + offset, y + h, w - offset * 2, -thickness, r, g, b, a)
    end

    local bounds = math.max(offset, thickness)
    renderer.rectangle(x, y + bounds, thickness, h - bounds * 2, r, g, b, a)
    renderer.rectangle(x + w, y + bounds, -thickness, h - bounds * 2, r, g, b, a)

    if radius == 0 then return end

    renderer.circle_outline(x + offset, y + offset, r, g, b, a, offset, 180, 0.25, thickness)
    renderer.circle_outline(x + offset, y + h - offset, r, g, b, a, offset, 90, 0.25, thickness)
    renderer.circle_outline(x + w - offset, y + offset, r, g, b, a, offset, 270, 0.25, thickness)
    renderer.circle_outline(x + w - offset, y + h - offset, r, g, b, a, offset, 0, 0.25, thickness)
end

function UI.lav.rounded_rectangle(x, y, w, h, r, g, b, a, radius)
    y = y + radius
    local datacircle = {
        {x + radius, y, 180},
        {x + w - radius, y, 90},
        {x + radius, y + h - radius * 2, 270},
        {x + w - radius, y + h - radius * 2, 0},
    }
    local data = {
        {x + radius, y, w - radius * 2, h - radius * 2},
        {x + radius, y - radius, w - radius * 2, radius},
        {x + radius, y + h - radius * 2, w - radius * 2, radius},
        {x, y, radius, h - radius * 2},
        {x + w - radius, y, radius, h - radius * 2},
    }

    for _, d in pairs(datacircle) do
        renderer.circle(d[1], d[2], r, g, b, a, radius, d[3], 0.25)
    end
    for _, d in pairs(data) do
        renderer.rectangle(d[1], d[2], d[3], d[4], r, g, b, a)
    end
end

function UI.lav.outline_glow(x, y, w, h, r, g, b, a, thickness, radius)
    if thickness == nil or thickness < 1 then thickness = 1 end
    if radius == nil or radius < 0 then radius = 0 end

    local limit = math.min(w * 0.5, h * 0.5)
    radius = math.min(limit, radius)
    thickness = thickness + radius

    local rd = radius * 2
    x, y, w, h = x + radius - 1, y + radius - 1, w - rd + 2, h - rd + 2

    local factor = 1
    local step = UI.lav.inverse_lerp(radius, thickness, radius + 1)

    for k = radius, thickness do
        local kd = k * 2
        local rounding = radius == 0 and radius or k
        UI.lav.rectangle_outline(x - k, y - k, w + kd, h + kd, r, g, b, a * factor / 3, 1, rounding)
        factor = factor - step
    end
end

function UI.lav.fade_rect(x, y, w, h, radius, r, g, b, a, glow, w1)
    local n = a / 15
    w1 = w1 < 3 and 0 or w1
    local circ_fill = w1 > 5 and 0.25 or w1 / 150

    renderer.circle_outline(x + radius, y + radius, r, g, b, a, radius, 180, circ_fill, 1)
    renderer.circle_outline(x + w - radius, y + h - radius, r, g, b, a, radius, 0, circ_fill, 1)

    renderer.gradient(x + radius - 2, y, w1, 1, r, g, b, a, r, g, b, n, true)
    renderer.gradient(x + w - w1 - radius + 2, y + h - 1, w1, 1, r, g, b, n, r, g, b, a, true)

    renderer.gradient(x + radius - 5, y + h / 2 - radius * 2 + 2, 1, w1 / 3.5, r, g, b, a, r, g, b, n, false)
    renderer.gradient(x + w - 1, y - w1 / 3.5 - (radius - h) + 1, 1, w1 / 3.5, r, g, b, n, r, g, b, a, false)

    if a > 45 then
        UI.lav.outline_glow(x, y, w, h, r, g, b, glow, 5, radius)
    end
end

function UI.lav.bind_state(ref)
    -- returns is_active, mode_idx (0..3)
    local is_active, mode_idx = false, 0

    if type(ref) == "table" then
        if #ref == 1 then
            local state = {ui.get(ref[1])}
            mode_idx = state[2] or 0
            if mode_idx ~= 0 then
                is_active = (mode_idx == 3) and (not state[1]) or state[1]
            end
        else
            local checkbox_state = ui.get(ref[1])
            local hk = {ui.get(ref[2])}
            mode_idx = hk[2] or 0
            if checkbox_state and mode_idx ~= 0 then
                is_active = (mode_idx == 3) and (not hk[1]) or hk[1]
            end
        end
    else
        local state = {ui.get(ref)}
        mode_idx = state[2] or 0
        if mode_idx ~= 0 then
            is_active = (mode_idx == 3) and (not state[1]) or state[1]
        end
    end

    return is_active, mode_idx
end

function UI.lav.draw(kb_r, kb_g, kb_b)
    local self = UI.lav
    local h = self.height
    local padding = self.padding
    local menu_open = ui.is_menu_open()

    -- build the display list: preview everything while the menu is open,
    -- otherwise only the currently active binds (exactly like lavender)
    local list = {}
    local has_active = false
    for _, bind in ipairs(keybind_refs) do
        local is_active, mode_idx = self.bind_state(bind.ref)
        if is_active then has_active = true end
        list[#list + 1] = {
            name = bind.name,
            mode = self.modes[mode_idx + 1] or "?",
            active = is_active,
            show = menu_open or is_active
        }
    end

    -- stable width over the full list (lavender's kb_get_max_width)
    local max_width = 0
    for _, item in ipairs(list) do
        local name_w = renderer.measure_text("", item.name:lower())
        local mode_w = renderer.measure_text("", item.mode)
        local total = name_w + mode_w + padding
        if total > max_width then max_width = total end
    end
    if max_width == 0 then
        max_width = renderer.measure_text("", self.title) + padding
    end

    local target_w = menu_open and 130 or (max_width - 10)
    self.width = easing.quad_in(0.2, self.width, target_w - self.width, 1)

    local target_op = (has_active or menu_open) and 255 or 0
    self.opacity = easing.quad_in(0.4, self.opacity, target_op - self.opacity, 1)

    local box_w = self.width + padding
    local box_x, box_y = keybinds_drag.get()
    box_x, box_y = keybinds_drag.drag(box_w, h)

    if self.opacity < 10 then
        return
    end

    local op = self.opacity

    -- title container
    self.rounded_rectangle(box_x, box_y, box_w, h, 19, 19, 19, op, 5)
    self.rectangle_outline(box_x, box_y, box_w, h, 32, 32, 32, op, 2, 3)
    renderer.text(box_x + box_w / 2, box_y + h / 2, 225, 225, 232, op, "cb", 0, self.title)
    self.fade_rect(box_x - 1, box_y, box_w + 2, h, 5, kb_r, kb_g, kb_b, op, 190, h * 2)

    -- binds below the title
    local count = 0
    for _, item in ipairs(list) do
        local st = self.binds[item.name]
        if not st then
            st = {x = box_x, y = box_y + h, opacity = 0, opacity_mode = 0}
            self.binds[item.name] = st
        end

        local target_y = box_y + h + (15 * count)
        if menu_open then
            st.x = box_x
            st.y = target_y
        else
            st.x = easing.quad_in(0.4, st.x, box_x - st.x, 1)
            st.y = easing.quad_in(0.4, st.y, target_y - st.y, 1)
        end

        if item.show then
            st.opacity = easing.quad_in(0.4, st.opacity, 255 - st.opacity, 1)
            st.opacity_mode = easing.quad_in(0.4, st.opacity_mode, 125 - st.opacity_mode, 1)
        else
            st.opacity = easing.quad_in(0.4, st.opacity, 0 - st.opacity, 1)
            st.opacity_mode = easing.quad_in(0.4, st.opacity_mode, 0 - st.opacity_mode, 1)
        end

        if st.opacity > 20 then
            local name = item.name:lower()
            local mode_w = renderer.measure_text("", item.mode)
            renderer.text(st.x + 5, st.y + h / 2, 225, 225, 232, st.opacity, "", 0, name)
            renderer.text(st.x + self.width - mode_w + 15, st.y + h / 2, 226, 226, 226, st.opacity_mode, "", 0, item.mode)
            count = count + 1
        end
    end
end

-- ===== Steam avatar box (ported from EmberLash) =====
-- Fetches the local player's Steam avatar via gamesense/images, rounds its
-- corners with ffi and draws it in its OWN box, disconnected from the
-- watermark and framed to match whichever watermark style is active.
-- Lives on the UI table so no new chunk-level locals are introduced.
UI.avatar = {
    tex = nil,        -- rounded avatar texture handle
    steam64 = nil,    -- steam64 the current texture belongs to
    last_try = 0
}

function UI.avatar.round(img, radius)
    if not img or img.type ~= "rgba" then return nil end

    local w, h = img.width, img.height
    radius = math.min(radius or math.floor(math.min(w, h) * 0.25), math.floor(math.min(w, h) / 2))

    local size = #img.contents
    local src = ffi.cast("uint8_t*", ffi.cast("const char*", img.contents))
    local dst = ffi.new("uint8_t[?]", size)
    ffi.copy(dst, src, size)

    local function inside(px, py, cx, cy, r)
        local dx, dy = px - cx, py - cy
        return dx * dx + dy * dy <= r * r
    end

    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local keep = true
            if x < radius and y < radius then
                keep = inside(x, y, radius, radius, radius)
            elseif x >= w - radius and y < radius then
                keep = inside(x, y, w - radius - 1, radius, radius)
            elseif x < radius and y >= h - radius then
                keep = inside(x, y, radius, h - radius - 1, radius)
            elseif x >= w - radius and y >= h - radius then
                keep = inside(x, y, w - radius - 1, h - radius - 1, radius)
            end
            if not keep then
                dst[(y * w + x) * 4 + 3] = 0
            end
        end
    end

    return renderer.load_rgba(ffi.string(dst, size), w, h)
end

function UI.avatar.ensure()
    local lp = entity.get_local_player()
    if not lp then return end

    local s64 = entity.get_steam64(lp)
    if not s64 or s64 == 0 then return end
    if UI.avatar.tex and UI.avatar.steam64 == s64 then return end

    -- throttle retries: the avatar may not be cached by Steam yet
    local now = globals.realtime()
    if now - UI.avatar.last_try < 1 then return end
    UI.avatar.last_try = now

    -- fully guarded: images.get_steam_avatar / renderer.load_rgba may be absent
    -- on some builds, and must never take down watermark rendering
    local ok, t = pcall(function()
        local raw = images.get_steam_avatar(s64)
        if not raw then return nil end
        return UI.avatar.round(raw, 32)
    end)

    if ok and t then
        UI.avatar.tex = t
        UI.avatar.steam64 = s64
    end
end

-- draw the framed avatar box; its right edge sits `gap` px left of `wm_left`
function UI.avatar.draw_box(style, wm_left, box_y, box_h, r, g, b, alpha)
    if not UI.avatar.tex then return end

    local gap = 6
    local size = box_h
    local x = wm_left - gap - size
    local y = box_y
    local pad = 4

    if style == "Lavender" then
        UI.lav.rounded_rectangle(x, y, size, size, 19, 19, 19, alpha, 5)
        UI.lav.rectangle_outline(x, y, size, size, 32, 32, 32, alpha, 2, 3)
        UI.lav.fade_rect(x - 1, y, size + 2, size, 5, r, g, b, alpha, 190, size * 2)
    elseif style == "Windows" then
        UI.win_interface(x, y, size, size, r, g, b, alpha)
    elseif style == "Black" then
        renderer.rectangle(x, y, size, size, 20, 15, 20, alpha * 0.85)
        renderer.gradient(x, y, size, 2, r, g, b, alpha * 0.9, r, g, b, alpha * 0.9, true)
        renderer.gradient(x, y + size - 2, size, 2, r, g, b, alpha * 0.7, r, g, b, alpha * 0.7, true)
        renderer.rectangle(x, y, 2, size, r, g, b, alpha)
        renderer.rectangle(x + size - 2, y, 2, size, r, g, b, alpha)
    else -- Pink / default
        renderer.rectangle(x, y, size, size, 10, 8, 15, alpha * 0.6)
        renderer.gradient(x, y, size, 2, r, g, b, alpha, r, g, b, alpha, true)
        renderer.gradient(x, y + size - 1, size, 1, r, g, b, alpha * 0.4, r, g, b, alpha * 0.4, true)
    end

    -- the avatar itself (guarded: renderer.texture may vary across builds)
    pcall(renderer.texture, UI.avatar.tex, x + pad, y + pad, size - pad * 2, size - pad * 2, 255, 255, 255, alpha, "f")
end

-- ===== Setup watermark (EmberLash port): connection / performance stats =====
-- Appends FPS / Ping / Loss / Var / Timeout to the watermark text so it renders
-- across every watermark style. Lives on UI, so no new chunk-level locals.
UI.setup = {
    fps_smooth = 0,
    to = { active = false, start = nil, grace = nil, duration = 0 }
}

-- bind engine net-channel once (guarded); unavailable APIs simply zero the stats
UI.setup._net_ok = pcall(function()
    -- VEngineClient014::GetNetChannelInfo (vtable index 78) -> INetChannelInfo*
    UI.setup._get_nci = vmt_bind("engine.dll", "VEngineClient014", 78, "void*(__thiscall*)(void*)")

    local avgloss_t = ffi.typeof("float(__thiscall*)(void*, int)")
    UI.setup._avgloss = function(nc, flow)
        return ffi.cast(avgloss_t, (ffi.cast("void***", nc)[0])[11])(nc, flow)
    end

    local framerate_t = ffi.typeof("void(__thiscall*)(void*, float*, float*, float*)")
    UI.setup._framerate = function(nc, a, b, c)
        return ffi.cast(framerate_t, (ffi.cast("void***", nc)[0])[25])(nc, a, b, c)
    end
end)

function UI.setup.get_fps()
    local raw = 1 / math.max(globals.frametime(), 0.0001)
    UI.setup.fps_smooth = UI.setup.fps_smooth * 0.9 + raw * 0.1
    return math.floor(UI.setup.fps_smooth + 0.5)
end

function UI.setup.get_ping()
    return math.floor(client.latency() * 1000)
end

function UI.setup.get_loss()
    if not UI.setup._net_ok then return 0 end
    local v = 0
    pcall(function()
        local nc = UI.setup._get_nci()
        if nc == nil then return end
        local out = UI.setup._avgloss(nc, 0) or 0
        local inc = UI.setup._avgloss(nc, 1) or 0
        v = math.floor((inc + out) * 100)
    end)
    return v
end

function UI.setup.get_var()
    if not UI.setup._net_ok then return 0 end
    local v = 0
    pcall(function()
        local nc = UI.setup._get_nci()
        if nc == nil then return end
        local ft, ftd, fsd = ffi.new("float[1]"), ffi.new("float[1]"), ffi.new("float[1]")
        UI.setup._framerate(nc, ft, ftd, fsd)
        v = math.floor(ftd[0] * 1000)
    end)
    return v
end

function UI.setup.is_timeout()
    local ok, res = pcall(function()
        local ack     = globals.commandack()
        local last_o  = globals.lastoutgoingcommand()
        local choke   = globals.chokedcommands()
        local frozen  = globals.servertickcount()
        local score = 0
        if (last_o - ack) > 48 then score = score + 1 end
        if frozen == 0 then score = score + 2 end
        if choke > 20 then score = score + 1 end
        return score >= 3
    end)
    return ok and res or false
end

function UI.setup.get_timeout()
    local now = globals.realtime()
    local to = UI.setup.to
    if UI.setup.is_timeout() then
        if not to.grace then to.grace = now end
        if now - to.grace > 0.5 then
            if not to.active then to.active = true; to.start = now end
            to.duration = now - to.start
        end
    else
        to.active = false
        to.start = nil
        to.duration = 0
        to.grace = nil
    end
    return to.duration or 0
end

-- build the plain-text stats tail (single colour, matches the watermark info text)
function UI.setup.build(selected)
    if not selected then return "" end

    local function has(name)
        for _, v in ipairs(selected) do
            if v == name then return true end
        end
        return false
    end

    local parts = {}
    if has("FPS")     then parts[#parts + 1] = tostring(UI.setup.get_fps()) .. " FPS" end
    if has("Ping")    then parts[#parts + 1] = tostring(UI.setup.get_ping()) .. " MS" end
    if has("Loss")    then parts[#parts + 1] = tostring(UI.setup.get_loss()) .. "% LOSS" end
    if has("Var")     then parts[#parts + 1] = tostring(UI.setup.get_var()) .. " VAR" end
    if has("Timeout") then parts[#parts + 1] = string.format("%.1fs TIMEOUT", UI.setup.get_timeout()) end

    if #parts == 0 then return "" end
    return " | " .. table.concat(parts, " | ")
end

local function draw_keybinds()
    if not ui.get(UI.enabled) or not ui.get(UI.keybinds) then
        keybinds_alpha = 0
        keybind_item_anims = {}
        return
    end
    
    local screen_x, screen_y = client.screen_size()
    
    local kb_r, kb_g, kb_b, kb_a = ui.get(UI.keybinds_color)
    local P_R, P_G, P_B = kb_r, kb_g, kb_b
    
    local size = ui.get(UI.keybinds_size)
    local style = ui.get(UI.keybinds_style)
    local anim_mode = ui.get(UI.keybinds_anim)

    -- Lavender style is a self-contained port; render it and bail out early
    if style == "Lavender" then
        UI.lav.draw(P_R, P_G, P_B)
        return
    end

    local is_windows = (style == "Windows")
    -- Масштаб: в стиле Windows держим компактно (как multi panel в emberfix),
    -- Big лишь немного крупнее Medium, без раздувания
    local scale
    local font
    if is_windows then
        -- Шрифт как в emberfix: 'b' (bold). Заголовок будет 'cb' (centered bold).
        scale = size == "Small" and 0.9 or (size == "Big" and 1.1 or 1.0)
        font = "b"
    else
        scale = size == "Small" and 0.85 or (size == "Big" and 1.2 or 1.0)
        font = size == "Small" and "-" or (size == "Big" and "+" or "")
    end
    
    local active_binds = {}
    
    for _, bind in ipairs(keybind_refs) do
        local ref = bind.ref
        local is_active = false
        local mode_idx = 0
        local value_text = ""
        
        if type(ref) == "table" then
            if #ref == 1 then
                local state = {ui.get(ref[1])}
                if state[2] and state[2] ~= 0 then
                    if state[2] == 3 then
                        is_active = not state[1]
                    else
                        is_active = state[1]
                    end
                    mode_idx = state[2]
                end
            else
                local checkbox_state = ui.get(ref[1])
                local hotkey_state = {ui.get(ref[2])}
                if checkbox_state and hotkey_state[2] and hotkey_state[2] ~= 0 then
                    if hotkey_state[2] == 3 then
                        is_active = not hotkey_state[1]
                    else
                        is_active = hotkey_state[1]
                    end
                    mode_idx = hotkey_state[2]
                end
                
                if bind.show_value and is_active then
                    if #ref >= 3 then
                        local slider_value = ui.get(ref[3])
                        value_text = tostring(slider_value)
                    end
                end
            end
        else
            local state = {ui.get(ref)}
            if state[2] and state[2] ~= 0 then
                if state[2] == 3 then
                    is_active = not state[1]
                else
                    is_active = state[1]
                end
                mode_idx = state[2]
            end
        end
        
        if is_active and mode_idx > 0 and mode_idx <= 3 then
            table.insert(active_binds, {
                name = bind.name,
                mode = value_text ~= "" and value_text or (keybind_modes[mode_idx] or "?")
            })
        end
    end
    
    if ui.is_menu_open() and #active_binds == 0 then
        table.insert(active_binds, {name = "Menu toggled", mode = "~"})
    end
    
    local title = "keybinds"
    
    local base_w = 120
    local item_h, title_h, padding
    if is_windows then
        -- Геометрия как в multi panel emberfix: секции по ~22, боковые отступы.
        -- Заголовочная зона выше (26), чтобы надпись не пересекала верхнюю рамку/полосу.
        item_h = 22
        title_h = 26
        padding = 40
        base_w = 130
    else
        item_h = size == "Small" and 16 or (size == "Big" and 20 or 14)
        title_h = size == "Small" and 20 or (size == "Big" and 24 or 18)
        padding = size == "Small" and 35 or 20
    end
    
    local max_width = base_w
    for _, bind in ipairs(active_binds) do
        local name_w = renderer.measure_text(font, bind.name)
        local mode_w = renderer.measure_text(font, bind.mode)
        local total_w = name_w + mode_w + padding
        if total_w > max_width then
            max_width = total_w
        end
    end
    
    -- Учитываем ширину заголовка, чтобы он не упирался в боковые рамки
    if is_windows then
        local title_w = renderer.measure_text("cb", title)
        local title_needed = title_w + 24  -- запас на боковые полосы + отступы
        if title_needed > max_width then
            max_width = title_needed
        end
    end
    
    local box_w = max_width * scale
    local box_h = (title_h + (#active_binds * item_h)) * scale
    -- В стиле Windows добавляем немного места снизу под обводку окна
    if is_windows then
        box_h = box_h + 6 * scale
    end
    local box_x, box_y = keybinds_drag.get()
    
    box_x, box_y = keybinds_drag.drag(box_w, box_h)
    
    local target_alpha = (#active_binds > 0) and 255 or 0
    keybinds_alpha = keybinds_alpha + (target_alpha - keybinds_alpha) * globals.frametime() * 8
    
    if keybinds_alpha < 1 then return end
    
    local time = globals.realtime()
    local pulse = math.abs(math.sin(time * 2)) * 0.4 + 0.6
    local title_wave = 0
    
    if anim_mode == "Moving" then
    elseif anim_mode == "Moving title" then
        title_wave = math.sin(time * 3) * 3
    end
    
    if style == "Modern" then
        local gradient_shift = (math.sin(time * 1.5) + 1) / 2
        
        local color1_r = P_R + (202 - P_R) * gradient_shift
        local color1_g = P_G + (70 - P_G) * gradient_shift
        local color1_b = P_B + (205 - P_B) * gradient_shift
        
        local color2_r = 202 + (P_R - 202) * gradient_shift
        local color2_g = 70 + (P_G - 70) * gradient_shift
        local color2_b = 205 + (P_B - 205) * gradient_shift
        
        renderer.rectangle(box_x, box_y, box_w, box_h, 10, 8, 15, keybinds_alpha * 0.6)
        
        for i = 1, 2 do
            local glow_size = i * 1.5
            local glow_a = (30 / i) * (keybinds_alpha / 255)
            renderer.rectangle(box_x - glow_size, box_y - glow_size, 
                box_w + glow_size * 2, box_h + glow_size * 2,
                P_R, P_G, P_B, glow_a)
        end
        
        renderer.gradient(box_x, box_y, box_w / 2, 2,
            color1_r, color1_g, color1_b, keybinds_alpha * pulse,
            color2_r, color2_g, color2_b, keybinds_alpha * pulse, true)
        renderer.gradient(box_x + box_w / 2, box_y, box_w / 2, 2,
            color2_r, color2_g, color2_b, keybinds_alpha * pulse,
            color1_r, color1_g, color1_b, keybinds_alpha * pulse, true)
        
        renderer.gradient(box_x, box_y + box_h - 1, box_w / 2, 1,
            P_R, P_G, P_B, keybinds_alpha * 0.4,
            P_R, P_G, P_B, keybinds_alpha * 0.4, true)
        renderer.gradient(box_x + box_w / 2, box_y + box_h - 1, box_w / 2, 1,
            P_R, P_G, P_B, keybinds_alpha * 0.4,
            P_R, P_G, P_B, keybinds_alpha * 0.4, true)
        
        renderer.gradient(box_x + 2, box_y + 3, box_w - 4, 1,
            255, 255, 255, keybinds_alpha * 0.2, 255, 255, 255, 0, false)
        
        local title_y = box_y + (title_h * scale) / 2
        renderer.text(box_x + box_w / 2 + 1, title_y, 0, 0, 0, keybinds_alpha * 0.6, "c" .. font, 0, title)
        renderer.text(box_x + box_w / 2 + title_wave, title_y - 1, P_R, P_G, P_B, keybinds_alpha, "c" .. font, 0, title)
    elseif style == "Modern black" then
        local gradient_shift = (math.sin(time * 1.5) + 1) / 2
        
        local color1_r = P_R + (202 - P_R) * gradient_shift
        local color1_g = P_G + (70 - P_G) * gradient_shift
        local color1_b = P_B + (205 - P_B) * gradient_shift
        
        local color2_r = 202 + (P_R - 202) * gradient_shift
        local color2_g = 70 + (P_G - 70) * gradient_shift
        local color2_b = 205 + (P_B - 205) * gradient_shift
        
        renderer.rectangle(box_x, box_y, box_w, box_h, 15, 10, 20, keybinds_alpha * 0.95)
        
        renderer.gradient(box_x, box_y, box_w / 2, 2,
            color1_r, color1_g, color1_b, keybinds_alpha * pulse,
            color2_r, color2_g, color2_b, keybinds_alpha * pulse, true)
        renderer.gradient(box_x + box_w / 2, box_y, box_w / 2, 2,
            color2_r, color2_g, color2_b, keybinds_alpha * pulse,
            color1_r, color1_g, color1_b, keybinds_alpha * pulse, true)
        
        renderer.rectangle(box_x, box_y + box_h - 1, box_w, 1, P_R, P_G, P_B, keybinds_alpha * 0.3)
        
        local title_y = box_y + (title_h * scale) / 2
        renderer.text(box_x + box_w / 2 + 1, title_y, 0, 0, 0, keybinds_alpha * 0.6, "c" .. font, 0, title)
        renderer.text(box_x + box_w / 2 + title_wave, title_y - 1, P_R, P_G, P_B, keybinds_alpha, "c" .. font, 0, title)
    elseif style == "Windows" then
        -- Окно в стиле emberfix: фон + акцентная полоса + боковые полосы + тройная обводка
        win_create_interface(box_x, box_y, box_w, box_h, P_R, P_G, P_B, keybinds_alpha)

        -- Заголовок: центрируем по вертикали в заголовочной зоне, ниже верхней обводки
        local center_x = box_x + box_w / 2
        local _, th = renderer.measure_text("cb", title)
        local zone_top = box_y + 5            -- ниже верхней обводки
        local zone_bottom = box_y + (title_h * scale)
        local title_y = zone_top + ((zone_bottom - zone_top) - th) / 2
        renderer.text(center_x + title_wave + 1, title_y + 1, 0, 0, 0, keybinds_alpha * 0.6, "cb", 0, title)
        renderer.text(center_x + title_wave, title_y, 255, 255, 255, keybinds_alpha, "cb", 0, title)
    else
        renderer.text(box_x + box_w / 2 + 1, box_y + 1, 0, 0, 0, keybinds_alpha * 0.4, "c" .. font, 0, title)
        renderer.text(box_x + box_w / 2 + title_wave, box_y, P_R, P_G, P_B, keybinds_alpha, "c" .. font, 0, title)
        
        local line_y = box_y + (title_h * scale) - 4
        renderer.gradient(box_x, line_y, box_w / 2, 1,
            P_R, P_G, P_B, keybinds_alpha * 0.8,
            P_R, P_G, P_B, keybinds_alpha * 0.8, true)
        renderer.gradient(box_x + box_w / 2, line_y, box_w / 2, 1,
            P_R, P_G, P_B, keybinds_alpha * 0.8,
            P_R, P_G, P_B, keybinds_alpha * 0.8, true)
    end
    
    local y_offset = box_y + (title_h * scale)
    for i, bind in ipairs(active_binds) do
        if not keybind_item_anims[bind.name] then
            keybind_item_anims[bind.name] = {alpha = 0, slide = -20}
        end
        
        local anim = keybind_item_anims[bind.name]
        anim.alpha = anim.alpha + (255 - anim.alpha) * globals.frametime() * 10
        anim.slide = anim.slide + (0 - anim.slide) * globals.frametime() * 12
        
        local item_alpha = (keybinds_alpha / 255) * anim.alpha
        local hover_wave = 0
        local bounce_offset = 0
        
        if anim_mode == "Moving" then
            hover_wave = math.sin(time * 4 + i) * 2
        elseif anim_mode == "Bouncy" then
            bounce_offset = math.abs(math.sin(time * 3 + i * 0.5)) * 3
        end
        
        local mode_w = renderer.measure_text(font, bind.mode)
        local text_x = box_x + 8 + anim.slide + hover_wave
        local text_y = y_offset - bounce_offset
        
        if style == "Modern" or style == "Modern black" then
            renderer.text(text_x + 1, text_y + 1, 0, 0, 0, item_alpha * 0.5, font, 0, bind.name)
            renderer.text(text_x, text_y, P_R, P_G, P_B, item_alpha, font, 0, bind.name)
            
            renderer.text(box_x + box_w - mode_w - 7, text_y + 1, 0, 0, 0, item_alpha * 0.4, font, 0, bind.mode)
            renderer.text(box_x + box_w - mode_w - 8, text_y, P_R, P_G, P_B, item_alpha, font, 0, bind.mode)
            
            local dot_x = box_x + 4 + anim.slide
            local dot_pulse = math.abs(math.sin(time * 3 + i * 0.5)) * 0.5 + 0.5
            renderer.circle(dot_x, text_y + 4, P_R, P_G, P_B, item_alpha * dot_pulse, 1.5, 0, 1)
        elseif style == "Windows" then
            -- Имя бинда слева (белое), режим справа (акцентный цвет), с отступами от боковых полос
            local win_x = box_x + 12 + anim.slide + hover_wave
            renderer.text(win_x + 1, text_y + 1, 0, 0, 0, item_alpha * 0.5, font, 0, bind.name)
            renderer.text(win_x, text_y, 255, 255, 255, item_alpha, font, 0, bind.name)

            renderer.text(box_x + box_w - mode_w - 11, text_y + 1, 0, 0, 0, item_alpha * 0.5, font, 0, bind.mode)
            renderer.text(box_x + box_w - mode_w - 12, text_y, P_R, P_G, P_B, item_alpha, font, 0, bind.mode)
        else
            renderer.text(box_x + 1, text_y + 1, 0, 0, 0, item_alpha * 0.3, font, 0, bind.name)
            renderer.text(box_x, text_y, P_R, P_G, P_B, item_alpha, font, 0, bind.name)
            
            renderer.text(box_x + box_w - mode_w + 1, text_y + 1, 0, 0, 0, item_alpha * 0.3, font, 0, bind.mode)
            renderer.text(box_x + box_w - mode_w, text_y, P_R, P_G, P_B, item_alpha, font, 0, bind.mode)
        end
        
        y_offset = y_offset + (item_h * scale)
    end
    
    for name, anim in pairs(keybind_item_anims) do
        local found = false
        for _, bind in ipairs(active_binds) do
            if bind.name == name then
                found = true
                break
            end
        end
        if not found then
            anim.alpha = anim.alpha - globals.frametime() * 800
            anim.slide = anim.slide - globals.frametime() * 60
            if anim.alpha <= 0 then
                keybind_item_anims[name] = nil
            end
        end
    end
    
    local items_to_render = {}
    for name, anim in pairs(keybind_item_anims) do
        local found = false
        local bind_data = nil
        for _, bind in ipairs(active_binds) do
            if bind.name == name then
                found = true
                bind_data = bind
                break
            end
        end
        if not found and anim.alpha > 0 then
            table.insert(items_to_render, {name = name, mode = "", anim = anim})
        end
    end
    
    for i, item in ipairs(items_to_render) do
        local anim = item.anim
        local item_alpha = (keybinds_alpha / 255) * anim.alpha
        local y_pos = box_y + (title_h * scale) + (#active_binds + i - 1) * (item_h * scale)
        
        if style == "Modern" or style == "Modern black" then
            renderer.text(box_x + 8 + anim.slide + 1, y_pos + 1, 0, 0, 0, item_alpha * 0.5, font, 0, item.name)
            renderer.text(box_x + 8 + anim.slide, y_pos, 255, 200, 230, item_alpha, font, 0, item.name)
            
            local dot_x = box_x + 4 + anim.slide
            renderer.circle(dot_x, y_pos + 4, P_R, P_G, P_B, item_alpha * 0.5, 1.5, 0, 1)
        elseif style == "Windows" then
            renderer.text(box_x + 8 + anim.slide + 1, y_pos + 1, 0, 0, 0, item_alpha * 0.5, font, 0, item.name)
            renderer.text(box_x + 8 + anim.slide, y_pos, 200, 200, 200, item_alpha, font, 0, item.name)
        else
            renderer.text(box_x + 1, y_pos + 1, 0, 0, 0, item_alpha * 0.3, font, 0, item.name)
            renderer.text(box_x, y_pos, 255, 200, 230, item_alpha, font, 0, item.name)
        end
    end
    
    if style == "Modern" or style == "Modern black" then
        local corner_time = time * 4
        for i = 1, 3 do
            local corner_x = box_x + box_w - 4 - (i * 3)
            local corner_y = box_y + 6
            local corner_alpha = (math.abs(math.sin(corner_time + i)) * 0.6 + 0.4) * keybinds_alpha
            renderer.circle(corner_x, corner_y, P_R, P_G, P_B, corner_alpha * 0.8, 1, 0, 1)
        end
    end
end


local scope_overlay_ref = ui.reference('VISUALS', 'Effects', 'Remove scope overlay')
local scope_alpha = 0

local function draw_scope_lines()
    if not ui.get(UI.enabled) or not ui.get(UI.scope) then
        return
    end
    ui.set(scope_overlay_ref, false)
    
    local width, height = client.screen_size()
    local style = ui.get(UI.scope_style)
    local r, g, b, a = ui.get(UI.scope_color)
    local thickness = ui.get(UI.scope_thickness)
    local length = ui.get(UI.scope_length) * height / 1080
    local gap = ui.get(UI.scope_gap) * height / 1080
    local speed = ui.get(UI.scope_fade)
    local glow = ui.get(UI.scope_glow)
    
    local me = entity.get_local_player()
    if not me then return end
    local wpn = entity.get_player_weapon(me)
    if not wpn then return end
    
    local scope_level = entity.get_prop(wpn, 'm_zoomLevel')
    local scoped = entity.get_prop(me, 'm_bIsScoped') == 1
    local resume_zoom = entity.get_prop(me, 'm_bResumeZoom') == 1
    
    local is_valid = entity.is_alive(me) and wpn ~= nil and scope_level ~= nil
    local act = is_valid and scope_level > 0 and scoped and not resume_zoom
    
    local FT = speed > 3 and globals.frametime() * speed or 1
    local alpha_mult = easing.linear(scope_alpha, 0, 1, 1)
    
    local cx, cy = width / 2, height / 2
    
    local function draw_line_segment(x1, y1, x2, y2, cr, cg, cb, ca, cr2, cg2, cb2, ca2, is_horizontal)
        local line_length = is_horizontal and math.abs(x2 - x1) or math.abs(y2 - y1)
        
        if style == "Dotted" then
            local dot_len = 4
            local dot_gap = 4
            local pos = 0
            while pos < line_length do
                local seg_len = math.min(dot_len, line_length - pos)
                local frac_start = pos / line_length
                local frac_end = (pos + seg_len) / line_length
                local sr = cr + (cr2 - cr) * frac_start
                local sg = cg + (cg2 - cg) * frac_start
                local sb = cb + (cb2 - cb) * frac_start
                local sa = ca + (ca2 - ca) * frac_start
                local er = cr + (cr2 - cr) * frac_end
                local eg = cg + (cg2 - cg) * frac_end
                local eb = cb + (cb2 - cb) * frac_end
                local ea = ca + (ca2 - ca) * frac_end
                
                if is_horizontal then
                    local dir = x2 > x1 and 1 or -1
                    local sx = x1 + pos * dir
                    for t = 0, thickness - 1 do
                        renderer.gradient(sx, y1 + t, seg_len, 1, sr, sg, sb, sa, er, eg, eb, ea, true)
                    end
                else
                    local dir = y2 > y1 and 1 or -1
                    local sy = y1 + pos * dir
                    for t = 0, thickness - 1 do
                        renderer.gradient(x1 + t, sy, 1, seg_len, sr, sg, sb, sa, er, eg, eb, ea, false)
                    end
                end
                pos = pos + dot_len + dot_gap
            end
        else
            if is_horizontal then
                for t = 0, thickness - 1 do
                    renderer.gradient(math.min(x1, x2), y1 + t, line_length, 1, cr, cg, cb, ca, cr2, cg2, cb2, ca2, true)
                end
            else
                for t = 0, thickness - 1 do
                    renderer.gradient(x1 + t, math.min(y1, y2), 1, line_length, cr, cg, cb, ca, cr2, cg2, cb2, ca2, false)
                end
            end
        end
    end
    
    local function draw_glow_layer(x1, y1, x2, y2, cr, cg, cb, base_a, is_horizontal)
        for i = 1, 3 do
            local offset = i * 1.5
            local glow_a = base_a * (0.25 / i)
            if is_horizontal then
                renderer.gradient(math.min(x1, x2), y1 - offset, math.abs(x2 - x1), 1, cr, cg, cb, 0, cr, cg, cb, glow_a, true)
                renderer.gradient(math.min(x1, x2), y1 + offset, math.abs(x2 - x1), 1, cr, cg, cb, 0, cr, cg, cb, glow_a, true)
            else
                renderer.gradient(x1 - offset, math.min(y1, y2), 1, math.abs(y2 - y1), cr, cg, cb, 0, cr, cg, cb, glow_a, false)
                renderer.gradient(x1 + offset, math.min(y1, y2), 1, math.abs(y2 - y1), cr, cg, cb, 0, cr, cg, cb, glow_a, false)
            end
        end
    end
    
    local aa = alpha_mult * a
    local r2, g2, b2, a2_raw = r, g, b, a
    if style == "Dual color" then
        r2, g2, b2, a2_raw = ui.get(UI.scope_color2)
    elseif style == "Rainbow" then
        local hue1 = rainbow_hue
        local hue2 = (hue1 + 0.25) % 1.0
        r, g, b = hsv_to_rgb(hue1, 0.8, 1.0)
        r2, g2, b2 = hsv_to_rgb(hue2, 0.8, 1.0)
        a2_raw = a
    end
    local aa2 = alpha_mult * a2_raw
    
    local remove_lines = ui.get(UI.scope_remove_lines)
    local remove_left = false
    local remove_right = false
    local remove_up = false
    local remove_down = false
    
    for i = 1, #remove_lines do
        if remove_lines[i] == "Left" then
            remove_left = true
        elseif remove_lines[i] == "Right" then
            remove_right = true
        elseif remove_lines[i] == "Up" then
            remove_up = true
        elseif remove_lines[i] == "Down" then
            remove_down = true
        end
    end

    if not remove_left then
        draw_line_segment(cx - length, cy, cx - gap, cy, r, g, b, 0, r2, g2, b2, aa2, true)
    end
 
    if not remove_right then
        draw_line_segment(cx + gap, cy, cx + length, cy, r2, g2, b2, aa2, r, g, b, 0, true)
    end
 
    if not remove_up then
        draw_line_segment(cx, cy - length, cx, cy - gap, r, g, b, 0, r2, g2, b2, aa2, false)
    end
 
    if not remove_down then
        draw_line_segment(cx, cy + gap, cx, cy + length, r2, g2, b2, aa2, r, g, b, 0, false)
    end
    
    if glow then
        if not remove_left then
            draw_glow_layer(cx - length, cy, cx - gap, cy, r, g, b, aa, true)
        end
        if not remove_right then
            draw_glow_layer(cx + gap, cy, cx + length, cy, r, g, b, aa, true)
        end
        if not remove_up then
            draw_glow_layer(cx, cy - length, cx, cy - gap, r, g, b, aa, false)
        end
        if not remove_down then
            draw_glow_layer(cx, cy + gap, cx, cy + length, r, g, b, aa, false)
        end
    end
    
    scope_alpha = math.max(0, math.min(1, scope_alpha + (act and FT or -FT)))
end

local function scope_paint_ui()
    if not ui.get(UI.enabled) or not ui.get(UI.scope) then return end
    ui.set(scope_overlay_ref, true)
end


local tracer_queue = {}

local grenade_trails = {}
local grenade_entities = {}

local function on_bullet_impact(e)
    if not ui.get(UI.enabled) or not ui.get(UI.tracers) then return end
    if client.userid_to_entindex(e.userid) ~= entity.get_local_player() then return end
    

    local limit = ui.get(UI.tracers_limit)
    local count = 0
    local oldest_tick = nil
    for tick, _ in pairs(tracer_queue) do
        count = count + 1
        if oldest_tick == nil or tick < oldest_tick then
            oldest_tick = tick
        end
    end
    if count >= limit and oldest_tick then
        tracer_queue[oldest_tick] = nil
    end
    
    local lx, ly, lz = client.eye_position()
    local duration = ui.get(UI.tracers_duration)
    tracer_queue[globals.tickcount()] = {
        lx, ly, lz, e.x, e.y, e.z,
        globals.curtime() + duration,
        globals.curtime(),
        duration
    }
end

local function draw_tracers()
    if not ui.get(UI.enabled) or not ui.get(UI.tracers) then return end
    
    local style = ui.get(UI.tracers_style)
    local r, g, b, a = ui.get(UI.tracers_color)
    local glow_on = ui.get(UI.tracers_glow)
    local glow_int = ui.get(UI.tracers_glow_intensity)
    local anim = ui.get(UI.tracers_anim)
    local thickness = ui.get(UI.tracers_thickness)
    local cur_time = globals.curtime()
    local time_val = globals.realtime()
    
    local r2, g2, b2, a2 = r, g, b, a
    if style == "Gradient" then
        r2, g2, b2, a2 = ui.get(UI.tracers_color2)
    end
    
    for tick, data in pairs(tracer_queue) do
        local end_time = data[7]
        local start_time = data[8]
        local total_dur = data[9]
        
        if cur_time > end_time then
            tracer_queue[tick] = nil
        else
            local time_alive = cur_time - start_time
            local time_remaining = end_time - cur_time
            local life_frac = time_alive / total_dur
            
            local sx, sy, sz = data[1], data[2], data[3]
            local ex, ey, ez = data[4], data[5], data[6]
            
            if anim == "Shrink" then
                sx = sx + (ex - sx) * life_frac
                sy = sy + (ey - sy) * life_frac
                sz = sz + (ez - sz) * life_frac
            end
            
            local x1, y1 = renderer.world_to_screen(sx, sy, sz)
            local x2, y2 = renderer.world_to_screen(ex, ey, ez)
            
            if (x1 == nil or y1 == nil) and (x2 ~= nil and y2 ~= nil) then
                local clip_sx, clip_sy, clip_sz = sx, sy, sz
                local mid_ex, mid_ey, mid_ez = ex, ey, ez
                for _ = 1, 8 do
                    local mx = (clip_sx + mid_ex) * 0.5
                    local my = (clip_sy + mid_ey) * 0.5
                    local mz = (clip_sz + mid_ez) * 0.5
                    local tx, ty = renderer.world_to_screen(mx, my, mz)
                    if tx ~= nil and ty ~= nil then
                        mid_ex, mid_ey, mid_ez = mx, my, mz
                        x1, y1 = tx, ty
                    else
                        clip_sx, clip_sy, clip_sz = mx, my, mz
                    end
                end
            elseif (x2 == nil or y2 == nil) and (x1 ~= nil and y1 ~= nil) then
                local clip_ex, clip_ey, clip_ez = ex, ey, ez
                local mid_sx, mid_sy, mid_sz = sx, sy, sz
                for _ = 1, 8 do
                    local mx = (mid_sx + clip_ex) * 0.5
                    local my = (mid_sy + clip_ey) * 0.5
                    local mz = (mid_sz + clip_ez) * 0.5
                    local tx, ty = renderer.world_to_screen(mx, my, mz)
                    if tx ~= nil and ty ~= nil then
                        mid_sx, mid_sy, mid_sz = mx, my, mz
                        x2, y2 = tx, ty
                    else
                        clip_ex, clip_ey, clip_ez = mx, my, mz
                    end
                end
            end
            
            if x1 ~= nil and x2 ~= nil and y1 ~= nil and y2 ~= nil then
                local draw_a = a
                local draw_a2 = a2
                
                if time_remaining < 0.5 then
                    local fade = time_remaining / 0.5
                    draw_a = draw_a * fade
                    draw_a2 = draw_a2 * fade
                end
                
                if anim == "Pulse" then
                    local pulse = (math.sin(time_val * 8 + tick * 0.1) * 0.4 + 0.6)
                    draw_a = draw_a * pulse
                    draw_a2 = draw_a2 * pulse
                end
                
                local dr, dg, db = r, g, b
                local dr2, dg2, db2 = r2, g2, b2
                
                if style == "Rainbow" then
                    local hue = (rainbow_hue + tick * 0.001) % 1.0
                    dr, dg, db = hsv_to_rgb(hue, 0.8, 1.0)
                    local hue2 = (hue + 0.3) % 1.0
                    dr2, dg2, db2 = hsv_to_rgb(hue2, 0.8, 1.0)
                end
                
                if anim == "Fade out" then
                    draw_a2 = 0
                end
                
                if glow_on then
                    for i = 1, glow_int do
                        local offset = i * 1.5
                        local ga = draw_a * (0.2 / i)
                        renderer.line(x1 + offset, y1 + offset, x2 + offset, y2 + offset, dr, dg, db, ga)
                        renderer.line(x1 - offset, y1 - offset, x2 - offset, y2 - offset, dr, dg, db, ga)
                        renderer.line(x1 + offset, y1 - offset, x2 + offset, y2 - offset, dr, dg, db, ga)
                        renderer.line(x1 - offset, y1 + offset, x2 - offset, y2 + offset, dr, dg, db, ga)
                    end
                end
                
                local function draw_thick_line(lx1, ly1, lx2, ly2, lr, lg, lb, la)
                    for t = 0, thickness - 1 do
                        local offset = t - (thickness - 1) / 2
                        renderer.line(lx1 + offset, ly1, lx2 + offset, ly2, lr, lg, lb, la)
                        if t > 0 then
                            renderer.line(lx1, ly1 + offset, lx2, ly2 + offset, lr, lg, lb, la)
                        end
                    end
                end
                
                if style == "Gradient" or style == "Rainbow" then
                    local segments = 10
                    for s = 0, segments - 1 do
                        local t1 = s / segments
                        local t2 = (s + 1) / segments
                        local lx1 = x1 + (x2 - x1) * t1
                        local ly1 = y1 + (y2 - y1) * t1
                        local lx2 = x1 + (x2 - x1) * t2
                        local ly2 = y1 + (y2 - y1) * t2
                        local lr = dr + (dr2 - dr) * t1
                        local lg = dg + (dg2 - dg) * t1
                        local lb = db + (db2 - db) * t1
                        local la = draw_a + (draw_a2 - draw_a) * t1
                        draw_thick_line(lx1, ly1, lx2, ly2, lr, lg, lb, la)
                    end
                else
                    if anim == "Fade out" then
                        local segments = 10
                        for s = 0, segments - 1 do
                            local t1 = s / segments
                            local t2 = (s + 1) / segments
                            local lx1 = x1 + (x2 - x1) * t1
                            local ly1 = y1 + (y2 - y1) * t1
                            local lx2 = x1 + (x2 - x1) * t2
                            local ly2 = y1 + (y2 - y1) * t2
                            local la = draw_a * (1 - t1)
                            draw_thick_line(lx1, ly1, lx2, ly2, dr, dg, db, la)
                        end
                    else
                        draw_thick_line(x1, y1, x2, y2, dr, dg, db, draw_a)
                    end
                end
            end
        end
    end
end


local trail_queue = {}

local function on_setup_command(c)
    if not ui.get(UI.enabled) or not ui.get(UI.trails) then return end
    
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end
    
    local x, y, z = entity.get_origin(me)
    if not x then return end
    
    local vx, vy, vz = entity.get_prop(me, "m_vecVelocity")
    local velocity = 0
    if vx then
        velocity = math.sqrt(vx*vx + vy*vy)
    end
    
    local dx, dy = 0, 0
    if #trail_queue > 0 then
        local last = trail_queue[#trail_queue]
        dx, dy = x - last.x, y - last.y
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist < 4 then return end 
        dx = dx / dist
        dy = dy / dist
    else
        dx, dy = 1, 0
    end
    
    local nx = -dy
    local ny = dx
    
    local duration = ui.get(UI.trails_duration) / 10
    table.insert(trail_queue, {
        x = x, y = y, z = z,
        nx = nx, ny = ny,
        end_time = globals.curtime() + duration,
        start_time = globals.curtime(),
        duration = duration,
        velocity = velocity
    })
    
    if #trail_queue > 500 then
        table.remove(trail_queue, 1)
    end
end

local function draw_trails()
    if not ui.get(UI.enabled) or not ui.get(UI.trails) then return end
    
    local cur_time = globals.curtime()
    local new_queue = {}
    
    for _, pt in ipairs(trail_queue) do
        if cur_time <= pt.end_time then
            table.insert(new_queue, pt)
        end
    end
    trail_queue = new_queue
    
    local style = ui.get(UI.trails_style)
    local r, g, b, a = ui.get(UI.trails_color)
    local r2, g2, b2, a2 = r, g, b, a
    if style == "Gradient" then
        r2, g2, b2 = ui.get(UI.trails_color2)
    end
    
    local thickness = ui.get(UI.trails_thickness) / 10
    local glow_on = ui.get(UI.trails_glow)
    local glow_thickness = ui.get(UI.trails_glow_thickness) / 10
    local anim = ui.get(UI.trails_anim)
    local q_len = #trail_queue
    
    if q_len < 2 then return end
    
    for i = 1, q_len - 1 do
        local p1 = trail_queue[i]
        local p2 = trail_queue[i+1]
        
        local t1 = i / q_len
        
        local l1_x, l1_y = renderer.world_to_screen(p1.x + p1.nx * thickness, p1.y + p1.ny * thickness, p1.z)
        local r1_x, r1_y = renderer.world_to_screen(p1.x - p1.nx * thickness, p1.y - p1.ny * thickness, p1.z)
        local l2_x, l2_y = renderer.world_to_screen(p2.x + p2.nx * thickness, p2.y + p2.ny * thickness, p2.z)
        local r2_x, r2_y = renderer.world_to_screen(p2.x - p2.nx * thickness, p2.y - p2.ny * thickness, p2.z)
        
        if l1_x ~= nil and l1_y ~= nil and r1_x ~= nil and r1_y ~= nil and 
           l2_x ~= nil and l2_y ~= nil and r2_x ~= nil and r2_y ~= nil then
            
            local dr, dg, db = r, g, b
            local da = a
            
            local life_frac = (cur_time - p1.start_time) / p1.duration
            
            if anim == "Fade out" then
                da = math.max(0, a * (1 - life_frac))
            elseif anim == "Wave" then
                da = a * (0.6 + 0.4 * math.sin(cur_time * 4 - i * 0.15))
            end
            
            if style == "Gradient" then
                dr = r + (r2 - r) * t1
                dg = g + (g2 - g) * t1
                db = b + (b2 - b) * t1
            elseif style == "Rainbow" then
                local hue = (rainbow_hue + i * 0.01) % 1.0
                dr, dg, db = hsv_to_rgb(hue, 0.8, 1.0)
            end
            
            renderer.triangle(l1_x, l1_y, r1_x, r1_y, l2_x, l2_y, dr, dg, db, da)
            renderer.triangle(r1_x, r1_y, r2_x, r2_y, l2_x, l2_y, dr, dg, db, da)
            
            if glow_on then
                local gl1_x, gl1_y = renderer.world_to_screen(p1.x + p1.nx * (thickness + glow_thickness), p1.y + p1.ny * (thickness + glow_thickness), p1.z)
                local gr1_x, gr1_y = renderer.world_to_screen(p1.x - p1.nx * (thickness + glow_thickness), p1.y - p1.ny * (thickness + glow_thickness), p1.z)
                local gl2_x, gl2_y = renderer.world_to_screen(p2.x + p2.nx * (thickness + glow_thickness), p2.y + p2.ny * (thickness + glow_thickness), p2.z)
                local gr2_x, gr2_y = renderer.world_to_screen(p2.x - p2.nx * (thickness + glow_thickness), p2.y - p2.ny * (thickness + glow_thickness), p2.z)
                if gl1_x and gr1_x and gl2_x and gr2_x then
                    local ga = da * 0.25
                    renderer.triangle(gl1_x, gl1_y, gr1_x, gr1_y, gl2_x, gl2_y, dr, dg, db, ga)
                    renderer.triangle(gr1_x, gr1_y, gr2_x, gr2_y, gl2_x, gl2_y, dr, dg, db, ga)
                end
            end
        end
    end
end

local function update_grenade_trails()
    if not ui.get(UI.enabled) or not ui.get(UI.grenade_trail) then return end
    
    local lp = entity.get_local_player()
    if not lp then return end
    
    local all_grenades = {}
    
    local grenade_classes = {
        "CBaseCSGrenadeProjectile",
        "CSmokeGrenadeProjectile",
        "CMolotovProjectile",
        "CInferno"
    }
    
    for _, class_name in ipairs(grenade_classes) do
        local grenades = entity.get_all(class_name)
        for _, ent in ipairs(grenades) do
            local owner = entity.get_prop(ent, "m_hOwnerEntity")
            if owner == lp then
                table.insert(all_grenades, ent)
            end
        end
    end
    
    local cur_time = globals.curtime()
    local duration = ui.get(UI.grenade_trail_duration) / 10
    
    for _, ent in ipairs(all_grenades) do
        if not grenade_entities[ent] then
            grenade_entities[ent] = {
                positions = {},
                last_update = cur_time
            }
        end
        
        local x, y, z = entity.get_prop(ent, "m_vecOrigin")
        if x and y and z then
            local data = grenade_entities[ent]
            
            if #data.positions == 0 or cur_time - data.last_update > 0.01 then
                table.insert(data.positions, {x = x, y = y, z = z, time = cur_time})
                data.last_update = cur_time
            end
        end
    end
    
    for ent, data in pairs(grenade_entities) do
        local new_positions = {}
        for _, pos in ipairs(data.positions) do
            if cur_time - pos.time <= duration then
                table.insert(new_positions, pos)
            end
        end
        data.positions = new_positions
        
        if #data.positions == 0 then
            grenade_entities[ent] = nil
        end
    end
end

local function draw_grenade_trails()
    if not ui.get(UI.enabled) or not ui.get(UI.grenade_trail) then return end
    
    local style = ui.get(UI.grenade_trail_style)
    local r, g, b, a = ui.get(UI.grenade_trail_color)
    local r2, g2, b2 = r, g, b
    if style == "Gradient" then
        r2, g2, b2 = ui.get(UI.grenade_trail_color2)
    end
    
    local thickness = ui.get(UI.grenade_trail_thickness)
    local glow_on = ui.get(UI.grenade_trail_glow)
    local glow_intensity = ui.get(UI.grenade_trail_glow_intensity)
    
    for ent, data in pairs(grenade_entities) do
        local positions = data.positions
        local pos_count = #positions
        
        if pos_count >= 2 then
            for i = 1, pos_count - 1 do
                local p1 = positions[i]
                local p2 = positions[i + 1]
                
                local x1, y1 = renderer.world_to_screen(p1.x, p1.y, p1.z)
                local x2, y2 = renderer.world_to_screen(p2.x, p2.y, p2.z)
                
                if x1 and y1 and x2 and y2 then
                    local t = i / pos_count
                    local dr, dg, db = r, g, b
                    
                    if style == "Gradient" then
                        dr = r + (r2 - r) * t
                        dg = g + (g2 - g) * t
                        db = b + (b2 - b) * t
                    elseif style == "Rainbow" then
                        local hue = (rainbow_hue + i * 0.02) % 1.0
                        dr, dg, db = hsv_to_rgb(hue, 0.8, 1.0)
                    end
                    
                    local function draw_thick_line_grenade(lx1, ly1, lx2, ly2, lr, lg, lb, la, line_thickness)
                        for t = 0, line_thickness - 1 do
                            local offset = t - (line_thickness - 1) / 2
                            local angle = math.atan2(ly2 - ly1, lx2 - lx1) + math.pi / 2
                            local ox = math.cos(angle) * offset
                            local oy = math.sin(angle) * offset
                            renderer.line(lx1 + ox, ly1 + oy, lx2 + ox, ly2 + oy, lr, lg, lb, la)
                        end
                    end
                    
                    if glow_on then
                        for j = glow_intensity, 1, -1 do
                            local glow_thickness = thickness + j * 2
                            local glow_alpha = (a * 0.2) / j
                            draw_thick_line_grenade(x1, y1, x2, y2, dr, dg, db, glow_alpha, glow_thickness)
                        end
                    end
                    
                    draw_thick_line_grenade(x1, y1, x2, y2, dr, dg, db, a, thickness)
                end
            end
        end
    end
end

local function on_round_prestart()
    tracer_queue = {}
    trail_queue = {}
    healthbar_players = {}
    grenade_entities = {}
end

local indicator_anims = {}
local healthbar_players = {}

local function lerp(a, b, percentage)
    return a + (b - a) * percentage
end

local function draw_healthbar()
    if not ui.get(UI.enabled) or not ui.get(UI.healthbar) then return end
    
    local style = ui.get(UI.healthbar_style)
    local r_full, g_full, b_full, a_full = ui.get(UI.healthbar_color_full)
    local r_empty, g_empty, b_empty, a_empty = ui.get(UI.healthbar_color_empty)
    
    local local_player = entity.get_local_player()
    local force_teammates = false or ui.get(ui.reference("Visuals", "Player ESP", "Teammates"))
    
    if not entity.is_alive(local_player) then
        local m_iObserverMode = entity.get_prop(local_player, "m_iObserverMode")
        if m_iObserverMode == 4 or m_iObserverMode == 5 then
            local spectated_ent = entity.get_prop(local_player, "m_hObserverTarget")
            if entity.is_enemy(spectated_ent) then
                force_teammates = true
            end
        end
    end
    
    local enemy_players = entity.get_players(not force_teammates)
    
    for i = 1, #enemy_players do
        local e = enemy_players[i]
        if entity.is_alive(local_player) or not force_teammates or force_teammates and (not entity.is_alive(local_player) and not entity.is_enemy(e)) then
            local x1, y1, x2, y2, alpha = entity.get_bounding_box(e)
            if x1 ~= nil and y1 ~= nil and not entity.is_dormant(e) then
                local hp = entity.get_prop(e, "m_iHealth")
                local height = y2 - y1 + 2
                y1 = y1 - 1
                local leftside = x1 - 5
                
                if hp ~= nil then
                    local percentage = hp / 100
                    
                    renderer.rectangle(leftside - 1, y1, 4, height, 20, 20, 20, 150)
                    
                    local bar_height = math.floor(height * percentage) - 2
                    local bar_y = math.ceil(y2 - (height * percentage)) + 2
                    
                    local new_r, new_g, new_b = r_full, g_full, b_full
                    
                    if style == "Rainbow" then
                        local hue = (rainbow_hue + (1 - percentage) * 0.3) % 1.0
                        new_r, new_g, new_b = hsv_to_rgb(hue, 0.8, 1.0)
                        renderer.rectangle(leftside, bar_y, 2, bar_height, new_r, new_g, new_b, 255)
                    elseif style == "Gradient" then
                        new_r = lerp(r_empty, r_full, percentage)
                        new_g = lerp(g_empty, g_full, percentage)
                        new_b = lerp(b_empty, b_full, percentage)
                        renderer.gradient(leftside, bar_y, 2, bar_height, new_r, new_g, new_b, 255, r_empty, g_empty, b_empty, 255, false)
                    else
                        renderer.rectangle(leftside, bar_y, 2, bar_height, new_r, new_g, new_b, 255)
                    end
                    
                    if hp < 100 then
                        renderer.text(leftside - 2, bar_y, 255, 255, 255, 255, "-cd", 0, hp)
                    end
                end
            end
        end
    end
end

local function draw_indicators()
    if not ui.get(UI.enabled) or not ui.get(UI.indicators) then return end
    
    local features = ui.get(UI.indicators_features)
    if #features == 0 then return end
    
    local size_setting = ui.get(UI.indicators_size)
    local font_flag = ""
    local base_spacing = 22
    local glow_mult = 1.0
    
    if size_setting == "Small" then
        font_flag = ""
        base_spacing = 22
        glow_mult = 0.8
    elseif size_setting == "Medium" then
        font_flag = "b"
        base_spacing = 28
        glow_mult = 1.2
    elseif size_setting == "Big" then
        font_flag = "+"
        base_spacing = 36
        glow_mult = 1.5
    end
    
    local screen_x, screen_y = client.screen_size()
    local start_x = 15
    local start_y = screen_y / 2 + 80
    local spacing = base_spacing
    local cur_time = globals.curtime()
    
    local fake_duck_ref = ui.reference("RAGE", "Other", "Duck peek assist")
    
    local indicator_data = {
        {name = "Force safe point", ref = ui.reference("RAGE", "Aimbot", "Force safe point"), short = "SP", color = {255, 255, 255}},
        {name = "Force body aim", ref = ui.reference("RAGE", "Aimbot", "Force body aim"), short = "BODY", color = {255, 255, 255}},
        {name = "Ping spike", ref = {ui.reference("MISC", "Miscellaneous", "Ping spike")}, short = "PING", color = {255, 255, 255}},
        {name = "Double tap", ref = {ui.reference("RAGE", "Aimbot", "Double tap")}, short = "DT", color = {255, 255, 255}, check_charge = true},
        {name = "Duck peek assist", ref = fake_duck_ref, short = "DUCK", color = {255, 255, 255}},
        {name = "Freestanding", ref = {ui.reference("AA", "Anti-aimbot angles", "Freestanding")}, short = "FS", color = {255, 255, 255}},
        {name = "On shot anti-aim", ref = {ui.reference("AA", "Other", "On shot anti-aim")}, short = "OSAA", color = {255, 255, 255}},
        {name = "Minimum damage override", ref = mindmg_refs, short = "MD", color = {255, 255, 255}}
    }
    
    local active_indicators = {}
    
    for _, feature in ipairs(features) do
        for _, data in ipairs(indicator_data) do
            if data.name == feature then
                local is_active = false
                local is_charging = false
                
                if type(data.ref) == "table" then
                    if #data.ref > 1 then
                        is_active = ui.get(data.ref[1]) and ui.get(data.ref[2])
                    else
                        is_active = ui.get(data.ref[1])
                    end
                else
                    is_active = ui.get(data.ref)
                end
                
                if is_active and data.check_charge then
                    local local_player = entity.get_local_player()
                    if local_player then
                        local weapon = entity.get_player_weapon(local_player)
                        if weapon then
                            local next_attack = entity.get_prop(local_player, "m_flNextAttack")
                            local next_primary_attack = entity.get_prop(weapon, "m_flNextPrimaryAttack")
                            local server_time = globals.curtime()
                            
                            if next_attack and next_primary_attack then
                                is_charging = next_attack > server_time or next_primary_attack > server_time
                            end
                        end
                    end
                end
                
                if is_active then
                    local indicator_copy = {
                        name = data.name,
                        ref = data.ref,
                        short = data.short,
                        color = data.color,
                        is_charging = is_charging
                    }
                    table.insert(active_indicators, indicator_copy)
                end
                break
            end
        end
    end
    
    for i, data in ipairs(active_indicators) do
        local y_pos = start_y + (i - 1) * spacing
        
        if not indicator_anims[data.short] then
            indicator_anims[data.short] = {
                alpha = 0,
                x_offset = -30,
                glow_pulse = 0,
                sparkle_time = cur_time,
                bounce = 0
            }
        end
        
        local anim = indicator_anims[data.short]
        
        anim.alpha = anim.alpha + (255 - anim.alpha) * globals.frametime() * 8
        anim.x_offset = anim.x_offset + (0 - anim.x_offset) * globals.frametime() * 10
        anim.glow_pulse = math.abs(math.sin(cur_time * 3)) * 0.5 + 0.5
        anim.bounce = math.sin(cur_time * 4 + i * 0.5) * 2
        
        local x = start_x + anim.x_offset
        local y = y_pos + anim.bounce
        
        local ind_r, ind_g, ind_b = ui.get(UI.indicators_color)
        local r, g, b = ind_r, ind_g, ind_b
        
        if data.is_charging then
            r, g, b = 255, 80, 80
        end
        
        local alpha = anim.alpha
        
        local text_w, text_h = renderer.measure_text(font_flag, data.short)
        
        local glow_size = (8 + anim.glow_pulse * 4) * glow_mult
        renderer.circle(x + text_w / 2, y + text_h / 2, r, g, b, alpha * 0.15 * anim.glow_pulse, glow_size, 0, 1)
        renderer.circle(x + text_w / 2, y + text_h / 2, r, g, b, alpha * 0.25 * anim.glow_pulse, glow_size * 0.6, 0, 1)
        
        local sparkle_interval = 0.8
        if cur_time - anim.sparkle_time > sparkle_interval then
            anim.sparkle_time = cur_time
        end
        local sparkle_progress = (cur_time - anim.sparkle_time) / sparkle_interval
        if sparkle_progress < 0.3 then
            local sparkle_alpha = (1 - sparkle_progress / 0.3) * alpha
            local sparkle_offset = sparkle_progress * 15
            renderer.text(x + text_w + sparkle_offset, y - 2, 255, 255, 255, sparkle_alpha, "", 0, "✦")
        end
        
        renderer.text(x + 1, y + 1, 0, 0, 0, alpha * 0.7, font_flag, 0, data.short)
        
        if not data.is_charging then
            local hue_shift = (cur_time * 0.5 + i * 0.2) % 1.0
            local r2, g2, b2 = hsv_to_rgb(hue_shift, 0.3, 1.0)
            local gradient_r = r + (r2 - r) * anim.glow_pulse * 0.3
            local gradient_g = g + (g2 - g) * anim.glow_pulse * 0.3
            local gradient_b = b + (b2 - b) * anim.glow_pulse * 0.3
            
            renderer.text(x, y, gradient_r, gradient_g, gradient_b, alpha, font_flag, 0, data.short)
        else
            renderer.text(x, y, r, g, b, alpha, font_flag, 0, data.short)
        end
        
        local bar_w = text_w + 4
        local bar_h = 2
        local bar_y = y + text_h + 2
        
        if data.is_charging then
            renderer.rectangle(x, bar_y, bar_w, bar_h, 255, 80, 80, alpha * 0.8)
        else
            renderer.gradient(x, bar_y, bar_w / 2, bar_h, r, g, b, alpha * 0.8, r, g, b, alpha * 0.8, true)
            renderer.gradient(x + bar_w / 2, bar_y, bar_w / 2, bar_h, r, g, b, alpha * 0.8, r, g, b, alpha * 0.8, true)
        end
    end
    
    for short, anim in pairs(indicator_anims) do
        local found = false
        for _, data in ipairs(active_indicators) do
            if data.short == short then
                found = true
                break
            end
        end
        
        if not found then
            anim.alpha = anim.alpha + (0 - anim.alpha) * globals.frametime() * 12
            anim.x_offset = anim.x_offset + (-30 - anim.x_offset) * globals.frametime() * 10
            
            if anim.alpha < 5 then
                indicator_anims[short] = nil
            end
        end
    end
end

local function handle_aspect_ratio()
    if not ui.get(UI.enabled) or not ui.get(UI.aspect_ratio_enabled) then
        client.set_cvar("r_aspectratio", 0)
        return
    end
    
    local screen_width, screen_height = client.screen_size()
    if screen_width ~= aspect_ratio_screen_width or screen_height ~= aspect_ratio_screen_height then
        aspect_ratio_table, aspect_ratio_steps = setup_aspect_ratio()
    end
    
    local aspect_ratio = ui.get(UI.aspect_ratio) * 0.01
    aspect_ratio = 2 - aspect_ratio
    
    local aspectratio_value = (screen_width * aspect_ratio) / screen_height
    
    if aspect_ratio == 1 then
        aspectratio_value = 0
    end
    
    client.set_cvar("r_aspectratio", tonumber(aspectratio_value))
end

local function handle_world_effects()
    if not ui.get(UI.enabled) then return end
    
    local wall_color_enabled = ui.get(UI.wall_color)
    if wall_color_enabled or state.wall_color_prev then
        if wall_color_enabled then
            local style = ui.get(UI.wall_color_style)
            local r, g, b, a = ui.get(UI.wall_color_picker)
            local r2, g2, b2 = r, g, b
            
            if style == "Gradient" then
                r2, g2, b2 = ui.get(UI.wall_color_picker2)
            end
            
            if style == "Rainbow" then
                r, g, b = hsv_to_rgb(rainbow_hue, 0.8, 1.0)
            elseif style == "Pulse" then
                local pulse = math.abs(math.sin(globals.curtime() * 2))
                r = r * pulse
                g = g * pulse
                b = b * pulse
            elseif style == "Gradient" then
                local t = (math.sin(globals.curtime() * 0.5) + 1) / 2
                r = r + (r2 - r) * t
                g = g + (g2 - g) * t
                b = b + (b2 - b) * t
            end
            
            r, g, b = r / 255, g / 255, b / 255
            cvars.mat_ambient_light_r:set_raw_float(r)
            cvars.mat_ambient_light_g:set_raw_float(g)
            cvars.mat_ambient_light_b:set_raw_float(b)
        else
            cvars.mat_ambient_light_r:set_raw_float(0)
            cvars.mat_ambient_light_g:set_raw_float(0)
            cvars.mat_ambient_light_b:set_raw_float(0)
        end
    end
    state.wall_color_prev = wall_color_enabled
    
    local model_brightness_enabled = ui.get(UI.model_brightness)
    if model_brightness_enabled or state.model_brightness_prev then
        if model_brightness_enabled then
            local brightness = ui.get(UI.model_brightness_value)
            cvars.r_modelAmbientMin:set_raw_float(brightness * 0.05)
        else
            cvars.r_modelAmbientMin:set_raw_float(0)
        end
    end
    state.model_brightness_prev = model_brightness_enabled
    
    local bloom_enabled = ui.get(UI.bloom)
    local exposure_enabled = ui.get(UI.exposure)
    
    if bloom_enabled or exposure_enabled or state.bloom_prev or state.exposure_prev then
        local tone_map_controllers = entity.get_all("CEnvTonemapController")
        for i = 1, #tone_map_controllers do
            local tone_map_controller = tone_map_controllers[i]
            
            if bloom_enabled then
                if state.bloom_default == nil then
                    if entity.get_prop(tone_map_controller, "m_bUseCustomBloomScale") == 1 then
                        state.bloom_default = entity.get_prop(tone_map_controller, "m_flCustomBloomScale")
                    else
                        state.bloom_default = -1
                    end
                end
                local bloom_value = ui.get(UI.bloom_scale)
                entity.set_prop(tone_map_controller, "m_bUseCustomBloomScale", 1)
                entity.set_prop(tone_map_controller, "m_flCustomBloomScale", bloom_value * 0.01)
            elseif state.bloom_prev and state.bloom_default ~= nil then
                if state.bloom_default == -1 then
                    entity.set_prop(tone_map_controller, "m_bUseCustomBloomScale", 0)
                    entity.set_prop(tone_map_controller, "m_flCustomBloomScale", 0)
                else
                    entity.set_prop(tone_map_controller, "m_bUseCustomBloomScale", 1)
                    entity.set_prop(tone_map_controller, "m_flCustomBloomScale", state.bloom_default)
                end
            end
            
            if exposure_enabled then
                if state.exposure_min_default == nil then
                    if entity.get_prop(tone_map_controller, "m_bUseCustomAutoExposureMin") == 1 then
                        state.exposure_min_default = entity.get_prop(tone_map_controller, "m_flCustomAutoExposureMin")
                    else
                        state.exposure_min_default = -1
                    end
                    if entity.get_prop(tone_map_controller, "m_bUseCustomAutoExposureMax") == 1 then
                        state.exposure_max_default = entity.get_prop(tone_map_controller, "m_flCustomAutoExposureMax")
                    else
                        state.exposure_max_default = -1
                    end
                end
                local exposure_value = ui.get(UI.exposure_value)
                entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMin", 1)
                entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMax", 1)
                entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMin", math.max(0.0000, exposure_value * 0.001))
                entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMax", math.max(0.0000, exposure_value * 0.001))
            elseif state.exposure_prev and state.exposure_min_default ~= nil then
                if state.exposure_min_default == -1 then
                    entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMin", 0)
                    entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMin", 0)
                else
                    entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMin", 1)
                    entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMin", state.exposure_min_default)
                end
                if state.exposure_max_default == -1 then
                    entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMax", 0)
                    entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMax", 0)
                else
                    entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMax", 1)
                    entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMax", state.exposure_max_default)
                end
            end
        end
    end
    state.bloom_prev = bloom_enabled
    state.exposure_prev = exposure_enabled
end

ffi.cdef[[
    typedef struct 
    {
        void*   fnHandle;        
        char    szName[260];     
        int     nLoadFlags;      
        int     nServerCount;    
        int     type;            
        int     flags;           
        float  vecMins[3];       
        float  vecMaxs[3];       
        float   radius;          
        char    pad[0x1C];       
    }model_t;
    
    typedef int(__thiscall* get_model_index_t)(void*, const char*);
    typedef const model_t(__thiscall* find_or_load_model_t)(void*, const char*);
    typedef int(__thiscall* add_string_t)(void*, bool, const char*, int, const void*);
    typedef void*(__thiscall* find_table_t)(void*, const char*);
    typedef void(__thiscall* set_model_index_t)(void*, int);
    typedef int(__thiscall* precache_model_t)(void*, const char*, bool);
    typedef void*(__thiscall* get_client_entity_t)(void*, int);
]]

local class_ptr = ffi.typeof("void***")

local rawientitylist = client.create_interface("client_panorama.dll", "VClientEntityList003")
local ientitylist = rawientitylist and ffi.cast(class_ptr, rawientitylist)
local get_client_entity = ientitylist and ffi.cast("get_client_entity_t", ientitylist[0][3])

local rawivmodelinfo = client.create_interface("engine.dll", "VModelInfoClient004")
local ivmodelinfo = rawivmodelinfo and ffi.cast(class_ptr, rawivmodelinfo)
local get_model_index = ivmodelinfo and ffi.cast("get_model_index_t", ivmodelinfo[0][2])
local find_or_load_model = ivmodelinfo and ffi.cast("find_or_load_model_t", ivmodelinfo[0][39])

local rawnetworkstringtablecontainer = client.create_interface("engine.dll", "VEngineClientStringTable001")
local networkstringtablecontainer = rawnetworkstringtablecontainer and ffi.cast(class_ptr, rawnetworkstringtablecontainer)
local find_table = networkstringtablecontainer and ffi.cast("find_table_t", networkstringtablecontainer[0][3])

local function precache_model(modelname)
    if not find_table or not networkstringtablecontainer then return false end
    
    local rawprecache_table = find_table(networkstringtablecontainer, "modelprecache")
    if rawprecache_table then 
        local precache_table = ffi.cast(class_ptr, rawprecache_table)
        if precache_table then 
            local add_string = ffi.cast("add_string_t", precache_table[0][8])
            if add_string and find_or_load_model and ivmodelinfo then
                find_or_load_model(ivmodelinfo, modelname)
                local idx = add_string(precache_table, false, modelname, -1, nil)
                if idx == -1 then 
                    return false
                end
            end
        end
    end
    return true
end

local function set_model_index(entity, idx)
    if not get_client_entity or not ientitylist then return end
    
    local raw_entity = get_client_entity(ientitylist, entity)
    if raw_entity then 
        local gce_entity = ffi.cast(class_ptr, raw_entity)
        local a_set_model_index = ffi.cast("set_model_index_t", gce_entity[0][75])
        if a_set_model_index then 
            a_set_model_index(gce_entity, idx)
        end
    end
end

local function change_model(ent, model)
    if not model or model == "" or model:len() <= 5 then return end
    if not get_model_index or not ivmodelinfo then return end
    
    if precache_model(model) == false then 
        return
    end
    local idx = get_model_index(ivmodelinfo, model)
    if idx == -1 then 
        return
    end
    set_model_index(ent, idx)
end

local function on_paint()
    rainbow_hue = (rainbow_hue + globals.frametime() * 0.3) % 1.0
    
    if intro_animation.active then
        draw_intro_animation()
        return
    end
    
    if ui.get(UI.enabled) and ui.get(UI.first_person_nade) then
        local me = entity.get_local_player()
        if me and entity.is_alive(me) then
            local weapon = entity.get_player_weapon(me)
            if weapon then
                local weapon_name = entity.get_classname(weapon)
                if weapon_name then
                    local thirdperson_ref = ui.reference("VISUALS", "Effects", "Force third person (alive)")
                    local is_grenade = weapon_name:find("Grenade") or weapon_name:find("Molotov") or weapon_name:find("Incendiary")
                    if is_grenade then
                        ui.set(thirdperson_ref, false)
                    else
                        ui.set(thirdperson_ref, true)
                    end
                end
            end
        end
    end
    
    if ui.get(UI.enabled) and ui.get(UI.fog) and ui.get(UI.fog_style) == "Rainbow" then
        handle_fog()
    end
    
    if ui.get(UI.enabled) and ui.get(UI.skybox) and ui.get(UI.skybox_style) == "Rainbow" then
        update_skybox_color()
    end
    
    if ui.get(UI.enabled) and ui.get(UI.console_color) then
        if console_color.is_visible(console_color.engine_client) then
            local r, g, b, a = ui.get(UI.console_color_picker)
            
            for _, mat in ipairs(console_color.mats) do
                mat:color_modulate(r, g, b)
                mat:alpha_modulate(a)
            end
        end
    end
    
    if ui.get(UI.enabled) and ui.get(UI.thirdperson_distance) then
        client.exec("cam_idealdist ", ui.get(UI.thirdperson_distance_value))
    else
        client.exec("cam_idealdist 80")
    end
    
    if ui.get(UI.enabled) and ui.get(UI.viewmodel_changer) then
        local fov = ui.get(UI.viewmodel_fov) * 0.1
        local x = ui.get(UI.viewmodel_x) * 0.1
        local y = ui.get(UI.viewmodel_y) * 0.1
        local z = ui.get(UI.viewmodel_z) * 0.1
        cvars.viewmodel_fov:set_raw_float(fov)
        cvars.viewmodel_offset_x:set_raw_float(x)
        cvars.viewmodel_offset_y:set_raw_float(y)
        cvars.viewmodel_offset_z:set_raw_float(z)
    else
        cvars.viewmodel_fov:set_raw_float(68.0)
        cvars.viewmodel_offset_x:set_raw_float(2.5)
        cvars.viewmodel_offset_y:set_raw_float(0.0)
        cvars.viewmodel_offset_z:set_raw_float(-1.5)
    end
    
    handle_aspect_ratio()
    handle_world_effects()
    update_hit_particles()
    update_grenade_trails()
    
    draw_notifications()
    update_clantag()
    draw_watermark()
    draw_kill_image()
    draw_scope_lines()
    draw_tracers()
    draw_trails()
    draw_grenade_trails()
    draw_hit_particles()
    draw_spectators()
    draw_keybinds()
    draw_indicators()
    draw_healthbar()
end

handle_warmup_assistant = function()
    if not ui.get(UI.enabled) or not ui.get(UI.warmup_helper) then return end

    -- Шаг 1: sv_cheats должен встать в 1 ПЕРЕД остальными cheat-защищёнными командами
    client.exec("sv_cheats 1")

    -- Шаг 2: с небольшой задержкой применяем защищённые настройки,
    -- иначе движок отклонит их как cheat-protected до того, как sv_cheats успеет примениться
    client.delay_call(0.1, function()
        client.exec("sv_regeneration_force_on 1")
        client.exec("sv_infinite_ammo 1")
        client.exec("sv_airaccelerate 100")
        client.exec("mp_limitteams 0")
        client.exec("mp_autoteambalance 0")
        client.exec("mp_roundtime 60")
        client.exec("mp_roundtime_defuse 60")
        client.exec("mp_maxmoney 60000")
        client.exec("mp_startmoney 60000")
        client.exec("mp_freezetime 0")
        client.exec("mp_buytime 9999")
        client.exec("mp_buy_anywhere 1")
        client.exec("ammo_grenade_limit_total 5")
        client.exec("mp_respawn_on_death_ct 1")
        client.exec("mp_respawn_on_death_t 1")
        client.exec("bot_stop 1")
        client.exec("bot_kick")
        client.exec("mp_warmup_end")
    end)

    -- Шаг 3: рестарт в самом конце, когда все настройки уже применены
    client.delay_call(0.3, function()
        client.exec("mp_restartgame 1")
    end)

    add_notification("Warmup Assistant applied", "hit")
end

restore_warmup_defaults = function()
    -- Возвращаем cvar'ы к стандартным значениям competitive-режима

    -- Шаг 1: восстанавливаем cheat-защищённые команды (sv_cheats ещё в 1)
    client.exec("sv_regeneration_force_on 0")
    client.exec("sv_infinite_ammo 0")
    client.exec("sv_airaccelerate 12")
    client.exec("mp_limitteams 2")
    client.exec("mp_autoteambalance 1")
    client.exec("mp_roundtime 1.92")
    client.exec("mp_roundtime_defuse 1.92")
    client.exec("mp_maxmoney 16000")
    client.exec("mp_startmoney 800")
    client.exec("mp_freezetime 15")
    client.exec("mp_buytime 20")
    client.exec("mp_buy_anywhere 0")
    client.exec("ammo_grenade_limit_total 4")
    client.exec("mp_respawn_on_death_ct 0")
    client.exec("mp_respawn_on_death_t 0")
    client.exec("bot_stop 0")

    -- Шаг 2: возвращаем sv_cheats в 0 и перезапускаем раунд, чтобы всё вступило в силу
    client.delay_call(0.1, function()
        client.exec("sv_cheats 0")
        client.exec("mp_restartgame 1")
    end)

    add_notification("Warmup Assistant reverted", "miss")
end

apply_fps_boost = function()
    local enabled = ui.get(UI.fps_boost)
    local selected = ui.get(UI.fps_boost_options)

    -- Превращаем список выбранных опций в удобную для проверки таблицу
    local opt = {}
    if selected then
        for i = 1, #selected do
            opt[selected[i]] = true
        end
    end

    -- Если чекбокс выключен или ничего не выбрано — возвращаем стандартные значения
    if not enabled or next(opt) == nil then
        client.set_cvar("r_dynamic", "1")
        client.set_cvar("cl_csm_shadows", "1")
        client.set_cvar("r_drawtracers_firstperson", "1")
        client.set_cvar("cl_ragdoll_physics_enable", "1")
        client.set_cvar("r_eyegloss", "1")
        client.set_cvar("r_eyemove", "1")
        client.set_cvar("r_eyeshift_x", "1")
        client.set_cvar("r_eyeshift_y", "1")
        client.set_cvar("r_eyeshift_z", "1")
        client.set_cvar("r_eyesize", "1")
        client.set_cvar("mat_queue_mode", "-1")
        client.set_cvar("r_queued_decals", "0")
        client.set_cvar("r_queued_post_processing", "0")
        client.set_cvar("r_queued_ropes", "0")
        client.set_cvar("r_threaded_particles", "0")
        client.set_cvar("r_threaded_renderables", "0")
        client.set_cvar("cl_forcepreload", "0")
        client.set_cvar("fps_max", "300")
        client.set_cvar("muzzleflash_light", "1")
        client.set_cvar("func_break_max_pieces", "15")
        if not enabled then
            add_notification("FPS Boost disabled", "miss")
        end
        return
    end

    -- Применяем выбранные оптимизации
    if opt["Disable Dynamic Lighting"] then client.set_cvar("r_dynamic", "0") end
    if opt["Disable Dynamic Shadows"] then client.set_cvar("cl_csm_shadows", "0") end
    if opt["Disable First-Person Tracers"] then client.set_cvar("r_drawtracers_firstperson", "0") end
    if opt["Disable Ragdolls"] then client.set_cvar("cl_ragdoll_physics_enable", "0") end
    if opt["Disable Eye Gloss"] then client.set_cvar("r_eyegloss", "0") end
    if opt["Disable Eye Movement"] then
        client.set_cvar("r_eyemove", "0")
        client.set_cvar("r_eyeshift_x", "0")
        client.set_cvar("r_eyeshift_y", "0")
        client.set_cvar("r_eyeshift_z", "0")
        client.set_cvar("r_eyesize", "0")
    end
    if opt["Enable Multi-Core Rendering"] then
        client.set_cvar("mat_queue_mode", "2")
        client.set_cvar("r_queued_decals", "1")
        client.set_cvar("r_queued_post_processing", "1")
        client.set_cvar("r_queued_ropes", "1")
        client.set_cvar("r_threaded_particles", "1")
        client.set_cvar("r_threaded_renderables", "1")
    end
    if opt["Force Preload"] then client.set_cvar("cl_forcepreload", "1") end
    if opt["Remove FPS Cap"] then client.set_cvar("fps_max", "0") end
    if opt["Disable Muzzle Flash Light"] then client.set_cvar("muzzleflash_light", "0") end
    if opt["Reduce Breakable Object Impact"] then client.set_cvar("func_break_max_pieces", "0") end

    client.exec("clear")
    add_notification("FPS Boost applied", "hit")
end

client.set_event_callback('aim_hit', on_aim_hit)
client.set_event_callback('aim_miss', on_aim_miss)
client.set_event_callback('player_hurt', on_player_hurt)
client.set_event_callback('player_death', on_player_death)
client.set_event_callback('bullet_impact', on_bullet_impact)
client.set_event_callback('round_prestart', on_round_prestart)
client.set_event_callback('round_start', function()
    handle_fog()
end)

local function on_autobuy_round_prestart()
    if not ui.get(UI.enabled) or not ui.get(UI.autobuy_enabled) then return end
    
    local lp = entity.get_local_player()
    if not lp then return end
    
    local money = entity.get_prop(lp, "m_iAccount")
    if not money then return end
    
    local threshold_value = ui.get(UI.autobuy_balance)
    local price_threshold = 0
    
    if ui.get(UI.autobuy_cost_based) and threshold_value == 0 then
        price_threshold = autobuy_state.primary_cost
    elseif threshold_value ~= 0 then
        price_threshold = threshold_value
    end
    
    client.delay_call(0.3, function()
        local delay_offset = 0
        
        if money < price_threshold then
            local backup_primary = ui.get(UI.autobuy_backup_primary)
            if weapons.buy_commands[backup_primary] then
                client.delay_call(delay_offset, client.exec, weapons.buy_commands[backup_primary])
                delay_offset = delay_offset + 0.05
            end
            
            local backup_secondary = ui.get(UI.autobuy_backup_secondary)
            if weapons.buy_commands[backup_secondary] then
                client.delay_call(delay_offset, client.exec, weapons.buy_commands[backup_secondary])
                delay_offset = delay_offset + 0.05
            end
            
            local backup_utilities = ui.get(UI.autobuy_backup_utilities) or {}
            for i = 1, #backup_utilities do
                local util = backup_utilities[i]
                if weapons.buy_commands[util] then
                    client.delay_call(delay_offset, client.exec, weapons.buy_commands[util])
                    delay_offset = delay_offset + 0.05
                end
            end
            
            local backup_grenades = ui.get(UI.autobuy_backup_grenades) or {}
            for i = 1, #backup_grenades do
                local nade = backup_grenades[i]
                if weapons.buy_commands[nade] then
                    client.delay_call(delay_offset, client.exec, weapons.buy_commands[nade])
                    delay_offset = delay_offset + 0.05
                end
            end
        else
            local primary = ui.get(UI.autobuy_primary)
            if weapons.buy_commands[primary] then
                client.delay_call(delay_offset, client.exec, weapons.buy_commands[primary])
                delay_offset = delay_offset + 0.05
            end
            
            local secondary = ui.get(UI.autobuy_secondary)
            if weapons.buy_commands[secondary] then
                client.delay_call(delay_offset, client.exec, weapons.buy_commands[secondary])
                delay_offset = delay_offset + 0.05
            end
            
            local utilities = ui.get(UI.autobuy_utilities) or {}
            for i = 1, #utilities do
                local util = utilities[i]
                if weapons.buy_commands[util] then
                    client.delay_call(delay_offset, client.exec, weapons.buy_commands[util])
                    delay_offset = delay_offset + 0.05
                end
            end
            
            local grenades = ui.get(UI.autobuy_grenades) or {}
            for i = 1, #grenades do
                local nade = grenades[i]
                if weapons.buy_commands[nade] then
                    client.delay_call(delay_offset, client.exec, weapons.buy_commands[nade])
                    delay_offset = delay_offset + 0.05
                end
            end
        end
    end)
end

client.set_event_callback('round_prestart', on_autobuy_round_prestart)
client.set_event_callback('setup_command', function(cmd)
    on_setup_command(cmd)
    smooth_animation_setup_command(cmd)
end)
client.set_event_callback('paint', on_paint)
client.set_event_callback('paint_ui', scope_paint_ui)
client.set_event_callback('pre_render', function()
    smooth_animation_pre_render()
    
    if not ui.get(UI.enabled) or not ui.get(UI.model_changer) then return end
    
    local me = entity.get_local_player()
    if not me then return end
    
    local team = entity.get_prop(me, 'm_iTeamNum')
    if not team then return end
    
    local model_mode = ui.get(UI.model_changer_mode)
    
    if team == 2 then
        local model_name, model_path
        if model_mode == "Auto" then
            model_name = ui.get(UI.model_changer_t_auto)
            model_path = models.auto_t[model_name]
        else
            model_name = ui.get(UI.model_changer_t)
            model_path = models.t_player[model_name]
        end
        if model_path and model_path ~= "" then
            change_model(me, model_path)
        end
    elseif team == 3 then
        local model_name, model_path
        if model_mode == "Auto" then
            model_name = ui.get(UI.model_changer_ct_auto)
            model_path = models.auto_ct[model_name]
        else
            model_name = ui.get(UI.model_changer_ct)
            model_path = models.ct_player[model_name]
        end
        if model_path and model_path ~= "" then
            change_model(me, model_path)
        end
    end
end)

client.set_event_callback('override_view', override_view_handler)

client.set_event_callback('shutdown', function()
    client.set_clan_tag('')
    ui.set(scope_overlay_ref, false)
    client.set_cvar('fog_override', '0')
    
    local tone_map_controllers = entity.get_all("CEnvTonemapController")
    for i = 1, #tone_map_controllers do
        local tone_map_controller = tone_map_controllers[i]
        if state.bloom_prev and state.bloom_default ~= nil then
            if state.bloom_default == -1 then
                entity.set_prop(tone_map_controller, "m_bUseCustomBloomScale", 0)
                entity.set_prop(tone_map_controller, "m_flCustomBloomScale", 0)
            else
                entity.set_prop(tone_map_controller, "m_bUseCustomBloomScale", 1)
                entity.set_prop(tone_map_controller, "m_flCustomBloomScale", state.bloom_default)
            end
        end
        if state.exposure_prev and state.exposure_min_default ~= nil then
            if state.exposure_min_default == -1 then
                entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMin", 0)
                entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMin", 0)
            else
                entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMin", 1)
                entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMin", state.exposure_min_default)
            end
            if state.exposure_max_default == -1 then
                entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMax", 0)
                entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMax", 0)
            else
                entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMax", 1)
                entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMax", state.exposure_max_default)
            end
        end
    end
    cvars.mat_ambient_light_r:set_raw_float(0)
    cvars.mat_ambient_light_g:set_raw_float(0)
    cvars.mat_ambient_light_b:set_raw_float(0)
    cvars.r_modelAmbientMin:set_raw_float(0)
end)

local function reset_world_defaults()
    if globals.mapname() == nil then
        state.bloom_default, state.exposure_min_default, state.exposure_max_default = nil, nil, nil
    end
    client.delay_call(0.5, reset_world_defaults)
end
reset_world_defaults()

client.color_log(255, 255, 255, "[gamesense] \0")
client.color_log(255, 255, 255, "WinstonRED loaded successfully!")


