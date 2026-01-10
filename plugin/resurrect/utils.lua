local wezterm = require("wezterm") --[[@as Wezterm]] --- this type cast invokes the LSP module for Wezterm

local utils = {}

utils.is_windows = wezterm.target_triple == "x86_64-pc-windows-msvc"
utils.is_mac = (wezterm.target_triple == "x86_64-apple-darwin" or wezterm.target_triple == "aarch64-apple-darwin")
utils.separator = utils.is_windows and "\\" or "/"

--------------------------------------------------------------------------------
-- Path Normalization (Pure Functions)
--------------------------------------------------------------------------------

--- Check if a path looks like a Windows path (has drive letter or backslashes)
---@param path string
---@return boolean
function utils.is_windows_path(path)
	-- Guard: empty or nil path is not a Windows path
	if not path or path == "" then return false end
	-- Drive letter (e.g., "C:") or backslash separator indicates Windows
	return path:match("^%a:") ~= nil or path:find("\\", 1, true) ~= nil
end

--- Normalize path separators to the target platform's separator
--- Pure function: takes explicit is_windows parameter
---@param path string The path to normalize
---@param to_windows boolean If true, convert to backslashes; if false, convert to forward slashes
---@return string The normalized path
function utils.normalize_path_separators(path, to_windows)
	if not path or path == "" then return path end
	-- Ternary: convert to backslash for Windows, forward slash for Unix
	return to_windows and path:gsub("/", "\\") or path:gsub("\\", "/")
end

--- Normalize a path to the current platform's conventions
---@param path string The path to normalize
---@return string The normalized path
function utils.normalize_path(path)
	return utils.normalize_path_separators(path, utils.is_windows)
end

--- Split a path into its component parts
--- Handles both Windows and Unix paths
---@param path string The path to split
---@return string[] components Array of path components
---@return string|nil drive_or_root Drive letter (e.g., "C:") for Windows, "/" for Unix absolute paths, or nil for relative paths
function utils.path_components(path)
	if not path or path == "" then return {}, nil end

	-- Normalize to forward slashes for consistent parsing
	local normalized = path:gsub("\\", "/")

	-- Extract drive/root prefix: Windows drive letter or Unix root
	local drive, rest = normalized:match("^(%a:)(.*)$")
	local drive_or_root = drive or (normalized:sub(1, 1) == "/" and "/" or nil)
	normalized = drive and rest or (drive_or_root == "/" and normalized:sub(2) or normalized)

	-- Collect non-empty path components
	local components = {}
	for component in normalized:gmatch("[^/]+") do
		if component ~= "" then components[#components + 1] = component end
	end

	return components, drive_or_root
end

--- Join path components back into a path string
---@param components string[] Array of path components
---@param drive_or_root string|nil Drive letter or root indicator
---@param use_backslash boolean Whether to use backslashes (Windows style)
---@return string The joined path
function utils.join_path_components(components, drive_or_root, use_backslash)
	local sep = use_backslash and "\\" or "/"
	-- Build prefix: "/" becomes sep, drive letter gets sep appended, nil becomes empty
	local prefix = drive_or_root and (drive_or_root == "/" and sep or drive_or_root .. sep) or ""
	return prefix .. table.concat(components, sep)
end

--- Build a path from root and a sequence of components
--- Used for iteratively creating parent directories
---@param components string[] Array of path components
---@param count number Number of components to include (from the start)
---@param drive_or_root string|nil Drive letter or root indicator
---@param use_backslash boolean Whether to use backslashes (Windows style)
---@return string The partial path
function utils.build_partial_path(components, count, drive_or_root, use_backslash)
	-- Take first N components and join them
	local partial = {}
	for i = 1, math.min(count, #components) do partial[#partial + 1] = components[i] end
	return utils.join_path_components(partial, drive_or_root, use_backslash)
end

-- Helper function to remove formatting esc sequences in the string
---@param str string
---@return string
function utils.strip_format_esc_seq(str)
	local clean_str, _ = str:gsub(string.char(27) .. "%[[^m]*m", "")
	return clean_str
end

-- getting screen dimensions
---@return number
function utils.get_current_window_width()
	-- Find focused window and return its column width, default to 80
	for _, window in ipairs(wezterm.gui.gui_windows()) do
		if window:is_focused() then return window:active_tab():get_size().cols end
	end
	return 80
end

-- replace the center of a string with another string
---@param str string string to be modified
---@param len number length to be removed from the middle of str
---@param pad string string that must be inserted in place of the missing part of str
function utils.replace_center(str, len, pad)
	local mid = #str // 2
	local start = mid - (len // 2)
	return str:sub(1, start) .. pad .. str:sub(start + len + 1)
end

-- returns the length of a utf8 string
---@param str string
---@return number
function utils.utf8len(str)
	local _, len = str:gsub("[%z\1-\127\194-\244][\128-\191]*", "")
	return len
end

-- Execute a cmd and return its stdout
---@param cmd string command
---@return boolean success result
---@return string|nil error
function utils.execute(cmd)
	local stdout
	local suc, err = pcall(function()
		local handle = io.popen(cmd)
		if not handle then error("Could not open process: " .. cmd) end
		stdout = handle:read("*a")
		if stdout == nil then error("Error running process: " .. cmd) end
		handle:close()
	end)
	-- Return (success, stdout) on success, (false, error) on failure
	return suc, suc and stdout or err
end

--------------------------------------------------------------------------------
-- Directory Creation (Imperative I/O)
--------------------------------------------------------------------------------

--- Check if a path exists (file or directory)
--- Uses os.rename as primary check, with wezterm.run_child_process fallback for special dirs (e.g., root)
---@param path string The path to check
---@return boolean exists True if the path exists
function utils.path_exists(path)
	if not path or path == "" then return false end

	-- Primary: os.rename to self (fast, no process spawn)
	local ok, err = os.rename(path, path)
	if ok then return true end
	if err and err:find("[Pp]ermission denied") then return true end

	-- Fallback using wezterm.run_child_process instead of io.popen
	local args = utils.is_windows
		and { "cmd.exe", "/c", "if", "exist", path:gsub("/", "\\"), "(echo Y)" }
		or { "test", "-e", path }
	local success, stdout, stderr = wezterm.run_child_process(args)
	-- For Unix: success itself indicates existence
	-- For Windows: check stdout for "Y"
	if utils.is_windows then
		return stdout and stdout:match("Y") ~= nil
	else
		return success
	end
end

--- Alias for path_exists (directories and files use same check)
utils.directory_exists = utils.path_exists

--- Create a single directory (not recursive)
---@param path string The directory path to create
---@return boolean success True if created or already exists
---@return string|nil error Error message if creation failed
function utils.create_single_directory(path)
	if not path or path == "" then return false, "Path is empty" end
	if utils.path_exists(path) then return true, nil end

	local args = utils.is_windows
		and { "cmd.exe", "/c", "mkdir", path:gsub("/", "\\") }
		or { "mkdir", path }

	local success, stdout, stderr = wezterm.run_child_process(args)
	if success or utils.path_exists(path) then return true, nil end

	return false, "Failed to create: " .. path .. (stderr and (" - " .. stderr) or "")
end

--- Create a directory and all parent directories as needed
--- Handles Windows drive letters (e.g., C:) and both / and \ separators
---@param path string The full directory path to create
---@return boolean success True if all directories were created or already exist
---@return string|nil error Error message if creation failed
function utils.ensure_folder_exists(path)
	if not path or path == "" then return false, "Path is empty or nil" end
	if utils.path_exists(path) then return true, nil end

	local components, drive_or_root = utils.path_components(path)
	if #components == 0 then
		return drive_or_root and utils.path_exists(drive_or_root) or false, "Invalid path"
	end

	-- Create directories iteratively from root
	for i = 1, #components do
		local partial = utils.build_partial_path(components, i, drive_or_root, utils.is_windows)
		local success, err = utils.create_single_directory(partial)
		if not success then return false, err end
	end

	return true, nil
end

-- deep copy
---@param original table
---@return any copy
function utils.deepcopy(original)
	-- Non-tables return as-is; tables are recursively copied
	if type(original) ~= "table" then return original end
	local copy = {}
	for k, v in pairs(original) do copy[k] = utils.deepcopy(v) end
	return copy
end

-- extend table
---@alias behavior
---| 'error' # Raises an error if a key exists in multiple tables
---| 'keep'  # Uses the value from the leftmost table (first occurrence)
---| 'force' # Uses the value from the rightmost table (last occurrence)
---
---@param behavior behavior
---@param ... table
---@return table|nil
function utils.tbl_deep_extend(behavior, ...)
	local tables = { ... }
	if #tables == 0 then return {} end

	-- Helper: copy value (deep copy tables, pass-through primitives)
	local function copy_val(v)
		return type(v) == "table" and utils.deepcopy(v) or v
	end

	-- Initialize result with first table
	local result = {}
	for k, v in pairs(tables[1]) do result[k] = copy_val(v) end

	-- Behavior dispatch table for handling key conflicts
	local conflict_handlers = {
		error = function(k) error("Key '" .. tostring(k) .. "' exists in multiple tables") end,
		force = function(_, v) return copy_val(v) end,
		keep = function(_, _, existing) return existing end,  -- Keep existing value
	}

	-- Merge remaining tables
	for i = 2, #tables do
		for k, v in pairs(tables[i]) do
			if type(result[k]) == "table" and type(v) == "table" then
				-- Recursively merge nested tables
				result[k] = utils.tbl_deep_extend(behavior, result[k], v)
			elseif result[k] ~= nil then
				-- Key conflict: dispatch based on behavior
				local handler = conflict_handlers[behavior]
				local new_val = handler(k, v, result[k])
				if new_val ~= nil then result[k] = new_val end
			else
				-- New key: just add it
				result[k] = copy_val(v)
			end
		end
	end

	return result
end

return utils
