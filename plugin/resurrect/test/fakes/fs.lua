-- Virtual Filesystem Fake for testing
-- Provides in-memory file storage for testing persistence without touching disk

local fs = {}

--------------------------------------------------------------------------------
-- Internal State
--------------------------------------------------------------------------------

local files = {}  -- path -> content
local directories = {}  -- path -> true (for tracking created directories)

--------------------------------------------------------------------------------
-- Core Operations
--------------------------------------------------------------------------------

--- Write content to a virtual file
---@param path string The file path
---@param content string The content to write
---@return boolean success
function fs.write(path, content)
    if not path or path == "" then
        return false
    end
    files[path] = content

    -- Ensure parent directories exist
    local parent = path:match("(.+)/[^/]+$") or path:match("(.+)\\[^\\]+$")
    if parent then
        fs.mkdir(parent)
    end

    return true
end

--- Read content from a virtual file
---@param path string The file path
---@return string|nil content
function fs.read(path)
    return files[path]
end

--- Check if a virtual file exists
---@param path string The file path
---@return boolean exists
function fs.exists(path)
    return files[path] ~= nil or directories[path] ~= nil
end

--- Delete a virtual file
---@param path string The file path
---@return boolean success
function fs.delete(path)
    if files[path] then
        files[path] = nil
        return true
    end
    return false
end

--- Create a virtual directory
---@param path string The directory path
---@return boolean success
function fs.mkdir(path)
    if not path or path == "" then
        return false
    end
    directories[path] = true

    -- Create parent directories recursively
    local parent = path:match("(.+)/[^/]+$") or path:match("(.+)\\[^\\]+$")
    if parent and parent ~= path then
        fs.mkdir(parent)
    end

    return true
end

--- List files in a virtual directory
---@param dir string The directory path
---@return string[] paths
function fs.list(dir)
    local result = {}
    local dir_pattern = "^" .. dir:gsub("([%.%-%+%[%]%(%)%$%^%%])", "%%%1")

    for path in pairs(files) do
        if path:match(dir_pattern) then
            result[#result + 1] = path
        end
    end

    table.sort(result)
    return result
end

--- List all files matching a pattern
---@param pattern string Lua pattern to match
---@return string[] paths
function fs.glob(pattern)
    local result = {}

    for path in pairs(files) do
        if path:match(pattern) then
            result[#result + 1] = path
        end
    end

    table.sort(result)
    return result
end

--- Reset all virtual filesystem state
function fs.reset()
    files = {}
    directories = {}
end

--------------------------------------------------------------------------------
-- Inspection Helpers (for test assertions)
--------------------------------------------------------------------------------

--- Get all files as a table (path -> content)
---@return table<string, string>
function fs.all_files()
    local copy = {}
    for k, v in pairs(files) do
        copy[k] = v
    end
    return copy
end

--- Get count of stored files
---@return number
function fs.file_count()
    local count = 0
    for _ in pairs(files) do
        count = count + 1
    end
    return count
end

--- Check if directory exists (was created)
---@param path string
---@return boolean
function fs.dir_exists(path)
    return directories[path] == true
end

--------------------------------------------------------------------------------
-- Wezterm Integration
--------------------------------------------------------------------------------

--- Inject filesystem functions into wezterm fake
--- This patches wezterm to use the virtual filesystem
---@param wezterm_fake table The wezterm fake module
function fs.inject(wezterm_fake)
    -- Patch read_dir to use virtual filesystem
    wezterm_fake.read_dir = function(path)
        local result = {}
        local dir_len = #path
        if not path:match("[/\\]$") then
            dir_len = dir_len + 1
        end

        for file_path in pairs(files) do
            -- Check if file is directly in this directory (not in subdirectory)
            if file_path:sub(1, #path) == path then
                local remainder = file_path:sub(dir_len + 1)
                -- Only include direct children (no further path separators)
                if not remainder:match("/") and not remainder:match("\\") then
                    result[#result + 1] = file_path
                end
            end
        end

        return result
    end

    -- Store original run_child_process
    local original_run_child_process = wezterm_fake.run_child_process

    -- Patch run_child_process to intercept mkdir commands
    wezterm_fake.run_child_process = function(args)
        if args and args[1] == "mkdir" then
            local path = args[2]
            if path then
                fs.mkdir(path)
                return true, "", ""
            end
        end
        -- Fall through to original for other commands
        if original_run_child_process then
            return original_run_child_process(args)
        end
        return true, "", ""
    end
end

--- Create a mock file handle for io.open compatibility
---@param path string
---@param mode string
---@return table|nil handle
function fs.open(path, mode)
    mode = mode or "r"

    if mode:match("r") then
        -- Read mode
        local content = files[path]
        if not content then
            return nil
        end
        local pos = 1
        return {
            read = function(self, fmt)
                if fmt == "*a" or fmt == "*all" then
                    local result = content:sub(pos)
                    pos = #content + 1
                    return result
                elseif fmt == "*l" or fmt == "*line" then
                    local line_end = content:find("\n", pos)
                    if not line_end then
                        if pos > #content then return nil end
                        local result = content:sub(pos)
                        pos = #content + 1
                        return result
                    end
                    local result = content:sub(pos, line_end - 1)
                    pos = line_end + 1
                    return result
                end
                return content:sub(pos)
            end,
            close = function() end,
            lines = function(self)
                return function()
                    return self:read("*l")
                end
            end,
        }
    elseif mode:match("w") then
        -- Write mode
        local buffer = {}
        return {
            write = function(self, ...)
                for _, v in ipairs({...}) do
                    buffer[#buffer + 1] = tostring(v)
                end
            end,
            close = function()
                files[path] = table.concat(buffer)
                -- Ensure parent directory exists
                local parent = path:match("(.+)/[^/]+$")
                if parent then
                    directories[parent] = true
                end
            end,
        }
    end

    return nil
end

return fs
