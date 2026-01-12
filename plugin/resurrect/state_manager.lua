---@type Wezterm
local wezterm = require("wezterm")
local core = require("resurrect.core.pane_tree")
local shell_io = require("resurrect.shell.io")

local pub = {}

-- Re-export sanitize_filename from core (for backward compatibility)
pub.sanitize_filename = core.sanitize_filename

---save state to a file
---Delegates to shell/io.save() for workflow orchestration
---@param state workspace_state | window_state | tab_state
---@param opt_name? string
function pub.save_state(state, opt_name)
	shell_io.save(state, opt_name)
end

---Reads a file with the state
---Delegates to shell/io.load() for workflow orchestration
---@param name string
---@param type string
---@return table
function pub.load_state(name, type)
	local result = shell_io.load(name, type)
	-- Backward compatibility: return empty table instead of nil on error
	return result or {}
end

local save_in_progress = false

---Saves the state after interval in seconds
---@param opts? { interval_seconds: integer?, save_workspaces: boolean?, save_windows: boolean?, save_tabs: boolean? }
function pub.periodic_save(opts)
	-- Default options with ternary idiom
	opts = opts or { save_workspaces = true }
	opts.interval_seconds = opts.interval_seconds or (60 * 15)

	wezterm.time.call_after(opts.interval_seconds, function()
		-- Guard: skip if previous save still running (prevents overlap)
		if save_in_progress then
			pub.periodic_save(opts) -- reschedule and check again later
			return
		end
		save_in_progress = true

		wezterm.emit("resurrect.state_manager.periodic_save.start", opts)

		-- Helper: check if title is non-empty
		local function has_title(title)
			return title and title ~= ""
		end

		if opts.save_workspaces then
			pub.save_state(require("resurrect.workspace_state").get_workspace_state())
		end

		if opts.save_windows then
			for _, gui_win in ipairs(wezterm.gui.gui_windows()) do
				local mux_win = gui_win:mux_window()
				if has_title(mux_win:get_title()) then
					pub.save_state(require("resurrect.window_state").get_window_state(mux_win))
				end
			end
		end

		if opts.save_tabs then
			for _, gui_win in ipairs(wezterm.gui.gui_windows()) do
				for _, mux_tab in ipairs(gui_win:mux_window():tabs()) do
					if has_title(mux_tab:get_title()) then
						pub.save_state(require("resurrect.tab_state").get_tab_state(mux_tab))
					end
				end
			end
		end

		wezterm.emit("resurrect.state_manager.periodic_save.finished", opts)
		save_in_progress = false
		pub.periodic_save(opts)
	end)
end

---Writes the current state name and type
---Delegates to shell/io.write_current_state()
---@param name string
---@param type string
---@return boolean
---@return string|nil
function pub.write_current_state(name, type)
	return shell_io.write_current_state(name, type)
end

---callback for resurrecting workspaces on startup
---Delegates to shell/io for reading current state
---@return boolean
---@return string|nil
function pub.resurrect_on_gui_startup()
	local suc, err = pcall(function()
		local name, state_type = shell_io.read_current_state()
		if not name or not state_type then
			error("Could not read current state file")
		end
		if state_type == "workspace" then
			require("resurrect.workspace_state").restore_workspace(pub.load_state(name, state_type), {
				spawn_in_workspace = true,
				relative = true,
				restore_text = true,
				on_pane_restore = require("resurrect.tab_state").default_on_pane_restore,
			})
			wezterm.mux.set_active_workspace(name)
		end
	end)
	return suc, err
end

---Deletes a state file
---Delegates to shell/io.delete()
---@param file_path string
function pub.delete_state(file_path)
	shell_io.delete(file_path)
end

--- Merges user-supplied options with default options
--- @param user_opts encryption_opts
function pub.set_encryption(user_opts)
	require("resurrect.shell.file_io").set_encryption(user_opts)
end

---Changes the directory to save the state to
---Delegates to shell/io.change_state_dir() and syncs local save_state_dir
---@param directory string
function pub.change_state_save_dir(directory)
	shell_io.change_state_dir(directory)
	-- Keep local save_state_dir in sync for backward compatibility
	pub.save_state_dir = shell_io.save_state_dir
end

---Sets the maximum number of lines to capture from pane scrollback
---@param max_nlines integer
function pub.set_max_nlines(max_nlines)
	require("resurrect.pane_tree").max_nlines = max_nlines
end

return pub
