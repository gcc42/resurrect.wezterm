---@type Wezterm
local wezterm = require("wezterm")

local pub = {}

--- checks if the user is on windows
local is_windows = wezterm.target_triple == "x86_64-pc-windows-msvc"
local separator = is_windows and "\\" or "/"

local function init()
	-- Plugin is at wezterm.config_dir/plugins/resurrect
	local plugin_dir = wezterm.config_dir .. separator .. "plugins" .. separator .. "resurrect"

	-- Add plugin directory to package.path for submodule requires
	local plugin_lua_path = plugin_dir .. separator .. "plugin" .. separator .. "?.lua"
	package.path = plugin_lua_path .. ";" .. package.path

	-- Export submodules
	pub.workspace_state = require("resurrect.workspace_state")
	pub.window_state = require("resurrect.window_state")
	pub.tab_state = require("resurrect.tab_state")
	pub.fuzzy_loader = require("resurrect.fuzzy_loader")
	pub.state_manager = require("resurrect.state_manager")
end

init()

return pub
