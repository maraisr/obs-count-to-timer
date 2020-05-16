obs = obslua

-- Tracking settings
source_name = "" -- The name of the source we are populating
count_till = "" -- The time in 24hr till we want to count
pettern = "$min:$sec" -- The text format

activated = false -- Should be counting down

start_hotkey_id = obs.OBS_INVALID_HOTKEY_ID

string.split = function(str, pat, limit)
    local t = {}
    local fpat = "(.-)" .. pat
    local last_end = 1
    local s, e, cap = str:find(fpat, 1)
    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(t, cap)
        end

        last_end = e + 1
        s, e, cap = str:find(fpat, last_end)

        if limit ~= nil and limit <= #t then
            break
        end
    end

    if last_end <= #str then
        cap = str:sub(last_end)
        table.insert(t, cap)
    end

    return t
end

function get_source_text_with_pattern(mm, ss)
    local p_format = pattern;

    if p_format == nil then
        p_format = "$min:$sec";
    end

    return pattern:gsub("%$(%w+)", { min = mm, sec = ss });
end

function set_text_on_source(value, source_name)
    local source = obs.obs_get_source_by_name(source_name)
    if source ~= nil then
        local settings = obs.obs_data_create()
        obs.obs_data_set_string(settings, "text", value)
        obs.obs_source_update(source, settings)
        obs.obs_data_release(settings)
        obs.obs_source_release(source)
    else
        obs.script_log(obs.LOG_ERROR, "No source to update")
    end
end

function get_internal_value()
    local till_arr = string.split(count_till, ":")

    if next(till_arr) == nil then return false end

    local now = os.time()
    local future = os.time {
        year = os.date("%Y", now),
        month = os.date("%m", now),
        day = os.date("%d", now),
        hour = till_arr[1],
        min = till_arr[2],
        sec = 0,
        isdst = false
    }

    if (now > future) then
        activate(false)
        set_text_on_source(get_source_text_with_pattern("00", "00"), source_name)
        return false
    end

    local delta = os.difftime(future, now)
    local d_hours = math.floor(delta / 3600)
    local d_mins = math.floor((delta - (d_hours * 3600)) / 60)
    local d_seconds = delta - (d_hours * 3600) - (d_mins * 60)

    set_text_on_source(get_source_text_with_pattern(string.format("%02d", d_mins), string.format("%02d", d_seconds)), source_name)
    return true
end

function timer_callback()
    local result = get_internal_value()

    if result == false then
        obs.remove_current_callback()
    end
end

function activate(activating)
    if activated == activating then
        return
    end

    activated = activating

    if activating then
        obs.script_log(obs.LOG_DEBUG, "Starting timers")
        if (get_internal_value() ~= false) then
            obs.timer_add(timer_callback, 1000)
        end
    else
        obs.script_log(obs.LOG_DEBUG, "Stopping timers")
        obs.timer_remove(timer_callback)
    end
end

-- A function named script_description returns the description shown to
-- the user
function script_description()
    return "Sets a text source to the mm:ss till a 24hr time is reached."
end

function script_properties()
    local props = obs.obs_properties_create()
    local controls_props = obs.obs_properties_create()
    local setup_props = obs.obs_properties_create()

    obs.obs_properties_add_text(controls_props, "end_time", "Countdown to (hh:mm)", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(controls_props, "pattern", "Text pattern (default: $min:$sec)", obs.OBS_TEXT_DEFAULT)

    obs.obs_properties_add_button(controls_props, "start_button", "Start", function() activate(true) end)
    obs.obs_properties_add_button(controls_props, "stop_button", "Stop", function() activate(false) end)

    local p = obs.obs_properties_add_list(setup_props, "source", "Target", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            local source_id = obs.obs_source_get_unversioned_id(source)
            if source_id == "text_gdiplus" or source_id == "text_ft2_source" then
                local name = obs.obs_source_get_name(source)
                obs.obs_property_list_add_string(p, name, name)
            end
        end
    end
    obs.source_list_release(sources)

    obs.obs_properties_add_group(props, "controls", "Controls", obs.OBS_GROUP_NORMAL, controls_props)
    obs.obs_properties_add_group(props, "setup", "Setup", obs.OBS_GROUP_NORMAL, setup_props)

    return props
end

function start_hotkey_handler(pressed)
    if not pressed then
        return
    end

    obs.script_log(obs.LOG_DEBUG, "Start Hotkey handler fired")

    activate(true)
end

function activate_signal(cd, activating)
    local source = obs.calldata_source(cd, "source")
    if source ~= nil then
        local name = obs.obs_source_get_name(source)
        if (name == source_name) then
            activate(activating)
        end
    end
end

function source_activated(cd)
    obs.script_log(obs.LOG_DEBUG, "Activating")
    activate_signal(cd, true)
end

function source_deactivated(cd)
    obs.script_log(obs.LOG_DEBUG, "Deactivating")
    activate_signal(cd, false)
end

-- And... we begin, effectivly the entrypoint
-- A function named script_load will be called on startup
function script_load(settings)
    local sh = obs.obs_get_signal_handler()
    obs.signal_handler_connect(sh, "source_activate", source_activated)
    obs.signal_handler_connect(sh, "source_deactivate", source_deactivated)

    start_hotkey_id = obs.obs_hotkey_register_frontend("start_hotkey", "Start Count-to Timer", start_hotkey_handler)
    local hotkey_save_array = obs.obs_data_get_array(settings, "hotkey")
    obs.obs_hotkey_load(start_hotkey_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

-- A function named script_update will be called when settings are changed
function script_update(settings)
    activate(false)
    count_till = obs.obs_data_get_string(settings, "end_time")
    source_name = obs.obs_data_get_string(settings, "source")
    pattern = obs.obs_data_get_string(settings, "pattern")
end

-- A function named script_save will be called when the script is saved
function script_save(settings)
    local hotkey_save_array = obs.obs_hotkey_save(start_hotkey_id)
    obs.obs_data_set_array(settings, "start_hotkey", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

