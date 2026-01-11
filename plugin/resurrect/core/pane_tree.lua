---@class CorePaneTree
---@field build fun(panes: RawPaneData[]): PaneTree?, string[]
---@field plan_splits fun(tree: PaneTree, opts: {relative?: boolean, absolute?: boolean}): SplitCommand[]
---@field sanitize_filename fun(name: string?): string
---@field map fun(tree: PaneTree?, fn: fun(node: PaneTree): PaneTree): PaneTree?
---@field fold fun(tree: PaneTree?, acc: any, fn: fun(acc: any, node: PaneTree): any): any
local M = {}

--------------------------------------------------------------------------------
-- Coordinate Comparison and Helpers
--------------------------------------------------------------------------------

---Compare function returns true if a is more left than b
---@param a RawPaneData|PaneTree
---@param b RawPaneData|PaneTree
---@return boolean
function M.compare_by_coord(a, b)
	if a.left == b.left then
		return a.top < b.top
	else
		return a.left < b.left
	end
end

---Check if pane is to the right of root
---@param root RawPaneData|PaneTree
---@param pane RawPaneData|PaneTree
---@return boolean
function M.is_right(root, pane)
	if root.left + root.width < pane.left then
		return true
	end
	return false
end

---Check if pane is below root
---@param root RawPaneData|PaneTree
---@param pane RawPaneData|PaneTree
---@return boolean
function M.is_bottom(root, pane)
	if root.top + root.height < pane.top then
		return true
	end
	return false
end

---Find and remove connected bottom pane from list
---@param root PaneTree
---@param panes RawPaneData[]
---@return RawPaneData?
function M.pop_connected_bottom(root, panes)
	for i, pane in ipairs(panes) do
		if root.left == pane.left and root.top + root.height + 1 == pane.top then
			table.remove(panes, i)
			return pane
		end
	end
	return nil
end

---Find and remove connected right pane from list
---@param root PaneTree
---@param panes RawPaneData[]
---@return RawPaneData?
function M.pop_connected_right(root, panes)
	for i, pane in ipairs(panes) do
		if root.top == pane.top and root.left + root.width + 1 == pane.left then
			table.remove(panes, i)
			return pane
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Tree Building
--------------------------------------------------------------------------------

---Convert RawPaneData to PaneTree node
---Note: domain is only included when is_spawnable is true (matches old behavior)
---@param pane RawPaneData
---@return PaneTree
local function to_tree_node(pane)
	return {
		left = pane.left,
		top = pane.top,
		width = pane.width,
		height = pane.height,
		cwd = pane.cwd,
		-- Only include domain for spawnable domains (preserves old behavior)
		domain = pane.is_spawnable and pane.domain or nil,
		text = pane.text,
		process = pane.process,
		is_active = pane.is_active,
		is_zoomed = pane.is_zoomed,
		alt_screen_active = pane.alt_screen_active,
	}
end

---Insert panes into tree structure recursively
---@param root PaneTree?
---@param panes RawPaneData[]
---@param warnings string[]
---@return PaneTree?
local function insert(root, panes, warnings)
	if root == nil then
		return nil
	end

	if #panes == 0 then
		return root
	end

	local right, bottom = {}, {}
	for _, pane in ipairs(panes) do
		if M.is_right(root, pane) then
			table.insert(right, pane)
		end
		if M.is_bottom(root, pane) then
			table.insert(bottom, pane)
		end
	end

	if #right > 0 then
		local right_child = M.pop_connected_right(root, right)
		if right_child then
			if not right_child.is_spawnable then
				warnings[#warnings + 1] = "Domain " .. (right_child.domain or "unknown") .. " is not spawnable"
			end
			root.right = insert(to_tree_node(right_child), right, warnings)
		end
	end

	if #bottom > 0 then
		local bottom_child = M.pop_connected_bottom(root, bottom)
		if bottom_child then
			if not bottom_child.is_spawnable then
				warnings[#warnings + 1] = "Domain " .. (bottom_child.domain or "unknown") .. " is not spawnable"
			end
			root.bottom = insert(to_tree_node(bottom_child), bottom, warnings)
		end
	end

	return root
end

---Build pane tree from raw extracted data (PURE)
---@param panes RawPaneData[]
---@return PaneTree?, string[]
function M.build(panes)
	if not panes or #panes == 0 then
		return nil, {}
	end

	local warnings = {}

	-- Sort panes by coordinate
	table.sort(panes, M.compare_by_coord)

	-- Remove first pane as root
	local root_pane = table.remove(panes, 1)
	if not root_pane then
		return nil, warnings
	end

	-- Warn if root is not spawnable
	if not root_pane.is_spawnable then
		warnings[#warnings + 1] = "Domain " .. (root_pane.domain or "unknown") .. " is not spawnable"
	end

	-- Convert to tree node and build tree
	local root = to_tree_node(root_pane)
	return insert(root, panes, warnings), warnings
end

--------------------------------------------------------------------------------
-- Tree Traversal
--------------------------------------------------------------------------------

---Maps over the pane tree
---@param pane_tree PaneTree?
---@param f fun(pane_tree: PaneTree): PaneTree
---@return PaneTree?
function M.map(pane_tree, f)
	if pane_tree == nil then
		return nil
	end

	pane_tree = f(pane_tree)
	if pane_tree.right then
		M.map(pane_tree.right, f)
	end
	if pane_tree.bottom then
		M.map(pane_tree.bottom, f)
	end

	return pane_tree
end

---Fold over the pane tree
---@generic T
---@param pane_tree PaneTree?
---@param acc T
---@param f fun(acc: T, pane_tree: PaneTree): T
---@return T
function M.fold(pane_tree, acc, f)
	if pane_tree == nil then
		return acc
	end

	acc = f(acc, pane_tree)
	if pane_tree.right then
		acc = M.fold(pane_tree.right, acc, f)
	end
	if pane_tree.bottom then
		acc = M.fold(pane_tree.bottom, acc, f)
	end

	return acc
end

--------------------------------------------------------------------------------
-- Split Planning
--------------------------------------------------------------------------------

---Plan splits needed to restore pane tree (PURE)
---@param tree PaneTree
---@param opts {relative?: boolean, absolute?: boolean}
---@return SplitCommand[]
function M.plan_splits(tree, opts)
	opts = opts or {}
	local commands = {}

	M.fold(tree, nil, function(_, node)
		if node.right then
			---@type SplitCommand
			local cmd = {
				direction = "Right",
				cwd = node.right.cwd,
				text = node.right.text,
				domain = node.right.domain,
			}
			if opts.relative then
				cmd.size = node.right.width / (node.width + node.right.width)
			elseif opts.absolute then
				cmd.size = node.right.width
			end
			commands[#commands + 1] = cmd
		end
		if node.bottom then
			---@type SplitCommand
			local cmd = {
				direction = "Bottom",
				cwd = node.bottom.cwd,
				text = node.bottom.text,
				domain = node.bottom.domain,
			}
			if opts.relative then
				cmd.size = node.bottom.height / (node.height + node.bottom.height)
			elseif opts.absolute then
				cmd.size = node.bottom.height
			end
			commands[#commands + 1] = cmd
		end
		return nil
	end)

	return commands
end

--------------------------------------------------------------------------------
-- Filename Sanitization
--------------------------------------------------------------------------------

---Sanitizes a string to be safe for use as a filename on all platforms.
---Pure function: no side effects, deterministic output.
---@param name string? The input string to sanitize
---@return string The sanitized filename-safe string
function M.sanitize_filename(name)
	if not name then
		return "_unnamed_"
	end

	local result = name
		:gsub("[/\\]", "+") -- path separators -> + (preserves structure)
		:gsub("%.%.", "_") -- .. -> _ (prevent path traversal confusion)
		:gsub('[<>:"|%?%*]', "_") -- Windows-invalid chars -> _
		:gsub("[\x00-\x1f\x7f]", "_") -- control characters -> _
		:gsub("[%. ]+$", "") -- trim trailing dots/spaces (Windows)

	return result ~= "" and result or "_unnamed_"
end

return M
