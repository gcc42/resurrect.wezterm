---@type Wezterm
local wezterm = require("wezterm")
local core = require("resurrect.core.pane_tree")
local shell_api = require("resurrect.shell.api")

---@class pane_tree_module
---@field max_nlines integer
local pub = {}
pub.max_nlines = 3500

---@alias PaneInformation {left: integer, top: integer, height: integer, width: integer, pane: Pane?}
---@alias pane_tree {left: integer, top: integer, height: integer, width: integer,
---bottom: pane_tree?, right: pane_tree?, text: string, cwd: string, domain?: string,
---process?: local_process_info?, pane: Pane?, is_active: boolean, is_zoomed: boolean,
---alt_screen_active: boolean}
---@alias local_process_info {name: string, argv: string[], cwd: string, executable: string}

-- Re-export pure functions from core
pub.map = core.map
pub.fold = core.fold

---Create a pane tree from a list of PaneInformation
---Uses shell/api to extract pane data, then core to build tree
---@param panes PaneInformation[]
---@return pane_tree | nil
function pub.create_pane_tree(panes)
	-- Extract raw pane data using shell API
	local raw_panes = shell_api.extract_panes(panes, pub.max_nlines)

	-- Build tree using core pure function
	local tree, warnings = core.build(raw_panes)

	-- Emit warnings for non-spawnable domains
	for _, warning in ipairs(warnings) do
		wezterm.log_warn(warning)
		wezterm.emit("resurrect.error", warning)
	end

	return tree
end

return pub
