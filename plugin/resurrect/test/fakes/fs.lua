---In-memory virtual filesystem for tests
---Intercepts io.open and io.lines to provide in-memory file operations
local fs = {}

-- State
local test_root = nil
local files = {} -- { [path] = content }
local dirs = {} -- { [path] = true }
local counter = 0

-- Save original io and os functions
local real_io_open = io.open
local real_io_lines = io.lines
local real_os_remove = os.remove

--- Check if a path is within the test root
---@param path string
---@return boolean
local function is_test_path(path)
	return test_root ~= nil and path:sub(1, #test_root) == test_root
end

--- Create a fake file handle for reading
---@param content string
---@return table handle
local function make_read_handle(content)
	local pos = 1
	return {
		read = function(_, mode)
			if mode == "*a" or mode == "*all" then
				local result = content:sub(pos)
				pos = #content + 1
				return result
			elseif mode == "*l" or mode == "*line" or mode == nil then
				if pos > #content then
					return nil
				end
				local newline = content:find("\n", pos)
				if newline then
					local line = content:sub(pos, newline - 1)
					pos = newline + 1
					return line
				else
					local line = content:sub(pos)
					pos = #content + 1
					return line
				end
			end
			return nil
		end,
		lines = function(self)
			return function()
				return self:read("*l")
			end
		end,
		close = function()
			return true
		end,
		seek = function()
			return pos
		end,
	}
end

--- Create a fake file handle for writing
---@param path string
---@return table handle
local function make_write_handle(path)
	local buffer = {}
	return {
		write = function(_, ...)
			for _, v in ipairs({ ... }) do
				table.insert(buffer, tostring(v))
			end
			return true
		end,
		flush = function()
			files[path] = table.concat(buffer)
			return true
		end,
		close = function()
			files[path] = table.concat(buffer)
			return true
		end,
	}
end

--- Fake io.open that intercepts test paths
---@param path string
---@param mode string|nil
---@return table|nil handle
---@return string|nil error
local function fake_io_open(path, mode)
	if not is_test_path(path) then
		return real_io_open(path, mode)
	end

	mode = mode or "r"

	if mode:match("r") then
		local content = files[path]
		if content then
			return make_read_handle(content)
		end
		return nil, "No such file or directory"
	elseif mode:match("w") or mode:match("a") then
		-- Create parent directory
		local parent = path:match("(.+)/[^/]+$")
		if parent then
			fs.mkdir(parent)
		end
		return make_write_handle(path)
	end

	return nil, "Unsupported mode"
end

--- Fake io.lines that intercepts test paths
---@param path string
---@return function iterator
local function fake_io_lines(path)
	if not is_test_path(path) then
		return real_io_lines(path)
	end

	local content = files[path]
	if not content then
		error("cannot open file '" .. path .. "' (No such file or directory)")
	end

	local handle = make_read_handle(content)
	return function()
		return handle:read("*l")
	end
end

--- Fake os.remove that intercepts test paths
---@param path string
---@return boolean|nil success
---@return string|nil error
local function fake_os_remove(path)
	if not is_test_path(path) then
		return real_os_remove(path)
	end

	if files[path] then
		files[path] = nil
		return true
	end
	return nil, "No such file or directory"
end

--- Create a unique test directory (in-memory)
---@return string root The virtual root path
function fs.setup()
	counter = counter + 1
	test_root = "/tmp/resurrect-test-" .. counter
	files = {}
	dirs = { [test_root] = true }

	-- Install fake io/os functions
	io.open = fake_io_open
	io.lines = fake_io_lines
	os.remove = fake_os_remove

	return test_root
end

--- Clean up test state
function fs.teardown()
	-- Restore real io/os functions
	io.open = real_io_open
	io.lines = real_io_lines
	os.remove = real_os_remove

	test_root = nil
	files = {}
	dirs = {}
end

--- Get the test root directory
---@return string|nil root The virtual root path
function fs.get_root()
	return test_root
end

--- Ensure a directory exists (creates parent dirs)
---@param path string Directory path to create
function fs.mkdir(path)
	if not path then
		return
	end
	-- Create the directory and all parents
	local parts = {}
	for part in path:gmatch("[^/]+") do
		table.insert(parts, part)
	end
	local current = ""
	for _, part in ipairs(parts) do
		current = current .. "/" .. part
		dirs[current] = true
	end
end

--- Write content to a file
---@param path string File path
---@param content string Content to write
---@return boolean success
function fs.write(path, content)
	if not path then
		return false
	end
	-- Create parent directory
	local parent = path:match("(.+)/[^/]+$")
	if parent then
		fs.mkdir(parent)
	end
	files[path] = content
	return true
end

--- Read content from a file
---@param path string File path
---@return string|nil content File content or nil if not found
function fs.read(path)
	return files[path]
end

--- Check if path exists (file or directory)
---@param path string Path to check
---@return boolean exists
function fs.exists(path)
	return files[path] ~= nil or dirs[path] ~= nil
end

--- Delete a file
---@param path string File path
---@return boolean success
function fs.delete(path)
	if files[path] then
		files[path] = nil
		return true
	end
	return false
end

--- List files in directory
---@param dir string Directory path
---@return string[] files List of file names in the directory
function fs.list(dir)
	local result = {}
	local seen = {}
	local prefix = dir .. "/"

	-- Find files in directory
	for path in pairs(files) do
		if path:sub(1, #prefix) == prefix then
			local rest = path:sub(#prefix + 1)
			local name = rest:match("^([^/]+)")
			if name and not seen[name] then
				seen[name] = true
				table.insert(result, name)
			end
		end
	end

	-- Find subdirectories
	for path in pairs(dirs) do
		if path:sub(1, #prefix) == prefix then
			local rest = path:sub(#prefix + 1)
			local name = rest:match("^([^/]+)")
			if name and not seen[name] then
				seen[name] = true
				table.insert(result, name)
			end
		end
	end

	return result
end

--- Reset (alias for teardown + setup)
---@return string root The new virtual root path
function fs.reset()
	fs.teardown()
	return fs.setup()
end

return fs
