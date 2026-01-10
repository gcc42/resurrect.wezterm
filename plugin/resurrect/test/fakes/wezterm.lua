-- Fake WezTerm API for testing
-- Provides a working implementation with test helpers for inspection
local wezterm = {}

-- Configurable platform settings
wezterm.target_triple = "x86_64-apple-darwin"  -- default to macOS

-- Directory paths (configurable)
wezterm.home_dir = os.getenv("HOME") or "/home/test"
wezterm.config_dir = wezterm.home_dir .. "/.config/wezterm"

-- Log capture storage (array of {level, message} objects)
local captured_logs = {}

-- Logging functions that capture output
function wezterm.log_info(...)
    local msg = table.concat({...}, " ")
    captured_logs[#captured_logs + 1] = { level = "info", message = msg }
end

function wezterm.log_error(...)
    local msg = table.concat({...}, " ")
    captured_logs[#captured_logs + 1] = { level = "error", message = msg }
end

function wezterm.log_warn(...)
    local msg = table.concat({...}, " ")
    captured_logs[#captured_logs + 1] = { level = "warn", message = msg }
end

-- Event system
local event_handlers = {}

function wezterm.on(event_name, callback)
    if not event_handlers[event_name] then
        event_handlers[event_name] = {}
    end
    table.insert(event_handlers[event_name], callback)
end

function wezterm.emit(event_name, ...)
    local handlers = event_handlers[event_name]
    if handlers then
        for _, callback in ipairs(handlers) do
            callback(...)
        end
    end
end

-- Action callback (commonly used in wezterm configs)
function wezterm.action_callback(fn)
    return { callback = fn, type = "action_callback" }
end

-- Action table (mock)
wezterm.action = setmetatable({}, {
    __index = function(_, key)
        return function(...)
            return { action = key, args = {...} }
        end
    end
})

-- Config builder (mock)
function wezterm.config_builder()
    return {}
end

-- Plugin system (mock)
wezterm.plugin = {}
function wezterm.plugin.require(url)
    return { url = url }
end

-- Utility functions
function wezterm.format(items)
    -- Simple format mock - just concatenate text items
    local result = ""
    for _, item in ipairs(items) do
        if item.Text then
            result = result .. item.Text
        end
    end
    return result
end

function wezterm.strftime(format)
    return os.date(format)
end

function wezterm.sleep_ms(ms)
    -- No-op in tests, or use os.execute for actual sleep if needed
end

-- Test helper functions (not part of real wezterm API)
wezterm._test = {}

function wezterm._test.get_logs()
    return captured_logs
end

function wezterm._test.clear_logs()
    captured_logs = {}
end

function wezterm._test.get_events()
    return event_handlers
end

function wezterm._test.clear_events()
    event_handlers = {}
end

function wezterm._test.reset()
    wezterm._test.clear_logs()
    wezterm._test.clear_events()
end

function wezterm._test.set_target_triple(triple)
    wezterm.target_triple = triple
end

function wezterm._test.set_home_dir(path)
    wezterm.home_dir = path
end

function wezterm._test.set_config_dir(path)
    wezterm.config_dir = path
end

return wezterm
