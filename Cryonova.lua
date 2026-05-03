--#region lua
local lua = {}
lua.configs = {}
--#endregion

--#region require
local pui = require('gamesense/pui')
local base64 = require('gamesense/base64')
local clipboard = require('gamesense/clipboard')
local http = require('gamesense/http')
local images = require('gamesense/images')
local json = require('json')
local antiaim_data = require('gamesense/antiaim_funcs')
local vector = require('vector')
local ffi = require('ffi')
local weapons = require('gamesense/csgo_weapons')
lua.entity = require('gamesense/entity')
--#endregion

--#region notifications
local notify = { bottom = {} }

notify.new_bottom = function(r, g, b, parts)
    notify.bottom[#notify.bottom + 1] = {
        started = globals.realtime(),
        expires = globals.realtime() + 5,
        alpha = 0,
        y = nil,
        r = r,
        g = g,
        b = b,
        parts = parts
    }
end

local function notify_lerp(from, to, amount)
    return from + (to - from) * amount
end

local function notify_text(parts, alpha, accent_r, accent_g, accent_b)
    local out = ''
    for i = 1, #parts do
        local part = parts[i]
        local text = tostring(part[1] or '')
        local accent = part[2]
        local r, g, b = 255, 255, 255
        if accent then
            r, g, b = accent_r, accent_g, accent_b
        end
        out = out .. string.format('\a%02x%02x%02x%02x%s', r, g, b, alpha, text)
    end
    return out
end

client.set_event_callback('paint_ui', function()
    local screen_w, screen_h = client.screen_size()
    local now = globals.realtime()
    local ft = globals.frametime()
    for i = #notify.bottom, 1, -1 do
        local item = notify.bottom[i]
        local active = now < item.expires
        item.alpha = notify_lerp(item.alpha, active and 255 or 0, active and ft * 9 or ft * 18)
        if item.alpha <= 1 and not active then
            table.remove(notify.bottom, i)
        else
            local text = notify_text(item.parts, math.floor(item.alpha), item.r, item.g, item.b)
            local width = renderer.measure_text('', text) + 34
            local height = 24
            local target_y = screen_h - 140 - (#notify.bottom - i) * 34
            item.y = notify_lerp(item.y or screen_h, target_y, ft * 8)
            local x = screen_w * 0.5 - width * 0.5
            local y = item.y
            renderer.rectangle(x + 4, y + 4, width, height, 0, 0, 0, item.alpha * 0.18)
            renderer.rectangle(x, y, width, height, 18, 18, 18, item.alpha * 0.88)
            renderer.rectangle(x, y, 2, height, item.r, item.g, item.b, item.alpha)
            renderer.text(x + 9, y + 6, item.r, item.g, item.b, item.alpha, '', 0, '*')
            renderer.text(x + 22, y + 6, 255, 255, 255, item.alpha, '', 0, text)
        end
    end
end)
--#endregion
--#region drag
local draggable = {}
draggable.__index = draggable

function draggable:new(name, base_x, base_y, width, height)
    local screen_w, screen_h = client.screen_size()
    local pos_x_slider = pui.slider('LUA', 'B', name .. ' Position X', 0, 10000, base_x / screen_w * 10000)
    local pos_y_slider = pui.slider('LUA', 'B', name .. ' Position Y', 0, 10000, base_y / screen_h * 10000)
    pos_x_slider:set_visible(false)
    pos_y_slider:set_visible(false)

    local obj = setmetatable({
        name = name,
        width = width or 200,
        height = height or 100,
        x_slider = pos_x_slider,
        y_slider = pos_y_slider,
        is_dragging = false,
        offset_x = 0,
        offset_y = 0
    }, draggable)

    return obj
end

function draggable:get_position()
    local screen_w, screen_h = client.screen_size()
    local x = self.x_slider:get() / 10000 * screen_w
    local y = self.y_slider:get() / 10000 * screen_h
    return x, y
end

function draggable:set_position(x, y)
    local screen_w, screen_h = client.screen_size()
    self.x_slider:set(x / screen_w * 10000)
    self.y_slider:set(y / screen_h * 10000)
end

function draggable:start_drag(mouse_x, mouse_y)
    local x, y = self:get_position()
    self.is_dragging = true
    self.offset_x = mouse_x - x
    self.offset_y = mouse_y - y
end

function draggable:stop_drag()
    self.is_dragging = false
end

function draggable:handle_drag()
    local mouse_x, mouse_y = ui.mouse_position()

    if self.is_dragging then
        local new_x = mouse_x - self.offset_x
        local new_y = mouse_y - self.offset_y

        local screen_w, screen_h = client.screen_size()
        new_x = math.max(0, math.min(screen_w - self.width, new_x))
        new_y = math.max(0, math.min(screen_h - self.height, new_y))

        self:set_position(new_x, new_y)

        if not client.key_state(0x01) then
            self:stop_drag()
        end
    else
        local x, y = self:get_position()
        local is_hovering = mouse_x >= x and mouse_x <= x + self.width and mouse_y >= y and mouse_y <= y + self.height

        if is_hovering and ui.is_menu_open() and client.key_state(0x01) then
            self:start_drag(mouse_x, mouse_y)
        end
    end
end
--#endregion

--#region render
local render = renderer
local screen = vector(client.screen_size())
render.frame_count = 0
render.frame_string = 0

math.exploit = function ()
    local me = entity.get_local_player()
    if not me then return end
    local tickcount = globals.tickcount()
    local tickbase = entity.get_prop(me, 'm_nTickBase')
    return tickcount > tickbase
end

render.get_frame = function ( sel, answer )
    render.frame_count = 0.9 * render.frame_count + 0.1 * globals.absoluteframetime()
    if globals.tickcount() % sel == 1 then
        render.frame_string = tostring(1 / render.frame_count)
    end

    if answer == 'string' then
        return math.floor(render.frame_string)
    elseif answer == 'count' then
        return math.floor(render.frame_count)
    end
end

render.round_rect = function (x, y, width, height, radius, r, g, b, a)
    local top_left_x, top_left_y = x + radius, y + radius
    local top_right_x, top_right_y = x + width - radius, y + radius
    local bottom_left_x, bottom_left_y = x + radius, y + height - radius
    local bottom_right_x, bottom_right_y = x + width - radius, y + height - radius

    -- circle
    render.circle(top_left_x, top_left_y, r, g, b, a, radius, 180, 0.25)         -- up left
    render.circle(top_right_x, top_right_y, r, g, b, a, radius, 90, 0.25)        -- up right
    render.circle(bottom_left_x, bottom_left_y, r, g, b, a, radius, 270, 0.25)   -- down left
    render.circle(bottom_right_x, bottom_right_y, r, g, b, a, radius, 0, 0.25)   -- down right

    -- rect
    render.rectangle(x + radius, y, width - radius * 2, radius, r, g, b, a)                    -- up
    render.rectangle(x + radius, y + height - radius, width - radius * 2, radius, r, g, b, a)  -- down
    render.rectangle(x, y + radius, radius, height - radius * 2, r, g, b, a)                   -- left
    render.rectangle(x + width - radius, y + radius, radius, height - radius * 2, r, g, b, a)  -- right

    render.rectangle(x + radius, y + radius, width - radius * 2, height - radius * 2, r, g, b, a)
end

render.shadow = function(x, y, width, height, radius, glow_size, r, g, b, a)
    for i = glow_size, 1, -1 do
        local alpha = a * (i / glow_size) * 0.6
        if alpha <= 0 then
            goto continue
        end
        render.round_rect(x - i, y - i, width + i * 2, height + i * 2, radius, r, g, b, alpha)
    end

    render.round_rect(x, y, width, height, radius, r, g, b, a)
    ::continue::
end
--#endregion

--#region lua.sounds
local function bind_signature(module, interface, signature, typestring)
    local interface = client.create_interface(module, interface) or error('invalid interface', 2)
    local instance = client.find_signature(module, signature) or error('invalid signature', 2)
    local success, typeof = pcall(ffi.typeof, typestring)
    if not success then
        error(typeof, 2)
    end
    local fnptr = ffi.cast(typeof, instance) or error('invalid typecast', 2)
    return function(...)
        return fnptr(interface, ...)
    end
end

local function vmt_entry(instance, index, type)
	return ffi.cast(type, (ffi.cast('void***', instance)[0])[index])
end

local function vmt_bind(module, interface, index, typestring)
	local instance = client.create_interface(module, interface) or error('invalid interface')
	local success, typeof = pcall(ffi.typeof, typestring)
	if not success then
		error(typeof, 2)
	end
	local fnptr = vmt_entry(instance, index, typeof) or error('invalid vtable')
	return function(...)
		return fnptr(instance, ...)
	end
end

local int_ptr	   = ffi.typeof('int[1]')
local char_buffer   = ffi.typeof('char[?]')

local find_first	= bind_signature('filesystem_stdio.dll', 'VFileSystem017', '\x55\x8B\xEC\x6A\x00\xFF\x75\x10\xFF\x75\x0C\xFF\x75\x08\xE8\xCC\xCC\xCC\xCC\x5D', 'const char*(__thiscall*)(void*, const char*, const char*, int*)')
local find_next	 = bind_signature('filesystem_stdio.dll', 'VFileSystem017', '\x55\x8B\xEC\x83\xEC\x0C\x53\x8B\xD9\x8B\x0D\xCC\xCC\xCC\xCC', 'const char*(__thiscall*)(void*, int)')
local find_close	= bind_signature('filesystem_stdio.dll', 'VFileSystem017', '\x55\x8B\xEC\x53\x8B\x5D\x08\x85', 'void(__thiscall*)(void*, int)')

local current_directory = bind_signature('filesystem_stdio.dll', 'VFileSystem017', '\x55\x8B\xEC\x56\x8B\x75\x08\x56\xFF\x75\x0C', 'bool(__thiscall*)(void*, char*, int)')
local add_to_searchpath = bind_signature('filesystem_stdio.dll', 'VFileSystem017', '\x55\x8B\xEC\x81\xEC\xCC\xCC\xCC\xCC\x8B\x55\x08\x53\x56\x57', 'void(__thiscall*)(void*, const char*, const char*, int)')
local find_is_directory = bind_signature('filesystem_stdio.dll', 'VFileSystem017', '\x55\x8B\xEC\x0F\xB7\x45\x08', 'bool(__thiscall*)(void*, int)')
local surface_playsound = vmt_bind('vguimatsurface.dll', 'VGUI_Surface031', 82, 'void(__thiscall*)(void*, const char*)')

lua.sounds = {} do
    lua.sounds.sound_names = {}
    lua.sounds.sound_name_to_file = {}
    lua.sounds.collect_files = function ()
        local files = {}
        local file_handle = int_ptr()
        local file = find_first('*', 'XGAME', file_handle)
        while file ~= nil do
            local file_name = ffi.string(file)
            if find_is_directory(file_handle[0]) == false and (file_name:find('.mp3') or file_name:find('.wav')) then
                files[#files+1] = file_name
            end
            file = find_next(file_handle[0])
        end
        find_close(file_handle[0])
        return files
    end
    lua.sounds.normalize_file_name = function (name)
        if name:find('_') then
            name = name:gsub('_', ' ')
        end
        if name:find('.mp3') then
            name = name:gsub('.mp3', '')
        end
        if name:find('.wav') then
            name = name:gsub('.wav', '')
        end
        return name
    end
    lua.sounds.play = function (sound, type)
        if type == true then
            surface_playsound(sound)
        else
            cvar.play:invoke_callback(sound)
        end
    end
    lua.sounds.set = function (struct, sounds)
        for i, n in pairs(struct) do
            n:set_callback(function()
                lua.sounds.play(sounds, false)
            end, true)
        end
    end
    lua.sounds.init_sound = function (sound_name, sound_file)
	    lua.sounds.sound_names[#lua.sounds.sound_names+1] = sound_name
	    lua.sounds.sound_name_to_file[sound_name] = sound_file
    end
end
--#endregion

--#region lerp
local mathematic = {} do
	local function linear(t, b, c, d)
		return c * t / d + b
	end

	local function get_deltatime()
		return globals.frametime()
	end

    mathematic.round = (function(num)
        if num % 1 >= 0.5 then
            return math.ceil(num)
        else
            return math.floor(num)
        end
    end)

    mathematic.normalize = function (x, min, max)
        local delta = max - min

        while x < min do
            x = x + delta
        end

        while x > max do
            x = x - delta
        end

        return x
    end

    mathematic.normalize_yaw = function (x)
        return mathematic.normalize(x, -180, 180)
    end

    mathematic.calc_angle = function (a, b)
        local x_delta = b.x - a.x
        local y_delta = b.y - a.y
        local z_delta = b.z - a.z 
        local hyp = math.sqrt(x_delta^2 + y_delta^2)
        local x = math.atan2(z_delta, hyp) * 57.295779513082
        local y = math.atan2(y_delta , x_delta) * 180 / 3.14159265358979323846
        return { x = mathematic.normalize_yaw(x, 90), y = mathematic.normalize_yaw(y, 180), z = 0 }
    end

	local function solve(easing_fn, prev, new, clock, duration)
		if clock <= 0 then return new end
		if clock >= duration then return new end

		prev = easing_fn(clock, prev, new - prev, duration)

		if type(prev) == 'number' then
			if math.abs(new - prev) < 0.001 then
				return new
			end

			local remainder = math.fmod(prev, 1.0)

			if remainder < 0.001 then
				return math.floor(prev)
			end

			if remainder > 0.999 then
				return math.ceil(prev)
			end
		end

		return prev
	end

	function mathematic.interp(a, b, t, easing_fn)
		easing_fn = easing_fn or linear

		if type(b) == 'boolean' then
			b = b and 1 or 0
		end

		return solve(easing_fn, a, b, get_deltatime(), t)
	end

    mathematic.interpolation = function(start, _end, time)
        return (_end - start) * time + start
    end

    mathematic.clamp = function(value, minimum, maximum)
        assert(value and minimum and maximum, '')
        if minimum > maximum then minimum, maximum = maximum, minimum end
        return math.max(minimum, math.min(maximum, value))
    end

    mathematic.hex_rgba = function(r, g, b, a)
        return bit.tohex(
        (math.floor(r + 0.5) * 16777216) + 
        (math.floor(g + 0.5) * 65536) + 
        (math.floor(b + 0.5) * 256) + 
        (math.floor(a + 0.5))
        )
    end

    mathematic.animate_text = function(time, string, r, g, b, a, r2, g2, b2, a2)
        local t_out, t_out_iter = { }, 1

        local l = string:len( ) - 1

        local r_add = (r2 - r)
        local g_add = (g2 - g)
        local b_add = (b2 - b)
        local a_add = (a2 - a)

        for i = 1, #string do
            local iter = (i - 1)/(#string - 1) + time
            t_out[t_out_iter] = '\a' .. mathematic.hex_rgba( r + r_add * math.abs(math.cos( iter )), g + g_add * math.abs(math.cos( iter )), b + b_add * math.abs(math.cos( iter )), a + a_add * math.abs(math.cos( iter )) )

            t_out[t_out_iter + 1] = string:sub( i, i )

            t_out_iter = t_out_iter + 2
        end

        return t_out
    end

    mathematic.lerp = function(start, _end, time)
        time = time or 0.005
        time = mathematic.clamp(globals.frametime() * time * 175.0, 0.01, 1.0)
        local a = mathematic.interpolation(start, _end, time)
        if _end == 0.0 and a < 0.01 and a > -0.01 then
            a = 0.0
        elseif _end == 1.0 and a < 1.01 and a > 0.99 then
            a = 1.0
        end
        return a
    end
    function mathematic.lerp_color(r1, g1, b1, a1, r2, g2, b2, a2, t)
		local r = mathematic.lerp(r1, r2, t)
		local g = mathematic.lerp(g1, g2, t)
		local b = mathematic.lerp(b1, b2, t)
		local a = mathematic.lerp(a1, a2, t)

		return r, g, b, a
	end
end
--#endregion

--#region lua.helps
lua.helps = {} do
    --#region lua.helps.exploits
    lua.helps.exploits = {}
    lua.helps.exploits.max_tickbase = 0
    lua.helps.exploits.ticks = 0
    lua.helps.additions = {}
    lua.helps.exploits.is_peeking = function ()
        local me = entity.get_local_player()
        if not me then return end
        local enemies = entity.get_players(true)
        if not enemies then
            return false
        end

        local predict_amt = 0.25
        local eye_position = vector(client.eye_position())
        local velocity_prop_local = vector(entity.get_prop(me, 'm_vecVelocity'))
        local predicted_eye_position = vector(eye_position.x + velocity_prop_local.x * predict_amt, eye_position.y + velocity_prop_local.y * predict_amt, eye_position.z + velocity_prop_local.z * predict_amt)
        for i = 1, #enemies do
            local player = enemies[i]
            local velocity_prop = vector(entity.get_prop(player, 'm_vecVelocity'))
            local origin = vector(entity.get_prop(player, 'm_vecOrigin'))
            local predicted_origin = vector(origin.x + velocity_prop.x * predict_amt, origin.y + velocity_prop.y * predict_amt, origin.z + velocity_prop.z * predict_amt)
            entity.get_prop(player, 'm_vecOrigin', predicted_origin)
            local head_origin = vector(entity.hitbox_position(player, 0))
            local predicted_head_origin = vector(head_origin.x + velocity_prop.x * predict_amt, head_origin.y + velocity_prop.y * predict_amt, head_origin.z + velocity_prop.z * predict_amt)
            local trace_entity, damage = client.trace_bullet(me, predicted_eye_position.x, predicted_eye_position.y, predicted_eye_position.z, predicted_head_origin.x, predicted_head_origin.y, predicted_head_origin.z)
            entity.get_prop( player, 'm_vecOrigin', origin )
            if damage > 0 then
                return true
            end
        end
        return false
    end
    lua.helps.exploits.ping = function ()
        local me = entity.get_local_player()
        if not me then return end
        local resource = entity.get_player_resource(me)
        if not resource then return end

        local ping = entity.get_prop(resource, 'm_iPing', me)
        return ping
    end
    lua.helps.exploits.defensive = function ()
        local me = entity.get_local_player()
        if not me then return end
        local tickcount = globals.tickcount()
        local tickbase = entity.get_prop(me, 'm_nTickBase')

        if math.abs(tickbase - lua.helps.exploits.max_tickbase) > 64 then
            lua.helps.exploits.max_tickbase = 0
        end

        if tickbase > lua.helps.exploits.max_tickbase then
            lua.helps.exploits.max_tickbase = tickbase
        elseif lua.helps.exploits.max_tickbase > tickbase then
            lua.helps.exploits.ticks = math.min(14, math.max(0, lua.helps.exploits.max_tickbase - tickbase - 1))
        end
        if lua.helps.exploits.ticks == nil then return 0 end
        return math.exploit and lua.helps.exploits.ticks or 0
    end
    lua.helps.exploits.get_freestand = function(p, a)
        if not p then return false end
        if not a then return false end

        local is_dynamic = lua.reference.antiaim.angles.yaw_base:get() == 'At targets'
        local player_origin = vector(entity.get_origin(p))
        local ent_origin = vector(entity.get_origin(a))
        local yaw_base = is_dynamic and mathematic.calc_angle(player_origin, ent_origin).y or vector(client.camera_angles()).y
        local yaw = yaw_base + lua.reference.antiaim.angles.yaw[2]:get()
        local fs_yaw = mathematic.normalize_yaw(entity.get_prop(p, 'm_angEyeAngles[1]') - 180, 180)
        local diff = math.abs(yaw - fs_yaw)
        local is_fs = diff > 50 and diff < 300
    
        return is_fs
    end
    lua.helps.exploits.get_freestand_direction = function(p)
        local data = {
            side = 1,
            last_side = 0,
            last_hit = 0,
            hit_side = 0
        }
    
        if not p or entity.get_prop(p, 'm_lifeState') ~= 0 then
            return
        end
    
        if data.hit_side ~= 0 and globals.curtime() - data.last_hit > 5 then
            data.last_side = 0
            data.last_hit = 0
            data.hit_side = 0
        end
    
        local eye = vector(client.eye_position())
        local ang = vector(client.camera_angles())
        local trace_data = {left = 0, right = 0}
    
        for i = ang.y - 120, ang.y + 120, 30 do
            if i ~= ang.y then
                local rad = math.rad(i)
                local px, py, pz = eye.x + 256 * math.cos(rad), eye.y + 256 * math.sin(rad), eye.z
                local fraction = client.trace_line(p, eye.x, eye.y, eye.z, px, py, pz)
                local side = i < ang.y and 'left' or 'right'
                trace_data[side] = trace_data[side] + fraction
            end
        end

        data.side = trace_data.left < trace_data.right and -1 or 1
    
        if data.side == data.last_side then
            return
        end
    
        data.last_side = data.side
    
        if data.hit_side ~= 0 then
            data.side = data.hit_side
        end
    
        return data.side
    end
    lua.helps.exploits.get_maximum_usrcmd_ticks = function (wish_ticks)
        local game_rules = entity.get_game_rules()
        local is_valve_ds =
            entity.get_prop(game_rules, 'm_bIsValveDS') == 1 or
            entity.get_prop(game_rules, 'm_bIsQueuedMatchmaking') == 1
    
        local _iTicksAllowed = is_valve_ds and 6 or lua.reference.rage.binds.usercmd:get() - 2
    
        return wish_ticks and math.min(_iTicksAllowed, wish_ticks) or _iTicksAllowed
    end
    lua.helps.additions.normalize = function (x, min, max)
        local delta = max - min;

        while x < min do
            x = x + delta;
        end

        while x > max do
            x = x - delta;
        end

        return x;
    end
    lua.helps.additions.normalize_yaw = function (x)
        return lua.helps.additions.normalize(x, -180, 180);
    end

    client.set_event_callback('level_init', function() lua.helps.exploits.max_tickbase, lua.helps.exploits.ticks = 0, 0 end)
    --#endregion
end
--#endregion

--#region lua.pui
lua.pui = {} do
    lua.pui.ui = {}

    pui.macros.name_lua = '\bE7FBFF90\b9FDDFB90[Cryonova ~ Nightly]'
    pui.macros.color_tabs = '\aA9DCEBFF'
    pui.macros.color_start = '\aE7FBFFFF'
    pui.macros.color_sad = '\a8FCFFAFF'
    pui.macros.color_ref = '\aC8EEF6FF'

    lua.pui.tabs = {
        welcome = '~ Welcome',
        builder = '* Anti-Aim',
        antiaim = '+ Anti-aimbot',
        features = '~ Miscellanous',
        world = '# Visuals',
        rage = string.char(226, 138, 149) .. ' Rage',
        other = '> Other'
    }

    lua.sounds.contract = 'ui/csgo_ui_contract_type1'
    lua.sounds.init_sound( 'Switch 3D', 'buttons/light_power_on_switch_01')
    lua.sounds.init_sound( 'Senko', 'survival/paradrop_idle_01.wav')
    lua.sounds.init_sound( 'Menu', 'ui/csgo_ui_contract_type1')
    lua.sounds.init_sound( 'Strain', 'physics/wood/wood_strain7')
    lua.sounds.init_sound( 'Stop', 'doors/wood_stop1')
    lua.sounds.init_sound( 'Impact', 'physics/wood/wood_plank_impact_hard4')
    lua.sounds.init_sound( 'Warning', 'resource/warning')

    local current_path = char_buffer(128)
	current_directory(current_path, ffi.sizeof(current_path))
	current_path = string.format('%s/csgo/sound', ffi.string(current_path))
	add_to_searchpath(current_path, 'XGAME', 0)
	local sound_files = lua.sounds.collect_files()
	for i = 1, #sound_files do
		local file_name = sound_files[i]
		lua.sounds.init_sound(lua.sounds.normalize_file_name(file_name), string.format('%s', file_name))
	end

    lua.pui.ui.group = {
        main = pui.group('aa', 'anti-aimbot angles'),
        fake = pui.group('aa', 'fake lag'),
        other = pui.group('aa', 'other')
    }

    lua.pui.ui.search = {
        title = lua.pui.ui.group.main:label('\aE7FBFFFFcry\aCFF4FFFFono\aA9DCEBFFva \aE7FBFFFF~ \aA9DCEBFFbuild(\a8FCFFAFFnightly\aA9DCEBFF)'),
        group = lua.pui.ui.group.main:combobox('\n ~ Internal group', {'Main'}),
        tab = lua.pui.ui.group.main:combobox('\n ~ Navigation', {lua.pui.tabs.welcome, lua.pui.tabs.builder, lua.pui.tabs.features, lua.pui.tabs.world, lua.pui.tabs.rage})
    }

    local welcome_username = 'your_username'
    pcall(function ()
        if panorama and panorama.open then
            local csgo_hud = panorama.open('CSGOHud')
            if csgo_hud and csgo_hud.MyPersonaAPI and csgo_hud.MyPersonaAPI.GetName then
                welcome_username = csgo_hud.MyPersonaAPI.GetName() or welcome_username
            end
        end
    end)

    lua.pui.ui.welcome = {
        user = ui.new_label('aa', 'anti-aimbot angles', '\aE7FBFFFF* \aC8EEF6FFUser: \aFFFFFFFF' .. welcome_username),
        version = ui.new_label('aa', 'anti-aimbot angles', '\aE7FBFFFF* \aC8EEF6FFVersion: \aFFFFFFFFNightly [debug]'),
        spacer = ui.new_label('aa', 'anti-aimbot angles', ' '),
        configs_label = ui.new_label('aa', 'anti-aimbot angles', '\aA9DCEBFF~ Your configs ~'),
        list = ui.new_listbox('aa', 'anti-aimbot angles', '\n ~ Cryonova configs', {'Default'}),
        name = ui.new_textbox('aa', 'anti-aimbot angles', '\n ~ Config name'),
        load = ui.new_button('aa', 'anti-aimbot angles', 'Load', function () if lua.pui.configs then lua.pui.configs.load_selected() end end),
        save = ui.new_button('aa', 'anti-aimbot angles', 'Save', function () if lua.pui.configs then lua.pui.configs.save_current() end end),
        delete = ui.new_button('aa', 'anti-aimbot angles', 'Delete', function () if lua.pui.configs then lua.pui.configs.delete_selected() end end),
        import_clipboard = ui.new_button('aa', 'anti-aimbot angles', 'Import from clipboard', function () if lua.pui.configs then lua.pui.configs.import_clipboard() end end),
        export_clipboard = ui.new_button('aa', 'anti-aimbot angles', 'Export to clipboard', function () if lua.pui.configs then lua.pui.configs.export_selected() end end)
    }
    lua.pui.ui.welcome_refs = {
        lua.pui.ui.welcome.user,
        lua.pui.ui.welcome.version,
        lua.pui.ui.welcome.spacer,
        lua.pui.ui.welcome.configs_label,
        lua.pui.ui.welcome.list,
        lua.pui.ui.welcome.name,
        lua.pui.ui.welcome.load,
        lua.pui.ui.welcome.save,
        lua.pui.ui.welcome.delete,
        lua.pui.ui.welcome.import_clipboard,
        lua.pui.ui.welcome.export_clipboard
    }
    for i = 1, #lua.pui.ui.welcome_refs do
        ui.set_visible(lua.pui.ui.welcome_refs[i], false)
    end

    lua.pui.ui.rage = {
        tweaks_label = lua.pui.ui.group.main:label('\f<color_start> ~ ' .. '\f<color_tabs> Tweaks'),
        resolver = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_sad> {alpha} ' .. '\f<color_tabs> Resolver'),
        resolver_mode = lua.pui.ui.group.main:combobox('\f<color_start> ~ ' .. '\f<color_ref> Resolver ' .. '\f<color_start> / ' .. '\f<color_tabs> Mode', {'Default', 'Experimental'}),
        defensive_aa_resolver = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_tabs> Defensive anti-aim resolver'),
        backtrack_exploit = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_tabs> Backtrack exploit'),
        dt_last_tick = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_tabs> Doubletap on last tick'),
        safety_label = lua.pui.ui.group.main:label('\f<color_start> ~ ' .. '\f<color_tabs> Safety'),
        force_body = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_tabs> Force body aim on lethal'),
        other_label = lua.pui.ui.group.main:label('\f<color_start> ~ ' .. '\f<color_tabs> Other'),
        shot_logs = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_tabs> Aimbot logs'),
        shot_logs_col = lua.pui.ui.group.main:color_picker('\n ~ Aimbot logs notify color', 255, 226, 243, 255),
        peekbot = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_tabs> Peek bot'),
        peekbot_bind = lua.pui.ui.group.main:hotkey('\f<color_start> ~ ' .. '\f<color_ref> Peek bot ' .. '\f<color_start> / ' .. '\f<color_tabs> Bind', false, 0),
        peekbot_distance = lua.pui.ui.group.main:slider('\f<color_start> ~ ' .. '\f<color_ref> Peek bot ' .. '\f<color_start> / ' .. '\f<color_tabs> Tracing distance', 30, 100, 60),
        peekbot_freestanding = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_ref> Peek bot ' .. '\f<color_start> / ' .. '\f<color_tabs> Freestanding'),
        peekbot_visualize = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_ref> Peek bot ' .. '\f<color_start> / ' .. '\f<color_tabs> Renderer trace positions')
    }

    lua.pui.ui.antiaim = {
        manuals = lua.pui.ui.group.other:checkbox('\f<color_start> ~ ' .. '\f<color_tabs> Manuals'),
        manuall = lua.pui.ui.group.other:hotkey('\f<color_start> ~ ' .. '\f<color_ref> Manuals ' .. '\f<color_start> / ' ..  '\f<color_tabs> Left', false, 0),
        manualr = lua.pui.ui.group.other:hotkey('\f<color_start> ~ ' .. '\f<color_ref> Manuals ' .. '\f<color_start> / ' ..  '\f<color_tabs> Right', false, 0),
        manualf = lua.pui.ui.group.other:hotkey('\f<color_start> ~ ' .. '\f<color_ref> Manuals ' .. '\f<color_start> / ' ..  '\f<color_tabs> Forward', false, 0),
        manualb = lua.pui.ui.group.other:hotkey('\f<color_start> ~ ' .. '\f<color_ref> Manuals ' .. '\f<color_start> / ' ..  '\f<color_tabs> Back', false, 0),
        manualsr = lua.pui.ui.group.other:hotkey('\f<color_start> ~ ' .. '\f<color_ref> Manuals ' .. '\f<color_start> / ' ..  '\f<color_tabs> Reset', false, 0),
        freestand = lua.pui.ui.group.other:hotkey('\f<color_start> ~ ' .. '\f<color_ref> Manuals ' .. '\f<color_start> / ' ..  '\f<color_tabs> Freestand', false, 0)
    }

    lua.pui.onground = false
    lua.pui.ticks = -1
    lua.pui.state = 'Regular'
    lua.pui.condition_names = {'Regular', 'Numb', 'Push', 'Crawling', 'Crouch', 'Сreeping', 'Aerobic', 'Aerobic+', 'Using', 'Freestand', 'Manual Left', 'Manual Right', 'Manual Back', 'Manual Forward'}
    lua.pui.ui.conditions = {}
    lua.pui.ui.state = lua.pui.ui.group.main:combobox('\f<color_start> ~ ' .. '\f<color_tabs> Condition', 'Regular', 'Numb', 'Push', 'Crawling', 'Crouch', 'Сreeping', 'Aerobic', 'Aerobic+', 'Using', 'Freestand', 'Manual Left', 'Manual Right', 'Manual Back', 'Manual Forward')
    lua.pui.ui.state:set_callback(function()
        lua.sounds.play(lua.sounds.contract, false)
    end, true)
    for i, name in pairs(lua.pui.condition_names) do
        lua.pui.ui.conditions[name] = {
            override = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Override '),
            yaw = lua.pui.ui.group.main:slider('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Yaw ', -180, 180, 0),
            yaw_lr = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Left / Right '),
            yaw_l = lua.pui.ui.group.main:slider('\n\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Left', -90, 90, 0),
            yaw_r = lua.pui.ui.group.main:slider('\n\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Right ', -90, 90, 0),
            yaw_multi = lua.pui.ui.group.main:multiselect('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Modifier ', {'Offset', 'Center', 'Random', 'Spray'}),
            yaw_multi_s = lua.pui.ui.group.main:slider('\n\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Modifier Slide', 0, 60, 0),
            lby = lua.pui.ui.group.main:combobox('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Body Yaw ', {'Off', 'Static', 'Ticks', 'Random Ticks'}),
            lby_yaw = lua.pui.ui.group.main:slider('\n\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Body Value ', 0, 60, 1),
            tick = lua.pui.ui.group.main:slider('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Delay ', 1, 15, 1),
            defensive = lua.pui.ui.group.fake:combobox('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Defensive ', {'Off', 'On Peek', 'Always', 'Flick'}),
            defensive_aa_on = lua.pui.ui.group.fake:checkbox('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Defensive Antiaim '),
            pitch_defensive_c = lua.pui.ui.group.fake:combobox('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Defensive Pitch', {'Default', 'Random'}),
            pitch_defensive_s = lua.pui.ui.group.fake:slider('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Defensive Pitch', -89, 89, 0),
            yawd_defensive_s = lua.pui.ui.group.fake:slider('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Defensive Yaw', 0, 180, 0),
            yaw_defensive = lua.pui.ui.group.fake:multiselect('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Defensive Modifier ', {'Offset', 'Center', 'Random', 'Spin'}),
            yaw_defensive_s = lua.pui.ui.group.fake:slider('\n\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Defensive Modifier Slide', 0, 180, 0),
            defensive_minus = lua.pui.ui.group.other:slider('\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Defensive Minus & Plus', 0, 5, 3),
            defensive_plus = lua.pui.ui.group.other:slider('\n\f<color_start> ~ ' .. '\f<color_ref> ' ..name .. ' \f<color_start> / ' .. '\f<color_tabs> Defensive Plus', 0, 14, 11),
        }
        lua.sounds.set(lua.pui.ui.conditions[name], lua.sounds.contract)
    end
    lua.pui.ui.conditions['Manual Left'].yaw:set(-90)
    lua.pui.ui.conditions['Manual Right'].yaw:set(90)
    lua.pui.ui.conditions['Manual Forward'].yaw:set(180)

    lua.pui.ui.home = {
        cryonova_label = lua.pui.ui.group.other:label('\f<color_tabs> Cryonova' .. '\f<color_start> ~ ' .. '\f<color_tabs> @javasense')
    }

    lua.pui.ui.animations = {
        animations_select = lua.pui.ui.group.main:multiselect('\f<color_start> ~ ' .. '\f<color_tabs> Animations', {'Aerobic', 'Ground', 'Lean', 'Additive'}):depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}),
        aerobic = lua.pui.ui.group.main:combobox('\f<color_start> ~ ' .. '\f<color_ref> Animations ' .. '\f<color_start> / ' .. '\f<color_tabs> Aerobic', {'Quadrobic', 'Static', 'Jitter', 'Trap', 'Swag', 'Walking'}),
        ground = lua.pui.ui.group.main:combobox('\f<color_start> ~ ' .. '\f<color_ref> Animations ' .. '\f<color_start> / ' .. '\f<color_tabs> Ground', {'Static', 'Static invert', 'Jitter', 'Trap', 'Swag', 'Freeze', 'Freeze & Static', 'Freeze & Static invert', 'Bugged'}),
        lean = lua.pui.ui.group.main:combobox('\f<color_start> ~ ' .. '\f<color_ref> Animations ' .. '\f<color_start> / ' .. '\f<color_tabs> Lean', {'Zero', 'Big', 'Jitter'}),
        other = lua.pui.ui.group.main:multiselect('\f<color_start> ~ ' .. '\f<color_ref> Animations ' .. '\f<color_start> / ' .. '\f<color_tabs> Additive', {'2021 animfix', 'Model scale', 'Autopeek fix', 'Animation smooth', 'Flashed', 'Zero pitch'})
    }

    lua.pui.ui.render = {
        panels_select = lua.pui.ui.group.main:multiselect('\f<color_start> ~ ' .. '\f<color_tabs> Widgets', {'Indicator', 'Obscuration', 'Damage', 'Hitmarker', 'Lag comp box', 'Watermark', 'Grenade visuals', 'Menu visuals', 'Reload indicator', 'Bomb timer'--[[, 'Binds']]}):depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}),
        indicator_style = lua.pui.ui.group.main:combobox('\f<color_start> ~ ' .. '\f<color_tabs> Indicator style', {'Mode v1', 'Mode v2'}),
        indicatorcol = lua.pui.ui.group.main:color_picker('\n ~ Indicator color', 155, 155, 155, 255),
        indicatorcol2 = lua.pui.ui.group.main:color_picker('\n ~ Indicator color 2', 100, 100, 255, 255),
        watermark_mode = lua.pui.ui.group.main:combobox('\f<color_start> ~ ' .. '\f<color_ref> Watermark ' .. '\f<color_start> / ' .. '\f<color_tabs> Mode', {'Mode 1', 'Mode 2'}),
        watermark_items = lua.pui.ui.group.main:multiselect('\f<color_start> ~ ' .. '\f<color_ref> Watermark ' .. '\f<color_start> / ' .. '\f<color_tabs> Items', {'Logo', 'KD Ratio', 'Speed', 'Framerate', 'Latency', 'Var', 'Loss', 'Connectivity Issues', 'Server Address', 'Preset', 'Username', 'Time'}),
        reload_indicator_color = lua.pui.ui.group.main:color_picker('\n ~ Reload indicator color', 120, 185, 255, 235),
        lagcomp_box_color = lua.pui.ui.group.main:color_picker('\n ~ Lag comp box color', 47, 117, 221, 255),
        lagcomp_text_color = lua.pui.ui.group.main:color_picker('\n ~ Lag comp text color', 255, 45, 45, 255),
        visual_tuning_label = lua.pui.ui.group.main:label('\f<color_start> ~ ' .. '\f<color_tabs> Visual tuning'),
        ui_scale = lua.pui.ui.group.main:slider('\f<color_start> ~ ' .. '\f<color_ref> UI ' .. '\f<color_start> / ' .. '\f<color_tabs> Visual scale', 60, 160, 100, true, '%'),
        ui_animation_speed = lua.pui.ui.group.main:slider('\f<color_start> ~ ' .. '\f<color_ref> UI ' .. '\f<color_start> / ' .. '\f<color_tabs> Animation speed', 25, 250, 100, true, '%'),
        grenade_visuals_label = lua.pui.ui.group.main:label('\f<color_start> ~ ' .. '\f<color_tabs> Grenade visuals'),
        grenade_timer = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_ref> Grenades ' .. '\f<color_start> / ' .. '\f<color_tabs> Text timer'),
        smoke_timer_color = lua.pui.ui.group.main:color_picker('\n ~ Smoke timer color', 145, 190, 255, 255),
        molotov_timer_color = lua.pui.ui.group.main:color_picker('\n ~ Molotov timer color', 255, 150, 70, 255),
        grenade_radius = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_ref> Grenades ' .. '\f<color_start> / ' .. '\f<color_tabs> Animated radius'),
        menu_visuals_label = lua.pui.ui.group.main:label('\f<color_start> ~ ' .. '\f<color_tabs> Menu visuals'),
        animated_intro = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_ref> Menu ' .. '\f<color_start> / ' .. '\f<color_tabs> Animated intro on load'),
        menu_particles = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_ref> Menu ' .. '\f<color_start> / ' .. '\f<color_tabs> Particles'),
        particles_amount = lua.pui.ui.group.main:slider('\f<color_start> ~ ' .. '\f<color_ref> Particles ' .. '\f<color_start> / ' .. '\f<color_tabs> Amount', 8, 80, 32),
        cursor_trail = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_ref> Menu ' .. '\f<color_start> / ' .. '\f<color_tabs> Cursor trail'),
        cursor_trail_color = lua.pui.ui.group.main:color_picker('\n ~ Cursor trail color', 190, 90, 255, 210),
    }
    lua.pui.ui.render.animated_intro:set(true)
    lua.pui.ui.aspectratio_info = {[177] = '16:9',[161] = '16:10',[150] = '3:2',[133] = '4:3',[125] = '5:4'}
    lua.pui.ui.world = {
        world_manager = lua.pui.ui.group.other:multiselect('\f<color_start> ~ ' .. '\f<color_tabs> Selection \n world', {'Local Sharing', 'Viewmodel', 'View changer'}):depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}),
        me_sharing_v = lua.pui.ui.group.other:checkbox('\f<color_start> ~ ' .. '\f<color_ref> Local Sharing ' .. '\f<color_start> / ' .. '\f<color_tabs> Visible'),
        me_sharing = lua.pui.ui.group.other:combobox('\n ~ Local Sharing', {'Static', 'Dragging'}),
        me_sharingcol = lua.pui.ui.group.other:color_picker('\n ~ Local Sharing color', 255, 0, 0, 255),
        handdrag_v = lua.pui.ui.group.other:checkbox('\f<color_start> ~ ' .. '\f<color_ref> Viewmodel ' .. '\f<color_start> / ' .. '\f<color_tabs> Visible'),
        hands_drag = lua.pui.ui.group.other:checkbox('\f<color_start> ~ ' .. '\f<color_tabs> Viewmodel changer'),
        hand_fov = lua.pui.ui.group.other:slider('\f<color_start> ~ ' .. '\f<color_ref> Viewmodel ' .. '\f<color_start> / ' .. '\f<color_tabs> FOV', -90, 90, cvar.viewmodel_fov:get_float()),
        hand_x = lua.pui.ui.group.other:slider('\f<color_start> ~ ' .. '\f<color_ref> Viewmodel ' .. '\f<color_start> / ' .. '\f<color_tabs> X', -1000, 1000, cvar.viewmodel_offset_x:get_float(), true, '', 0.01),
        hand_y = lua.pui.ui.group.other:slider('\f<color_start> ~ ' .. '\f<color_ref> Viewmodel ' .. '\f<color_start> / ' .. '\f<color_tabs> Y', -1000, 1000, cvar.viewmodel_offset_y:get_float(), true, '', 0.01),
        hand_z = lua.pui.ui.group.other:slider('\f<color_start> ~ ' .. '\f<color_ref> Viewmodel ' .. '\f<color_start> / ' .. '\f<color_tabs> Z', -1000, 1000, cvar.viewmodel_offset_z:get_float(), true, '', 0.01),
        viewdrag_v = lua.pui.ui.group.other:checkbox('\f<color_start> ~ ' .. '\f<color_ref> View changer ' .. '\f<color_start> / ' .. '\f<color_tabs> Visible'),
        custom_scope = lua.pui.ui.group.other:checkbox('\f<color_start> ~ ' .. '\f<color_tabs> Custom scope', {155, 155, 155}),
        custom_scope_position = lua.pui.ui.group.other:slider('\f<color_start> ~ ' .. '\f<color_ref> Scope ' .. '\f<color_start> / ' .. '\f<color_tabs> Position', 5, 500, 90),
        custom_scope_offset = lua.pui.ui.group.other:slider('\f<color_start> ~ ' .. '\f<color_ref> Scope ' .. '\f<color_start> / ' .. '\f<color_tabs> Offset', 3, 500, 3),
        custom_scope_fade = lua.pui.ui.group.other:slider('\f<color_start> ~ ' .. '\f<color_ref> Scope ' .. '\f<color_start> / ' .. '\f<color_tabs> Fade time', 3, 20, 12, true, 'fr', 1, { [3] = 'Off' }),
        zoom_scale = lua.pui.ui.group.other:checkbox('\f<color_start> ~ ' .. '\f<color_tabs> Zoom scaling'),
        zoom_offset = lua.pui.ui.group.other:slider('\f<color_start> ~ ' .. '\f<color_ref> Zoom ' .. '\f<color_start> / ' .. '\f<color_tabs> Offset', -25, 60, 0),
        aspectratio = lua.pui.ui.group.other:slider('\f<color_start> ~ ' .. '\f<color_tabs> Aspect Ratio', 0, 300, 0, true, '', 0.01, lua.pui.ui.aspectratio_info),
    }

    lua.pui.ui.additive = {
        other = lua.pui.ui.group.main:multiselect('\f<color_start> ~ ' .. '\f<color_tabs> Selection \n Additive', {'Sounds', 'Razpeek', 'Fast Ladder', 'Force Update', 'Clantag', 'Console filter', 'Yandex Music', 'Avoid backstab'}):depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}),
        force_update = lua.pui.ui.group.main:button('\f<color_tabs>Force update', function() return client.request_full_update(), client.reload_active_scripts() end),
        sounds_check = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_tabs> Hitsound'),
        sounds_list = lua.pui.ui.group.main:combobox('\n \f<color_start> ~ ' .. '\f<color_tabs> Hitsound', lua.sounds.sound_names),
        yandex_x = lua.pui.ui.group.main:slider('\n \f<color_start> ~ ' .. '\f<color_tabs> Yandex HUD x', 0, 1920, 30, true, 'px'),
        yandex_y = lua.pui.ui.group.main:slider('\f<color_start> ~ ' .. '\f<color_tabs> Yandex HUD y', 0, 1080, 300, true, 'px'),
        yandex_w = lua.pui.ui.group.main:slider('\f<color_start> ~ ' .. '\f<color_tabs> Yandex HUD width', 320, 760, 430, true, 'px'),
        yandex_update = lua.pui.ui.group.main:slider('\f<color_start> ~ ' .. '\f<color_tabs> Yandex HUD update', 1, 10, 2, true, 's'),
        yandex_cover = lua.pui.ui.group.main:checkbox('\f<color_start> ~ ' .. '\f<color_tabs> Yandex HUD cover'),
        yandex_accent = lua.pui.ui.group.main:color_picker('\n ~ Yandex left bar color', 255, 200, 0, 255),
        yandex_alpha = lua.pui.ui.group.main:slider('\f<color_start> ~ ' .. '\f<color_tabs> Yandex HUD alpha', 0, 255, 255),
        yandex_prev = lua.pui.ui.group.main:button('\f<color_tabs>Yandex previous', function() lua.yandex.send_command('previous') end),
        yandex_play = lua.pui.ui.group.main:button('\f<color_tabs>Yandex play / pause', function() lua.yandex.send_command('playpause') end),
        yandex_next = lua.pui.ui.group.main:button('\f<color_tabs>Yandex next', function() lua.yandex.send_command('next') end)
    }

    local config = {lua.pui.ui.conditions, lua.pui.ui.animations, lua.pui.ui.render, lua.pui.ui.world, lua.pui.ui.additive, lua.pui.ui.rage}
    local package, data, encrypted, decrypted = pui.setup(config)

    lua.pui.ui.export = function ()
        data = package:save()
        encrypted = base64.encode(json.stringify(data))
        clipboard.set(encrypted)
        if lua.notifications and lua.notifications.event_enabled('config') then
            lua.notifications.push('success', 'Config', 'Exported to clipboard')
        end
    end

    lua.pui.ui.import = function (input)
        local ok, err = pcall(function ()
            decrypted = json.parse(base64.decode(input ~= nil and input or clipboard.get()))
            package:load(decrypted)
        end)
        if lua.notifications and lua.notifications.event_enabled('config') then
            if ok then
                lua.notifications.push('success', 'Config', 'Config loaded')
            else
                lua.notifications.push('error', 'Config error', tostring(err):gsub('\\n', ' '):sub(1, 90))
            end
        end
        if not ok then client.color_log(255, 100, 100, '[cryonova] config import failed: ', tostring(err)) end
    end

    local cfg_beta = 'W3siQ3JvdWNoIjp7ImxieV95YXciOjEsImxieSI6IlJhbmRvbSBUaWNrcyIsInlhd19yIjowLCJwaXRjaF9kZWZlbnNpdmVfcyI6LTg5LCJ5YXdfbHIiOmZhbHNlLCJ5YXdfbCI6MCwiZGVmZW5zaXZlX21pbnVzIjozLCJkZWZlbnNpdmUiOiJGbGljayIsIm92ZXJyaWRlIjp0cnVlLCJkZWZlbnNpdmVfYWFfb24iOnRydWUsInlhd19kZWZlbnNpdmVfcyI6NjUsInRpY2siOjEsInlhdyI6MCwieWF3X211bHRpX3MiOjIwLCJ5YXdkX2RlZmVuc2l2ZV9zIjo5MCwieWF3X2RlZmVuc2l2ZSI6WyJDZW50ZXIiLCJSYW5kb20iLCJTcGluIiwifiJdLCJkZWZlbnNpdmVfcGx1cyI6MTEsInlhd19tdWx0aSI6WyJDZW50ZXIiLCJSYW5kb20iLCJ+Il19LCJQdXNoIjp7ImxieV95YXciOjEsImxieSI6IlJhbmRvbSBUaWNrcyIsInlhd19yIjowLCJwaXRjaF9kZWZlbnNpdmVfcyI6LTIyLCJ5YXdfbHIiOmZhbHNlLCJ5YXdfbCI6MCwiZGVmZW5zaXZlX21pbnVzIjozLCJkZWZlbnNpdmUiOiJPbiBQZWVrIiwib3ZlcnJpZGUiOnRydWUsImRlZmVuc2l2ZV9hYV9vbiI6dHJ1ZSwieWF3X2RlZmVuc2l2ZV9zIjoyNSwidGljayI6MSwieWF3IjowLCJ5YXdfbXVsdGlfcyI6MjUsInlhd2RfZGVmZW5zaXZlX3MiOjEwMCwieWF3X2RlZmVuc2l2ZSI6WyJSYW5kb20iLCJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIkNlbnRlciIsIlJhbmRvbSIsIn4iXX0sIk1hbnVhbCBGb3J3YXJkIjp7ImxieV95YXciOjEsImxieSI6Ik9mZiIsInlhd19yIjowLCJwaXRjaF9kZWZlbnNpdmVfcyI6MCwieWF3X2xyIjpmYWxzZSwieWF3X2wiOjAsImRlZmVuc2l2ZV9taW51cyI6MywiZGVmZW5zaXZlIjoiT2ZmIiwib3ZlcnJpZGUiOmZhbHNlLCJkZWZlbnNpdmVfYWFfb24iOmZhbHNlLCJ5YXdfZGVmZW5zaXZlX3MiOjAsInRpY2siOjEsInlhdyI6MTgwLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIkFlcm9iaWMrIjp7ImxieV95YXciOjEsImxieSI6IlRpY2tzIiwieWF3X3IiOjAsInBpdGNoX2RlZmVuc2l2ZV9zIjotODksInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6IkZsaWNrIiwib3ZlcnJpZGUiOnRydWUsImRlZmVuc2l2ZV9hYV9vbiI6dHJ1ZSwieWF3X2RlZmVuc2l2ZV9zIjoxNTAsInRpY2siOjEsInlhdyI6MCwieWF3X211bHRpX3MiOjMwLCJ5YXdkX2RlZmVuc2l2ZV9zIjowLCJ5YXdfZGVmZW5zaXZlIjpbIkNlbnRlciIsIlJhbmRvbSIsIlNwaW4iLCJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIkNlbnRlciIsIn4iXX0sIkNyYXdsaW5nIjp7ImxieV95YXciOjEsImxieSI6IlRpY2tzIiwieWF3X3IiOjgsInBpdGNoX2RlZmVuc2l2ZV9zIjowLCJ5YXdfbHIiOnRydWUsInlhd19sIjotMTQsImRlZmVuc2l2ZV9taW51cyI6MywiZGVmZW5zaXZlIjoiRmxpY2siLCJvdmVycmlkZSI6dHJ1ZSwiZGVmZW5zaXZlX2FhX29uIjpmYWxzZSwieWF3X2RlZmVuc2l2ZV9zIjowLCJ0aWNrIjo1LCJ5YXciOjAsInlhd19tdWx0aV9zIjoyNywieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIlJhbmRvbSIsIn4iXX0sIkZyZWVzdGFuZCI6eyJsYnlfeWF3IjoxLCJsYnkiOiJPZmYiLCJ5YXdfciI6MCwicGl0Y2hfZGVmZW5zaXZlX3MiOjAsInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6Ik9mZiIsIm92ZXJyaWRlIjpmYWxzZSwiZGVmZW5zaXZlX2FhX29uIjpmYWxzZSwieWF3X2RlZmVuc2l2ZV9zIjowLCJ0aWNrIjoxLCJ5YXciOjAsInlhd19tdWx0aV9zIjowLCJ5YXdkX2RlZmVuc2l2ZV9zIjowLCJ5YXdfZGVmZW5zaXZlIjpbIn4iXSwiZGVmZW5zaXZlX3BsdXMiOjExLCJ5YXdfbXVsdGkiOlsifiJdfSwiTnVtYiI6eyJsYnlfeWF3IjoxLCJsYnkiOiJSYW5kb20gVGlja3MiLCJ5YXdfciI6MCwicGl0Y2hfZGVmZW5zaXZlX3MiOjAsInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6Ik9mZiIsIm92ZXJyaWRlIjp0cnVlLCJkZWZlbnNpdmVfYWFfb24iOmZhbHNlLCJ5YXdfZGVmZW5zaXZlX3MiOjAsInRpY2siOjEsInlhdyI6MCwieWF3X211bHRpX3MiOjE4LCJ5YXdkX2RlZmVuc2l2ZV9zIjowLCJ5YXdfZGVmZW5zaXZlIjpbIn4iXSwiZGVmZW5zaXZlX3BsdXMiOjExLCJ5YXdfbXVsdGkiOlsiT2Zmc2V0IiwiQ2VudGVyIiwiUmFuZG9tIiwifiJdfSwiTWFudWFsIEJhY2siOnsibGJ5X3lhdyI6MSwibGJ5IjoiT2ZmIiwieWF3X3IiOjAsInBpdGNoX2RlZmVuc2l2ZV9zIjowLCJ5YXdfbHIiOmZhbHNlLCJ5YXdfbCI6MCwiZGVmZW5zaXZlX21pbnVzIjozLCJkZWZlbnNpdmUiOiJPZmYiLCJvdmVycmlkZSI6ZmFsc2UsImRlZmVuc2l2ZV9hYV9vbiI6ZmFsc2UsInlhd19kZWZlbnNpdmVfcyI6MCwidGljayI6MSwieWF3IjowLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIk1hbnVhbCBMZWZ0Ijp7ImxieV95YXciOjEsImxieSI6Ik9mZiIsInlhd19yIjowLCJwaXRjaF9kZWZlbnNpdmVfcyI6MCwieWF3X2xyIjpmYWxzZSwieWF3X2wiOjAsImRlZmVuc2l2ZV9taW51cyI6MywiZGVmZW5zaXZlIjoiT2ZmIiwib3ZlcnJpZGUiOmZhbHNlLCJkZWZlbnNpdmVfYWFfb24iOmZhbHNlLCJ5YXdfZGVmZW5zaXZlX3MiOjAsInRpY2siOjEsInlhdyI6LTkwLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIk1hbnVhbCBSaWdodCI6eyJsYnlfeWF3IjoxLCJsYnkiOiJPZmYiLCJ5YXdfciI6MCwicGl0Y2hfZGVmZW5zaXZlX3MiOjAsInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6Ik9mZiIsIm92ZXJyaWRlIjpmYWxzZSwiZGVmZW5zaXZlX2FhX29uIjpmYWxzZSwieWF3X2RlZmVuc2l2ZV9zIjowLCJ0aWNrIjoxLCJ5YXciOjkwLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sItChcmVlcGluZyI6eyJsYnlfeWF3IjoxLCJsYnkiOiJPZmYiLCJ5YXdfciI6MCwicGl0Y2hfZGVmZW5zaXZlX3MiOjAsInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6Ik9mZiIsIm92ZXJyaWRlIjpmYWxzZSwiZGVmZW5zaXZlX2FhX29uIjpmYWxzZSwieWF3X2RlZmVuc2l2ZV9zIjowLCJ0aWNrIjoxLCJ5YXciOjAsInlhd19tdWx0aV9zIjowLCJ5YXdkX2RlZmVuc2l2ZV9zIjowLCJ5YXdfZGVmZW5zaXZlIjpbIn4iXSwiZGVmZW5zaXZlX3BsdXMiOjExLCJ5YXdfbXVsdGkiOlsifiJdfSwiUmVndWxhciI6eyJsYnlfeWF3Ijo2MCwibGJ5IjoiU3RhdGljIiwieWF3X3IiOjAsInBpdGNoX2RlZmVuc2l2ZV9zIjo4OSwieWF3X2xyIjpmYWxzZSwieWF3X2wiOjAsImRlZmVuc2l2ZV9taW51cyI6MywiZGVmZW5zaXZlIjoiRmxpY2siLCJvdmVycmlkZSI6ZmFsc2UsImRlZmVuc2l2ZV9hYV9vbiI6dHJ1ZSwieWF3X2RlZmVuc2l2ZV9zIjo5MCwidGljayI6MSwieWF3IjowLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJDZW50ZXIiLCJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIkFlcm9iaWMiOnsibGJ5X3lhdyI6NjAsImxieSI6IlRpY2tzIiwieWF3X3IiOi0xOSwicGl0Y2hfZGVmZW5zaXZlX3MiOi00NSwieWF3X2xyIjpmYWxzZSwieWF3X2wiOjE5LCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6IkFsd2F5cyIsIm92ZXJyaWRlIjp0cnVlLCJkZWZlbnNpdmVfYWFfb24iOnRydWUsInlhd19kZWZlbnNpdmVfcyI6NzAsInRpY2siOjIsInlhdyI6MCwieWF3X211bHRpX3MiOjM2LCJ5YXdkX2RlZmVuc2l2ZV9zIjo0NSwieWF3X2RlZmVuc2l2ZSI6WyJTcGluIiwifiJdLCJkZWZlbnNpdmVfcGx1cyI6MTEsInlhd19tdWx0aSI6WyJSYW5kb20iLCJ+Il19fSx7ImFlcm9iaWMiOiJUcmFwIiwiYW5pbWF0aW9uc19zZWxlY3QiOlsiQWVyb2JpYyIsIkdyb3VuZCIsIkxlYW4iLCJBZGRpdGl2ZSIsIn4iXSwibGVhbiI6IkppdHRlciIsIm90aGVyIjpbIkF1dG9wZWVrIGZpeCIsIkFuaW1hdGlvbiBzbW9vdGgiLCJ+Il0sImdyb3VuZCI6IlN3YWcifSx7ImluZGljYXRvcmNvbDIiOiIjNjQ2NEZGRkYiLCJpbmRpY2F0b3IiOlsiU2NvcGUiLCJHcmVuYWRlIiwifiJdLCJncmFwaCI6ZmFsc2UsImluZGljYXRvcmNvbCI6IiNGRkZGRkZGRiIsImdyYXBoX2MiOiIjNzhBMDUwRkYiLCJwYW5lbHNfc2VsZWN0IjpbIkluZGljYXRvciIsIn4iXX0seyJoYW5kZHJhZ192IjpmYWxzZSwidGhpcmRwZXJzb24iOjY5LCJjdXN0b21fc2NvcGVfcG9zaXRpb24iOjkwLCJmbGFzaGxpZ2h0IjpmYWxzZSwidmlld2RyYWdfdiI6ZmFsc2UsImN1c3RvbV9zY29wZV9mYWRlIjoxMiwiY3VzdG9tX3Njb3BlX29mZnNldCI6Mywiem9vbV9zY2FsZSI6ZmFsc2UsInRoaXJkcGVyc29uX2FuaW0iOmZhbHNlLCJtZV9zaGFyaW5nX3YiOmZhbHNlLCJoYW5kX3oiOi0xLCJoYW5kX3giOjEsImN1c3RvbV9zY29wZSI6ZmFsc2UsIndvcmxkX21hbmFnZXIiOlsifiJdLCJhc3BlY3RyYXRpbyI6MCwiZmxhc2hsaWdodF92IjpmYWxzZSwiaGFuZF9mb3YiOjU2LCJoYW5kc19kcmFnIjpmYWxzZSwiY3VzdG9tX3Njb3BlX2MiOiIjOUI5QjlCRkYiLCJtZV9zaGFyaW5nY29sIjoiI0ZGMDAwMEZGIiwiaGFuZF95IjotNCwibWVfc2hhcmluZyI6IlN0YXRpYyIsInpvb21fb2Zmc2V0IjowfSx7InNvdW5kc19saXN0IjoiU3dpdGNoIDNEIiwic291bmRzX2NoZWNrIjpmYWxzZSwib3RoZXIiOlsifiJdfV0='
    local cfg_agr = 'W3siQ3JvdWNoIjp7ImxieV95YXciOjEsImxieSI6IlRpY2tzIiwieWF3X3IiOjUwLCJwaXRjaF9kZWZlbnNpdmVfcyI6LTg5LCJ5YXdfbHIiOnRydWUsInlhd19sIjotMzIsImRlZmVuc2l2ZV9taW51cyI6MywiZGVmZW5zaXZlIjoiRmxpY2siLCJvdmVycmlkZSI6dHJ1ZSwiZGVmZW5zaXZlX2FhX29uIjp0cnVlLCJ5YXdfZGVmZW5zaXZlX3MiOjgxLCJ0aWNrIjoyLCJ5YXciOjAsInlhd19tdWx0aV9zIjowLCJ5YXdkX2RlZmVuc2l2ZV9zIjozNywieWF3X2RlZmVuc2l2ZSI6WyJDZW50ZXIiLCJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIlB1c2giOnsibGJ5X3lhdyI6MSwibGJ5IjoiVGlja3MiLCJ5YXdfciI6MzcsInBpdGNoX2RlZmVuc2l2ZV9zIjowLCJ5YXdfbHIiOnRydWUsInlhd19sIjotMzIsImRlZmVuc2l2ZV9taW51cyI6MywiZGVmZW5zaXZlIjoiT24gUGVlayIsIm92ZXJyaWRlIjp0cnVlLCJkZWZlbnNpdmVfYWFfb24iOmZhbHNlLCJ5YXdfZGVmZW5zaXZlX3MiOjAsInRpY2siOjIsInlhdyI6MCwieWF3X211bHRpX3MiOjAsInlhd2RfZGVmZW5zaXZlX3MiOjAsInlhd19kZWZlbnNpdmUiOlsifiJdLCJkZWZlbnNpdmVfcGx1cyI6MTEsInlhd19tdWx0aSI6WyJ+Il19LCJNYW51YWwgRm9yd2FyZCI6eyJsYnlfeWF3IjoxLCJsYnkiOiJPZmYiLCJ5YXdfciI6MCwicGl0Y2hfZGVmZW5zaXZlX3MiOjAsInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6Ik9mZiIsIm92ZXJyaWRlIjpmYWxzZSwiZGVmZW5zaXZlX2FhX29uIjpmYWxzZSwieWF3X2RlZmVuc2l2ZV9zIjowLCJ0aWNrIjoxLCJ5YXciOjAsInlhd19tdWx0aV9zIjowLCJ5YXdkX2RlZmVuc2l2ZV9zIjowLCJ5YXdfZGVmZW5zaXZlIjpbIn4iXSwiZGVmZW5zaXZlX3BsdXMiOjExLCJ5YXdfbXVsdGkiOlsifiJdfSwiQWVyb2JpYysiOnsibGJ5X3lhdyI6MSwibGJ5IjoiVGlja3MiLCJ5YXdfciI6NDcsInBpdGNoX2RlZmVuc2l2ZV9zIjotNTksInlhd19sciI6dHJ1ZSwieWF3X2wiOi0zNSwiZGVmZW5zaXZlX21pbnVzIjozLCJkZWZlbnNpdmUiOiJBbHdheXMiLCJvdmVycmlkZSI6dHJ1ZSwiZGVmZW5zaXZlX2FhX29uIjp0cnVlLCJ5YXdfZGVmZW5zaXZlX3MiOjEwNiwidGljayI6MywieWF3IjowLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJSYW5kb20iLCJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIkNyYXdsaW5nIjp7ImxieV95YXciOjEsImxieSI6IlRpY2tzIiwieWF3X3IiOjAsInBpdGNoX2RlZmVuc2l2ZV9zIjotNDcsInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6Ik9uIFBlZWsiLCJvdmVycmlkZSI6dHJ1ZSwiZGVmZW5zaXZlX2FhX29uIjpmYWxzZSwieWF3X2RlZmVuc2l2ZV9zIjoxODAsInRpY2siOjEsInlhdyI6LTMsInlhd19tdWx0aV9zIjoxMCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJSYW5kb20iLCJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIkNlbnRlciIsIn4iXX0sIkZyZWVzdGFuZCI6eyJsYnlfeWF3IjowLCJsYnkiOiJTdGF0aWMiLCJ5YXdfciI6MCwicGl0Y2hfZGVmZW5zaXZlX3MiOjAsInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjAsImRlZmVuc2l2ZSI6Ik9uIFBlZWsiLCJvdmVycmlkZSI6dHJ1ZSwiZGVmZW5zaXZlX2FhX29uIjp0cnVlLCJ5YXdfZGVmZW5zaXZlX3MiOjM1LCJ0aWNrIjoxLCJ5YXciOjAsInlhd19tdWx0aV9zIjowLCJ5YXdkX2RlZmVuc2l2ZV9zIjoxMDAsInlhd19kZWZlbnNpdmUiOlsiUmFuZG9tIiwifiJdLCJkZWZlbnNpdmVfcGx1cyI6MTEsInlhd19tdWx0aSI6WyJ+Il19LCJOdW1iIjp7ImxieV95YXciOjEsImxieSI6IlRpY2tzIiwieWF3X3IiOjM5LCJwaXRjaF9kZWZlbnNpdmVfcyI6MCwieWF3X2xyIjp0cnVlLCJ5YXdfbCI6LTIxLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6Ik9mZiIsIm92ZXJyaWRlIjp0cnVlLCJkZWZlbnNpdmVfYWFfb24iOmZhbHNlLCJ5YXdfZGVmZW5zaXZlX3MiOjAsInRpY2siOjIsInlhdyI6MCwieWF3X211bHRpX3MiOjAsInlhd2RfZGVmZW5zaXZlX3MiOjAsInlhd19kZWZlbnNpdmUiOlsifiJdLCJkZWZlbnNpdmVfcGx1cyI6MTEsInlhd19tdWx0aSI6WyJ+Il19LCJNYW51YWwgQmFjayI6eyJsYnlfeWF3IjoxLCJsYnkiOiJPZmYiLCJ5YXdfciI6MCwicGl0Y2hfZGVmZW5zaXZlX3MiOjAsInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6Ik9mZiIsIm92ZXJyaWRlIjpmYWxzZSwiZGVmZW5zaXZlX2FhX29uIjpmYWxzZSwieWF3X2RlZmVuc2l2ZV9zIjowLCJ0aWNrIjoxLCJ5YXciOjAsInlhd19tdWx0aV9zIjowLCJ5YXdkX2RlZmVuc2l2ZV9zIjowLCJ5YXdfZGVmZW5zaXZlIjpbIn4iXSwiZGVmZW5zaXZlX3BsdXMiOjExLCJ5YXdfbXVsdGkiOlsifiJdfSwiTWFudWFsIExlZnQiOnsibGJ5X3lhdyI6NjAsImxieSI6IlN0YXRpYyIsInlhd19yIjowLCJwaXRjaF9kZWZlbnNpdmVfcyI6MCwieWF3X2xyIjpmYWxzZSwieWF3X2wiOjAsImRlZmVuc2l2ZV9taW51cyI6MywiZGVmZW5zaXZlIjoiT24gUGVlayIsIm92ZXJyaWRlIjp0cnVlLCJkZWZlbnNpdmVfYWFfb24iOnRydWUsInlhd19kZWZlbnNpdmVfcyI6MCwidGljayI6MSwieWF3IjotOTAsInlhd19tdWx0aV9zIjowLCJ5YXdkX2RlZmVuc2l2ZV9zIjo5MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIk1hbnVhbCBSaWdodCI6eyJsYnlfeWF3Ijo2MCwibGJ5IjoiU3RhdGljIiwieWF3X3IiOjAsInBpdGNoX2RlZmVuc2l2ZV9zIjowLCJ5YXdfbHIiOmZhbHNlLCJ5YXdfbCI6MCwiZGVmZW5zaXZlX21pbnVzIjozLCJkZWZlbnNpdmUiOiJPbiBQZWVrIiwib3ZlcnJpZGUiOnRydWUsImRlZmVuc2l2ZV9hYV9vbiI6dHJ1ZSwieWF3X2RlZmVuc2l2ZV9zIjowLCJ0aWNrIjoxLCJ5YXciOjkwLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6OTAsInlhd19kZWZlbnNpdmUiOlsifiJdLCJkZWZlbnNpdmVfcGx1cyI6MTEsInlhd19tdWx0aSI6WyJ+Il19LCLQoXJlZXBpbmciOnsibGJ5X3lhdyI6MSwibGJ5IjoiT2ZmIiwieWF3X3IiOjAsInBpdGNoX2RlZmVuc2l2ZV9zIjowLCJ5YXdfbHIiOmZhbHNlLCJ5YXdfbCI6MCwiZGVmZW5zaXZlX21pbnVzIjozLCJkZWZlbnNpdmUiOiJPZmYiLCJvdmVycmlkZSI6ZmFsc2UsImRlZmVuc2l2ZV9hYV9vbiI6ZmFsc2UsInlhd19kZWZlbnNpdmVfcyI6MCwidGljayI6MSwieWF3IjowLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIlJlZ3VsYXIiOnsibGJ5X3lhdyI6MCwibGJ5IjoiVGlja3MiLCJ5YXdfciI6MCwicGl0Y2hfZGVmZW5zaXZlX3MiOjAsInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6Ik9uIFBlZWsiLCJvdmVycmlkZSI6ZmFsc2UsImRlZmVuc2l2ZV9hYV9vbiI6ZmFsc2UsInlhd19kZWZlbnNpdmVfcyI6ODAsInRpY2siOjEsInlhdyI6MCwieWF3X211bHRpX3MiOjI1LCJ5YXdkX2RlZmVuc2l2ZV9zIjoxMDAsInlhd19kZWZlbnNpdmUiOlsifiJdLCJkZWZlbnNpdmVfcGx1cyI6MTEsInlhd19tdWx0aSI6WyJ+Il19LCJBZXJvYmljIjp7ImxieV95YXciOjEsImxieSI6IlRpY2tzIiwieWF3X3IiOjAsInBpdGNoX2RlZmVuc2l2ZV9zIjotODksInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6IkFsd2F5cyIsIm92ZXJyaWRlIjp0cnVlLCJkZWZlbnNpdmVfYWFfb24iOnRydWUsInlhd19kZWZlbnNpdmVfcyI6MTIwLCJ0aWNrIjoxLCJ5YXciOjUsInlhd19tdWx0aV9zIjo0MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJDZW50ZXIiLCJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIkNlbnRlciIsIn4iXX19LHsiYWVyb2JpYyI6IlN0YXRpYyIsImFuaW1hdGlvbnNfc2VsZWN0IjpbIkFlcm9iaWMiLCJHcm91bmQiLCJMZWFuIiwiQWRkaXRpdmUiLCJ+Il0sImxlYW4iOiJCaWciLCJvdGhlciI6WyJBdXRvcGVlayBmaXgiLCJBbmltYXRpb24gc21vb3RoIiwifiJdLCJncm91bmQiOiJTdGF0aWMgaW52ZXJ0In0seyJpbmRpY2F0b3Jjb2wyIjoiIzY0NjRGRkZGIiwiaW5kaWNhdG9yIjpbIlNjb3BlIiwiR3JlbmFkZSIsIn4iXSwiZ3JhcGgiOmZhbHNlLCJpbmRpY2F0b3Jjb2wiOiIjRkZGRkZGRkYiLCJncmFwaF9jIjoiIzc4QTA1MEZGIiwicGFuZWxzX3NlbGVjdCI6WyJEYW1hZ2UiLCJIaXRtYXJrZXIiLCJ+Il19LHsiaGFuZGRyYWdfdiI6dHJ1ZSwidGhpcmRwZXJzb24iOjY5LCJjdXN0b21fc2NvcGVfcG9zaXRpb24iOjkwLCJmbGFzaGxpZ2h0IjpmYWxzZSwidmlld2RyYWdfdiI6dHJ1ZSwiY3VzdG9tX3Njb3BlX2ZhZGUiOjEyLCJjdXN0b21fc2NvcGVfb2Zmc2V0Ijo2MCwiem9vbV9zY2FsZSI6ZmFsc2UsInRoaXJkcGVyc29uX2FuaW0iOmZhbHNlLCJtZV9zaGFyaW5nX3YiOmZhbHNlLCJoYW5kX3oiOi0xMzUsImhhbmRfeCI6MCwiY3VzdG9tX3Njb3BlIjp0cnVlLCJ3b3JsZF9tYW5hZ2VyIjpbIkhhbmRzIERyYWdnaW5nIiwiVmlldyBEcmFnZ2luZyIsIn4iXSwiYXNwZWN0cmF0aW8iOjAsImZsYXNobGlnaHRfdiI6ZmFsc2UsImhhbmRfZm92Ijo1OSwiaGFuZHNfZHJhZyI6dHJ1ZSwiY3VzdG9tX3Njb3BlX2MiOiIjOUI5QjlCRkYiLCJtZV9zaGFyaW5nY29sIjoiI0ZGMDAwMEZGIiwiaGFuZF95IjotMjAwLCJtZV9zaGFyaW5nIjoiRHJhZ2dpbmciLCJ6b29tX29mZnNldCI6NH0seyJzb3VuZHNfbGlzdCI6IkltcGFjdCIsInNvdW5kc19jaGVjayI6dHJ1ZSwib3RoZXIiOlsiU291bmRzIiwifiJdfV0='
    local cfg = 'W3siQ3JvdWNoIjp7ImxieV95YXciOjEsImxieSI6IlRpY2tzIiwieWF3X3IiOjUwLCJwaXRjaF9kZWZlbnNpdmVfcyI6MCwieWF3X2xyIjp0cnVlLCJ5YXdfbCI6LTMyLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6IkZsaWNrIiwib3ZlcnJpZGUiOnRydWUsImRlZmVuc2l2ZV9hYV9vbiI6ZmFsc2UsInlhd19kZWZlbnNpdmVfcyI6MCwidGljayI6MiwieWF3IjowLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIlB1c2giOnsibGJ5X3lhdyI6MSwibGJ5IjoiVGlja3MiLCJ5YXdfciI6MzcsInBpdGNoX2RlZmVuc2l2ZV9zIjowLCJ5YXdfbHIiOnRydWUsInlhd19sIjotMzIsImRlZmVuc2l2ZV9taW51cyI6MywiZGVmZW5zaXZlIjoiT24gUGVlayIsIm92ZXJyaWRlIjp0cnVlLCJkZWZlbnNpdmVfYWFfb24iOmZhbHNlLCJ5YXdfZGVmZW5zaXZlX3MiOjAsInRpY2siOjIsInlhdyI6MCwieWF3X211bHRpX3MiOjEwLCJ5YXdkX2RlZmVuc2l2ZV9zIjowLCJ5YXdfZGVmZW5zaXZlIjpbIn4iXSwiZGVmZW5zaXZlX3BsdXMiOjExLCJ5YXdfbXVsdGkiOlsiUmFuZG9tIiwifiJdfSwiTWFudWFsIEZvcndhcmQiOnsibGJ5X3lhdyI6MSwibGJ5IjoiT2ZmIiwieWF3X3IiOjAsInBpdGNoX2RlZmVuc2l2ZV9zIjowLCJ5YXdfbHIiOmZhbHNlLCJ5YXdfbCI6MCwiZGVmZW5zaXZlX21pbnVzIjozLCJkZWZlbnNpdmUiOiJPZmYiLCJvdmVycmlkZSI6ZmFsc2UsImRlZmVuc2l2ZV9hYV9vbiI6ZmFsc2UsInlhd19kZWZlbnNpdmVfcyI6MCwidGljayI6MSwieWF3IjowLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIkFlcm9iaWMrIjp7ImxieV95YXciOjEsImxieSI6IlRpY2tzIiwieWF3X3IiOjQ3LCJwaXRjaF9kZWZlbnNpdmVfcyI6MCwieWF3X2xyIjp0cnVlLCJ5YXdfbCI6LTM1LCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6IkZsaWNrIiwib3ZlcnJpZGUiOnRydWUsImRlZmVuc2l2ZV9hYV9vbiI6ZmFsc2UsInlhd19kZWZlbnNpdmVfcyI6MCwidGljayI6MywieWF3IjowLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIkNyYXdsaW5nIjp7ImxieV95YXciOjEsImxieSI6IlRpY2tzIiwieWF3X3IiOjAsInBpdGNoX2RlZmVuc2l2ZV9zIjowLCJ5YXdfbHIiOmZhbHNlLCJ5YXdfbCI6MCwiZGVmZW5zaXZlX21pbnVzIjozLCJkZWZlbnNpdmUiOiJGbGljayIsIm92ZXJyaWRlIjp0cnVlLCJkZWZlbnNpdmVfYWFfb24iOmZhbHNlLCJ5YXdfZGVmZW5zaXZlX3MiOjAsInRpY2siOjEsInlhdyI6LTMsInlhd19tdWx0aV9zIjoxOSwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIkNlbnRlciIsIn4iXX0sIkZyZWVzdGFuZCI6eyJsYnlfeWF3IjoxLCJsYnkiOiJPZmYiLCJ5YXdfciI6MCwicGl0Y2hfZGVmZW5zaXZlX3MiOjAsInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6Ik9mZiIsIm92ZXJyaWRlIjp0cnVlLCJkZWZlbnNpdmVfYWFfb24iOnRydWUsInlhd19kZWZlbnNpdmVfcyI6MCwidGljayI6MSwieWF3IjowLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIk51bWIiOnsibGJ5X3lhdyI6MSwibGJ5IjoiVGlja3MiLCJ5YXdfciI6MzksInBpdGNoX2RlZmVuc2l2ZV9zIjowLCJ5YXdfbHIiOnRydWUsInlhd19sIjotMjEsImRlZmVuc2l2ZV9taW51cyI6MywiZGVmZW5zaXZlIjoiT2ZmIiwib3ZlcnJpZGUiOnRydWUsImRlZmVuc2l2ZV9hYV9vbiI6ZmFsc2UsInlhd19kZWZlbnNpdmVfcyI6MCwidGljayI6MiwieWF3IjowLCJ5YXdfbXVsdGlfcyI6MCwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIn4iXX0sIk1hbnVhbCBCYWNrIjp7ImxieV95YXciOjEsImxieSI6Ik9mZiIsInlhd19yIjowLCJwaXRjaF9kZWZlbnNpdmVfcyI6MCwieWF3X2xyIjpmYWxzZSwieWF3X2wiOjAsImRlZmVuc2l2ZV9taW51cyI6MywiZGVmZW5zaXZlIjoiT2ZmIiwib3ZlcnJpZGUiOmZhbHNlLCJkZWZlbnNpdmVfYWFfb24iOmZhbHNlLCJ5YXdfZGVmZW5zaXZlX3MiOjAsInRpY2siOjEsInlhdyI6MCwieWF3X211bHRpX3MiOjAsInlhd2RfZGVmZW5zaXZlX3MiOjAsInlhd19kZWZlbnNpdmUiOlsifiJdLCJkZWZlbnNpdmVfcGx1cyI6MTEsInlhd19tdWx0aSI6WyJ+Il19LCJNYW51YWwgTGVmdCI6eyJsYnlfeWF3IjoxLCJsYnkiOiJPZmYiLCJ5YXdfciI6MCwicGl0Y2hfZGVmZW5zaXZlX3MiOjAsInlhd19sciI6ZmFsc2UsInlhd19sIjowLCJkZWZlbnNpdmVfbWludXMiOjMsImRlZmVuc2l2ZSI6Ik9mZiIsIm92ZXJyaWRlIjpmYWxzZSwiZGVmZW5zaXZlX2FhX29uIjp0cnVlLCJ5YXdfZGVmZW5zaXZlX3MiOjAsInRpY2siOjEsInlhdyI6MCwieWF3X211bHRpX3MiOjAsInlhd2RfZGVmZW5zaXZlX3MiOjAsInlhd19kZWZlbnNpdmUiOlsifiJdLCJkZWZlbnNpdmVfcGx1cyI6MTEsInlhd19tdWx0aSI6WyJ+Il19LCJNYW51YWwgUmlnaHQiOnsibGJ5X3lhdyI6MSwibGJ5IjoiT2ZmIiwieWF3X3IiOjAsInBpdGNoX2RlZmVuc2l2ZV9zIjowLCJ5YXdfbHIiOmZhbHNlLCJ5YXdfbCI6MCwiZGVmZW5zaXZlX21pbnVzIjozLCJkZWZlbnNpdmUiOiJPZmYiLCJvdmVycmlkZSI6ZmFsc2UsImRlZmVuc2l2ZV9hYV9vbiI6dHJ1ZSwieWF3X2RlZmVuc2l2ZV9zIjowLCJ0aWNrIjoxLCJ5YXciOjAsInlhd19tdWx0aV9zIjowLCJ5YXdkX2RlZmVuc2l2ZV9zIjowLCJ5YXdfZGVmZW5zaXZlIjpbIn4iXSwiZGVmZW5zaXZlX3BsdXMiOjExLCJ5YXdfbXVsdGkiOlsifiJdfSwi0KFyZWVwaW5nIjp7ImxieV95YXciOjEsImxieSI6Ik9mZiIsInlhd19yIjowLCJwaXRjaF9kZWZlbnNpdmVfcyI6MCwieWF3X2xyIjpmYWxzZSwieWF3X2wiOjAsImRlZmVuc2l2ZV9taW51cyI6MywiZGVmZW5zaXZlIjoiT2ZmIiwib3ZlcnJpZGUiOmZhbHNlLCJkZWZlbnNpdmVfYWFfb24iOmZhbHNlLCJ5YXdfZGVmZW5zaXZlX3MiOjAsInRpY2siOjEsInlhdyI6MCwieWF3X211bHRpX3MiOjAsInlhd2RfZGVmZW5zaXZlX3MiOjAsInlhd19kZWZlbnNpdmUiOlsifiJdLCJkZWZlbnNpdmVfcGx1cyI6MTEsInlhd19tdWx0aSI6WyJ+Il19LCJSZWd1bGFyIjp7ImxieV95YXciOjEsImxieSI6IlRpY2tzIiwieWF3X3IiOjAsInBpdGNoX2RlZmVuc2l2ZV9zIjowLCJ5YXdfbHIiOmZhbHNlLCJ5YXdfbCI6MCwiZGVmZW5zaXZlX21pbnVzIjozLCJkZWZlbnNpdmUiOiJPZmYiLCJvdmVycmlkZSI6ZmFsc2UsImRlZmVuc2l2ZV9hYV9vbiI6ZmFsc2UsInlhd19kZWZlbnNpdmVfcyI6MCwidGljayI6MiwieWF3IjowLCJ5YXdfbXVsdGlfcyI6MjUsInlhd2RfZGVmZW5zaXZlX3MiOjAsInlhd19kZWZlbnNpdmUiOlsifiJdLCJkZWZlbnNpdmVfcGx1cyI6MTEsInlhd19tdWx0aSI6WyJ+Il19LCJBZXJvYmljIjp7ImxieV95YXciOjYwLCJsYnkiOiJUaWNrcyIsInlhd19yIjo0MCwicGl0Y2hfZGVmZW5zaXZlX3MiOjAsInlhd19sciI6dHJ1ZSwieWF3X2wiOi00MCwiZGVmZW5zaXZlX21pbnVzIjozLCJkZWZlbnNpdmUiOiJBbHdheXMiLCJvdmVycmlkZSI6dHJ1ZSwiZGVmZW5zaXZlX2FhX29uIjpmYWxzZSwieWF3X2RlZmVuc2l2ZV9zIjowLCJ0aWNrIjo4LCJ5YXciOjUsInlhd19tdWx0aV9zIjoxMSwieWF3ZF9kZWZlbnNpdmVfcyI6MCwieWF3X2RlZmVuc2l2ZSI6WyJ+Il0sImRlZmVuc2l2ZV9wbHVzIjoxMSwieWF3X211bHRpIjpbIlJhbmRvbSIsIn4iXX19LHsiYWVyb2JpYyI6IlN0YXRpYyIsImFuaW1hdGlvbnNfc2VsZWN0IjpbIkFlcm9iaWMiLCJMZWFuIiwiQWRkaXRpdmUiLCJ+Il0sImxlYW4iOiJCaWciLCJvdGhlciI6WyJBdXRvcGVlayBmaXgiLCJBbmltYXRpb24gc21vb3RoIiwifiJdLCJncm91bmQiOiJTdGF0aWMifSx7ImluZGljYXRvcmNvbDIiOiIjNjQ2NEZGRkYiLCJpbmRpY2F0b3IiOlsiU2NvcGUiLCJHcmVuYWRlIiwifiJdLCJncmFwaCI6ZmFsc2UsImluZGljYXRvcmNvbCI6IiNGRkZGRkZGRiIsImdyYXBoX2MiOiIjNzhBMDUwRkYiLCJwYW5lbHNfc2VsZWN0IjpbIkluZGljYXRvciIsIkhpdG1hcmtlciIsIkdhbWVzZW5zZSIsIn4iXX0seyJoYW5kZHJhZ192Ijp0cnVlLCJ0aGlyZHBlcnNvbiI6NjksImN1c3RvbV9zY29wZV9wb3NpdGlvbiI6OTAsImZsYXNobGlnaHQiOmZhbHNlLCJ2aWV3ZHJhZ192Ijp0cnVlLCJjdXN0b21fc2NvcGVfZmFkZSI6MTIsImN1c3RvbV9zY29wZV9vZmZzZXQiOjYwLCJ6b29tX3NjYWxlIjp0cnVlLCJ0aGlyZHBlcnNvbl9hbmltIjpmYWxzZSwibWVfc2hhcmluZ192IjpmYWxzZSwiaGFuZF96IjotMTQ4LCJoYW5kX3giOjEwOSwiY3VzdG9tX3Njb3BlIjp0cnVlLCJ3b3JsZF9tYW5hZ2VyIjpbIkhhbmRzIERyYWdnaW5nIiwiVmlldyBEcmFnZ2luZyIsIn4iXSwiYXNwZWN0cmF0aW8iOjE2NSwiZmxhc2hsaWdodF92IjpmYWxzZSwiaGFuZF9mb3YiOjU2LCJoYW5kc19kcmFnIjp0cnVlLCJjdXN0b21fc2NvcGVfYyI6IiNGRkZGRkZGRiIsIm1lX3NoYXJpbmdjb2wiOiIjRkYwMDAwRkYiLCJoYW5kX3kiOi00NzAsIm1lX3NoYXJpbmciOiJEcmFnZ2luZyIsInpvb21fb2Zmc2V0Ijo5fSx7InNvdW5kc19saXN0IjoiSW1wYWN0Iiwic291bmRzX2NoZWNrIjp0cnVlLCJvdGhlciI6WyJTb3VuZHMiLCJGb3JjZSBVcGRhdGUiLCJDbGFudGFnIiwifiJdfV0='
    lua.pui.configs = {
        db_key = 'cryonova_configs',
        names = {'Default'},
        data = {}
    }

    local config_notify = function (kind, title, message)
        if lua.notifications and lua.notifications.event_enabled('config') then
            lua.notifications.push(kind, title, message)
        end
    end

    lua.pui.configs.refresh = function ()
        local names = {'Default'}
        for name, _ in pairs(lua.pui.configs.data or {}) do
            if name ~= 'Default' then
                names[#names + 1] = name
            end
        end
        table.sort(names, function (a, b)
            if a == 'Default' then return true end
            if b == 'Default' then return false end
            return tostring(a):lower() < tostring(b):lower()
        end)
        lua.pui.configs.names = names
        if lua.pui.ui.welcome and lua.pui.ui.welcome.list then
            pcall(function () ui.update(lua.pui.ui.welcome.list, names) end)
        end
    end

    lua.pui.configs.read = function ()
        local stored = database.read(lua.pui.configs.db_key)
        lua.pui.configs.data = type(stored) == 'table' and stored or {}
        lua.pui.configs.refresh()
    end

    lua.pui.configs.write = function ()
        database.write(lua.pui.configs.db_key, lua.pui.configs.data)
        lua.pui.configs.refresh()
    end

    lua.pui.configs.selected_name = function ()
        local index = lua.pui.ui.welcome and lua.pui.ui.welcome.list and ui.get(lua.pui.ui.welcome.list) or 0
        return lua.pui.configs.names[(index or 0) + 1] or 'Default'
    end

    lua.pui.configs.input_name = function ()
        local name = lua.pui.ui.welcome and lua.pui.ui.welcome.name and ui.get(lua.pui.ui.welcome.name) or ''
        name = tostring(name):gsub('^%s+', ''):gsub('%s+$', '')
        if name == '' then
            name = lua.pui.configs.selected_name()
        end
        if name == '' or name == 'Default' then
            name = 'Config ' .. tostring(#(lua.pui.configs.names or {}) + 1)
        end
        return name
    end

    lua.pui.configs.load_selected = function ()
        local name = lua.pui.configs.selected_name()
        if name == 'Default' then
            lua.pui.ui.import(cfg)
            return
        end
        local encoded = lua.pui.configs.data[name]
        if encoded then
            lua.pui.ui.import(encoded)
        else
            config_notify('error', 'Config', 'Config not found')
        end
    end

    lua.pui.configs.save_current = function ()
        local name = lua.pui.configs.input_name()
        lua.pui.configs.data[name] = base64.encode(json.stringify(package:save()))
        lua.pui.configs.write()
        config_notify('success', 'Config', 'Saved: ' .. name)
    end

    lua.pui.configs.delete_selected = function ()
        local name = lua.pui.configs.selected_name()
        if name == 'Default' then
            config_notify('error', 'Config', 'Default config is protected')
            return
        end
        lua.pui.configs.data[name] = nil
        lua.pui.configs.write()
        config_notify('success', 'Config', 'Deleted: ' .. name)
    end

    lua.pui.configs.import_clipboard = function ()
        local name = lua.pui.configs.input_name()
        local encoded = clipboard.get()
        local ok = pcall(function ()
            package:load(json.parse(base64.decode(encoded)))
        end)
        if ok then
            lua.pui.configs.data[name] = encoded
            lua.pui.configs.write()
            config_notify('success', 'Config', 'Imported: ' .. name)
        else
            config_notify('error', 'Config', 'Import failed')
        end
    end

    lua.pui.configs.export_selected = function ()
        local name = lua.pui.configs.selected_name()
        local encoded = name == 'Default' and cfg or lua.pui.configs.data[name]
        if encoded then
            clipboard.set(encoded)
            config_notify('success', 'Config', 'Exported: ' .. name)
        else
            config_notify('error', 'Config', 'Nothing to export')
        end
    end

    lua.pui.configs.read()
    lua.pui.ui.buttons = {
        export = lua.pui.ui.group.other:button('\f<color_tabs> Export config', function ()
            lua.pui.ui.export()
        end),
        import = lua.pui.ui.group.other:button('\f<color_tabs> Import config', function ()
            lua.pui.ui.import()
        end),
        default = lua.pui.ui.group.other:button('\f<color_tabs> Default config', function ()
            lua.pui.ui.import(cfg)
        end),
        agressive = lua.pui.ui.group.other:button('\f<color_tabs> Agressive config', function ()
            lua.pui.ui.import(cfg_agr)
        end),
        beta = lua.pui.ui.group.other:button('\f<color_tabs> Beta config', function ()
            lua.pui.ui.import(cfg_beta)
        end)
    }
    for _, ref in pairs(lua.pui.ui.buttons) do
        ref:set_visible(false)
    end

    lua.sounds.set(lua.pui.ui.search, lua.sounds.contract)
    lua.sounds.set(lua.pui.ui.rage, lua.sounds.contract)
    lua.sounds.set(lua.pui.ui.animations, lua.sounds.contract)
    lua.sounds.set(lua.pui.ui.render, lua.sounds.contract)
    lua.sounds.set(lua.pui.ui.world, lua.sounds.contract)
    lua.sounds.set(lua.pui.ui.additive, lua.sounds.contract)
    lua.sounds.set(lua.pui.ui.home, lua.sounds.contract)
    lua.sounds.set(lua.pui.ui.buttons, lua.sounds.contract)

    lua.pui.ui.search.group:set_visible(false)
    lua.pui.ui.search.tab:depend({lua.pui.ui.search.group, 'Main'})

    lua.pui.ui.state:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.builder})

    for _, ref in pairs(lua.pui.ui.rage) do
        ref:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.rage})
    end
    lua.pui.ui.rage.resolver_mode:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.rage}, {lua.pui.ui.rage.resolver, true})
    lua.pui.ui.rage.shot_logs_col:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.rage}, {lua.pui.ui.rage.shot_logs, true})
    lua.pui.ui.rage.peekbot_bind:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.rage}, {lua.pui.ui.rage.peekbot, true})
    lua.pui.ui.rage.peekbot_distance:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.rage}, {lua.pui.ui.rage.peekbot, true})
    lua.pui.ui.rage.peekbot_visualize:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.rage}, {lua.pui.ui.rage.peekbot, true})

    lua.pui.ui.antiaim.manuals:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.builder})
    lua.pui.ui.antiaim.manuall:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.builder}, {lua.pui.ui.antiaim.manuals, true})
    lua.pui.ui.antiaim.manualr:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.builder}, {lua.pui.ui.antiaim.manuals, true})
    lua.pui.ui.antiaim.manualb:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.builder}, {lua.pui.ui.antiaim.manuals, true})
    lua.pui.ui.antiaim.manualf:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.builder}, {lua.pui.ui.antiaim.manuals, true})
    lua.pui.ui.antiaim.manualsr:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.builder}, {lua.pui.ui.antiaim.manuals, true})
    lua.pui.ui.antiaim.freestand:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.builder}, {lua.pui.ui.antiaim.manuals, true})

    lua.pui.ui.animations.ground:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features})
    lua.pui.ui.animations.aerobic:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.animations.animations_select, 'Aerobic'})
    lua.pui.ui.animations.ground:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.animations.animations_select, 'Ground'})
    lua.pui.ui.animations.lean:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.animations.animations_select, 'Lean'})
    lua.pui.ui.animations.other:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.animations.animations_select, 'Additive'})
    lua.pui.ui.render.indicator_style:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Indicator'})
    lua.pui.ui.render.indicatorcol:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Indicator'})
    lua.pui.ui.render.indicatorcol2:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Indicator'})
    lua.pui.ui.render.reload_indicator_color:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Reload indicator'})
    lua.pui.ui.render.lagcomp_box_color:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Lag comp box'})
    lua.pui.ui.render.lagcomp_text_color:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Lag comp box'})
    lua.pui.ui.render.visual_tuning_label:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world})
    lua.pui.ui.render.ui_scale:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world})
    lua.pui.ui.render.ui_animation_speed:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world})
    lua.pui.ui.render.grenade_visuals_label:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Grenade visuals'})
    lua.pui.ui.render.grenade_timer:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Grenade visuals'})
    lua.pui.ui.render.smoke_timer_color:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Grenade visuals'}, {lua.pui.ui.render.grenade_timer, true})
    lua.pui.ui.render.molotov_timer_color:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Grenade visuals'}, {lua.pui.ui.render.grenade_timer, true})
    lua.pui.ui.render.grenade_radius:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Grenade visuals'})
    lua.pui.ui.render.menu_visuals_label:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Menu visuals'})
    lua.pui.ui.render.animated_intro:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Menu visuals'})
    lua.pui.ui.render.menu_particles:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Menu visuals'})
    lua.pui.ui.render.particles_amount:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Menu visuals'}, {lua.pui.ui.render.menu_particles, true})
    lua.pui.ui.render.cursor_trail:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Menu visuals'})
    lua.pui.ui.render.cursor_trail_color:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Menu visuals'}, {lua.pui.ui.render.cursor_trail, true})
    lua.pui.ui.render.watermark_mode:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Watermark'})
    lua.pui.ui.render.watermark_items:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.render.panels_select, 'Watermark'}, {lua.pui.ui.render.watermark_mode, 'Mode 2'})
lua.pui.ui.world.me_sharing_v:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'Local Sharing'})
    lua.pui.ui.world.hands_drag:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'Viewmodel'})
    lua.pui.ui.world.hand_fov:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.world.hands_drag, true}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'Viewmodel'})
    lua.pui.ui.world.hand_x:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.world.hands_drag, true}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'Viewmodel'})
    lua.pui.ui.world.hand_y:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.world.hands_drag, true}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'Viewmodel'})
    lua.pui.ui.world.hand_z:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.world.hands_drag, true}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'Viewmodel'})
    lua.pui.ui.world.me_sharing:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.world.me_sharing_v, true}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'Local Sharing'})
    lua.pui.ui.world.me_sharingcol:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.world.me_sharing_v, true}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'Local Sharing'})
    lua.pui.ui.world.custom_scope:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'View changer'})
    lua.pui.ui.world.custom_scope_position:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'View changer'}, {lua.pui.ui.world.custom_scope, true})
    lua.pui.ui.world.custom_scope_offset:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'View changer'}, {lua.pui.ui.world.custom_scope, true})
    lua.pui.ui.world.custom_scope_fade:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'View changer'}, {lua.pui.ui.world.custom_scope, true})
    lua.pui.ui.world.zoom_scale:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'View changer'})
    lua.pui.ui.world.zoom_offset:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'View changer'}, {lua.pui.ui.world.zoom_scale, true})
    lua.pui.ui.world.aspectratio:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.world}, {lua.pui.ui.world.world_manager, 'View changer'})
    lua.pui.ui.additive.force_update:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Force Update'})
    lua.pui.ui.additive.sounds_check:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Sounds'})
    lua.pui.ui.additive.sounds_list:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.additive.sounds_check, true}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Sounds'})
    lua.pui.ui.additive.yandex_x:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Yandex Music'})
    lua.pui.ui.additive.yandex_y:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Yandex Music'})
    lua.pui.ui.additive.yandex_w:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Yandex Music'})
    lua.pui.ui.additive.yandex_update:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Yandex Music'})
    lua.pui.ui.additive.yandex_cover:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Yandex Music'})
    lua.pui.ui.additive.yandex_accent:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Yandex Music'})
    lua.pui.ui.additive.yandex_alpha:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Yandex Music'})
    lua.pui.ui.additive.yandex_prev:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Yandex Music'})
    lua.pui.ui.additive.yandex_play:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Yandex Music'})
    lua.pui.ui.additive.yandex_next:depend({lua.pui.ui.search.group, 'Main'}, {lua.pui.ui.search.tab, lua.pui.tabs.features}, {lua.pui.ui.additive.other, 'Yandex Music'})
    lua.pui.set_visible = function ()
        local welcome_visible = lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.welcome
        if lua.pui.ui.welcome_refs ~= nil then
            for i = 1, #lua.pui.ui.welcome_refs do
                ui.set_visible(lua.pui.ui.welcome_refs[i], welcome_visible)
            end
        end
        if lua.pui.ui.buttons ~= nil then
            for _, ref in pairs(lua.pui.ui.buttons) do
                ref:set_visible(false)
            end
        end
        if lua.pui.ui.home and lua.pui.ui.home.cryonova_label then
            lua.pui.ui.home.cryonova_label:set_visible(false)
        end
        if lua.pui.ui.world and lua.pui.ui.world.handdrag_v then
            lua.pui.ui.world.handdrag_v:set_visible(false)
        end

        
        if lua.pui.ui.world and lua.pui.ui.world.viewdrag_v then
            lua.pui.ui.world.viewdrag_v:set_visible(false)
        end
        local selected_state = lua.pui.ui.state:get()

        for i, name in pairs(lua.pui.condition_names) do
            local enabled = name == selected_state
            local overriden = i == 1 or lua.pui.ui.conditions[name].override:get()
            local lby = lua.pui.ui.conditions[name].lby:get() ~= 'Off'
            local lr = lua.pui.ui.conditions[name].yaw_lr:get()
            local mod_s = lua.pui.ui.conditions[name].yaw_multi
            local def = lua.pui.ui.conditions[name].defensive:get() ~= 'Off'
            local defaa = lua.pui.ui.conditions[name].defensive_aa_on:get()
            local def_s = lua.pui.ui.conditions[name].yaw_defensive
            lua.pui.ui.conditions[name].override:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and i > 1)
            lua.pui.ui.conditions[name].yaw:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden)
            lua.pui.ui.conditions[name].yaw_lr:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden)
            lua.pui.ui.conditions[name].yaw_l:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden and lr)
            lua.pui.ui.conditions[name].yaw_r:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden and lr)
            lua.pui.ui.conditions[name].yaw_multi:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden)
            lua.pui.ui.conditions[name].yaw_multi_s:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden and (mod_s:get('Offset') or mod_s:get('Center') or mod_s:get('Random') or mod_s:get('Spray')))
            lua.pui.ui.conditions[name].lby:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden)
            lua.pui.ui.conditions[name].lby_yaw:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden and lby)
            lua.pui.ui.conditions[name].tick:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden)
            lua.pui.ui.conditions[name].defensive:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden)
            lua.pui.ui.conditions[name].defensive_minus:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden and def)
            lua.pui.ui.conditions[name].defensive_plus:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden and def)
            lua.pui.ui.conditions[name].defensive_aa_on:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden and def)
            lua.pui.ui.conditions[name].pitch_defensive_c:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden and def and defaa)
            lua.pui.ui.conditions[name].pitch_defensive_s:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden and def and defaa)
            lua.pui.ui.conditions[name].yawd_defensive_s:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden and def and defaa)
            lua.pui.ui.conditions[name].yaw_defensive:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden and def and defaa)
            lua.pui.ui.conditions[name].yaw_defensive_s:set_visible(lua.pui.ui.search.group:get() == 'Main' and lua.pui.ui.search.tab:get() == lua.pui.tabs.builder and enabled and overriden and def and defaa and (def_s:get('Offset') or def_s:get('Center') or def_s:get('Random') or def_s:get('Spin')))
        end
    end
    client.set_event_callback('paint_ui', lua.pui.set_visible)
end
--#endregion

--#region lua.reference
lua.reference = {} do
    lua.reference.init = function ()
		lua.reference.rage = {
			binds = {
				weapon_type = pui.reference('rage', 'weapon type', 'weapon type'),
				enabled = { pui.reference('rage', 'aimbot', 'enabled') },
				stop = { pui.reference('rage', 'aimbot', 'quick stop') },
				minimum_damage = pui.reference('rage', 'aimbot', 'minimum damage'),
				minimum_damage_override = {pui.reference('rage', 'aimbot', 'minimum damage override')},
				minimum_hitchance = pui.reference('rage', 'aimbot', 'minimum hit chance'),
				double_tap = {pui.reference('rage', 'aimbot', 'double tap')},
                body_aim = pui.reference('rage', 'aimbot', 'force body aim'),
                safe_point = pui.reference('rage', 'aimbot', 'force safe point'),
				double_tap_fl = pui.reference('rage', 'aimbot', 'double tap fake lag limit'),
				ps = { pui.reference('misc', 'miscellaneous', 'ping spike') },
				quickpeek = {pui.reference('rage', 'other', 'quick peek assist')},
				quickpeekm = {pui.reference('rage', 'other', 'quick peek assist mode')},
                fakeduck = pui.reference('rage', 'other', 'duck peek assist'),
				on_shot_anti_aim = {pui.reference('aa', 'other', 'on shot anti-aim')},
				usercmd = pui.reference('misc', 'settings', 'sv_maxusrcmdprocessticks2')
			}
		}
        do
            local hitchance_names = {string.char(10) .. ' hotkey-hitchance', '\\\\n hotkey-hitchance', 'hotkey-hitchance', 'minimum hit chance override', 'hit chance override', 'override hit chance', 'override hitchance'}
            for i = 1, #hitchance_names do
                local ok, ref_a, ref_b, ref_c = pcall(pui.reference, 'rage', 'aimbot', hitchance_names[i])
                if ok and ref_a ~= nil then
                    lua.reference.rage.binds.minimum_hitchance_override = {ref_a, ref_b, ref_c}
                    break
                end
            end
        end
		 lua.reference.antiaim = {
			angles = {
				enabled = pui.reference('aa', 'anti-aimbot angles', 'enabled'),
				pitch = { pui.reference('aa', 'anti-aimbot angles', 'pitch') },
				roll = pui.reference('aa', 'anti-aimbot angles', 'roll'),
				yaw_base = pui.reference('aa', 'anti-aimbot angles', 'yaw base'),
				yaw = { pui.reference('aa', 'anti-aimbot angles', 'yaw') },
				freestanding_body_yaw = pui.reference('aa', 'anti-aimbot angles', 'freestanding body yaw'),
				edge_yaw = pui.reference('aa', 'anti-aimbot angles', 'edge yaw'),
				yaw_jitter = { pui.reference('aa', 'anti-aimbot angles', 'yaw jitter') },
				desync = { pui.reference('aa', 'anti-aimbot angles', 'body yaw') },
				freestanding = pui.reference('aa', 'anti-aimbot angles', 'freestanding'),
				roll_aa = pui.reference('aa', 'anti-aimbot angles', 'roll')
			},
			fakelag = {
				on = {pui.reference('aa', 'fake lag', 'enabled')},
				amount = pui.reference('aa', 'fake lag', 'amount'),
				variance = pui.reference('aa', 'fake lag', 'variance'),
				limit = pui.reference('aa', 'fake lag', 'limit')
			},
			other = {
				slide = {pui.reference('aa','other','slow motion')},
				slow_motion = {pui.reference('aa', 'other', 'slow motion')},
				fake_peek = {pui.reference('aa', 'other', 'fake peek')},
				leg_movement = pui.reference('aa', 'other', 'leg movement')
			}
		}
		lua.reference.visuals = {
			effects = {
				thirdperson = { pui.reference('visuals', 'effects', 'force third person (alive)') },
                scope = pui.reference('visuals', 'effects', 'remove scope overlay'),
				dpi = pui.reference('misc', 'settings', 'dpi scale'),
				clrmenu = pui.reference('misc', 'settings', 'menu color'),
				output = pui.reference('misc', 'miscellaneous', 'draw console output'),
				name = { pui.reference('visuals', 'player esp', 'name') },
                ping = {pui.reference('misc', 'miscellaneous', 'ping spike')},
				fov = pui.reference('misc', 'miscellaneous', 'override fov'),
                clantag = pui.reference('MISC', 'Miscellaneous', 'Clan tag spammer'),
				zfov = pui.reference('misc', 'miscellaneous', 'override zoom fov')
			}
		}
	end
    lua.reference.hide = function(boolean)
		pui.traverse(lua.reference.antiaim.angles, function (r, path)
			r:set_visible(boolean)
		end)
        pui.traverse(lua.reference.antiaim.fakelag, function (r, path)
			r:set_visible(not boolean and lua.pui.ui.search.group:get() == 'Other')
		end)
        pui.traverse(lua.reference.antiaim.other, function (r, path)
			r:set_visible(not boolean and lua.pui.ui.search.group:get() == 'Other')
		end)
        lua.reference.rage.binds.on_shot_anti_aim[1]:set_visible(lua.pui.ui.search.group:get() == 'Other')
    end
    defer(lua.reference.hide)
    defer(function ()
        pui.traverse(lua.reference.rage, function (ref)
            ref:override()
            ref:set_enabled(true)
            if ref.hotkey then ref.hotkey:set_enabled(true) end
        end)
        pui.traverse(lua.reference.antiaim, function (ref)
            ref:override()
            ref:set_enabled(true)
            if ref.hotkey then ref.hotkey:set_enabled(true) end
        end)
        pui.traverse(lua.reference.visuals, function (ref)
            ref:override()
            ref:set_enabled(true)
            if ref.hotkey then ref.hotkey:set_enabled(true) end
        end)
        lua.reference.rage.binds.usercmd:set_visible(false)
    end)
end
lua.reference.init()
--#endregion

--#region lua.rage
lua.rage = {} do
    local hitgroup_names = {'generic', 'head', 'chest', 'stomach', 'left arm', 'right arm', 'left leg', 'right leg', 'neck', '?', 'gear'}
    local hitbox_ids = {1, 2, 3, 4, 5, 6, 7}
    local hitbox_names = {'head', 'chest', 'stomach', 'left_arm', 'right_arm', 'left_leg', 'right_leg'}

    local function rage_enabled(ref)
        return lua.pui.ui.rage and lua.pui.ui.rage[ref] and lua.pui.ui.rage[ref]:get()
    end

    local function rage_log(r, g, b, text)
        if client.color_log then
            client.color_log(r, g, b, '[Cryonova Rage] ' .. text)
        else
            print('[Cryonova Rage] ' .. text)
        end
    end
    local weapon_to_verb = { knife = 'knifed', hegrenade = 'naded', inferno = 'burned' }

    local function num_format(n)
        local mod = n % 10
        if mod == 1 and n ~= 11 then return n .. 'st' end
        if mod == 2 and n ~= 12 then return n .. 'nd' end
        if mod == 3 and n ~= 13 then return n .. 'rd' end
        return n .. 'th'
    end

    local function lower_name(ent)
        local name = entity.get_player_name(ent) or 'unknown'
        return string.lower(name)
    end

    local function table_flags(data)
        return table.concat({
            data.self_choke > 1 and 1 or 0,
            data.velocity_modifier < 1.00 and 1 or 0,
            data.boosted and 1 or 0
        })
    end

    local function get_safety(shot, target)
        if not shot.boosted then
            return -1
        end

        local plist_safety = plist.get(target, 'Override safe point')
        local force_safe = false
        if lua.reference.rage.binds.safe_point then
            local ok, value = pcall(function() return lua.reference.rage.binds.safe_point:get() end)
            force_safe = ok and value or false
        end
        if plist_safety == 'Off' or not force_safe and plist_safety ~= 'On' then
            return 0
        end

        return force_safe and 2 or 1
    end

    lua.rage.logs = { shots = {}, impacts = {}, notify = {} }
    local function notify_color()
        local r, g, b, a = lua.pui.ui.rage.shot_logs_col:get()
        return r, g, b, a or 255
    end

    local function notify_push(kind, text)
        local queue = lua.rage.logs.notify
        queue[#queue + 1] = {
            kind = kind,
            text = text,
            start = globals.realtime(),
            duration = 4.0,
            alpha = 0
        }
    end

    lua.rage.logs_paint = function()
        local queue = lua.rage.logs.notify
        if #queue == 0 then return end

        local screen_x, screen_y = client.screen_size()
        local now = globals.realtime()
        local base_y = screen_y - 140

        for i = #queue, 1, -1 do
            local item = queue[i]
            local elapsed = now - item.start
            local left = item.duration - elapsed
            if left <= 0 then
                table.remove(queue, i)
            else
                local fade = mathematic.clamp(math.min(elapsed / 0.2, left / 0.25), 0, 1)
                item.alpha = fade
                local text_w = renderer.measure_text('c', item.text)
                local w = text_w + 42
                local h = 18
                local x = screen_x / 2 - w / 2
                local y = base_y - ((#queue - i) * 22) + (1 - fade) * 8
                local cr, cg, cb, ca = notify_color()
                local progress = mathematic.clamp(left / item.duration, 0, 1)
                local bg_a = math.floor(mathematic.clamp(ca or 255, 0, 255) * 0.63 * fade)
                local text_a = math.floor(255 * fade)

                render.round_rect(x, y, w, h, 4, 13, 13, 13, bg_a)
                renderer.text(x + w / 2 - 6, y + h / 2, 255, 255, 255, text_a, 'c', 0, item.text)
                renderer.circle_outline(x + w - 13, y + h / 2, 13, 13, 13, 255, 7, 0, 1, 4)
                renderer.circle_outline(x + w - 13, y + h / 2, 255, 255, 255, 255, 6, 0, progress, 2)
            end
        end
    end

    local function ticks(time)
        local interval = globals.tickinterval()
        if not time or not interval or interval <= 0 or time ~= time then return nil end
        local tick = math.floor(time / interval + 0.5)
        if tick ~= tick or tick < 0 or tick > 2147483647 then return nil end
        return tick
    end

    local function calc_lerp_time()
        local updaterate = cvar.cl_updaterate:get_float()
        local min_updaterate = cvar.sv_minupdaterate:get_float()
        local max_updaterate = cvar.sv_maxupdaterate:get_float()
        local interp_ratio = cvar.cl_interp_ratio:get_float()
        local min_ratio = cvar.sv_client_min_interp_ratio:get_float()
        local max_ratio = cvar.sv_client_max_interp_ratio:get_float()
        local interp = cvar.cl_interp:get_float()

        updaterate = mathematic.clamp(updaterate, min_updaterate, max_updaterate)
        if not updaterate or updaterate <= 0 then return interp or 0 end
        interp_ratio = mathematic.clamp(interp_ratio, min_ratio, max_ratio)
        return mathematic.clamp(interp_ratio / updaterate, interp or 0, 1)
    end

    local function angle_to_vector(pitch, yaw)
        local pitch_rad = math.rad(pitch)
        local yaw_rad = math.rad(yaw)
        return math.cos(pitch_rad) * math.cos(yaw_rad), math.cos(pitch_rad) * math.sin(yaw_rad), -math.sin(pitch_rad)
    end

    local function set_movement(cmd, desired_pos)
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return end
        local pitch, yaw = vector(entity.get_origin(me)):to(desired_pos):angles()
        if type(pitch) == 'table' then
            yaw = pitch.y
        end
        cmd.in_forward = 1
        cmd.in_back = 0
        cmd.in_moveleft = 0
        cmd.in_moveright = 0
        cmd.in_speed = 0
        cmd.forwardmove = 800
        cmd.sidemove = 0
        cmd.move_yaw = yaw
    end

    if not renderer.circle_3d then
        renderer.circle_3d = function(pos, radius, start_at, percentage, segment, filled, r, g, b, a)
            local old_x, old_y
            local end_at = math.floor(percentage * 360)
            local step = (end_at - start_at) / segment
            for rot = start_at, end_at, step do
                local rad = math.rad(rot)
                local px = radius * math.cos(rad) + pos.x
                local py = radius * math.sin(rad) + pos.y
                local sx, sy = renderer.world_to_screen(px, py, pos.z)
                local cx, cy = renderer.world_to_screen(pos.x, pos.y, pos.z)
                if sx and sy and old_x and old_y then
                    if filled and cx and cy then
                        renderer.triangle(sx, sy, old_x, old_y, cx, cy, r, g, b, a)
                    else
                        renderer.line(sx, sy, old_x, old_y, r, g, b, a)
                    end
                end
                old_x, old_y = sx, sy
            end
        end
    end

    lua.rage.resolver = { misses = {}, side = {}, defensive_data = {}, sim = {} }

    lua.rage.resolver.apply = function()
        if not rage_enabled('resolver') then
            for _, enemy in ipairs(entity.get_players(true)) do
                plist.set(enemy, 'Force body yaw', false)
            end
            return
        end

        for _, enemy in ipairs(entity.get_players(true)) do
            local miss_count = lua.rage.resolver.misses[enemy] or 0
            local side = miss_count == 1 and -1 or miss_count == 2 and 1 or 0
            if side == 0 then
                plist.set(enemy, 'Force body yaw', false)
            else
                local value = lua.pui.ui.rage.resolver_mode:get() == 'Default' and (side * 58) or (side * 60)
                plist.set(enemy, 'Force body yaw', true)
                plist.set(enemy, 'Force body yaw value', value)
            end
        end
    end

    lua.rage.resolver.defensive = function()
        if not rage_enabled('defensive_aa_resolver') then
            for _, enemy in ipairs(entity.get_players(true)) do
                plist.set(enemy, 'force pitch', false)
            end
            return
        end

        for _, enemy in ipairs(entity.get_players(true)) do
            local data = lua.rage.resolver.defensive_data[enemy]
            if data == nil then
                data = { last_sim = 0, defensive_until = 0, pitch_vl = 0, timer = 0 }
                lua.rage.resolver.defensive_data[enemy] = data
            end

            local sim_time = ticks(entity.get_prop(enemy, 'm_flSimulationTime'))
            local sim_diff = sim_time - data.last_sim
            if sim_diff < 0 then
                data.defensive_until = globals.tickcount() + math.abs(sim_diff) - ticks(client.latency())
            end
            data.last_sim = sim_time

            local pitch = entity.get_prop(enemy, 'm_angEyeAngles[0]') or 0
            if data.defensive_until > globals.tickcount() then
                if pitch < 70 then
                    data.pitch_vl = data.pitch_vl + 1
                    data.timer = globals.realtime() + 5
                end
            elseif data.timer - globals.realtime() < 0 then
                data.pitch_vl = 0
                data.timer = 0
            end

            plist.set(enemy, 'force pitch', data.pitch_vl > 3)
            if data.pitch_vl > 3 then
                plist.set(enemy, 'force pitch value', 89)
            end
        end
    end

    lua.rage.logs_fire = function(e)
        if not rage_enabled('shot_logs') or not e or e.id == nil then return end
        local me = entity.get_local_player()
        lua.rage.logs.shots[e.id] = {
            original = e,
            time = globals.realtime(),
            self_choke = globals.chokedcommands(),
            boosted = e.boosted,
            safety = get_safety(e, e.target),
            velocity_modifier = me and (entity.get_prop(me, 'm_flVelocityModifier') or 1) or 1,
            total_hits = me and (entity.get_prop(me, 'm_totalHitsOnServer') or 0) or 0,
            history = globals.tickcount() - (e.tick or globals.tickcount()),
            lagcomp = e.teleported == true,
            damage = e.damage or 0,
            hit_chance = math.floor((e.hit_chance or 0) + 0.5),
            hitgroup = e.hitgroup or 0
        }
    end

    lua.rage.logs_impact = function(e)
        if not rage_enabled('shot_logs') then return end
        local me = entity.get_local_player()
        if client.userid_to_entindex(e.userid) ~= me then return end
        local impacts = lua.rage.logs.impacts
        if #impacts > 150 then
            lua.rage.logs.impacts = {}
            impacts = lua.rage.logs.impacts
        end
        impacts[#impacts + 1] = { tick = globals.tickcount(), eye = vector(client.eye_position()), shot = vector(e.x, e.y, e.z) }
    end

    lua.rage.logs_hit = function(e)
        if not rage_enabled('shot_logs') then return end
        local pre = lua.rage.logs.shots[e.id]
        local shot_id = num_format(((e.id or 0) % 15) + 1)
        local group = hitgroup_names[(e.hitgroup or 0) + 1] or '?'
        local target_name = lower_name(e.target)
        local hit_chance = pre and pre.hit_chance or math.floor((e.hit_chance or 0) + 0.5)
        local safety = pre and pre.safety or -1
        local history = pre and pre.history or (globals.tickcount() - (e.tick or globals.tickcount()))
        local flags = pre and table_flags(pre) or '000'
        local mismatch = ''

        if pre then
            local aimed_group = hitgroup_names[(pre.hitgroup or 0) + 1] or '?'
            local mismatch_parts = {}
            if (e.damage or 0) ~= pre.damage then
                mismatch_parts[#mismatch_parts + 1] = 'dmg: ' .. pre.damage
            end
            if group ~= aimed_group then
                mismatch_parts[#mismatch_parts + 1] = 'hitgroup: ' .. aimed_group
            end
            if #mismatch_parts > 0 then
                mismatch = ' | mismatch: [ ' .. table.concat(mismatch_parts, ' | ') .. ' ]'
            end
        end
        local aimed_group = pre and (hitgroup_names[(pre.hitgroup or 0) + 1] or '?') or group
        local damage = e.damage or 0
        local wanted_damage = pre and pre.damage or damage
        local lagcomp = pre and pre.lagcomp or false
        local message = string.format("hit %s for %d [%d] in the %s [%s] [hc: %d%%, bt: %d, lc: %s]", string.upper(target_name), damage, wanted_damage, group, aimed_group, hit_chance, history, tostring(lagcomp))
        notify_push('hit', message)
        rage_log(255, 255, 255, message)
        if e.id ~= nil then
            lua.rage.logs.shots[e.id] = nil
        end
    end

    lua.rage.logs_miss = function(e)
        if not rage_enabled('shot_logs') then return end
        local pre = lua.rage.logs.shots[e.id]
        local shot_id = num_format(((e.id or 0) % 15) + 1)
        local group = hitgroup_names[(e.hitgroup or 0) + 1] or '?'
        local target_name = lower_name(e.target)
        local hit_chance = pre and pre.hit_chance or math.floor((e.hit_chance or 0) + 0.5)
        local safety = pre and pre.safety or -1
        local history = pre and pre.history or (globals.tickcount() - (e.tick or globals.tickcount()))
        local flags = pre and table_flags(pre) or '000'
        local reason = e.reason or '?'
        local detail = reason

        if pre and reason == '?' then
            local me = entity.get_local_player()
            local total_hits = me and (entity.get_prop(me, 'm_totalHitsOnServer') or 0) or 0
            detail = total_hits ~= pre.total_hits and 'damage rejection' or 'unknown [angle: ? | ?]'
        elseif reason == 'prediction error' or reason == 'unregistered shot' then
            detail = 'prediction error' .. (reason == 'unregistered shot' and ' [unregistered shot]' or '')
        end
        local aimed_group = pre and (hitgroup_names[(pre.hitgroup or 0) + 1] or '?') or group
        local wanted_damage = pre and pre.damage or 0
        local lagcomp = pre and pre.lagcomp or false
        local message = string.format("missed %s's %s due to %s [dmg: %d, bt: %d, lc: %s]", string.upper(target_name), aimed_group, detail, wanted_damage, history, tostring(lagcomp))
        notify_push('miss', message)
        rage_log(255, 103, 103, message)
        if e.id ~= nil then
            lua.rage.logs.shots[e.id] = nil
        end
    end

    lua.rage.logs_hurt = function(e)
        if not rage_enabled('shot_logs') then return end
        local attacker = client.userid_to_entindex(e.attacker)
        if attacker ~= entity.get_local_player() then return end
        local group = hitgroup_names[(e.hitgroup or 0) + 1] or '?'
        if group == 'generic' and weapon_to_verb[e.weapon] ~= nil then
            local target = client.userid_to_entindex(e.userid)
            rage_log(255, 255, 255, string.format('%s %s for %d damage (%d remaining)', weapon_to_verb[e.weapon], lower_name(target), e.dmg_health or 0, e.health or 0))
        end
    end

    lua.rage.peekbot = {
        start_position = vector(0, 0, 0),
        cache_eye_left = vector(0, 0, 0),
        cache_eye_right = vector(0, 0, 0),
        set_location = true,
        shot_fired = false,
        reload_timer = 0,
        reached_max_distance = false,
        should_return = false,
        left_trace_active = false,
        right_trace_active = false,
        peekbot_active = false,
        calculate_wall_dist_left = 0,
        calculate_wall_dist_right = 0,
        lerp_distance = 0,
        targets = {}
    }

    lua.rage.peekbot.return_to_start = function(cmd)
        local data = lua.rage.peekbot
        if not data.should_return then return end
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return end
        local origin = vector(entity.get_origin(me))
        if data.start_position:dist2d(origin) > 1 then
            if not client.key_state(0x57) and not client.key_state(0x41) and not client.key_state(0x53) and not client.key_state(0x44) and not lua.reference.rage.binds.quickpeek[1]:get_hotkey() then
                set_movement(cmd, data.start_position)
            end
        else
            data.should_return = false
            data.shot_fired = false
            data.reached_max_distance = false
        end
    end

    lua.rage.peekbot.run = function(cmd)
        local data = lua.rage.peekbot
        local enabled = rage_enabled('peekbot')
        data.lerp_distance = mathematic.lerp(data.lerp_distance, enabled and lua.pui.ui.rage.peekbot_distance:get() or 0, globals.frametime() * 15)
        if not enabled then
            lua.reference.antiaim.angles.freestanding:set(false)
            return
        end

        if not lua.pui.ui.rage.peekbot_bind:get() then
            data.set_location = true
            data.lerp_distance = 0
            if rage_enabled('peekbot_freestanding') then
                lua.reference.antiaim.angles.freestanding:set(false)
            end
            return
        end

        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return end
        local eye = vector(client.eye_position())
        local origin = vector(entity.get_origin(me))

        if data.set_location then
            data.start_position = origin
            data.set_location = false
        end

        lua.rage.peekbot.return_to_start(cmd)

        local target = client.current_threat()
        if not target or entity.is_dormant(target) then return end
        data.targets[target] = data.targets[target] or {}

        local target_origin = vector(entity.get_origin(target))
        local enemy_ang = math.deg(math.atan2(eye.y - target_origin.y, eye.x - target_origin.x))
        local left_x, left_y = angle_to_vector(0, enemy_ang - 90)
        local right_x, right_y = angle_to_vector(0, enemy_ang + 90)
        local distance = lua.pui.ui.rage.peekbot_distance:get()

        local eye_left = vector(left_x * math.max(0, data.lerp_distance - data.calculate_wall_dist_left) + eye.x, left_y * math.max(0, data.lerp_distance - data.calculate_wall_dist_left) + eye.y, eye.z)
        local eye_right = vector(right_x * math.max(0, data.lerp_distance - data.calculate_wall_dist_right) + eye.x, right_y * math.max(0, data.lerp_distance - data.calculate_wall_dist_right) + eye.y, eye.z)
        local eye_left_ext = vector(left_x * data.lerp_distance * 1.2 + eye.x, left_y * data.lerp_distance * 1.2 + eye.y, eye.z)
        local eye_right_ext = vector(right_x * data.lerp_distance * 1.2 + eye.x, right_y * data.lerp_distance * 1.2 + eye.y, eye.z)

        data.cache_eye_left = eye_left
        data.cache_eye_right = eye_right
        data.left_trace_active = false
        data.right_trace_active = false

        for i, id in ipairs(hitbox_ids) do
            local hitbox = vector(entity.hitbox_position(target, id))
            local _, damage_left = client.trace_bullet(me, eye_left.x, eye_left.y, eye_left.z, hitbox.x, hitbox.y, hitbox.z, false)
            local _, damage_right = client.trace_bullet(me, eye_right.x, eye_right.y, eye_right.z, hitbox.x, hitbox.y, hitbox.z, false)
            local trace_wall_left = client.trace_line(0, eye_left.x, eye_left.y, eye_left.z, eye_left_ext.x, eye_left_ext.y, eye_left_ext.z)
            local trace_wall_right = client.trace_line(0, eye_right.x, eye_right.y, eye_right.z, eye_right_ext.x, eye_right_ext.y, eye_right_ext.z)

            data.calculate_wall_dist_left = trace_wall_left ~= 1 and (1 - trace_wall_left) * (distance / (distance / 100)) or 0
            data.calculate_wall_dist_right = trace_wall_right ~= 1 and (1 - trace_wall_right) * (distance / (distance / 100)) or 0

            local left = damage_left and damage_left > 0
            local right = damage_right and damage_right > 0
            data.targets[target][hitbox_names[i]] = left or right

            if left and not data.right_trace_active then
                data.left_trace_active = true
            end
            if right and not data.left_trace_active then
                data.right_trace_active = true
            end
        end

        local visible = false
        for _, name in ipairs(hitbox_names) do
            visible = visible or data.targets[target][name]
        end
        data.peekbot_active = visible

        if data.start_position:dist2d(origin) > distance then
            data.reached_max_distance = true
        end

        if data.peekbot_active and not data.shot_fired and data.reload_timer < globals.realtime() and not data.reached_max_distance then
            if data.left_trace_active then
                set_movement(cmd, eye_left)
            elseif data.right_trace_active then
                set_movement(cmd, eye_right)
            end
        else
            data.should_return = true
        end

        if rage_enabled('peekbot_freestanding') then
            lua.reference.antiaim.angles.freestanding.hotkey:set('always on')
            lua.reference.antiaim.angles.freestanding:set(true)
        end
    end

    lua.rage.resolver.render_data = { target = nil, x = nil, y = nil }
    lua.rage.resolver.render = function()
        if not rage_enabled('resolver') then return end
        local target = client.current_threat()
        if not target or target == 0 or entity.is_dormant(target) then
            lua.rage.resolver.render_data.target = nil
            return
        end

        local x, y, z = entity.get_origin(target)
        if x == nil then return end
        z = z + 96

        local sx, sy = renderer.world_to_screen(x, y, z)
        if sx == nil or sy == nil then return end

        local data = lua.rage.resolver.render_data
        if data.target ~= target or data.x == nil or data.y == nil then
            data.target, data.x, data.y = target, sx, sy
        else
            data.x = mathematic.lerp(data.x, sx, 0.18)
            data.y = mathematic.lerp(data.y, sy, 0.18)
        end

        local text = 'Resolve'
        local width = renderer.measure_text(nil, text)
        renderer.text(data.x - width / 2, data.y - 22, 120, 255, 120, 255, nil, 0, text)
    end
    lua.rage.peekbot.render = function()
        local data = lua.rage.peekbot
        local target = client.current_threat()
        if not rage_enabled('peekbot') or not lua.pui.ui.rage.peekbot_bind:get() or not rage_enabled('peekbot_visualize') or not target or entity.is_dormant(target) then return end
        local me = entity.get_local_player()
        if not me then return end
        local origin = vector(entity.get_origin(me))
        local target_origin = vector(entity.get_origin(target))
        renderer.circle_3d(vector(data.start_position.x, data.start_position.y, origin.z), 10, 0, 1, 48, false, data.shot_fired and 149 or 255, data.shot_fired and 186 or 255, 255, 255)
        renderer.circle_3d(vector(data.cache_eye_left.x, data.cache_eye_left.y, origin.z), 13, 0, 1, 48, false, 149, data.left_trace_active and 255 or 186, data.left_trace_active and 162 or 255, data.right_trace_active and 100 or 255)
        renderer.circle_3d(vector(data.cache_eye_right.x, data.cache_eye_right.y, origin.z), 13, 0, 1, 48, false, 149, data.right_trace_active and 255 or 186, data.right_trace_active and 162 or 255, data.left_trace_active and 100 or 255)
        renderer.circle_3d(vector(target_origin.x, target_origin.y, target_origin.z), 13, 0, 1, 48, false, 149, 255, 162, 255)
    end

    lua.rage.backtrack = { simtime_backup = nil }
    lua.rage.backtrack.run = function(cmd)
        if not rage_enabled('backtrack_exploit') then return end
        if cmd == nil then return end
        local target = client.current_threat()
        if not target or target == 0 or entity.is_dormant(target) then return end
        local vx, vy = entity.get_prop(target, 'm_vecVelocity')
        local speed = math.sqrt((vx or 0) ^ 2 + (vy or 0) ^ 2)
        if speed < 5 then return end
        local simtime = entity.get_prop(target, 'm_flSimulationTime')
        if not simtime or simtime <= 0 or simtime ~= simtime then return end
        local delta = globals.curtime() - simtime
        local latency = client.latency() or 0
        if delta <= latency or delta <= 0.2 or delta > 0.6 or cvar.cl_lagcompensation:get_int() ~= 1 then return end

        local tick = ticks(simtime + calc_lerp_time())
        if tick == nil then return end
        pcall(function() cmd.tickcount = tick end)
    end

    lua.rage.dt_last_tick = function()
        if not rage_enabled('dt_last_tick') then return end
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return end
        local tickbase = entity.get_prop(me, 'm_nTickBase') - globals.tickcount()
        local doubletap = lua.reference.rage.binds.double_tap[1]:get() and lua.reference.rage.binds.double_tap[1].hotkey:get() and not lua.reference.rage.binds.fakeduck:get()
        local weapon_ent = entity.get_player_weapon(me)
        if not weapon_ent then return end
        local weapon_idx = entity.get_prop(weapon_ent, 'm_iItemDefinitionIndex')
        local last_shot = entity.get_prop(weapon_ent, 'm_fLastShotTime')
        if not weapon_idx or not last_shot then return end
        local single_fire = weapon_idx == 40 or weapon_idx == 9 or weapon_idx == 64 or weapon_idx == 27 or weapon_idx == 29 or weapon_idx == 35
        local attack = globals.curtime() - last_shot <= (single_fire and 1.50 or 0.50)
        if tickbase > 0 and doubletap then
            lua.reference.rage.binds.enabled[1]:override(attack)
        else
            lua.reference.rage.binds.enabled[1]:override()
        end
    end

    lua.rage.force_body = function()
        if not rage_enabled('force_body') then
            for _, enemy in ipairs(entity.get_players(true)) do
                plist.set(enemy, 'Override prefer body aim', '-')
            end
            return
        end
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return end
        local weapon_ent = entity.get_player_weapon(me)
        if not weapon_ent then return end
        local weapon_idx = entity.get_prop(weapon_ent, 'm_iItemDefinitionIndex')
        local weapon = weapon_idx and weapons[weapon_idx]
        if not weapon then return end
        local local_origin = vector(entity.get_prop(me, 'm_vecAbsOrigin'))
        for _, enemy in ipairs(entity.get_players(true)) do
            local enemy_origin = vector(entity.get_prop(enemy, 'm_vecOrigin'))
            local distance = local_origin:dist(enemy_origin)
            local health = entity.get_prop(enemy, 'm_iHealth') or 0
            local armor = entity.get_prop(enemy, 'm_ArmorValue') or 0
            local damage = (weapon.damage * math.pow(weapon.range_modifier, distance * 0.002)) * 1.25
            local armor_damage = damage * (weapon.armor_ratio * 0.5)
            if damage - armor_damage * 0.5 > armor then
                armor_damage = damage - (armor / 0.5)
            end
            plist.set(enemy, 'Override prefer body aim', armor_damage >= health and 'Force' or '-')
        end
    end

    lua.pui.ui.rage.peekbot_bind:set('On hotkey')
    lua.pui.ui.additive.yandex_cover:set(true)

    client.set_event_callback('aim_hit', function(e)
        lua.rage.resolver.misses[e.target] = entity.get_prop(e.target, 'm_iHealth') < 1 and 0 or lua.rage.resolver.misses[e.target]
        lua.rage.logs_hit(e)
    end)

    client.set_event_callback('aim_miss', function(e)
        if rage_enabled('resolver') and e.reason == '?' then
            lua.rage.resolver.misses[e.target] = ((lua.rage.resolver.misses[e.target] or 0) + 1) % 3
        end
        lua.rage.logs_miss(e)
    end)

    client.set_event_callback('aim_fire', function(e)
        lua.rage.logs_fire(e)
        lua.rage.peekbot.shot_fired = true
        lua.rage.peekbot.reload_timer = globals.realtime() + 1.23
    end)

    client.set_event_callback('bullet_impact', lua.rage.logs_impact)
    client.set_event_callback('player_hurt', lua.rage.logs_hurt)
    client.set_event_callback('paint', lua.rage.peekbot.render)
    client.set_event_callback('paint', lua.rage.resolver.render)
    client.set_event_callback('paint', lua.rage.logs_paint)
    client.set_event_callback('setup_command', function(cmd)
        lua.rage.peekbot.run(cmd)
        lua.rage.backtrack.run(cmd)
        lua.rage.dt_last_tick()
        lua.rage.force_body()
    end)
    client.set_event_callback('net_update_end', function()
        lua.rage.resolver.apply()
        lua.rage.resolver.defensive()
    end)
end
--#endregion
--#region lua.keybinds 
lua.keybinds = {}
lua.keybinds.add = function(name, ref, gradient_fn)
    lua.keybinds.binds[#lua.keybinds.binds + 1] = { name = string.sub(name, 1, 2), full_name = name, ref = ref, color = disabled_color, alpha = 0, gradient_progress = 0, gradient_fn = gradient_fn }
end
lua.keybinds.text = function(x, y, r, g, b, a, text, alpha)
    if alpha == nil then
        alpha = 1
    end

    if alpha <= 0 then
        return
    end

    local text_wh = vector(render.measure_text(nil, text))

    render.text(x + 10, y, r, g, b, a, nil, nil, '~ '..text)

    lua.keybinds.y = lua.keybinds.y + text_wh.y * alpha
end
lua.keybinds.binds = {}
lua.keybinds.add('Force body', lua.reference.rage.binds.body_aim)
lua.keybinds.add('Safe point', lua.reference.rage.binds.safe_point)
lua.keybinds.add('Double tap', lua.reference.rage.binds.double_tap[1].hotkey)
lua.keybinds.add('Hide shots', lua.reference.rage.binds.on_shot_anti_aim[1].hotkey)
lua.keybinds.add('Min. damage', lua.reference.rage.binds.minimum_damage_override[1].hotkey)
lua.keybinds.add('Fake ducking', lua.reference.rage.binds.fakeduck)
lua.keybinds.add('Fake latency', lua.reference.visuals.effects.ping[1].hotkey)
lua.keybinds.add('Auto direction', lua.reference.antiaim.angles.freestanding.hotkey)
--#endregion

--#region lua.notifications
lua.notifications = {} do
    lua.notifications.active = {}
    lua.notifications.history = {}
    lua.notifications.last_stats = {fps = 0, ping = 0, loss = 0, watch = 0, keybinds = 0, spectators = 0}
    lua.notifications.last_keybinds = {}
    lua.notifications.last_spectators = {}
    lua.notifications.initialized_keybinds = false

    function lua.notifications.enabled()
        return false
    end

    function lua.notifications.event_enabled(name)
        return false
    end

    function lua.notifications.play_sound()
    end

    function lua.notifications.clear_history()
        lua.notifications.history = {}
    end

    function lua.notifications.push(kind, title, message, duration, sound)
    end

    function lua.notifications.paint()
    end

    function lua.notifications.watch_stats()
    end

    function lua.notifications.think()
    end
end
--#endregion


--#region lua.test
lua.test = {} do
    lua.test.load_time = globals.realtime()
    lua.test.particles = {}
    lua.test.cursor_points = {}
    lua.test.grenade_cache = {}
    lua.test.intro_flakes = {}
    lua.test.intro_cracks = {}
    lua.test.intro_shards = {}

    function lua.test.get_colors()
        return {
            primary = {90, 190, 255, 255},
            secondary = {190, 90, 255, 255},
            background = {8, 10, 18, 220},
            text = {238, 242, 255, 255}
        }
    end

    function lua.test.scale()
        return (lua.pui.ui.render.ui_scale:get() or 100) / 100
    end

    function lua.test.anim_speed()
        return (lua.pui.ui.render.ui_animation_speed:get() or 100) / 100
    end

    local function circle_3d(pos, radius, start_at, percentage, segment, filled, r, g, b, a)
        local old_x, old_y
        local end_at = start_at + math.floor((percentage or 1) * 360)
        local seg = math.max(12, segment or 64)
        local step = math.max(1, (end_at - start_at) / seg)
        for rot = start_at, end_at, step do
            local rad = math.rad(rot)
            local px = radius * math.cos(rad) + pos.x
            local py = radius * math.sin(rad) + pos.y
            local sx, sy = renderer.world_to_screen(px, py, pos.z)
            local cx, cy = renderer.world_to_screen(pos.x, pos.y, pos.z)
            if sx and sy and old_x and old_y then
                if filled and cx and cy then
                    renderer.triangle(sx, sy, old_x, old_y, cx, cy, r, g, b, a)
                else
                    renderer.line(sx, sy, old_x, old_y, r, g, b, a)
                end
            end
            old_x, old_y = sx, sy
        end
    end

    local function get_entities(classname)
        local ok, ents = pcall(entity.get_all, classname)
        if ok and ents ~= nil then return ents end
        return {}
    end

    local function get_origin_safe(ent)
        local x, y, z = entity.get_origin(ent)
        if x == nil then
            x, y, z = entity.get_prop(ent, 'm_vecOrigin')
        end
        if x == nil then return nil end
        return vector(x, y, z)
    end

    local function get_tick_prop(ent, props)
        for i = 1, #props do
            local ok, value = pcall(entity.get_prop, ent, props[i])
            if ok and value ~= nil and value > 0 then return value end
        end
        return nil
    end

    local function grenade_data(ent, kind)
        local cache = lua.test.grenade_cache[ent]
        local duration = kind == 'smoke' and 18.0 or 7.1
        local tick_props = kind == 'smoke' and {'m_nSmokeEffectTickBegin'} or {'m_nFireEffectTickBegin'}
        local tick_begin = get_tick_prop(ent, tick_props)
        local start_time = tick_begin ~= nil and tick_begin * globals.tickinterval() or nil

        if cache == nil then
            cache = { kind = kind, start = start_time or globals.curtime(), origin = get_origin_safe(ent) }
            lua.test.grenade_cache[ent] = cache
        end

        if start_time ~= nil then cache.start = start_time end
        local origin = get_origin_safe(ent)
        if origin ~= nil then cache.origin = origin end
        if cache.origin == nil then return nil end

        local elapsed = globals.curtime() - cache.start
        if elapsed < 0 then elapsed = 0 end
        local remaining = duration - elapsed
        if remaining <= -1 then return nil end

        local clamped_remaining = mathematic.clamp(remaining, 0, duration)
        local life_progress = mathematic.clamp(elapsed / duration, 0, 1)
        local reveal_time = kind == 'smoke' and 1.65 or 0.85
        local reveal_progress = mathematic.clamp(elapsed / reveal_time, 0, 1)

        return {
            origin = cache.origin,
            duration = duration,
            remaining = clamped_remaining,
            progress = mathematic.clamp(clamped_remaining / duration, 0, 1),
            life_progress = life_progress,
            reveal_progress = reveal_progress,
            elapsed = elapsed,
            kind = kind
        }
    end

    local function draw_timer_card(pos, kind, remaining, progress, color)
        local sx, sy = renderer.world_to_screen(pos.x, pos.y, pos.z + 34)
        if sx == nil or sy == nil then return end

        local scale = lua.test.scale()
        local r, g, b = color[1], color[2], color[3]
        local label = kind == 'smoke' and 'smoke' or 'molotov'
        local text = string.format('%s %.1fs', label, math.max(0, remaining))

        render.text(sx + 1, sy + 1, 0, 0, 0, 180, 'c', 0, text)
        render.text(sx, sy, r, g, b, 235, 'c', 0, text)
    end

    local function ease_out_cubic(x)
        x = mathematic.clamp(x or 0, 0, 1)
        return 1 - math.pow(1 - x, 3)
    end

    local function draw_smoke_reveal(data, color, now, speed)
        local reveal_done = data.reveal_progress >= 1
        local reveal = reveal_done and 1 or ease_out_cubic(data.reveal_progress)
        local final_radius = 144
        local radius = final_radius * reveal
        local breathe = reveal_done and 0 or math.sin(now * 2.15 * speed + data.elapsed) * 2.5
        local r, g, b = color[1], color[2], color[3]
        local alpha = reveal_done and 92 or (45 + reveal * 65)

        if radius < 6 then return end
        circle_3d(data.origin, radius, 0, 1, 96, true, r, g, b, 12 + 18 * reveal)
        circle_3d(data.origin, radius + breathe, 0, 1, 96, false, r, g, b, alpha)
    end

    local function draw_molotov_ignite(data, color, now, speed)
        local reveal_done = data.reveal_progress >= 1
        local reveal = reveal_done and 1 or ease_out_cubic(data.reveal_progress)
        local final_radius = 150
        local radius = final_radius * reveal
        local flicker = reveal_done and 0 or math.sin(now * 8.5 * speed + data.elapsed * 3.0) * 4
        local r, g, b = color[1], color[2], color[3]
        local alpha = reveal_done and 110 or (55 + reveal * 70)

        if radius < 6 then return end
        circle_3d(data.origin, radius, 0, 1, 96, true, r, g, b, 14 + 20 * reveal)
        circle_3d(data.origin, radius + flicker, 0, 1, 96, false, r, g, b, alpha)
    end

    function lua.test.paint_grenades()
        local ui = lua.pui.ui.render
        if not (ui.grenade_timer:get() or ui.grenade_radius:get()) then return end

        local now = globals.realtime()
        local speed = lua.test.anim_speed()
        local sr, sg, sb, sa = ui.smoke_timer_color:get()
        local mr, mg, mb, ma = ui.molotov_timer_color:get()
        local smoke_color = {sr, sg, sb, sa}
        local fire_color = {mr, mg, mb, ma}
        local seen = {}

        for _, ent in ipairs(get_entities('CSmokeGrenadeProjectile')) do
            local did_smoke = entity.get_prop(ent, 'm_bDidSmokeEffect')
            if did_smoke == nil or did_smoke == 1 then
                local data = grenade_data(ent, 'smoke')
                if data and data.remaining > 0 then
                    seen[ent] = true
                    if ui.grenade_radius:get() then
                        draw_smoke_reveal(data, smoke_color, now, speed)
                    end
                    if ui.grenade_timer:get() then
                        draw_timer_card(data.origin, 'smoke', data.remaining, data.progress, smoke_color)
                    end
                end
            end
        end

        for _, ent in ipairs(get_entities('CInferno')) do
            local data = grenade_data(ent, 'molotov')
            if data and data.remaining > 0 then
                seen[ent] = true
                if ui.grenade_radius:get() then
                    draw_molotov_ignite(data, fire_color, now, speed)
                end
                if ui.grenade_timer:get() then
                    draw_timer_card(data.origin, 'molotov', data.remaining, data.progress, fire_color)
                end
            end
        end

        for ent in pairs(lua.test.grenade_cache) do
            if seen[ent] ~= true then
                local cache = lua.test.grenade_cache[ent]
                if cache == nil or globals.curtime() - cache.start > 20 then
                    lua.test.grenade_cache[ent] = nil
                end
            end
        end
    end

    local function ensure_particles()
        local amount = lua.pui.ui.render.particles_amount:get()
        while #lua.test.particles < amount do
            lua.test.particles[#lua.test.particles + 1] = {
                x = math.random(0, math.max(1, math.floor(screen.x))),
                y = math.random(0, math.max(1, math.floor(screen.y))),
                vx = (math.random() - 0.5) * 0.35,
                vy = (math.random() - 0.5) * 0.35,
                size = math.random(1, 3),
                phase = math.random() * 6.28
            }
        end
        while #lua.test.particles > amount do
            table.remove(lua.test.particles)
        end
    end

    function lua.test.paint_menu_visuals()
        if not ui.is_menu_open() then return end

        local colors = lua.test.get_colors()
        local pr, pg, pb = colors.primary[1], colors.primary[2], colors.primary[3]
        local sr, sg, sb = colors.secondary[1], colors.secondary[2], colors.secondary[3]
        local br, bg, bb = colors.background[1], colors.background[2], colors.background[3]
        local speed = lua.test.anim_speed()
        local scale = lua.test.scale()
        local now = globals.realtime()

        if lua.pui.ui.render.menu_particles:get() then
            ensure_particles()
            for i = 1, #lua.test.particles do
                local p = lua.test.particles[i]
                p.x = p.x + p.vx * speed * 2
                p.y = p.y + p.vy * speed * 2
                if p.x < -10 then p.x = screen.x + 10 elseif p.x > screen.x + 10 then p.x = -10 end
                if p.y < -10 then p.y = screen.y + 10 elseif p.y > screen.y + 10 then p.y = -10 end
                local a = 70 + math.sin(now * 2 * speed + p.phase) * 25
                render.circle(p.x, p.y, pr, pg, pb, a, math.max(1, p.size * scale), 0, 1)
            end
        end

        if lua.pui.ui.render.cursor_trail:get() then
            local mx, my = ui.mouse_position()
            local cr, cg, cb, ca = lua.pui.ui.render.cursor_trail_color:get()
            if mx ~= nil and my ~= nil then
                local last = lua.test.cursor_points[#lua.test.cursor_points]
                if last == nil or math.abs(mx - last.x) + math.abs(my - last.y) > 2 then
                    lua.test.cursor_points[#lua.test.cursor_points + 1] = {x = mx, y = my, t = now}
                end
            end
            while #lua.test.cursor_points > 34 do table.remove(lua.test.cursor_points, 1) end
            for i = #lua.test.cursor_points, 1, -1 do
                local p = lua.test.cursor_points[i]
                local life = 0.75 - (now - p.t)
                if life <= 0 then
                    table.remove(lua.test.cursor_points, i)
                else
                    local pct = mathematic.clamp(life / 0.75, 0, 1)
                    local a = pct * ca
                    local radius = (2.2 + (1 - pct) * 3.2) * scale
                    renderer.circle(p.x, p.y, cr, cg, cb, a, radius, 0, 1)
                    if i > 1 then
                        local prev = lua.test.cursor_points[i - 1]
                        if prev ~= nil then
                            renderer.line(p.x, p.y, prev.x, prev.y, cr, cg, cb, a * 0.55)
                        end
                    end
                end
            end
        else
            lua.test.cursor_points = {}
        end
    end


    local function ensure_intro_assets()
        if #lua.test.intro_flakes == 0 then
            for i = 1, 30 do
                lua.test.intro_flakes[#lua.test.intro_flakes + 1] = {
                    x = ((i * 97) % 1000) / 1000,
                    y = ((i * 53) % 1000) / 1000,
                    size = 1 + (i % 3),
                    drift = 0.2 + (i % 7) * 0.08,
                    phase = i * 0.47
                }
            end
        end

        if #lua.test.intro_cracks == 0 then
            local center_bias = -math.pi / 2
            for i = 1, 15 do
                local angle = center_bias + (i / 15) * math.pi * 2 + math.sin(i * 0.85) * 0.12
                lua.test.intro_cracks[#lua.test.intro_cracks + 1] = {
                    angle = angle,
                    length = 110 + (i % 5) * 34,
                    delay = (i - 1) * 0.032,
                    split = 0.42 + (i % 4) * 0.08,
                    bend = ((i % 2 == 0) and 1 or -1) * (0.18 + (i % 3) * 0.05)
                }
            end
        end

        if #lua.test.intro_shards == 0 then
            for i = 1, 18 do
                local angle = -math.pi / 2 + (i / 18) * math.pi * 2
                lua.test.intro_shards[#lua.test.intro_shards + 1] = {
                    angle = angle,
                    start = 30 + (i % 4) * 8,
                    travel = 55 + (i % 6) * 18,
                    size = 8 + (i % 5) * 2,
                    spin = ((i % 2 == 0) and 1 or -1) * (0.8 + (i % 3) * 0.35),
                    delay = (i % 6) * 0.03
                }
            end
        end
    end

    function lua.test.paint_intro()
        if not lua.pui.ui.render.animated_intro:get() then return end
        local elapsed = globals.realtime() - lua.test.load_time
        local duration = 4.55
        if elapsed > duration then return end

        ensure_intro_assets()

        local colors = lua.test.get_colors()
        local speed = lua.test.anim_speed()
        local scale = lua.test.scale()
        local cx, cy = screen.x * 0.5, screen.y * 0.42

        local freeze = mathematic.clamp(elapsed / 1.10, 0, 1)
        local crack = mathematic.clamp((elapsed - 0.95) / 0.95, 0, 1)
        local shatter = mathematic.clamp((elapsed - 1.85) / 0.95, 0, 1)
        local outro = mathematic.clamp((duration - elapsed) / 0.95, 0, 1)
        local alpha_mul = math.min(1, outro)
        local frost_alpha = (70 + freeze * 105) * (1 - shatter * 0.62) * alpha_mul
        local text_alpha = mathematic.clamp((elapsed - 0.45) / 0.7, 0, 1) * alpha_mul

        render.rectangle(0, 0, screen.x, screen.y, 200, 228, 255, frost_alpha)

        for i = 1, #lua.test.intro_flakes do
            local flake = lua.test.intro_flakes[i]
            local px = flake.x * screen.x + math.sin(elapsed * (0.8 + flake.drift) + flake.phase) * 18 * scale
            local py = ((flake.y + elapsed * 0.04 * flake.drift) % 1) * screen.y
            local a = (22 + freeze * 70) * alpha_mul
            renderer.circle(px, py, 240, 248, 255, a, flake.size * scale, 0, 1)
            renderer.line(px - 3 * scale, py, px + 3 * scale, py, 240, 248, 255, a * 0.65)
            renderer.line(px, py - 3 * scale, px, py + 3 * scale, 240, 248, 255, a * 0.65)
        end

        for i = 1, #lua.test.intro_cracks do
            local c = lua.test.intro_cracks[i]
            local show = mathematic.clamp((crack - c.delay) / (1 - c.delay), 0, 1)
            if show > 0 then
                local len = c.length * ease_out_cubic(show)
                local dx, dy = math.cos(c.angle), math.sin(c.angle)
                local bend_x, bend_y = math.cos(c.angle + c.bend), math.sin(c.angle + c.bend)
                local mx = cx + dx * len * c.split
                local my = cy + dy * len * c.split
                local ex = mx + bend_x * len * (1 - c.split)
                local ey = my + bend_y * len * (1 - c.split)
                local aa = (80 + crack * 130) * alpha_mul
                renderer.line(cx, cy, mx, my, 245, 250, 255, aa)
                renderer.line(mx, my, ex, ey, 245, 250, 255, aa)

                local b_len = len * (0.16 + (i % 3) * 0.08)
                local ba = c.angle + ((i % 2 == 0) and -0.7 or 0.7)
                local bx = mx + math.cos(ba) * b_len
                local by = my + math.sin(ba) * b_len
                renderer.line(mx, my, bx, by, 235, 245, 255, aa * 0.72)
            end
        end

        for i = 1, #lua.test.intro_shards do
            local s = lua.test.intro_shards[i]
            local prog = mathematic.clamp((shatter - s.delay) / (1 - s.delay), 0, 1)
            if prog > 0 then
                local dist = s.start + s.travel * ease_out_cubic(prog)
                local sx = cx + math.cos(s.angle) * dist
                local sy = cy + math.sin(s.angle) * dist
                local rot = s.angle + elapsed * s.spin * speed
                local size = s.size * scale * (1 - prog * 0.15)
                local x1 = sx + math.cos(rot) * size
                local y1 = sy + math.sin(rot) * size
                local x2 = sx + math.cos(rot + 2.25) * size * 0.72
                local y2 = sy + math.sin(rot + 2.25) * size * 0.72
                local x3 = sx + math.cos(rot - 2.15) * size * 0.9
                local y3 = sy + math.sin(rot - 2.15) * size * 0.9
                renderer.triangle(x1, y1, x2, y2, x3, y3, 230, 242, 255, 85 * (1 - prog) * alpha_mul)
            end
        end

        local shimmer = 0.72 + math.sin(elapsed * 5.2 * speed) * 0.28
        local title = 'CRYONOVA'
        local title_y = cy + 4 * scale
        local glow_alpha = 24 * text_alpha
        for ox = -3, 3 do
            for oy = -2, 2 do
                if math.abs(ox) + math.abs(oy) <= 4 then
                    render.text(cx + ox * scale, title_y + oy * scale, 172, 218, 255, glow_alpha, 'c+', 0, title)
                end
            end
        end
        render.text(cx + 3 * scale, title_y + 3 * scale, 6, 12, 20, 170 * text_alpha, 'c+', 0, title)
        render.text(cx, title_y, 246, 249, 255, 255 * text_alpha, 'c+', 0, title)
        render.text(cx, title_y - 1 * scale, 186, 228, 255, 105 * text_alpha * shimmer, 'c+', 0, title)
    end


    client.set_event_callback('paint', function ()
        lua.test.paint_grenades()
    end)

    client.set_event_callback('paint_ui', function ()
        lua.test.paint_menu_visuals()
        lua.test.paint_intro()
    end)

    client.set_event_callback('level_init', function ()
        lua.test.grenade_cache = {}
    end)
end
--#endregion

--#region lua.extra_widgets
lua.extra_widgets = lua.extra_widgets or {} do
    local ew = lua.extra_widgets
    ew.reload_alpha = ew.reload_alpha or 0

    local function selected(name)
        return lua.pui.ui.render ~= nil and lua.pui.ui.render.panels_select:get(name)
    end

    local function panel(x, y, w, h, title, alpha)
        alpha = alpha or 1
        render.shadow(x, y, w, h, 8, 2, 0, 0, 0, 34 * alpha)
        render.round_rect(x, y, w, h, 8, 14, 16, 24, 198 * alpha)
        render.round_rect(x, y, w, h, 8, 255, 255, 255, 7 * alpha)
        if title ~= nil and title ~= '' then
            render.text(x + 12, y + 8, 228, 234, 245, 220 * alpha, '-', 0, title)
        end
    end

    local function progress_bar(x, y, w, h, frac, r, g, b, alpha)
        frac = mathematic.clamp(frac or 0, 0, 1)
        render.round_rect(x, y, w, h, h / 2, 255, 255, 255, 10 * alpha)
        if frac > 0 then
            render.round_rect(x, y, math.max(2, w * frac), h, h / 2, r, g, b, 210 * alpha)
        end
    end

    function ew.get_reload_data()
        if not selected('Reload indicator') then return false, 0 end
        local me = entity.get_local_player()
        if me == nil or not entity.is_alive(me) then return false, 0 end
        local weapon = entity.get_player_weapon(me)
        if weapon == nil then return false, 0 end
        local in_reload = entity.get_prop(weapon, 'm_bInReload') == 1
        if not in_reload then return false, 0 end
        local next_attack = entity.get_prop(weapon, 'm_flNextPrimaryAttack') or globals.curtime()
        local remaining = math.max(0, next_attack - globals.curtime())
        local frac = 1 - mathematic.clamp(remaining / 3, 0, 1)
        return true, frac
    end

    function ew.is_reload_active()
        local active = ew.get_reload_data()
        return active == true
    end

    local function bomb_data()
        local bombs = entity.get_all('CPlantedC4') or {}
        if #bombs == 0 then return nil end
        local bomb = bombs[1]
        local blow = entity.get_prop(bomb, 'm_flC4Blow') or 0
        local timer = math.max(0, blow - globals.curtime())
        local site = (entity.get_prop(bomb, 'm_nBombSite') or 0) == 0 and 'A' or 'B'
        local defuser = entity.get_prop(bomb, 'm_hBombDefuser') or -1
        local defuse_end = entity.get_prop(bomb, 'm_flDefuseCountDown') or 0
        local defuse_time = math.max(0, defuse_end - globals.curtime())
        return {
            timer = timer,
            frac = mathematic.clamp(timer / 40, 0, 1),
            site = site,
            defuse_time = defuse_time,
            defusing = defuser ~= nil and defuser ~= -1 and defuse_end > globals.curtime()
        }
    end

    local function draw_bomb_panel()
        if not selected('Bomb timer') then return end
        local data = bomb_data()
        if data == nil then return end

        local w = 240
        local h = data.defusing and 78 or 52
        local x = screen.x * 0.5 - w * 0.5
        local y = 82
        local left = x + 12
        local right = x + w - 12

        panel(x, y, w, h, 'Bomb timer', 1)

        local bomb_row_y = y + 24
        render.text(left, bomb_row_y, 235, 240, 250, 235, '-', 0, 'Site ' .. data.site)
        render.text(right, bomb_row_y, 255, 196, 196, 240, 'r', 0, string.format('%.1fs', data.timer))
        progress_bar(left, bomb_row_y + 12, w - 24, 6, 1 - data.frac, 255, 94, 94, 1)

        if data.defusing then
            local can = data.defuse_time <= data.timer
            local defuse_row_y = y + 47
            render.text(left, defuse_row_y, 235, 240, 250, 235, '-', 0, 'Defusing')
            render.text(right, defuse_row_y, can and 140 or 255, can and 235 or 170, can and 255 or 170, 240, 'r', 0, string.format('%.1fs', data.defuse_time))
            progress_bar(left, defuse_row_y + 12, w - 24, 6, 1 - mathematic.clamp(data.defuse_time / 10, 0, 1), can and 120 or 255, can and 190 or 122, can and 255 or 122, 1)
        end
    end

    local function draw_reload_circle()
        local active, frac = ew.get_reload_data()
        ew.reload_alpha = mathematic.lerp(ew.reload_alpha, active and 1 or 0, 0.18)
        if ew.reload_alpha <= 0.02 then return end

        local r, g, b, a = lua.pui.ui.render.reload_indicator_color:get()
        local cx, cy = screen.x * 0.5, screen.y * 0.5 + 34
        local radius = 10
        local alpha = ew.reload_alpha

        if renderer.circle_outline ~= nil then
            renderer.circle_outline(cx, cy, 255, 255, 255, 16 * alpha, radius, 0, 1, 2)
            renderer.circle_outline(cx, cy, r, g, b, math.min(a, 235) * alpha, radius, -90, frac, 2.5)
        else
            render.circle(cx, cy, 255, 255, 255, 24 * alpha, radius + 1, 0, 1)
            render.circle(cx, cy, r, g, b, math.min(a, 220) * alpha, radius, -90, frac)
        end
    end

    function ew.paint()
        draw_bomb_panel()
        draw_reload_circle()
    end

    client.set_event_callback('paint_ui', function()
        ew.paint()
    end)
end
--#endregion

--#region lua.yandex
lua.yandex = {
    state = {
        title = 'Waiting for music...',
        artist = 'Yandex Music',
        status = 'starting',
        ok = false,
        last = 0,
        cover_url = '',
        cover_rev = 0,
        cover = nil,
        position = 0,
        duration = 0,
        remaining = 0,
        progress = 0,
        cover_loading = false
    }
} do
    lua.yandex.send_command = function(cmd)
        http.get('http://127.0.0.1:4545/' .. cmd, function(success, response)
            if not success or response.status ~= 200 then
                client.log('[Yandex HUD] command failed: ' .. tostring(cmd))
            end
        end)
    end

    lua.yandex.clamp_text = function(s, n)
        s = tostring(s or '')
        if #s > n then
            return s:sub(1, n - 3) .. '...'
        end
        return s
    end

    lua.yandex.try_load_image = function(body)
        local ok, img = pcall(images.load_jpg, body)
        if ok and img ~= nil then return img end
        ok, img = pcall(images.load_png, body)
        if ok and img ~= nil then return img end
        return nil
    end

    lua.yandex.fetch_cover = function(url)
        local state = lua.yandex.state
        if url == nil or url == '' or state.cover_loading then return end
        state.cover_loading = true
        http.get(url, function(success, response)
            state.cover_loading = false
            if not success or response.status ~= 200 then
                client.log('[Yandex HUD] cover failed: ' .. tostring(response and response.status or 'no response'))
                return
            end
            local img = lua.yandex.try_load_image(response.body)
            if img ~= nil then
                state.cover = img
            else
                client.log('[Yandex HUD] cover image decode failed')
            end
        end)
    end

    lua.yandex.fetch_current = function()
        local state = lua.yandex.state
        http.get('http://127.0.0.1:4545/current', function(success, response)
            if not success or response.status ~= 200 then
                state.ok = false
                state.title = 'Bridge offline'
                state.artist = 'Start start_bridge.bat'
                state.status = 'offline'
                return
            end

            local data = json.parse(response.body)
            if not data then return end
            state.ok = data.ok == true
            state.title = data.title or 'No title'
            state.artist = data.artist or 'No artist'
            state.status = data.status or 'unknown'
            state.position = tonumber(data.position) or 0
            state.duration = tonumber(data.duration) or 0
            state.remaining = tonumber(data.remaining) or math.max(0, state.duration - state.position)
            state.progress = tonumber(data.progress) or (state.duration > 0 and state.position / state.duration or 0)
            state.progress = math.max(0, math.min(1, state.progress))

            if data.cover_url and data.cover_url ~= '' and data.cover_rev and data.cover_rev ~= state.cover_rev then
                state.cover_url = data.cover_url
                state.cover_rev = data.cover_rev
                lua.yandex.fetch_cover(state.cover_url)
            end
        end)
    end

    lua.yandex.format_time = function(sec)
        sec = math.max(0, math.floor(tonumber(sec) or 0))
        local m = math.floor(sec / 60)
        local s = sec % 60
        return string.format('%d:%02d', m, s)
    end

    lua.yandex.draw = function()
        local state = lua.yandex.state
        local now = globals.realtime()
        if now - state.last > lua.pui.ui.additive.yandex_update:get() then
            state.last = now
            lua.yandex.fetch_current()
        end

        local x = lua.pui.ui.additive.yandex_x:get()
        local y = lua.pui.ui.additive.yandex_y:get()
        local w = lua.pui.ui.additive.yandex_w:get()
        local h = 104
        local bg_a = lua.pui.ui.additive.yandex_alpha:get()

        render.round_rect(x, y, w, h, 20, 5, 5, 7, bg_a)
        local ar, ag, ab, aa = lua.pui.ui.additive.yandex_accent:get()
        render.round_rect(x + 2, y + 12, 4, h - 24, 2, ar, ag, ab, aa)

        local cx, cy, cs = x + 20, y + 14, 56
        render.round_rect(cx - 2, cy - 2, cs + 4, cs + 4, 12, 20, 20, 22, 255)
        if lua.pui.ui.additive.yandex_cover:get() and state.cover ~= nil then
            state.cover:draw(cx, cy, cs, cs, 255, 255, 255, 255)
        else
            render.round_rect(cx, cy, cs, cs, 10, 33, 33, 36, 255)
            renderer.text(cx + cs / 2, cy + 21, 175, 175, 180, 230, 'c', 0, '*')
        end

        local tx = x + 92
        local max_title = math.floor((w - 115) / 8)
        renderer.text(tx, y + 17, 255, 255, 255, 255, 'b', 0, lua.yandex.clamp_text(state.title, max_title))
        renderer.text(tx, y + 40, 220, 220, 220, 245, '', 0, lua.yandex.clamp_text(state.artist, max_title + 8))

        local status = tostring(state.status or '')
        local sr, sg, sb = 155, 155, 155
        if status == 'playing' then sr, sg, sb = 95, 255, 125 end
        if status == 'paused' then sr, sg, sb = 255, 210, 85 end
        if status == 'offline' or status == 'error' then sr, sg, sb = 255, 90, 90 end
        renderer.text(tx, y + 62, sr, sg, sb, 255, '', 0, '* ' .. status)

        local bar_x = tx
        local bar_y = y + 84
        local bar_w = w - 118
        local prog = state.progress or 0
        local fill_w = math.floor(bar_w * prog)

        renderer.text(bar_x, y + 76, 170, 170, 175, 245, '', 0, lua.yandex.format_time(state.position))
        local right_text = state.duration > 0 and ('-' .. lua.yandex.format_time(state.remaining)) or '-0:00'
        renderer.text(bar_x + bar_w - 38, y + 76, 170, 170, 175, 245, '', 0, right_text)

        render.round_rect(bar_x, bar_y + 14, bar_w, 4, 2, 35, 35, 39, 255)
        if fill_w > 0 then
            render.round_rect(bar_x, bar_y + 14, fill_w, 4, 2, 255, 255, 255, 235)
            renderer.circle(bar_x + fill_w, bar_y + 16, 245, 245, 245, 255, 4, 0, 1)
        end
    end
end
--#endregion
--#region lua.animations, lua.render
lua.animations = {} lua.render = {} do
    lua.animations.aerobic = function ()
        local me = entity.get_local_player()
        if not me then return end
        local self_index = lua.entity.new(me)
        if self_index:get_anim_state().on_ground == true then return end

        if lua.pui.ui.animations.aerobic:get() == 'Quadrobic' then
           entity.set_prop(me, 'm_flPoseParameter', self_index:get_anim_state().time_since_in_air, 6)
        end

        if lua.pui.ui.animations.aerobic:get() == 'Static' then
            entity.set_prop(me, 'm_flPoseParameter', 1, 6)
        end

        if lua.pui.ui.animations.aerobic:get() == 'Trap' then
            entity.set_prop(me, 'm_flPoseParameter', client.random_float(5 / 10, 10 / 5), 6)
        end

        if lua.pui.ui.animations.aerobic:get() == 'Swag' then
            entity.set_prop(me, 'm_flPoseParameter', math.random(math.random(0.0, 1.0), client.random_float(self_index:get_anim_state().time_since_in_air, 1)), 6)
        end

        if lua.pui.ui.animations.aerobic:get() == 'Jitter' then
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.5, 1.0), 6)
        end

        if lua.pui.ui.animations.aerobic:get() == 'Walking' then
            self_index:get_anim_overlay(6).weight = 1
            self_index:get_anim_overlay(6).cycle = globals.realtime() * 0.5 % 1
        end
    end

    lua.animations.ground = function ()
        local me = entity.get_local_player()
        if not me then return end
        local self_index = lua.entity.new(me)
        if self_index:get_anim_state().on_ground == false then return end

        if lua.pui.ui.animations.ground:get() == 'Static' then
            entity.set_prop(me, 'm_flPoseParameter', 1, 0)
            entity.set_prop(me, 'm_flPoseParameter', 1, 7)
        end

        if lua.pui.ui.animations.ground:get() == 'Static invert' then
            entity.set_prop(me, 'm_flPoseParameter', 0.5, 0)
            entity.set_prop(me, 'm_flPoseParameter', 0, 7)
        end

        if lua.pui.ui.animations.ground:get() == 'Trap' then
            entity.set_prop(me, 'm_flPoseParameter', client.random_float(5 / 10, 10 / 5), 0)
            entity.set_prop(me, 'm_flPoseParameter', client.random_float(5 / 10, 10 / 5), 7)
        end

        if lua.pui.ui.animations.ground:get() == 'Swag' then
            entity.set_prop(me, 'm_flPoseParameter', math.random(client.random_float(0.0, 5.0), client.random_float(0.0, 1.0)), 0)
            entity.set_prop(me, 'm_flPoseParameter', math.random(client.random_float(0.0, 5.0), client.random_float(0.0, 1.0)), 7)
        end

        if lua.pui.ui.animations.ground:get() == 'Jitter' then
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 7)
            entity.set_prop(me, 'm_flPoseParameter', math.random(client.random_float(0.0, 1.0), client.random_float(0.0, 1.0)), 0)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 1)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 3)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 4)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 5)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 8)
        end

        if lua.pui.ui.animations.ground:get() == 'Freeze' then
            entity.set_prop(me, 'm_flPoseParameter', 0, 10)
        end

        if lua.pui.ui.animations.ground:get() == 'Freeze & Static' then
            entity.set_prop(me, 'm_flPoseParameter', 1, 0)
            entity.set_prop(me, 'm_flPoseParameter', 0, 10)
        end

        if lua.pui.ui.animations.ground:get() == 'Freeze & Static invert' then
            entity.set_prop(me, 'm_flPoseParameter', 0.5, 0)
            entity.set_prop(me, 'm_flPoseParameter', 0, 10)
        end

        if lua.pui.ui.animations.ground:get() == 'Bugged' then
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 7)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 0)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 1)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 2)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 3)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 4)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 5)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 8)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 9)
            entity.set_prop(me, 'm_flPoseParameter', math.random(0.0, 1.0), 10)
        end
    end

    lua.animations.lean = function ()
        local me = entity.get_local_player()
        if not me then return end
        local self_index = lua.entity.new(me)

        if lua.pui.ui.animations.lean:get() == 'Jitter' then
            self_index:get_anim_overlay(12).weight = math.random(0.3, 1)
            self_index:get_anim_overlay(12).cycle = globals.realtime() * 0.5 % 1
        end

        if self_index:get_anim_state().m_velocity < 10 then return end

        if lua.pui.ui.animations.lean:get() == 'Zero' then
            self_index:get_anim_overlay(12).weight = 0
            self_index:get_anim_overlay(12).cycle = globals.realtime() * 0.5 % 1
        end

        if lua.pui.ui.animations.lean:get() == 'Big' then
            self_index:get_anim_overlay(12).weight = 1
            self_index:get_anim_overlay(12).cycle = globals.realtime() * 0.5 % 1
        end
    end

    lua.animations.other = function ()
        local me = entity.get_local_player()
        if not me then return end
        local self_index = lua.entity.new(me)

        if lua.pui.ui.animations.other:get('2021 animfix') then
            entity.set_prop(me, 'm_flPoseParameter', 0.5, 11)
        end

        if lua.pui.ui.animations.other:get('Animation smooth') then
            self_index:get_anim_overlay(3).weight = 1
            self_index:get_anim_overlay(3).cycle = globals.realtime() * 0.5 % 1
        end

        if lua.pui.ui.animations.other:get('Autopeek fix') and lua.reference.antiaim.other.leg_movement:get() ~= 'Always slide' and lua.reference.rage.binds.quickpeek[1]:get() then
            self_index:get_anim_overlay(7).weight = 0
        end

        if lua.pui.ui.animations.other:get('Model scale') then
            entity.set_prop(me, 'm_flModelScale', 0.5)
            entity.set_prop(me, 'm_ScaleType', 1)
        else
            entity.set_prop(me, 'm_flModelScale', 1)
            entity.set_prop(me, 'm_ScaleType', 0)
        end

        if lua.pui.ui.animations.other:get('Flashed') then
            self_index:get_anim_overlay(0).sequence = 227
        end

        if lua.pui.ui.animations.other:get('Zero pitch') and self_index:get_anim_state().hit_in_ground_animation == true 
        and self_index:get_anim_state().magic_fraction == 1 and self_index:get_anim_state().on_ground == true then
            entity.set_prop(me, 'm_flPoseParameter', 0.5, 12)
        end
    end

    lua.pui.ui.animations.animations_select:set_event('pre_render', lua.animations.aerobic, function (this)
        return this:get('Aerobic')
    end)
    lua.pui.ui.animations.animations_select:set_event('pre_render', lua.animations.ground, function (this)
        return this:get('Ground')
    end)
    lua.pui.ui.animations.animations_select:set_event('pre_render', lua.animations.lean, function (this)
        return this:get('Lean')
    end)
    lua.pui.ui.animations.animations_select:set_event('pre_render', lua.animations.other, function (this)
        return this:get('Additive')
    end)

    lua.render.anims = {
        a = 0,
        b = 0,
        c = 0,
        d = 0,
        e = 0,
        f = 0,
        g = 0,
        h = 0,
        i = 0,
        j = 0,
        k = 0,
        l = 0,
        m = 0,
        n = 0,
        o = 0,
        p = 0,
        q = 0,
        r = 0,
        s = 0,
        t = 0,
        u = 0,
        v = 0,
        w = 0,
        x = 0,
        y = 0,
        z = 0
    }

    lua.render.lni = {
        center = {
            a = 0,
            b = 0,
            c = 0,
            d = 0,
            e = 0,
            f = 0,
            g = 0,
            h = 0,
            i = 0,
            j = 0,
            k = 0,
            l = 0
        },
        crosshair_indicator = {},
    }

    lua.render.interpfuncs = function ()
        lua.render.anims.u = mathematic.lerp(lua.render.anims.u, ui.is_menu_open() and lua.pui.ui.render.panels_select:get('Obscuration') and 1 or 0, 0.06)
        local me = entity.get_local_player()
        if not me then return end
        local grenade = false
        local weapon = entity.get_player_weapon(me)
        if weapon ~= nil then
            local weaponi = weapons(weapon)
            if weaponi.weapon_type_int == 9 then
                grenade = true
            end
        end

        lua.render.lni.center.a = mathematic.lerp(lua.render.lni.center.a, lua.pui.ui.render.panels_select:get('Indicator') and 1 or 0, 0.06)
        lua.render.lni.center.b = mathematic.lerp(lua.render.lni.center.b, lua.reference.rage.binds.double_tap[1].hotkey:get() and 1 or 0, 0.06)
        lua.render.lni.center.d = mathematic.lerp(lua.render.lni.center.d, lua.reference.rage.binds.minimum_damage_override[1]:get_hotkey() and 1 or 0, 0.06)
        lua.render.lni.center.f = mathematic.lerp(lua.render.lni.center.f, math.exploit() and 1 or 0, 0.03)
        lua.render.anims.a = mathematic.lerp(lua.render.anims.a, lua.pui.ui.render.panels_select:get('Watermark') and 1 or 0, 0.06)
        lua.render.anims.b = mathematic.lerp(lua.render.anims.b, lua.pui.ui.world.world_manager:get('Local Sharing') and 1 or 0, 0.06)
        lua.render.anims.c = mathematic.lerp(lua.render.anims.c, math.exploit and lua.helps.exploits.defensive() > 0 and 1 or 0, 0.06)
        lua.render.anims.d = mathematic.lerp(lua.render.anims.d, lua.pui.ui.render.panels_select:get('Binds') and 1 or 0, 0.06)
        lua.render.anims.h = mathematic.lerp(lua.render.anims.h, 0, 0.06)
        lua.render.anims.m = mathematic.lerp(lua.render.anims.m, entity.get_prop(me, 'm_bIsScoped') == 1 and 1 or 0, 0.06)
    end
    lua.render.data_hit = {}

    client.set_event_callback('player_hurt', function(e)
        local player = entity.get_local_player()
        if player == nil then
            return
        end

        local victim = client.userid_to_entindex(e.userid)
        if victim == nil then
            return
        end

        local attacker = client.userid_to_entindex(e.attacker)
        if attacker == nil then
            return
        end

        if attacker == player then
            table.insert(lua.render.data_hit, 
                {
                    position = entity.hitbox_position(victim, e.hitgroup),
                    damage = e.dmg_health,
                    weapon = e.weapon,
                    alpha_3d = 0,
                    alpha_crosshair = 0,
                    time = globals.realtime(),
                }
            )
        end
    end)

    lua.render.hitmarker = function()
        local x, y = screen.x / 2, screen.y / 2
        for k, v in pairs(lua.render.data_hit) do
            v.alpha_crosshair = mathematic.lerp(v.alpha_crosshair, v.time + 0.5 > globals.realtime() and 1 or 0, 0.095)
            lua.render.lni.center.g = v.alpha_crosshair
        end
        render.line(x - 5, y - 5, x - 10, y - 10, 255, 255, 255, 255 * lua.render.lni.center.g)
        render.line(x + 5, y + 5, x + 10, y + 10, 255, 255, 255, 255 * lua.render.lni.center.g)
        render.line(x - 5, y + 5, x - 10, y + 10, 255, 255, 255, 255 * lua.render.lni.center.g)
        render.line(x + 5, y - 5, x + 10, y - 10, 255, 255, 255, 255 * lua.render.lni.center.g)
    end

    lua.render.dragapf = function ()
        local me = entity.get_local_player()
        if not me then return end
        local weapon = entity.get_player_weapon(me)
        if lua.reference.rage.binds.quickpeek[1]:get_hotkey() and lua.reference.rage.binds.double_tap[1].hotkey:get() and lua.reference.rage.binds.double_tap[1]:get() then
            local fire = 0
            local wpn = 0
            for k, v in pairs(lua.render.data_hit) do
                wpn = v.weapon
                fire = v.damage
                if v.time + 0.01 < globals.realtime() then
                    table.remove(lua.render.data_hit, k)
                end
            end

            local scout = 0
            if weapon ~= nil and fire ~= 0 then
                local weaponi = weapons(weapon)
                if weaponi.weapon_type_int == 5 then
                    scout = 1
                end
            end

            if fire ~= 0 and scout and wpn == 'ssg08' then
                cvar.slot3:invoke_callback()
            else
                cvar.slot1:invoke_callback()
            end
        end

        
    end

    local steit = ''
    local function draw_stable_indicator_line(x, y, r, g, b, a, flags, alpha, text_width, ...)
        if alpha == nil then alpha = 1 end
        if alpha <= 0 then return end
        local width = text_width or render.measure_text(flags, ...)
        render.text(x - width * 0.5, y, r, g, b, a * alpha, flags, width * alpha + 1.9, ...)
    end

    local function draw_indicator_star(x, y, size, r, g, b, a)
        render.line(x - size, y, x + size, y, r, g, b, a)
        render.line(x, y - size, x, y + size, r, g, b, a)
        if size > 1 then
            render.line(x - size + 1, y - size + 1, x + size - 1, y + size - 1, r, g, b, a * 0.65)
            render.line(x - size + 1, y + size - 1, x + size - 1, y - size + 1, r, g, b, a * 0.65)
        end
    end

    local function draw_indicator_stars(x, y, r, g, b, a)
        local points = {
            {-21, 2, 1}, {-14, 0, 2}, {-7, 2, 1}, {0, 0, 3}, {8, 2, 1}, {15, 0, 2}, {22, 2, 1}
        }
        for i = 1, #points do
            local point = points[i]
            if point[3] == 1 then
                render.rectangle(x + point[1], y + point[2], 1, 1, r, g, b, a * 0.75)
            else
                draw_indicator_star(x + point[1], y + point[2], point[3], r, g, b, a)
            end
        end
    end

    local function get_indicator_state()
        local state = lua.createmove.get_state()
        local states = {
            ['Numb'] = 'standing',
            ['Push'] = 'moving',
            ['Aerobic'] = 'aerobic',
            ['Aerobic+'] = 'aerobic+',
            ['Crouch'] = 'crouch',
            ['Crawling'] = 'walking',
            ['Сreeping'] = 'crouch+',
            ['?reeping'] = 'crawling',
            ['Using'] = 'using',
            ['Freestand'] = 'freestanding',
            ['Manual Left'] = 'manual left',
            ['Manual Right'] = 'manual right',
            ['Manual Back'] = 'manual back',
            ['Manual Forward'] = 'manual forward'
        }
        return states[state] or tostring(state):lower()
    end
    function draggable:indicator ()
        local me = entity.get_local_player()
        if not me then return end

        local state = get_indicator_state():upper()

        local r, g, b = lua.pui.ui.render.indicatorcol:get()
        local r2, g2, b2 = lua.pui.ui.render.indicatorcol2:get()
        local weapon = entity.get_player_weapon(me)
        if not weapon then return end
        local next_attack = entity.get_prop(me, 'm_flNextAttack')
        local next_primary_attack = entity.get_prop(weapon, 'm_flNextPrimaryAttack')
        if not next_primary_attack then return end

        local base_x = screen.x * 0.5
        local base_y = screen.y * 0.5 + 18
        local alpha = lua.render.lni.center.a

        if not (math.max(next_primary_attack, next_attack) > globals.curtime()) and lua.reference.rage.binds.double_tap[1].hotkey:get() and lua.reference.rage.binds.double_tap[1]:get() then
            lua.render.lni.center.c = mathematic.clamp(lua.render.lni.center.c + globals.frametime() / 0.15, 0, 1)
        else
            lua.render.lni.center.c = mathematic.clamp(lua.render.lni.center.c - globals.frametime() / 0.15, 0, 1)
        end

        if (math.max(next_primary_attack, next_attack) > globals.curtime()) and lua.reference.rage.binds.double_tap[1].hotkey:get() and lua.reference.rage.binds.double_tap[1]:get() then
            lua.render.lni.center.j = mathematic.clamp(lua.render.lni.center.j + globals.frametime() / 0.15, 0, 1)
        else
            lua.render.lni.center.j = mathematic.clamp(lua.render.lni.center.j - globals.frametime() / 0.15, 0, 1)
        end

        if lua.reference.rage.binds.on_shot_anti_aim[1]:get() and lua.reference.rage.binds.on_shot_anti_aim[1].hotkey:get() and not lua.reference.rage.binds.double_tap[1].hotkey:get() then
            lua.render.lni.center.e = mathematic.clamp(lua.render.lni.center.e + globals.frametime() / 0.15, 0, 1)
        else
            lua.render.lni.center.e = mathematic.clamp(lua.render.lni.center.e - globals.frametime() / 0.15, 0, 1)
        end


        local brand = 'CRYONOVA'
        local brand_width = render.measure_text('-', brand)
        local brand_gradient = mathematic.animate_text(globals.curtime(), brand, r2, g2, b2, 255 * alpha, r, g, b, 255 * alpha)
        draw_stable_indicator_line(base_x, base_y, r, g, b, 255 * alpha, '-', alpha, brand_width, unpack(brand_gradient))

        local state_width = render.measure_text('-', state)
        if state == steit then
            lua.render.lni.center.k = mathematic.clamp(lua.render.lni.center.k + globals.frametime() / 0.15, 0, 1)
        else
            lua.render.lni.center.k = mathematic.clamp(lua.render.lni.center.k - globals.frametime() / 0.15, 0, 1)
        end
        if lua.render.lni.center.k < .1 then
            steit = state
        end
        draw_stable_indicator_line(base_x, base_y + 13, r, g, b, 255, '-', lua.render.lni.center.k * alpha, state_width, steit)

        local dt_ready = 'DT ' .. '\a' .. mathematic.hex_rgba(155, 255, 155, 255 * lua.render.lni.center.c) .. 'READY'
        local dt_width = render.measure_text('-', 'DT READY')
        draw_stable_indicator_line(base_x, base_y + 24, r, g, b, 255, '-', lua.render.lni.center.c * alpha, dt_width, dt_ready)

        local charging = mathematic.animate_text(globals.curtime(), 'CHARGING', 255, 100, 100, 255 * lua.render.lni.center.j, r, g, b, 255 * lua.render.lni.center.j)
        local charging_width = render.measure_text('-', 'DT CHARGING')
        draw_stable_indicator_line(base_x, base_y + 24, r, g, b, 255, '-', lua.render.lni.center.j * alpha, charging_width, 'DT ', unpack(charging))

        local os_ready = 'ACTIVE'
        local os_width = render.measure_text('-', 'OSAA ' .. os_ready)
        local os_gradient = mathematic.animate_text(globals.curtime(), os_ready, r2, g2, b2, 255 * lua.render.lni.center.e, r, g, b, 255 * lua.render.lni.center.e)
        draw_stable_indicator_line(base_x, base_y + 24, r, g, b, 255, '-', lua.render.lni.center.e * alpha, os_width, 'OSAA ', unpack(os_gradient))

    end

    function draggable:indicator_enthusiasm ()
        local me = entity.get_local_player()
        if not me then return end

        local r, g, b = lua.pui.ui.render.indicatorcol:get()
        local r2, g2, b2 = lua.pui.ui.render.indicatorcol2:get()
        local weapon = entity.get_player_weapon(me)
        if not weapon then return end
        local next_attack = entity.get_prop(me, 'm_flNextAttack') or 0
        local next_primary_attack = entity.get_prop(weapon, 'm_flNextPrimaryAttack') or 0
        local base_x = screen.x * 0.5
        local base_y = screen.y * 0.5 + 17
        local alpha = lua.render.lni.center.a

        local doubletap = lua.reference.rage.binds.double_tap[1]:get() and lua.reference.rage.binds.double_tap[1].hotkey:get()
        local charging = doubletap and math.max(next_primary_attack, next_attack) > globals.curtime()
        local mindmg = lua.reference.rage.binds.minimum_damage_override[1]:get_hotkey()
        local onshot = lua.reference.rage.binds.on_shot_anti_aim[1]:get() and lua.reference.rage.binds.on_shot_anti_aim[1].hotkey:get() and not doubletap

        lua.render.lni.center.c = mathematic.clamp(lua.render.lni.center.c + globals.frametime() / 0.15 * ((doubletap and not charging) and 1 or -1), 0, 1)
        lua.render.lni.center.j = mathematic.clamp(lua.render.lni.center.j + globals.frametime() / 0.15 * ((doubletap and charging) and 1 or -1), 0, 1)
        lua.render.lni.center.d = mathematic.lerp(lua.render.lni.center.d, mindmg and 1 or 0, 0.08)
        lua.render.lni.center.e = mathematic.lerp(lua.render.lni.center.e, onshot and 1 or 0, 0.08)

        local decor = string.char(226, 130, 138, 226, 128, 167, 46, 194, 176, 46, 226, 139, 134, 226, 156, 166, 226, 139, 134, 46, 194, 176, 46, 226, 128, 167, 226, 130, 138)
        local decor_width = render.measure_text('b', decor)
        draw_stable_indicator_line(base_x, base_y - 3, 255, 255, 255, 190, 'b', alpha, decor_width, decor)

        local title = 'cryonova'
        local title_width = render.measure_text('b', title)
        local title_gradient = mathematic.animate_text(globals.curtime(), title, r, g, b, 245 * alpha, r2, g2, b2, 185 * alpha)
        draw_stable_indicator_line(base_x, base_y + 8, r, g, b, 245, 'b', alpha, title_width, unpack(title_gradient))

        local bind_y = base_y + 20
        local bind_alpha = math.max(lua.render.lni.center.c, lua.render.lni.center.j, lua.render.lni.center.d, lua.render.lni.center.e)
        local bind_text = nil
        local bind_r, bind_g, bind_b = 255, 255, 255
        if lua.render.lni.center.j > 0.01 then
            bind_text = 'charging'
            bind_r, bind_g, bind_b = 255, 120, 120
        elseif lua.render.lni.center.c > 0.01 then
            bind_text = 'rapid'
            bind_r, bind_g, bind_b = 255, 255, 255
        elseif lua.render.lni.center.d > 0.01 then
            bind_text = 'impair'
        elseif lua.render.lni.center.e > 0.01 then
            bind_text = 'on-shot'
        end

        if bind_text ~= nil then
            local bind_width = render.measure_text('', bind_text)
            draw_stable_indicator_line(base_x, bind_y, bind_r, bind_g, bind_b, 220, '', bind_alpha * alpha, bind_width, bind_text)
            bind_y = bind_y + 11 * bind_alpha
        end

        local state = get_indicator_state()
        local state_width = render.measure_text('', state)
        draw_stable_indicator_line(base_x, bind_y, 255, 255, 255, 220, '', alpha, state_width, state)
    end

    local draggable_ind = draggable:new('draggable indicator', screen.x / 2, screen.y / 2 + 20, 20, 50)

    local initiliaze_indicator = function ()
        if lua.pui.ui.render.indicator_style:get() == 'Mode v2' then
            draggable_ind:indicator_enthusiasm()
        else
            draggable_ind:indicator()
        end
    end

    lua.render.custom_scope = function ()
        local enable = lua.pui.ui.world.custom_scope:get()
        local r, g, b, a = lua.pui.ui.world.custom_scope:get_color()
        local position = lua.pui.ui.world.custom_scope_position:get() * screen.y / 1080
        local offset = lua.pui.ui.world.custom_scope_offset:get() * screen.y / 1080
        local fade =  lua.pui.ui.world.custom_scope_fade:get()

        local me = entity.get_local_player()
        if not me then return end
        local wpn = entity.get_player_weapon(me)
        if not wpn then return end

        if enable then
            lua.reference.visuals.effects.scope:override(false)
        end

        local scope_level = entity.get_prop(wpn, 'm_zoomLevel')
        local scoped = entity.get_prop(me, 'm_bIsScoped') == 1
        local resume_zoom = entity.get_prop(me, 'm_bResumeZoom') == 1
        local is_valid = entity.is_alive(me) and wpn ~= nil and scope_level ~= nil
        local act = enable and is_valid and scope_level > 0 and scoped and not resume_zoom

        local fadetime = fade > 3 and globals.frametime() * fade or 1
        local alpha = mathematic.lerp(lua.render.anims.k, 0, 0.06)

        local x = screen.x / 2
        local y = screen.y / 2

        local scopeda = lua.render.anims.m
        local left_center_x = x - scopeda * position - offset + 1
        local right_center_x = x + offset
        local up_center_y = y - scopeda * position - scopeda * offset
        local down_center_y = y + scopeda * offset

        render.gradient(left_center_x, y, scopeda * position, 1, r, g, b, 0, r, g, b, alpha * a, true)
        render.gradient(left_center_x + scopeda * position + scopeda * offset / 2 - 1, y, - scopeda * offset / 2, 1, r, g, b, 0, r, g, b, alpha * a, true)
        render.gradient(right_center_x, y, scopeda * position, 1, r, g, b, alpha * a, r, g, b, 0, true)
        render.gradient(right_center_x - scopeda * offset / 2, y, scopeda * offset / 2 + 1, 1, r, g, b, 0, r, g, b, alpha * a, true)

        render.gradient(x, up_center_y, 1, scopeda * position + scopeda * 2, r, g, b, 0, r, g, b, alpha * a, false)
        render.gradient(x, up_center_y + scopeda * position + scopeda * offset / 2, 1, - scopeda * offset / 2, r, g, b, 0, r, g, b, alpha * a, false)
        render.gradient(x, down_center_y, 1, scopeda * position, r, g, b, alpha * a, r, g, b, 0, false)
        render.gradient(x, down_center_y - scopeda * offset / 2, 1, scopeda * offset / 2 + 1, r, g, b, 0, r, g, b, alpha * a, false)

        lua.render.anims.k = mathematic.clamp(lua.render.anims.k + (act and fadetime or -fadetime), 0, 1)
    end
    lua.render.lagcomp = {
        esp_data = {},
        sim_ticks = {},
        net_data = {}
    }

    local function lagcomp_time_to_ticks(time)
        return math.floor(0.5 + time / globals.tickinterval())
    end

    local function lagcomp_vec_add(a, b)
        return {a[1] + b[1], a[2] + b[2], a[3] + b[3]}
    end

    local function lagcomp_vec_sub(a, b)
        return {a[1] - b[1], a[2] - b[2], a[3] - b[3]}
    end

    local function lagcomp_vec_length_2d(x, y)
        return x * x + y * y
    end

    local function lagcomp_get_entities(enemy_only, alive_only)
        local players, player_resource = {}, entity.get_player_resource()
        enemy_only = enemy_only ~= nil and enemy_only or false
        alive_only = alive_only ~= nil and alive_only or true

        for player = 1, globals.maxplayers() do
            local valid = true
            if enemy_only and not entity.is_enemy(player) then valid = false end
            if valid and alive_only and player_resource ~= nil and entity.get_prop(player_resource, 'm_bAlive', player) ~= 1 then valid = false end
            if valid then players[#players + 1] = player end
        end

        return players
    end

    local function lagcomp_extrapolate(ent, origin, ticks)
        local tickinterval = globals.tickinterval()
        local gravity = cvar.sv_gravity:get_float() * tickinterval
        local jump_impulse = cvar.sv_jump_impulse:get_float() * tickinterval
        local velocity = {entity.get_prop(ent, 'm_vecVelocity')}

        if velocity[1] == nil then return origin end

        local predicted_origin, previous_origin = origin, origin
        local z_gravity = velocity[3] > 0 and -gravity or jump_impulse

        for i = 1, ticks do
            previous_origin = predicted_origin
            predicted_origin = {
                predicted_origin[1] + velocity[1] * tickinterval,
                predicted_origin[2] + velocity[2] * tickinterval,
                predicted_origin[3] + (velocity[3] + z_gravity) * tickinterval
            }

            local fraction = client.trace_line(-1, previous_origin[1], previous_origin[2], previous_origin[3], predicted_origin[1], predicted_origin[2], predicted_origin[3])
            if fraction <= 0.99 then
                return previous_origin
            end
        end

        return predicted_origin
    end

    lua.render.lagcomp_net_update = function()
        local state = lua.render.lagcomp
        local players = lagcomp_get_entities(true, true)

        for i = 1, #players do
            local idx = players[i]
            local previous_tick = state.sim_ticks[idx]

            if entity.is_dormant(idx) or not entity.is_alive(idx) then
                state.sim_ticks[idx] = nil
                state.net_data[idx] = nil
                state.esp_data[idx] = nil
            else
                local origin = {entity.get_origin(idx)}
                local simulation_time = entity.get_prop(idx, 'm_flSimulationTime')

                if origin[1] ~= nil and simulation_time ~= nil then
                    local simulation_tick = lagcomp_time_to_ticks(simulation_time)

                    if previous_tick ~= nil then
                        local delta = simulation_tick - previous_tick.tick

                        if delta < 0 or delta > 0 and delta <= 64 then
                            local diff_origin = lagcomp_vec_sub(origin, previous_tick.origin)
                            local teleport_distance = lagcomp_vec_length_2d(diff_origin[1], diff_origin[2])
                            local predicted_origin = lagcomp_extrapolate(idx, origin, math.max(delta - 1, 0))

                            if delta < 0 then
                                state.esp_data[idx] = 1
                            end

                            state.net_data[idx] = {
                                tick = delta - 1,
                                origin = origin,
                                predicted_origin = predicted_origin,
                                tickbase = delta < 0,
                                lagcomp = teleport_distance > 4096
                            }
                        end
                    end

                    if state.esp_data[idx] == nil then
                        state.esp_data[idx] = 0
                    end

                    state.sim_ticks[idx] = {
                        tick = simulation_tick,
                        origin = origin
                    }
                end
            end
        end
    end

    local function lagcomp_line_3d(a, b, r, g, bl, alpha)
        local ax, ay = renderer.world_to_screen(a[1], a[2], a[3])
        local bx, by = renderer.world_to_screen(b[1], b[2], b[3])
        if ax ~= nil and bx ~= nil then
            renderer.line(ax, ay, bx, by, r, g, bl, alpha)
        end
    end

    lua.render.lagcomp_paint = function()
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return end

        local box_r, box_g, box_b, box_a = lua.pui.ui.render.lagcomp_box_color:get()
        local text_r, text_g, text_b, text_a = lua.pui.ui.render.lagcomp_text_color:get()
        local state = lua.render.lagcomp

        for idx, net_data in pairs(state.net_data) do
            if entity.is_alive(idx) and entity.is_enemy(idx) and net_data ~= nil then
                if net_data.lagcomp and net_data.predicted_origin ~= nil then
                    local predicted_pos = net_data.predicted_origin
                    local mins = {entity.get_prop(idx, 'm_vecMins')}
                    local maxs = {entity.get_prop(idx, 'm_vecMaxs')}

                    if mins[1] ~= nil and maxs[1] ~= nil then
                        local min = lagcomp_vec_add(mins, predicted_pos)
                        local max = lagcomp_vec_add(maxs, predicted_pos)
                        local points = {
                            {min[1], min[2], min[3]}, {min[1], max[2], min[3]},
                            {max[1], max[2], min[3]}, {max[1], min[2], min[3]},
                            {min[1], min[2], max[3]}, {min[1], max[2], max[3]},
                            {max[1], max[2], max[3]}, {max[1], min[2], max[3]}
                        }
                        local edges = {
                            {1, 2}, {2, 3}, {3, 4}, {4, 1},
                            {5, 6}, {6, 7}, {7, 8}, {8, 5},
                            {1, 5}, {2, 6}, {3, 7}, {4, 8}
                        }

                        local origin = {entity.get_origin(idx)}
                        if origin[1] ~= nil then
                            lagcomp_line_3d(origin, predicted_pos, box_r, box_g, box_b, box_a)
                        end

                        for i = 1, #edges do
                            lagcomp_line_3d(points[edges[i][1]], points[edges[i][2]], box_r, box_g, box_b, box_a)
                        end
                    end
                end

                local x1, y1, x2, y2, alpha = entity.get_bounding_box(idx)
                if x1 ~= nil and alpha > 0 then
                    local esp_alpha = state.esp_data[idx] or 0
                    if esp_alpha > 0 then
                        esp_alpha = esp_alpha - globals.frametime() * 2
                        esp_alpha = esp_alpha < 0 and 0 or esp_alpha
                        state.esp_data[idx] = esp_alpha
                    end

                    local tickbase = net_data.tickbase or esp_alpha > 0
                    local lagcomp = net_data.lagcomp
                    local label = tickbase and 'SHIFTING TICKBASE' or lagcomp and 'LAG COMP BREAKER' or ''

                    if label ~= '' then
                        local name = entity.get_player_name(idx)
                        local y_add = name == '' and -8 or 0
                        local label_alpha = (not tickbase or lagcomp) and alpha or esp_alpha
                        renderer.text(x1 + (x2 - x1) / 2, y1 - 18 + y_add, text_r, text_g, text_b, text_a * label_alpha, 'c', 0, label)
                    end
                end
            end
        end
    end

    function draggable:dmg_indicator()
        local me = entity.get_local_player()
        if not me then return end

        local check = entity.get_player_weapon(me) and weapons(me)
        local valid = check and check.weapon_type_int == 9 and check.weapon_type_int == 0
        if lua.pui.ui.render.panels_select:get('Damage') then
            if lua.reference.rage.binds.minimum_damage_override[1]:get_hotkey() then
                lua.render.anims.n = mathematic.lerp(lua.render.anims.n, 1, 0.06)
            elseif pui.menu_open then
                lua.render.anims.n = mathematic.lerp(lua.render.anims.n, 1, 0.06)
            else
                lua.render.anims.n = mathematic.lerp(lua.render.anims.n, 0.5, 0.06)
            end
        else
            lua.render.anims.n = mathematic.lerp(lua.render.anims.n, 0, 0.06)
        end
        lua.render.anims.p = mathematic.lerp(lua.render.anims.p, lua.reference.rage.binds.minimum_damage_override[1]:get_hotkey() and lua.reference.rage.binds.minimum_damage_override[2].value or lua.reference.rage.binds.minimum_damage:get() + 0.5, 0.06)

        local x, y = self:get_position()
        render.text(x, y, 255, 255, 255, 255 * lua.render.anims.n, '-', 0, math.floor(lua.render.anims.p))
    end

    local draggable_dmg = draggable:new('draggable dmg', screen.x / 2 + 15, screen.y / 2 - 15, 30, 10)

    local initiliaze_dmg = function ()
        draggable_dmg:handle_drag()
        draggable_dmg:dmg_indicator()
    end

    function draggable:watermark()
        local me = entity.get_local_player()
        if not me then return end

        local x, y = self:get_position()
        render.round_rect(x - 2, y - 2, self.width + 4, self.height + 4, 6, 80, 80, 80, 255 * lua.render.anims.a)
        render.round_rect(x - 1, y - 1, self.width + 2, self.height + 2, 6, 37, 37, 37, 255 * lua.render.anims.a)
        render.text(x + 10, y + self.height / 4, 255, 255, 255, 255 * lua.render.anims.a, nil, 0, '✨ Cryonova   Javasense   Developer')
    end

    local draggable_window = draggable:new('draggable watermark', screen.x - 240, 10, 230, 30)

    local initiliaze_watermark = function ()
        draggable_window:handle_drag()
        draggable_window:watermark()
    end

    lua.render.obscuration = function()
        if lua.render.anims.u <= 0.01 then return end
        render.rectangle(0, 0, screen.x, screen.y, 1, 1, 1, 145 * lua.render.anims.u)
    end
    lua.render.watermark = {}
    lua.render.watermark.framerate = 0
    lua.render.watermark.last_framerate = 0
    lua.render.watermark.cpu = {idle = 0, kernel = 0, user = 0, ready = false}
    lua.render.watermark.hardware = {cpu_failed = false, memory_failed = false, frequency_failed = false}

    local function watermark_cdef(definition)
        pcall(ffi.cdef, definition)
    end

    local function watermark_load_library(...)
        for i = 1, select('#', ...) do
            local ok, library = pcall(ffi.load, select(i, ...))
            if ok and library ~= nil then
                return library
            end
        end

        return nil
    end

    watermark_cdef('typedef struct { unsigned long dwLowDateTime; unsigned long dwHighDateTime; } CN_FILETIME;')
    watermark_cdef('typedef struct { unsigned long dwLength; unsigned long dwMemoryLoad; unsigned long long ullTotalPhys; unsigned long long ullAvailPhys; unsigned long long ullTotalPageFile; unsigned long long ullAvailPageFile; unsigned long long ullTotalVirtual; unsigned long long ullAvailVirtual; unsigned long long ullAvailExtendedVirtual; } CN_MEMORYSTATUSEX;')
    watermark_cdef('int __stdcall GetSystemTimes(CN_FILETIME* lpIdleTime, CN_FILETIME* lpKernelTime, CN_FILETIME* lpUserTime);')
    watermark_cdef('int __stdcall GlobalMemoryStatusEx(CN_MEMORYSTATUSEX* lpBuffer);')
    watermark_cdef('typedef struct { unsigned long Number; unsigned long MaxMhz; unsigned long CurrentMhz; unsigned long MhzLimit; unsigned long MaxIdleState; unsigned long CurrentIdleState; } CN_PROCESSOR_POWER_INFORMATION;')
    watermark_cdef('long __stdcall CallNtPowerInformation(int InformationLevel, void* InputBuffer, unsigned long InputBufferLength, void* OutputBuffer, unsigned long OutputBufferLength);')
    watermark_cdef('typedef void* CN_PDH_HQUERY; typedef void* CN_PDH_HCOUNTER; typedef unsigned long CN_DWORD; typedef unsigned long CN_DWORD_PTR;')
    watermark_cdef('typedef struct { CN_DWORD CStatus; double doubleValue; } CN_PDH_FMT_COUNTERVALUE_DOUBLE;')
    watermark_cdef('typedef struct { char* szName; CN_PDH_FMT_COUNTERVALUE_DOUBLE FmtValue; } CN_PDH_FMT_COUNTERVALUE_ITEM_A;')
    watermark_cdef('long __stdcall PdhOpenQueryA(const char* szDataSource, CN_DWORD_PTR dwUserData, CN_PDH_HQUERY* phQuery);')
    watermark_cdef('long __stdcall PdhAddEnglishCounterA(CN_PDH_HQUERY hQuery, const char* szFullCounterPath, CN_DWORD_PTR dwUserData, CN_PDH_HCOUNTER* phCounter);')
    watermark_cdef('long __stdcall PdhAddCounterA(CN_PDH_HQUERY hQuery, const char* szFullCounterPath, CN_DWORD_PTR dwUserData, CN_PDH_HCOUNTER* phCounter);')
    watermark_cdef('long __stdcall PdhCollectQueryData(CN_PDH_HQUERY hQuery);')
    watermark_cdef('long __stdcall PdhGetFormattedCounterArrayA(CN_PDH_HCOUNTER hCounter, CN_DWORD dwFormat, CN_DWORD* lpdwBufferSize, CN_DWORD* lpdwItemCount, CN_PDH_FMT_COUNTERVALUE_ITEM_A* ItemBuffer);')
    watermark_cdef('long __stdcall PdhGetFormattedCounterValue(CN_PDH_HCOUNTER hCounter, CN_DWORD dwFormat, CN_DWORD* lpdwType, CN_PDH_FMT_COUNTERVALUE_DOUBLE* pValue);')
    watermark_cdef('long __stdcall PdhCloseQuery(CN_PDH_HQUERY hQuery);')

    local kernel32 = watermark_load_library('kernel32.dll', 'kernel32')
    local powrprof = watermark_load_library('powrprof.dll', 'powrprof')
    local pdh = watermark_load_library('pdh.dll', 'pdh')

    local watermark_get_net_channel_info = nil
    pcall(function()
        watermark_get_net_channel_info = vmt_bind('engine.dll', 'VEngineClient014', 78, 'void*(__thiscall*)(void*)')
    end)

    local function watermark_netchannel_call(nci, index, typestring, ...)
        if nci == nil then
            return nil
        end

        local ok_type, ctype = pcall(ffi.typeof, typestring)
        if not ok_type then
            return nil
        end

        local ok_entry, fn = pcall(vmt_entry, nci, index, ctype)
        if not ok_entry or fn == nil then
            return nil
        end

        local ok_call, result = pcall(fn, nci, ...)
        if not ok_call then
            return nil
        end

        return result == nil and true or result
    end

    local function watermark_netchannel()
        if watermark_get_net_channel_info == nil then
            return nil
        end

        local ok, nci = pcall(watermark_get_net_channel_info)
        return ok and nci or nil
    end

    local function watermark_has(item)
        return lua.pui.ui.render.watermark_items:get(item)
    end

    local function watermark_fps()
        lua.render.watermark.framerate = 0.9 * lua.render.watermark.framerate + 0.1 * globals.absoluteframetime()
        lua.render.watermark.last_framerate = lua.render.watermark.framerate > 0 and lua.render.watermark.framerate or globals.absoluteframetime()
        return math.floor(1 / lua.render.watermark.last_framerate)
    end

    local function watermark_filetime_value(filetime)
        return tonumber(filetime.dwHighDateTime) * 4294967296 + tonumber(filetime.dwLowDateTime)
    end

    local function watermark_cpu_load()
        if not kernel32 or lua.render.watermark.hardware.cpu_failed then
            return 'cpu n/a'
        end

        local idle = ffi.new('CN_FILETIME[1]')
        local kernel = ffi.new('CN_FILETIME[1]')
        local user = ffi.new('CN_FILETIME[1]')
        local ok, result = pcall(function()
            return kernel32.GetSystemTimes(idle, kernel, user)
        end)
        if not ok or not result then
            lua.render.watermark.hardware.cpu_failed = true
            return 'cpu n/a'
        end

        local idle_time = watermark_filetime_value(idle[0])
        local kernel_time = watermark_filetime_value(kernel[0])
        local user_time = watermark_filetime_value(user[0])
        local cpu = lua.render.watermark.cpu

        if not cpu.ready then
            cpu.idle, cpu.kernel, cpu.user, cpu.ready = idle_time, kernel_time, user_time, true
            return 'cpu 0%'
        end

        local idle_delta = idle_time - cpu.idle
        local total_delta = (kernel_time - cpu.kernel) + (user_time - cpu.user)
        cpu.idle, cpu.kernel, cpu.user = idle_time, kernel_time, user_time

        if total_delta <= 0 then
            return 'cpu 0%'
        end

        return string.format('cpu %d%%', mathematic.clamp(math.floor((1 - idle_delta / total_delta) * 100), 0, 100))
    end

    local function watermark_memory_load()
        if not kernel32 or lua.render.watermark.hardware.memory_failed then
            return 'mem n/a'
        end

        local memory = ffi.new('CN_MEMORYSTATUSEX[1]')
        memory[0].dwLength = ffi.sizeof(memory[0])
        local ok, result = pcall(function()
            return kernel32.GlobalMemoryStatusEx(memory)
        end)
        if not ok or not result then
            lua.render.watermark.hardware.memory_failed = true
            return 'mem n/a'
        end

        return string.format('mem %d%%', memory[0].dwMemoryLoad)
    end

    local function watermark_kd(me)
        local resource = entity.get_player_resource(me)
        local kills = resource ~= nil and entity.get_prop(resource, 'm_iKills', me) or entity.get_prop(me, 'm_iKills')
        local deaths = resource ~= nil and entity.get_prop(resource, 'm_iDeaths', me) or entity.get_prop(me, 'm_iDeaths')

        kills = kills or 0
        deaths = deaths or 0
        return string.format('kd %.2f', kills / math.max(deaths, 1))
    end

    local function watermark_speed(me)
        local vx, vy = entity.get_prop(me, 'm_vecVelocity')
        if vx == nil or vy == nil then
            return '0 u/s'
        end
        return string.format('%d u/s', math.floor(math.sqrt(vx * vx + vy * vy)))
    end

    local function watermark_time()
        local hours, minutes = client.system_time()
        return string.format('%02d:%02d', hours or 0, minutes or 0)
    end

    local function watermark_ping()
        local nci = watermark_netchannel()
        local latency = watermark_netchannel_call(nci, 9, 'float(__thiscall*)(void*, int)', 0) or client.latency()
        return string.format('%d ms', math.max(0, latency) * 1000)
    end

    local function watermark_server()
        local nci = watermark_netchannel()
        local address = watermark_netchannel_call(nci, 1, 'const char*(__thiscall*)(void*)')
        if address ~= nil then
            local ok, text = pcall(ffi.string, address)
            if ok and text ~= nil and #text > 0 then
                return text
            end
        end

        if globals.mapname ~= nil then
            local ok, map = pcall(globals.mapname)
            if ok and map ~= nil then
                return map
            end
        end

        return 'offline'
    end

    local function watermark_var()
        local nci = watermark_netchannel()
        local frame_time = ffi.new('float[1]')
        local frame_time_std = ffi.new('float[1]')
        local frame_start_std = ffi.new('float[1]')
        local result = watermark_netchannel_call(nci, 25, 'void(__thiscall*)(void*, float*, float*, float*)', frame_time, frame_time_std, frame_start_std)

        if result ~= nil and frame_start_std[0] > 0 then
            return string.format('var %.1f ms', frame_start_std[0] * 1000)
        end

        return string.format('var %.1f ms', globals.absoluteframetime() * 1000)
    end

    local function watermark_loss()
        local nci = watermark_netchannel()
        local loss = watermark_netchannel_call(nci, 11, 'float(__thiscall*)(void*, int)', 0) or 0
        return string.format('loss %.1f%%', mathematic.clamp(loss * 100, 0, 100))
    end

    local function watermark_connectivity()
        local nci = watermark_netchannel()
        local timing_out = watermark_netchannel_call(nci, 7, 'bool(__thiscall*)(void*)')
        local loss = watermark_netchannel_call(nci, 11, 'float(__thiscall*)(void*, int)', 0) or 0
        local latency = watermark_netchannel_call(nci, 9, 'float(__thiscall*)(void*, int)', 0) or client.latency()

        return (timing_out or loss > 0.02 or latency > 0.2) and 'connection unstable' or 'connection ok'
    end

    local function watermark_cpu_frequency()
        if not powrprof or lua.render.watermark.hardware.frequency_failed then
            return 'cpu freq unavailable'
        end

        local processors = ffi.new('CN_PROCESSOR_POWER_INFORMATION[64]')
        local size = ffi.sizeof(processors)
        local ok, status = pcall(function()
            return powrprof.CallNtPowerInformation(11, nil, 0, processors, size)
        end)
        if not ok or status ~= 0 then
            lua.render.watermark.hardware.frequency_failed = true
            return 'cpu freq unavailable'
        end

        local total, count = 0, 0
        for i = 0, 63 do
            if processors[i].CurrentMhz > 0 then
                total = total + processors[i].CurrentMhz
                count = count + 1
            end
        end

        if count == 0 then
            return 'cpu freq unavailable'
        end

        return string.format('cpu %.2f ghz', total / count / 1000)
    end

    lua.render.watermark.gpu = {query = nil, counter = nil, mode = 'array', ready = false, failed = false}
    local function watermark_gpu_load()
        if not pdh or lua.render.watermark.gpu.failed then
            return 'gpu unavailable'
        end

        local gpu = lua.render.watermark.gpu
        if not gpu.ready then
            local query = ffi.new('CN_PDH_HQUERY[1]')
            local counter = ffi.new('CN_PDH_HCOUNTER[1]')
            local total_counter = ffi.new('CN_PDH_HCOUNTER[1]')
            local ok_open, open_status = pcall(function()
                return pdh.PdhOpenQueryA(nil, 0, query)
            end)
            local opened = ok_open and open_status == 0 and query[0] ~= nil
            local added = false

            local ok_add, add_status = opened and pcall(function()
                return pdh.PdhAddEnglishCounterA(query[0], '\\GPU Engine(*)\\Utilization Percentage', 0, counter)
            end)
            if opened and ok_add and add_status == 0 and counter[0] ~= nil then
                added = true
                gpu.mode = 'array'
            else
                ok_add, add_status = opened and pcall(function()
                    return pdh.PdhAddEnglishCounterA(query[0], '\\GPU Engine(_Total)\\Utilization Percentage', 0, total_counter)
                end)
            end

            if not added and opened and ok_add and add_status == 0 and total_counter[0] ~= nil then
                counter[0] = total_counter[0]
                added = true
                gpu.mode = 'single'
            elseif not added then
                ok_add, add_status = opened and pcall(function()
                    return pdh.PdhAddCounterA(query[0], '\\GPU Engine(*)\\Utilization Percentage', 0, counter)
                end)
            end

            if not added and opened and ok_add and add_status == 0 and counter[0] ~= nil then
                added = true
                gpu.mode = 'array'
            end

            if not opened or not added then
                if query[0] ~= nil then
                    pcall(function() return pdh.PdhCloseQuery(query[0]) end)
                end
                gpu.failed = true
                return 'gpu unavailable'
            end

            gpu.query = query[0]
            gpu.counter = counter[0]
            gpu.ready = true
            pcall(function() return pdh.PdhCollectQueryData(gpu.query) end)
            return 'gpu 0%'
        end

        local ok_collect, collect_status = pcall(function()
            return pdh.PdhCollectQueryData(gpu.query)
        end)
        if not ok_collect or collect_status ~= 0 then
            return 'gpu unavailable'
        end

        if gpu.mode == 'single' then
            local value = ffi.new('CN_PDH_FMT_COUNTERVALUE_DOUBLE[1]')
            local value_type = ffi.new('CN_DWORD[1]', 0)
            local ok_value = pcall(function()
                return pdh.PdhGetFormattedCounterValue(gpu.counter, 0x00000200, value_type, value)
            end)
            if not ok_value or value[0].CStatus ~= 0 then
                return 'gpu unavailable'
            end

            return string.format('gpu %d%%', mathematic.clamp(math.floor(value[0].doubleValue), 0, 100))
        end

        local buffer_size = ffi.new('CN_DWORD[1]', 0)
        local item_count = ffi.new('CN_DWORD[1]', 0)
        pcall(function()
            return pdh.PdhGetFormattedCounterArrayA(gpu.counter, 0x00000200, buffer_size, item_count, nil)
        end)
        if buffer_size[0] == 0 or item_count[0] == 0 then
            return 'gpu 0%'
        end

        local items = ffi.new('uint8_t[?]', buffer_size[0])
        local formatted = ffi.cast('CN_PDH_FMT_COUNTERVALUE_ITEM_A*', items)
        local ok_array, array_status = pcall(function()
            return pdh.PdhGetFormattedCounterArrayA(gpu.counter, 0x00000200, buffer_size, item_count, formatted)
        end)
        if not ok_array or array_status ~= 0 then
            return 'gpu unavailable'
        end

        local total = 0
        for i = 0, tonumber(item_count[0]) - 1 do
            if formatted[i].FmtValue.CStatus == 0 then
                total = total + formatted[i].FmtValue.doubleValue
            end
        end

        return string.format('gpu %d%%', mathematic.clamp(math.floor(total), 0, 100))
    end

    local function watermark_mode_one()
        local me = entity.get_local_player()
        if not me then return end

        local text = 'CRYONOVA'
        local text_xy = vector(render.measure_text('-', text))
        render.text(screen.x / 2 - text_xy.x / 2, screen.y - 15, 255, 255, 255, 255 * lua.render.anims.a, '-', 0, text)
    end

    local function watermark_mode_two_render()
        local me = entity.get_local_player()
        if not me then return end

        local parts = {}
        if watermark_has('Logo') then parts[#parts + 1] = 'CRYONOVA' end
        if watermark_has('KD Ratio') then parts[#parts + 1] = watermark_kd(me) end
        if watermark_has('Speed') then parts[#parts + 1] = watermark_speed(me) end
        if watermark_has('Framerate') then parts[#parts + 1] = string.format('%d fps', watermark_fps()) end
        if watermark_has('Latency') then parts[#parts + 1] = watermark_ping() end
        if watermark_has('Var') then parts[#parts + 1] = watermark_var() end
        if watermark_has('Loss') then parts[#parts + 1] = watermark_loss() end
        if watermark_has('Connectivity Issues') then parts[#parts + 1] = watermark_connectivity() end
        if watermark_has('Server Address') then parts[#parts + 1] = watermark_server() end
        if watermark_has('Preset') then parts[#parts + 1] = lua.pui.ui.search.tab:get() end
        if watermark_has('Username') then parts[#parts + 1] = entity.get_player_name(me) or 'local' end
        if watermark_has('Time') then parts[#parts + 1] = watermark_time() end

        if #parts == 0 then
            parts[#parts + 1] = 'CRYONOVA'
       end

        local text = table.concat(parts, ' | ')
        local flags = ''
        local text_xy = vector(render.measure_text(flags, text))
        local x, y = screen.x / 2 - text_xy.x / 2, screen.y - 28
        render.text(x + 1, y + 1, 0, 0, 0, 180 * lua.render.anims.a, flags, 0, text)
        render.text(x, y, 255, 255, 255, 255 * lua.render.anims.a, flags, 0, text)
    end

    local render_watermark = function()
        if lua.pui.ui.render.watermark_mode:get() == 'Mode 1' then
            watermark_mode_one()
        else
            watermark_mode_two_render()
        end
    end

    local watermark = render_watermark

    lua.pui.ui.render.panels_select:set_event('paint_ui', lua.render.obscuration, function (this)
        return this:get('Obscuration')
    end)

    lua.pui.ui.render.panels_select:set_event('paint_ui', initiliaze_indicator, function (this)
        return this:get('Indicator')
    end)

    lua.pui.ui.render.panels_select:set_event('paint_ui', lua.render.hitmarker, function (this)
        return this:get('Hitmarker')
    end)

    --lua.pui.ui.render.panels_select:set_event('paint_ui', initiliaze_watermark, function (this)
    --    return this:get('Watermark')
    --end)

    lua.pui.ui.render.panels_select:set_event('paint_ui', watermark, function (this)
        return this:get('Watermark')
    end)

    lua.pui.ui.render.panels_select:set_event('paint_ui', initiliaze_dmg, function (this)
        return this:get('Damage')
    end)

    --lua.pui.ui.render.panels_select:set_event('paint_ui', initiliaze_keybinds, function (this)
    --    return this:get('Binds')
    --end)

    lua.pui.ui.render.panels_select:set_event('net_update_end', lua.render.lagcomp_net_update, function (this)
        return this:get('Lag comp box')
    end)

    lua.pui.ui.render.panels_select:set_event('paint', lua.render.lagcomp_paint, function (this)
        return this:get('Lag comp box')
    end)

    lua.pui.ui.world.world_manager:set_event('paint', lua.render.custom_scope, function (this)
        return this:get('View changer')
    end)

    lua.pui.ui.additive.other:set_event('paint', lua.render.dragapf, function (this)
        return this:get('Razpeek')
    end)

    lua.pui.ui.additive.other:set_event('paint', lua.yandex.draw, function (this)
        return this:get('Yandex Music')
    end)

    client.set_event_callback('paint_ui', function ()
        lua.reference.visuals.effects.scope:override(true)
        lua.render.interpfuncs()
        lua.reference.hide(false)
    end)

    lua.reference.init()
end
--#endregion

--#region anti-crasher
local CS_UM_SendPlayerItemFound = 63
local DispatchUserMessage_t = ffi.typeof [[ bool(__thiscall*)(void*, int msg_type, int nFlags, int size, const void* msg)
]]

local VClient018 = client.create_interface('client.dll', 'VClient018')
local pointer = ffi.cast('uintptr_t**', VClient018)
local vtable = ffi.cast('uintptr_t*', pointer[0])
local size = 0
while vtable[size] ~= 0x0 do
   size = size + 1
end

local hooked_vtable = ffi.new('uintptr_t[?]', size)
for i = 0, size - 1 do
    hooked_vtable[i] = vtable[i]
end

pointer[0] = hooked_vtable
local oDispatch = ffi.cast(DispatchUserMessage_t, vtable[38])
local function hkDispatch(thisptr, msg_type, nFlags, size, msg)
    if msg_type == CS_UM_SendPlayerItemFound then
        return false
    end

    return oDispatch(thisptr, msg_type, nFlags, size, msg)
end

client.set_event_callback('shutdown', function()
    hooked_vtable[38] = vtable[38]
    pointer[0] = vtable
end)
hooked_vtable[38] = ffi.cast('uintptr_t', ffi.cast(DispatchUserMessage_t, hkDispatch))
--#endregion

--#region lua.cvar, lua.world
cvar.weapon_accuracy_forcespread:set_raw_float(0)
cvar.sv_airaccelerate:set_raw_float(100)
lua.cvar = {} lua.world = {} do
    lua.cvar.console_filter = {
        cached = false,
        enable = 0,
        text = '',
        text_out = ''
    }

    local function get_cvar_string(ref)
        local ok, value = pcall(function() return ref:get_string() end)
        return ok and value or ''
    end

    local function set_cvar_int(ref, value)
        pcall(function() ref:set_int(value) end)
    end

    local function set_cvar_string(ref, value)
        pcall(function() ref:set_string(value) end)
    end

    local function set_console_filter(enable)
        if enable then
            if not lua.cvar.console_filter.cached then
                lua.cvar.console_filter.cached = true
                lua.cvar.console_filter.enable = cvar.con_filter_enable:get_int()
                lua.cvar.console_filter.text = get_cvar_string(cvar.con_filter_text)
                lua.cvar.console_filter.text_out = get_cvar_string(cvar.con_filter_text_out)
            end
            set_cvar_int(cvar.con_filter_enable, 1)
            set_cvar_string(cvar.con_filter_text, 'Cryonova')
            set_cvar_string(cvar.con_filter_text_out, '')
        elseif lua.cvar.console_filter.cached then
            set_cvar_int(cvar.con_filter_enable, lua.cvar.console_filter.enable)
            set_cvar_string(cvar.con_filter_text, lua.cvar.console_filter.text)
            set_cvar_string(cvar.con_filter_text_out, lua.cvar.console_filter.text_out)
            lua.cvar.console_filter.cached = false
        end
    end

    lua.cvar.console_filter_on = function()
        set_console_filter(lua.pui.ui.additive.other:get('Console filter'))
    end

    lua.world.me_sharing = function (cmd)
        local me = entity.get_local_player()
        local iTicksAllowed = lua.helps.exploits.get_maximum_usrcmd_ticks(14)
        local flags = entity.get_prop(me, 'm_fFlags')
        if lua.reference.visuals.effects.thirdperson[1].hotkey:get() == false then return end
        lua.render.anims.e = mathematic.lerp(lua.render.anims.e, (cmd.chokedcommands == 10 or lua.helps.exploits.defensive() > 13) and 1 or 0, 0.025)
        local r, g, b = lua.pui.ui.world.me_sharingcol:get()
        if lua.pui.ui.world.me_sharing:get() == 'Dragging' then
            client.draw_hitboxes(me, globals.tickinterval() * iTicksAllowed * lua.render.anims.b, 
            255 * lua.render.anims.b, r * lua.render.anims.b, g * lua.render.anims.b, b * lua.render.anims.b, 255 * lua.render.anims.e)
        else
            if cmd.chokedcommands == 10 or lua.helps.exploits.defensive() > 13 then
                client.draw_hitboxes(me, globals.tickinterval() * iTicksAllowed * lua.render.anims.b, 
                255 * lua.render.anims.b, r * lua.render.anims.b, g * lua.render.anims.b, b * lua.render.anims.b, 255 * lua.render.anims.b)
            end
        end
    end

    lua.pui.ui.world.world_manager:set_event('setup_command', lua.world.me_sharing, function (this)
        return this:get('Local Sharing')
    end)

    lua.world.hands_drag = function ()
        cvar.viewmodel_fov:set_raw_float(lua.pui.ui.world.hand_fov:get())
        cvar.viewmodel_offset_x:set_raw_float(lua.pui.ui.world.hand_x:get() * 0.01)
        cvar.viewmodel_offset_y:set_raw_float(lua.pui.ui.world.hand_y:get() * 0.01)
        cvar.viewmodel_offset_z:set_raw_float(lua.pui.ui.world.hand_z:get() * 0.01)
    end
lua.world.aspectratio = function ()
        local aspect = lua.pui.ui.world.aspectratio:get()
        lua.render.anims.y = mathematic.lerp(lua.render.anims.y, aspect * 0.01, 0.035)
        cvar.r_aspectratio:set_float(aspect ~= 0.0 and lua.render.anims.y or 0)
    end

    lua.pui.ui.world.world_manager:set_event('paint', lua.world.aspectratio, function (this)
        return this:get('View changer')
    end)

    lua.pui.ui.world.world_manager:set_event('paint', lua.world.hands_drag, function (this)
        return this:get('Viewmodel')
    end)

    lua.world.zoom = function (z)
        local me = entity.get_local_player()
        if not lua.pui.ui.world.zoom_scale:get() then return end
        local offset = lua.pui.ui.world.zoom_offset:get()
        local wpn = entity.get_player_weapon(me)
        if not wpn then return end
        local scope_level = entity.get_prop(wpn, 'm_zoomLevel')
        local scoped = entity.get_prop(me, 'm_bIsScoped') == 1
        local act = 0
        if scoped then
            if scope_level == 1 then
                act = 1
            else
                act = 2
            end
        else
            act = 0
        end
        lua.render.anims.z = mathematic.lerp(lua.render.anims.z, scoped and act or 0, 0.06)

        z.fov = z.fov - offset * lua.render.anims.z
    end

    lua.pui.ui.world.world_manager:set_event('override_view', lua.world.zoom, function (this)
        return this:get('View changer')
    end)

    lua.cvar.clantag_list = {
        ena = false,
        en = 0,
        cl = {
            'c',
            'cr',
            'cry',
            'cryo',
            'cryon',
            'cryono',
            'cryonov',
            'cryonova',
            'cryonova',
            'cryo nova',
            'cryo|nova',
            'cryo/nova',
            'cry0nova',
            'cryon0va',
            'cryonova',
            'cryonova',
            'cryonov',
            'cryono',
            'cryon',
            'cryo',
            'cry',
            'cr',
            'c',
            ''
        }

    }

    lua.cvar.clantag = function ()
        if lua.cvar.clantag_list.ena and not lua.pui.ui.additive.other:get('Clantag') then
			lua.cvar.clantag_list.ena = false
			client.unset_event_callback('net_update_end', lua.cvar.clantag)
			client.set_clan_tag()
		end

        local time = math.floor(globals.curtime() * 4 + 0.5)
		local i = time % #lua.cvar.clantag_list.cl + 1

		if i == lua.cvar.clantag_list.en then return end
		lua.cvar.clantag_list.en = i

		client.set_clan_tag(lua.cvar.clantag_list.cl[i])
    end

    lua.cvar.clantag_on = function ()
		lua.pui.ui.additive.other:set_callback(function (this)
            lua.cvar.console_filter_on()
            lua.reference.visuals.effects.clantag:set_enabled(not this:get('Clantag'))

			if this:get('Clantag') then
				lua.cvar.clantag_list.ena = true
				client.set_event_callback('net_update_end', lua.cvar.clantag)
				lua.reference.visuals.effects.clantag:override(false)
			else
				lua.reference.visuals.effects.clantag:override()
				client.set_clan_tag()
			end
		end, true)
		defer(function ()
            set_console_filter(false)
			lua.reference.visuals.effects.clantag:set_enabled(true)
			lua.reference.visuals.effects.clantag:override()
			client.set_clan_tag()
		end)
    end
    lua.cvar.clantag_on()
end
--#endregion

--#region lua.hitsound 
lua.hitsound = {} do
    lua.hitsound.hurt = function (k)
        if not lua.pui.ui.additive.sounds_check:get() then return end
        local me = entity.get_local_player()
        local attacker_id = client.userid_to_entindex(k.attacker)
		if attacker_id == nil or attacker_id ~= me then
			return
		end

        local sound_file = lua.sounds.sound_name_to_file[lua.pui.ui.additive.sounds_list:get()]
        lua.sounds.play(sound_file, false)
    end

    lua.pui.ui.additive.other:set_event('player_hurt', lua.hitsound.hurt, function (this)
        return this:get('Sounds')
    end)
end
--#endregion

--#region lua.createmove
lua.createmove = {} do
lua.createmove.enabled = false
lua.createmove.start_time = globals.realtime()
lua.createmove.use_enable = function (cmd)
    lua.createmove.enabled = false

    if not lua.pui.ui.conditions['Using'].override:get() then
        return
    end

    if cmd.in_use == 0 then
        lua.createmove.start_time = globals.realtime()
        return
    end

    local player = entity.get_local_player()

    if player == nil then
        return
    end

    local player_origin = { entity.get_origin(player) }
	
    local CPlantedC4 = entity.get_all('CPlantedC4')
    local dist_to_bomb = 999

    if #CPlantedC4 > 0 then
        local bomb = CPlantedC4[1]
        local bomb_origin = { entity.get_origin(bomb) }

        dist_to_bomb = vector(player_origin[1], player_origin[2], player_origin[3]):dist(vector(bomb_origin[1], bomb_origin[2], bomb_origin[3]))
    end

    local CHostage = entity.get_all('CHostage')
    local dist_to_hostage = 999

    if CHostage ~= nil then
        if #CHostage > 0 then
            local hostage_origin = {entity.get_origin(CHostage[1])}

            dist_to_hostage = math.min(vector(player_origin[1], player_origin[2], player_origin[3]):dist(vector(hostage_origin[1], hostage_origin[2], hostage_origin[3])), vector(player_origin[1], player_origin[2], player_origin[3]):dist(vector(hostage_origin[1], hostage_origin[2], hostage_origin[3])))
        end
    end

    if dist_to_hostage < 65 and entity.get_prop(player, 'm_iTeamNum') ~= 2 then
        return
    end

    if dist_to_bomb < 65 and entity.get_prop(player, 'm_iTeamNum') ~= 2 then
        return
    end

    if cmd.in_use then
        if globals.realtime() - lua.createmove.start_time < 0.02 then
            return
        end
    end

    cmd.in_use = false
    lua.createmove.enabled = true
end

lua.createmove.get_state = function ()
    local me = entity.get_local_player()
    if not me then
        return 'Regular'
    end

    local first_velocity, second_velocity = entity.get_prop(me, 'm_vecVelocity')
    lua.createmove.speed = math.floor(math.sqrt(first_velocity*first_velocity+second_velocity*second_velocity))

    if entity.get_prop(me, 'm_hGroundEntity') == 0 then
        lua.pui.ticks = lua.pui.ticks + 1
    else
        lua.pui.ticks = 0
    end

    lua.createmove.onground = lua.pui.ticks >= 32

    if lua.createmove.enabled and lua.pui.ui.conditions['Using'].override:get() then
        return 'Using'
    end

    if lua.createmove.selected_manual == 1 then
        return 'Manual Left'
    end

    if lua.createmove.selected_manual == 2 then
        return 'Manual Right'
    end

    if lua.createmove.selected_manual == 3 then
        return 'Manual Back'
    end

    if lua.createmove.selected_manual == 4 then
        return 'Manual Forward'
    end

    if lua.pui.ui.antiaim.freestand:get() and lua.pui.ui.conditions['Freestand'].override:get() then
        return 'Freestand'
    end

    if not lua.createmove.onground then
        if entity.get_prop(me, 'm_flDuckAmount') == 1 and lua.pui.ui.conditions['Aerobic+'].override:get() then
            return 'Aerobic+'
        end

        return 'Aerobic'
    end

    if entity.get_prop(me, 'm_flDuckAmount') == 1 then
        if lua.createmove.speed > 5 and lua.pui.ui.conditions['Сreeping'].override:get() then
            return 'Сreeping'
        end

        return 'Crouch'
    end

    if lua.reference.antiaim.other.slide[1].hotkey:get() and lua.pui.ui.conditions['Crawling'].override:get() then
        return 'Crawling'
    end

    if lua.createmove.speed > 5 then
        return 'Push'
    end

    return 'Numb'
end

lua.createmove.set_invert = false
lua.createmove.set_tick = 0
lua.createmove.get_invert = function (ref, cmd)
    local me = entity.get_local_player()
    if not me then return end

    if globals.tickcount() > lua.createmove.set_tick + ref then
        if cmd.chokedcommands == 0 then
            lua.createmove.set_invert = not lua.createmove.set_invert
            lua.createmove.set_tick = globals.tickcount()
        end
    end

    if globals.tickcount() < lua.createmove.set_tick then
        lua.createmove.set_tick = globals.tickcount()
    end

    return lua.createmove.set_invert
end

lua.createmove.fast_ladder = function(cmd)
    if not lua.pui.ui.additive.other:get('Fast Ladder') then return end
    local me = entity.get_local_player()
    if not me then return end

    local move_type = entity.get_prop(me, 'm_MoveType')
    local weapon = entity.get_player_weapon(me)
    local throw = entity.get_prop(weapon, 'm_fThrowTime')

    if move_type ~= 9 then
        return
    end

    if weapon == nil then
        return
    end

    if throw ~= nil and throw ~= 0 then
        return
    end

    if cmd.forwardmove > 0 then
        if cmd.pitch < 45 then
            cmd.pitch = 89
            cmd.in_moveright = 1
            cmd.in_moveleft = 0
            cmd.in_forward = 0
            cmd.in_back = 1

            if cmd.sidemove == 0 then
                cmd.yaw = cmd.yaw + 90
            end

            if cmd.sidemove < 0 then
                cmd.yaw = cmd.yaw + 150
            end

            if cmd.sidemove > 0 then
                cmd.yaw = cmd.yaw + 30
            end
        end
    elseif cmd.forwardmove < 0 then
        cmd.pitch = 89
        cmd.in_moveleft = 1
        cmd.in_moveright = 0
        cmd.in_forward = 1
        cmd.in_back = 0

        if cmd.sidemove == 0 then
            cmd.yaw = cmd.yaw + 90
        end

        if cmd.sidemove > 0 then
            cmd.yaw = cmd.yaw + 150
        end

        if cmd.sidemove < 0 then
            cmd.yaw = cmd.yaw + 30
        end
    end
end

lua.createmove.manual = function()
    lua.pui.ui.antiaim.manuall:set('On hotkey')
    lua.pui.ui.antiaim.manualr:set('On hotkey')
    lua.pui.ui.antiaim.manualb:set('On hotkey')
    lua.pui.ui.antiaim.manualf:set('On hotkey')
    lua.pui.ui.antiaim.manualsr:set('On hotkey')

    if not lua.pui.ui.antiaim.manuals:get() then
        lua.createmove.selected_manual = 0
        return
    end

    if lua.createmove.selected_manual == nil then
        lua.createmove.selected_manual = 0
    end

    local left_pressed = lua.pui.ui.antiaim.manuall:get()
    if left_pressed and not lua.createmove.left_pressed then
        if lua.createmove.selected_manual == 1 then
            lua.createmove.selected_manual = 0
        else
            lua.createmove.selected_manual = 1
        end
    end

    local right_pressed = lua.pui.ui.antiaim.manualr:get()
    if right_pressed and not lua.createmove.right_pressed then
        if lua.createmove.selected_manual == 2 then
            lua.createmove.selected_manual = 0
        else
            lua.createmove.selected_manual = 2
        end
    end

    local back_pressed = lua.pui.ui.antiaim.manualb:get()
    if back_pressed and not lua.createmove.back_pressed then
        if lua.createmove.selected_manual == 3 then
            lua.createmove.selected_manual = 0
        else
            lua.createmove.selected_manual = 3
        end
    end

    local forward_pressed = lua.pui.ui.antiaim.manualf:get()
    if forward_pressed and not lua.createmove.forward_pressed then
        if lua.createmove.selected_manual == 4 then
            lua.createmove.selected_manual = 0
        else
            lua.createmove.selected_manual = 4
        end
    end

    local reset_pressed = lua.pui.ui.antiaim.manualsr:get()
    if reset_pressed and not lua.createmove.reset_pressed then
        if lua.createmove.selected_manual == 5 then
            lua.createmove.selected_manual = 5
        else
            lua.createmove.selected_manual = 0
        end
    end

    lua.createmove.left_pressed = left_pressed
    lua.createmove.right_pressed = right_pressed
    lua.createmove.back_pressed = back_pressed
    lua.createmove.forward_pressed = forward_pressed
    lua.createmove.reset_pressed = reset_pressed
end

lua.createmove.freestand = function()
    local state = lua.createmove.get_state()
    if not lua.pui.ui.conditions[state].override:get() then
        state = 'Regular'
    end

    local fs = lua.pui.ui.antiaim.freestand:get()
    if lua.createmove.selected_manual ~= 0 then
        fs = false
    end

    if lua.helps.exploits.defensive() > lua.pui.ui.conditions[state].defensive_minus:get() and 
    lua.helps.exploits.defensive() < lua.pui.ui.conditions[state].defensive_plus:get() and 
        lua.pui.ui.conditions[state].defensive_aa_on:get() and
        lua.pui.ui.conditions[state].defensive:get() ~= 'Off' then

        lua.reference.antiaim.angles.freestanding.hotkey:set('always on')
        lua.reference.antiaim.angles.freestanding:set(false)
    else
        lua.reference.antiaim.angles.freestanding.hotkey:set('always on')
        lua.reference.antiaim.angles.freestanding:set(fs)
    end
end

lua.createmove.spray = 0
lua.createmove.spin = 0
lua.createmove.builder = function (cmd)
    local me = entity.get_local_player()
    if not me then return end

    local state = lua.createmove.get_state()

    if not lua.pui.ui.conditions[state].override:get() then
        state = 'Regular'
    end

    local yaw_da = 0
    local delay = lua.pui.ui.conditions[state].lby:get() == 'Random Ticks' and client.random_int(lua.pui.ui.conditions[state].tick:get(), lua.pui.ui.conditions[state].tick:get() * 5) or lua.pui.ui.conditions[state].tick:get()
    local invert = lua.createmove.get_invert(delay, cmd)

    local direction_freestand = lua.helps.exploits.get_freestand_direction(me)

    local def_pitch = lua.pui.ui.conditions[state].pitch_defensive_c:get() == 'Default' and lua.pui.ui.conditions[state].pitch_defensive_s:get() or client.random_int(-lua.pui.ui.conditions[state].pitch_defensive_s:get(), lua.pui.ui.conditions[state].pitch_defensive_s:get())
    local yawd_defensive_s = lua.pui.ui.conditions[state].yawd_defensive_s:get()
    local def_p = lua.pui.ui.conditions[state].defensive_plus
    local def_m = lua.pui.ui.conditions[state].defensive_minus
    local defensive = lua.pui.ui.conditions[state].defensive
    local defensive_aa = lua.pui.ui.conditions[state].defensive_aa_on
    local defensive_yaw = lua.pui.ui.conditions[state].yaw_defensive
    local defensive_yaw_slide = lua.pui.ui.conditions[state].yaw_defensive_s:get()
    local d_yaw = 0
    if lua.createmove.spin > 180 then
        lua.createmove.spin = -180
    end
    lua.createmove.spin = lua.createmove.spin + defensive_yaw_slide / 9

    if defensive_yaw:get('Offset') then
        d_yaw = d_yaw + (invert and -defensive_yaw_slide / 2 or defensive_yaw_slide)
    end

    if defensive_yaw:get('Center') then
        d_yaw = d_yaw + (invert and -defensive_yaw_slide or defensive_yaw_slide)
    end

    if defensive_yaw:get('Random') then
        d_yaw = d_yaw + (invert and -client.random_int(0, defensive_yaw_slide) or client.random_int(0, defensive_yaw_slide))
    end

    if defensive_yaw:get('Spin') then
        d_yaw = d_yaw + lua.createmove.spin
    end

    local yaw = lua.pui.ui.conditions[state].yaw:get()
    local lr = lua.pui.ui.conditions[state].yaw_lr:get()
    local r = lua.pui.ui.conditions[state].yaw_r:get()
    local l = lua.pui.ui.conditions[state].yaw_l:get()
    local invert_lr = lr and (invert and l or r) or 0

    local modifier_sel = lua.pui.ui.conditions[state].yaw_multi
    local modifier_slide = lua.pui.ui.conditions[state].yaw_multi_s:get()
    local multiselect_modifier = 0
    if modifier_sel:get('Offset') then
        local mod_offset = invert and modifier_slide / 2 or modifier_slide
        multiselect_modifier = multiselect_modifier + mod_offset
    end

    if modifier_sel:get('Center') then
        local mod_center = invert and -modifier_slide or modifier_slide
        multiselect_modifier = multiselect_modifier + mod_center
    end

    if modifier_sel:get('Random') then
        local mod_random = invert and -client.random_int(0, modifier_slide) or client.random_int(0, modifier_slide)
        multiselect_modifier = multiselect_modifier + mod_random
    end

    if lua.createmove.spray > 60 or lua.createmove.spray < -60 then
        lua.createmove.spray = 0
    end

    if modifier_sel:get('Spray') then
        lua.createmove.spray = lua.createmove.spray + (invert and - modifier_slide or modifier_slide) / 4
        local spray = lua.createmove.spray
        multiselect_modifier = multiselect_modifier + spray
    end

    local body_yaw = lua.pui.ui.conditions[state].lby:get()
    local body_value = lua.pui.ui.conditions[state].lby_yaw:get()
    local lby_count = 'Off'
    local lby_number = 'Off'
    if body_yaw == 'Ticks' then
        lby_count = 'Static'
        lby_number = invert and -body_value or body_value
    elseif body_yaw == 'Random Ticks' then
        lby_count = 'Static'
        lby_number = invert and -body_value or body_value
    elseif body_yaw == 'Static' then
        lby_count = 'Static'
        lby_number = direction_freestand == -1 and -body_value or body_value
    else
        lby_count = 'Off'
        lby_number = 0
    end
    local byaw = false
    if lua.pui.ui.additive.other:get('Avoid backstab') then
        local players = entity.get_players(true)
        local origin = vector(entity.get_prop(entity.get_local_player(), 'm_vecOrigin'))
        for i = 1, #players do
            local enemy = players[i]
            local x, y, z = entity.get_prop(enemy, 'm_vecOrigin')
            local weapon = entity.get_player_weapon(enemy)
            if x ~= nil and weapon ~= nil and entity.get_classname(weapon) == 'CKnife' then
                local distance = math.sqrt((x - origin.x)^2 + (y - origin.y)^2 + (z - origin.z)^2)
                if distance <= 200 then
                    byaw = true
                    break
                end
            end
        end
    end

    if lua.pui.ui.antiaim.manuals:get() and lua.createmove.selected_manual == 2 and not lua.pui.ui.conditions['Manual Right'].override:get() then
        if lua.helps.exploits.defensive() > 3
        and lua.helps.exploits.defensive() < 11
        then
            yaw_da = lua.helps.additions.normalize_yaw(direction_freestand * yawd_defensive_s + d_yaw)
            lua.reference.antiaim.angles.yaw[2]:override(yaw_da)
            lua.reference.antiaim.angles.pitch[2]:override(-89)
        else
            yaw_da = lua.helps.additions.normalize_yaw(90)
            lua.reference.antiaim.angles.yaw[2]:override(yaw_da)
            lua.reference.antiaim.angles.pitch[2]:override(89)
        end
    elseif lua.pui.ui.antiaim.manuals:get() and lua.createmove.selected_manual == 1 and not lua.pui.ui.conditions['Manual Left'].override:get() then
        if lua.helps.exploits.defensive() > 3
        and lua.helps.exploits.defensive() < 11
        then
            yaw_da = lua.helps.additions.normalize_yaw(direction_freestand * yawd_defensive_s + d_yaw)
            lua.reference.antiaim.angles.yaw[2]:override(yaw_da)
            lua.reference.antiaim.angles.pitch[2]:override(-89)
        else
            yaw_da = lua.helps.additions.normalize_yaw(-90)
            lua.reference.antiaim.angles.yaw[2]:override(yaw_da)
            lua.reference.antiaim.angles.pitch[2]:override(89)
        end
    elseif lua.pui.ui.antiaim.manuals:get() and lua.createmove.selected_manual == 4 and not lua.pui.ui.conditions['Manual Forward'].override:get() then
        if lua.helps.exploits.defensive() > 3
        and lua.helps.exploits.defensive() < 11
        then
            yaw_da = lua.helps.additions.normalize_yaw(direction_freestand * yawd_defensive_s + d_yaw)
            lua.reference.antiaim.angles.yaw[2]:override(yaw_da)
            lua.reference.antiaim.angles.pitch[2]:override(-89)
        else
            yaw_da = lua.helps.additions.normalize_yaw(180)
            lua.reference.antiaim.angles.yaw[2]:override(yaw_da)
            lua.reference.antiaim.angles.pitch[2]:override(89)
        end
    elseif lua.pui.ui.antiaim.manuals:get() and lua.createmove.selected_manual == 3 and not lua.pui.ui.conditions['Manual Back'].override:get() then
        if lua.helps.exploits.defensive() > 3
        and lua.helps.exploits.defensive() < 11
        then
            yaw_da = lua.helps.additions.normalize_yaw(direction_freestand * yawd_defensive_s + d_yaw)
            lua.reference.antiaim.angles.yaw[2]:override(yaw_da)
            lua.reference.antiaim.angles.pitch[2]:override(-89)
        else
            yaw_da = lua.helps.additions.normalize_yaw(0)
            lua.reference.antiaim.angles.yaw[2]:override(yaw_da)
            lua.reference.antiaim.angles.pitch[2]:override(89)
        end
    else
        if lua.helps.exploits.defensive() > def_m:get()
        and lua.helps.exploits.defensive() < def_p:get()
        and defensive_aa:get() and defensive:get() ~= 'Off' then
            yaw_da = lua.helps.additions.normalize_yaw(direction_freestand * yawd_defensive_s + d_yaw)
            lua.reference.antiaim.angles.yaw[2]:override(yaw_da)
            lua.reference.antiaim.angles.pitch[2]:override(def_pitch)
        else
            yaw_da = lua.helps.additions.normalize_yaw(((lua.createmove.enabled and lua.pui.ui.conditions['Using'].override:get() or byaw) and 180 or 0) + yaw + invert_lr + multiselect_modifier)
            lua.reference.antiaim.angles.yaw[2]:override(yaw_da)
            lua.reference.antiaim.angles.pitch[2]:override(lua.createmove.enabled and lua.pui.ui.conditions['Using'].override:get() and 0 or 89)
        end
    end
    lua.reference.antiaim.angles.pitch[1]:override('custom')
    lua.reference.antiaim.angles.yaw_base:override((lua.createmove.enabled and lua.pui.ui.conditions['Using'].override:get() or lua.createmove.selected_manual ~= 0) and 'local view' or 'at targets')
    lua.reference.antiaim.angles.yaw[1]:override('180')
    lua.reference.antiaim.angles.yaw_jitter[1]:override('off')
    lua.reference.antiaim.angles.yaw_jitter[2]:override(0)
    lua.reference.antiaim.angles.desync[1]:override(lby_count)
    lua.reference.antiaim.angles.desync[2]:override(lby_number)
end

lua.createmove.defensive = function (cmd)
    local state = lua.createmove.get_state()
    if not lua.pui.ui.conditions[state].override:get() then
        state = 'Regular'
    end

    if not lua.reference.rage.binds.double_tap[1].hotkey:get() and not lua.reference.rage.binds.double_tap[1]:get() then
        return
    end

    if lua.pui.ui.conditions[state].defensive:get() == 'Always' then
        cmd.force_defensive = true
    elseif lua.helps.exploits.is_peeking() and lua.pui.ui.conditions[state].defensive:get() == 'On Peek' then
        cmd.allow_send_packet = false
        cmd.force_defensive = true
    elseif lua.pui.ui.conditions[state].defensive:get() == 'Flick' then
        cmd.force_defensive = cmd.command_number % 8 == 0
    else
        cmd.force_defensive = false
    end
end

lua.createmove.allow_charge = function (cmd)
    local tickbase = entity.get_prop(entity.get_local_player(), 'm_nTickBase') - globals.tickcount()
    local os_ref = lua.reference.rage.binds.on_shot_anti_aim[1].hotkey:get() and lua.reference.rage.binds.on_shot_anti_aim[1]:get() and not lua.reference.rage.binds.fakeduck:get()
    local doubletap_ref = lua.reference.rage.binds.double_tap[1].hotkey:get() and lua.reference.rage.binds.double_tap[1]:get() and not lua.reference.rage.binds.fakeduck:get()
    local active_weapon = entity.get_prop(entity.get_local_player(), 'm_hActiveWeapon')

    if active_weapon == nil then
        return
    end

    local weapon_idx = entity.get_prop(active_weapon, 'm_iItemDefinitionIndex')

    if weapon_idx == nil or weapon_idx == 64 then
        return
    end

    local last_shot = entity.get_prop(active_weapon, 'm_fLastShotTime')

    if last_shot == nil then
        return
    end

    local single_fire_weapon =
        weapon_idx == 40 or weapon_idx == 9 or weapon_idx == 64 or weapon_idx == 27 or weapon_idx == 29 or
        weapon_idx == 35
    local value = single_fire_weapon and 0 or 0.50
    local in_attack = globals.curtime() - last_shot <= value

    if tickbase > 0 and os_ref then
        if in_attack then
            lua.reference.rage.binds.enabled[1]:override(true)
        else
            lua.reference.rage.binds.enabled[1]:override(false)
        end
    elseif tickbase > 0 and doubletap_ref then
        if in_attack then
            lua.reference.rage.binds.enabled[1]:override(true)
        else
            lua.reference.rage.binds.enabled[1]:override(false)
        end
    else
        lua.reference.rage.binds.enabled[1]:override(true)
    end
end

client.set_event_callback('setup_command', lua.createmove.fast_ladder)
client.set_event_callback('setup_command', lua.createmove.defensive)
client.set_event_callback('setup_command', lua.createmove.use_enable)
client.set_event_callback('setup_command', lua.createmove.builder)
client.set_event_callback('setup_command', lua.createmove.allow_charge)
client.set_event_callback('pre_render', lua.createmove.manual)
client.set_event_callback('setup_command', lua.createmove.freestand)
end
--#endregion





























