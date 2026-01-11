---Virtual filesystem for tests using real temp directory
local fs = {}

-- Cross-platform temp directory detection
local function get_temp_base()
	return os.getenv("TMPDIR") -- macOS
		or os.getenv("TEMP") -- Windows
		or os.getenv("TMP") -- Windows alt
		or "/tmp" -- Linux/fallback
end

-- Platform detection
local is_windows = package.config:sub(1, 1) == "\\"

-- State
local test_root = nil

--- Create a unique test directory
function fs.setup()
	local base = get_temp_base()
	test_root = base .. (is_windows and "\\" or "/") .. "resurrect-test-" .. os.time() .. "-" .. math.random(10000)

	if is_windows then
		os.execute('mkdir "' .. test_root .. '"')
	else
		os.execute("mkdir -p '" .. test_root .. "'")
	end

	return test_root
end

--- Clean up test directory
function fs.teardown()
	if not test_root then
		return
	end

	if is_windows then
		os.execute('rmdir /s /q "' .. test_root .. '" 2>nul')
	else
		os.execute("rm -rf '" .. test_root .. "' 2>/dev/null")
	end

	test_root = nil
end

--- Get the test root directory
function fs.get_root()
	return test_root
end

--- Ensure a directory exists (creates parent dirs)
function fs.mkdir(path)
	if is_windows then
		os.execute('mkdir "' .. path .. '" 2>nul')
	else
		os.execute("mkdir -p '" .. path .. "'")
	end
end

--- Write content to a file
function fs.write(path, content)
	local file = io.open(path, "w")
	if not file then
		fs.mkdir(path:match("(.+)[/\\][^/\\]+$")) -- create parent dir
		file = io.open(path, "w")
	end
	if not file then
		return false
	end
	file:write(content)
	file:close()
	return true
end

--- Read content from a file
function fs.read(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return content
end

--- Check if path exists
function fs.exists(path)
	local file = io.open(path, "r")
	if file then
		file:close()
		return true
	end
	return false
end

--- Delete a file
function fs.delete(path)
	return os.remove(path)
end

--- List files in directory (returns iterator or table)
function fs.list(dir)
	local files = {}
	local cmd
	if is_windows then
		cmd = 'dir /b "' .. dir .. '" 2>nul'
	else
		cmd = "ls -1 '" .. dir .. "' 2>/dev/null"
	end

	local handle = io.popen(cmd)
	if handle then
		for line in handle:lines() do
			table.insert(files, line)
		end
		handle:close()
	end
	return files
end

--- Reset (alias for teardown + setup)
function fs.reset()
	fs.teardown()
	return fs.setup()
end

return fs
