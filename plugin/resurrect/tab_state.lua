---@type Wezterm
local wezterm = require("wezterm")
local pane_tree_mod = require("resurrect.pane_tree")
local pub = {}

---Determine if right split happened before bottom split based on geometry.
---If right pane spans full height (parent + bottom), right was split first.
---If bottom pane spans full width (parent + right), bottom was split first.
---@param pane_tree pane_tree
---@return boolean true if right should be split first
local function should_split_right_first(pane_tree)
	local right = pane_tree.right
	local bottom = pane_tree.bottom

	if not right or not bottom then
		return right ~= nil
	end

	local right_spans_full_height = right.height >= (pane_tree.height + bottom.height - 1)
	return right_spans_full_height
end

---Execute a split operation
---@param pane Pane?
---@param parent pane_tree
---@param child pane_tree
---@param direction "Right" | "Bottom"
---@param opts restore_opts
local function do_split(pane, parent, child, direction, opts)
	if not pane then
		return
	end
	local split_args = { direction = direction, cwd = child.cwd }
	if opts.relative then
		if direction == "Right" then
			split_args.size = child.width / (parent.width + child.width)
		else
			split_args.size = child.height / (parent.height + child.height)
		end
	elseif opts.absolute then
		split_args.size = direction == "Right" and child.width or child.height
	end
	child.pane = pane:split(split_args)
end

---Function used to split panes when mapping over the pane_tree
---@param opts restore_opts
---@return fun(acc: {active_pane: Pane, is_zoomed: boolean}, pane_tree: pane_tree):
---{active_pane: Pane, is_zoomed: boolean}
local function make_splits(opts)
	if opts == nil then
		opts = {}
	end

	return function(acc, pane_tree)
		local pane = pane_tree.pane

		if opts.on_pane_restore then
			opts.on_pane_restore(pane_tree)
		end

		local right = pane_tree.right
		local bottom = pane_tree.bottom

		if should_split_right_first(pane_tree) then
			if right then
				do_split(pane, pane_tree, right, "Right", opts)
			end
			if bottom then
				do_split(pane, pane_tree, bottom, "Bottom", opts)
			end
		else
			if bottom then
				do_split(pane, pane_tree, bottom, "Bottom", opts)
			end
			if right then
				do_split(pane, pane_tree, right, "Right", opts)
			end
		end

		if pane_tree.is_active then
			acc.active_pane = pane_tree.pane
		end

		if pane_tree.is_zoomed then
			acc.is_zoomed = true
		end

		return acc
	end
end

---creates and returns the state of the tab
---@param tab MuxTab
---@return tab_state
function pub.get_tab_state(tab)
	local panes = tab:panes_with_info()

	local function is_zoomed()
		for _, pane in ipairs(panes) do
			if pane.is_zoomed then
				return true
			end
		end
		return false
	end

	local tab_state = {
		title = tab:get_title(),
		is_zoomed = is_zoomed(),
		pane_tree = pane_tree_mod.create_pane_tree(panes),
	}

	return tab_state
end

---Force closes all other tabs in the window but one
---@param tab MuxTab
---@param pane_to_keep Pane
local function close_all_other_panes(tab, pane_to_keep)
	for _, pane in ipairs(tab:panes()) do
		if pane:pane_id() ~= pane_to_keep:pane_id() then
			pane:activate()
			tab:window():gui_window():perform_action(wezterm.action.CloseCurrentPane({ confirm = false }), pane)
		end
	end
end

---restore a tab
---@param tab MuxTab
---@param tab_state tab_state
---@param opts restore_opts
function pub.restore_tab(tab, tab_state, opts)
	wezterm.emit("resurrect.tab_state.restore_tab.start")
	if opts.pane then
		tab_state.pane_tree.pane = opts.pane
	else
		local split_args = { cwd = tab_state.pane_tree.cwd }
		if tab_state.pane_tree.domain then
			split_args.domain = { DomainName = tab_state.pane_tree.domain }
		end
		local new_pane = tab:active_pane():split(split_args)
		tab_state.pane_tree.pane = new_pane
	end

	if opts.close_open_panes then
		close_all_other_panes(tab, tab_state.pane_tree.pane)
	end

	if tab_state.title then
		tab:set_title(tab_state.title)
	end

	local acc = pane_tree_mod.fold(tab_state.pane_tree, { is_zoomed = false }, make_splits(opts))
	acc.active_pane:activate()
	wezterm.emit("resurrect.tab_state.restore_tab.finished")
end

function pub.save_tab_action()
	return wezterm.action_callback(function(win, pane)
		local resurrect = require("resurrect")
		local tab = pane:tab()
		if tab:get_title() == "" then
			win:perform_action(
				wezterm.action.PromptInputLine({
					description = "Enter new tab title",
					action = wezterm.action_callback(function(_, callback_pane, title)
						if title then
							callback_pane:tab():set_title(title)
							local state = pub.get_tab_state(tab)
							resurrect.state_manager.save_state(state)
						end
					end),
				}),
				pane
			)
		elseif tab:get_title() then
			local state = pub.get_tab_state(tab)
			resurrect.state_manager.save_state(state)
		end
	end)
end

--- Function to restore text or processes when restoring panes
---@param pane_tree pane_tree
function pub.default_on_pane_restore(pane_tree)
	local pane = pane_tree.pane

	-- Spawn process if using alt screen, otherwise restore text
	if pane_tree.alt_screen_active then
		pane:send_text(wezterm.shell_join_args(pane_tree.process.argv) .. "\r\n")
	elseif pane_tree.text then
		pane:inject_output(pane_tree.text:gsub("%s+$", ""))
	end
end

return pub
