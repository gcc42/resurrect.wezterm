-- Fake WezTerm API for testing
-- Provides a working implementation with test helpers for inspection
local wezterm = {}

-- Configurable platform settings
wezterm.target_triple = "x86_64-apple-darwin"  -- default to macOS

-- Directory paths (configurable)
wezterm.home_dir = os.getenv("HOME") or "/home/test"
wezterm.config_dir = wezterm.home_dir .. "/.config/wezterm"

--------------------------------------------------------------------------------
-- JSON encode/decode (simple implementation for testing)
--------------------------------------------------------------------------------

-- Simple JSON encoder (handles tables, strings, numbers, booleans, nil)
local function json_encode_value(val, indent, level)
    indent = indent or ""
    level = level or 0
    local t = type(val)

    if val == nil then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val then return "null" end  -- NaN
        if val == math.huge or val == -math.huge then return "null" end
        return tostring(val)
    elseif t == "string" then
        -- Escape special characters
        local escaped = val:gsub('\\', '\\\\')
            :gsub('"', '\\"')
            :gsub('\n', '\\n')
            :gsub('\r', '\\r')
            :gsub('\t', '\\t')
        return '"' .. escaped .. '"'
    elseif t == "table" then
        -- Check if array (sequential integer keys starting at 1)
        local is_array = true
        local max_index = 0
        for k, _ in pairs(val) do
            if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
                is_array = false
                break
            end
            max_index = math.max(max_index, k)
        end
        if is_array and max_index ~= #val then
            is_array = false
        end

        local parts = {}
        if is_array then
            for i = 1, #val do
                parts[#parts + 1] = json_encode_value(val[i], indent, level + 1)
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(val) do
                local key = type(k) == "string" and k or tostring(k)
                parts[#parts + 1] = '"' .. key .. '":' .. json_encode_value(v, indent, level + 1)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

function wezterm.json_encode(val)
    return json_encode_value(val)
end

-- Simple JSON decoder
local function json_decode(str)
    if not str or str == "" then return nil end

    local pos = 1
    local function skip_whitespace()
        while pos <= #str and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function parse_value()
        skip_whitespace()
        local c = str:sub(pos, pos)

        if c == '"' then
            -- String
            pos = pos + 1
            local start = pos
            local result = ""
            while pos <= #str do
                local char = str:sub(pos, pos)
                if char == '"' then
                    pos = pos + 1
                    return result
                elseif char == '\\' then
                    pos = pos + 1
                    local escape = str:sub(pos, pos)
                    if escape == 'n' then result = result .. '\n'
                    elseif escape == 'r' then result = result .. '\r'
                    elseif escape == 't' then result = result .. '\t'
                    elseif escape == '"' then result = result .. '"'
                    elseif escape == '\\' then result = result .. '\\'
                    else result = result .. escape end
                else
                    result = result .. char
                end
                pos = pos + 1
            end
            error("Unterminated string")
        elseif c == '{' then
            -- Object
            pos = pos + 1
            local obj = {}
            skip_whitespace()
            if str:sub(pos, pos) == '}' then
                pos = pos + 1
                return obj
            end
            while true do
                skip_whitespace()
                if str:sub(pos, pos) ~= '"' then error("Expected string key") end
                local key = parse_value()
                skip_whitespace()
                if str:sub(pos, pos) ~= ':' then error("Expected colon") end
                pos = pos + 1
                obj[key] = parse_value()
                skip_whitespace()
                local sep = str:sub(pos, pos)
                if sep == '}' then
                    pos = pos + 1
                    return obj
                elseif sep == ',' then
                    pos = pos + 1
                else
                    error("Expected comma or closing brace")
                end
            end
        elseif c == '[' then
            -- Array
            pos = pos + 1
            local arr = {}
            skip_whitespace()
            if str:sub(pos, pos) == ']' then
                pos = pos + 1
                return arr
            end
            while true do
                arr[#arr + 1] = parse_value()
                skip_whitespace()
                local sep = str:sub(pos, pos)
                if sep == ']' then
                    pos = pos + 1
                    return arr
                elseif sep == ',' then
                    pos = pos + 1
                else
                    error("Expected comma or closing bracket")
                end
            end
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        elseif c:match("[%d%-]") then
            -- Number
            local num_str = str:match("%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
            pos = pos + #num_str
            return tonumber(num_str)
        else
            error("Unexpected character: " .. c .. " at position " .. pos)
        end
    end

    return parse_value()
end

function wezterm.json_parse(str)
    local ok, result = pcall(json_decode, str)
    if ok then return result end
    return nil
end

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

-- Shell join args (for restoring processes)
function wezterm.shell_join_args(args)
    if not args then return "" end
    local parts = {}
    for _, arg in ipairs(args) do
        -- Simple quoting for args with spaces
        if arg:match("%s") then
            parts[#parts + 1] = '"' .. arg .. '"'
        else
            parts[#parts + 1] = arg
        end
    end
    return table.concat(parts, " ")
end

--------------------------------------------------------------------------------
-- Time module (for periodic saves and delayed operations)
--------------------------------------------------------------------------------

local pending_timers = {}

wezterm.time = {
    call_after = function(seconds, callback)
        pending_timers[#pending_timers + 1] = {
            seconds = seconds,
            callback = callback,
        }
    end,
}

--------------------------------------------------------------------------------
-- Emitted events tracking (for verifying event emissions in tests)
--------------------------------------------------------------------------------

local emitted_events = {}

-- Wrap emit to track emitted events
local original_emit = wezterm.emit
wezterm.emit = function(event_name, ...)
    emitted_events[#emitted_events + 1] = {
        name = event_name,
        args = {...},
    }
    -- Also call original handlers if any
    local handlers = event_handlers[event_name]
    if handlers then
        for _, callback in ipairs(handlers) do
            callback(...)
        end
    end
end

--------------------------------------------------------------------------------
-- GUI stub (for tests that need gui_window access)
--------------------------------------------------------------------------------

wezterm.gui = {
    gui_windows = function()
        return {}
    end,
}

--------------------------------------------------------------------------------
-- Mux stub (will be replaced by mux fake when loaded)
--------------------------------------------------------------------------------

wezterm.mux = {
    _active_workspace = "default",
    _windows = {},

    get_active_workspace = function()
        return wezterm.mux._active_workspace
    end,

    all_windows = function()
        return wezterm.mux._windows
    end,

    spawn_window = function(args)
        -- Stub: return nil values, real implementation in mux fake
        return nil, nil, nil
    end,

    get_domain = function(name)
        return {
            name = name,
            is_spawnable = function() return true end,
        }
    end,
}

-- Run a child process and return success, stdout, stderr
-- This is a test implementation using io.popen for portability
function wezterm.run_child_process(args)
    if not args or #args == 0 then
        return false, "", "No command provided"
    end

    -- Build command string from args array
    local cmd = table.concat(args, " ")

    -- For test command, we need special handling
    if args[1] == "test" then
        -- Use shell to run test command
        cmd = "sh -c '" .. table.concat(args, " ") .. "'"
        local handle = io.popen(cmd .. " 2>&1; echo $?", "r")
        if handle then
            local output = handle:read("*a")
            handle:close()
            -- Extract exit code from last line
            local exit_code = output:match("(%d+)%s*$")
            return exit_code == "0", "", ""
        end
        return false, "", "Failed to execute"
    end

    -- For mkdir and other commands
    local handle = io.popen(cmd .. " 2>&1", "r")
    if handle then
        local output = handle:read("*a")
        handle:close()
        -- Consider success if no error output or if directory was created
        return true, output, ""
    end
    return false, "", "Failed to execute"
end

-- Test helper functions (not part of real wezterm API)
wezterm._test = {
    _pending_timers = pending_timers,
}

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

function wezterm._test.get_emitted_events()
    return emitted_events
end

function wezterm._test.clear_emitted_events()
    emitted_events = {}
end

function wezterm._test.reset()
    wezterm._test.clear_logs()
    wezterm._test.clear_events()
    wezterm._test.clear_emitted_events()
    pending_timers = {}
    wezterm._test._pending_timers = pending_timers
    wezterm.mux._active_workspace = "default"
    wezterm.mux._windows = {}
end

-- Tick all pending timers (execute their callbacks)
function wezterm._test.tick_timers()
    local timers = pending_timers
    pending_timers = {}
    wezterm._test._pending_timers = pending_timers
    for _, timer in ipairs(timers) do
        timer.callback()
    end
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

-- Set the active workspace name
function wezterm._test.set_active_workspace(name)
    wezterm.mux._active_workspace = name
end

-- Set the mux windows list (used by mux fake)
function wezterm._test.set_windows(windows)
    wezterm.mux._windows = windows
end

-- Inject a mux fake (replaces wezterm.mux with the provided fake)
function wezterm._test.set_mux(mux_fake)
    wezterm.mux = mux_fake
end

return wezterm
