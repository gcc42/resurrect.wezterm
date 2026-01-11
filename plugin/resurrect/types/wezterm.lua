---@meta
-- WezTerm API type definitions for LuaLS
-- These are stubs for type checking only, not runtime code

---@class WezPlugin
local WezPlugin = {}

---Require a wezterm plugin
---@param url string Plugin URL
---@return table
function WezPlugin.require(url) end

---@class Wezterm
---@field mux WezMux
---@field gui WezGui
---@field time WezTime
---@field plugin WezPlugin Plugin loader
---@field target_triple string Platform identifier (e.g., "x86_64-apple-darwin")
---@field config_dir string Path to WezTerm config directory
---@field home_dir string User home directory
---@field nerdfonts table<string, string> Nerd font icon mappings
local Wezterm = {}

---Log info message
---@param msg string
function Wezterm.log_info(msg) end

---Log warning message
---@param msg string
function Wezterm.log_warn(msg) end

---Log error message
---@param msg string
function Wezterm.log_error(msg) end

---Encode value to JSON string
---@param val any
---@return string
function Wezterm.json_encode(val) end

---Parse JSON string to value
---@param str string
---@return any
function Wezterm.json_parse(str) end

---Emit an event
---@param event string Event name
---@param ... any Event arguments
function Wezterm.emit(event, ...) end

---Register event handler
---@param event string Event name
---@param callback function Handler function
function Wezterm.on(event, callback) end

---Join arguments for shell command
---@param args string[]
---@return string
function Wezterm.shell_join_args(args) end

---Run child process synchronously
---@param args string[] Command and arguments
---@return boolean success
---@return string stdout
---@return string stderr
function Wezterm.run_child_process(args) end

---Read directory contents
---@param path string
---@return string[] files
function Wezterm.read_dir(path) end

---Format styled text
---@param segments table[]
---@return string
function Wezterm.format(segments) end

---Create action callback
---@param callback fun(window: GuiWindow, pane: Pane, id?: string, label?: string)
---@return table action
function Wezterm.action_callback(callback) end

---@class WezAction
---@field CloseCurrentPane fun(opts: table): table
---@field CloseCurrentTab fun(opts: table): table
---@field InputSelector fun(opts: table): table
---@field PromptInputLine fun(opts: table): table
local WezAction = {}

---@type WezAction
Wezterm.action = WezAction

---@class WezMux
local WezMux = {}

---Get active workspace name
---@return string
function WezMux.get_active_workspace() end

---Get all mux windows
---@return MuxWindow[]
function WezMux.all_windows() end

---Spawn a new window
---@param args? SpawnWindowArgs
---@return MuxTab tab
---@return Pane pane
---@return MuxWindow window
function WezMux.spawn_window(args) end

---Get domain by name
---@param name string
---@return MuxDomain
function WezMux.get_domain(name) end

---Set active workspace
---@param name string
function WezMux.set_active_workspace(name) end

---@class SpawnWindowArgs
---@field workspace? string
---@field cwd? string
---@field domain? table

---@class WezGui
local WezGui = {}

---Get all GUI windows
---@return GuiWindow[]
function WezGui.gui_windows() end

---@class WezTime
local WezTime = {}

---Schedule callback after delay
---@param seconds number
---@param callback function
function WezTime.call_after(seconds, callback) end
