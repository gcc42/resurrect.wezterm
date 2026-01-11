-- Core Pure Functions Test Suite
--
-- Tests for pure functions in core/pane_tree.lua (no WezTerm dependencies).
-- These tests verify the functional core in isolation.
--
-- Note: End-to-end layout tests are in capture_spec.lua (full pipeline)

local core = require("resurrect.core.pane_tree")

--------------------------------------------------------------------------------
-- Test Fixtures
--------------------------------------------------------------------------------

---@param overrides table?
---@return RawPaneData
local function make_pane(overrides)
	local pane = {
		left = 0,
		top = 0,
		width = 160,
		height = 48,
		cwd = "/home",
		domain = "local",
		is_spawnable = true,
		text = "",
		is_active = false,
		is_zoomed = false,
		alt_screen_active = false,
	}
	if overrides then
		for k, v in pairs(overrides) do
			pane[k] = v
		end
	end
	return pane
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe("Core Pane Tree", function()
	---------------------------------------------------------------------------
	-- build() edge cases (layouts tested in capture_spec.lua)
	---------------------------------------------------------------------------

	describe("build", function()
		it("returns nil for empty or nil input", function()
			local tree1, warnings1 = core.build({})
			expect(tree1).to_not.exist()
			expect(#warnings1).to.equal(0)

			local tree2, warnings2 = core.build(nil)
			expect(tree2).to_not.exist()
			expect(#warnings2).to.equal(0)
		end)

		it("warns for non-spawnable domains", function()
			local panes = { make_pane({ domain = "SSH:dead", is_spawnable = false }) }
			local tree, warnings = core.build(panes)

			expect(tree).to.exist()
			expect(#warnings).to.equal(1)
			expect(warnings[1]).to.match("SSH:dead")
		end)
	end)

	---------------------------------------------------------------------------
	-- plan_splits() - unique function not tested elsewhere
	---------------------------------------------------------------------------

	describe("plan_splits", function()
		it("returns empty list for single pane", function()
			local tree = make_pane()
			expect(#core.plan_splits(tree, {})).to.equal(0)
		end)

		it("plans splits with correct direction and cwd", function()
			local tree = {
				left = 0,
				top = 0,
				width = 80,
				height = 24,
				cwd = "/left",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
				right = {
					left = 81,
					top = 0,
					width = 80,
					height = 24,
					cwd = "/right",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
				},
				bottom = {
					left = 0,
					top = 25,
					width = 80,
					height = 24,
					cwd = "/bottom",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
				},
			}
			local commands = core.plan_splits(tree, {})

			expect(#commands).to.equal(2)
			expect(commands[1].direction).to.equal("Right")
			expect(commands[1].cwd).to.equal("/right")
			expect(commands[2].direction).to.equal("Bottom")
			expect(commands[2].cwd).to.equal("/bottom")
		end)

		it("calculates relative and absolute sizes", function()
			local tree = {
				left = 0,
				top = 0,
				width = 80,
				height = 48,
				cwd = "/left",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
				right = {
					left = 81,
					top = 0,
					width = 80,
					height = 48,
					cwd = "/right",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
				},
			}

			local rel_cmds = core.plan_splits(tree, { relative = true })
			expect(rel_cmds[1].size).to.equal(0.5)

			local abs_cmds = core.plan_splits(tree, { absolute = true })
			expect(abs_cmds[1].size).to.equal(80)

			local no_size = core.plan_splits(tree, {})
			expect(no_size[1].size).to_not.exist()
		end)

		it("includes domain in split commands", function()
			local tree = {
				left = 0,
				top = 0,
				width = 80,
				height = 48,
				cwd = "/local",
				domain = "local",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
				right = {
					left = 81,
					top = 0,
					width = 80,
					height = 48,
					cwd = "/remote",
					domain = "SSH:server",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
				},
			}
			local commands = core.plan_splits(tree, {})
			expect(commands[1].domain).to.equal("SSH:server")
		end)
	end)

	---------------------------------------------------------------------------
	-- sanitize_filename() - pure filename sanitization
	---------------------------------------------------------------------------

	describe("sanitize_filename", function()
		it("passes through normal names unchanged", function()
			expect(core.sanitize_filename("myworkspace")).to.equal("myworkspace")
		end)

		it("converts path separators to plus", function()
			expect(core.sanitize_filename("/home/user/project")).to.equal("+home+user+project")
			expect(core.sanitize_filename("C:\\Users\\foo")).to.equal("C_+Users+foo")
		end)

		it("sanitizes unsafe characters", function()
			-- Path traversal
			expect(core.sanitize_filename("../../../etc"):match("%.%.")).to.equal(nil)
			-- Windows-invalid chars
			expect(core.sanitize_filename('file<>:"|?*name'):match('[<>:"|%?%*]')).to.equal(nil)
			-- Control characters
			expect(core.sanitize_filename("name\x00\tnull")).to.equal("name__null")
		end)

		it("returns _unnamed_ for nil or empty input", function()
			expect(core.sanitize_filename(nil)).to.equal("_unnamed_")
			expect(core.sanitize_filename("")).to.equal("_unnamed_")
		end)
	end)
end)
