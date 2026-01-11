---Shell I/O module: File I/O operations for state persistence.
---Handles save/load/delete workflows and directory management.
---All event emissions are preserved as they are public API.

---@type Wezterm
local wezterm = require("wezterm")
local file_io = require("resurrect.file_io")
local utils = require("resurrect.utils")
local core = require("resurrect.core.pane_tree")

---@class ShellIO
local M = {}

-- Default configuration (will be set by state_manager.change_state_save_dir)
M.save_state_dir = wezterm.config_dir .. "/resurrect/"

--------------------------------------------------------------------------------
-- State Type Detection
--------------------------------------------------------------------------------

---Detect the type of state object
---@param state table The state object to detect
---@return StateType|nil type The detected state type, or nil if unknown
local function detect_state_type(state)
	if state.window_states then
		return "workspace"
	elseif state.tabs then
		return "window"
	elseif state.pane_tree then
		return "tab"
	end
	return nil
end

---Get the name field from a state object based on its type
---@param state table The state object
---@param state_type StateType The type of state
---@return string|nil name The name of the state
local function get_state_name(state, state_type)
	if state_type == "workspace" then
		return state.workspace
	elseif state_type == "window" then
		return state.title
	elseif state_type == "tab" then
		return state.title
	end
	return nil
end

--------------------------------------------------------------------------------
-- File Path Construction
--------------------------------------------------------------------------------

---Build file path for a state file
---@param name string The state name (will be sanitized)
---@param state_type StateType The type of state
---@return string path The full file path
function M.build_file_path(name, state_type)
	local sanitized_name = core.sanitize_filename(name)
	return string.format("%s%s%s%s.json", M.save_state_dir, state_type, utils.separator, sanitized_name)
end

--------------------------------------------------------------------------------
-- Save Workflow
--------------------------------------------------------------------------------

---Save state to a file
---Emits events: resurrect.file_io.write_state.start, resurrect.file_io.write_state.finished
---@param state WorkspaceState|WindowState|TabState The state to save
---@param opt_name string|nil Optional custom name for the file
---@return boolean success True if save succeeded
function M.save(state, opt_name)
	-- Detect state type
	local state_type = detect_state_type(state)
	if not state_type then
		wezterm.emit("resurrect.error", "Unknown state type")
		return false
	end

	-- Determine file name
	local name = opt_name or get_state_name(state, state_type)
	if not name then
		wezterm.emit("resurrect.error", "Cannot determine state name")
		return false
	end

	-- Build file path
	local file_path = M.build_file_path(name, state_type)

	-- Delegate to file_io which handles events and encoding
	file_io.write_state(file_path, state, state_type)

	return true
end

--------------------------------------------------------------------------------
-- Load Workflow
--------------------------------------------------------------------------------

---Load state from a file
---Emits events: resurrect.state_manager.load_state.start, resurrect.state_manager.load_state.finished, resurrect.error
---@param name string The name of the state to load
---@param state_type StateType The type of state
---@return WorkspaceState|WindowState|TabState|nil state The loaded state, or nil on error
function M.load(name, state_type)
	wezterm.emit("resurrect.state_manager.load_state.start", name, state_type)

	local file_path = M.build_file_path(name, state_type)
	local json = file_io.load_json(file_path)

	-- Guard: invalid json returns nil with error event
	if not json then
		wezterm.emit("resurrect.error", "Invalid json: " .. file_path)
		return nil
	end

	wezterm.emit("resurrect.state_manager.load_state.finished", name, state_type)
	return json
end

--------------------------------------------------------------------------------
-- Delete Workflow
--------------------------------------------------------------------------------

---Delete a state file
---Emits events: resurrect.state_manager.delete_state.start,
---resurrect.state_manager.delete_state.finished, resurrect.error
---@param file_path string The relative path to the file (type/name.json)
---@return boolean success True if delete succeeded
function M.delete(file_path)
	wezterm.emit("resurrect.state_manager.delete_state.start", file_path)

	local full_path = M.save_state_dir .. file_path
	local success = os.remove(full_path)

	if not success then
		wezterm.emit("resurrect.error", "Failed to delete state: " .. full_path)
		wezterm.log_error("Failed to delete state: " .. full_path)
	end

	wezterm.emit("resurrect.state_manager.delete_state.finished", file_path)
	return success == true
end

--------------------------------------------------------------------------------
-- Current State Tracking
--------------------------------------------------------------------------------

---Write the current state name and type (for restore on startup)
---@param name string The state name
---@param state_type StateType The type of state
---@return boolean success
---@return string|nil error
function M.write_current_state(name, state_type)
	local file_path = M.save_state_dir .. utils.separator .. "current_state"
	local content = string.format("%s\n%s", name, state_type)
	return file_io.write_file(file_path, content)
end

---Valid state types for validation
---@type table<string, boolean>
local VALID_STATE_TYPES = {
	workspace = true,
	window = true,
	tab = true,
}

---Read the current state name and type
---@return string|nil name
---@return StateType|nil type
function M.read_current_state()
	local file_path = M.save_state_dir .. utils.separator .. "current_state"
	local file = io.open(file_path, "r")
	if not file then
		return nil, nil
	end

	local name = file:read("*line")
	local state_type_raw = file:read("*line")
	file:close()

	-- Validate state_type is a valid StateType
	if not state_type_raw or not VALID_STATE_TYPES[state_type_raw] then
		return nil, nil
	end

	---@type StateType
	local state_type = state_type_raw
	return name, state_type
end

--------------------------------------------------------------------------------
-- Directory Management
--------------------------------------------------------------------------------

---Change the directory where state files are saved
---Creates subdirectories for workspace, window, and tab states
---@param directory string The new save directory
function M.change_state_dir(directory)
	local types = { "workspace", "window", "tab" }
	for _, state_type in ipairs(types) do
		utils.ensure_folder_exists(directory .. "/" .. state_type)
	end
	M.save_state_dir = directory
end

return M
